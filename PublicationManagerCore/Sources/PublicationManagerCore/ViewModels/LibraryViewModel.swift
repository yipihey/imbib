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

    public private(set) var publications: [CDPublication] = []
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

    // MARK: - Dependencies

    private let repository: PublicationRepository

    // MARK: - Initialization

    public init(repository: PublicationRepository = PublicationRepository()) {
        self.repository = repository
    }

    // MARK: - Loading

    public func loadPublications() async {
        Logger.viewModels.entering()
        defer { Logger.viewModels.exiting() }

        isLoading = true
        error = nil

        do {
            let sortKey = sortOrder.sortKey
            publications = await repository.fetchAll(sortedBy: sortKey, ascending: sortAscending)
            Logger.viewModels.info("Loaded \(self.publications.count) publications")
        }

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
                isLoading = false
            }
        }
    }

    // MARK: - Import

    public func importBibTeX(from url: URL) async throws -> Int {
        Logger.viewModels.info("Importing BibTeX from \(url.lastPathComponent)")

        let content = try String(contentsOf: url, encoding: .utf8)
        let parser = BibTeXParser()
        let entries = try parser.parseEntries(content)

        let imported = await repository.importEntries(entries)
        await loadPublications()

        Logger.viewModels.info("Imported \(imported) entries")
        return imported
    }

    public func importEntry(_ entry: BibTeXEntry) async {
        Logger.viewModels.info("Importing entry: \(entry.citeKey)")

        await repository.create(from: entry)
        await loadPublications()
    }

    // MARK: - Delete

    public func deleteSelected() async {
        let toDelete = publications.filter { selectedPublications.contains($0.id) }
        guard !toDelete.isEmpty else { return }

        Logger.viewModels.info("Deleting \(toDelete.count) publications")

        await repository.delete(toDelete)
        selectedPublications.removeAll()
        await loadPublications()
    }

    public func delete(_ publication: CDPublication) async {
        Logger.viewModels.info("Deleting: \(publication.citeKey)")

        await repository.delete(publication)
        selectedPublications.remove(publication.id)
        await loadPublications()
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
