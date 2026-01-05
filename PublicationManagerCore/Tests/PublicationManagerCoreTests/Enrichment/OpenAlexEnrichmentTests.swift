//
//  OpenAlexEnrichmentTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-04.
//

import XCTest
@testable import PublicationManagerCore

final class OpenAlexEnrichmentTests: XCTestCase {

    var session: URLSession!
    var source: OpenAlexSource!

    override func setUp() {
        super.setUp()

        MockURLProtocol.reset()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)

        source = OpenAlexSource(session: session)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Capabilities Tests

    func testEnrichmentCapabilities() async {
        let caps = await source.enrichmentCapabilities

        XCTAssertTrue(caps.contains(.citationCount))
        XCTAssertTrue(caps.contains(.references))
        XCTAssertTrue(caps.contains(.citations))
        XCTAssertTrue(caps.contains(.abstract))
        XCTAssertTrue(caps.contains(.pdfURL))
        XCTAssertTrue(caps.contains(.openAccess))
        XCTAssertTrue(caps.contains(.venue))
    }

    func testDoesNotSupportAuthorStats() async {
        let caps = await source.enrichmentCapabilities
        XCTAssertFalse(caps.contains(.authorStats))
    }

    // MARK: - Enrich Success Tests

    func testEnrichWithDOI() async throws {
        let fixtureData = loadFixture("openalex_work")
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("doi.org") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "10.48550/arxiv.1706.03762"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertEqual(result.data.citationCount, 98000)
        XCTAssertEqual(result.data.source, .openAlex)
    }

    func testEnrichWithOpenAlexID() async throws {
        let fixtureData = loadFixture("openalex_work")
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("W2741809807") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.openAlex: "W2741809807"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertEqual(result.data.citationCount, 98000)
    }

    func testEnrichReturnsAbstract() async throws {
        let fixtureData = loadFixture("openalex_work")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertNotNil(result.data.abstract)
        // Abstract is reconstructed from inverted index
        XCTAssertTrue(result.data.abstract?.contains("Transformer") == true)
    }

    func testEnrichReturnsPDFURL() async throws {
        let fixtureData = loadFixture("openalex_work")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertNotNil(result.data.pdfURLs)
        XCTAssertEqual(result.data.pdfURLs?.count, 1)
        XCTAssertEqual(result.data.pdfURLs?.first?.absoluteString, "https://arxiv.org/pdf/1706.03762.pdf")
    }

    func testEnrichReturnsOpenAccessStatus() async throws {
        let fixtureData = loadFixture("openalex_work")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertEqual(result.data.openAccessStatus, .gold)
    }

    func testEnrichReturnsVenue() async throws {
        let fixtureData = loadFixture("openalex_work")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertEqual(result.data.venue, "Advances in Neural Information Processing Systems")
    }

    // MARK: - References Tests

    func testEnrichReturnsReferences() async throws {
        let fixtureData = loadFixture("openalex_work")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertNotNil(result.data.references)
        XCTAssertEqual(result.data.references?.count, 3)
        XCTAssertEqual(result.data.referenceCount, 3)

        // References are just IDs from OpenAlex
        let firstRef = result.data.references?.first
        XCTAssertEqual(firstRef?.id, "W2100837269")
    }

    // MARK: - Minimal Response Tests

    func testEnrichWithMinimalResponse() async throws {
        let fixtureData = loadFixture("openalex_minimal")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.openAlex: "W123456"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertEqual(result.data.citationCount, 0)
        XCTAssertEqual(result.data.referenceCount, 0)
        XCTAssertNil(result.data.abstract)
        XCTAssertNil(result.data.pdfURLs)
        XCTAssertNil(result.data.venue)
        XCTAssertEqual(result.data.openAccessStatus, .closed)
    }

    // MARK: - Identifier Resolution Tests

    func testResolveIdentifierWithOpenAlexID() async throws {
        let identifiers: [IdentifierType: String] = [.openAlex: "W12345"]
        let resolved = try await source.resolveIdentifier(from: identifiers)

        XCTAssertEqual(resolved[.openAlex], "W12345")
    }

    func testResolveIdentifierFromDOI() async throws {
        let identifiers: [IdentifierType: String] = [.doi: "10.1234/test"]
        let resolved = try await source.resolveIdentifier(from: identifiers)

        XCTAssertEqual(resolved[.doi], "10.1234/test")
        XCTAssertNotNil(resolved[.openAlex])
    }

    func testEnrichAddsOpenAlexIDToResolvedIdentifiers() async throws {
        let fixtureData = loadFixture("openalex_work")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "10.48550/arxiv.1706.03762"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertEqual(result.resolvedIdentifiers[.openAlex], "W2741809807")
    }

    // MARK: - Error Handling Tests

    func testEnrichWithNoIdentifiers() async {
        let identifiers: [IdentifierType: String] = [:]

        do {
            _ = try await source.enrich(identifiers: identifiers, existingData: nil)
            XCTFail("Expected error")
        } catch let error as EnrichmentError {
            if case .noIdentifier = error {
                // Expected
            } else {
                XCTFail("Expected noIdentifier error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEnrichWithUnsupportedIdentifier() async {
        // arXiv is not directly supported by OpenAlex
        let identifiers: [IdentifierType: String] = [.arxiv: "2301.12345"]

        do {
            _ = try await source.enrich(identifiers: identifiers, existingData: nil)
            XCTFail("Expected error")
        } catch let error as EnrichmentError {
            if case .noIdentifier = error {
                // Expected
            } else {
                XCTFail("Expected noIdentifier error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEnrichNotFound() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }

        let identifiers: [IdentifierType: String] = [.doi: "nonexistent"]

        do {
            _ = try await source.enrich(identifiers: identifiers, existingData: nil)
            XCTFail("Expected error")
        } catch let error as EnrichmentError {
            if case .notFound = error {
                // Expected
            } else {
                XCTFail("Expected notFound error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEnrichRateLimited() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]

        do {
            _ = try await source.enrich(identifiers: identifiers, existingData: nil)
            XCTFail("Expected error")
        } catch let error as EnrichmentError {
            if case .rateLimited = error {
                // Expected
            } else {
                XCTFail("Expected rateLimited error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEnrichMalformedJSON() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "invalid json".data(using: .utf8))
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]

        do {
            _ = try await source.enrich(identifiers: identifiers, existingData: nil)
            XCTFail("Expected error")
        } catch let error as EnrichmentError {
            if case .parseError = error {
                // Expected
            } else {
                XCTFail("Expected parseError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Merge Tests

    func testEnrichMergesWithExistingData() async throws {
        let fixtureData = loadFixture("openalex_minimal")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let existingData = EnrichmentData(
            citationCount: 999,
            abstract: "Existing abstract",
            source: .semanticScholar
        )

        let identifiers: [IdentifierType: String] = [.openAlex: "W123456"]
        let result = try await source.enrich(identifiers: identifiers, existingData: existingData)

        // New data (citationCount: 0) takes precedence
        XCTAssertEqual(result.data.citationCount, 0)

        // Existing abstract is kept since minimal has nil
        XCTAssertEqual(result.data.abstract, "Existing abstract")

        // Source is the new enrichment source
        XCTAssertEqual(result.data.source, .openAlex)
    }

    // MARK: - Helper

    private func loadFixture(_ name: String) -> Data {
        let path = "/Users/tabel/Projects/imbib/PublicationManagerCore/Tests/PublicationManagerCoreTests/Enrichment/Fixtures/\(name).json"
        return try! Data(contentsOf: URL(fileURLWithPath: path))
    }
}
