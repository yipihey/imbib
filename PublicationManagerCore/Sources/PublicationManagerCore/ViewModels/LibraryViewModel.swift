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

    /// Import a paper from online search with optional PDF.
    ///
    /// This imports the paper's BibTeX and optionally downloads and attaches the PDF.
    public func importOnlinePaper(
        _ paper: OnlinePaper,
        downloadPDF: Bool = true,
        in library: CDLibrary? = nil
    ) async throws -> CDPublication {
        Logger.viewModels.infoCapture("Importing online paper: \(paper.title)", category: "import")

        // Fetch BibTeX
        let bibtex = try await paper.bibtex()
        let parser = BibTeXParser()
        let entries = try parser.parseEntries(bibtex)

        guard let entry = entries.first else {
            throw ImportError.noBibTeXEntry
        }

        // Create publication
        let publication = await repository.create(from: entry)

        // Apply pending metadata if any
        if let metadata = await SessionCache.shared.getMetadata(for: paper.id) {
            if let customKey = metadata.customCiteKey {
                await repository.updateField(publication, field: "citeKey", value: customKey)
            }
            if !metadata.notes.isEmpty {
                await repository.updateField(publication, field: "notes", value: metadata.notes)
            }
            // TODO: Apply tags when tag support is fully implemented
            await SessionCache.shared.clearMetadata(for: paper.id)
        }

        // Download PDF if available and requested
        if downloadPDF, let pdfURL = paper.remotePDFURL {
            do {
                try await PDFManager.shared.downloadAndImport(from: pdfURL, for: publication, in: library)
                Logger.viewModels.infoCapture("Downloaded and attached PDF", category: "import")
            } catch {
                // Log but don't fail the import - paper is still added without PDF
                Logger.viewModels.warningCapture("Failed to download PDF: \(error.localizedDescription)", category: "import")
            }
        }

        await loadPublications()
        return publication
    }

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
