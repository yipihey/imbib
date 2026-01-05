//
//  DBLPSource.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog

// MARK: - DBLP Source

/// Source plugin for DBLP computer science bibliography.
public actor DBLPSource: SourcePlugin {

    // MARK: - Properties

    public nonisolated let metadata = SourceMetadata(
        id: "dblp",
        name: "DBLP",
        description: "Computer science bibliography",
        rateLimit: .none,
        credentialRequirement: .none,
        registrationURL: nil,
        deduplicationPriority: 70,
        iconName: "desktopcomputer"
    )

    private let baseURL = "https://dblp.org/search/publ/api"
    private let session: URLSession

    // MARK: - Initialization

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - SourcePlugin

    public func search(query: String) async throws -> [SearchResult] {
        Logger.sources.entering()
        defer { Logger.sources.exiting() }

        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "h", value: "50"),  // max results
        ]

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
        Logger.sources.entering()
        defer { Logger.sources.exiting() }

        // DBLP provides BibTeX at a predictable URL
        guard let bibtexURL = result.bibtexURL else {
            throw SourceError.notFound("No BibTeX URL")
        }

        Logger.network.httpRequest("GET", url: bibtexURL)

        let (data, response) = try await session.data(from: bibtexURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let bibtexString = String(data: data, encoding: .utf8) else {
            throw SourceError.notFound("Could not fetch BibTeX")
        }

        Logger.network.httpResponse(httpResponse.statusCode, url: bibtexURL, bytes: data.count)

        let parser = BibTeXParser()
        let entries = try parser.parseEntries(bibtexString)

        guard let entry = entries.first else {
            throw SourceError.parseError("No entry in BibTeX response")
        }

        return entry
    }

    public nonisolated func normalize(_ entry: BibTeXEntry) -> BibTeXEntry {
        entry
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> [SearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let hits = result["hits"] as? [String: Any],
              let hitArray = hits["hit"] as? [[String: Any]] else {
            return []
        }

        return hitArray.compactMap { parseHit($0) }
    }

    private func parseHit(_ hit: [String: Any]) -> SearchResult? {
        guard let info = hit["info"] as? [String: Any] else { return nil }

        let key = info["key"] as? String ?? UUID().uuidString
        let title = info["title"] as? String ?? "Untitled"
        let authors = extractAuthors(from: info)
        let year = (info["year"] as? String).flatMap { Int($0) }
        let venue = info["venue"] as? String
        let doi = info["doi"] as? String
        let ee = info["ee"] as? String  // Electronic edition URL

        // DBLP key to BibTeX URL
        let bibtexURL = URL(string: "https://dblp.org/rec/\(key).bib")
        let webURL = URL(string: "https://dblp.org/rec/\(key)")

        // Build PDF links with source tracking
        var pdfLinks: [PDFLink] = []
        if let eeURL = ee, let url = URL(string: eeURL) {
            pdfLinks.append(PDFLink(url: url, type: .publisher, sourceID: "dblp"))
        }

        return SearchResult(
            id: key,
            sourceID: "dblp",
            title: title,
            authors: authors,
            year: year,
            venue: venue,
            doi: doi,
            pdfLinks: pdfLinks,
            webURL: webURL,
            bibtexURL: bibtexURL
        )
    }

    private func extractAuthors(from info: [String: Any]) -> [String] {
        guard let authors = info["authors"] as? [String: Any],
              let authorData = authors["author"] else { return [] }

        // Can be single author (dict) or multiple (array)
        if let authorArray = authorData as? [[String: Any]] {
            return authorArray.compactMap { $0["text"] as? String }
        } else if let authorDict = authorData as? [String: Any] {
            if let name = authorDict["text"] as? String {
                return [name]
            }
        }

        return []
    }
}
