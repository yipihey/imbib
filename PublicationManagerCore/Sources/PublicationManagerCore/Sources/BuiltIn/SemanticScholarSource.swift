//
//  SemanticScholarSource.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog

// MARK: - Semantic Scholar Source

/// Source plugin for Semantic Scholar academic search.
public actor SemanticScholarSource: SourcePlugin {

    // MARK: - Properties

    public nonisolated let metadata = SourceMetadata(
        id: "semanticscholar",
        name: "Semantic Scholar",
        description: "AI-powered academic search engine",
        rateLimit: RateLimit(requestsPerInterval: 100, intervalSeconds: 1),
        credentialRequirement: .apiKeyOptional,
        registrationURL: URL(string: "https://www.semanticscholar.org/product/api#api-key-form"),
        deduplicationPriority: 40,
        iconName: "brain"
    )

    private let rateLimiter: RateLimiter
    private let baseURL = "https://api.semanticscholar.org/graph/v1"
    private let session: URLSession
    private let credentialManager: CredentialManager

    // MARK: - Initialization

    public init(
        session: URLSession = .shared,
        credentialManager: CredentialManager = CredentialManager()
    ) {
        self.session = session
        self.credentialManager = credentialManager
        self.rateLimiter = RateLimiter(
            rateLimit: RateLimit(requestsPerInterval: 100, intervalSeconds: 1)
        )
    }

    // MARK: - SourcePlugin

    public func search(query: String) async throws -> [SearchResult] {
        Logger.sources.entering()
        defer { Logger.sources.exiting() }

        await rateLimiter.waitIfNeeded()

        var components = URLComponents(string: "\(baseURL)/paper/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fields", value: "paperId,title,authors,year,venue,abstract,externalIds,openAccessPdf,url"),
            URLQueryItem(name: "limit", value: "50"),
        ]

        guard let url = components.url else {
            throw SourceError.invalidRequest("Invalid URL")
        }

        Logger.network.httpRequest("GET", url: url)

        var request = URLRequest(url: url)

        // Add API key if available
        if let apiKey = await credentialManager.apiKey(for: "semanticscholar") {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        Logger.network.httpResponse(httpResponse.statusCode, url: url, bytes: data.count)

        if httpResponse.statusCode == 429 {
            throw SourceError.rateLimited(retryAfter: nil)
        }

        guard httpResponse.statusCode == 200 else {
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        return try parseResponse(data)
    }

    public func fetchBibTeX(for result: SearchResult) async throws -> BibTeXEntry {
        // Semantic Scholar doesn't have a BibTeX endpoint
        // Construct entry from search result data
        return constructBibTeXEntry(from: result)
    }

    public nonisolated func normalize(_ entry: BibTeXEntry) -> BibTeXEntry {
        entry
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> [SearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let papers = json["data"] as? [[String: Any]] else {
            throw SourceError.parseError("Invalid Semantic Scholar response")
        }

        return papers.compactMap { parsePaper($0) }
    }

    private func parsePaper(_ paper: [String: Any]) -> SearchResult? {
        guard let paperId = paper["paperId"] as? String,
              let title = paper["title"] as? String else { return nil }

        let authors = extractAuthors(from: paper)
        let year = paper["year"] as? Int
        let venue = paper["venue"] as? String
        let abstract = paper["abstract"] as? String
        let externalIds = paper["externalIds"] as? [String: Any] ?? [:]

        let doi = externalIds["DOI"] as? String
        let arxivID = externalIds["ArXiv"] as? String
        let pmid = externalIds["PubMed"] as? String

        var pdfURL: URL?
        if let openAccess = paper["openAccessPdf"] as? [String: Any],
           let urlString = openAccess["url"] as? String {
            pdfURL = URL(string: urlString)
        }

        let webURL = (paper["url"] as? String).flatMap { URL(string: $0) }

        return SearchResult(
            id: paperId,
            sourceID: "semanticscholar",
            title: title,
            authors: authors,
            year: year,
            venue: venue,
            abstract: abstract,
            doi: doi,
            arxivID: arxivID,
            pmid: pmid,
            semanticScholarID: paperId,
            pdfURL: pdfURL,
            webURL: webURL
        )
    }

    private func extractAuthors(from paper: [String: Any]) -> [String] {
        guard let authors = paper["authors"] as? [[String: Any]] else { return [] }
        return authors.compactMap { $0["name"] as? String }
    }

    private func constructBibTeXEntry(from result: SearchResult) -> BibTeXEntry {
        var fields: [String: String] = [:]

        fields["title"] = result.title
        fields["author"] = result.authors.joined(separator: " and ")
        if let year = result.year {
            fields["year"] = String(year)
        }
        if let venue = result.venue {
            fields["journal"] = venue
        }
        if let abstract = result.abstract {
            fields["abstract"] = abstract
        }
        if let doi = result.doi {
            fields["doi"] = doi
        }
        if let arxivID = result.arxivID {
            fields["eprint"] = arxivID
            fields["archiveprefix"] = "arXiv"
        }
        if let url = result.webURL {
            fields["url"] = url.absoluteString
        }

        let citeKey = CiteKeyGenerator().generate(from: result)

        return BibTeXEntry(
            citeKey: citeKey,
            entryType: "article",
            fields: fields
        )
    }
}
