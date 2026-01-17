//
//  IdentifierExtractorTextTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-16.
//

import XCTest
@testable import PublicationManagerCore

final class IdentifierExtractorTextTests: XCTestCase {

    // MARK: - DOI Extraction Tests

    func testExtractDOI_simpleDOI_extractsCorrectly() {
        let text = "This paper has DOI 10.1038/nature12373 in its text."
        let result = IdentifierExtractor.extractDOIFromText(text)
        XCTAssertEqual(result, "10.1038/nature12373")
    }

    func testExtractDOI_withPrefix_extractsCorrectly() {
        let text = "doi:10.1002/andp.19053221004"
        let result = IdentifierExtractor.extractDOIFromText(text)
        XCTAssertEqual(result, "10.1002/andp.19053221004")
    }

    func testExtractDOI_withURLPrefix_extractsCorrectly() {
        let text = "Available at https://doi.org/10.1103/PhysRevLett.116.061102"
        let result = IdentifierExtractor.extractDOIFromText(text)
        XCTAssertEqual(result, "10.1103/PhysRevLett.116.061102")
    }

    func testExtractDOI_withDxDOIOrg_extractsCorrectly() {
        let text = "Link: http://dx.doi.org/10.1126/science.1234567"
        let result = IdentifierExtractor.extractDOIFromText(text)
        XCTAssertEqual(result, "10.1126/science.1234567")
    }

    func testExtractDOI_complexDOI_extractsCorrectly() {
        let text = "DOI: 10.1088/0004-637X/800/2/144"
        let result = IdentifierExtractor.extractDOIFromText(text)
        XCTAssertEqual(result, "10.1088/0004-637X/800/2/144")
    }

    func testExtractDOI_noMatch_returnsNil() {
        let text = "This text contains no DOI identifier."
        let result = IdentifierExtractor.extractDOIFromText(text)
        XCTAssertNil(result)
    }

    func testExtractDOI_invalidDOI_returnsNil() {
        let text = "Not a DOI: 10.12/short"  // Less than 4 digits after 10.
        let result = IdentifierExtractor.extractDOIFromText(text)
        XCTAssertNil(result)
    }

    func testExtractDOI_multipleInText_extractsFirst() {
        let text = "First 10.1234/first and second 10.5678/second"
        let result = IdentifierExtractor.extractDOIFromText(text)
        XCTAssertEqual(result, "10.1234/first")
    }

    // MARK: - arXiv Extraction Tests

    func testExtractArXiv_newFormat_extractsCorrectly() {
        let text = "Available on arXiv: 2401.12345"
        let result = IdentifierExtractor.extractArXivFromText(text)
        XCTAssertEqual(result, "2401.12345")
    }

    func testExtractArXiv_newFormatWithVersion_stripsVersion() {
        let text = "arXiv:2312.05678v2"
        let result = IdentifierExtractor.extractArXivFromText(text)
        XCTAssertEqual(result, "2312.05678")
    }

    func testExtractArXiv_fiveDigits_extractsCorrectly() {
        let text = "Paper ID: 2401.00001"
        let result = IdentifierExtractor.extractArXivFromText(text)
        XCTAssertEqual(result, "2401.00001")
    }

    func testExtractArXiv_oldFormat_extractsCorrectly() {
        let text = "From astro-ph/0612345"
        let result = IdentifierExtractor.extractArXivFromText(text)
        XCTAssertEqual(result, "astro-ph/0612345")
    }

    func testExtractArXiv_oldFormatHepTh_extractsCorrectly() {
        let text = "Reference: hep-th/9901234v1"
        let result = IdentifierExtractor.extractArXivFromText(text)
        XCTAssertEqual(result, "hep-th/9901234")
    }

    func testExtractArXiv_withPrefix_extractsCorrectly() {
        let text = "arXiv:2305.14314"
        let result = IdentifierExtractor.extractArXivFromText(text)
        XCTAssertEqual(result, "2305.14314")
    }

    func testExtractArXiv_noMatch_returnsNil() {
        let text = "This paper has no arXiv identifier."
        let result = IdentifierExtractor.extractArXivFromText(text)
        XCTAssertNil(result)
    }

    func testExtractArXiv_partialMatch_returnsNil() {
        let text = "Year 2024 and number 123 but not arXiv"
        let result = IdentifierExtractor.extractArXivFromText(text)
        XCTAssertNil(result)
    }

    // MARK: - Bibcode Extraction Tests

    func testExtractBibcode_journalArticle_extractsCorrectly() {
        let text = "ADS bibcode: 2023ApJ...945..123A"
        let result = IdentifierExtractor.extractBibcodeFromText(text)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.hasPrefix("2023ApJ") == true)
    }

    func testExtractBibcode_monthlyNotices_extractsCorrectly() {
        let text = "Reference 2022MNRAS.512.1234B in the paper"
        let result = IdentifierExtractor.extractBibcodeFromText(text)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("MNRAS") == true)
    }

    func testExtractBibcode_noMatch_returnsNil() {
        let text = "This has no bibcode identifier."
        let result = IdentifierExtractor.extractBibcodeFromText(text)
        XCTAssertNil(result)
    }

    // MARK: - PMID Extraction Tests

    func testExtractPMID_withPrefix_extractsCorrectly() {
        let text = "PMID: 12345678"
        let result = IdentifierExtractor.extractPMIDFromText(text)
        XCTAssertEqual(result, "12345678")
    }

    func testExtractPMID_withPubMedID_extractsCorrectly() {
        let text = "PubMed ID: 98765432"
        let result = IdentifierExtractor.extractPMIDFromText(text)
        XCTAssertEqual(result, "98765432")
    }

    func testExtractPMID_fromURL_extractsCorrectly() {
        let text = "https://pubmed.ncbi.nlm.nih.gov/34567890/"
        let result = IdentifierExtractor.extractPMIDFromText(text)
        XCTAssertEqual(result, "34567890")
    }

    func testExtractPMID_noMatch_returnsNil() {
        let text = "No PubMed identifier here."
        let result = IdentifierExtractor.extractPMIDFromText(text)
        XCTAssertNil(result)
    }

    // MARK: - Edge Cases

    func testExtractDOI_withTrailingPunctuation_cleansUp() {
        let text = "The DOI is 10.1234/test.paper."
        let result = IdentifierExtractor.extractDOIFromText(text)
        // Should not include trailing period
        XCTAssertEqual(result, "10.1234/test.paper")
    }

    func testExtractArXiv_caseInsensitive_extractsCorrectly() {
        let text = "ARXIV:2401.12345"
        let result = IdentifierExtractor.extractArXivFromText(text)
        XCTAssertEqual(result, "2401.12345")
    }

    func testExtractDOI_emptyString_returnsNil() {
        let result = IdentifierExtractor.extractDOIFromText("")
        XCTAssertNil(result)
    }

    func testExtractArXiv_emptyString_returnsNil() {
        let result = IdentifierExtractor.extractArXivFromText("")
        XCTAssertNil(result)
    }
}
