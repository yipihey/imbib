//
//  RISExporterTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-04.
//

import XCTest
@testable import PublicationManagerCore

final class RISExporterTests: XCTestCase {

    var exporter: RISExporter!

    override func setUp() {
        super.setUp()
        exporter = RISExporter()
    }

    override func tearDown() {
        exporter = nil
        super.tearDown()
    }

    // MARK: - Basic Export Tests

    func testExport_singleEntry_containsTYandER() {
        let entry = RISEntry(type: .JOUR, tags: [] as [RISTagValue])

        let output = exporter.export(entry)

        XCTAssertTrue(output.hasPrefix("TY  - JOUR"))
        XCTAssertTrue(output.hasSuffix("ER  - "))
    }

    func testExport_containsAllTags() {
        let entry = RISEntry(type: .JOUR, tags: [
            (.AU, "Smith, John"),
            (.TI, "Test Title"),
            (.PY, "2024")
        ])

        let output = exporter.export(entry)

        XCTAssertTrue(output.contains("AU  - Smith, John"))
        XCTAssertTrue(output.contains("TI  - Test Title"))
        XCTAssertTrue(output.contains("PY  - 2024"))
    }

    func testExport_tagFormat_isCorrect() {
        let entry = RISEntry(type: .JOUR, tags: [
            (.TI, "Test")
        ])

        let output = exporter.export(entry)
        let lines = output.components(separatedBy: "\n")

        // Check format: XX  - value (two letters, two spaces, hyphen, space, value)
        for line in lines where !line.isEmpty {
            XCTAssertTrue(line.contains("  - "), "Line should contain tag format: \(line)")
        }
    }

    func testExport_multipleEntries_separatedByBlankLines() {
        let entries = [
            RISEntry(type: .JOUR, tags: [(.TI, "First")]),
            RISEntry(type: .BOOK, tags: [(.TI, "Second")])
        ]

        let output = exporter.export(entries)

        XCTAssertTrue(output.contains("ER  - \n\nTY  - "))
    }

    // MARK: - Type Export Tests

    func testExport_journalType() {
        let entry = RISEntry(type: .JOUR, tags: [] as [RISTagValue])
        let output = exporter.export(entry)
        XCTAssertTrue(output.contains("TY  - JOUR"))
    }

    func testExport_bookType() {
        let entry = RISEntry(type: .BOOK, tags: [] as [RISTagValue])
        let output = exporter.export(entry)
        XCTAssertTrue(output.contains("TY  - BOOK"))
    }

    func testExport_conferenceType() {
        let entry = RISEntry(type: .CONF, tags: [] as [RISTagValue])
        let output = exporter.export(entry)
        XCTAssertTrue(output.contains("TY  - CONF"))
    }

    func testExport_chapterType() {
        let entry = RISEntry(type: .CHAP, tags: [] as [RISTagValue])
        let output = exporter.export(entry)
        XCTAssertTrue(output.contains("TY  - CHAP"))
    }

    func testExport_thesisType() {
        let entry = RISEntry(type: .THES, tags: [] as [RISTagValue])
        let output = exporter.export(entry)
        XCTAssertTrue(output.contains("TY  - THES"))
    }

    // MARK: - Multiple Author Tests

    func testExport_multipleAuthors_eachOnOwnLine() {
        let entry = RISEntry(type: .JOUR, tags: [
            (.AU, "Smith, John"),
            (.AU, "Doe, Jane"),
            (.AU, "Wilson, Bob")
        ])

        let output = exporter.export(entry)

        XCTAssertTrue(output.contains("AU  - Smith, John"))
        XCTAssertTrue(output.contains("AU  - Doe, Jane"))
        XCTAssertTrue(output.contains("AU  - Wilson, Bob"))
    }

    // MARK: - Multiple Keyword Tests

    func testExport_multipleKeywords_eachOnOwnLine() {
        let entry = RISEntry(type: .JOUR, tags: [
            (.KW, "machine learning"),
            (.KW, "deep learning"),
            (.KW, "AI")
        ])

        let output = exporter.export(entry)

        XCTAssertTrue(output.contains("KW  - machine learning"))
        XCTAssertTrue(output.contains("KW  - deep learning"))
        XCTAssertTrue(output.contains("KW  - AI"))
    }

    // MARK: - Builder Tests

    func testBuilder_createsValidEntry() {
        let entry = RISExporter.builder(type: .JOUR)
            .author("Smith, John")
            .title("Test Title")
            .year(2024)
            .build()

        XCTAssertEqual(entry.type, .JOUR)
        XCTAssertEqual(entry.authors, ["Smith, John"])
        XCTAssertEqual(entry.title, "Test Title")
        XCTAssertEqual(entry.year, 2024)
    }

    func testBuilder_multipleAuthors() {
        let entry = RISExporter.builder(type: .JOUR)
            .authors(["Smith, John", "Doe, Jane"])
            .build()

        XCTAssertEqual(entry.authors.count, 2)
    }

    func testBuilder_allFields() {
        let entry = RISExporter.builder(type: .JOUR)
            .author("Smith, John")
            .title("Test Title")
            .journal("Nature")
            .year(2024)
            .volume("10")
            .issue("3")
            .pages(start: "100", end: "115")
            .doi("10.1234/test")
            .abstract("This is an abstract.")
            .keywords(["test", "example"])
            .url("https://example.com")
            .publisher("Springer")
            .place("New York")
            .issn("1234-5678")
            .referenceID("Smith2024")
            .build()

        XCTAssertEqual(entry.title, "Test Title")
        XCTAssertEqual(entry.secondaryTitle, "Nature")
        XCTAssertEqual(entry.year, 2024)
        XCTAssertEqual(entry.volume, "10")
        XCTAssertEqual(entry.issue, "3")
        XCTAssertEqual(entry.startPage, "100")
        XCTAssertEqual(entry.endPage, "115")
        XCTAssertEqual(entry.doi, "10.1234/test")
        XCTAssertEqual(entry.abstract, "This is an abstract.")
        XCTAssertEqual(entry.keywords.count, 2)
        XCTAssertEqual(entry.url, "https://example.com")
        XCTAssertEqual(entry.publisher, "Springer")
        XCTAssertEqual(entry.place, "New York")
        XCTAssertEqual(entry.issn, "1234-5678")
        XCTAssertEqual(entry.referenceID, "Smith2024")
    }

    func testBuilder_pagesFromRange() {
        let entry = RISExporter.builder(type: .JOUR)
            .pages("100-115")
            .build()

        XCTAssertEqual(entry.startPage, "100")
        XCTAssertEqual(entry.endPage, "115")
    }

    func testBuilder_pagesFromRangeWithDash() {
        let entry = RISExporter.builder(type: .JOUR)
            .pages("100–115")  // en-dash
            .build()

        XCTAssertEqual(entry.startPage, "100")
        XCTAssertEqual(entry.endPage, "115")
    }

    func testBuilder_dateWithMonthAndDay() {
        let entry = RISExporter.builder(type: .JOUR)
            .date(year: 2024, month: 6, day: 15)
            .build()

        // Should store full date format
        let pyValue = entry.firstValue(for: .PY)
        XCTAssertEqual(pyValue, "2024/06/15")
    }

    func testBuilder_editors() {
        let entry = RISExporter.builder(type: .BOOK)
            .editors(["Editor One", "Editor Two"])
            .build()

        XCTAssertEqual(entry.editors.count, 2)
    }

    func testBuilder_customTag() {
        let entry = RISExporter.builder(type: .JOUR)
            .tag(.N1, value: "Custom note")
            .build()

        XCTAssertEqual(entry.notes, "Custom note")
    }

    // MARK: - Round Trip Tests

    func testRoundTrip_parseAndExport() throws {
        let parser = RISParser()

        let original = """
        TY  - JOUR
        AU  - Smith, John
        AU  - Doe, Jane
        TI  - Test Title
        JF  - Test Journal
        PY  - 2024
        VL  - 10
        IS  - 3
        SP  - 100
        EP  - 115
        DO  - 10.1234/test
        KW  - test
        KW  - example
        ER  -
        """

        let entries = try parser.parse(original)
        let exported = exporter.export(entries)

        // Parse again
        let reparsed = try parser.parse(exported)

        XCTAssertEqual(entries.first?.type, reparsed.first?.type)
        XCTAssertEqual(entries.first?.authors, reparsed.first?.authors)
        XCTAssertEqual(entries.first?.title, reparsed.first?.title)
        XCTAssertEqual(entries.first?.year, reparsed.first?.year)
        XCTAssertEqual(entries.first?.doi, reparsed.first?.doi)
        XCTAssertEqual(entries.first?.keywords.count, reparsed.first?.keywords.count)
    }

    // MARK: - Extension Tests

    func testEntry_toRIS_extension() {
        let entry = RISEntry(type: .JOUR, tags: [
            (.TI, "Test")
        ])

        let output = entry.toRIS()

        XCTAssertTrue(output.contains("TY  - JOUR"))
        XCTAssertTrue(output.contains("TI  - Test"))
    }

    func testArray_toRIS_extension() {
        let entries = [
            RISEntry(type: .JOUR, tags: [(.TI, "First")]),
            RISEntry(type: .BOOK, tags: [(.TI, "Second")])
        ]

        let output = entries.toRIS()

        XCTAssertTrue(output.contains("TY  - JOUR"))
        XCTAssertTrue(output.contains("TY  - BOOK"))
    }
}
