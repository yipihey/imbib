//
//  OpenAlexEnrichment.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog

// MARK: - OpenAlex Enrichment Plugin

/// Extension to make OpenAlexSource conform to EnrichmentPlugin.
///
/// OpenAlex provides rich enrichment data including:
/// - Citation count and reference count
/// - Open access status (gold, green, bronze, hybrid, closed)
/// - Open access PDF URL
/// - Venue information
/// - Abstract (if available)
extension OpenAlexSource: EnrichmentPlugin {

    // MARK: - Capabilities

    public nonisolated var enrichmentCapabilities: EnrichmentCapabilities {
        [.citationCount, .references, .citations, .abstract, .pdfURL, .openAccess, .venue]
    }

    // MARK: - Enrichment

    public func enrich(
        identifiers: [IdentifierType: String],
        existingData: EnrichmentData?
    ) async throws -> EnrichmentResult {
        Logger.sources.info("OpenAlex: enriching paper with identifiers: \(identifiers)")

        // Build query URL
        let workURL = try buildWorkURL(from: identifiers)

        var request = URLRequest(url: workURL)

        // Add polite pool email if available
        if let email = await credentialManager.email(for: "openalex") {
            request.url = URL(string: workURL.absoluteString + "&mailto=\(email)")
        }

        await rateLimiter.waitIfNeeded()
        Logger.network.httpRequest("GET", url: workURL)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnrichmentError.networkError("Invalid response")
        }

        Logger.network.httpResponse(httpResponse.statusCode, url: workURL, bytes: data.count)

        switch httpResponse.statusCode {
        case 200:
            break
        case 404:
            throw EnrichmentError.notFound
        case 429:
            throw EnrichmentError.rateLimited(retryAfter: nil)
        default:
            throw EnrichmentError.networkError("HTTP \(httpResponse.statusCode)")
        }

        // Parse enrichment response
        let enrichmentData = try parseEnrichmentResponse(data)

        // Extract resolved OpenAlex ID
        var resolvedIdentifiers = identifiers
        if let oaID = try? extractOpenAlexID(from: data) {
            resolvedIdentifiers[.openAlex] = oaID
        }

        Logger.sources.info("OpenAlex: enrichment complete - citations: \(enrichmentData.citationCount ?? 0)")

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
        // If we already have an OpenAlex ID, return as-is
        if identifiers[.openAlex] != nil {
            return identifiers
        }

        // Try to resolve using DOI
        if let doi = identifiers[.doi] {
            var result = identifiers
            result[.openAlex] = "https://doi.org/\(doi)"
            return result
        }

        return identifiers
    }

    // MARK: - Private Helpers

    /// Build the work URL from identifiers
    private func buildWorkURL(from identifiers: [IdentifierType: String]) throws -> URL {
        // Prefer OpenAlex ID
        if let oaID = identifiers[.openAlex] {
            // Handle both full URL and short ID formats
            if oaID.hasPrefix("W") {
                return URL(string: "\(baseURL)/works/\(oaID)")!
            } else if oaID.hasPrefix("https://") {
                return URL(string: "\(baseURL)/works/\(oaID)")!
            }
        }

        // Use DOI
        if let doi = identifiers[.doi] {
            return URL(string: "\(baseURL)/works/https://doi.org/\(doi)")!
        }

        throw EnrichmentError.noIdentifier
    }

    /// Extract OpenAlex ID from response
    private func extractOpenAlexID(from data: Data) throws -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            return nil
        }
        return id.replacingOccurrences(of: "https://openalex.org/", with: "")
    }

    /// Parse enrichment response from OpenAlex API
    private func parseEnrichmentResponse(_ data: Data) throws -> EnrichmentData {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EnrichmentError.parseError("Invalid JSON response")
        }

        // Citation and reference counts
        let citationCount = json["cited_by_count"] as? Int
        let referenceCount = (json["referenced_works"] as? [Any])?.count

        // Abstract (from inverted index)
        let abstract: String?
        if let invertedIndex = json["abstract_inverted_index"] as? [String: [Int]] {
            abstract = reconstructAbstract(from: invertedIndex)
        } else {
            abstract = nil
        }

        // Venue
        let venue: String?
        if let primaryLocation = json["primary_location"] as? [String: Any],
           let source = primaryLocation["source"] as? [String: Any] {
            venue = source["display_name"] as? String
        } else {
            venue = nil
        }

        // Open access info
        let openAccessStatus: OpenAccessStatus?
        var pdfURLs: [URL]?

        if let openAccess = json["open_access"] as? [String: Any] {
            let isOA = openAccess["is_oa"] as? Bool ?? false
            let oaStatus = openAccess["oa_status"] as? String

            if isOA {
                switch oaStatus {
                case "gold": openAccessStatus = .gold
                case "green": openAccessStatus = .green
                case "bronze": openAccessStatus = .bronze
                case "hybrid": openAccessStatus = .hybrid
                default: openAccessStatus = .unknown
                }
            } else {
                openAccessStatus = .closed
            }

            if let oaURL = openAccess["oa_url"] as? String,
               let url = URL(string: oaURL) {
                pdfURLs = [url]
            }
        } else {
            openAccessStatus = nil
        }

        // Parse references (limited to first 100 for performance)
        let references: [PaperStub]?
        if let referencedWorks = json["referenced_works"] as? [String] {
            // OpenAlex only gives IDs, not full data - we'd need additional API calls
            // For now, create stubs with just IDs
            references = referencedWorks.prefix(100).map { workID in
                let shortID = workID.replacingOccurrences(of: "https://openalex.org/", with: "")
                return PaperStub(
                    id: shortID,
                    title: "Referenced Work",  // Would need API call for details
                    authors: []
                )
            }
        } else {
            references = nil
        }

        return EnrichmentData(
            citationCount: citationCount,
            referenceCount: referenceCount,
            references: references,
            abstract: abstract,
            pdfURLs: pdfURLs,
            openAccessStatus: openAccessStatus,
            venue: venue,
            source: .openAlex
        )
    }

    /// Reconstruct abstract from inverted index
    private func reconstructAbstract(from invertedIndex: [String: [Int]]) -> String {
        var words: [(Int, String)] = []
        for (word, positions) in invertedIndex {
            for position in positions {
                words.append((position, word))
            }
        }
        words.sort { $0.0 < $1.0 }
        return words.map { $0.1 }.joined(separator: " ")
    }
}
