//
//  SessionCacheTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-04.
//

import XCTest
@testable import PublicationManagerCore

final class SessionCacheTests: XCTestCase {

    // MARK: - Search Results Caching

    func testCacheSearchResults_storesResults() async {
        let cache = SessionCache.shared
        let results = [
            createMockSearchResult(id: "1", title: "Test Paper 1"),
            createMockSearchResult(id: "2", title: "Test Paper 2")
        ]

        // Cache results
        await cache.cacheSearchResults(results, for: "test query", sourceIDs: ["arxiv"])

        // Retrieve cached results
        let cached = await cache.getCachedResults(for: "test query", sourceIDs: ["arxiv"])

        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.count, 2)
    }

    func testCacheSearchResults_returnsNilForDifferentQuery() async {
        let cache = SessionCache.shared
        let results = [createMockSearchResult(id: "1", title: "Test")]

        await cache.cacheSearchResults(results, for: "query A", sourceIDs: ["arxiv"])

        // Different query should not return cached results
        let cached = await cache.getCachedResults(for: "query B", sourceIDs: ["arxiv"])

        XCTAssertNil(cached)
    }

    func testCacheSearchResults_caseInsensitiveQuery() async {
        let cache = SessionCache.shared
        let results = [createMockSearchResult(id: "1", title: "Test")]

        await cache.cacheSearchResults(results, for: "Machine Learning", sourceIDs: ["arxiv"])

        // Same query with different case should match
        let cached = await cache.getCachedResults(for: "machine learning", sourceIDs: ["arxiv"])

        XCTAssertNotNil(cached)
    }

    func testCacheSearchResults_differentSourceIDsAreSeparate() async {
        let cache = SessionCache.shared

        let arxivResults = [createMockSearchResult(id: "arxiv1", title: "ArXiv Paper")]
        let adsResults = [createMockSearchResult(id: "ads1", title: "ADS Paper")]

        await cache.cacheSearchResults(arxivResults, for: "quantum", sourceIDs: ["arxiv"])
        await cache.cacheSearchResults(adsResults, for: "quantum", sourceIDs: ["ads"])

        let arxivCached = await cache.getCachedResults(for: "quantum", sourceIDs: ["arxiv"])
        let adsCached = await cache.getCachedResults(for: "quantum", sourceIDs: ["ads"])

        XCTAssertEqual(arxivCached?.count, 1)
        XCTAssertEqual(adsCached?.count, 1)
        XCTAssertEqual(arxivCached?.first?.id, "arxiv1")
        XCTAssertEqual(adsCached?.first?.id, "ads1")
    }

    // MARK: - BibTeX Caching

    func testCacheBibTeX_storesAndRetrieves() async {
        let cache = SessionCache.shared
        let bibtex = """
        @article{Einstein1905,
            author = {Albert Einstein},
            title = {On the Electrodynamics}
        }
        """

        await cache.cacheBibTeX(bibtex, for: "paper123")

        let cached = await cache.getCachedBibTeX(for: "paper123")

        XCTAssertEqual(cached, bibtex)
    }

    func testCacheBibTeX_returnsNilForUnknownPaper() async {
        let cache = SessionCache.shared

        let cached = await cache.getCachedBibTeX(for: "unknown-paper-xyz")

        XCTAssertNil(cached)
    }

    // MARK: - Pending Metadata

    func testPendingMetadata_setAndGet() async {
        let cache = SessionCache.shared
        let metadata = PendingPaperMetadata(
            tags: ["important", "toread"],
            notes: "Great paper on quantum computing",
            customCiteKey: "MyCustomKey2020"
        )

        await cache.setMetadata(metadata, for: "paper456")

        let retrieved = await cache.getMetadata(for: "paper456")

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.tags, ["important", "toread"])
        XCTAssertEqual(retrieved?.notes, "Great paper on quantum computing")
        XCTAssertEqual(retrieved?.customCiteKey, "MyCustomKey2020")
    }

    func testPendingMetadata_updateSpecificFields() async {
        let cache = SessionCache.shared

        // Set initial metadata
        await cache.setMetadata(PendingPaperMetadata(notes: "Initial notes"), for: "paper789")

        // Update just the tags
        await cache.updateMetadata(for: "paper789", tags: ["newtag"])

        let retrieved = await cache.getMetadata(for: "paper789")

        XCTAssertEqual(retrieved?.tags, ["newtag"])
        XCTAssertEqual(retrieved?.notes, "Initial notes") // Should be preserved
    }

    func testPendingMetadata_clearAfterImport() async {
        let cache = SessionCache.shared

        await cache.setMetadata(PendingPaperMetadata(notes: "Notes"), for: "paperToImport")

        // Simulate clearing after import
        await cache.clearMetadata(for: "paperToImport")

        let retrieved = await cache.getMetadata(for: "paperToImport")

        XCTAssertNil(retrieved)
    }

    // MARK: - PendingPaperMetadata Tests

    func testPendingPaperMetadata_isEmpty() {
        let empty = PendingPaperMetadata()
        XCTAssertTrue(empty.isEmpty)

        let withTags = PendingPaperMetadata(tags: ["tag"])
        XCTAssertFalse(withTags.isEmpty)

        let withNotes = PendingPaperMetadata(notes: "Some notes")
        XCTAssertFalse(withNotes.isEmpty)

        let withCiteKey = PendingPaperMetadata(customCiteKey: "Key2020")
        XCTAssertFalse(withCiteKey.isEmpty)
    }

    func testPendingPaperMetadata_equatable() {
        let meta1 = PendingPaperMetadata(tags: ["a", "b"], notes: "Notes")
        let meta2 = PendingPaperMetadata(tags: ["a", "b"], notes: "Notes")
        let meta3 = PendingPaperMetadata(tags: ["c"], notes: "Notes")

        XCTAssertEqual(meta1, meta2)
        XCTAssertNotEqual(meta1, meta3)
    }

    func testPendingPaperMetadata_sendable() {
        // Verify Sendable conformance by passing across actor boundary
        let metadata = PendingPaperMetadata(tags: ["test"], notes: "Test notes")

        Task {
            await SessionCache.shared.setMetadata(metadata, for: "sendableTest")
        }

        // If this compiles, Sendable conformance is working
        XCTAssertTrue(true)
    }

    // MARK: - Cache Configuration Tests

    func testCacheConfiguration_constants() {
        XCTAssertEqual(SessionCache.maxSearchResults, 50)
        XCTAssertEqual(SessionCache.maxPDFCacheSize, 100 * 1024 * 1024) // 100 MB
        XCTAssertEqual(SessionCache.maxResultAge, 3600) // 1 hour
    }

    // MARK: - Helper Methods

    private func createMockSearchResult(id: String, title: String) -> SearchResult {
        SearchResult(
            id: id,
            sourceID: "mock",
            title: title,
            authors: ["Test Author"],
            year: 2020,
            venue: "Test Journal",
            abstract: "Test abstract"
        )
    }
}
