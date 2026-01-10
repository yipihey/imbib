//
//  QueryBuilderStateTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-09.
//

import XCTest
@testable import PublicationManagerCore

final class QueryBuilderStateTests: XCTestCase {

    // MARK: - Parse Tests

    func testParse_simpleAuthorQuery() {
        let state = QueryBuilderState.parse(query: "author:Einstein", source: .ads)

        XCTAssertEqual(state.terms.count, 1)
        XCTAssertEqual(state.terms[0].field, .adsAuthor)
        XCTAssertEqual(state.terms[0].value, "Einstein")
    }

    func testParse_quotedMultiWordValue() {
        let state = QueryBuilderState.parse(query: "author:\"Clark, Susan\"", source: .ads)

        XCTAssertEqual(state.terms.count, 1)
        XCTAssertEqual(state.terms[0].field, .adsAuthor)
        XCTAssertEqual(state.terms[0].value, "Clark, Susan")
    }

    func testParse_spaceAfterColon_trimmed() {
        // Users sometimes type "author: Name" with space after colon
        let state = QueryBuilderState.parse(query: "author: Einstein", source: .ads)

        XCTAssertEqual(state.terms.count, 1)
        XCTAssertEqual(state.terms[0].field, .adsAuthor)
        // Value should have leading space trimmed when regenerated
        let generated = state.generateQuery()
        XCTAssertEqual(generated, "author:Einstein")
    }

    func testParse_outerQuotes_removed() {
        // Malformed query with outer quotes around entire string
        let state = QueryBuilderState.parse(query: "\"author: Clark, Susan\"", source: .ads)

        XCTAssertEqual(state.terms.count, 1)
        XCTAssertEqual(state.terms[0].field, .adsAuthor)
        // Outer quotes should be stripped, then parsed correctly
        let generated = state.generateQuery()
        XCTAssertEqual(generated, "author:\"Clark, Susan\"")
    }

    func testParse_andQuery() {
        let state = QueryBuilderState.parse(query: "author:Einstein AND title:relativity", source: .ads)

        XCTAssertEqual(state.matchType, .all)
        XCTAssertEqual(state.terms.count, 2)
        XCTAssertEqual(state.terms[0].field, .adsAuthor)
        XCTAssertEqual(state.terms[0].value, "Einstein")
        XCTAssertEqual(state.terms[1].field, .adsTitle)
        XCTAssertEqual(state.terms[1].value, "relativity")
    }

    func testParse_orQuery() {
        let state = QueryBuilderState.parse(query: "author:Einstein OR author:Bohr", source: .ads)

        XCTAssertEqual(state.matchType, .any)
        XCTAssertEqual(state.terms.count, 2)
    }

    func testParse_noFieldPrefix_usesAllFields() {
        let state = QueryBuilderState.parse(query: "dark matter", source: .ads)

        XCTAssertEqual(state.terms.count, 1)
        XCTAssertEqual(state.terms[0].field, .adsAll)
        XCTAssertEqual(state.terms[0].value, "dark matter")
    }

    // MARK: - Generate Tests

    func testGenerate_singleTerm() {
        let state = QueryBuilderState(
            source: .ads,
            matchType: .all,
            terms: [QueryTerm(field: .adsAuthor, value: "Einstein")]
        )

        XCTAssertEqual(state.generateQuery(), "author:Einstein")
    }

    func testGenerate_multiWordValue_quoted() {
        let state = QueryBuilderState(
            source: .ads,
            matchType: .all,
            terms: [QueryTerm(field: .adsAuthor, value: "Clark, Susan")]
        )

        XCTAssertEqual(state.generateQuery(), "author:\"Clark, Susan\"")
    }

    func testGenerate_multipleTerms_and() {
        let state = QueryBuilderState(
            source: .ads,
            matchType: .all,
            terms: [
                QueryTerm(field: .adsAuthor, value: "Einstein"),
                QueryTerm(field: .adsTitle, value: "relativity")
            ]
        )

        XCTAssertEqual(state.generateQuery(), "author:Einstein AND title:relativity")
    }

    func testGenerate_multipleTerms_or() {
        let state = QueryBuilderState(
            source: .ads,
            matchType: .any,
            terms: [
                QueryTerm(field: .adsAuthor, value: "Einstein"),
                QueryTerm(field: .adsAuthor, value: "Bohr")
            ]
        )

        XCTAssertEqual(state.generateQuery(), "author:Einstein OR author:Bohr")
    }

    // MARK: - Round Trip Tests

    func testRoundTrip_simpleQuery() {
        let original = "author:Einstein"
        let state = QueryBuilderState.parse(query: original, source: .ads)
        let regenerated = state.generateQuery()

        XCTAssertEqual(regenerated, original)
    }

    func testRoundTrip_quotedQuery() {
        let original = "author:\"Clark, Susan\""
        let state = QueryBuilderState.parse(query: original, source: .ads)
        let regenerated = state.generateQuery()

        XCTAssertEqual(regenerated, original)
    }

    func testRoundTrip_complexQuery() {
        let original = "author:Einstein AND title:\"special relativity\""
        let state = QueryBuilderState.parse(query: original, source: .ads)
        let regenerated = state.generateQuery()

        XCTAssertEqual(regenerated, original)
    }

    func testRoundTrip_malformedQuery_fixed() {
        // Malformed input with outer quotes should be fixed after round trip
        let malformed = "\"author: Clark, Susan\""
        let state = QueryBuilderState.parse(query: malformed, source: .ads)
        let regenerated = state.generateQuery()

        // Should produce correct format
        XCTAssertEqual(regenerated, "author:\"Clark, Susan\"")
    }
}
