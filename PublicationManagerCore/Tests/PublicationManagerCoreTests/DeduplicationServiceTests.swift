//
//  DeduplicationServiceTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-04.
//

import XCTest
@testable import PublicationManagerCore

final class DeduplicationServiceTests: XCTestCase {

    var service: DeduplicationService!

    override func setUp() async throws {
        service = DeduplicationService()
    }

    // MARK: - Identifier Deduplication

    func testDeduplicateByDOI() async {
        let result1 = SearchResult(
            id: "crossref-1",
            sourceID: "crossref",
            title: "Research Paper",
            authors: ["Author One"],
            year: 2023,
            doi: "10.1234/test.2023"
        )

        let result2 = SearchResult(
            id: "semantic-1",
            sourceID: "semanticscholar",
            title: "Research Paper",
            authors: ["Author One"],
            year: 2023,
            doi: "10.1234/test.2023"
        )

        let deduplicated = await service.deduplicate([result1, result2])

        XCTAssertEqual(deduplicated.count, 1)
        XCTAssertEqual(deduplicated[0].sourceIDs.count, 2)
        // Crossref should be primary (higher priority)
        XCTAssertEqual(deduplicated[0].primary.sourceID, "crossref")
    }

    func testDeduplicateByArXivID() async {
        let result1 = SearchResult(
            id: "arxiv-1",
            sourceID: "arxiv",
            title: "Preprint Paper",
            authors: ["Researcher"],
            year: 2023,
            arxivID: "2301.12345"
        )

        let result2 = SearchResult(
            id: "semantic-2",
            sourceID: "semanticscholar",
            title: "Preprint Paper",
            authors: ["Researcher"],
            year: 2023,
            arxivID: "2301.12345v2"  // With version suffix
        )

        let deduplicated = await service.deduplicate([result1, result2])

        XCTAssertEqual(deduplicated.count, 1)
        XCTAssertEqual(deduplicated[0].sourceIDs.count, 2)
    }

    func testDeduplicateByBibcode() async {
        let result1 = SearchResult(
            id: "ads-1",
            sourceID: "ads",
            title: "Astronomy Paper",
            authors: ["Astronomer"],
            year: 2023,
            bibcode: "2023ApJ...123..456A"
        )

        let result2 = SearchResult(
            id: "semantic-3",
            sourceID: "semanticscholar",
            title: "Astronomy Paper",
            authors: ["Astronomer"],
            year: 2023,
            bibcode: "2023ApJ...123..456A"
        )

        let deduplicated = await service.deduplicate([result1, result2])

        XCTAssertEqual(deduplicated.count, 1)
        // ADS should be primary (higher priority than Semantic Scholar)
        XCTAssertEqual(deduplicated[0].primary.sourceID, "ads")
    }

    // MARK: - Fuzzy Matching

    func testFuzzyMatchByTitle() async {
        let result1 = SearchResult(
            id: "source1-1",
            sourceID: "crossref",
            title: "Deep Learning for Natural Language Processing",
            authors: ["Smith, John"],
            year: 2022
        )

        let result2 = SearchResult(
            id: "source2-1",
            sourceID: "dblp",
            title: "Deep Learning for Natural Language Processing",
            authors: ["John Smith"],
            year: 2022
        )

        let deduplicated = await service.deduplicate([result1, result2])

        XCTAssertEqual(deduplicated.count, 1)
        XCTAssertEqual(deduplicated[0].sourceIDs.count, 2)
    }

    // MARK: - No Deduplication

    func testDifferentPapersNotDeduplicated() async {
        let result1 = SearchResult(
            id: "paper1",
            sourceID: "crossref",
            title: "First Paper About Quantum Computing",
            authors: ["Alice Researcher"],
            year: 2023
        )

        let result2 = SearchResult(
            id: "paper2",
            sourceID: "crossref",
            title: "Second Paper About Machine Learning",
            authors: ["Bob Scientist"],
            year: 2023
        )

        let deduplicated = await service.deduplicate([result1, result2])

        XCTAssertEqual(deduplicated.count, 2)
    }

    func testSameTitleDifferentYears() async {
        let result1 = SearchResult(
            id: "paper-2020",
            sourceID: "crossref",
            title: "Annual Review of Progress",
            authors: ["Smith, John"],
            year: 2020
        )

        let result2 = SearchResult(
            id: "paper-2023",
            sourceID: "crossref",
            title: "Annual Review of Progress",
            authors: ["Smith, John"],
            year: 2023
        )

        let deduplicated = await service.deduplicate([result1, result2])

        // Different years should not be deduplicated (more than 1 year apart)
        XCTAssertEqual(deduplicated.count, 2)
    }

    // MARK: - Priority

    func testSourcePriority() async {
        let arxiv = SearchResult(
            id: "arxiv-id",
            sourceID: "arxiv",
            title: "Shared Paper",
            authors: ["Author"],
            year: 2023,
            doi: "10.1234/shared"
        )

        let crossref = SearchResult(
            id: "crossref-id",
            sourceID: "crossref",
            title: "Shared Paper",
            authors: ["Author"],
            year: 2023,
            doi: "10.1234/shared"
        )

        let semantic = SearchResult(
            id: "semantic-id",
            sourceID: "semanticscholar",
            title: "Shared Paper",
            authors: ["Author"],
            year: 2023,
            doi: "10.1234/shared"
        )

        // Test different orderings - Crossref should always be primary
        let deduplicated1 = await service.deduplicate([arxiv, crossref, semantic])
        XCTAssertEqual(deduplicated1[0].primary.sourceID, "crossref")

        let deduplicated2 = await service.deduplicate([semantic, arxiv, crossref])
        XCTAssertEqual(deduplicated2[0].primary.sourceID, "crossref")
    }

    // MARK: - Identifier Collection

    func testIdentifiersCollected() async {
        let result1 = SearchResult(
            id: "paper1",
            sourceID: "crossref",
            title: "Multi-ID Paper",
            authors: ["Author"],
            year: 2023,
            doi: "10.1234/paper",
            arxivID: nil
        )

        let result2 = SearchResult(
            id: "paper2",
            sourceID: "arxiv",
            title: "Multi-ID Paper",
            authors: ["Author"],
            year: 2023,
            doi: "10.1234/paper",
            arxivID: "2301.00001"
        )

        let deduplicated = await service.deduplicate([result1, result2])

        XCTAssertEqual(deduplicated.count, 1)
        XCTAssertNotNil(deduplicated[0].identifiers[.doi])
        XCTAssertNotNil(deduplicated[0].identifiers[.arxiv])
    }
}
