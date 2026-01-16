//
//  IdentifierExtractorTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-16.
//

import XCTest
@testable import PublicationManagerCore

/// Tests for IdentifierExtractor utility.
///
/// Verifies correct extraction of:
/// - arXiv IDs from eprint, arxivid, and arxiv fields
/// - DOI, bibcode, PMID, PMCID
/// - arXiv ID normalization
/// - Bibcode extraction from ADS URLs
final class IdentifierExtractorTests: XCTestCase {

    // MARK: - arXiv ID Extraction Tests

    func testArxivID_fromEprintField() {
        // Given - standard BibTeX eprint field
        let fields = ["eprint": "2301.12345"]

        // When
        let result = IdentifierExtractor.arxivID(from: fields)

        // Then
        XCTAssertEqual(result, "2301.12345")
    }

    func testArxivID_fromArxividField() {
        // Given - alternative arxivid field
        let fields = ["arxivid": "2301.54321"]

        // When
        let result = IdentifierExtractor.arxivID(from: fields)

        // Then
        XCTAssertEqual(result, "2301.54321")
    }

    func testArxivID_fromArxivField() {
        // Given - arxiv field (another common variation)
        let fields = ["arxiv": "2301.99999"]

        // When
        let result = IdentifierExtractor.arxivID(from: fields)

        // Then
        XCTAssertEqual(result, "2301.99999")
    }

    func testArxivID_priorityOrder() {
        // Given - multiple fields, eprint should take priority
        let fields = [
            "eprint": "2301.11111",
            "arxivid": "2301.22222",
            "arxiv": "2301.33333"
        ]

        // When
        let result = IdentifierExtractor.arxivID(from: fields)

        // Then - eprint has highest priority
        XCTAssertEqual(result, "2301.11111")
    }

    func testArxivID_arxividOverArxiv() {
        // Given - arxivid and arxiv fields, arxivid should take priority
        let fields = [
            "arxivid": "2301.22222",
            "arxiv": "2301.33333"
        ]

        // When
        let result = IdentifierExtractor.arxivID(from: fields)

        // Then
        XCTAssertEqual(result, "2301.22222")
    }

    func testArxivID_emptyFields_returnsNil() {
        // Given - empty fields dictionary
        let fields: [String: String] = [:]

        // When
        let result = IdentifierExtractor.arxivID(from: fields)

        // Then
        XCTAssertNil(result)
    }

    func testArxivID_emptyValue_returnsEmpty() {
        // Given - eprint field with empty value
        let fields = ["eprint": ""]

        // When
        let result = IdentifierExtractor.arxivID(from: fields)

        // Then - returns the empty string (caller should check)
        XCTAssertEqual(result, "")
    }

    func testArxivID_oldFormatWithCategory() {
        // Given - old-style arXiv ID with category
        let fields = ["eprint": "hep-ph/0601001"]

        // When
        let result = IdentifierExtractor.arxivID(from: fields)

        // Then
        XCTAssertEqual(result, "hep-ph/0601001")
    }

    func testArxivID_withVersionSuffix() {
        // Given - arXiv ID with version suffix
        let fields = ["eprint": "2301.12345v2"]

        // When
        let result = IdentifierExtractor.arxivID(from: fields)

        // Then - version is preserved (normalization handles stripping)
        XCTAssertEqual(result, "2301.12345v2")
    }

    func testArxivID_withArchivePrefix() {
        // Given - arXiv ID with arXiv: prefix in field
        let fields = ["eprint": "arXiv:2301.12345"]

        // When
        let result = IdentifierExtractor.arxivID(from: fields)

        // Then - prefix is preserved (normalization handles stripping)
        XCTAssertEqual(result, "arXiv:2301.12345")
    }

    // MARK: - arXiv ID Normalization Tests

    func testNormalizeArxivID_removesArxivPrefix() {
        // Given
        let arxivID = "arXiv:2301.12345"

        // When
        let result = IdentifierExtractor.normalizeArXivID(arxivID)

        // Then
        XCTAssertEqual(result, "2301.12345")
    }

    func testNormalizeArxivID_removesArxivPrefixCaseInsensitive() {
        // Given - different case variations
        let variations = ["ARXIV:2301.12345", "ArXiv:2301.12345", "arxiv:2301.12345"]

        for arxivID in variations {
            // When
            let result = IdentifierExtractor.normalizeArXivID(arxivID)

            // Then - all should normalize the same
            XCTAssertEqual(result, "2301.12345", "Failed for: \(arxivID)")
        }
    }

    func testNormalizeArxivID_stripsVersionSuffix() {
        // Given - arXiv ID with version
        let arxivID = "2301.12345v3"

        // When
        let result = IdentifierExtractor.normalizeArXivID(arxivID)

        // Then
        XCTAssertEqual(result, "2301.12345")
    }

    func testNormalizeArxivID_stripsVersionSuffix_multipleDigits() {
        // Given - high version number
        let arxivID = "2301.12345v15"

        // When
        let result = IdentifierExtractor.normalizeArXivID(arxivID)

        // Then
        XCTAssertEqual(result, "2301.12345")
    }

    func testNormalizeArxivID_preservesOldFormat() {
        // Given - old-style arXiv ID
        let arxivID = "hep-ph/0601001"

        // When
        let result = IdentifierExtractor.normalizeArXivID(arxivID)

        // Then - old format is preserved (lowercased)
        XCTAssertEqual(result, "hep-ph/0601001")
    }

    func testNormalizeArxivID_lowercasesResult() {
        // Given - uppercase category
        let arxivID = "HEP-PH/0601001"

        // When
        let result = IdentifierExtractor.normalizeArXivID(arxivID)

        // Then
        XCTAssertEqual(result, "hep-ph/0601001")
    }

    func testNormalizeArxivID_handlesWhitespace() {
        // Given - whitespace around ID
        let arxivID = "  2301.12345  "

        // When
        let result = IdentifierExtractor.normalizeArXivID(arxivID)

        // Then
        XCTAssertEqual(result, "2301.12345")
    }

    func testNormalizeArxivID_prefixAndVersion() {
        // Given - both prefix and version
        let arxivID = "arXiv:2301.12345v2"

        // When
        let result = IdentifierExtractor.normalizeArXivID(arxivID)

        // Then
        XCTAssertEqual(result, "2301.12345")
    }

    func testNormalizeArxivID_preservesVInOldFormat() {
        // Given - old format with 'v' in category (not a version suffix)
        let arxivID = "cond-mat.str-el/0601001v1"

        // When
        let result = IdentifierExtractor.normalizeArXivID(arxivID)

        // Then - version is stripped, category preserved
        XCTAssertEqual(result, "cond-mat.str-el/0601001")
    }

    // MARK: - DOI Extraction Tests

    func testDOI_fromDoiField() {
        // Given
        let fields = ["doi": "10.1234/example.2024"]

        // When
        let result = IdentifierExtractor.doi(from: fields)

        // Then
        XCTAssertEqual(result, "10.1234/example.2024")
    }

    func testDOI_emptyFields_returnsNil() {
        // Given
        let fields: [String: String] = [:]

        // When
        let result = IdentifierExtractor.doi(from: fields)

        // Then
        XCTAssertNil(result)
    }

    // MARK: - Bibcode Extraction Tests

    func testBibcode_fromBibcodeField() {
        // Given
        let fields = ["bibcode": "2024ApJ...123..456A"]

        // When
        let result = IdentifierExtractor.bibcode(from: fields)

        // Then
        XCTAssertEqual(result, "2024ApJ...123..456A")
    }

    func testBibcode_fromAdsurl_uiAdsabs() {
        // Given - modern ADS URL
        let fields = ["adsurl": "https://ui.adsabs.harvard.edu/abs/2024ApJ...123..456A/abstract"]

        // When
        let result = IdentifierExtractor.bibcode(from: fields)

        // Then
        XCTAssertEqual(result, "2024ApJ...123..456A")
    }

    func testBibcode_fromAdsurl_oldAdsabs() {
        // Given - old-style ADS URL
        let fields = ["adsurl": "https://adsabs.harvard.edu/abs/2024ApJ...123..456A"]

        // When
        let result = IdentifierExtractor.bibcode(from: fields)

        // Then
        XCTAssertEqual(result, "2024ApJ...123..456A")
    }

    func testBibcode_bibcodeFieldPriority() {
        // Given - both bibcode and adsurl
        let fields = [
            "bibcode": "2024ApJ...111..111B",
            "adsurl": "https://ui.adsabs.harvard.edu/abs/2024ApJ...222..222C/abstract"
        ]

        // When
        let result = IdentifierExtractor.bibcode(from: fields)

        // Then - bibcode field has priority
        XCTAssertEqual(result, "2024ApJ...111..111B")
    }

    func testBibcode_invalidAdsurl_returnsNil() {
        // Given - non-ADS URL
        let fields = ["adsurl": "https://example.com/paper"]

        // When
        let result = IdentifierExtractor.bibcode(from: fields)

        // Then
        XCTAssertNil(result)
    }

    // MARK: - PMID and PMCID Tests

    func testPMID_fromPmidField() {
        // Given
        let fields = ["pmid": "12345678"]

        // When
        let result = IdentifierExtractor.pmid(from: fields)

        // Then
        XCTAssertEqual(result, "12345678")
    }

    func testPMCID_fromPmcidField() {
        // Given
        let fields = ["pmcid": "PMC1234567"]

        // When
        let result = IdentifierExtractor.pmcid(from: fields)

        // Then
        XCTAssertEqual(result, "PMC1234567")
    }

    // MARK: - Batch Extraction Tests

    func testAllIdentifiers_extractsAll() {
        // Given - fields with multiple identifiers
        let fields = [
            "eprint": "2301.12345",
            "doi": "10.1234/example",
            "bibcode": "2024ApJ...123..456A",
            "pmid": "12345678",
            "pmcid": "PMC1234567"
        ]

        // When
        let result = IdentifierExtractor.allIdentifiers(from: fields)

        // Then
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(result[.arxiv], "2301.12345")
        XCTAssertEqual(result[.doi], "10.1234/example")
        XCTAssertEqual(result[.bibcode], "2024ApJ...123..456A")
        XCTAssertEqual(result[.pmid], "12345678")
        XCTAssertEqual(result[.pmcid], "PMC1234567")
    }

    func testAllIdentifiers_partialFields() {
        // Given - only some identifiers
        let fields = [
            "doi": "10.1234/example",
            "bibcode": "2024ApJ...123..456A"
        ]

        // When
        let result = IdentifierExtractor.allIdentifiers(from: fields)

        // Then
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[.doi], "10.1234/example")
        XCTAssertEqual(result[.bibcode], "2024ApJ...123..456A")
        XCTAssertNil(result[.arxiv])
        XCTAssertNil(result[.pmid])
    }

    func testAllIdentifiers_emptyFields() {
        // Given
        let fields: [String: String] = [:]

        // When
        let result = IdentifierExtractor.allIdentifiers(from: fields)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - String Extension Tests (Bibcode Extraction from URL)

    func testExtractingBibcode_validUIURL() {
        // Given
        let url = "https://ui.adsabs.harvard.edu/abs/2024ApJ...123..456A/abstract"

        // When
        let result = url.extractingBibcode()

        // Then
        XCTAssertEqual(result, "2024ApJ...123..456A")
    }

    func testExtractingBibcode_validOldURL() {
        // Given
        let url = "https://adsabs.harvard.edu/abs/2024ApJ...123..456A"

        // When
        let result = url.extractingBibcode()

        // Then
        XCTAssertEqual(result, "2024ApJ...123..456A")
    }

    func testExtractingBibcode_nonADSURL_returnsNil() {
        // Given
        let url = "https://example.com/abs/2024ApJ...123..456A"

        // When
        let result = url.extractingBibcode()

        // Then - not an ADS domain
        XCTAssertNil(result)
    }

    func testExtractingBibcode_noAbsComponent_returnsNil() {
        // Given - ADS domain but no /abs/ path
        let url = "https://ui.adsabs.harvard.edu/search/2024ApJ...123..456A"

        // When
        let result = url.extractingBibcode()

        // Then
        XCTAssertNil(result)
    }

    func testExtractingBibcode_invalidURL_returnsNil() {
        // Given
        let url = "not a valid url"

        // When
        let result = url.extractingBibcode()

        // Then
        XCTAssertNil(result)
    }
}
