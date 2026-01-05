//
//  RISParserTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-04.
//

import XCTest
@testable import PublicationManagerCore

final class RISParserTests: XCTestCase {

    var parser: RISParser!

    override func setUp() {
        super.setUp()
        parser = RISParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    // MARK: - Basic Parsing Tests

    func testParse_singleEntry_returnsOneEntry() throws {
        let ris = """
        TY  - JOUR
        AU  - Smith, John
        TI  - Test Title
        PY  - 2024
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.count, 1)
    }

    func testParse_extractsType() throws {
        let ris = """
        TY  - JOUR
        TI  - Test
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.type, .JOUR)
    }

    func testParse_extractsTitle() throws {
        let ris = """
        TY  - JOUR
        TI  - A Relational Model of Data
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.title, "A Relational Model of Data")
    }

    func testParse_extractsAuthors() throws {
        let ris = """
        TY  - JOUR
        AU  - Codd, Edgar F.
        TI  - Test
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.authors, ["Codd, Edgar F."])
    }

    func testParse_extractsMultipleAuthors() throws {
        let ris = """
        TY  - JOUR
        AU  - Smith, John
        AU  - Doe, Jane
        AU  - Wilson, Bob
        TI  - Test
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.authors.count, 3)
        XCTAssertEqual(entries.first?.authors[0], "Smith, John")
        XCTAssertEqual(entries.first?.authors[1], "Doe, Jane")
        XCTAssertEqual(entries.first?.authors[2], "Wilson, Bob")
    }

    func testParse_extractsYear() throws {
        let ris = """
        TY  - JOUR
        TI  - Test
        PY  - 1970
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.year, 1970)
    }

    func testParse_extractsYearFromDateFormat() throws {
        let ris = """
        TY  - JOUR
        TI  - Test
        PY  - 2024/01/15/extra
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.year, 2024)
    }

    func testParse_extractsJournal() throws {
        let ris = """
        TY  - JOUR
        TI  - Test
        JF  - Communications of the ACM
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.secondaryTitle, "Communications of the ACM")
    }

    func testParse_extractsVolume() throws {
        let ris = """
        TY  - JOUR
        TI  - Test
        VL  - 13
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.volume, "13")
    }

    func testParse_extractsIssue() throws {
        let ris = """
        TY  - JOUR
        TI  - Test
        IS  - 6
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.issue, "6")
    }

    func testParse_extractsPages() throws {
        let ris = """
        TY  - JOUR
        TI  - Test
        SP  - 377
        EP  - 387
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.startPage, "377")
        XCTAssertEqual(entries.first?.endPage, "387")
        XCTAssertEqual(entries.first?.pages, "377-387")
    }

    func testParse_extractsDOI() throws {
        let ris = """
        TY  - JOUR
        TI  - Test
        DO  - 10.1145/362384.362685
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.doi, "10.1145/362384.362685")
    }

    func testParse_extractsAbstract() throws {
        let ris = """
        TY  - JOUR
        TI  - Test
        AB  - This is the abstract text.
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.abstract, "This is the abstract text.")
    }

    func testParse_extractsKeywords() throws {
        let ris = """
        TY  - JOUR
        TI  - Test
        KW  - machine learning
        KW  - deep learning
        KW  - AI
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.keywords.count, 3)
        XCTAssertTrue(entries.first?.keywords.contains("machine learning") == true)
        XCTAssertTrue(entries.first?.keywords.contains("deep learning") == true)
        XCTAssertTrue(entries.first?.keywords.contains("AI") == true)
    }

    func testParse_extractsURL() throws {
        let ris = """
        TY  - JOUR
        TI  - Test
        UR  - https://example.com/paper.pdf
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.url, "https://example.com/paper.pdf")
    }

    func testParse_extractsPublisher() throws {
        let ris = """
        TY  - BOOK
        TI  - Test
        PB  - Springer
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.publisher, "Springer")
    }

    func testParse_extractsPlace() throws {
        let ris = """
        TY  - BOOK
        TI  - Test
        CY  - New York
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.place, "New York")
    }

    func testParse_extractsISSN() throws {
        let ris = """
        TY  - JOUR
        TI  - Test
        SN  - 0001-0782
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.issn, "0001-0782")
    }

    func testParse_extractsReferenceID() throws {
        let ris = """
        TY  - JOUR
        TI  - Test
        ID  - Codd1970
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.referenceID, "Codd1970")
    }

    // MARK: - Multiple Entry Tests

    func testParse_multipleEntries_returnsAll() throws {
        let ris = """
        TY  - JOUR
        TI  - First Article
        ER  -

        TY  - BOOK
        TI  - Second Book
        ER  -

        TY  - CONF
        TI  - Third Conference
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].type, .JOUR)
        XCTAssertEqual(entries[1].type, .BOOK)
        XCTAssertEqual(entries[2].type, .CONF)
    }

    // MARK: - Entry Type Tests

    func testParse_bookType() throws {
        let ris = """
        TY  - BOOK
        TI  - Test Book
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.type, .BOOK)
    }

    func testParse_chapterType() throws {
        let ris = """
        TY  - CHAP
        TI  - Test Chapter
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.type, .CHAP)
    }

    func testParse_conferenceType() throws {
        let ris = """
        TY  - CONF
        TI  - Test Conference
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.type, .CONF)
    }

    func testParse_thesisType() throws {
        let ris = """
        TY  - THES
        TI  - Test Thesis
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.type, .THES)
    }

    func testParse_reportType() throws {
        let ris = """
        TY  - RPRT
        TI  - Test Report
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.type, .RPRT)
    }

    func testParse_unknownType_fallsBackToGEN() throws {
        let ris = """
        TY  - UNKNOWN
        TI  - Test
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.type, .GEN)
    }

    // MARK: - Edge Cases

    func testParse_emptyContent_throws() {
        XCTAssertThrowsError(try parser.parse("")) { error in
            guard case RISError.emptyContent = error else {
                XCTFail("Expected emptyContent error")
                return
            }
        }
    }

    func testParse_whitespaceOnly_throws() {
        XCTAssertThrowsError(try parser.parse("   \n\n  \t  ")) { error in
            guard case RISError.emptyContent = error else {
                XCTFail("Expected emptyContent error")
                return
            }
        }
    }

    func testParse_missingER_stillParsesEntry() throws {
        let ris = """
        TY  - JOUR
        TI  - Test
        """

        let entries = try parser.parse(ris)

        // Parser should still create entry even without ER
        XCTAssertEqual(entries.count, 1)
    }

    func testParse_preservesRawRIS() throws {
        let ris = """
        TY  - JOUR
        AU  - Smith, John
        TI  - Test Title
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertNotNil(entries.first?.rawRIS)
        XCTAssertTrue(entries.first?.rawRIS?.contains("TY  - JOUR") == true)
        XCTAssertTrue(entries.first?.rawRIS?.contains("AU  - Smith") == true)
    }

    func testParse_alternateAuthorTag_A1() throws {
        let ris = """
        TY  - JOUR
        A1  - Smith, John
        TI  - Test
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.authors, ["Smith, John"])
    }

    func testParse_alternateTitleTag_T1() throws {
        let ris = """
        TY  - JOUR
        T1  - Alternate Title
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.title, "Alternate Title")
    }

    func testParse_alternateYearTag_Y1() throws {
        let ris = """
        TY  - JOUR
        TI  - Test
        Y1  - 2020
        ER  -
        """

        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.first?.year, 2020)
    }

    // MARK: - Fixture Tests

    func testParse_sampleFixture() throws {
        let ris = try loadFixture("sample.ris")
        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.type, .JOUR)
        XCTAssertEqual(entries.first?.authors, ["Codd, Edgar F."])
        XCTAssertEqual(entries.first?.title, "A Relational Model of Data for Large Shared Data Banks")
        XCTAssertEqual(entries.first?.year, 1970)
        XCTAssertEqual(entries.first?.doi, "10.1145/362384.362685")
        XCTAssertEqual(entries.first?.keywords.count, 3)
    }

    func testParse_multipleAuthorsFixture() throws {
        let ris = try loadFixture("multiple_authors.ris")
        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.count, 2)

        // First entry - AlexNet paper
        XCTAssertEqual(entries[0].authors.count, 3)
        XCTAssertEqual(entries[0].authors[0], "Krizhevsky, Alex")
        XCTAssertEqual(entries[0].year, 2012)

        // Second entry - Transformer paper
        XCTAssertEqual(entries[1].authors.count, 8)
        XCTAssertEqual(entries[1].type, .CONF)
        XCTAssertEqual(entries[1].year, 2017)
    }

    func testParse_allTypesFixture() throws {
        let ris = try loadFixture("all_types.ris")
        let entries = try parser.parse(ris)

        XCTAssertEqual(entries.count, 8)

        // Verify different types are parsed
        let types = entries.map { $0.type }
        XCTAssertTrue(types.contains(.BOOK))
        XCTAssertTrue(types.contains(.CHAP))
        XCTAssertTrue(types.contains(.THES))
        XCTAssertTrue(types.contains(.RPRT))
        XCTAssertTrue(types.contains(.ELEC))
        XCTAssertTrue(types.contains(.NEWS))
        XCTAssertTrue(types.contains(.PAT))
        XCTAssertTrue(types.contains(.GEN))
    }

    // MARK: - Validation Tests

    func testValidate_validContent_returnsNoErrors() {
        let ris = """
        TY  - JOUR
        TI  - Test
        ER  -
        """

        let errors = parser.validate(ris)

        XCTAssertTrue(errors.isEmpty)
    }

    func testValidate_emptyContent_returnsError() {
        let errors = parser.validate("")

        XCTAssertEqual(errors.count, 1)
        guard case .emptyContent = errors.first else {
            XCTFail("Expected emptyContent error")
            return
        }
    }

    func testValidate_missingER_returnsError() {
        let ris = """
        TY  - JOUR
        TI  - Test
        """

        let errors = parser.validate(ris)

        XCTAssertEqual(errors.count, 1)
        guard case .missingEndTag = errors.first else {
            XCTFail("Expected missingEndTag error")
            return
        }
    }

    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name.replacingOccurrences(of: ".ris", with: ""),
                                    withExtension: "ris",
                                    subdirectory: "Fixtures") else {
            throw TestError.fixtureNotFound(name)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private enum TestError: Error {
    case fixtureNotFound(String)
}
