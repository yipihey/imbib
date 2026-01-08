//
//  PublicationRowData.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-05.
//

import Foundation

/// Immutable value-type snapshot of publication data for safe list rendering.
///
/// This struct captures all data needed to display a publication row at creation time.
/// Unlike passing `CDPublication` directly (which can crash if the object is deleted
/// during SwiftUI re-render), `PublicationRowData` is immune to Core Data lifecycle issues.
///
/// ## Why This Exists
///
/// When using `@ObservedObject CDPublication` in row views:
/// 1. User deletes publications
/// 2. Core Data marks objects as deleted
/// 3. SwiftUI re-renders the List
/// 4. `@ObservedObject` setup triggers property access on deleted objects
/// 5. **CRASH** - before any guard in `body` can run
///
/// By converting to value types upfront, we eliminate this race condition entirely.
public struct PublicationRowData: Identifiable, Hashable, Sendable {

    // MARK: - Core Identity

    /// Unique identifier (matches CDPublication.id)
    public let id: UUID

    /// BibTeX cite key
    public let citeKey: String

    // MARK: - Display Data

    /// Publication title
    public let title: String

    /// Pre-formatted author string for display (e.g., "Einstein, Bohr ... Feynman")
    public let authorString: String

    /// Publication year (nil if not available)
    public let year: Int?

    /// Abstract text (nil if not available)
    public let abstract: String?

    /// Whether the publication has been read
    public let isRead: Bool

    /// Whether a PDF is available (local or remote)
    public let hasPDF: Bool

    /// Citation count from online sources
    public let citationCount: Int

    /// DOI for context menu "Copy DOI" action
    public let doi: String?

    /// Venue (journal, booktitle, or publisher) for display
    public let venue: String?

    /// Date added to library (for sorting)
    public let dateAdded: Date

    /// Date last modified (for sorting)
    public let dateModified: Date

    // MARK: - arXiv Categories

    /// Primary arXiv category (e.g., "cs.LG", "astro-ph.GA")
    public let primaryCategory: String?

    /// All arXiv categories (includes cross-listed)
    public let categories: [String]

    // MARK: - Initialization

    /// Create a snapshot from a CDPublication.
    ///
    /// - Parameter publication: The Core Data publication to snapshot
    /// - Returns: nil if the publication has been deleted or is invalid
    public init?(publication: CDPublication) {
        // Guard against deleted Core Data objects
        guard !publication.isDeleted,
              publication.managedObjectContext != nil else {
            return nil
        }

        self.id = publication.id
        self.citeKey = publication.citeKey
        self.title = publication.title ?? "Untitled"
        self.authorString = Self.formatAuthorString(from: publication)
        self.year = publication.year > 0 ? Int(publication.year) : Self.parseYearFromFields(publication.fields)
        self.abstract = publication.abstract
        self.isRead = publication.isRead
        self.hasPDF = Self.checkHasPDF(publication)
        self.citationCount = Int(publication.citationCount)
        self.doi = publication.doi
        self.venue = Self.extractVenue(from: publication)
        self.dateAdded = publication.dateAdded
        self.dateModified = publication.dateModified
        self.primaryCategory = Self.extractPrimaryCategory(from: publication)
        self.categories = Self.extractCategories(from: publication)
    }

    // MARK: - Venue Extraction

    /// Extract venue from publication fields based on entry type.
    ///
    /// Priority: journal > booktitle > series > publisher
    /// For articles: journal
    /// For conference papers: booktitle
    /// For books: publisher or series
    private static func extractVenue(from publication: CDPublication) -> String? {
        let fields = publication.fields

        // Try journal first (for @article)
        if let journal = fields["journal"], !journal.isEmpty {
            return cleanVenue(journal)
        }

        // Try booktitle (for @inproceedings, @incollection)
        if let booktitle = fields["booktitle"], !booktitle.isEmpty {
            return cleanVenue(booktitle)
        }

        // Try series (for book series)
        if let series = fields["series"], !series.isEmpty {
            return cleanVenue(series)
        }

        // Try publisher as fallback (for @book, @proceedings)
        if let publisher = fields["publisher"], !publisher.isEmpty {
            return cleanVenue(publisher)
        }

        return nil
    }

    /// Clean venue string (remove braces, trim whitespace)
    private static func cleanVenue(_ venue: String) -> String {
        venue
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Author Formatting

    /// Format author list for Mail-style display.
    ///
    /// - 1 author: "LastName"
    /// - 2 authors: "LastName1, LastName2"
    /// - 3 authors: "LastName1, LastName2, LastName3"
    /// - 4+ authors: "LastName1, LastName2 ... LastNameN"
    private static func formatAuthorString(from publication: CDPublication) -> String {
        // Try CDAuthor entities first
        let sortedAuthors = publication.sortedAuthors
        if !sortedAuthors.isEmpty {
            let names = sortedAuthors.map { BibTeXFieldCleaner.cleanAuthorName($0.displayName) }
            return formatAuthorList(names)
        }

        // Fall back to raw author field (BibTeX format with " and ")
        guard let rawAuthor = publication.fields["author"] else {
            return "Unknown Author"
        }

        let authors = rawAuthor.components(separatedBy: " and ")
            .map { BibTeXFieldCleaner.cleanAuthorName($0) }
            .filter { !$0.isEmpty }

        return formatAuthorList(authors)
    }

    private static func formatAuthorList(_ authors: [String]) -> String {
        guard !authors.isEmpty else {
            return "Unknown Author"
        }

        let lastNames = authors.map { extractLastName(from: $0) }

        switch lastNames.count {
        case 1:
            return lastNames[0]
        case 2:
            return "\(lastNames[0]), \(lastNames[1])"
        case 3:
            return "\(lastNames[0]), \(lastNames[1]), \(lastNames[2])"
        default:
            // 4+ authors: first two ... last
            return "\(lastNames[0]), \(lastNames[1]) ... \(lastNames[lastNames.count - 1])"
        }
    }

    private static func extractLastName(from author: String) -> String {
        let trimmed = author.trimmingCharacters(in: .whitespaces)

        if trimmed.contains(",") {
            // "Last, First" format
            return trimmed.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? trimmed
        } else {
            // "First Last" format - get the last word
            let parts = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
            return parts.last ?? trimmed
        }
    }

    // MARK: - Year Parsing

    private static func parseYearFromFields(_ fields: [String: String]) -> Int? {
        guard let yearStr = fields["year"], let parsed = Int(yearStr) else {
            return nil
        }
        return parsed > 0 ? parsed : nil
    }

    // MARK: - Attachment Check

    private static func checkHasPDF(_ publication: CDPublication) -> Bool {
        // Only show paperclip for actual stored attachments (not potential download URLs)
        guard let linkedFiles = publication.linkedFiles else { return false }
        return !linkedFiles.isEmpty
    }

    // MARK: - Category Extraction

    /// Extract primary arXiv category from BibTeX fields.
    ///
    /// Looks for `primaryclass` field (standard arXiv BibTeX convention).
    private static func extractPrimaryCategory(from publication: CDPublication) -> String? {
        publication.fields["primaryclass"]
    }

    /// Extract all arXiv categories from BibTeX fields.
    ///
    /// Returns the primary category plus any cross-listed categories from `categories` field.
    private static func extractCategories(from publication: CDPublication) -> [String] {
        var result: [String] = []

        // Add primary category first
        if let primary = publication.fields["primaryclass"], !primary.isEmpty {
            result.append(primary)
        }

        // Add additional categories from categories field (comma-separated)
        if let categoriesField = publication.fields["categories"] {
            let additional = categoriesField
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !result.contains($0) }
            result.append(contentsOf: additional)
        }

        return result
    }
}

// MARK: - Batch Conversion

extension PublicationRowData {

    /// Convert an array of CDPublications to row data, filtering out deleted objects.
    ///
    /// - Parameter publications: The publications to convert
    /// - Returns: Array of valid row data (deleted publications are excluded)
    public static func from(_ publications: [CDPublication]) -> [PublicationRowData] {
        publications.compactMap { PublicationRowData(publication: $0) }
    }
}
