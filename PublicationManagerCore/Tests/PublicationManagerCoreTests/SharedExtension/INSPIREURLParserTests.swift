//
//  INSPIREURLParserTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-08.
//

import XCTest
@testable import PublicationManagerCore

final class INSPIREURLParserTests: XCTestCase {

    // MARK: - Modern Literature URL Tests

    func testParse_literatureURL_extractsRecordID() {
        // Given
        let url = URL(string: "https://inspirehep.net/literature/1234567")!

        // When
        let result = INSPIREURLParser.parse(url)

        // Then
        XCTAssertEqual(result, .recordID(1234567))
    }

    func testParse_literatureURL_withTrailingSlash() {
        // Given
        let url = URL(string: "https://inspirehep.net/literature/1234567/")!

        // When
        let result = INSPIREURLParser.parse(url)

        // Then
        XCTAssertEqual(result, .recordID(1234567))
    }

    func testParse_literatureURL_withQueryParams() {
        // Given
        let url = URL(string: "https://inspirehep.net/literature/1234567?utm_source=twitter")!

        // When
        let result = INSPIREURLParser.parse(url)

        // Then
        XCTAssertEqual(result, .recordID(1234567))
    }

    func testParse_wwwSubdomain() {
        // Given
        let url = URL(string: "https://www.inspirehep.net/literature/1234567")!

        // When
        let result = INSPIREURLParser.parse(url)

        // Then
        XCTAssertEqual(result, .recordID(1234567))
    }

    func testParse_labsSubdomain() {
        // Given
        let url = URL(string: "https://labs.inspirehep.net/literature/9876543")!

        // When
        let result = INSPIREURLParser.parse(url)

        // Then
        XCTAssertEqual(result, .recordID(9876543))
    }

    // MARK: - API URL Tests

    func testParse_apiURL_extractsRecordID() {
        // Given
        let url = URL(string: "https://inspirehep.net/api/literature/1234567")!

        // When
        let result = INSPIREURLParser.parse(url)

        // Then
        XCTAssertEqual(result, .recordID(1234567))
    }

    // MARK: - Legacy URL Tests

    func testParse_legacyRecordURL_extractsRecordID() {
        // Given
        let url = URL(string: "https://old.inspirehep.net/record/1234567")!

        // When
        let result = INSPIREURLParser.parse(url)

        // Then
        XCTAssertEqual(result, .recordID(1234567))
    }

    // MARK: - Search URL Tests

    func testParse_arXivSearchURL_extractsArXivID() {
        // Given
        let url = URL(string: "https://inspirehep.net/literature?q=arxiv:2401.12345")!

        // When
        let result = INSPIREURLParser.parse(url)

        // Then
        XCTAssertEqual(result, .arXivID("2401.12345"))
    }

    func testParse_arXivSearchURL_withVersion() {
        // Given
        let url = URL(string: "https://inspirehep.net/literature?q=arxiv:2401.12345v2")!

        // When
        let result = INSPIREURLParser.parse(url)

        // Then
        XCTAssertEqual(result, .arXivID("2401.12345v2"))
    }

    func testParse_doiSearchURL_extractsDOI() {
        // Given
        let url = URL(string: "https://inspirehep.net/literature?q=doi:10.1016/j.physletb.2012.08.020")!

        // When
        let result = INSPIREURLParser.parse(url)

        // Then
        XCTAssertEqual(result, .doi("10.1016/j.physletb.2012.08.020"))
    }

    // MARK: - Non-INSPIRE URL Tests

    func testParse_nonINSPIREURL_returnsNil() {
        // Given
        let url = URL(string: "https://arxiv.org/abs/2401.12345")!

        // When
        let result = INSPIREURLParser.parse(url)

        // Then
        XCTAssertNil(result)
    }

    func testParse_googleURL_returnsNil() {
        // Given
        let url = URL(string: "https://google.com/search?q=inspire")!

        // When
        let result = INSPIREURLParser.parse(url)

        // Then
        XCTAssertNil(result)
    }

    func testParse_adsURL_returnsNil() {
        // Given
        let url = URL(string: "https://ui.adsabs.harvard.edu/abs/2012PhLB..716....1A")!

        // When
        let result = INSPIREURLParser.parse(url)

        // Then
        XCTAssertNil(result)
    }

    // MARK: - Edge Cases

    func testParse_literatureSearchURL_withoutIdentifier_returnsNil() {
        // Given - search URL with generic query, no specific identifier
        let url = URL(string: "https://inspirehep.net/literature?q=higgs+boson")!

        // When
        let result = INSPIREURLParser.parse(url)

        // Then
        XCTAssertNil(result)
    }

    func testParse_homepageURL_returnsNil() {
        // Given
        let url = URL(string: "https://inspirehep.net/")!

        // When
        let result = INSPIREURLParser.parse(url)

        // Then
        XCTAssertNil(result)
    }

    func testParse_authorsURL_returnsNil() {
        // Given
        let url = URL(string: "https://inspirehep.net/authors/1234567")!

        // When
        let result = INSPIREURLParser.parse(url)

        // Then
        XCTAssertNil(result)
    }

    // MARK: - isINSPIREURL Tests

    func testIsINSPIREURL_validURL_returnsTrue() {
        // Given
        let url = URL(string: "https://inspirehep.net/literature/1234567")!

        // When
        let result = INSPIREURLParser.isINSPIREURL(url)

        // Then
        XCTAssertTrue(result)
    }

    func testIsINSPIREURL_labsSubdomain_returnsTrue() {
        // Given
        let url = URL(string: "https://labs.inspirehep.net/literature/1234567")!

        // When
        let result = INSPIREURLParser.isINSPIREURL(url)

        // Then
        XCTAssertTrue(result)
    }

    func testIsINSPIREURL_nonINSPIRE_returnsFalse() {
        // Given
        let url = URL(string: "https://arxiv.org/abs/2401.12345")!

        // When
        let result = INSPIREURLParser.isINSPIREURL(url)

        // Then
        XCTAssertFalse(result)
    }

    // MARK: - INSPIREIdentifier Tests

    func testRecordID_stringValue() {
        // Given
        let id = INSPIREIdentifier.recordID(1234567)

        // When
        let result = id.stringValue

        // Then
        XCTAssertEqual(result, "1234567")
    }

    func testRecordID_apiQuery() {
        // Given
        let id = INSPIREIdentifier.recordID(1234567)

        // When
        let result = id.apiQuery

        // Then
        XCTAssertEqual(result, "recid:1234567")
    }

    func testRecordID_webURL() {
        // Given
        let id = INSPIREIdentifier.recordID(1234567)

        // When
        let result = id.webURL

        // Then
        XCTAssertEqual(result?.absoluteString, "https://inspirehep.net/literature/1234567")
    }

    func testArXivID_apiQuery() {
        // Given
        let id = INSPIREIdentifier.arXivID("2401.12345")

        // When
        let result = id.apiQuery

        // Then
        XCTAssertEqual(result, "arxiv:2401.12345")
    }

    func testDOI_apiQuery() {
        // Given
        let id = INSPIREIdentifier.doi("10.1016/j.physletb.2012.08.020")

        // When
        let result = id.apiQuery

        // Then
        XCTAssertEqual(result, "doi:10.1016/j.physletb.2012.08.020")
    }
}
