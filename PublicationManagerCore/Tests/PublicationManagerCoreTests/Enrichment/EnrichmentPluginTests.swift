//
//  EnrichmentPluginTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-04.
//

import XCTest
@testable import PublicationManagerCore

// MARK: - Mock Enrichment Plugin

/// Configurable mock for testing EnrichmentPlugin consumers.
actor MockEnrichmentPlugin: EnrichmentPlugin {

    // MARK: - Configuration

    let metadata: SourceMetadata
    let enrichmentCapabilities: EnrichmentCapabilities

    var enrichResult: EnrichmentResult?
    var shouldFail: EnrichmentError?
    var resolvedIdentifiers: [IdentifierType: String]?

    // MARK: - Tracking

    private(set) var enrichCallCount = 0
    private(set) var lastIdentifiers: [IdentifierType: String]?
    private(set) var resolveCallCount = 0

    // MARK: - Initialization

    init(
        id: String = "mock",
        name: String = "Mock Source",
        capabilities: EnrichmentCapabilities = .all,
        enrichResult: EnrichmentResult? = nil
    ) {
        self.metadata = SourceMetadata(
            id: id,
            name: name,
            description: "Mock source for testing"
        )
        self.enrichmentCapabilities = capabilities
        self.enrichResult = enrichResult
    }

    // MARK: - EnrichmentPlugin

    func enrich(
        identifiers: [IdentifierType: String],
        existingData: EnrichmentData?
    ) async throws -> EnrichmentResult {
        enrichCallCount += 1
        lastIdentifiers = identifiers

        if let error = shouldFail {
            throw error
        }

        if let result = enrichResult {
            return result
        }

        // Default mock result
        return EnrichmentResult(
            data: EnrichmentData(
                citationCount: 100,
                source: .semanticScholar,
                fetchedAt: Date()
            ),
            resolvedIdentifiers: identifiers
        )
    }

    func resolveIdentifier(
        from identifiers: [IdentifierType: String]
    ) async throws -> [IdentifierType: String] {
        resolveCallCount += 1

        if let resolved = resolvedIdentifiers {
            return identifiers.merging(with: resolved)
        }

        return identifiers
    }

    // MARK: - Test Helpers

    func setEnrichResult(_ result: EnrichmentResult) {
        self.enrichResult = result
    }

    func setFailure(_ error: EnrichmentError) {
        self.shouldFail = error
    }

    func setResolvedIdentifiers(_ ids: [IdentifierType: String]) {
        self.resolvedIdentifiers = ids
    }

    func reset() {
        enrichCallCount = 0
        lastIdentifiers = nil
        resolveCallCount = 0
        shouldFail = nil
    }
}

// MARK: - Tests

final class EnrichmentPluginTests: XCTestCase {

    // MARK: - Mock Plugin Tests

    func testMockPluginMetadata() async {
        let plugin = MockEnrichmentPlugin(
            id: "test",
            name: "Test Source",
            capabilities: [.citationCount, .references]
        )

        let metadata = await plugin.metadata
        XCTAssertEqual(metadata.id, "test")
        XCTAssertEqual(metadata.name, "Test Source")
    }

    func testMockPluginCapabilities() async {
        let plugin = MockEnrichmentPlugin(capabilities: [.citationCount, .abstract])

        let caps = await plugin.enrichmentCapabilities
        XCTAssertTrue(caps.contains(.citationCount))
        XCTAssertTrue(caps.contains(.abstract))
        XCTAssertFalse(caps.contains(.references))
    }

    func testMockPluginEnrichSuccess() async throws {
        let plugin = MockEnrichmentPlugin()

        let expectedResult = EnrichmentResult(
            data: EnrichmentData(
                citationCount: 500,
                abstract: "Test abstract",
                source: .semanticScholar
            ),
            resolvedIdentifiers: [.semanticScholar: "S2123"]
        )
        await plugin.setEnrichResult(expectedResult)

        let identifiers: [IdentifierType: String] = [.doi: "10.1234/test"]
        let result = try await plugin.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertEqual(result.data.citationCount, 500)
        XCTAssertEqual(result.data.abstract, "Test abstract")
        XCTAssertEqual(result.resolvedIdentifiers[.semanticScholar], "S2123")

        let callCount = await plugin.enrichCallCount
        XCTAssertEqual(callCount, 1)

        let lastIds = await plugin.lastIdentifiers
        XCTAssertEqual(lastIds?[.doi], "10.1234/test")
    }

    func testMockPluginEnrichFailure() async {
        let plugin = MockEnrichmentPlugin()
        await plugin.setFailure(.noIdentifier)

        let identifiers: [IdentifierType: String] = [.doi: "10.1234/test"]

        do {
            _ = try await plugin.enrich(identifiers: identifiers, existingData: nil)
            XCTFail("Expected error to be thrown")
        } catch let error as EnrichmentError {
            if case .noIdentifier = error {
                // Expected
            } else {
                XCTFail("Expected noIdentifier error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testMockPluginResolveIdentifiers() async throws {
        let plugin = MockEnrichmentPlugin()
        await plugin.setResolvedIdentifiers([.semanticScholar: "S2456"])

        let identifiers: [IdentifierType: String] = [.doi: "10.1234/test"]
        let resolved = try await plugin.resolveIdentifier(from: identifiers)

        XCTAssertEqual(resolved[.doi], "10.1234/test")
        XCTAssertEqual(resolved[.semanticScholar], "S2456")

        let resolveCount = await plugin.resolveCallCount
        XCTAssertEqual(resolveCount, 1)
    }

    func testMockPluginReset() async throws {
        let plugin = MockEnrichmentPlugin()

        // Make some calls
        _ = try await plugin.enrich(identifiers: [.doi: "10.1234/test"], existingData: nil)
        _ = try await plugin.resolveIdentifier(from: [:])

        await plugin.reset()

        let enrichCount = await plugin.enrichCallCount
        let resolveCount = await plugin.resolveCallCount

        XCTAssertEqual(enrichCount, 0)
        XCTAssertEqual(resolveCount, 0)
    }

    // MARK: - Protocol Default Implementation Tests

    func testDefaultResolveIdentifierPassthrough() async throws {
        let plugin = MockEnrichmentPlugin()

        // Without setting custom resolved identifiers, should pass through
        let identifiers: [IdentifierType: String] = [.doi: "10.1234/test", .arxiv: "2301.12345"]
        let resolved = try await plugin.resolveIdentifier(from: identifiers)

        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual(resolved[.doi], "10.1234/test")
        XCTAssertEqual(resolved[.arxiv], "2301.12345")
    }

    func testCanEnrichWithIdentifiers() async {
        let plugin = MockEnrichmentPlugin()

        let identifiers: [IdentifierType: String] = [.doi: "10.1234/test"]
        let canEnrich = await plugin.canEnrich(identifiers: identifiers)

        XCTAssertTrue(canEnrich)
    }

    func testCanEnrichWithoutIdentifiers() async {
        let plugin = MockEnrichmentPlugin()

        let identifiers: [IdentifierType: String] = [:]
        let canEnrich = await plugin.canEnrich(identifiers: identifiers)

        XCTAssertFalse(canEnrich)
    }

    func testSupportsCapability() async {
        let plugin = MockEnrichmentPlugin(capabilities: [.citationCount, .references])

        let hasCitations = await plugin.supports(.citationCount)
        let hasRefs = await plugin.supports(.references)
        let hasAuthorStats = await plugin.supports(.authorStats)

        XCTAssertTrue(hasCitations)
        XCTAssertTrue(hasRefs)
        XCTAssertFalse(hasAuthorStats)
    }

    // MARK: - Identifier Map Extension Tests

    func testIdentifierMapFromDOI() {
        let ids = [IdentifierType: String].from(doi: "10.1234/test")

        XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(ids.doi, "10.1234/test")
    }

    func testIdentifierMapFromArXiv() {
        let ids = [IdentifierType: String].from(arxivID: "2301.12345")

        XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(ids.arxivID, "2301.12345")
    }

    func testIdentifierMapFromBibcode() {
        let ids = [IdentifierType: String].from(bibcode: "2020ApJ...123...45A")

        XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(ids.bibcode, "2020ApJ...123...45A")
    }

    func testIdentifierMapMerging() {
        let ids1: [IdentifierType: String] = [.doi: "10.1234/test"]
        let ids2: [IdentifierType: String] = [.arxiv: "2301.12345", .semanticScholar: "S2123"]

        let merged = ids1.merging(with: ids2)

        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.doi, "10.1234/test")
        XCTAssertEqual(merged.arxivID, "2301.12345")
        XCTAssertEqual(merged.semanticScholarID, "S2123")
    }

    func testIdentifierMapMergingOverwrites() {
        let ids1: [IdentifierType: String] = [.doi: "old-doi"]
        let ids2: [IdentifierType: String] = [.doi: "new-doi"]

        let merged = ids1.merging(with: ids2)

        XCTAssertEqual(merged.doi, "new-doi")  // Other takes precedence
    }

    func testIdentifierMapAccessors() {
        let ids: [IdentifierType: String] = [
            .doi: "10.1234/test",
            .arxiv: "2301.12345",
            .bibcode: "2020ApJ...123...45A",
            .semanticScholar: "S2123",
            .openAlex: "W123456"
        ]

        XCTAssertEqual(ids.doi, "10.1234/test")
        XCTAssertEqual(ids.arxivID, "2301.12345")
        XCTAssertEqual(ids.bibcode, "2020ApJ...123...45A")
        XCTAssertEqual(ids.semanticScholarID, "S2123")
        XCTAssertEqual(ids.openAlexID, "W123456")
    }

    func testIdentifierMapNilAccessors() {
        let ids: [IdentifierType: String] = [.doi: "10.1234/test"]

        XCTAssertEqual(ids.doi, "10.1234/test")
        XCTAssertNil(ids.arxivID)
        XCTAssertNil(ids.bibcode)
    }

    // MARK: - Multiple Plugins Tests

    func testMultiplePluginsWithDifferentCapabilities() async throws {
        let s2Plugin = MockEnrichmentPlugin(
            id: "s2",
            name: "Semantic Scholar",
            capabilities: [.citationCount, .references, .citations]
        )

        let oaPlugin = MockEnrichmentPlugin(
            id: "oa",
            name: "OpenAlex",
            capabilities: [.citationCount, .openAccess, .venue]
        )

        // S2 has refs/cites, OA doesn't
        let s2HasRefs = await s2Plugin.supports(.references)
        let oaHasRefs = await oaPlugin.supports(.references)
        XCTAssertTrue(s2HasRefs)
        XCTAssertFalse(oaHasRefs)

        // OA has openAccess, S2 doesn't
        let s2HasOA = await s2Plugin.supports(.openAccess)
        let oaHasOA = await oaPlugin.supports(.openAccess)
        XCTAssertFalse(s2HasOA)
        XCTAssertTrue(oaHasOA)

        // Both have citation count
        let s2HasCites = await s2Plugin.supports(.citationCount)
        let oaHasCites = await oaPlugin.supports(.citationCount)
        XCTAssertTrue(s2HasCites)
        XCTAssertTrue(oaHasCites)
    }

    func testPluginCallTracking() async throws {
        let plugin = MockEnrichmentPlugin()

        // Initial state
        var count = await plugin.enrichCallCount
        XCTAssertEqual(count, 0)

        // After first call
        _ = try await plugin.enrich(identifiers: [.doi: "1"], existingData: nil)
        count = await plugin.enrichCallCount
        XCTAssertEqual(count, 1)

        // After second call
        _ = try await plugin.enrich(identifiers: [.doi: "2"], existingData: nil)
        count = await plugin.enrichCallCount
        XCTAssertEqual(count, 2)

        // Last identifiers should be from second call
        let lastIds = await plugin.lastIdentifiers
        XCTAssertEqual(lastIds?[.doi], "2")
    }

    // MARK: - Error Handling Tests

    func testEnrichmentErrorNoSourceAvailable() async {
        let plugin = MockEnrichmentPlugin()
        await plugin.setFailure(.noSourceAvailable)

        do {
            _ = try await plugin.enrich(identifiers: [.doi: "test"], existingData: nil)
            XCTFail("Expected error")
        } catch let error as EnrichmentError {
            XCTAssertEqual(error.errorDescription, "No enrichment source could provide data")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEnrichmentErrorRateLimited() async {
        let plugin = MockEnrichmentPlugin()
        await plugin.setFailure(.rateLimited(retryAfter: 120))

        do {
            _ = try await plugin.enrich(identifiers: [.doi: "test"], existingData: nil)
            XCTFail("Expected error")
        } catch let error as EnrichmentError {
            XCTAssertTrue(error.errorDescription?.contains("120") == true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEnrichmentErrorNetworkError() async {
        let plugin = MockEnrichmentPlugin()
        await plugin.setFailure(.networkError("Connection refused"))

        do {
            _ = try await plugin.enrich(identifiers: [.doi: "test"], existingData: nil)
            XCTFail("Expected error")
        } catch let error as EnrichmentError {
            XCTAssertTrue(error.errorDescription?.contains("Connection refused") == true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
