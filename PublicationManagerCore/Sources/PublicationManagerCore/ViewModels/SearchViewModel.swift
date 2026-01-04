//
//  SearchViewModel.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog
import SwiftUI

// MARK: - Search View Model

/// View model for searching across publication sources.
@MainActor
@Observable
public final class SearchViewModel {

    // MARK: - Published State

    /// Raw deduplicated results from search
    public private(set) var results: [DeduplicatedResult] = []

    /// OnlinePaper wrappers for unified view layer
    public private(set) var papers: [OnlinePaper] = []

    public private(set) var isSearching = false
    public private(set) var error: Error?

    public var query = ""
    public var selectedSourceIDs: Set<String> = []
    public var selectedResults: Set<String> = []

    // MARK: - Dependencies

    private let sourceManager: SourceManager
    private let deduplicationService: DeduplicationService
    private let repository: PublicationRepository

    // MARK: - Initialization

    public init(
        sourceManager: SourceManager = SourceManager(),
        deduplicationService: DeduplicationService = DeduplicationService(),
        repository: PublicationRepository = PublicationRepository()
    ) {
        self.sourceManager = sourceManager
        self.deduplicationService = deduplicationService
        self.repository = repository
    }

    // MARK: - Available Sources

    public var availableSources: [SourceMetadata] {
        get async {
            await sourceManager.availableSources
        }
    }

    // MARK: - Search

    public func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            papers = []
            return
        }

        Logger.viewModels.entering()
        defer { Logger.viewModels.exiting() }

        // Check session cache first
        let sourceIDs = Array(selectedSourceIDs)
        if let cached = await SessionCache.shared.getCachedResults(for: query, sourceIDs: sourceIDs) {
            Logger.viewModels.infoCapture("Using cached results for: \(query)", category: "search")
            results = await deduplicationService.deduplicate(cached)
            papers = OnlinePaper.from(results: results)
            return
        }

        isSearching = true
        error = nil
        results = []
        papers = []

        do {
            let options = SearchOptions(
                maxResults: 100,
                sortOrder: .relevance,
                sourceIDs: selectedSourceIDs.isEmpty ? nil : sourceIDs
            )

            let rawResults = try await sourceManager.search(query: query, options: options)

            // Cache the raw results
            await SessionCache.shared.cacheSearchResults(rawResults, for: query, sourceIDs: sourceIDs)

            results = await deduplicationService.deduplicate(rawResults)
            papers = OnlinePaper.from(results: results)

            Logger.viewModels.infoCapture("Search returned \(self.results.count) deduplicated results", category: "search")
        } catch {
            self.error = error
            Logger.viewModels.errorCapture("Search failed: \(error.localizedDescription)", category: "search")
        }

        isSearching = false
    }

    // MARK: - Import

    public func importResult(_ result: DeduplicatedResult) async throws {
        Logger.viewModels.infoCapture("Importing: \(result.primary.title)", category: "import")

        // Get any pending metadata from session cache
        let pendingMetadata = await SessionCache.shared.getMetadata(for: result.id)

        let entry = try await sourceManager.fetchBibTeX(for: result.primary)
        let publication = await repository.create(from: entry)

        // Apply pending metadata if any
        if let metadata = pendingMetadata, !metadata.isEmpty {
            // Apply custom cite key
            if let customKey = metadata.customCiteKey {
                await repository.updateField(publication, field: "citeKey", value: customKey)
            }
            // Apply notes
            if !metadata.notes.isEmpty {
                await repository.updateField(publication, field: "notes", value: metadata.notes)
            }
            // Clear the pending metadata
            await SessionCache.shared.clearMetadata(for: result.id)
        }

        // Invalidate the library lookup cache so the indicator updates
        await DefaultLibraryLookupService.shared.invalidateCache()
    }

    public func importPaper(_ paper: OnlinePaper) async throws {
        guard let result = results.first(where: { $0.id == paper.id }) else {
            throw SearchViewModelError.paperNotFound
        }
        try await importResult(result)
    }

    public func importSelected() async throws -> Int {
        Logger.viewModels.infoCapture("Importing \(self.selectedResults.count) results", category: "import")

        var imported = 0

        for resultID in selectedResults {
            guard let result = results.first(where: { $0.id == resultID }) else { continue }

            do {
                try await importResult(result)
                imported += 1
            } catch {
                Logger.viewModels.errorCapture("Failed to import \(result.primary.title): \(error.localizedDescription)", category: "import")
            }
        }

        selectedResults.removeAll()
        return imported
    }

    // MARK: - Pending Metadata

    /// Set temporary metadata for a paper before import
    public func setPendingMetadata(for paperID: String, tags: Set<String>? = nil, notes: String? = nil, customCiteKey: String? = nil) async {
        await SessionCache.shared.updateMetadata(for: paperID, tags: tags, notes: notes, customCiteKey: customCiteKey)
    }

    /// Get pending metadata for a paper
    public func getPendingMetadata(for paperID: String) async -> PendingPaperMetadata? {
        await SessionCache.shared.getMetadata(for: paperID)
    }

    // MARK: - Selection

    public func toggleSelection(_ result: DeduplicatedResult) {
        if selectedResults.contains(result.id) {
            selectedResults.remove(result.id)
        } else {
            selectedResults.insert(result.id)
        }
    }

    public func selectAll() {
        selectedResults = Set(results.map { $0.id })
    }

    public func clearSelection() {
        selectedResults.removeAll()
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

// MARK: - Search View Model Error

public enum SearchViewModelError: LocalizedError {
    case paperNotFound

    public var errorDescription: String? {
        switch self {
        case .paperNotFound:
            return "Paper not found in search results"
        }
    }
}
