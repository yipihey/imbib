//
//  RISBibTeXConverterTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-04.
//

import XCTest
@testable import PublicationManagerCore

final class RISBibTeXConverterTests: XCTestCase {

    // MARK: - RIS to BibTeX Tests

    func testToBibTeX_convertsType_journalToArticle() {
        let ris = RISEntry(type: .JOUR, tags: [] as [RISTagValue])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.entryType, "article")
    }

    func testToBibTeX_convertsType_bookToBook() {
        let ris = RISEntry(type: .BOOK, tags: [] as [RISTagValue])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.entryType, "book")
    }

    func testToBibTeX_convertsType_confToInproceedings() {
        let ris = RISEntry(type: .CONF, tags: [] as [RISTagValue])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.entryType, "inproceedings")
    }

    func testToBibTeX_convertsType_chapToIncollection() {
        let ris = RISEntry(type: .CHAP, tags: [] as [RISTagValue])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.entryType, "incollection")
    }

    func testToBibTeX_convertsType_thesToPhdthesis() {
        let ris = RISEntry(type: .THES, tags: [] as [RISTagValue])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.entryType, "phdthesis")
    }

    func testToBibTeX_convertsType_rprtToTechreport() {
        let ris = RISEntry(type: .RPRT, tags: [] as [RISTagValue])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.entryType, "techreport")
    }

    func testToBibTeX_convertsType_genToMisc() {
        let ris = RISEntry(type: .GEN, tags: [] as [RISTagValue])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.entryType, "misc")
    }

    func testToBibTeX_combinesAuthors() {
        let ris = RISEntry(type: .JOUR, tags: [
            (.AU, "Smith, John"),
            (.AU, "Doe, Jane")
        ])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.fields["author"], "Smith, John and Doe, Jane")
    }

    func testToBibTeX_mapsTitle() {
        let ris = RISEntry(type: .JOUR, tags: [
            (.TI, "Test Title")
        ])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.fields["title"], "Test Title")
    }

    func testToBibTeX_mapsYear() {
        let ris = RISEntry(type: .JOUR, tags: [
            (.PY, "2024")
        ])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.fields["year"], "2024")
    }

    func testToBibTeX_mapsJournalForArticle() {
        let ris = RISEntry(type: .JOUR, tags: [
            (.JF, "Nature")
        ])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.fields["journal"], "Nature")
    }

    func testToBibTeX_mapsBooktitleForConference() {
        let ris = RISEntry(type: .CONF, tags: [
            (.T2, "ICML 2024")
        ])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.fields["booktitle"], "ICML 2024")
    }

    func testToBibTeX_combinesPages() {
        let ris = RISEntry(type: .JOUR, tags: [
            (.SP, "100"),
            (.EP, "115")
        ])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.fields["pages"], "100-115")
    }

    func testToBibTeX_mapsDOI() {
        let ris = RISEntry(type: .JOUR, tags: [
            (.DO, "10.1234/test")
        ])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.fields["doi"], "10.1234/test")
    }

    func testToBibTeX_mapsAbstract() {
        let ris = RISEntry(type: .JOUR, tags: [
            (.AB, "This is an abstract.")
        ])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.fields["abstract"], "This is an abstract.")
    }

    func testToBibTeX_combinesKeywords() {
        let ris = RISEntry(type: .JOUR, tags: [
            (.KW, "machine learning"),
            (.KW, "deep learning")
        ])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.fields["keywords"], "machine learning, deep learning")
    }

    func testToBibTeX_generatesCiteKey() {
        let ris = RISEntry(type: .JOUR, tags: [
            (.AU, "Smith, John"),
            (.TI, "A Great Discovery"),
            (.PY, "2024")
        ])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.citeKey, "Smith2024Great")
    }

    func testToBibTeX_usesReferenceIDIfAvailable() {
        let ris = RISEntry(type: .JOUR, tags: [
            (.AU, "Smith, John"),
            (.TI, "Test"),
            (.PY, "2024"),
            (.ID, "CustomKey2024")
        ])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.citeKey, "CustomKey2024")
    }

    // MARK: - BibTeX to RIS Tests

    func testToRIS_convertsType_articleToJOUR() {
        let bibtex = BibTeXEntry(citeKey: "test", entryType: "article")

        let ris = RISBibTeXConverter.toRIS(bibtex)

        XCTAssertEqual(ris.type, .JOUR)
    }

    func testToRIS_convertsType_bookToBOOK() {
        let bibtex = BibTeXEntry(citeKey: "test", entryType: "book")

        let ris = RISBibTeXConverter.toRIS(bibtex)

        XCTAssertEqual(ris.type, .BOOK)
    }

    func testToRIS_convertsType_inproceedingsToCONF() {
        let bibtex = BibTeXEntry(citeKey: "test", entryType: "inproceedings")

        let ris = RISBibTeXConverter.toRIS(bibtex)

        XCTAssertEqual(ris.type, .CONF)
    }

    func testToRIS_convertsType_incollectionToCHAP() {
        let bibtex = BibTeXEntry(citeKey: "test", entryType: "incollection")

        let ris = RISBibTeXConverter.toRIS(bibtex)

        XCTAssertEqual(ris.type, .CHAP)
    }

    func testToRIS_convertsType_phdthesisToTHES() {
        let bibtex = BibTeXEntry(citeKey: "test", entryType: "phdthesis")

        let ris = RISBibTeXConverter.toRIS(bibtex)

        XCTAssertEqual(ris.type, .THES)
    }

    func testToRIS_convertsType_techreportToRPRT() {
        let bibtex = BibTeXEntry(citeKey: "test", entryType: "techreport")

        let ris = RISBibTeXConverter.toRIS(bibtex)

        XCTAssertEqual(ris.type, .RPRT)
    }

    func testToRIS_splitsAuthors() {
        let bibtex = BibTeXEntry(
            citeKey: "test",
            entryType: "article",
            fields: ["author": "Smith, John and Doe, Jane"]
        )

        let ris = RISBibTeXConverter.toRIS(bibtex)

        XCTAssertEqual(ris.authors.count, 2)
        XCTAssertEqual(ris.authors[0], "Smith, John")
        XCTAssertEqual(ris.authors[1], "Doe, Jane")
    }

    func testToRIS_mapsTitle() {
        let bibtex = BibTeXEntry(
            citeKey: "test",
            entryType: "article",
            fields: ["title": "Test Title"]
        )

        let ris = RISBibTeXConverter.toRIS(bibtex)

        XCTAssertEqual(ris.title, "Test Title")
    }

    func testToRIS_mapsYear() {
        let bibtex = BibTeXEntry(
            citeKey: "test",
            entryType: "article",
            fields: ["year": "2024"]
        )

        let ris = RISBibTeXConverter.toRIS(bibtex)

        XCTAssertEqual(ris.year, 2024)
    }

    func testToRIS_mapsJournal() {
        let bibtex = BibTeXEntry(
            citeKey: "test",
            entryType: "article",
            fields: ["journal": "Nature"]
        )

        let ris = RISBibTeXConverter.toRIS(bibtex)

        XCTAssertEqual(ris.secondaryTitle, "Nature")
    }

    func testToRIS_splitsPages() {
        let bibtex = BibTeXEntry(
            citeKey: "test",
            entryType: "article",
            fields: ["pages": "100-115"]
        )

        let ris = RISBibTeXConverter.toRIS(bibtex)

        XCTAssertEqual(ris.startPage, "100")
        XCTAssertEqual(ris.endPage, "115")
    }

    func testToRIS_splitsKeywords() {
        let bibtex = BibTeXEntry(
            citeKey: "test",
            entryType: "article",
            fields: ["keywords": "machine learning, deep learning"]
        )

        let ris = RISBibTeXConverter.toRIS(bibtex)

        XCTAssertEqual(ris.keywords.count, 2)
        XCTAssertTrue(ris.keywords.contains("machine learning"))
        XCTAssertTrue(ris.keywords.contains("deep learning"))
    }

    func testToRIS_storesCiteKeyAsID() {
        let bibtex = BibTeXEntry(citeKey: "Smith2024", entryType: "article")

        let ris = RISBibTeXConverter.toRIS(bibtex)

        XCTAssertEqual(ris.referenceID, "Smith2024")
    }

    // MARK: - Round Trip Tests

    func testRoundTrip_RIStoBibTeXtoRIS() {
        let original = RISEntry(type: .JOUR, tags: [
            (.AU, "Smith, John"),
            (.AU, "Doe, Jane"),
            (.TI, "Test Title"),
            (.PY, "2024"),
            (.JF, "Nature"),
            (.VL, "10"),
            (.SP, "100"),
            (.EP, "115"),
            (.DO, "10.1234/test")
        ])

        let bibtex = RISBibTeXConverter.toBibTeX(original)
        let roundtrip = RISBibTeXConverter.toRIS(bibtex)

        XCTAssertEqual(original.type, roundtrip.type)
        XCTAssertEqual(original.authors, roundtrip.authors)
        XCTAssertEqual(original.title, roundtrip.title)
        XCTAssertEqual(original.year, roundtrip.year)
        XCTAssertEqual(original.doi, roundtrip.doi)
    }

    func testRoundTrip_BibTeXtoRIStoBibTeX() {
        let original = BibTeXEntry(
            citeKey: "Smith2024",
            entryType: "article",
            fields: [
                "author": "Smith, John and Doe, Jane",
                "title": "Test Title",
                "year": "2024",
                "journal": "Nature",
                "volume": "10",
                "pages": "100-115",
                "doi": "10.1234/test"
            ]
        )

        let ris = RISBibTeXConverter.toRIS(original)
        let roundtrip = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(original.entryType, roundtrip.entryType)
        XCTAssertEqual(original.fields["author"], roundtrip.fields["author"])
        XCTAssertEqual(original.fields["title"], roundtrip.fields["title"])
        XCTAssertEqual(original.fields["year"], roundtrip.fields["year"])
        XCTAssertEqual(original.fields["doi"], roundtrip.fields["doi"])
    }

    // MARK: - Batch Conversion Tests

    func testToBibTeX_batch() {
        let risEntries = [
            RISEntry(type: .JOUR, tags: [(.TI, "First")]),
            RISEntry(type: .BOOK, tags: [(.TI, "Second")])
        ]

        let bibtexEntries = RISBibTeXConverter.toBibTeX(risEntries)

        XCTAssertEqual(bibtexEntries.count, 2)
        XCTAssertEqual(bibtexEntries[0].entryType, "article")
        XCTAssertEqual(bibtexEntries[1].entryType, "book")
    }

    func testToRIS_batch() {
        let bibtexEntries = [
            BibTeXEntry(citeKey: "First", entryType: "article"),
            BibTeXEntry(citeKey: "Second", entryType: "book")
        ]

        let risEntries = RISBibTeXConverter.toRIS(bibtexEntries)

        XCTAssertEqual(risEntries.count, 2)
        XCTAssertEqual(risEntries[0].type, .JOUR)
        XCTAssertEqual(risEntries[1].type, .BOOK)
    }

    // MARK: - Extension Tests

    func testRISEntry_toBibTeX_extension() {
        let ris = RISEntry(type: .JOUR, tags: [(.TI, "Test")])

        let bibtex = ris.toBibTeX()

        XCTAssertEqual(bibtex.entryType, "article")
    }

    func testBibTeXEntry_toRIS_extension() {
        let bibtex = BibTeXEntry(citeKey: "test", entryType: "article")

        let ris = bibtex.toRIS()

        XCTAssertEqual(ris.type, .JOUR)
    }

    func testRISArray_toBibTeX_extension() {
        let risEntries = [
            RISEntry(type: .JOUR, tags: [] as [RISTagValue]),
            RISEntry(type: .BOOK, tags: [] as [RISTagValue])
        ]

        let bibtexEntries = risEntries.toBibTeX()

        XCTAssertEqual(bibtexEntries.count, 2)
    }

    func testBibTeXArray_toRIS_extension() {
        let bibtexEntries = [
            BibTeXEntry(citeKey: "1", entryType: "article"),
            BibTeXEntry(citeKey: "2", entryType: "book")
        ]

        let risEntries = bibtexEntries.toRIS()

        XCTAssertEqual(risEntries.count, 2)
    }

    // MARK: - Edge Cases

    func testToBibTeX_emptyAuthors() {
        let ris = RISEntry(type: .JOUR, tags: [
            (.TI, "Test")
        ])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertNil(bibtex.fields["author"])
    }

    func testToBibTeX_emptyEntry() {
        let ris = RISEntry(type: .GEN, tags: [] as [RISTagValue])

        let bibtex = RISBibTeXConverter.toBibTeX(ris)

        XCTAssertEqual(bibtex.entryType, "misc")
        XCTAssertEqual(bibtex.citeKey, "unknown")
    }

    func testToRIS_emptyEntry() {
        let bibtex = BibTeXEntry(citeKey: "test", entryType: "misc")

        let ris = RISBibTeXConverter.toRIS(bibtex)

        XCTAssertEqual(ris.type, .GEN)
        XCTAssertEqual(ris.referenceID, "test")
    }
}
