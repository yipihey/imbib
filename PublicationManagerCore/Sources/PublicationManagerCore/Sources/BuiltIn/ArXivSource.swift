//
//  ArXivSource.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog

// MARK: - arXiv Source

/// Source plugin for arXiv preprint server.
/// Uses the arXiv API (Atom feed format).
public actor ArXivSource: SourcePlugin {

    // MARK: - Properties

    public nonisolated let metadata = SourceMetadata(
        id: "arxiv",
        name: "arXiv",
        description: "Open-access preprint server for physics, math, CS, and more",
        rateLimit: RateLimit(requestsPerInterval: 1, intervalSeconds: 3),
        credentialRequirement: .none,
        registrationURL: nil,
        deduplicationPriority: 60,
        iconName: "doc.text"
    )

    private let rateLimiter: RateLimiter
    private let baseURL = "https://export.arxiv.org/api/query"
    private let session: URLSession

    // MARK: - Initialization

    public init(session: URLSession = .shared) {
        self.session = session
        self.rateLimiter = RateLimiter(rateLimit: RateLimit(requestsPerInterval: 1, intervalSeconds: 3))
    }

    // MARK: - SourcePlugin

    public func search(query: String) async throws -> [SearchResult] {
        Logger.sources.entering()
        defer { Logger.sources.exiting() }

        await rateLimiter.waitIfNeeded()

        // Build URL
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "search_query", value: "all:\(query)"),
            URLQueryItem(name: "start", value: "0"),
            URLQueryItem(name: "max_results", value: "50"),
            URLQueryItem(name: "sortBy", value: "relevance"),
            URLQueryItem(name: "sortOrder", value: "descending"),
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

        return try parseAtomFeed(data)
    }

    public func fetchBibTeX(for result: SearchResult) async throws -> BibTeXEntry {
        Logger.sources.entering()
        defer { Logger.sources.exiting() }

        // arXiv doesn't have a direct BibTeX endpoint, so we construct it
        return constructBibTeXEntry(from: result)
    }

    public nonisolated func normalize(_ entry: BibTeXEntry) -> BibTeXEntry {
        var fields = entry.fields

        // Add arXiv-specific fields
        if let arxivID = extractArXivID(from: entry) {
            fields["eprint"] = arxivID
            fields["archiveprefix"] = "arXiv"

            // Extract primary category if present
            if let category = extractCategory(from: arxivID) {
                fields["primaryclass"] = category
            }
        }

        return BibTeXEntry(
            citeKey: entry.citeKey,
            entryType: entry.entryType,
            fields: fields,
            rawBibTeX: entry.rawBibTeX
        )
    }

    // MARK: - Atom Feed Parsing

    private func parseAtomFeed(_ data: Data) throws -> [SearchResult] {
        let parser = ArXivAtomParser()
        return try parser.parse(data)
    }

    private func constructBibTeXEntry(from result: SearchResult) -> BibTeXEntry {
        var fields: [String: String] = [:]

        fields["title"] = result.title
        fields["author"] = result.authors.joined(separator: " and ")
        if let year = result.year {
            fields["year"] = String(year)
        }
        if let abstract = result.abstract {
            fields["abstract"] = abstract
        }
        if let arxivID = result.arxivID {
            fields["eprint"] = arxivID
            fields["archiveprefix"] = "arXiv"
        }
        if let url = result.webURL {
            fields["url"] = url.absoluteString
        }
        if let doi = result.doi {
            fields["doi"] = doi
        }

        let citeKey = CiteKeyGenerator().generate(from: result)

        return BibTeXEntry(
            citeKey: citeKey,
            entryType: "article",
            fields: fields
        )
    }

    private nonisolated func extractArXivID(from entry: BibTeXEntry) -> String? {
        if let eprint = entry.fields["eprint"] {
            return eprint
        }
        if let arxivid = entry.fields["arxivid"] {
            return arxivid
        }
        // Try to extract from URL
        if let url = entry.fields["url"], url.contains("arxiv.org") {
            if let match = url.range(of: #"\d{4}\.\d{4,5}(v\d+)?"#, options: .regularExpression) {
                return String(url[match])
            }
        }
        return nil
    }

    private nonisolated func extractCategory(from arxivID: String) -> String? {
        // Old format: hep-th/9901001
        if arxivID.contains("/") {
            return arxivID.components(separatedBy: "/").first
        }
        return nil
    }
}

// MARK: - Atom Parser

private class ArXivAtomParser: NSObject, XMLParserDelegate {

    private var results: [SearchResult] = []
    private var currentEntry: EntryData?
    private var currentElement: String = ""
    private var currentText: String = ""
    private var currentAuthors: [String] = []
    private var currentLinks: [String: String] = [:]

    struct EntryData {
        var id: String = ""
        var title: String = ""
        var summary: String = ""
        var published: String = ""
        var doi: String?
    }

    func parse(_ data: Data) throws -> [SearchResult] {
        results = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return results
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""

        if elementName == "entry" {
            currentEntry = EntryData()
            currentAuthors = []
            currentLinks = [:]
        } else if elementName == "link", let href = attributeDict["href"] {
            let rel = attributeDict["rel"] ?? "alternate"
            let type = attributeDict["type"] ?? ""
            if rel == "alternate" {
                currentLinks["web"] = href
            } else if type == "application/pdf" {
                currentLinks["pdf"] = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if elementName == "entry", var entry = currentEntry {
            // Build SearchResult
            let arxivID = extractArXivID(from: entry.id)
            let year = extractYear(from: entry.published)

            let result = SearchResult(
                id: arxivID ?? entry.id,
                sourceID: "arxiv",
                title: cleanTitle(entry.title),
                authors: currentAuthors,
                year: year,
                venue: "arXiv",
                abstract: entry.summary,
                doi: entry.doi,
                arxivID: arxivID,
                pdfURL: currentLinks["pdf"].flatMap { URL(string: $0) },
                webURL: currentLinks["web"].flatMap { URL(string: $0) }
            )
            results.append(result)
            currentEntry = nil

        } else if currentEntry != nil {
            switch elementName {
            case "id":
                currentEntry?.id = text
            case "title":
                currentEntry?.title = text
            case "summary":
                currentEntry?.summary = text
            case "published":
                currentEntry?.published = text
            case "name":
                currentAuthors.append(text)
            case "arxiv:doi":
                currentEntry?.doi = text
            default:
                break
            }
        }
    }

    private func extractArXivID(from idURL: String) -> String? {
        // ID format: http://arxiv.org/abs/2301.12345v1
        if let range = idURL.range(of: #"\d{4}\.\d{4,5}(v\d+)?"#, options: .regularExpression) {
            return String(idURL[range])
        }
        // Old format
        if let range = idURL.range(of: #"[a-z-]+/\d{7}"#, options: .regularExpression) {
            return String(idURL[range])
        }
        return nil
    }

    private func extractYear(from dateString: String) -> Int? {
        // Format: 2023-01-15T12:00:00Z
        if dateString.count >= 4, let year = Int(dateString.prefix(4)) {
            return year
        }
        return nil
    }

    private func cleanTitle(_ title: String) -> String {
        // Remove newlines and extra whitespace
        title.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
