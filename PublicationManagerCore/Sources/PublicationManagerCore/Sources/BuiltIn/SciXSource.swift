//
//  SciXSource.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-08.
//

import Foundation
import OSLog

// MARK: - SciX Source

/// Source plugin for SciX (Science Explorer).
/// SciX is the ADS team's expanded portal covering Earth science, planetary science,
/// astrophysics, heliophysics, and NASA-funded biological/physical sciences.
/// Requires API key from https://scixplorer.org/user/settings/token
public actor SciXSource: SourcePlugin {

    // MARK: - Properties

    public nonisolated let metadata = SourceMetadata(
        id: "scix",
        name: "SciX",
        description: "Science Explorer - Earth, planetary, helio, and life sciences",
        rateLimit: RateLimit(requestsPerInterval: 5000, intervalSeconds: 86400),  // 5000/day
        credentialRequirement: .apiKey,
        registrationURL: URL(string: "https://scixplorer.org/user/settings/token"),
        deduplicationPriority: 31,  // Slightly lower than ADS (30) for astro papers
        iconName: "globe"
    )

    let rateLimiter: RateLimiter
    let baseURL = "https://api.adsabs.harvard.edu/v1"  // Same API as ADS
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

    public func search(query: String, maxResults: Int = 50) async throws -> [SearchResult] {
        Logger.sources.entering()
        defer { Logger.sources.exiting() }

        guard let apiKey = await credentialManager.apiKey(for: "scix") else {
            throw SourceError.authenticationRequired("scix")
        }

        await rateLimiter.waitIfNeeded()

        var components = URLComponents(string: "\(baseURL)/search/query")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fl", value: "bibcode,title,author,year,pub,abstract,doi,identifier,doctype,esources"),
            URLQueryItem(name: "rows", value: "\(maxResults)"),
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
            throw SourceError.authenticationRequired("scix")
        }

        guard httpResponse.statusCode == 200 else {
            throw SourceError.networkError(URLError(.badServerResponse))
        }

        return try parseResponse(data)
    }

    public func fetchBibTeX(for result: SearchResult) async throws -> BibTeXEntry {
        Logger.sources.entering()
        defer { Logger.sources.exiting() }

        guard let apiKey = await credentialManager.apiKey(for: "scix") else {
            throw SourceError.authenticationRequired("scix")
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

        // SciX/ADS returns JSON with "export" field containing BibTeX
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

        guard let apiKey = await credentialManager.apiKey(for: "scix") else {
            throw SourceError.authenticationRequired("scix")
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

        // SciX/ADS returns JSON with "export" field containing RIS
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

        // Ensure scixurl is present
        if let bibcode = fields["bibcode"], fields["scixurl"] == nil {
            fields["scixurl"] = "https://scixplorer.org/abs/\(bibcode)"
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
            throw SourceError.parseError("Invalid SciX response")
        }

        return docs.compactMap { parseDoc($0) }
    }

    private func parseDoc(_ doc: [String: Any]) -> SearchResult? {
        guard let bibcode = doc["bibcode"] as? String else { return nil }

        let title = (doc["title"] as? [String])?.first ?? "Untitled"
        let authors = doc["author"] as? [String] ?? []
        let year = (doc["year"] as? Int) ?? (doc["year"] as? String).flatMap { Int($0) }
        let venue = doc["pub"] as? String
        let abstract = doc["abstract"] as? String
        let doi = extractDOI(from: doc)
        let arxivID = extractArXivID(from: doc)

        // Build PDF links from esources field
        let pdfLinks = buildPDFLinks(from: doc, bibcode: bibcode, arxivID: arxivID)

        return SearchResult(
            id: bibcode,
            sourceID: "scix",
            title: title,
            authors: authors,
            year: year,
            venue: venue,
            abstract: abstract,
            doi: doi,
            arxivID: arxivID,
            bibcode: bibcode,
            pdfLinks: pdfLinks,
            webURL: URL(string: "https://scixplorer.org/abs/\(bibcode)"),
            bibtexURL: URL(string: "https://scixplorer.org/abs/\(bibcode)/exportcitation")
        )
    }

    /// Build PDF links from SciX/ADS esources field
    ///
    /// Note: We avoid link_gateway URLs (e.g., /link_gateway/{bibcode}/PUB_PDF)
    /// because they are unreliable and often return 404. Instead:
    /// - For preprints: use direct arXiv URLs
    /// - For publisher PDFs: use DOI resolver (https://doi.org/{doi})
    /// - For SciX scans: these are hosted directly and work reliably
    private func buildPDFLinks(from doc: [String: Any], bibcode: String, arxivID: String?) -> [PDFLink] {
        var links: [PDFLink] = []
        let doi = extractDOI(from: doc)

        // Get esources array from response
        let esources = doc["esources"] as? [String] ?? []

        // Track what we have
        var hasPreprint = false
        var hasPublisher = false

        // Map esource types to our PDFLinkType
        for esource in esources {
            let upper = esource.uppercased()

            if upper == "EPRINT_PDF" {
                // Preprint/arXiv PDF - use direct arXiv URL
                if let arxivID = arxivID,
                   let url = URL(string: "https://arxiv.org/pdf/\(arxivID).pdf") {
                    links.append(PDFLink(url: url, type: .preprint, sourceID: "scix"))
                    hasPreprint = true
                }
            } else if upper == "PUB_PDF" || upper == "PUB_HTML" {
                // Publisher PDF - use DOI resolver (much more reliable than link_gateway)
                if let doi = doi, !doi.isEmpty,
                   let url = URL(string: "https://doi.org/\(doi)") {
                    links.append(PDFLink(url: url, type: .publisher, sourceID: "scix"))
                    hasPublisher = true
                }
            } else if upper == "ADS_PDF" || upper == "ADS_SCAN" {
                // SciX/ADS-hosted scans are reliable (hosted directly)
                if let url = URL(string: "https://scixplorer.org/link_gateway/\(bibcode)/ADS_PDF") {
                    links.append(PDFLink(url: url, type: .adsScan, sourceID: "scix"))
                }
            }
            // Note: We skip AUTHOR_PDF as link_gateway for it is unreliable
        }

        // If no esources but we have arXiv ID, add preprint link
        if !hasPreprint, let arxivID = arxivID,
           let url = URL(string: "https://arxiv.org/pdf/\(arxivID).pdf") {
            links.append(PDFLink(url: url, type: .preprint, sourceID: "scix"))
        }

        // If no publisher link but we have DOI, add it
        if !hasPublisher, let doi = doi, !doi.isEmpty,
           let url = URL(string: "https://doi.org/\(doi)") {
            links.append(PDFLink(url: url, type: .publisher, sourceID: "scix"))
        }

        return links
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

// MARK: - BrowserURLProvider Conformance

extension SciXSource: BrowserURLProvider {

    public static var sourceID: String { "scix" }

    /// Build the best URL to open in browser for interactive PDF fetch.
    ///
    /// Priority order for browser access (targeting published version):
    /// 1. DOI resolver - redirects to publisher where user can authenticate
    /// 2. SciX abstract page - shows all available full text sources
    ///
    /// - Parameter publication: The publication to find a PDF URL for
    /// - Returns: A URL to open in the browser, or nil if this source can't help
    public static func browserPDFURL(for publication: CDPublication) -> URL? {
        // Priority 1: DOI resolver - always redirects to publisher
        if let doi = publication.doi, !doi.isEmpty {
            Logger.pdfBrowser.debug("SciX: Using DOI resolver for: \(doi)")
            return URL(string: "https://doi.org/\(doi)")
        }

        // Priority 2: SciX abstract page - shows all available full text sources
        if let bibcode = publication.bibcode {
            Logger.pdfBrowser.debug("SciX: Using abstract page for bibcode: \(bibcode)")
            return URL(string: "https://scixplorer.org/abs/\(bibcode)/abstract")
        }

        return nil
    }
}
