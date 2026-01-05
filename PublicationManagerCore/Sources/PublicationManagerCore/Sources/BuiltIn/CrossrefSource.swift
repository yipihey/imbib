//
//  CrossrefSource.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog

// MARK: - Crossref Source

/// Source plugin for Crossref DOI registry.
/// Uses the Crossref REST API.
public actor CrossrefSource: SourcePlugin {

    // MARK: - Properties

    public nonisolated let metadata = SourceMetadata(
        id: "crossref",
        name: "Crossref",
        description: "DOI registration agency with metadata for scholarly content",
        rateLimit: RateLimit(requestsPerInterval: 50, intervalSeconds: 1),
        credentialRequirement: .emailOptional,
        registrationURL: nil,
        deduplicationPriority: 10,  // Highest priority (publisher source)
        iconName: "link"
    )

    private let rateLimiter: RateLimiter
    private let baseURL = "https://api.crossref.org/works"
    private let session: URLSession
    private let email: String?

    // MARK: - Initialization

    public init(session: URLSession = .shared, email: String? = nil) {
        self.session = session
        self.email = email
        self.rateLimiter = RateLimiter(rateLimit: RateLimit(requestsPerInterval: 50, intervalSeconds: 1))
    }

    // MARK: - SourcePlugin

    public func search(query: String) async throws -> [SearchResult] {
        Logger.sources.entering()
        defer { Logger.sources.exiting() }

        await rateLimiter.waitIfNeeded()

        var components = URLComponents(string: baseURL)!
        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "rows", value: "50"),
            URLQueryItem(name: "select", value: "DOI,title,author,published-print,published-online,container-title,abstract,link,type"),
        ]

        // Add polite pool email if available
        if let email = email {
            queryItems.append(URLQueryItem(name: "mailto", value: email))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw SourceError.invalidRequest("Invalid URL")
        }

        Logger.network.httpRequest("GET", url: url)

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

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

        guard let doi = result.doi else {
            throw SourceError.notFound("No DOI available")
        }

        await rateLimiter.waitIfNeeded()

        // Use content negotiation to get BibTeX directly
        let url = URL(string: "https://doi.org/\(doi)")!

        var request = URLRequest(url: url)
        request.setValue("application/x-bibtex", forHTTPHeaderField: "Accept")

        Logger.network.httpRequest("GET", url: url)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        Logger.network.httpResponse(httpResponse.statusCode, url: url, bytes: data.count)

        guard httpResponse.statusCode == 200,
              let bibtexString = String(data: data, encoding: .utf8) else {
            throw SourceError.notFound("Could not fetch BibTeX")
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

        guard let doi = result.doi else {
            throw SourceError.notFound("No DOI available")
        }

        await rateLimiter.waitIfNeeded()

        // Use content negotiation to get RIS directly
        let url = URL(string: "https://doi.org/\(doi)")!

        var request = URLRequest(url: url)
        request.setValue("application/x-research-info-systems", forHTTPHeaderField: "Accept")

        Logger.network.httpRequest("GET", url: url)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        Logger.network.httpResponse(httpResponse.statusCode, url: url, bytes: data.count)

        guard httpResponse.statusCode == 200,
              let risString = String(data: data, encoding: .utf8) else {
            throw SourceError.notFound("Could not fetch RIS")
        }

        let parser = RISParser()
        let entries = try parser.parse(risString)

        guard let entry = entries.first else {
            throw SourceError.parseError("No entry in RIS response")
        }

        return entry
    }

    public nonisolated func normalize(_ entry: BibTeXEntry) -> BibTeXEntry {
        // Crossref entries are generally well-formed
        entry
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> [SearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let items = message["items"] as? [[String: Any]] else {
            throw SourceError.parseError("Invalid Crossref response")
        }

        return items.compactMap { parseItem($0) }
    }

    private func parseItem(_ item: [String: Any]) -> SearchResult? {
        guard let doi = item["DOI"] as? String else { return nil }

        let title = extractTitle(from: item)
        let authors = extractAuthors(from: item)
        let year = extractYear(from: item)
        let venue = extractVenue(from: item)
        let abstract = item["abstract"] as? String
        let pdfURL = extractPDFURL(from: item)

        return SearchResult(
            id: doi,
            sourceID: "crossref",
            title: title,
            authors: authors,
            year: year,
            venue: venue,
            abstract: abstract?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression),
            doi: doi,
            pdfURL: pdfURL,
            webURL: URL(string: "https://doi.org/\(doi)"),
            bibtexURL: URL(string: "https://doi.org/\(doi)")
        )
    }

    private func extractTitle(from item: [String: Any]) -> String {
        if let titles = item["title"] as? [String], let first = titles.first {
            return first
        }
        return "Untitled"
    }

    private func extractAuthors(from item: [String: Any]) -> [String] {
        guard let authors = item["author"] as? [[String: Any]] else { return [] }

        return authors.compactMap { author -> String? in
            let given = author["given"] as? String ?? ""
            let family = author["family"] as? String ?? ""
            if family.isEmpty { return nil }
            return given.isEmpty ? family : "\(given) \(family)"
        }
    }

    private func extractYear(from item: [String: Any]) -> Int? {
        // Try published-print first, then published-online
        for key in ["published-print", "published-online", "created"] {
            if let dateInfo = item[key] as? [String: Any],
               let dateParts = dateInfo["date-parts"] as? [[Int]],
               let parts = dateParts.first,
               let year = parts.first {
                return year
            }
        }
        return nil
    }

    private func extractVenue(from item: [String: Any]) -> String? {
        if let container = item["container-title"] as? [String], let first = container.first {
            return first
        }
        return nil
    }

    private func extractPDFURL(from item: [String: Any]) -> URL? {
        guard let links = item["link"] as? [[String: Any]] else { return nil }

        for link in links {
            if let contentType = link["content-type"] as? String,
               contentType == "application/pdf",
               let urlString = link["URL"] as? String {
                return URL(string: urlString)
            }
        }
        return nil
    }
}
