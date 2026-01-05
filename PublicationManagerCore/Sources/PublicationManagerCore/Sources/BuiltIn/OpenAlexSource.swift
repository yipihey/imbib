//
//  OpenAlexSource.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog

// MARK: - OpenAlex Source

/// Source plugin for OpenAlex open scholarly metadata.
public actor OpenAlexSource: SourcePlugin {

    // MARK: - Properties

    public nonisolated let metadata = SourceMetadata(
        id: "openalex",
        name: "OpenAlex",
        description: "Open catalog of the world's scholarly works",
        rateLimit: RateLimit(requestsPerInterval: 100000, intervalSeconds: 86400),  // 100k/day
        credentialRequirement: .emailOptional,
        registrationURL: nil,
        deduplicationPriority: 50,
        iconName: "books.vertical"
    )

    let rateLimiter: RateLimiter
    let baseURL = "https://api.openalex.org"
    let session: URLSession
    let credentialManager: CredentialManager

    // MARK: - Initialization

    public init(
        session: URLSession = .shared,
        credentialManager: CredentialManager = CredentialManager()
    ) {
        self.session = session
        self.credentialManager = credentialManager
        self.rateLimiter = RateLimiter(
            rateLimit: RateLimit(requestsPerInterval: 100000, intervalSeconds: 86400)
        )
    }

    // MARK: - SourcePlugin

    public func search(query: String) async throws -> [SearchResult] {
        Logger.sources.entering()
        defer { Logger.sources.exiting() }

        await rateLimiter.waitIfNeeded()

        var components = URLComponents(string: "\(baseURL)/works")!
        var queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "per-page", value: "50"),
            URLQueryItem(name: "select", value: "id,doi,title,authorships,publication_year,host_venue,abstract_inverted_index,open_access,ids"),
        ]

        // Add polite pool email if available
        if let email = await credentialManager.email(for: "openalex") {
            queryItems.append(URLQueryItem(name: "mailto", value: email))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw SourceError.invalidRequest("Invalid URL")
        }

        Logger.network.httpRequest("GET", url: url)

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        Logger.network.httpResponse(httpResponse.statusCode, url: url, bytes: data.count)

        guard httpResponse.statusCode == 200 else {
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        return try parseResponse(data)
    }

    public func fetchBibTeX(for result: SearchResult) async throws -> BibTeXEntry {
        // If we have DOI, use content negotiation
        if let doi = result.doi {
            return try await fetchBibTeXByDOI(doi)
        }

        // Otherwise construct from metadata
        return constructBibTeXEntry(from: result)
    }

    public nonisolated func normalize(_ entry: BibTeXEntry) -> BibTeXEntry {
        entry
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> [SearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            throw SourceError.parseError("Invalid OpenAlex response")
        }

        return results.compactMap { parseWork($0) }
    }

    private func parseWork(_ work: [String: Any]) -> SearchResult? {
        guard let openAlexID = work["id"] as? String else { return nil }

        let title = work["title"] as? String ?? "Untitled"
        let authors = extractAuthors(from: work)
        let year = work["publication_year"] as? Int
        let venue = extractVenue(from: work)
        let abstract = reconstructAbstract(from: work)

        let doi = (work["doi"] as? String)?.replacingOccurrences(of: "https://doi.org/", with: "")
        let ids = work["ids"] as? [String: Any] ?? [:]
        let pmid = ids["pmid"] as? String
        let pmcid = ids["pmcid"] as? String

        // Build PDF links with source tracking
        var pdfLinks: [PDFLink] = []
        if let openAccess = work["open_access"] as? [String: Any],
           let oaURL = openAccess["oa_url"] as? String,
           let url = URL(string: oaURL) {
            pdfLinks.append(PDFLink(url: url, type: .publisher, sourceID: "openalex"))
        }

        // Extract OpenAlex ID from URL
        let shortID = openAlexID.replacingOccurrences(of: "https://openalex.org/", with: "")

        return SearchResult(
            id: shortID,
            sourceID: "openalex",
            title: title,
            authors: authors,
            year: year,
            venue: venue,
            abstract: abstract,
            doi: doi,
            pmid: pmid,
            openAlexID: shortID,
            pdfLinks: pdfLinks,
            webURL: URL(string: openAlexID)
        )
    }

    private func extractAuthors(from work: [String: Any]) -> [String] {
        guard let authorships = work["authorships"] as? [[String: Any]] else { return [] }

        return authorships.compactMap { authorship -> String? in
            guard let author = authorship["author"] as? [String: Any],
                  let name = author["display_name"] as? String else { return nil }
            return name
        }
    }

    private func extractVenue(from work: [String: Any]) -> String? {
        guard let hostVenue = work["host_venue"] as? [String: Any] else { return nil }
        return hostVenue["display_name"] as? String
    }

    private func reconstructAbstract(from work: [String: Any]) -> String? {
        guard let invertedIndex = work["abstract_inverted_index"] as? [String: [Int]] else {
            return nil
        }

        // Reconstruct abstract from inverted index
        var words: [(Int, String)] = []
        for (word, positions) in invertedIndex {
            for position in positions {
                words.append((position, word))
            }
        }

        words.sort { $0.0 < $1.0 }
        return words.map { $0.1 }.joined(separator: " ")
    }

    private func fetchBibTeXByDOI(_ doi: String) async throws -> BibTeXEntry {
        let url = URL(string: "https://doi.org/\(doi)")!

        var request = URLRequest(url: url)
        request.setValue("application/x-bibtex", forHTTPHeaderField: "Accept")

        Logger.network.httpRequest("GET", url: url)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let bibtexString = String(data: data, encoding: .utf8) else {
            throw SourceError.notFound("Could not fetch BibTeX")
        }

        Logger.network.httpResponse(httpResponse.statusCode, url: url, bytes: data.count)

        let parser = BibTeXParser()
        let entries = try parser.parseEntries(bibtexString)

        guard let entry = entries.first else {
            throw SourceError.parseError("No entry in BibTeX response")
        }

        return entry
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
