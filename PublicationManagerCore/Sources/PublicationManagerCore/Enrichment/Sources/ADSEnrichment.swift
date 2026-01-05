//
//  ADSEnrichment.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog

// MARK: - ADS Enrichment Plugin

/// Extension to make ADSSource conform to EnrichmentPlugin.
///
/// ADS provides enrichment data including:
/// - Citation count
/// - Reference count and list
/// - Abstract
extension ADSSource: EnrichmentPlugin {

    // MARK: - Capabilities

    public nonisolated var enrichmentCapabilities: EnrichmentCapabilities {
        [.citationCount, .references, .abstract]
    }

    // MARK: - Enrichment

    public func enrich(
        identifiers: [IdentifierType: String],
        existingData: EnrichmentData?
    ) async throws -> EnrichmentResult {
        Logger.sources.info("ADS: enriching paper with identifiers: \(identifiers)")

        // Get API key
        guard let apiKey = await credentialManager.apiKey(for: "ads") else {
            throw EnrichmentError.authenticationRequired("ads")
        }

        // Resolve bibcode from identifiers
        let bibcode = try resolveBibcode(from: identifiers)

        await rateLimiter.waitIfNeeded()

        // Build search URL to get enrichment fields
        var components = URLComponents(string: "\(baseURL)/search/query")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "bibcode:\(bibcode)"),
            URLQueryItem(name: "fl", value: "bibcode,citation_count,abstract,reference"),
            URLQueryItem(name: "rows", value: "1"),
        ]

        guard let url = components.url else {
            throw EnrichmentError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        Logger.network.httpRequest("GET", url: url)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnrichmentError.networkError("Invalid response")
        }

        Logger.network.httpResponse(httpResponse.statusCode, url: url, bytes: data.count)

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw EnrichmentError.authenticationRequired("ads")
        case 404:
            throw EnrichmentError.notFound
        case 429:
            throw EnrichmentError.rateLimited(retryAfter: nil)
        default:
            throw EnrichmentError.networkError("HTTP \(httpResponse.statusCode)")
        }

        // Parse enrichment response
        let enrichmentData = try parseEnrichmentResponse(data)

        // Resolved identifiers include bibcode
        var resolvedIdentifiers = identifiers
        resolvedIdentifiers[.bibcode] = bibcode

        Logger.sources.info("ADS: enrichment complete - citations: \(enrichmentData.citationCount ?? 0)")

        // Merge with existing data
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
        // If we already have a bibcode, return as-is
        if identifiers[.bibcode] != nil {
            return identifiers
        }

        // ADS can resolve DOI to bibcode via search
        if let doi = identifiers[.doi] {
            var result = identifiers
            // DOI search in ADS uses doi: prefix
            result[.bibcode] = "doi:\(doi)"
            return result
        }

        // arXiv ID can also be resolved
        if let arxiv = identifiers[.arxiv] {
            var result = identifiers
            result[.bibcode] = "arXiv:\(arxiv)"
            return result
        }

        return identifiers
    }

    // MARK: - Private Helpers

    /// Resolve bibcode from identifiers
    private func resolveBibcode(from identifiers: [IdentifierType: String]) throws -> String {
        // Direct bibcode
        if let bibcode = identifiers[.bibcode] {
            return bibcode
        }

        // DOI search
        if let doi = identifiers[.doi] {
            return "doi:\"\(doi)\""
        }

        // arXiv search
        if let arxiv = identifiers[.arxiv] {
            return "arXiv:\(arxiv)"
        }

        throw EnrichmentError.noIdentifier
    }

    /// Parse enrichment response from ADS API
    private func parseEnrichmentResponse(_ data: Data) throws -> EnrichmentData {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let docs = response["docs"] as? [[String: Any]] else {
            throw EnrichmentError.parseError("Invalid ADS response")
        }

        // Check if we got any results
        let numFound = response["numFound"] as? Int ?? 0
        if numFound == 0 {
            throw EnrichmentError.notFound
        }

        guard let doc = docs.first else {
            throw EnrichmentError.notFound
        }

        // Citation count
        let citationCount = doc["citation_count"] as? Int

        // Abstract
        let abstract = doc["abstract"] as? String

        // References (ADS returns bibcodes)
        let references: [PaperStub]?
        if let refBibcodes = doc["reference"] as? [String] {
            references = refBibcodes.prefix(100).map { bibcode in
                PaperStub(
                    id: bibcode,
                    title: "Referenced Work",  // Would need API call for details
                    authors: []
                )
            }
        } else {
            references = nil
        }

        let referenceCount = (doc["reference"] as? [String])?.count

        return EnrichmentData(
            citationCount: citationCount,
            referenceCount: referenceCount,
            references: references,
            abstract: abstract,
            source: .ads
        )
    }
}
