//
//  INSPIRESource.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-08.
//

import Foundation
import OSLog

// MARK: - INSPIRE HEP Source

/// Source plugin for INSPIRE HEP (High Energy Physics literature database).
/// No API key required - public access.
/// Rate limit: 15 requests per 5 seconds.
public actor INSPIRESource: SourcePlugin {

    // MARK: - Properties

    public nonisolated let metadata = SourceMetadata(
        id: "inspire",
        name: "INSPIRE HEP",
        description: "High Energy Physics literature database",
        rateLimit: RateLimit(requestsPerInterval: 15, intervalSeconds: 5),
        credentialRequirement: .none,
        registrationURL: nil,
        deduplicationPriority: 25,  // Higher priority than ADS (30) for HEP papers
        iconName: "atom"
    )

    let rateLimiter: RateLimiter
    let baseURL = "https://inspirehep.net/api"
    let session: URLSession

    // MARK: - Initialization

    public init(session: URLSession = .shared) {
        self.session = session
        self.rateLimiter = RateLimiter(
            rateLimit: RateLimit(requestsPerInterval: 15, intervalSeconds: 5)
        )
    }

    // MARK: - SourcePlugin

    public func search(query: String, maxResults: Int = 50) async throws -> [SearchResult] {
        Logger.sources.entering()
        defer { Logger.sources.exiting() }

        await rateLimiter.waitIfNeeded()

        var components = URLComponents(string: "\(baseURL)/literature")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "size", value: "\(min(maxResults, 100))"),
            URLQueryItem(name: "sort", value: "mostrecent"),
            URLQueryItem(name: "fields", value: "titles,authors,publication_info,arxiv_eprints,dois,abstracts,documents,citation_count,control_number,external_system_identifiers")
        ]

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
            if httpResponse.statusCode == 429 {
                throw SourceError.rateLimited(retryAfter: 5)
            }
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        return try parseSearchResponse(data)
    }

    public func fetchBibTeX(for result: SearchResult) async throws -> BibTeXEntry {
        Logger.sources.entering()
        defer { Logger.sources.exiting() }

        // Extract INSPIRE recid from result ID (INSPIRE IDs are numeric)
        guard let recid = extractRecordID(from: result.id) else {
            throw SourceError.notFound("No INSPIRE record ID")
        }

        await rateLimiter.waitIfNeeded()

        var components = URLComponents(string: "\(baseURL)/literature")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "recid:\(recid)"),
            URLQueryItem(name: "format", value: "bibtex")
        ]

        guard let url = components.url else {
            throw SourceError.invalidRequest("Invalid URL")
        }

        Logger.network.httpRequest("GET", url: url)

        var request = URLRequest(url: url)
        request.setValue("application/x-bibtex", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        Logger.network.httpResponse(httpResponse.statusCode, url: url, bytes: data.count)

        guard httpResponse.statusCode == 200 else {
            throw SourceError.notFound("Could not fetch BibTeX")
        }

        guard let bibtexString = String(data: data, encoding: .utf8) else {
            throw SourceError.parseError("Invalid BibTeX encoding")
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

        guard let recid = extractRecordID(from: result.id) else {
            throw SourceError.notFound("No INSPIRE record ID")
        }

        await rateLimiter.waitIfNeeded()

        var components = URLComponents(string: "\(baseURL)/literature")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "recid:\(recid)"),
            URLQueryItem(name: "format", value: "ris")
        ]

        guard let url = components.url else {
            throw SourceError.invalidRequest("Invalid URL")
        }

        Logger.network.httpRequest("GET", url: url)

        var request = URLRequest(url: url)
        request.setValue("application/x-research-info-systems", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        Logger.network.httpResponse(httpResponse.statusCode, url: url, bytes: data.count)

        guard httpResponse.statusCode == 200 else {
            throw SourceError.notFound("Could not fetch RIS")
        }

        guard let risString = String(data: data, encoding: .utf8) else {
            throw SourceError.parseError("Invalid RIS encoding")
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

        // Add INSPIRE URL if we have a citation key that might be a recid
        if fields["inspireurl"] == nil {
            // Try to extract recid from citation key or eprint field
            if let eprint = fields["eprint"] {
                fields["inspireurl"] = "https://inspirehep.net/literature/\(eprint)"
            }
        }

        return BibTeXEntry(
            citeKey: entry.citeKey,
            entryType: entry.entryType,
            fields: fields,
            rawBibTeX: entry.rawBibTeX
        )
    }

    // MARK: - Response Parsing

    private func parseSearchResponse(_ data: Data) throws -> [SearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = json["hits"] as? [String: Any],
              let hitsList = hits["hits"] as? [[String: Any]] else {
            throw SourceError.parseError("Invalid INSPIRE response")
        }

        return hitsList.compactMap { parseHit($0) }
    }

    private func parseHit(_ hit: [String: Any]) -> SearchResult? {
        // Extract record ID (control_number)
        guard let metadata = hit["metadata"] as? [String: Any],
              let controlNumber = metadata["control_number"] as? Int else {
            return nil
        }

        let recid = String(controlNumber)

        // Title
        let title: String
        if let titles = metadata["titles"] as? [[String: Any]],
           let firstTitle = titles.first,
           let titleText = firstTitle["title"] as? String {
            title = titleText
        } else {
            title = "Untitled"
        }

        // Authors
        var authors: [String] = []
        if let authorsList = metadata["authors"] as? [[String: Any]] {
            authors = authorsList.compactMap { authorDict -> String? in
                authorDict["full_name"] as? String
            }
        }

        // Year and venue from publication_info
        var year: Int?
        var venue: String?
        if let pubInfo = metadata["publication_info"] as? [[String: Any]],
           let firstPub = pubInfo.first {
            year = firstPub["year"] as? Int
            venue = firstPub["journal_title"] as? String
        }

        // Abstract
        var abstract: String?
        if let abstracts = metadata["abstracts"] as? [[String: Any]],
           let firstAbstract = abstracts.first,
           let abstractText = firstAbstract["value"] as? String {
            abstract = abstractText
        }

        // DOI
        var doi: String?
        if let dois = metadata["dois"] as? [[String: Any]],
           let firstDOI = dois.first,
           let doiValue = firstDOI["value"] as? String {
            doi = doiValue
        }

        // arXiv ID
        var arxivID: String?
        if let arxivEprints = metadata["arxiv_eprints"] as? [[String: Any]],
           let firstArxiv = arxivEprints.first,
           let arxivValue = firstArxiv["value"] as? String {
            arxivID = arxivValue
        }

        // Citation count (available for future enrichment)
        _ = metadata["citation_count"] as? Int

        // Build PDF links
        let pdfLinks = buildPDFLinks(from: metadata, arxivID: arxivID, doi: doi)

        return SearchResult(
            id: recid,
            sourceID: "inspire",
            title: title,
            authors: authors,
            year: year,
            venue: venue,
            abstract: abstract,
            doi: doi,
            arxivID: arxivID,
            pdfLinks: pdfLinks,
            webURL: URL(string: "https://inspirehep.net/literature/\(recid)"),
            bibtexURL: URL(string: "https://inspirehep.net/api/literature?q=recid:\(recid)&format=bibtex")
        )
    }

    /// Build PDF links from INSPIRE metadata
    private func buildPDFLinks(from metadata: [String: Any], arxivID: String?, doi: String?) -> [PDFLink] {
        var links: [PDFLink] = []

        // Priority 1: arXiv PDF (most reliable, free)
        if let arxivID = arxivID,
           let url = URL(string: "https://arxiv.org/pdf/\(arxivID).pdf") {
            links.append(PDFLink(url: url, type: .preprint, sourceID: "inspire"))
        }

        // Priority 2: Direct document links from INSPIRE
        if let documents = metadata["documents"] as? [[String: Any]] {
            for doc in documents {
                if let urlString = doc["url"] as? String,
                   let url = URL(string: urlString),
                   urlString.hasSuffix(".pdf") {
                    // Avoid duplicates
                    if !links.contains(where: { $0.url == url }) {
                        links.append(PDFLink(url: url, type: .author, sourceID: "inspire"))
                    }
                }
            }
        }

        // Priority 3: DOI resolver for publisher version
        if let doi = doi,
           let url = URL(string: "https://doi.org/\(doi)") {
            links.append(PDFLink(url: url, type: .publisher, sourceID: "inspire"))
        }

        return links
    }

    /// Extract numeric record ID from various ID formats
    private func extractRecordID(from id: String) -> String? {
        // If already numeric, use as-is
        if Int(id) != nil {
            return id
        }

        // Try to extract from URL format
        if let url = URL(string: id),
           let lastComponent = url.pathComponents.last,
           Int(lastComponent) != nil {
            return lastComponent
        }

        return nil
    }
}

// MARK: - BrowserURLProvider Conformance

extension INSPIRESource: BrowserURLProvider {

    public static var sourceID: String { "inspire" }

    /// Build the best URL to open in browser for interactive PDF fetch.
    ///
    /// For INSPIRE papers:
    /// 1. DOI resolver - redirects to publisher where user can authenticate
    /// 2. INSPIRE literature page - shows all available full text links
    ///
    /// - Parameter publication: The publication to find a PDF URL for
    /// - Returns: A URL to open in the browser, or nil if this source can't help
    public static func browserPDFURL(for publication: CDPublication) -> URL? {
        // Priority 1: DOI resolver
        if let doi = publication.doi, !doi.isEmpty {
            Logger.pdfBrowser.debug("INSPIRE: Using DOI resolver for: \(doi)")
            return URL(string: "https://doi.org/\(doi)")
        }

        // Priority 2: INSPIRE literature page (if we have an INSPIRE recid)
        // The recid might be stored in the fields or derivable from identifiers
        if let arxivID = publication.arxivID {
            // INSPIRE indexes by arXiv ID, so we can search for it
            Logger.pdfBrowser.debug("INSPIRE: Using arXiv search for: \(arxivID)")
            return URL(string: "https://inspirehep.net/literature?q=arxiv:\(arxivID)")
        }

        return nil
    }
}
