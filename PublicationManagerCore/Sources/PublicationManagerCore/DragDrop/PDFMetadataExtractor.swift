//
//  PDFMetadataExtractor.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-16.
//

import Foundation
import PDFKit
import OSLog

// MARK: - PDF Extracted Metadata

/// Metadata extracted from a PDF document.
public struct PDFExtractedMetadata: Sendable {
    /// Title from PDF document properties
    public let title: String?

    /// Author from PDF document properties
    public let author: String?

    /// Subject/description from PDF document properties
    public let subject: String?

    /// Keywords from PDF document properties
    public let keywords: [String]

    /// DOI extracted from PDF content
    public let extractedDOI: String?

    /// arXiv ID extracted from PDF content
    public let extractedArXivID: String?

    /// Bibcode extracted from PDF content (ADS)
    public let extractedBibcode: String?

    /// First-page text (fallback for title extraction)
    public let firstPageText: String?

    /// Confidence level of the extraction
    public let confidence: MetadataConfidence

    /// Creation date from PDF metadata
    public let creationDate: Date?

    /// Modification date from PDF metadata
    public let modificationDate: Date?

    public init(
        title: String? = nil,
        author: String? = nil,
        subject: String? = nil,
        keywords: [String] = [],
        extractedDOI: String? = nil,
        extractedArXivID: String? = nil,
        extractedBibcode: String? = nil,
        firstPageText: String? = nil,
        confidence: MetadataConfidence = .none,
        creationDate: Date? = nil,
        modificationDate: Date? = nil
    ) {
        self.title = title
        self.author = author
        self.subject = subject
        self.keywords = keywords
        self.extractedDOI = extractedDOI
        self.extractedArXivID = extractedArXivID
        self.extractedBibcode = extractedBibcode
        self.firstPageText = firstPageText
        self.confidence = confidence
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }

    /// Whether any identifier was extracted
    public var hasIdentifier: Bool {
        extractedDOI != nil || extractedArXivID != nil || extractedBibcode != nil
    }

    /// Best title: prefer document properties, fall back to first-page extraction
    public var bestTitle: String? {
        if let title, !title.isEmpty, title.lowercased() != "untitled" {
            return title
        }
        return nil
    }
}

// MARK: - Metadata Confidence

/// Confidence level of extracted metadata.
public enum MetadataConfidence: Int, Comparable, Sendable {
    /// No metadata could be extracted
    case none = 0

    /// Low confidence (fallback methods, heuristics)
    case low = 1

    /// Medium confidence (document properties but incomplete)
    case medium = 2

    /// High confidence (complete document properties or verified identifier)
    case high = 3

    public static func < (lhs: MetadataConfidence, rhs: MetadataConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - PDF Metadata Extractor

/// Extracts metadata and identifiers from PDF documents.
///
/// Extraction phases:
/// 1. PDF document properties (title, author, subject, keywords)
/// 2. Content scan for DOI/arXiv identifiers
/// 3. First-page title extraction (fallback)
public actor PDFMetadataExtractor {

    // MARK: - Singleton

    public static let shared = PDFMetadataExtractor()

    // MARK: - Properties

    /// Maximum number of pages to scan for identifiers
    private let maxPagesToScan = 3

    /// Maximum characters to scan per page
    private let maxCharsPerPage = 10000

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Extract metadata from a PDF file.
    ///
    /// - Parameter url: URL of the PDF file
    /// - Returns: Extracted metadata, or nil if the file cannot be read
    public func extract(from url: URL) async -> PDFExtractedMetadata? {
        Logger.files.infoCapture("Extracting metadata from: \(url.lastPathComponent)", category: "files")

        // Load PDF document
        guard let document = PDFDocument(url: url) else {
            Logger.files.warningCapture("Could not load PDF: \(url.lastPathComponent)", category: "files")
            return nil
        }

        return await extractFromDocument(document)
    }

    /// Extract metadata from PDF data.
    ///
    /// - Parameter data: PDF data
    /// - Returns: Extracted metadata, or nil if the data is invalid
    public func extract(from data: Data) async -> PDFExtractedMetadata? {
        Logger.files.infoCapture("Extracting metadata from PDF data (\(data.count) bytes)", category: "files")

        guard let document = PDFDocument(data: data) else {
            Logger.files.warningCapture("Could not parse PDF data", category: "files")
            return nil
        }

        return await extractFromDocument(document)
    }

    // MARK: - Private Methods

    /// Extract metadata from a loaded PDF document.
    @MainActor
    private func extractFromDocument(_ document: PDFDocument) async -> PDFExtractedMetadata {
        var title: String?
        var author: String?
        var subject: String?
        var keywords: [String] = []
        var creationDate: Date?
        var modificationDate: Date?
        var extractedDOI: String?
        var extractedArXivID: String?
        var extractedBibcode: String?
        var firstPageText: String?
        var confidence: MetadataConfidence = .none

        // Phase 1: Extract document properties
        if let attributes = document.documentAttributes {
            title = attributes[PDFDocumentAttribute.titleAttribute] as? String
            author = attributes[PDFDocumentAttribute.authorAttribute] as? String
            subject = attributes[PDFDocumentAttribute.subjectAttribute] as? String

            if let keywordsAttr = attributes[PDFDocumentAttribute.keywordsAttribute] {
                if let keywordsArray = keywordsAttr as? [String] {
                    keywords = keywordsArray
                } else if let keywordsString = keywordsAttr as? String {
                    keywords = keywordsString.components(separatedBy: CharacterSet(charactersIn: ",;"))
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            }

            creationDate = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date
            modificationDate = attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date

            // Update confidence based on document properties
            if title != nil && author != nil {
                confidence = .high
            } else if title != nil || author != nil {
                confidence = .medium
            }
        }

        // Phase 2: Scan content for identifiers
        let pageCount = min(document.pageCount, maxPagesToScan)
        var scannedText = ""

        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex),
                  let pageText = page.string else {
                continue
            }

            // Limit text per page
            let truncatedText = String(pageText.prefix(maxCharsPerPage))
            scannedText += truncatedText + "\n"

            // Extract first page text for title fallback
            if pageIndex == 0 {
                firstPageText = extractTitleFromFirstPage(truncatedText)
            }
        }

        // Extract identifiers from scanned text
        extractedDOI = IdentifierExtractor.extractDOIFromText(scannedText)
        extractedArXivID = IdentifierExtractor.extractArXivFromText(scannedText)
        extractedBibcode = IdentifierExtractor.extractBibcodeFromText(scannedText)

        // Upgrade confidence if identifier found
        if extractedDOI != nil || extractedArXivID != nil {
            confidence = max(confidence, .high)
        } else if extractedBibcode != nil {
            confidence = max(confidence, .medium)
        }

        Logger.files.infoCapture(
            "Extracted metadata - title: \(title ?? "none"), DOI: \(extractedDOI ?? "none"), arXiv: \(extractedArXivID ?? "none")",
            category: "files"
        )

        return PDFExtractedMetadata(
            title: title,
            author: author,
            subject: subject,
            keywords: keywords,
            extractedDOI: extractedDOI,
            extractedArXivID: extractedArXivID,
            extractedBibcode: extractedBibcode,
            firstPageText: firstPageText,
            confidence: confidence,
            creationDate: creationDate,
            modificationDate: modificationDate
        )
    }

    /// Extract a potential title from the first page text.
    ///
    /// Uses heuristics to find the title:
    /// - First large text block before author names
    /// - Exclude headers, page numbers, journal names
    private nonisolated func extractTitleFromFirstPage(_ text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Skip common header patterns
        let skipPatterns = [
            "preprint", "submitted", "accepted", "published",
            "journal", "volume", "issue", "pages",
            "doi:", "arxiv:", "http", "www",
            "copyright", "all rights reserved",
            "abstract"
        ]

        var candidateLines: [String] = []

        for line in lines.prefix(20) {  // Check first 20 lines
            let lowercased = line.lowercased()

            // Skip if matches common header patterns
            if skipPatterns.contains(where: { lowercased.contains($0) }) {
                continue
            }

            // Skip very short lines (likely page numbers, etc.)
            if line.count < 10 {
                continue
            }

            // Skip lines that look like author names (contain "and", multiple capital words)
            if lowercased.contains(" and ") && line.filter({ $0.isUppercase }).count > 3 {
                continue
            }

            // Skip lines that look like affiliations (contain "@", "university", "institute")
            if lowercased.contains("@") || lowercased.contains("university") || lowercased.contains("institute") {
                continue
            }

            candidateLines.append(line)

            // Return after finding 2 candidate lines (likely title is in first 1-2)
            if candidateLines.count >= 2 {
                break
            }
        }

        // Join candidate lines if they look like a multi-line title
        if candidateLines.count >= 2 {
            let combined = candidateLines.joined(separator: " ")
            if combined.count <= 300 {  // Reasonable title length
                return combined
            }
        }

        return candidateLines.first
    }
}
