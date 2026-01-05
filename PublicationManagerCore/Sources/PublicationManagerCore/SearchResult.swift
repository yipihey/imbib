//
//  SearchResult.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation

// MARK: - Search Result

/// A search result from any source plugin.
/// This is the common currency for cross-source search deduplication.
public struct SearchResult: Sendable, Identifiable, Equatable, Hashable {

    // MARK: - Identity

    /// Unique identifier for this result (source-specific format)
    public let id: String

    /// Which source plugin produced this result
    public let sourceID: String

    // MARK: - Bibliographic Data

    public let title: String
    public let authors: [String]
    public let year: Int?
    public let venue: String?
    public let abstract: String?

    // MARK: - Identifiers

    public let doi: String?
    public let arxivID: String?
    public let pmid: String?
    public let bibcode: String?
    public let semanticScholarID: String?
    public let openAlexID: String?

    // MARK: - URLs

    public let pdfURL: URL?
    public let webURL: URL?
    public let bibtexURL: URL?

    // MARK: - Initialization

    public init(
        id: String,
        sourceID: String,
        title: String,
        authors: [String] = [],
        year: Int? = nil,
        venue: String? = nil,
        abstract: String? = nil,
        doi: String? = nil,
        arxivID: String? = nil,
        pmid: String? = nil,
        bibcode: String? = nil,
        semanticScholarID: String? = nil,
        openAlexID: String? = nil,
        pdfURL: URL? = nil,
        webURL: URL? = nil,
        bibtexURL: URL? = nil
    ) {
        self.id = id
        self.sourceID = sourceID
        self.title = title
        self.authors = authors
        self.year = year
        self.venue = venue
        self.abstract = abstract
        self.doi = doi
        self.arxivID = arxivID
        self.pmid = pmid
        self.bibcode = bibcode
        self.semanticScholarID = semanticScholarID
        self.openAlexID = openAlexID
        self.pdfURL = pdfURL
        self.webURL = webURL
        self.bibtexURL = bibtexURL
    }
}

// MARK: - Identifier Helpers

public extension SearchResult {

    /// Returns the primary identifier for this result (DOI preferred)
    var primaryIdentifier: String? {
        doi ?? arxivID ?? pmid ?? bibcode ?? semanticScholarID ?? openAlexID
    }

    /// Returns all available identifiers as a dictionary
    var allIdentifiers: [IdentifierType: String] {
        var result: [IdentifierType: String] = [:]
        if let doi = doi { result[.doi] = doi }
        if let arxivID = arxivID { result[.arxiv] = arxivID }
        if let pmid = pmid { result[.pmid] = pmid }
        if let bibcode = bibcode { result[.bibcode] = bibcode }
        if let semanticScholarID = semanticScholarID { result[.semanticScholar] = semanticScholarID }
        if let openAlexID = openAlexID { result[.openAlex] = openAlexID }
        return result
    }

    /// First author's last name (for display and cite key generation)
    var firstAuthorLastName: String? {
        guard let first = authors.first else { return nil }
        // Handle "Last, First" format
        if first.contains(",") {
            return first.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
        }
        // Handle "First Last" format
        return first.components(separatedBy: " ").last
    }
}

// MARK: - Identifier Type

/// Types of publication identifiers across different sources
public enum IdentifierType: String, Sendable, Codable, CaseIterable, Hashable {
    case doi
    case arxiv
    case pmid
    case pmcid
    case bibcode
    case semanticScholar
    case openAlex
    case dblp

    public var displayName: String {
        switch self {
        case .doi: return "DOI"
        case .arxiv: return "arXiv"
        case .pmid: return "PubMed"
        case .pmcid: return "PMC"
        case .bibcode: return "ADS Bibcode"
        case .semanticScholar: return "Semantic Scholar"
        case .openAlex: return "OpenAlex"
        case .dblp: return "DBLP"
        }
    }
}

// MARK: - Deduplicated Result

/// A search result that may have duplicates from multiple sources.
/// Used by the deduplication service to present unified results.
public struct DeduplicatedResult: Sendable, Identifiable, Equatable {

    /// The primary result (from highest priority source)
    public let primary: SearchResult

    /// Alternate results from other sources (same paper)
    public let alternates: [SearchResult]

    /// All known identifiers across all sources
    public let identifiers: [IdentifierType: String]

    public var id: String { primary.id }

    public init(
        primary: SearchResult,
        alternates: [SearchResult] = [],
        identifiers: [IdentifierType: String] = [:]
    ) {
        self.primary = primary
        self.alternates = alternates
        self.identifiers = identifiers.isEmpty ? primary.allIdentifiers : identifiers
    }

    /// All source IDs that found this paper
    public var sourceIDs: [String] {
        [primary.sourceID] + alternates.map(\.sourceID)
    }

    /// Best available PDF URL across all sources
    public var bestPDFURL: URL? {
        primary.pdfURL ?? alternates.first(where: { $0.pdfURL != nil })?.pdfURL
    }

    /// Best available BibTeX URL across all sources
    public var bestBibTeXURL: URL? {
        primary.bibtexURL ?? alternates.first(where: { $0.bibtexURL != nil })?.bibtexURL
    }
}
