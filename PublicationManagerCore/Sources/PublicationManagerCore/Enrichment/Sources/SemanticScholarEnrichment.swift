//
//  SemanticScholarEnrichment.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog

// MARK: - Semantic Scholar Enrichment Plugin

/// Extension to make SemanticScholarSource conform to EnrichmentPlugin.
///
/// Semantic Scholar provides rich enrichment data including:
/// - Citation count and reference count
/// - Full references list with author/year/venue
/// - Full citations list (papers that cite this one)
/// - Abstract
/// - Open access PDF URLs
/// - Author statistics (h-index, citation count, paper count)
extension SemanticScholarSource: EnrichmentPlugin {

    // MARK: - Capabilities

    public nonisolated var enrichmentCapabilities: EnrichmentCapabilities {
        [.citationCount, .references, .citations, .abstract, .pdfURL, .authorStats]
    }

    // MARK: - Enrichment

    public func enrich(
        identifiers: [IdentifierType: String],
        existingData: EnrichmentData?
    ) async throws -> EnrichmentResult {
        Logger.sources.info("SemanticScholar: enriching paper with identifiers: \(identifiers)")

        // Resolve to S2 paper ID if needed
        let paperID = try await resolvePaperID(from: identifiers)

        // Fetch paper details with all enrichment fields
        let enrichmentFields = [
            "paperId", "title", "abstract", "year", "venue",
            "citationCount", "referenceCount", "openAccessPdf",
            "references", "references.paperId", "references.title",
            "references.authors", "references.year", "references.venue",
            "references.externalIds", "references.citationCount", "references.openAccessPdf",
            "citations", "citations.paperId", "citations.title",
            "citations.authors", "citations.year", "citations.venue",
            "citations.externalIds", "citations.citationCount", "citations.openAccessPdf",
            "authors", "authors.authorId", "authors.name",
            "authors.hIndex", "authors.citationCount", "authors.paperCount",
            "authors.affiliations"
        ].joined(separator: ",")

        let url = URL(string: "\(baseURL)/paper/\(paperID)?fields=\(enrichmentFields)")!

        var request = URLRequest(url: url)
        if let apiKey = await credentialManager.apiKey(for: "semanticscholar") {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }

        await rateLimiter.waitIfNeeded()
        Logger.network.httpRequest("GET", url: url)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnrichmentError.networkError("Invalid response")
        }

        Logger.network.httpResponse(httpResponse.statusCode, url: url, bytes: data.count)

        switch httpResponse.statusCode {
        case 200:
            break
        case 404:
            throw EnrichmentError.notFound
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw EnrichmentError.rateLimited(retryAfter: retryAfter)
        default:
            throw EnrichmentError.networkError("HTTP \(httpResponse.statusCode)")
        }

        // Parse enrichment response
        let enrichmentData = try parseEnrichmentResponse(data)

        // Extract any additional identifiers found
        var resolvedIdentifiers = identifiers
        resolvedIdentifiers[.semanticScholar] = paperID

        Logger.sources.info("SemanticScholar: enrichment complete - citations: \(enrichmentData.citationCount ?? 0)")

        // Merge: new data takes precedence, but fill gaps from existing
        let finalData: EnrichmentData
        if let existing = existingData {
            finalData = enrichmentData.merging(with: existing)
        } else {
            finalData = enrichmentData
        }

        return EnrichmentResult(
            data: finalData,
            resolvedIdentifiers: resolvedIdentifiers
        )
    }

    // MARK: - Identifier Resolution

    public func resolveIdentifier(
        from identifiers: [IdentifierType: String]
    ) async throws -> [IdentifierType: String] {
        // If we already have an S2 ID, return as-is
        if identifiers[.semanticScholar] != nil {
            return identifiers
        }

        // Try to resolve using supported identifiers
        let paperID = try await resolvePaperID(from: identifiers)

        var result = identifiers
        result[.semanticScholar] = paperID
        return result
    }

    // MARK: - Private Helpers

    /// Resolve identifiers to S2 paper ID
    private func resolvePaperID(from identifiers: [IdentifierType: String]) async throws -> String {
        // Already have S2 ID
        if let s2ID = identifiers[.semanticScholar] {
            return s2ID
        }

        // Try DOI (most reliable)
        if let doi = identifiers[.doi] {
            return "DOI:\(doi)"
        }

        // Try arXiv ID
        if let arxiv = identifiers[.arxiv] {
            return "ARXIV:\(arxiv)"
        }

        // Try PubMed ID
        if let pmid = identifiers[.pmid] {
            return "PMID:\(pmid)"
        }

        // No supported identifier
        throw EnrichmentError.noIdentifier
    }

    /// Parse enrichment response from S2 API
    private func parseEnrichmentResponse(_ data: Data) throws -> EnrichmentData {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EnrichmentError.parseError("Invalid JSON response")
        }

        // Citation and reference counts
        let citationCount = json["citationCount"] as? Int
        let referenceCount = json["referenceCount"] as? Int

        // Abstract
        let abstract = json["abstract"] as? String

        // PDF URL
        var pdfURLs: [URL]?
        if let openAccess = json["openAccessPdf"] as? [String: Any],
           let urlString = openAccess["url"] as? String,
           let url = URL(string: urlString) {
            pdfURLs = [url]
        }

        // Parse references
        let references: [PaperStub]?
        if let refsArray = json["references"] as? [[String: Any]] {
            references = refsArray.compactMap { parsePaperStub($0) }
        } else {
            references = nil
        }

        // Parse citations
        let citations: [PaperStub]?
        if let citesArray = json["citations"] as? [[String: Any]] {
            citations = citesArray.compactMap { parsePaperStub($0) }
        } else {
            citations = nil
        }

        // Parse author stats
        let authorStats: [AuthorStats]?
        if let authorsArray = json["authors"] as? [[String: Any]] {
            authorStats = authorsArray.compactMap { parseAuthorStats($0) }
        } else {
            authorStats = nil
        }

        return EnrichmentData(
            citationCount: citationCount,
            referenceCount: referenceCount,
            references: references,
            citations: citations,
            abstract: abstract,
            pdfURLs: pdfURLs,
            authorStats: authorStats,
            source: .semanticScholar
        )
    }

    /// Parse a paper stub from S2 reference/citation data
    private func parsePaperStub(_ paper: [String: Any]) -> PaperStub? {
        guard let paperId = paper["paperId"] as? String,
              let title = paper["title"] as? String else { return nil }

        let authors: [String]
        if let authorsArray = paper["authors"] as? [[String: Any]] {
            authors = authorsArray.compactMap { $0["name"] as? String }
        } else {
            authors = []
        }

        let year = paper["year"] as? Int
        let venue = paper["venue"] as? String
        let citationCount = paper["citationCount"] as? Int

        // External IDs
        let externalIds = paper["externalIds"] as? [String: Any] ?? [:]
        let doi = externalIds["DOI"] as? String
        let arxivID = externalIds["ArXiv"] as? String

        // Open access
        var isOpenAccess: Bool?
        if let openAccessPdf = paper["openAccessPdf"] as? [String: Any] {
            isOpenAccess = openAccessPdf["url"] != nil
        }

        return PaperStub(
            id: paperId,
            title: title,
            authors: authors,
            year: year,
            venue: venue,
            doi: doi,
            arxivID: arxivID,
            citationCount: citationCount,
            isOpenAccess: isOpenAccess
        )
    }

    /// Parse author statistics from S2 author data
    private func parseAuthorStats(_ author: [String: Any]) -> AuthorStats? {
        guard let authorId = author["authorId"] as? String,
              let name = author["name"] as? String else { return nil }

        let hIndex = author["hIndex"] as? Int
        let citationCount = author["citationCount"] as? Int
        let paperCount = author["paperCount"] as? Int

        var affiliations: [String]?
        if let affs = author["affiliations"] as? [[String: Any]], !affs.isEmpty {
            let names = affs.compactMap { $0["name"] as? String }
            affiliations = names.isEmpty ? nil : names
        }

        return AuthorStats(
            authorID: authorId,
            name: name,
            hIndex: hIndex,
            citationCount: citationCount,
            paperCount: paperCount,
            affiliations: affiliations
        )
    }
}
