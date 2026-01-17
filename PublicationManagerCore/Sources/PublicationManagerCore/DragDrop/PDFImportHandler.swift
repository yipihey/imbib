//
//  PDFImportHandler.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-16.
//

import Foundation
import CoreData
import OSLog

// MARK: - PDF Import Handler

/// Handles the workflow for importing PDFs as new publications.
///
/// Workflow:
/// 1. Extract metadata from PDF (title, author, DOI/arXiv)
/// 2. Enrich metadata via online sources (if identifier found)
/// 3. Check for duplicates
/// 4. Present preview to user
/// 5. Create publication and import PDF
@MainActor
public final class PDFImportHandler: ObservableObject {

    // MARK: - Singleton

    public static let shared = PDFImportHandler()

    // MARK: - Published State

    /// Current previews being prepared
    @Published public var previews: [PDFImportPreview] = []

    /// Whether preparation is in progress
    @Published public var isPreparing = false

    /// Current item being processed
    @Published public var currentItem: Int = 0

    /// Total items to process
    @Published public var totalItems: Int = 0

    // MARK: - Dependencies

    private let metadataExtractor: PDFMetadataExtractor
    private let attachmentManager: AttachmentManager
    private let persistenceController: PersistenceController

    // MARK: - Initialization

    public init(
        metadataExtractor: PDFMetadataExtractor = .shared,
        attachmentManager: AttachmentManager = .shared,
        persistenceController: PersistenceController = .shared
    ) {
        self.metadataExtractor = metadataExtractor
        self.attachmentManager = attachmentManager
        self.persistenceController = persistenceController
    }

    // MARK: - Public Methods

    /// Prepare PDFs for import by extracting and enriching metadata.
    ///
    /// - Parameters:
    ///   - urls: URLs of PDF files to import
    ///   - target: The drop target (determines library/collection)
    /// - Returns: Array of import previews for user confirmation
    public func preparePDFImport(urls: [URL], target: DropTarget) async -> [PDFImportPreview] {
        Logger.files.infoCapture("Preparing \(urls.count) PDFs for import", category: "files")

        isPreparing = true
        previews = []
        totalItems = urls.count
        currentItem = 0

        defer {
            isPreparing = false
        }

        var results: [PDFImportPreview] = []

        for (index, url) in urls.enumerated() {
            currentItem = index + 1

            let preview = await prepareSinglePDF(url: url, target: target)
            results.append(preview)
            previews = results
        }

        return results
    }

    /// Commit a single PDF import.
    ///
    /// - Parameters:
    ///   - preview: The import preview to commit
    ///   - libraryID: Target library UUID
    public func commitImport(_ preview: PDFImportPreview, to libraryID: UUID) async throws {
        Logger.files.infoCapture("Committing import for: \(preview.filename)", category: "files")

        let context = persistenceController.viewContext

        // Fetch library
        let libraryRequest = NSFetchRequest<CDLibrary>(entityName: "Library")
        libraryRequest.predicate = NSPredicate(format: "id == %@", libraryID as CVarArg)
        libraryRequest.fetchLimit = 1

        guard let library = try? context.fetch(libraryRequest).first else {
            throw DragDropError.libraryNotFound
        }

        switch preview.selectedAction {
        case .importAsNew:
            try await createPublicationFromPreview(preview, in: library)

        case .attachToExisting:
            if let existingID = preview.existingPublication {
                try await attachToExistingPublication(preview, publicationID: existingID, in: library)
            } else {
                throw DragDropError.publicationNotFound
            }

        case .replace:
            if let existingID = preview.existingPublication {
                try await replaceExistingPublication(preview, publicationID: existingID, in: library)
            } else {
                throw DragDropError.publicationNotFound
            }

        case .skip:
            Logger.files.infoCapture("Skipping import: \(preview.filename)", category: "files")
        }
    }

    // MARK: - Private Methods

    /// Prepare a single PDF for import.
    private func prepareSinglePDF(url: URL, target: DropTarget) async -> PDFImportPreview {
        let filename = url.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

        // Extract metadata from PDF
        let extractedMetadata = await metadataExtractor.extract(from: url)

        // Try to enrich via online sources
        var enrichedMetadata: EnrichedMetadata?
        if let doi = extractedMetadata?.extractedDOI {
            enrichedMetadata = await enrichFromDOI(doi)
        } else if let arxivID = extractedMetadata?.extractedArXivID {
            enrichedMetadata = await enrichFromArXiv(arxivID)
        }

        // Check for duplicates
        let (isDuplicate, existingID) = await checkForDuplicate(
            doi: extractedMetadata?.extractedDOI ?? enrichedMetadata?.doi,
            arxivID: extractedMetadata?.extractedArXivID ?? enrichedMetadata?.arxivID,
            title: extractedMetadata?.bestTitle ?? enrichedMetadata?.title
        )

        // Determine default action
        let defaultAction: ImportAction
        if isDuplicate {
            defaultAction = .attachToExisting
        } else {
            defaultAction = .importAsNew
        }

        return PDFImportPreview(
            sourceURL: url,
            filename: filename,
            fileSize: fileSize,
            extractedMetadata: extractedMetadata,
            enrichedMetadata: enrichedMetadata,
            isDuplicate: isDuplicate,
            existingPublication: existingID,
            status: .ready,
            selectedAction: defaultAction
        )
    }

    /// Enrich metadata from DOI.
    ///
    /// Uses the DOI resolver to fetch metadata. For now, this returns nil
    /// and enrichment happens via EnrichmentService after import.
    private func enrichFromDOI(_ doi: String) async -> EnrichedMetadata? {
        Logger.files.infoCapture("DOI found: \(doi) - will enrich after import", category: "files")

        // DOI enrichment happens post-import via EnrichmentService
        // For now, just return basic metadata with the DOI
        return EnrichedMetadata(
            doi: doi,
            source: "DOI"
        )
    }

    /// Enrich metadata from arXiv ID.
    private func enrichFromArXiv(_ arxivID: String) async -> EnrichedMetadata? {
        Logger.files.infoCapture("Enriching from arXiv: \(arxivID)", category: "files")

        do {
            let arxiv = ArXivSource()
            let results = try await arxiv.search(query: arxivID)
            if let result = results.first {
                let bibtexEntry = try? await arxiv.fetchBibTeX(for: result)
                // Use rawBibTeX if available, otherwise export the entry
                let bibtexString: String?
                if let entry = bibtexEntry {
                    bibtexString = entry.rawBibTeX ?? BibTeXExporter().export(entry)
                } else {
                    bibtexString = nil
                }
                return EnrichedMetadata(
                    title: result.title,
                    authors: result.authors,
                    year: result.year,
                    arxivID: arxivID,
                    abstract: result.abstract,
                    bibtex: bibtexString,
                    source: "arXiv"
                )
            }
        } catch {
            Logger.files.debugCapture("arXiv lookup failed: \(error.localizedDescription)", category: "files")
        }

        return nil
    }

    /// Check for duplicate publications.
    private func checkForDuplicate(doi: String?, arxivID: String?, title: String?) async -> (isDuplicate: Bool, existingID: UUID?) {
        let context = persistenceController.viewContext

        // Check by DOI
        if let doi {
            let request = NSFetchRequest<CDPublication>(entityName: "Publication")
            request.predicate = NSPredicate(format: "doi == %@", doi)
            request.fetchLimit = 1

            if let existing = try? context.fetch(request).first {
                return (true, existing.id)
            }
        }

        // Check by arXiv ID
        if let arxivID {
            let normalizedID = IdentifierExtractor.normalizeArXivID(arxivID)
            let request = NSFetchRequest<CDPublication>(entityName: "Publication")
            // Check multiple fields where arXiv might be stored
            request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "arxivID == %@", normalizedID),
                NSPredicate(format: "arxivID == %@", arxivID),
            ])
            request.fetchLimit = 1

            if let existing = try? context.fetch(request).first {
                return (true, existing.id)
            }
        }

        // Fuzzy match by title (last resort)
        if let title, !title.isEmpty {
            let request = NSFetchRequest<CDPublication>(entityName: "Publication")
            // Case-insensitive contains match
            request.predicate = NSPredicate(format: "title CONTAINS[cd] %@", title)
            request.fetchLimit = 5

            if let results = try? context.fetch(request) {
                // Check for close title match
                let normalizedTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                for existing in results {
                    let existingTitle = (existing.title ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    if existingTitle == normalizedTitle || existingTitle.contains(normalizedTitle) || normalizedTitle.contains(existingTitle) {
                        return (true, existing.id)
                    }
                }
            }
        }

        return (false, nil)
    }

    /// Create a new publication from preview.
    private func createPublicationFromPreview(_ preview: PDFImportPreview, in library: CDLibrary) async throws {
        let context = persistenceController.viewContext

        // Create publication
        let publication = CDPublication(context: context)
        publication.id = UUID()
        publication.dateAdded = Date()
        publication.dateModified = Date()

        // Use enriched metadata if available, fall back to extracted
        if let enriched = preview.enrichedMetadata {
            publication.title = enriched.title
            publication.year = Int16(enriched.year ?? 0)
            publication.doi = enriched.doi
            // arxivID is computed from fields["eprint"], set the field directly
            if let arxiv = enriched.arxivID {
                publication.fields["eprint"] = arxiv
            }

            // Set entry type and journal if available
            if let journal = enriched.journal {
                publication.fields["journal"] = journal
                publication.entryType = "article"
            } else {
                publication.entryType = "misc"
            }

            // Set authors
            if !enriched.authors.isEmpty {
                publication.fields["author"] = enriched.authors.joined(separator: " and ")
            }

            // Set abstract
            if let abstract = enriched.abstract {
                publication.fields["abstract"] = abstract
            }

            // Generate cite key
            publication.citeKey = generateCiteKey(
                author: enriched.authors.first,
                year: enriched.year,
                title: enriched.title
            )
        } else if let extracted = preview.extractedMetadata {
            publication.title = extracted.bestTitle ?? preview.filename
            publication.doi = extracted.extractedDOI
            // arxivID is computed from fields["eprint"], set the field directly
            if let arxiv = extracted.extractedArXivID {
                publication.fields["eprint"] = arxiv
            }
            publication.entryType = "misc"

            // Generate cite key from filename if no metadata
            publication.citeKey = generateCiteKey(from: preview.filename)
        } else {
            // No metadata - use filename
            publication.title = preview.filename
            publication.entryType = "misc"
            publication.citeKey = generateCiteKey(from: preview.filename)
        }

        // Add to library
        publication.addToLibrary(library)

        // Save first to get a valid publication
        try context.save()

        // Import the PDF
        _ = try attachmentManager.importPDF(
            from: preview.sourceURL,
            for: publication,
            in: library
        )

        // Save again with PDF link
        try context.save()

        Logger.files.infoCapture("Created publication: \(publication.citeKey) with PDF", category: "files")
    }

    /// Attach PDF to an existing publication.
    private func attachToExistingPublication(_ preview: PDFImportPreview, publicationID: UUID, in library: CDLibrary) async throws {
        let context = persistenceController.viewContext

        let request = NSFetchRequest<CDPublication>(entityName: "Publication")
        request.predicate = NSPredicate(format: "id == %@", publicationID as CVarArg)
        request.fetchLimit = 1

        guard let publication = try? context.fetch(request).first else {
            throw DragDropError.publicationNotFound
        }

        _ = try attachmentManager.importPDF(
            from: preview.sourceURL,
            for: publication,
            in: library
        )

        try context.save()

        Logger.files.infoCapture("Attached PDF to existing publication: \(publication.citeKey)", category: "files")
    }

    /// Replace existing publication's PDF.
    private func replaceExistingPublication(_ preview: PDFImportPreview, publicationID: UUID, in library: CDLibrary) async throws {
        let context = persistenceController.viewContext

        let request = NSFetchRequest<CDPublication>(entityName: "Publication")
        request.predicate = NSPredicate(format: "id == %@", publicationID as CVarArg)
        request.fetchLimit = 1

        guard let publication = try? context.fetch(request).first else {
            throw DragDropError.publicationNotFound
        }

        // Delete existing PDFs
        if let linkedFiles = publication.linkedFiles {
            for file in linkedFiles where file.fileType == "pdf" {
                try? attachmentManager.delete(file, in: library)
            }
        }

        // Import new PDF
        _ = try attachmentManager.importPDF(
            from: preview.sourceURL,
            for: publication,
            in: library
        )

        try context.save()

        Logger.files.infoCapture("Replaced PDF for publication: \(publication.citeKey)", category: "files")
    }

    /// Generate a cite key from author, year, and title.
    private func generateCiteKey(author: String?, year: Int?, title: String?) -> String {
        let authorPart: String
        if let author {
            // Extract last name
            let parts = author.components(separatedBy: " ")
            authorPart = parts.last ?? "Unknown"
        } else {
            authorPart = "Unknown"
        }

        let yearPart = year.map { String($0) } ?? "NoYear"

        let titlePart: String
        if let title {
            // Extract first significant word
            let words = title.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 && !["the", "and", "for", "with"].contains($0.lowercased()) }
            titlePart = words.first?.capitalized ?? "Paper"
        } else {
            titlePart = "Paper"
        }

        return "\(authorPart)\(yearPart)\(titlePart)"
    }

    /// Generate a cite key from a filename.
    private func generateCiteKey(from filename: String) -> String {
        // Remove extension and sanitize
        let name = (filename as NSString).deletingPathExtension
        let sanitized = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()

        return sanitized.isEmpty ? "import\(UUID().uuidString.prefix(8))" : sanitized
    }
}
