//
//  LibraryViewModel.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import CoreData
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

    /// Fast lookup by ID (populated during loadPublications)
    public private(set) var publicationsByID: [UUID: CDPublication] = [:]

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

        // Build ID lookup cache for O(1) access
        publicationsByID = Dictionary(uniqueKeysWithValues: publications.map { ($0.id, $0) })

        // Create LocalPaper wrappers for unified view layer
        papers = LocalPaper.from(publications: publications, libraryID: libraryID)

        Logger.viewModels.infoCapture("Loaded \(self.publications.count) publications", category: "library")

        isLoading = false
    }

    // MARK: - Lookup

    /// Fast O(1) lookup of publication by ID.
    ///
    /// First checks the local cache (for library publications), then falls back to
    /// Core Data fetch (for smart search results, Inbox feeds, etc.).
    ///
    /// Returns nil if no publication with that ID exists or if the object was deleted.
    public func publication(for id: UUID) -> CDPublication? {
        // Fast path: check local cache first
        if let pub = publicationsByID[id],
           !pub.isDeleted,
           pub.managedObjectContext != nil {
            return pub
        }

        // Slow path: fetch from Core Data (for smart searches, Inbox feeds, etc.)
        // Guard against Core Data not being fully initialized
        let context = PersistenceController.shared.viewContext
        guard let entity = NSEntityDescription.entity(forEntityName: "Publication", in: context) else {
            // Core Data not fully loaded yet, skip fetch
            return nil
        }

        let request = NSFetchRequest<CDPublication>()
        request.entity = entity
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        do {
            let results = try context.fetch(request)
            if let pub = results.first,
               !pub.isDeleted,
               pub.managedObjectContext != nil {
                return pub
            }
        } catch {
            Logger.viewModels.error("Failed to fetch publication \(id): \(error.localizedDescription)")
        }

        return nil
    }

    // MARK: - Search

    private func performSearch() {
        Task {
            if searchQuery.isEmpty {
                await loadPublications()
            } else {
                isLoading = true
                publications = await repository.search(query: searchQuery)
                publicationsByID = Dictionary(uniqueKeysWithValues: publications.map { ($0.id, $0) })
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

        // Queue newly imported papers for enrichment
        await queueNewlyImportedForEnrichment()

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

        // Queue newly imported papers for enrichment
        await queueNewlyImportedForEnrichment()

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

        Logger.viewModels.infoCapture("Deleting \(ids.count) publications by ID", category: "library")

        // 1. Remove from selection first
        for id in ids {
            selectedPublications.remove(id)
        }

        // 2. Remove from local publications array (if present)
        // This prevents SwiftUI from trying to render deleted objects during re-render
        publications.removeAll { ids.contains($0.id) }

        // 3. Give SwiftUI a moment to process the state change before Core Data deletion
        // This helps prevent race conditions where SwiftUI tries to render deleted objects
        try? await Task.sleep(for: .milliseconds(50))

        // 4. Delete from Core Data by fetching fresh objects by ID
        // This ensures deletion works even if publications came from a different source
        // (e.g., library.publications vs viewModel.publications)
        await repository.deleteByIDs(ids)

        // 5. Reload to sync with database
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
        // Post notification with publication ID for efficient single-row cache update
        // (O(1) update instead of O(n) full rebuild)
        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name("readStatusDidChange"), object: publication.id)
        }
    }

    /// Mark a publication as unread
    public func markAsUnread(_ publication: CDPublication) async {
        await repository.markAsUnread(publication)
        // Post notification with publication ID for efficient single-row cache update
        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name("readStatusDidChange"), object: publication.id)
        }
    }

    /// Toggle read/unread status
    public func toggleReadStatus(_ publication: CDPublication) async {
        await repository.toggleReadStatus(publication)
        // Post notification with publication ID for efficient single-row cache update
        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name("readStatusDidChange"), object: publication.id)
        }
    }

    /// Mark all selected publications as read
    public func markSelectedAsRead() async {
        let toMark = publications.filter { selectedPublications.contains($0.id) }
        await repository.markAllAsRead(toMark)
        await loadPublications()
    }

    /// Apple Mail-style smart toggle for multiple publications.
    /// - If ANY are unread → mark ALL as read
    /// - If ALL are read → mark ALL as unread
    public func smartToggleReadStatus(_ publicationIDs: Set<UUID>) async {
        let selected = publications.filter { publicationIDs.contains($0.id) }
        guard !selected.isEmpty else { return }

        // Check if any are unread
        let anyUnread = selected.contains { !$0.isRead }

        if anyUnread {
            // Make all read
            for pub in selected where !pub.isRead {
                await repository.markAsRead(pub)
            }
        } else {
            // All are read, make all unread
            for pub in selected {
                await repository.markAsUnread(pub)
            }
        }

        // Post notification for each changed publication
        await MainActor.run {
            for pub in selected {
                NotificationCenter.default.post(name: Notification.Name("readStatusDidChange"), object: pub.id)
            }
        }
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
        Clipboard.shared.setString(bibtex)

        Logger.viewModels.infoCapture("Copied \(toCopy.count) publications to clipboard", category: "clipboard")
    }

    /// Copy specific publications by IDs to clipboard as BibTeX
    public func copyToClipboard(_ ids: Set<UUID>) async {
        let toCopy = publications.filter { ids.contains($0.id) }
        guard !toCopy.isEmpty else { return }

        let bibtex = await repository.export(toCopy)
        Clipboard.shared.setString(bibtex)

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
        guard let bibtex = Clipboard.shared.getString() else {
            throw ImportError.noBibTeXEntry
        }

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

    // MARK: - Library and Collection Operations

    /// Add publications by IDs to another library (publications can belong to multiple libraries)
    public func addToLibrary(_ ids: Set<UUID>, library: CDLibrary) async {
        let toAdd = publications.filter { ids.contains($0.id) }
        guard !toAdd.isEmpty else { return }

        await repository.addToLibrary(toAdd, library: library)

        // Publications stay in current library, just also added to target library
        // No need to remove from selection or reload
        Logger.viewModels.infoCapture("Added \(toAdd.count) publications to \(library.displayName)", category: "library")
    }

    /// Add publications by IDs to a collection
    public func addToCollection(_ ids: Set<UUID>, collection: CDCollection) async {
        let toAdd = publications.filter { ids.contains($0.id) }
        guard !toAdd.isEmpty else { return }

        await repository.addPublications(toAdd, to: collection)
        Logger.viewModels.infoCapture("Added \(toAdd.count) publications to \(collection.name)", category: "library")
    }

    /// Remove publications from all collections (return to "All Publications")
    public func removeFromAllCollections(_ ids: Set<UUID>) async {
        let toRemove = publications.filter { ids.contains($0.id) }
        guard !toRemove.isEmpty else { return }

        await repository.removeFromAllCollections(toRemove)
        Logger.viewModels.infoCapture("Removed \(toRemove.count) publications from all collections", category: "library")
    }

    /// Remove publications from a specific library
    public func removeFromLibrary(_ ids: Set<UUID>, library: CDLibrary) async {
        let toRemove = publications.filter { ids.contains($0.id) }
        guard !toRemove.isEmpty else { return }

        await repository.removeFromLibrary(toRemove, library: library)
        Logger.viewModels.infoCapture("Removed \(toRemove.count) publications from \(library.displayName)", category: "library")
    }

    // MARK: - Smart Collections

    /// Execute a smart collection query and return matching publications.
    public func executeSmartCollection(_ collection: CDCollection) async -> [CDPublication] {
        await repository.executeSmartCollection(collection)
    }

    // MARK: - Enrichment

    /// Queue recently added publications for background enrichment.
    ///
    /// This finds publications that haven't been enriched and queues them
    /// for background processing to fetch PDF URLs, citation counts, etc.
    private func queueNewlyImportedForEnrichment() async {
        let unenriched = publications.filter { pub in
            pub.hasEnrichmentIdentifiers && !pub.hasBeenEnriched
        }

        guard !unenriched.isEmpty else { return }

        Logger.viewModels.infoCapture(
            "Queueing \(unenriched.count) papers for enrichment",
            category: "enrichment"
        )

        await EnrichmentCoordinator.shared.queueForEnrichment(
            unenriched,
            priority: .libraryPaper
        )
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
