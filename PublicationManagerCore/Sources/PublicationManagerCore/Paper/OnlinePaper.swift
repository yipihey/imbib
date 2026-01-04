//
//  OnlinePaper.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation

// MARK: - Online Paper

/// A paper from an online search result.
///
/// This wraps a SearchResult or DeduplicatedResult with additional
/// state for session caching and library membership checking.
public struct OnlinePaper: PaperRepresentable, Hashable {

    // MARK: - Identity

    public let id: String
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

    public let remotePDFURL: URL?
    public let webURL: URL?
    public let bibtexURL: URL?

    // MARK: - Context

    /// If this paper is from a smart search, stores the search ID
    public let smartSearchID: UUID?

    /// Reference to session cache for PDF retrieval
    private let sessionCacheID: UUID?

    // MARK: - Source Type

    public var sourceType: PaperSourceType {
        if let searchID = smartSearchID {
            return .smartSearch(searchID: searchID)
        }
        return .adHocSearch(sourceID: sourceID)
    }

    // MARK: - Initialization from SearchResult

    public init(
        result: SearchResult,
        smartSearchID: UUID? = nil,
        sessionCacheID: UUID? = nil
    ) {
        self.id = result.id
        self.sourceID = result.sourceID
        self.title = result.title
        self.authors = result.authors
        self.year = result.year
        self.venue = result.venue
        self.abstract = result.abstract
        self.doi = result.doi
        self.arxivID = result.arxivID
        self.pmid = result.pmid
        self.bibcode = result.bibcode
        self.semanticScholarID = result.semanticScholarID
        self.openAlexID = result.openAlexID
        self.remotePDFURL = result.pdfURL
        self.webURL = result.webURL
        self.bibtexURL = result.bibtexURL
        self.smartSearchID = smartSearchID
        self.sessionCacheID = sessionCacheID
    }

    // MARK: - Initialization from DeduplicatedResult

    public init(
        result: DeduplicatedResult,
        smartSearchID: UUID? = nil,
        sessionCacheID: UUID? = nil
    ) {
        self.id = result.primary.id
        self.sourceID = result.primary.sourceID
        self.title = result.primary.title
        self.authors = result.primary.authors
        self.year = result.primary.year
        self.venue = result.primary.venue
        self.abstract = result.primary.abstract

        // Merge identifiers from all sources
        self.doi = result.identifiers[.doi] ?? result.primary.doi
        self.arxivID = result.identifiers[.arxiv] ?? result.primary.arxivID
        self.pmid = result.identifiers[.pmid] ?? result.primary.pmid
        self.bibcode = result.identifiers[.bibcode] ?? result.primary.bibcode
        self.semanticScholarID = result.identifiers[.semanticScholar] ?? result.primary.semanticScholarID
        self.openAlexID = result.identifiers[.openAlex] ?? result.primary.openAlexID

        // Use best available URLs
        self.remotePDFURL = result.bestPDFURL
        self.webURL = result.primary.webURL
        self.bibtexURL = result.bestBibTeXURL

        self.smartSearchID = smartSearchID
        self.sessionCacheID = sessionCacheID
    }

    // MARK: - PaperRepresentable

    public func pdfURL() async -> URL? {
        // Check session cache first for already-downloaded PDF
        if let cachedURL = await SessionCache.shared.getCachedPDF(for: id) {
            return cachedURL
        }

        // Return remote URL - caller can use SessionCache to download if needed
        return remotePDFURL
    }

    public func bibtex() async throws -> String {
        // Check session cache first
        if let cached = await SessionCache.shared.getCachedBibTeX(for: id) {
            return cached
        }

        // Fetch from source
        guard let url = bibtexURL else {
            throw OnlinePaperError.noBibTeXAvailable
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let bibtex = String(data: data, encoding: .utf8) else {
            throw OnlinePaperError.invalidBibTeXData
        }

        // Cache for session
        await SessionCache.shared.cacheBibTeX(bibtex, for: id)

        return bibtex
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: OnlinePaper, rhs: OnlinePaper) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Online Paper Error

public enum OnlinePaperError: LocalizedError {
    case noBibTeXAvailable
    case invalidBibTeXData
    case pdfDownloadFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .noBibTeXAvailable:
            return "No BibTeX URL available for this paper"
        case .invalidBibTeXData:
            return "Failed to decode BibTeX data"
        case .pdfDownloadFailed(let error):
            return "PDF download failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Batch Creation

public extension OnlinePaper {
    /// Create OnlinePaper array from SearchResult array
    static func from(
        results: [SearchResult],
        smartSearchID: UUID? = nil
    ) -> [OnlinePaper] {
        results.map { OnlinePaper(result: $0, smartSearchID: smartSearchID) }
    }

    /// Create OnlinePaper array from DeduplicatedResult array
    static func from(
        results: [DeduplicatedResult],
        smartSearchID: UUID? = nil
    ) -> [OnlinePaper] {
        results.map { OnlinePaper(result: $0, smartSearchID: smartSearchID) }
    }
}
