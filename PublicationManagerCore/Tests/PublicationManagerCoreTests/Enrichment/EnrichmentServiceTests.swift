//
//  EnrichmentServiceTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-04.
//

import XCTest
@testable import PublicationManagerCore

// MARK: - Mock Settings Provider

actor MockSettingsProvider: EnrichmentSettingsProvider {
    var preferredSource: EnrichmentSource = .semanticScholar
    var sourcePriority: [EnrichmentSource] = [.semanticScholar, .openAlex, .ads]
    var autoSyncEnabled: Bool = true
    var refreshIntervalDays: Int = 7

    func setSourcePriority(_ priority: [EnrichmentSource]) {
        sourcePriority = priority
    }
}

// MARK: - Tests

final class EnrichmentServiceTests: XCTestCase {

    var mockPlugin1: MockEnrichmentPlugin!
    var mockPlugin2: MockEnrichmentPlugin!
    var settingsProvider: MockSettingsProvider!
    var service: EnrichmentService!

    override func setUp() async throws {
        mockPlugin1 = MockEnrichmentPlugin(
            id: "semanticscholar",
            name: "Semantic Scholar",
            capabilities: [.citationCount, .references]
        )

        mockPlugin2 = MockEnrichmentPlugin(
            id: "openalex",
            name: "OpenAlex",
            capabilities: [.citationCount, .openAccess]
        )

        settingsProvider = MockSettingsProvider()

        service = EnrichmentService(
            plugins: [mockPlugin1, mockPlugin2],
            settingsProvider: settingsProvider
        )
    }

    // MARK: - Basic Enrichment Tests

    func testEnrichNowWithValidIdentifiers() async throws {
        let expectedResult = EnrichmentResult(
            data: EnrichmentData(
                citationCount: 100,
                source: .semanticScholar
            ),
            resolvedIdentifiers: [.doi: "10.1234/test"]
        )
        await mockPlugin1.setEnrichResult(expectedResult)

        let identifiers: [IdentifierType: String] = [.doi: "10.1234/test"]
        let result = try await service.enrichNow(identifiers: identifiers)

        XCTAssertEqual(result.data.citationCount, 100)
        XCTAssertEqual(result.data.source, .semanticScholar)
    }

    func testEnrichNowWithNoIdentifiers() async {
        let identifiers: [IdentifierType: String] = [:]

        do {
            _ = try await service.enrichNow(identifiers: identifiers)
            XCTFail("Expected error")
        } catch let error as EnrichmentError {
            XCTAssertEqual(error.errorDescription, EnrichmentError.noIdentifier.errorDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEnrichNowTriesPluginsInPriorityOrder() async throws {
        // Set up settings to prefer openAlex first
        await settingsProvider.setSourcePriority([.openAlex, .semanticScholar])

        let oaResult = EnrichmentResult(
            data: EnrichmentData(citationCount: 50, source: .openAlex),
            resolvedIdentifiers: [:]
        )
        await mockPlugin2.setEnrichResult(oaResult)

        let identifiers: [IdentifierType: String] = [.doi: "10.1234/test"]
        let result = try await service.enrichNow(identifiers: identifiers)

        // Should use OpenAlex since it's first in priority
        XCTAssertEqual(result.data.source, .openAlex)
        XCTAssertEqual(result.data.citationCount, 50)

        // OpenAlex should have been called
        let oaCallCount = await mockPlugin2.enrichCallCount
        XCTAssertEqual(oaCallCount, 1)
    }

    func testEnrichNowFallsBackOnFailure() async throws {
        // First plugin fails
        await mockPlugin1.setFailure(.networkError("Connection failed"))

        // Second plugin succeeds
        let oaResult = EnrichmentResult(
            data: EnrichmentData(citationCount: 75, source: .openAlex),
            resolvedIdentifiers: [:]
        )
        await mockPlugin2.setEnrichResult(oaResult)

        let identifiers: [IdentifierType: String] = [.doi: "10.1234/test"]
        let result = try await service.enrichNow(identifiers: identifiers)

        // Should fall back to OpenAlex
        XCTAssertEqual(result.data.source, .openAlex)

        // Both plugins should have been tried
        let s2CallCount = await mockPlugin1.enrichCallCount
        let oaCallCount = await mockPlugin2.enrichCallCount
        XCTAssertEqual(s2CallCount, 1)
        XCTAssertEqual(oaCallCount, 1)
    }

    func testEnrichNowDoesNotFallbackOnRateLimited() async {
        await mockPlugin1.setFailure(.rateLimited(retryAfter: 60))

        let identifiers: [IdentifierType: String] = [.doi: "10.1234/test"]

        do {
            _ = try await service.enrichNow(identifiers: identifiers)
            XCTFail("Expected rate limited error")
        } catch let error as EnrichmentError {
            if case .rateLimited = error {
                // Expected - should not fall back
            } else {
                XCTFail("Expected rateLimited error")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // Second plugin should NOT have been tried
        let oaCallCount = await mockPlugin2.enrichCallCount
        XCTAssertEqual(oaCallCount, 0)
    }

    func testEnrichNowAllPluginsFail() async {
        await mockPlugin1.setFailure(.notFound)
        await mockPlugin2.setFailure(.notFound)

        let identifiers: [IdentifierType: String] = [.doi: "10.1234/test"]

        do {
            _ = try await service.enrichNow(identifiers: identifiers)
            XCTFail("Expected error")
        } catch let error as EnrichmentError {
            // Should throw the last error
            if case .notFound = error {
                // Expected
            } else {
                XCTFail("Expected notFound error")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Search Result Enrichment

    func testEnrichSearchResult() async throws {
        let expectedResult = EnrichmentResult(
            data: EnrichmentData(citationCount: 200, source: .semanticScholar),
            resolvedIdentifiers: [:]
        )
        await mockPlugin1.setEnrichResult(expectedResult)

        let searchResult = SearchResult(
            id: "test",
            sourceID: "test",
            title: "Test Paper",
            doi: "10.1234/test",
            arxivID: "2301.12345"
        )

        let result = try await service.enrichSearchResult(searchResult)

        XCTAssertEqual(result.data.citationCount, 200)

        // Should have used identifiers from search result
        let lastIds = await mockPlugin1.lastIdentifiers
        XCTAssertEqual(lastIds?[.doi], "10.1234/test")
        XCTAssertEqual(lastIds?[.arxiv], "2301.12345")
    }

    // MARK: - Queue Management Tests

    func testQueueForEnrichment() async {
        let publicationID = UUID()
        let identifiers: [IdentifierType: String] = [.doi: "10.1234/test"]

        await service.queueForEnrichment(
            publicationID: publicationID,
            identifiers: identifiers,
            priority: .libraryPaper
        )

        let depth = await service.queueDepth()
        XCTAssertEqual(depth, 1)
    }

    func testProcessNextQueued() async throws {
        let expectedResult = EnrichmentResult(
            data: EnrichmentData(citationCount: 50, source: .semanticScholar),
            resolvedIdentifiers: [:]
        )
        await mockPlugin1.setEnrichResult(expectedResult)

        let publicationID = UUID()
        await service.queueForEnrichment(
            publicationID: publicationID,
            identifiers: [.doi: "10.1234/test"],
            priority: .userTriggered
        )

        let result = await service.processNextQueued()

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.0, publicationID)

        switch result?.1 {
        case .success(let data):
            XCTAssertEqual(data.data.citationCount, 50)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        case .none:
            XCTFail("Expected result")
        }

        // Queue should be empty now
        let depth = await service.queueDepth()
        XCTAssertEqual(depth, 0)
    }

    func testProcessNextQueuedEmptyQueue() async {
        let result = await service.processNextQueued()
        XCTAssertNil(result)
    }

    func testProcessNextQueuedWithFailure() async {
        await mockPlugin1.setFailure(.notFound)
        await mockPlugin2.setFailure(.notFound)

        let publicationID = UUID()
        await service.queueForEnrichment(
            publicationID: publicationID,
            identifiers: [.doi: "10.1234/test"],
            priority: .libraryPaper
        )

        let result = await service.processNextQueued()

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.0, publicationID)

        switch result?.1 {
        case .success:
            XCTFail("Expected failure")
        case .failure:
            // Expected
            break
        case .none:
            XCTFail("Expected result")
        }
    }

    // MARK: - Background Sync Tests

    func testStartBackgroundSync() async {
        let isRunning1 = await service.isRunning
        XCTAssertFalse(isRunning1)

        await service.startBackgroundSync()

        let isRunning2 = await service.isRunning
        XCTAssertTrue(isRunning2)

        await service.stopBackgroundSync()

        let isRunning3 = await service.isRunning
        XCTAssertFalse(isRunning3)
    }

    func testStartBackgroundSyncIdempotent() async {
        await service.startBackgroundSync()
        await service.startBackgroundSync()  // Should not start second time

        let isRunning = await service.isRunning
        XCTAssertTrue(isRunning)

        await service.stopBackgroundSync()
    }

    func testStopBackgroundSyncWhenNotRunning() async {
        // Should not crash
        await service.stopBackgroundSync()

        let isRunning = await service.isRunning
        XCTAssertFalse(isRunning)
    }

    // MARK: - Plugin Access Tests

    func testRegisteredPlugins() async {
        let plugins = await service.registeredPlugins
        XCTAssertEqual(plugins.count, 2)
    }

    func testPluginForSourceID() async {
        let plugin = await service.plugin(for: "semanticscholar")
        XCTAssertNotNil(plugin)

        let metadata = await plugin?.metadata
        XCTAssertEqual(metadata?.name, "Semantic Scholar")
    }

    func testPluginForUnknownSourceID() async {
        let plugin = await service.plugin(for: "unknown")
        XCTAssertNil(plugin)
    }

    func testPluginsSupportingCapability() async {
        let citationPlugins = await service.plugins(supporting: .citationCount)
        XCTAssertEqual(citationPlugins.count, 2)  // Both support citation count

        let refsPlugins = await service.plugins(supporting: .references)
        XCTAssertEqual(refsPlugins.count, 1)  // Only S2 supports references

        let oaPlugins = await service.plugins(supporting: .openAccess)
        XCTAssertEqual(oaPlugins.count, 1)  // Only OpenAlex supports open access
    }

    // MARK: - Existing Data Merge Tests

    func testEnrichNowMergesWithExistingData() async throws {
        // New data has citation count but no abstract
        let newResult = EnrichmentResult(
            data: EnrichmentData(
                citationCount: 150,
                abstract: nil,
                source: .semanticScholar
            ),
            resolvedIdentifiers: [:]
        )
        await mockPlugin1.setEnrichResult(newResult)

        let existingData = EnrichmentData(
            citationCount: 100,
            abstract: "Existing abstract",
            source: .ads
        )

        let identifiers: [IdentifierType: String] = [.doi: "10.1234/test"]
        let result = try await service.enrichNow(identifiers: identifiers, existingData: existingData)

        // Plugin should have received existing data
        // (the actual merge behavior is tested in plugin tests)
        let callCount = await mockPlugin1.enrichCallCount
        XCTAssertEqual(callCount, 1)
    }
}

// MARK: - Default Settings Provider Tests

final class DefaultEnrichmentSettingsProviderTests: XCTestCase {

    func testDefaultSettings() async {
        let provider = DefaultEnrichmentSettingsProvider()

        let preferred = await provider.preferredSource
        let priority = await provider.sourcePriority
        let autoSync = await provider.autoSyncEnabled
        let interval = await provider.refreshIntervalDays

        XCTAssertEqual(preferred, .semanticScholar)
        XCTAssertEqual(priority, [.semanticScholar, .openAlex, .ads])
        XCTAssertTrue(autoSync)
        XCTAssertEqual(interval, 7)
    }

    func testCustomSettings() async {
        let settings = EnrichmentSettings(
            preferredSource: .openAlex,
            sourcePriority: [.ads, .openAlex],
            autoSyncEnabled: false,
            refreshIntervalDays: 14
        )
        let provider = DefaultEnrichmentSettingsProvider(settings: settings)

        let preferred = await provider.preferredSource
        let priority = await provider.sourcePriority
        let autoSync = await provider.autoSyncEnabled
        let interval = await provider.refreshIntervalDays

        XCTAssertEqual(preferred, .openAlex)
        XCTAssertEqual(priority, [.ads, .openAlex])
        XCTAssertFalse(autoSync)
        XCTAssertEqual(interval, 14)
    }

    func testUpdateSettings() async {
        let provider = DefaultEnrichmentSettingsProvider()

        let newSettings = EnrichmentSettings(
            preferredSource: .ads,
            sourcePriority: [.ads],
            autoSyncEnabled: false,
            refreshIntervalDays: 30
        )
        await provider.update(newSettings)

        let preferred = await provider.preferredSource
        XCTAssertEqual(preferred, .ads)
    }
}
