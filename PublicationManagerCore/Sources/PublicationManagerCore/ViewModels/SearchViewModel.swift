//
//  SearchViewModel.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog
import SwiftUI

// MARK: - Classic Form State

/// Stores the state of the ADS Classic search form for persistence across navigation
public struct ClassicFormState {
    public var authors: String = ""
    public var objects: String = ""
    public var titleWords: String = ""
    public var titleLogic: QueryLogic = .and
    public var abstractWords: String = ""
    public var abstractLogic: QueryLogic = .and
    public var yearFrom: Int? = nil
    public var yearTo: Int? = nil
    public var database: ADSDatabase = .all
    public var refereedOnly: Bool = false
    public var articlesOnly: Bool = false

    public init() {}

    public mutating func clear() {
        authors = ""
        objects = ""
        titleWords = ""
        titleLogic = .and
        abstractWords = ""
        abstractLogic = .and
        yearFrom = nil
        yearTo = nil
        database = .all
        refereedOnly = false
        articlesOnly = false
    }

    public var isEmpty: Bool {
        SearchFormQueryBuilder.isClassicFormEmpty(
            authors: authors,
            objects: objects,
            titleWords: titleWords,
            abstractWords: abstractWords,
            yearFrom: yearFrom,
            yearTo: yearTo
        )
    }
}

// MARK: - Paper Form State

/// Stores the state of the ADS Paper search form for persistence across navigation
public struct PaperFormState {
    public var bibcode: String = ""
    public var doi: String = ""
    public var arxivID: String = ""

    public init() {}

    public mutating func clear() {
        bibcode = ""
        doi = ""
        arxivID = ""
    }

    public var isEmpty: Bool {
        SearchFormQueryBuilder.isPaperFormEmpty(
            bibcode: bibcode,
            doi: doi,
            arxivID: arxivID
        )
    }
}

// MARK: - Modern Form State

/// Stores the state of the ADS Modern search form for persistence across navigation
public struct ModernFormState {
    public var searchText: String = ""

    public init() {}

    public mutating func clear() {
        searchText = ""
    }

    public var isEmpty: Bool {
        searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Search View Model

/// View model for searching across publication sources.
///
/// ADR-016: Search results are auto-imported to the active library's "Last Search"
/// collection. This provides immediate persistence and full editing capabilities
/// for all search results.
@MainActor
@Observable
public final class SearchViewModel {

    // MARK: - Published State

    public private(set) var isSearching = false
    public private(set) var error: Error?

    public var query = ""
    public var selectedSourceIDs: Set<String> = []
    public var selectedPublicationIDs: Set<UUID> = []

    // MARK: - Form State (persisted across navigation)

    /// Classic form state - persists when navigating away and back
    public var classicFormState = ClassicFormState()

    /// Paper form state - persists when navigating away and back
    public var paperFormState = PaperFormState()

    /// Modern form state - persists when navigating away and back
    public var modernFormState = ModernFormState()

    // MARK: - Dependencies

    public let sourceManager: SourceManager
    private let deduplicationService: DeduplicationService
    public let repository: PublicationRepository
    private weak var libraryManager: LibraryManager?

    // MARK: - Initialization

    public init(
        sourceManager: SourceManager = SourceManager(),
        deduplicationService: DeduplicationService = DeduplicationService(),
        repository: PublicationRepository = PublicationRepository(),
        libraryManager: LibraryManager? = nil
    ) {
        self.sourceManager = sourceManager
        self.deduplicationService = deduplicationService
        self.repository = repository
        self.libraryManager = libraryManager
    }

    /// Set the library manager (called from view layer after environment injection)
    public func setLibraryManager(_ manager: LibraryManager) {
        self.libraryManager = manager
    }

    // MARK: - Last Search Collection

    /// Publications from the Last Search collection (excludes deleted objects)
    public var publications: [CDPublication] {
        guard let collection = libraryManager?.activeLibrary?.lastSearchCollection else {
            return []
        }
        // Filter out deleted publications (isDeleted or managedObjectContext nil)
        return (collection.publications ?? [])
            .filter { !$0.isDeleted && $0.managedObjectContext != nil }
            .sorted { ($0.dateAdded) > ($1.dateAdded) }
    }

    // MARK: - Available Sources

    public var availableSources: [SourceMetadata] {
        get async {
            await sourceManager.availableSources
        }
    }

    // MARK: - Search (ADR-016: Auto-Import)

    /// Execute search and auto-import results to Last Search collection.
    ///
    /// This method:
    /// 1. Clears the previous Last Search results
    /// 2. Executes the search query
    /// 3. Deduplicates against existing library publications
    /// 4. Creates new CDPublication entities for new results
    /// 5. Adds all results to the Last Search collection
    public func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }

        guard let manager = libraryManager else {
            Logger.viewModels.errorCapture("No library manager available for search", category: "search")
            return
        }

        guard let collection = manager.getOrCreateLastSearchCollection() else {
            Logger.viewModels.errorCapture("Could not create Last Search collection", category: "search")
            return
        }

        Logger.viewModels.entering()
        defer { Logger.viewModels.exiting() }

        isSearching = true
        error = nil

        // Clear previous Last Search results
        manager.clearLastSearchCollection()

        do {
            let sourceIDs = Array(selectedSourceIDs)
            let options = SearchOptions(
                maxResults: 100,
                sortOrder: .relevance,
                sourceIDs: selectedSourceIDs.isEmpty ? nil : sourceIDs
            )

            let rawResults = try await sourceManager.search(query: query, options: options)

            // Deduplicate results
            let deduped = await deduplicationService.deduplicate(rawResults)

            Logger.viewModels.infoCapture("Search returned \(deduped.count) deduplicated results", category: "search")

            // Auto-import results to Last Search collection
            var importedCount = 0
            var existingCount = 0

            for result in deduped {
                // Check for existing publication by identifiers
                if let existing = await repository.findByIdentifiers(result.primary) {
                    // Add existing publication to Last Search collection
                    await repository.addToCollection(existing, collection: collection)
                    existingCount += 1
                } else {
                    // Create new publication and add to collection
                    // Use bestAbstract to merge abstracts from alternates (e.g., ADS has abstract but Crossref doesn't)
                    let publication = await repository.createFromSearchResult(
                        result.primary,
                        abstractOverride: result.bestAbstract
                    )
                    await repository.addToCollection(publication, collection: collection)
                    importedCount += 1
                }
            }

            Logger.viewModels.infoCapture("Search: imported \(importedCount) new, linked \(existingCount) existing", category: "search")

        } catch {
            self.error = error
            Logger.viewModels.errorCapture("Search failed: \(error.localizedDescription)", category: "search")
        }

        isSearching = false
    }

    // MARK: - Selection

    public func toggleSelection(_ publication: CDPublication) {
        if selectedPublicationIDs.contains(publication.id) {
            selectedPublicationIDs.remove(publication.id)
        } else {
            selectedPublicationIDs.insert(publication.id)
        }
    }

    public func selectAll() {
        selectedPublicationIDs = Set(publications.map { $0.id })
    }

    public func clearSelection() {
        selectedPublicationIDs.removeAll()
    }

    // MARK: - Source Selection

    public func toggleSource(_ sourceID: String) {
        if selectedSourceIDs.contains(sourceID) {
            selectedSourceIDs.remove(sourceID)
        } else {
            selectedSourceIDs.insert(sourceID)
        }
    }

    public func selectAllSources() async {
        selectedSourceIDs = Set(await availableSources.map { $0.id })
    }

    public func clearSourceSelection() {
        selectedSourceIDs.removeAll()
    }
}
