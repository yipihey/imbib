//
//  LibraryViewModel.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog
import SwiftUI

// MARK: - Library View Model

/// View model for the main library view.
@MainActor
@Observable
public final class LibraryViewModel {

    // MARK: - Published State

    /// Raw Core Data publications
    public private(set) var publications: [CDPublication] = []

    /// LocalPaper wrappers for unified view layer
    public private(set) var papers: [LocalPaper] = []

    public private(set) var isLoading = false
    public private(set) var error: Error?

    public var searchQuery = "" {
        didSet { performSearch() }
    }

    public var sortOrder: LibrarySortOrder = .dateAdded {
        didSet { Task { await loadPublications() } }
    }

    public var sortAscending = false {
        didSet { Task { await loadPublications() } }
    }

    public var selectedPublications: Set<UUID> = []

    // MARK: - Library Identity

    /// Unique identifier for this library (used by LocalPaper)
    public let libraryID: UUID

    // MARK: - Dependencies

    private let repository: PublicationRepository

    // MARK: - Initialization

    public init(repository: PublicationRepository = PublicationRepository(), libraryID: UUID = UUID()) {
        self.repository = repository
        self.libraryID = libraryID
    }

    // MARK: - Loading

    public func loadPublications() async {
        isLoading = true
        error = nil

        let sortKey = sortOrder.sortKey
        publications = await repository.fetchAll(sortedBy: sortKey, ascending: sortAscending)

        // Create LocalPaper wrappers for unified view layer
        papers = LocalPaper.from(publications: publications, libraryID: libraryID)

        Logger.viewModels.infoCapture("Loaded \(self.publications.count) publications", category: "library")

        isLoading = false
    }

    // MARK: - Search

    private func performSearch() {
        Task {
            if searchQuery.isEmpty {
                await loadPublications()
            } else {
                isLoading = true
                publications = await repository.search(query: searchQuery)
                papers = LocalPaper.from(publications: publications, libraryID: libraryID)
                isLoading = false
            }
        }
    }

    // MARK: - Import

    public func importBibTeX(from url: URL) async throws -> Int {
        Logger.viewModels.infoCapture("Importing BibTeX from \(url.lastPathComponent)", category: "import")

        let content = try String(contentsOf: url, encoding: .utf8)
        let parser = BibTeXParser()

        Logger.viewModels.infoCapture("Parsing BibTeX file...", category: "import")
        let entries = try parser.parseEntries(content)
        Logger.viewModels.infoCapture("Parsed \(entries.count) entries from file", category: "import")

        let imported = await repository.importEntries(entries)
        await loadPublications()

        Logger.viewModels.infoCapture("Successfully imported \(imported) entries", category: "import")
        return imported
    }

    public func importEntry(_ entry: BibTeXEntry) async {
        Logger.viewModels.infoCapture("Importing entry: \(entry.citeKey)", category: "import")

        await repository.create(from: entry)
        await loadPublications()
    }

    // MARK: - Delete

    public func deleteSelected() async {
        let toDelete = publications.filter { selectedPublications.contains($0.id) }
        guard !toDelete.isEmpty else { return }

        Logger.viewModels.infoCapture("Deleting \(toDelete.count) publications", category: "library")

        await repository.delete(toDelete)
        selectedPublications.removeAll()
        await loadPublications()
    }

    public func delete(_ publication: CDPublication) async {
        // Capture values before deletion since accessing deleted object crashes
        let citeKey = publication.citeKey
        let publicationID = publication.id

        Logger.viewModels.infoCapture("Deleting: \(citeKey)", category: "library")

        await repository.delete(publication)
        selectedPublications.remove(publicationID)
        await loadPublications()
    }

    public func delete(ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }

        // Find publications to delete - capture them in a single pass
        let toDelete = publications.filter { ids.contains($0.id) }
        guard !toDelete.isEmpty else { return }

        Logger.viewModels.infoCapture("Deleting \(toDelete.count) publications", category: "library")

        // Remove from selection first
        for id in ids {
            selectedPublications.remove(id)
        }

        // Batch delete all at once (doesn't call loadPublications between deletions)
        await repository.delete(toDelete)
        await loadPublications()
    }

    // MARK: - Update

    public func updateField(_ publication: CDPublication, field: String, value: String?) async {
        await repository.updateField(publication, field: field, value: value)
    }

    // MARK: - Export

    public func exportAll() async -> String {
        await repository.exportAll()
    }

    public func exportSelected() async -> String {
        let toExport = publications.filter { selectedPublications.contains($0.id) }
        return await repository.export(toExport)
    }

    // MARK: - Selection

    public func selectAll() {
        selectedPublications = Set(publications.map { $0.id })
    }

    public func clearSelection() {
        selectedPublications.removeAll()
    }

    public func toggleSelection(_ publication: CDPublication) {
        if selectedPublications.contains(publication.id) {
            selectedPublications.remove(publication.id)
        } else {
            selectedPublications.insert(publication.id)
        }
    }
}

// MARK: - Library Sort Order

public enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case dateAdded
    case dateModified
    case title
    case year
    case citeKey

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dateAdded: return "Date Added"
        case .dateModified: return "Date Modified"
        case .title: return "Title"
        case .year: return "Year"
        case .citeKey: return "Cite Key"
        }
    }

    var sortKey: String {
        switch self {
        case .dateAdded: return "dateAdded"
        case .dateModified: return "dateModified"
        case .title: return "title"
        case .year: return "year"
        case .citeKey: return "citeKey"
        }
    }
}
