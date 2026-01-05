//
//  SemanticScholarEnrichmentTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-04.
//

import XCTest
@testable import PublicationManagerCore

// MARK: - Tests

final class SemanticScholarEnrichmentTests: XCTestCase {

    var session: URLSession!
    var source: SemanticScholarSource!

    override func setUp() {
        super.setUp()

        MockURLProtocol.reset()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)

        source = SemanticScholarSource(session: session)
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
        XCTAssertTrue(caps.contains(.authorStats))
    }

    func testDoesNotSupportOpenAccess() async {
        let caps = await source.enrichmentCapabilities

        // S2 doesn't provide OA status enum, just PDF URLs
        XCTAssertFalse(caps.contains(.openAccess))
    }

    func testDoesNotSupportVenue() async {
        let caps = await source.enrichmentCapabilities

        // S2 venue is in search, not enrichment caps
        XCTAssertFalse(caps.contains(.venue))
    }

    // MARK: - Enrich Success Tests

    func testEnrichWithDOI() async throws {
        let fixtureData = loadFixture("semantic_scholar_paper")
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("DOI:") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "10.48550/arXiv.1706.03762"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        // Verify data
        XCTAssertEqual(result.data.citationCount, 125000)
        XCTAssertEqual(result.data.referenceCount, 45)
        XCTAssertEqual(result.data.source, .semanticScholar)
    }

    func testEnrichWithArXivID() async throws {
        let fixtureData = loadFixture("semantic_scholar_paper")
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("ARXIV:") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.arxiv: "1706.03762"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertEqual(result.data.citationCount, 125000)
    }

    func testEnrichWithPMID() async throws {
        let fixtureData = loadFixture("semantic_scholar_minimal")
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("PMID:") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.pmid: "12345678"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertNotNil(result.data)
    }

    func testEnrichWithS2ID() async throws {
        let fixtureData = loadFixture("semantic_scholar_paper")
        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.absoluteString.contains("649def34f8be") == true)
            XCTAssertFalse(request.url?.absoluteString.contains("DOI:") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.semanticScholar: "649def34f8be52c8b66281af98ae884c09aef38b"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertEqual(result.data.citationCount, 125000)
    }

    func testEnrichReturnsAbstract() async throws {
        let fixtureData = loadFixture("semantic_scholar_paper")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertNotNil(result.data.abstract)
        XCTAssertTrue(result.data.abstract?.contains("Transformer") == true)
    }

    func testEnrichReturnsPDFURL() async throws {
        let fixtureData = loadFixture("semantic_scholar_paper")
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

    // MARK: - References Tests

    func testEnrichReturnsReferences() async throws {
        let fixtureData = loadFixture("semantic_scholar_paper")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertNotNil(result.data.references)
        XCTAssertEqual(result.data.references?.count, 2)

        let firstRef = result.data.references?.first
        XCTAssertEqual(firstRef?.title, "Neural Machine Translation by Jointly Learning to Align and Translate")
        XCTAssertEqual(firstRef?.year, 2014)
        XCTAssertEqual(firstRef?.authors.count, 3)
        XCTAssertEqual(firstRef?.authors.first, "Dzmitry Bahdanau")
        XCTAssertEqual(firstRef?.doi, "10.48550/arXiv.1409.0473")
        XCTAssertEqual(firstRef?.arxivID, "1409.0473")
        XCTAssertEqual(firstRef?.citationCount, 25000)
    }

    func testReferenceOpenAccessDetection() async throws {
        let fixtureData = loadFixture("semantic_scholar_paper")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        // First ref has openAccessPdf
        let openRef = result.data.references?.first
        XCTAssertEqual(openRef?.isOpenAccess, true)

        // Second ref has no openAccessPdf (null)
        let closedRef = result.data.references?[1]
        XCTAssertNil(closedRef?.isOpenAccess)
    }

    // MARK: - Citations Tests

    func testEnrichReturnsCitations() async throws {
        let fixtureData = loadFixture("semantic_scholar_paper")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertNotNil(result.data.citations)
        XCTAssertEqual(result.data.citations?.count, 2)

        let firstCite = result.data.citations?.first
        XCTAssertEqual(firstCite?.title, "BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding")
        XCTAssertEqual(firstCite?.year, 2018)
        XCTAssertEqual(firstCite?.citationCount, 95000)
    }

    func testCitationIdentifiers() async throws {
        let fixtureData = loadFixture("semantic_scholar_paper")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        let bert = result.data.citations?.first
        XCTAssertEqual(bert?.doi, "10.18653/v1/N19-1423")
        XCTAssertEqual(bert?.arxivID, "1810.04805")

        // GPT-3 only has arxiv
        let gpt3 = result.data.citations?[1]
        XCTAssertNil(gpt3?.doi)
        XCTAssertEqual(gpt3?.arxivID, "2005.14165")
    }

    // MARK: - Author Stats Tests

    func testEnrichReturnsAuthorStats() async throws {
        let fixtureData = loadFixture("semantic_scholar_paper")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertNotNil(result.data.authorStats)
        XCTAssertEqual(result.data.authorStats?.count, 3)

        let vaswani = result.data.authorStats?.first
        XCTAssertEqual(vaswani?.name, "Ashish Vaswani")
        XCTAssertEqual(vaswani?.hIndex, 38)
        XCTAssertEqual(vaswani?.citationCount, 150000)
        XCTAssertEqual(vaswani?.paperCount, 45)
        XCTAssertEqual(vaswani?.affiliations?.first, "Google Brain")
    }

    func testAuthorWithEmptyAffiliations() async throws {
        let fixtureData = loadFixture("semantic_scholar_paper")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        let parmar = result.data.authorStats?[2]
        XCTAssertEqual(parmar?.name, "Niki Parmar")
        XCTAssertNil(parmar?.affiliations)  // Empty array becomes nil
    }

    // MARK: - Minimal Response Tests

    func testEnrichWithMinimalResponse() async throws {
        let fixtureData = loadFixture("semantic_scholar_minimal")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertEqual(result.data.citationCount, 0)
        XCTAssertEqual(result.data.referenceCount, 0)
        XCTAssertNil(result.data.abstract)
        XCTAssertNil(result.data.pdfURLs)
        XCTAssertEqual(result.data.references?.count, 0)
        XCTAssertEqual(result.data.citations?.count, 0)
        XCTAssertEqual(result.data.authorStats?.count, 0)
    }

    // MARK: - Identifier Resolution Tests

    func testResolveIdentifierWithS2ID() async throws {
        let identifiers: [IdentifierType: String] = [.semanticScholar: "abc123"]
        let resolved = try await source.resolveIdentifier(from: identifiers)

        XCTAssertEqual(resolved[.semanticScholar], "abc123")
        XCTAssertEqual(resolved.count, 1)
    }

    func testResolveIdentifierFromDOI() async throws {
        let identifiers: [IdentifierType: String] = [.doi: "10.1234/test"]
        let resolved = try await source.resolveIdentifier(from: identifiers)

        XCTAssertEqual(resolved[.doi], "10.1234/test")
        XCTAssertEqual(resolved[.semanticScholar], "DOI:10.1234/test")
    }

    func testEnrichAddsS2IDToResolvedIdentifiers() async throws {
        let fixtureData = loadFixture("semantic_scholar_paper")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "10.48550/arXiv.1706.03762"]
        let result = try await source.enrich(identifiers: identifiers, existingData: nil)

        XCTAssertEqual(result.resolvedIdentifiers[.doi], "10.48550/arXiv.1706.03762")
        XCTAssertEqual(result.resolvedIdentifiers[.semanticScholar], "DOI:10.48550/arXiv.1706.03762")
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
        // bibcode is not supported by S2
        let identifiers: [IdentifierType: String] = [.bibcode: "2020ApJ...123...45A"]

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

    func testEnrichServerError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]

        do {
            _ = try await source.enrich(identifiers: identifiers, existingData: nil)
            XCTFail("Expected error")
        } catch let error as EnrichmentError {
            if case .networkError(let msg) = error {
                XCTAssertTrue(msg.contains("500"))
            } else {
                XCTFail("Expected networkError, got \(error)")
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
        let fixtureData = loadFixture("semantic_scholar_minimal")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let existingData = EnrichmentData(
            citationCount: 999,  // Will be overwritten by new data
            abstract: "Existing abstract",
            source: .ads,
            fetchedAt: Date()
        )

        let identifiers: [IdentifierType: String] = [.doi: "test"]
        let result = try await source.enrich(identifiers: identifiers, existingData: existingData)

        // Minimal fixture has citationCount: 0, which overwrites existing 999
        XCTAssertEqual(result.data.citationCount, 0)

        // Existing abstract should be preserved (minimal has null)
        // Note: merge prefers self (new data) over other (existing) for non-nil values
        // Since minimal.abstract is nil, existing.abstract is kept
        XCTAssertEqual(result.data.abstract, "Existing abstract")

        // Source should be the new enrichment source
        XCTAssertEqual(result.data.source, .semanticScholar)
    }

    // MARK: - Request Validation Tests

    func testEnrichRequestIncludesAllFields() async throws {
        var capturedURL: URL?
        let fixtureData = loadFixture("semantic_scholar_paper")

        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, fixtureData)
        }

        let identifiers: [IdentifierType: String] = [.doi: "test"]
        _ = try await source.enrich(identifiers: identifiers, existingData: nil)

        let urlString = capturedURL?.absoluteString ?? ""

        // Verify required fields are requested
        XCTAssertTrue(urlString.contains("citationCount"))
        XCTAssertTrue(urlString.contains("referenceCount"))
        XCTAssertTrue(urlString.contains("references"))
        XCTAssertTrue(urlString.contains("citations"))
        XCTAssertTrue(urlString.contains("authors"))
        XCTAssertTrue(urlString.contains("hIndex"))
        XCTAssertTrue(urlString.contains("openAccessPdf"))
        XCTAssertTrue(urlString.contains("abstract"))
    }

    // MARK: - Helper

    private func loadFixture(_ name: String) -> Data {
        let path = "/Users/tabel/Projects/imbib/PublicationManagerCore/Tests/PublicationManagerCoreTests/Enrichment/Fixtures/\(name).json"
        return try! Data(contentsOf: URL(fileURLWithPath: path))
    }
}
