//
//  LibraryViewModel.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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

    public let repository: PublicationRepository

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

    /// Import a bibliography file (BibTeX or RIS) based on file extension.
    ///
    /// - Parameter url: URL to the .bib or .ris file
    /// - Returns: Number of entries imported
    public func importFile(from url: URL) async throws -> Int {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "bib", "bibtex":
            return try await importBibTeX(from: url)
        case "ris":
            return try await importRIS(from: url)
        default:
            throw ImportError.unsupportedFormat(ext)
        }
    }

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

    public func importRIS(from url: URL) async throws -> Int {
        Logger.viewModels.infoCapture("Importing RIS from \(url.lastPathComponent)", category: "import")

        let content = try String(contentsOf: url, encoding: .utf8)
        let parser = RISParser()

        Logger.viewModels.infoCapture("Parsing RIS file...", category: "import")
        let entries = try parser.parse(content)
        Logger.viewModels.infoCapture("Parsed \(entries.count) entries from file", category: "import")

        let imported = await repository.importRISEntries(entries)
        await loadPublications()

        Logger.viewModels.infoCapture("Successfully imported \(imported) RIS entries", category: "import")
        return imported
    }

    public func importEntry(_ entry: BibTeXEntry) async {
        Logger.viewModels.infoCapture("Importing entry: \(entry.citeKey)", category: "import")

        await repository.create(from: entry)
        await loadPublications()
    }

    /// Import a PDF file and attach it to a publication.
    public func importPDF(from url: URL, for publication: CDPublication, in library: CDLibrary? = nil) async throws {
        Logger.viewModels.infoCapture("Importing PDF for: \(publication.citeKey)", category: "import")

        try PDFManager.shared.importPDF(from: url, for: publication, in: library)
        await loadPublications()
    }

    // Note: importOnlinePaper and importPaperLocally have been removed as part of ADR-016.
    // Search results are now auto-imported to Last Search collection or smart search result collections.
    // Use SearchViewModel.search() or SmartSearchProvider.refresh() instead.

    /// Import a paper from a BibTeX entry directly.
    ///
    /// Use this when you have already fetched/parsed the BibTeX entry.
    @discardableResult
    public func importBibTeXEntry(_ entry: BibTeXEntry) async -> CDPublication {
        Logger.viewModels.infoCapture("Importing BibTeX entry: \(entry.citeKey)", category: "import")

        let publication = await repository.create(from: entry)
        await loadPublications()

        // Invalidate library lookup cache
        await DefaultLibraryLookupService.shared.invalidateCache()

        return publication
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

    /// Update a publication from an edited BibTeX entry.
    ///
    /// This replaces all fields in the publication with values from the entry.
    public func updateFromBibTeX(_ publication: CDPublication, entry: BibTeXEntry) async {
        Logger.viewModels.infoCapture("Updating publication from BibTeX: \(entry.citeKey)", category: "update")

        await repository.update(publication, with: entry)
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

    // MARK: - Read Status (Apple Mail Styling)

    /// Mark a publication as read
    public func markAsRead(_ publication: CDPublication) async {
        await repository.markAsRead(publication)
        // No reload needed - CDPublication is @ObservedObject so row updates automatically
    }

    /// Mark a publication as unread
    public func markAsUnread(_ publication: CDPublication) async {
        await repository.markAsUnread(publication)
        // No reload needed - CDPublication is @ObservedObject so row updates automatically
    }

    /// Toggle read/unread status
    public func toggleReadStatus(_ publication: CDPublication) async {
        await repository.toggleReadStatus(publication)
        // Post notification so sidebar can update unread count
        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name("readStatusDidChange"), object: nil)
        }
        // No reload needed - CDPublication is @ObservedObject so row updates automatically
    }

    /// Mark all selected publications as read
    public func markSelectedAsRead() async {
        let toMark = publications.filter { selectedPublications.contains($0.id) }
        await repository.markAllAsRead(toMark)
        await loadPublications()
    }

    /// Get count of unread publications
    public func unreadCount() async -> Int {
        await repository.unreadCount()
    }

    // MARK: - Clipboard Operations

    /// Copy selected publications to clipboard as BibTeX
    public func copySelectedToClipboard() async {
        let toCopy = publications.filter { selectedPublications.contains($0.id) }
        guard !toCopy.isEmpty else { return }

        let bibtex = await repository.export(toCopy)

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bibtex, forType: .string)
        #else
        UIPasteboard.general.string = bibtex
        #endif

        Logger.viewModels.infoCapture("Copied \(toCopy.count) publications to clipboard", category: "clipboard")
    }

    /// Copy specific publications by IDs to clipboard as BibTeX
    public func copyToClipboard(_ ids: Set<UUID>) async {
        let toCopy = publications.filter { ids.contains($0.id) }
        guard !toCopy.isEmpty else { return }

        let bibtex = await repository.export(toCopy)

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bibtex, forType: .string)
        #else
        UIPasteboard.general.string = bibtex
        #endif

        Logger.viewModels.infoCapture("Copied \(toCopy.count) publications to clipboard", category: "clipboard")
    }

    /// Cut selected publications (copy to clipboard, then delete)
    public func cutSelectedToClipboard() async {
        await copySelectedToClipboard()
        await deleteSelected()
        Logger.viewModels.infoCapture("Cut publications to clipboard", category: "clipboard")
    }

    /// Cut specific publications by IDs (copy to clipboard, then delete)
    public func cutToClipboard(_ ids: Set<UUID>) async {
        await copyToClipboard(ids)
        await delete(ids: ids)
        Logger.viewModels.infoCapture("Cut publications to clipboard", category: "clipboard")
    }

    /// Paste publications from clipboard (import BibTeX)
    @discardableResult
    public func pasteFromClipboard() async throws -> Int {
        #if os(macOS)
        guard let bibtex = NSPasteboard.general.string(forType: .string) else {
            throw ImportError.noBibTeXEntry
        }
        #else
        guard let bibtex = UIPasteboard.general.string else {
            throw ImportError.noBibTeXEntry
        }
        #endif

        let parser = BibTeXParser()
        let entries = try parser.parseEntries(bibtex)
        guard !entries.isEmpty else {
            throw ImportError.noBibTeXEntry
        }

        let imported = await repository.importEntries(entries)
        await loadPublications()

        Logger.viewModels.infoCapture("Pasted \(imported) publications from clipboard", category: "clipboard")
        return imported
    }

    // MARK: - Move Operations

    /// Move publications by IDs to a different library
    public func moveToLibrary(_ ids: Set<UUID>, library: CDLibrary) async {
        let toMove = publications.filter { ids.contains($0.id) }
        guard !toMove.isEmpty else { return }

        await repository.moveToLibrary(toMove, library: library)

        // Remove from selection if they were selected
        for id in ids {
            selectedPublications.remove(id)
        }

        await loadPublications()
        Logger.viewModels.infoCapture("Moved \(toMove.count) publications to \(library.displayName)", category: "library")
    }

    /// Add publications by IDs to a collection
    public func addToCollection(_ ids: Set<UUID>, collection: CDCollection) async {
        let toAdd = publications.filter { ids.contains($0.id) }
        guard !toAdd.isEmpty else { return }

        await repository.addPublications(toAdd, to: collection)
        Logger.viewModels.infoCapture("Added \(toAdd.count) publications to \(collection.name)", category: "library")
    }
}

// MARK: - Library Sort Order

public enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case dateAdded
    case dateModified
    case title
    case year
    case citeKey
    case citationCount

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dateAdded: return "Date Added"
        case .dateModified: return "Date Modified"
        case .title: return "Title"
        case .year: return "Year"
        case .citeKey: return "Cite Key"
        case .citationCount: return "Citation Count"
        }
    }

    var sortKey: String {
        switch self {
        case .dateAdded: return "dateAdded"
        case .dateModified: return "dateModified"
        case .title: return "title"
        case .year: return "year"
        case .citeKey: return "citeKey"
        case .citationCount: return "citationCount"
        }
    }
}

// MARK: - Import Error

public enum ImportError: LocalizedError, Sendable {
    case noBibTeXEntry
    case fileNotFound(URL)
    case invalidBibTeX(String)
    case unsupportedFormat(String)
    case parseError(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .noBibTeXEntry:
            return "No BibTeX entry found in the fetched data"
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .invalidBibTeX(let reason):
            return "Invalid BibTeX: \(reason)"
        case .unsupportedFormat(let ext):
            return "Unsupported file format: .\(ext)"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .cancelled:
            return "Import cancelled"
        }
    }
}
