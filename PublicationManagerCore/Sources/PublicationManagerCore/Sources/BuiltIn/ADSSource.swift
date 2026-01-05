//
//  ADSSource.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog

// MARK: - NASA ADS Source

/// Source plugin for NASA Astrophysics Data System.
/// Requires API key from https://ui.adsabs.harvard.edu/user/settings/token
public actor ADSSource: SourcePlugin {

    // MARK: - Properties

    public nonisolated let metadata = SourceMetadata(
        id: "ads",
        name: "NASA ADS",
        description: "Astrophysics Data System for astronomy and physics",
        rateLimit: RateLimit(requestsPerInterval: 5000, intervalSeconds: 86400),  // 5000/day
        credentialRequirement: .apiKey,
        registrationURL: URL(string: "https://ui.adsabs.harvard.edu/user/settings/token"),
        deduplicationPriority: 30,
        iconName: "sparkles"
    )

    let rateLimiter: RateLimiter
    let baseURL = "https://api.adsabs.harvard.edu/v1"
    let session: URLSession
    let credentialManager: any CredentialProviding

    // MARK: - Initialization

    public init(
        session: URLSession = .shared,
        credentialManager: any CredentialProviding = CredentialManager()
    ) {
        self.session = session
        self.credentialManager = credentialManager
        self.rateLimiter = RateLimiter(
            rateLimit: RateLimit(requestsPerInterval: 5000, intervalSeconds: 86400)
        )
    }

    // MARK: - SourcePlugin

    public func search(query: String) async throws -> [SearchResult] {
        Logger.sources.entering()
        defer { Logger.sources.exiting() }

        guard let apiKey = await credentialManager.apiKey(for: "ads") else {
            throw SourceError.authenticationRequired("ads")
        }

        await rateLimiter.waitIfNeeded()

        var components = URLComponents(string: "\(baseURL)/search/query")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fl", value: "bibcode,title,author,year,pub,abstract,doi,identifier,doctype"),
            URLQueryItem(name: "rows", value: "50"),
            URLQueryItem(name: "sort", value: "score desc"),
        ]

        guard let url = components.url else {
            throw SourceError.invalidRequest("Invalid URL")
        }

        Logger.network.httpRequest("GET", url: url)

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        Logger.network.httpResponse(httpResponse.statusCode, url: url, bytes: data.count)

        if httpResponse.statusCode == 401 {
            throw SourceError.authenticationRequired("ads")
        }

        guard httpResponse.statusCode == 200 else {
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        return try parseResponse(data)
    }

    public func fetchBibTeX(for result: SearchResult) async throws -> BibTeXEntry {
        Logger.sources.entering()
        defer { Logger.sources.exiting() }

        guard let apiKey = await credentialManager.apiKey(for: "ads") else {
            throw SourceError.authenticationRequired("ads")
        }

        guard let bibcode = result.bibcode else {
            throw SourceError.notFound("No bibcode")
        }

        await rateLimiter.waitIfNeeded()

        let url = URL(string: "\(baseURL)/export/bibtex")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["bibcode": [bibcode]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Logger.network.httpRequest("POST", url: url)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        Logger.network.httpResponse(httpResponse.statusCode, url: url, bytes: data.count)

        guard httpResponse.statusCode == 200 else {
            throw SourceError.notFound("Could not fetch BibTeX")
        }

        // ADS returns JSON with "export" field containing BibTeX
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bibtexString = json["export"] as? String else {
            throw SourceError.parseError("Invalid BibTeX response")
        }

        let parser = BibTeXParser()
        let entries = try parser.parseEntries(bibtexString)

        guard let entry = entries.first else {
            throw SourceError.parseError("No entry in BibTeX response")
        }

        return entry
    }

    public nonisolated var supportsRIS: Bool { true }

    public func fetchRIS(for result: SearchResult) async throws -> RISEntry {
        Logger.sources.entering()
        defer { Logger.sources.exiting() }

        guard let apiKey = await credentialManager.apiKey(for: "ads") else {
            throw SourceError.authenticationRequired("ads")
        }

        guard let bibcode = result.bibcode else {
            throw SourceError.notFound("No bibcode")
        }

        await rateLimiter.waitIfNeeded()

        let url = URL(string: "\(baseURL)/export/ris")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["bibcode": [bibcode]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        Logger.network.httpRequest("POST", url: url)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        Logger.network.httpResponse(httpResponse.statusCode, url: url, bytes: data.count)

        guard httpResponse.statusCode == 200 else {
            throw SourceError.notFound("Could not fetch RIS")
        }

        // ADS returns JSON with "export" field containing RIS
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let risString = json["export"] as? String else {
            throw SourceError.parseError("Invalid RIS response")
        }

        let parser = RISParser()
        let entries = try parser.parse(risString)

        guard let entry = entries.first else {
            throw SourceError.parseError("No entry in RIS response")
        }

        return entry
    }

    public nonisolated func normalize(_ entry: BibTeXEntry) -> BibTeXEntry {
        var fields = entry.fields

        // Ensure adsurl is present
        if let bibcode = fields["bibcode"], fields["adsurl"] == nil {
            fields["adsurl"] = "https://ui.adsabs.harvard.edu/abs/\(bibcode)"
        }

        return BibTeXEntry(
            citeKey: entry.citeKey,
            entryType: entry.entryType,
            fields: fields,
            rawBibTeX: entry.rawBibTeX
        )
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> [SearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let docs = response["docs"] as? [[String: Any]] else {
            throw SourceError.parseError("Invalid ADS response")
        }

        return docs.compactMap { parseDoc($0) }
    }

    private func parseDoc(_ doc: [String: Any]) -> SearchResult? {
        guard let bibcode = doc["bibcode"] as? String else { return nil }

        let title = (doc["title"] as? [String])?.first ?? "Untitled"
        let authors = doc["author"] as? [String] ?? []
        let year = doc["year"] as? Int
        let venue = doc["pub"] as? String
        let abstract = doc["abstract"] as? String
        let doi = extractDOI(from: doc)
        let arxivID = extractArXivID(from: doc)

        // Generate PDF URL:
        // - If paper has arXiv ID, use arXiv PDF (free and reliable)
        // - Otherwise, use ADS link gateway for publisher PDF
        let pdfURL: URL?
        if let arxivID = arxivID {
            pdfURL = URL(string: "https://arxiv.org/pdf/\(arxivID).pdf")
        } else {
            pdfURL = URL(string: "https://ui.adsabs.harvard.edu/link_gateway/\(bibcode)/PUB_PDF")
        }

        return SearchResult(
            id: bibcode,
            sourceID: "ads",
            title: title,
            authors: authors,
            year: year,
            venue: venue,
            abstract: abstract,
            doi: doi,
            arxivID: arxivID,
            bibcode: bibcode,
            pdfURL: pdfURL,
            webURL: URL(string: "https://ui.adsabs.harvard.edu/abs/\(bibcode)"),
            bibtexURL: URL(string: "https://ui.adsabs.harvard.edu/abs/\(bibcode)/exportcitation")
        )
    }

    private func extractDOI(from doc: [String: Any]) -> String? {
        if let doi = doc["doi"] as? [String] {
            return doi.first
        }
        return nil
    }

    private func extractArXivID(from doc: [String: Any]) -> String? {
        guard let identifiers = doc["identifier"] as? [String] else { return nil }

        for id in identifiers {
            if id.hasPrefix("arXiv:") {
                return String(id.dropFirst(6))
            }
            if id.range(of: #"^\d{4}\.\d{4,5}"#, options: .regularExpression) != nil {
                return id
            }
        }
        return nil
    }
}
