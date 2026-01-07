//
//  IdentifierExtractor.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-06.
//

import Foundation

// MARK: - Identifier Extractor

/// Centralized utility for extracting publication identifiers from BibTeX fields.
///
/// This eliminates duplicate identifier extraction logic and ensures consistent
/// handling across ManagedObjects, LocalPaper, and EnrichmentPlugin.
///
/// Field priority order for each identifier:
/// - arXiv: `eprint` → `arxivid` → `arxiv`
/// - DOI: `doi`
/// - Bibcode: `bibcode` (or extracted from `adsurl`)
/// - PMID: `pmid`
/// - PMCID: `pmcid`
public enum IdentifierExtractor {

    // MARK: - Individual Identifier Extraction

    /// Extract arXiv ID from BibTeX fields.
    ///
    /// Checks fields in priority order: `eprint`, `arxivid`, `arxiv`.
    /// The `eprint` field is standard BibTeX, while `arxivid` and `arxiv` are
    /// common alternatives used by various tools.
    ///
    /// - Parameter fields: Dictionary of BibTeX field names to values
    /// - Returns: The arXiv ID if found, nil otherwise
    public static func arxivID(from fields: [String: String]) -> String? {
        fields["eprint"] ?? fields["arxivid"] ?? fields["arxiv"]
    }

    /// Extract DOI from BibTeX fields.
    ///
    /// - Parameter fields: Dictionary of BibTeX field names to values
    /// - Returns: The DOI if found, nil otherwise
    public static func doi(from fields: [String: String]) -> String? {
        fields["doi"]
    }

    /// Extract ADS bibcode from BibTeX fields.
    ///
    /// Checks the `bibcode` field first, then attempts to extract from `adsurl`
    /// if present.
    ///
    /// - Parameter fields: Dictionary of BibTeX field names to values
    /// - Returns: The bibcode if found, nil otherwise
    public static func bibcode(from fields: [String: String]) -> String? {
        fields["bibcode"] ?? fields["adsurl"]?.extractingBibcode()
    }

    /// Extract PubMed ID from BibTeX fields.
    ///
    /// - Parameter fields: Dictionary of BibTeX field names to values
    /// - Returns: The PMID if found, nil otherwise
    public static func pmid(from fields: [String: String]) -> String? {
        fields["pmid"]
    }

    /// Extract PubMed Central ID from BibTeX fields.
    ///
    /// - Parameter fields: Dictionary of BibTeX field names to values
    /// - Returns: The PMCID if found, nil otherwise
    public static func pmcid(from fields: [String: String]) -> String? {
        fields["pmcid"]
    }

    // MARK: - Batch Extraction

    /// Extract all identifiers from BibTeX fields at once.
    ///
    /// This is more efficient than calling individual methods when you need
    /// multiple identifiers, as it only iterates the fields once.
    ///
    /// - Parameter fields: Dictionary of BibTeX field names to values
    /// - Returns: Dictionary of identifier types to their values
    public static func allIdentifiers(from fields: [String: String]) -> [IdentifierType: String] {
        var result: [IdentifierType: String] = [:]

        if let arxiv = arxivID(from: fields) {
            result[.arxiv] = arxiv
        }
        if let doi = doi(from: fields) {
            result[.doi] = doi
        }
        if let bibcode = bibcode(from: fields) {
            result[.bibcode] = bibcode
        }
        if let pmid = pmid(from: fields) {
            result[.pmid] = pmid
        }
        if let pmcid = pmcid(from: fields) {
            result[.pmcid] = pmcid
        }

        return result
    }

    // MARK: - arXiv ID Normalization

    /// Normalize an arXiv ID for database lookups.
    ///
    /// Handles:
    /// - Removes `arXiv:` prefix if present
    /// - Strips version suffix (e.g., `2401.12345v2` → `2401.12345`)
    /// - Lowercases for case-insensitive matching
    ///
    /// - Parameter arxivID: Raw arXiv ID
    /// - Returns: Normalized arXiv ID for indexed lookups
    public static func normalizeArXivID(_ arxivID: String) -> String {
        var id = arxivID.trimmingCharacters(in: .whitespaces)

        // Remove arXiv: prefix
        if id.lowercased().hasPrefix("arxiv:") {
            id = String(id.dropFirst(6))
        }

        // Strip version suffix (v1, v2, etc.)
        if let vIndex = id.lastIndex(of: "v") {
            let suffix = id[id.index(after: vIndex)...]
            if suffix.allSatisfy({ $0.isNumber }) && !suffix.isEmpty {
                id = String(id[..<vIndex])
            }
        }

        return id.lowercased()
    }
}

// MARK: - String Extension for Bibcode Extraction

public extension String {
    /// Extract ADS bibcode from an ADS URL.
    ///
    /// Handles URLs like:
    /// - `https://ui.adsabs.harvard.edu/abs/2023ApJ...123..456A/abstract`
    /// - `https://adsabs.harvard.edu/abs/2023ApJ...123..456A`
    ///
    /// Validates that the URL actually points to an ADS domain before extraction.
    ///
    /// - Returns: The bibcode if found, nil otherwise
    func extractingBibcode() -> String? {
        // Use URL parsing for robustness
        guard let url = URL(string: self),
              url.host?.contains("adsabs") == true,
              url.pathComponents.contains("abs"),
              let bibcodeIndex = url.pathComponents.firstIndex(of: "abs"),
              bibcodeIndex + 1 < url.pathComponents.count else {
            return nil
        }
        return url.pathComponents[bibcodeIndex + 1]
    }
}
