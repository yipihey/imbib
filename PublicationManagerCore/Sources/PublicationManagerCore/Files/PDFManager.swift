//
//  PDFManager.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import CoreData
import CryptoKit
import OSLog

// MARK: - PDF Manager

/// Manages PDF files associated with publications.
///
/// Handles:
/// - Importing PDFs with human-readable filenames (ADR-004)
/// - Filename generation from publication metadata
/// - Collision handling with numeric suffixes
/// - SHA256 integrity verification
/// - Temporary PDF caching for online papers
@MainActor
public final class PDFManager: ObservableObject {

    // MARK: - Singleton

    public static let shared = PDFManager()

    // MARK: - Properties

    private let persistenceController: PersistenceController
    private let fileManager = FileManager.default

    /// Default papers directory name
    private let papersFolderName = "Papers"

    // MARK: - Initialization

    public init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - Link Existing PDF (BibDesk Import)

    /// Link an existing PDF file without copying.
    ///
    /// Used when importing BibDesk .bib files that already have PDFs in place.
    /// The file is NOT copied - we just create a CDLinkedFile record pointing to it.
    ///
    /// - Parameters:
    ///   - relativePath: The relative path from .bib file location (e.g., "Papers/Einstein_1905.pdf")
    ///   - publication: The publication to link the PDF to
    ///   - library: The library containing the publication
    /// - Returns: The created CDLinkedFile entity, or nil if the file doesn't exist
    @discardableResult
    public func linkExistingPDF(
        relativePath: String,
        for publication: CDPublication,
        in library: CDLibrary? = nil
    ) -> CDLinkedFile? {
        Logger.files.infoCapture("Linking existing PDF: \(relativePath)", category: "files")

        // Verify file exists
        var absoluteURL: URL?
        if let library, let bibURL = library.resolveURL() {
            absoluteURL = bibURL.deletingLastPathComponent().appendingPathComponent(relativePath)
        } else if let appSupport = applicationSupportURL {
            absoluteURL = appSupport.appendingPathComponent(relativePath)
        }

        if let url = absoluteURL, !fileManager.fileExists(atPath: url.path) {
            Logger.files.warningCapture("Linked PDF not found at: \(url.path)", category: "files")
            // Still create the link - file might be on another device (CloudKit sync)
        }

        let filename = (relativePath as NSString).lastPathComponent

        // Check if already linked
        if let existingLinks = publication.linkedFiles,
           existingLinks.contains(where: { $0.relativePath == relativePath }) {
            Logger.files.debugCapture("PDF already linked: \(relativePath)", category: "files")
            return existingLinks.first { $0.relativePath == relativePath }
        }

        // Create linked file record
        let context = persistenceController.viewContext
        let linkedFile = CDLinkedFile(context: context)
        linkedFile.id = UUID()
        linkedFile.relativePath = relativePath
        linkedFile.filename = filename
        linkedFile.fileType = (filename as NSString).pathExtension.lowercased()
        linkedFile.dateAdded = Date()
        linkedFile.publication = publication

        // Compute SHA256 if file exists
        if let url = absoluteURL {
            linkedFile.sha256 = computeSHA256(for: url)
        }

        persistenceController.save()

        Logger.files.infoCapture("Linked existing PDF: \(filename)", category: "files")
        return linkedFile
    }

    /// Process Bdsk-File-* fields from a BibTeX entry and create linked file records.
    ///
    /// This is called during BibTeX import to preserve existing PDF links from BibDesk.
    public func processBdskFiles(
        from entry: BibTeXEntry,
        for publication: CDPublication,
        in library: CDLibrary? = nil
    ) {
        // Find all Bdsk-File-* fields
        let bdskFields = entry.fields.filter { $0.key.hasPrefix("Bdsk-File-") }

        for (_, value) in bdskFields.sorted(by: { $0.key < $1.key }) {
            if let relativePath = BdskFileCodec.decode(value) {
                linkExistingPDF(relativePath: relativePath, for: publication, in: library)
            }
        }
    }

    // MARK: - Import PDF (Copy)

    /// Import a PDF file for a publication.
    ///
    /// The PDF is copied to the library's Papers folder with a human-readable name
    /// based on the publication's metadata.
    ///
    /// - Parameters:
    ///   - sourceURL: URL of the source PDF file
    ///   - publication: The publication to link the PDF to
    ///   - library: The library containing the publication (determines Papers folder location)
    ///   - preserveFilename: If true, keeps the original filename instead of auto-generating
    /// - Returns: The created CDLinkedFile entity
    @discardableResult
    public func importPDF(
        from sourceURL: URL,
        for publication: CDPublication,
        in library: CDLibrary? = nil,
        preserveFilename: Bool = false
    ) throws -> CDLinkedFile {
        Logger.files.infoCapture("Importing PDF: \(sourceURL.lastPathComponent)", category: "files")

        // Determine papers directory
        let papersDirectory = try resolvePapersDirectory(for: library)

        // Generate filename - either auto-generated or preserve original
        let filename: String
        if preserveFilename {
            filename = sourceURL.lastPathComponent
        } else {
            filename = generateFilename(for: publication)
        }
        let resolvedFilename = resolveCollision(filename, in: papersDirectory)

        // Destination path
        let destinationURL = papersDirectory.appendingPathComponent(resolvedFilename)

        // Copy the file
        do {
            // Start accessing security-scoped resource if needed
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessing { sourceURL.stopAccessingSecurityScopedResource() }
            }

            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            Logger.files.infoCapture("Copied PDF to: \(resolvedFilename)", category: "files")
        } catch {
            Logger.files.errorCapture("Failed to copy PDF: \(error.localizedDescription)", category: "files")
            throw PDFError.copyFailed(sourceURL, error)
        }

        // Compute SHA256
        let sha256 = computeSHA256(for: destinationURL)

        // Create linked file record
        let context = persistenceController.viewContext
        let linkedFile = CDLinkedFile(context: context)
        linkedFile.id = UUID()
        linkedFile.relativePath = "\(papersFolderName)/\(resolvedFilename)"
        linkedFile.filename = resolvedFilename
        linkedFile.fileType = "pdf"
        linkedFile.sha256 = sha256
        linkedFile.dateAdded = Date()
        linkedFile.publication = publication

        persistenceController.save()

        Logger.files.infoCapture("Created linked file: \(linkedFile.id)", category: "files")
        return linkedFile
    }

    /// Import PDF data directly (e.g., from downloaded content).
    @discardableResult
    public func importPDF(
        data: Data,
        for publication: CDPublication,
        in library: CDLibrary? = nil
    ) throws -> CDLinkedFile {
        Logger.files.infoCapture("Importing PDF data (\(data.count) bytes)", category: "files")

        // Determine papers directory
        let papersDirectory = try resolvePapersDirectory(for: library)

        // Generate human-readable filename
        let filename = generateFilename(for: publication)
        let resolvedFilename = resolveCollision(filename, in: papersDirectory)

        // Destination path
        let destinationURL = papersDirectory.appendingPathComponent(resolvedFilename)

        // Write the data
        do {
            try data.write(to: destinationURL)
            Logger.files.infoCapture("Wrote PDF to: \(resolvedFilename)", category: "files")
        } catch {
            Logger.files.errorCapture("Failed to write PDF: \(error.localizedDescription)", category: "files")
            throw PDFError.writeFailed(destinationURL, error)
        }

        // Compute SHA256
        let sha256 = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()

        // Create linked file record
        let context = persistenceController.viewContext
        let linkedFile = CDLinkedFile(context: context)
        linkedFile.id = UUID()
        linkedFile.relativePath = "\(papersFolderName)/\(resolvedFilename)"
        linkedFile.filename = resolvedFilename
        linkedFile.fileType = "pdf"
        linkedFile.sha256 = sha256
        linkedFile.dateAdded = Date()
        linkedFile.publication = publication

        persistenceController.save()

        Logger.files.infoCapture("Created linked file: \(linkedFile.id)", category: "files")
        return linkedFile
    }

    // MARK: - Download PDF

    /// Download a PDF from a URL and import it.
    @discardableResult
    public func downloadAndImport(
        from url: URL,
        for publication: CDPublication,
        in library: CDLibrary? = nil
    ) async throws -> CDLinkedFile {
        Logger.files.infoCapture("Downloading PDF from: \(url.absoluteString)", category: "files")

        // Download the PDF
        let (data, response) = try await URLSession.shared.data(from: url)

        // Verify it's a PDF
        if let httpResponse = response as? HTTPURLResponse {
            guard httpResponse.statusCode == 200 else {
                Logger.files.errorCapture("HTTP error: \(httpResponse.statusCode)", category: "files")
                throw PDFError.downloadFailed(url, nil)
            }

            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            if !contentType.contains("pdf") && !contentType.contains("octet-stream") {
                Logger.files.warningCapture("Unexpected content type: \(contentType)", category: "files")
            }
        }

        guard !data.isEmpty else {
            throw PDFError.emptyDownload(url)
        }

        Logger.files.infoCapture("Downloaded \(data.count) bytes", category: "files")

        return try importPDF(data: data, for: publication, in: library)
    }

    // MARK: - Filename Generation

    /// Generate a human-readable filename for a publication.
    ///
    /// Format: `{FirstAuthorLastName}_{Year}_{TruncatedTitle}.pdf`
    /// Example: `Einstein_1905_OnTheElectrodynamics.pdf`
    public func generateFilename(for publication: CDPublication) -> String {
        // Get first author's last name
        let author: String
        if let firstAuthor = publication.sortedAuthors.first {
            author = firstAuthor.familyName
        } else if let authorField = publication.fields["author"] {
            // Parse first author from field
            let firstAuthorStr = authorField.components(separatedBy: " and ").first ?? authorField
            let parsed = CDAuthor.parse(firstAuthorStr)
            author = parsed.familyName
        } else {
            author = "Unknown"
        }

        // Get year
        let year = publication.year > 0 ? String(publication.year) : "NoYear"

        // Get truncated title
        let title = truncateTitle(publication.title ?? "Untitled", maxLength: 40)

        // Combine and sanitize
        let base = "\(author)_\(year)_\(title)"
        let sanitized = sanitizeFilename(base)

        return sanitized + ".pdf"
    }

    /// Generate filename from a BibTeX entry (for imports before CDPublication exists).
    public func generateFilename(from entry: BibTeXEntry) -> String {
        // Get first author
        let author: String
        if let authorField = entry.fields["author"] {
            let firstAuthorStr = authorField.components(separatedBy: " and ").first ?? authorField
            let parsed = CDAuthor.parse(firstAuthorStr)
            author = parsed.familyName
        } else {
            author = "Unknown"
        }

        // Get year
        let year = entry.fields["year"] ?? "NoYear"

        // Get truncated title
        let title = truncateTitle(entry.title ?? "Untitled", maxLength: 40)

        // Combine and sanitize
        let base = "\(author)_\(year)_\(title)"
        let sanitized = sanitizeFilename(base)

        return sanitized + ".pdf"
    }

    // MARK: - File Operations

    /// Get the absolute URL for a linked file.
    public func resolveURL(for linkedFile: CDLinkedFile, in library: CDLibrary?) -> URL? {
        guard let baseURL = library?.resolveURL()?.deletingLastPathComponent() else {
            // Fall back to app support directory
            return applicationSupportURL?.appendingPathComponent(linkedFile.relativePath)
        }
        return baseURL.appendingPathComponent(linkedFile.relativePath)
    }

    /// Delete a linked file from disk and Core Data.
    public func delete(_ linkedFile: CDLinkedFile, in library: CDLibrary? = nil) throws {
        Logger.files.infoCapture("Deleting linked file: \(linkedFile.filename)", category: "files")

        // Delete file from disk
        if let url = resolveURL(for: linkedFile, in: library) {
            try? fileManager.removeItem(at: url)
        }

        // Delete from Core Data
        let context = persistenceController.viewContext
        context.delete(linkedFile)
        persistenceController.save()
    }

    /// Verify file integrity using SHA256.
    public func verifyIntegrity(of linkedFile: CDLinkedFile, in library: CDLibrary? = nil) -> Bool {
        guard let expectedHash = linkedFile.sha256,
              let url = resolveURL(for: linkedFile, in: library),
              let actualHash = computeSHA256(for: url) else {
            return false
        }
        return expectedHash == actualHash
    }

    // MARK: - Private Helpers

    /// Resolve the Papers directory for a library.
    private func resolvePapersDirectory(for library: CDLibrary?) throws -> URL {
        let papersURL: URL

        if let library, let papersPath = library.papersDirectoryPath {
            papersURL = URL(fileURLWithPath: papersPath)
        } else if let library, let bibURL = library.resolveURL() {
            // Papers folder next to .bib file
            papersURL = bibURL.deletingLastPathComponent().appendingPathComponent(papersFolderName)
        } else {
            // Fall back to app support
            guard let appSupport = applicationSupportURL else {
                throw PDFError.noPapersDirectory
            }
            papersURL = appSupport.appendingPathComponent(papersFolderName)
        }

        // Create directory if needed
        if !fileManager.fileExists(atPath: papersURL.path) {
            try fileManager.createDirectory(at: papersURL, withIntermediateDirectories: true)
            Logger.files.infoCapture("Created Papers directory: \(papersURL.path)", category: "files")
        }

        return papersURL
    }

    /// Application support directory.
    private var applicationSupportURL: URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("imbib")
    }

    /// Truncate title to max length without breaking words.
    private func truncateTitle(_ title: String, maxLength: Int) -> String {
        // Remove leading articles
        var cleaned = title
        for article in ["The ", "A ", "An "] {
            if cleaned.hasPrefix(article) {
                cleaned = String(cleaned.dropFirst(article.count))
                break
            }
        }

        // Remove special characters and convert to camelCase-ish
        let words = cleaned.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.capitalized }

        var result = ""
        for word in words {
            if result.count + word.count > maxLength {
                break
            }
            result += word
        }

        return result.isEmpty ? "Untitled" : result
    }

    /// Sanitize filename by removing invalid characters.
    private func sanitizeFilename(_ name: String) -> String {
        // Invalid characters: / \ : * ? " < > |
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")

        var sanitized = name.components(separatedBy: invalidChars).joined()

        // Replace spaces and other whitespace
        sanitized = sanitized.replacingOccurrences(of: " ", with: "")

        // Normalize unicode
        sanitized = sanitized.precomposedStringWithCanonicalMapping

        // Limit length (filesystem limits)
        if sanitized.count > 200 {
            sanitized = String(sanitized.prefix(200))
        }

        return sanitized
    }

    /// Resolve filename collision by adding numeric suffix.
    private func resolveCollision(_ filename: String, in directory: URL) -> String {
        var candidate = filename
        var counter = 1

        while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            // Einstein_1905_Electrodynamics.pdf → Einstein_1905_Electrodynamics_2.pdf
            let name = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            candidate = "\(name)_\(counter + 1).\(ext)"
            counter += 1

            // Safety limit
            if counter > 1000 {
                // Fall back to UUID
                candidate = "\(name)_\(UUID().uuidString.prefix(8)).\(ext)"
                break
            }
        }

        if candidate != filename {
            Logger.files.debugCapture("Resolved collision: \(filename) → \(candidate)", category: "files")
        }

        return candidate
    }

    /// Compute SHA256 hash of a file.
    private func computeSHA256(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - PDF Error

public enum PDFError: LocalizedError {
    case copyFailed(URL, Error)
    case writeFailed(URL, Error)
    case downloadFailed(URL, Error?)
    case emptyDownload(URL)
    case noPapersDirectory
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .copyFailed(let url, let error):
            return "Failed to copy PDF from \(url.lastPathComponent): \(error.localizedDescription)"
        case .writeFailed(let url, let error):
            return "Failed to write PDF to \(url.lastPathComponent): \(error.localizedDescription)"
        case .downloadFailed(let url, let error):
            if let error {
                return "Failed to download PDF from \(url.host ?? url.absoluteString): \(error.localizedDescription)"
            }
            return "Failed to download PDF from \(url.host ?? url.absoluteString)"
        case .emptyDownload(let url):
            return "Downloaded empty file from \(url.host ?? url.absoluteString)"
        case .noPapersDirectory:
            return "No Papers directory configured"
        case .fileNotFound(let path):
            return "PDF not found: \(path)"
        }
    }
}
