//
//  DBLPSourceTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-04.
//

import XCTest
@testable import PublicationManagerCore

final class DBLPSourceTests: XCTestCase {

    // MARK: - Properties

    private var source: DBLPSource!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()
        source = DBLPSource()
    }

    override func tearDown() async throws {
        source = nil
        MockURLProtocol.reset()
        try await super.tearDown()
    }

    // MARK: - Metadata Tests

    func testMetadata_hasCorrectID() {
        let metadata = source.metadata

        XCTAssertEqual(metadata.id, "dblp")
    }

    func testMetadata_hasCorrectName() {
        let metadata = source.metadata

        XCTAssertEqual(metadata.name, "DBLP")
    }

    func testMetadata_hasNoCredentialRequirement() {
        let metadata = source.metadata

        XCTAssertEqual(metadata.credentialRequirement, .none)
    }

    func testMetadata_hasNoRateLimit() {
        let metadata = source.metadata

        XCTAssertEqual(metadata.rateLimit, .none)
    }

    func testMetadata_hasDeduplicationPriority() {
        let metadata = source.metadata

        XCTAssertEqual(metadata.deduplicationPriority, 70)
    }

    func testMetadata_hasIconName() {
        let metadata = source.metadata

        XCTAssertEqual(metadata.iconName, "desktopcomputer")
    }

    // MARK: - Response Parsing Tests

    func testParsing_validResponse_extractsResults() async throws {
        // Given
        let fixtureData = try loadFixture("dblp_search_database")
        MockURLProtocol.register(pattern: "dblp.org", response: .json(fixtureData))

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        // When
        let results = try await source.search(query: "database")

        // Then
        XCTAssertEqual(results.count, 3)
    }

    func testParsing_extractsTitle() async throws {
        // Given
        let fixtureData = try loadFixture("dblp_search_database")
        MockURLProtocol.register(pattern: "dblp.org", response: .json(fixtureData))

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        // When
        let results = try await source.search(query: "database")

        // Then
        XCTAssertTrue(results.contains { $0.title.contains("Relational Model") })
        XCTAssertTrue(results.contains { $0.title.contains("POSTGRES") })
        XCTAssertTrue(results.contains { $0.title.contains("Distributed System") })
    }

    func testParsing_extractsAuthors() async throws {
        // Given
        let fixtureData = try loadFixture("dblp_search_database")
        MockURLProtocol.register(pattern: "dblp.org", response: .json(fixtureData))

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        // When
        let results = try await source.search(query: "database")

        // Then
        let coddPaper = results.first { $0.title.contains("Relational Model") }
        XCTAssertNotNil(coddPaper)
        XCTAssertTrue(coddPaper?.authors.contains("Edgar F. Codd") == true)

        let postgresPaper = results.first { $0.title.contains("POSTGRES") }
        XCTAssertNotNil(postgresPaper)
        XCTAssertEqual(postgresPaper?.authors.count, 2)
        XCTAssertTrue(postgresPaper?.authors.contains("Michael Stonebraker") == true)
    }

    func testParsing_extractsYear() async throws {
        // Given
        let fixtureData = try loadFixture("dblp_search_database")
        MockURLProtocol.register(pattern: "dblp.org", response: .json(fixtureData))

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        // When
        let results = try await source.search(query: "database")

        // Then
        let coddPaper = results.first { $0.title.contains("Relational Model") }
        XCTAssertEqual(coddPaper?.year, 1970)

        let postgresPaper = results.first { $0.title.contains("POSTGRES") }
        XCTAssertEqual(postgresPaper?.year, 1986)
    }

    func testParsing_extractsVenue() async throws {
        // Given
        let fixtureData = try loadFixture("dblp_search_database")
        MockURLProtocol.register(pattern: "dblp.org", response: .json(fixtureData))

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        // When
        let results = try await source.search(query: "database")

        // Then
        let coddPaper = results.first { $0.title.contains("Relational Model") }
        XCTAssertEqual(coddPaper?.venue, "Communications of the ACM")

        let postgresPaper = results.first { $0.title.contains("POSTGRES") }
        XCTAssertEqual(postgresPaper?.venue, "SIGMOD Conference")
    }

    func testParsing_extractsDOI() async throws {
        // Given
        let fixtureData = try loadFixture("dblp_search_database")
        MockURLProtocol.register(pattern: "dblp.org", response: .json(fixtureData))

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        // When
        let results = try await source.search(query: "database")

        // Then
        let coddPaper = results.first { $0.title.contains("Relational Model") }
        XCTAssertEqual(coddPaper?.doi, "10.1145/362384.362685")
    }

    func testParsing_generatesBibTeXURL() async throws {
        // Given
        let fixtureData = try loadFixture("dblp_search_database")
        MockURLProtocol.register(pattern: "dblp.org", response: .json(fixtureData))

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        // When
        let results = try await source.search(query: "database")

        // Then
        let coddPaper = results.first { $0.title.contains("Relational Model") }
        XCTAssertEqual(coddPaper?.bibtexURL?.absoluteString, "https://dblp.org/rec/journals/cacm/Codd70.bib")
    }

    func testParsing_generatesWebURL() async throws {
        // Given
        let fixtureData = try loadFixture("dblp_search_database")
        MockURLProtocol.register(pattern: "dblp.org", response: .json(fixtureData))

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        // When
        let results = try await source.search(query: "database")

        // Then
        let coddPaper = results.first { $0.title.contains("Relational Model") }
        XCTAssertEqual(coddPaper?.webURL?.absoluteString, "https://dblp.org/rec/journals/cacm/Codd70")
    }

    func testParsing_setsPDFURLFromEE() async throws {
        // Given
        let fixtureData = try loadFixture("dblp_search_database")
        MockURLProtocol.register(pattern: "dblp.org", response: .json(fixtureData))

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        // When
        let results = try await source.search(query: "database")

        // Then
        let coddPaper = results.first { $0.title.contains("Relational Model") }
        XCTAssertEqual(coddPaper?.pdfURL?.absoluteString, "https://doi.org/10.1145/362384.362685")
    }

    func testParsing_setsSourceID() async throws {
        // Given
        let fixtureData = try loadFixture("dblp_search_database")
        MockURLProtocol.register(pattern: "dblp.org", response: .json(fixtureData))

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        // When
        let results = try await source.search(query: "database")

        // Then
        XCTAssertTrue(results.allSatisfy { $0.sourceID == "dblp" })
    }

    // MARK: - Empty Response Tests

    func testParsing_emptyResponse_returnsEmptyArray() async throws {
        // Given
        let emptyResponse = """
        {
            "result": {
                "hits": {
                    "@total": "0",
                    "@computed": "0",
                    "@sent": "0"
                },
                "query": "xyzabc123notfound",
                "status": {"@code": "200", "text": "OK"}
            }
        }
        """.data(using: .utf8)!

        MockURLProtocol.register(pattern: "dblp.org", response: .json(emptyResponse))

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        // When
        let results = try await source.search(query: "xyzabc123notfound")

        // Then
        XCTAssertTrue(results.isEmpty)
    }

    func testParsing_malformedJSON_returnsEmptyArray() async throws {
        // Given
        let malformedData = "not json".data(using: .utf8)!

        MockURLProtocol.register(pattern: "dblp.org", response: .text("not json"))

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        // When
        let results = try await source.search(query: "test")

        // Then
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Error Handling Tests

    func testSearch_networkError_throws() async {
        // Given
        MockURLProtocol.register(pattern: "dblp.org", response: .error(URLError(.notConnectedToInternet)))

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        // When/Then
        do {
            _ = try await source.search(query: "test")
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
        }
    }

    func testSearch_serverError_throws() async {
        // Given
        MockURLProtocol.register(pattern: "dblp.org", response: .serverError)

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        // When/Then
        do {
            _ = try await source.search(query: "test")
            XCTFail("Expected error to be thrown")
        } catch {
            guard case SourceError.networkError = error else {
                XCTFail("Expected networkError")
                return
            }
        }
    }

    // MARK: - Normalize Tests

    func testNormalize_returnsEntryUnmodified() {
        // Given
        let entry = BibTeXEntry(
            citeKey: "Codd1970",
            entryType: "article",
            fields: ["title": "Test", "author": "Codd"]
        )

        // When
        let normalized = source.normalize(entry)

        // Then
        XCTAssertEqual(normalized.citeKey, entry.citeKey)
        XCTAssertEqual(normalized.entryType, entry.entryType)
        XCTAssertEqual(normalized.fields, entry.fields)
    }

    // MARK: - Single Author Tests

    func testParsing_singleAuthor_extractsCorrectly() async throws {
        // Given - single author response (fixture has Edgar F. Codd as single author)
        let fixtureData = try loadFixture("dblp_search_database")
        MockURLProtocol.register(pattern: "dblp.org", response: .json(fixtureData))

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        // When
        let results = try await source.search(query: "database")

        // Then - Lamport paper should have single author
        let lamportPaper = results.first { $0.title.contains("Time, Clocks") }
        XCTAssertNotNil(lamportPaper)
        XCTAssertEqual(lamportPaper?.authors.count, 1)
        XCTAssertEqual(lamportPaper?.authors.first, "Leslie Lamport")
    }

    // MARK: - BibTeX Fetch Tests

    func testFetchBibTeX_validResponse_returnsEntry() async throws {
        // Given
        let bibtexResponse = """
        @article{DBLP:journals/cacm/Codd70,
          author    = {Edgar F. Codd},
          title     = {A Relational Model of Data for Large Shared Data Banks},
          journal   = {Communications of the ACM},
          volume    = {13},
          number    = {6},
          pages     = {377--387},
          year      = {1970},
          doi       = {10.1145/362384.362685}
        }
        """

        MockURLProtocol.register(pattern: "dblp.org/rec", response: .text(bibtexResponse))

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        let searchResult = SearchResult(
            id: "journals/cacm/Codd70",
            sourceID: "dblp",
            title: "A Relational Model",
            authors: ["Edgar F. Codd"],
            year: 1970,
            venue: nil,
            bibtexURL: URL(string: "https://dblp.org/rec/journals/cacm/Codd70.bib")
        )

        // When
        let entry = try await source.fetchBibTeX(for: searchResult)

        // Then
        XCTAssertEqual(entry.entryType, "article")
        XCTAssertEqual(entry.fields["author"], "Edgar F. Codd")
        XCTAssertEqual(entry.fields["year"], "1970")
        XCTAssertEqual(entry.fields["doi"], "10.1145/362384.362685")
    }

    func testFetchBibTeX_noBibtexURL_throws() async {
        // Given
        let searchResult = SearchResult(
            id: "test",
            sourceID: "dblp",
            title: "Test",
            authors: [],
            year: nil,
            venue: nil,
            bibtexURL: nil  // No BibTeX URL
        )

        // When/Then
        do {
            _ = try await source.fetchBibTeX(for: searchResult)
            XCTFail("Expected error to be thrown")
        } catch {
            guard case SourceError.notFound = error else {
                XCTFail("Expected notFound error")
                return
            }
        }
    }

    // MARK: - URL Query Tests

    func testSearch_sendsCorrectQueryParameters() async throws {
        // Given
        let fixtureData = try loadFixture("dblp_search_database")
        MockURLProtocol.register(pattern: "dblp.org", response: .json(fixtureData))

        let mockSession = MockURLProtocol.mockURLSession()
        let source = DBLPSource(session: mockSession)

        // When
        _ = try await source.search(query: "machine learning")

        // Then
        let request = MockURLProtocol.lastRequest
        XCTAssertNotNil(request)

        let url = request?.url
        XCTAssertTrue(url?.absoluteString.contains("q=machine%20learning") == true ||
                     url?.absoluteString.contains("q=machine+learning") == true)
        XCTAssertTrue(url?.absoluteString.contains("format=json") == true)
        XCTAssertTrue(url?.absoluteString.contains("h=50") == true)
    }

    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> Data {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/Responses") else {
            throw TestError.fixtureNotFound(name)
        }
        return try Data(contentsOf: url)
    }
}

// MARK: - Test Helpers

private enum TestError: Error {
    case fixtureNotFound(String)
}
