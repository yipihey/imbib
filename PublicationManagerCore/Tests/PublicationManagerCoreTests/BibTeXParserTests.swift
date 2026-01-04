//
//  BibTeXParserTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-04.
//

import XCTest
@testable import PublicationManagerCore

final class BibTeXParserTests: XCTestCase {

    var parser: BibTeXParser!

    override func setUp() {
        super.setUp()
        parser = BibTeXParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    // MARK: - Basic Parsing

    func testParseSimpleArticle() throws {
        let input = """
        @article{Einstein1905,
            author = {Albert Einstein},
            title = {On the Electrodynamics of Moving Bodies},
            journal = {Annalen der Physik},
            year = {1905}
        }
        """

        let entries = try parser.parseEntries(input)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].citeKey, "Einstein1905")
        XCTAssertEqual(entries[0].entryType, "article")
        XCTAssertEqual(entries[0].fields["author"], "Albert Einstein")
        XCTAssertEqual(entries[0].fields["title"], "On the Electrodynamics of Moving Bodies")
        XCTAssertEqual(entries[0].fields["year"], "1905")
    }

    func testParseMultipleEntries() throws {
        let input = """
        @article{Entry1, author = {Author One}, title = {Title One}, year = {2020}}
        @book{Entry2, author = {Author Two}, title = {Title Two}, year = {2021}}
        @inproceedings{Entry3, author = {Author Three}, title = {Title Three}, year = {2022}}
        """

        let entries = try parser.parseEntries(input)

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].citeKey, "Entry1")
        XCTAssertEqual(entries[0].entryType, "article")
        XCTAssertEqual(entries[1].citeKey, "Entry2")
        XCTAssertEqual(entries[1].entryType, "book")
        XCTAssertEqual(entries[2].citeKey, "Entry3")
        XCTAssertEqual(entries[2].entryType, "inproceedings")
    }

    // MARK: - Nested Braces

    func testParseNestedBraces() throws {
        let input = """
        @article{DNA,
            title = {Structure of {DNA} and {RNA}}
        }
        """

        let entries = try parser.parseEntries(input)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].fields["title"], "Structure of {DNA} and {RNA}")
    }

    func testParseDeepNestedBraces() throws {
        let input = """
        @article{Deep,
            title = {Outer {Middle {Inner} text} end}
        }
        """

        let entries = try parser.parseEntries(input)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].fields["title"], "Outer {Middle {Inner} text} end")
    }

    // MARK: - String Macros

    func testParseStringMacro() throws {
        let input = """
        @string{jphys = "Journal of Physics"}

        @article{Test,
            journal = jphys
        }
        """

        let items = try parser.parse(input)
        let entries = items.compactMap { item -> BibTeXEntry? in
            if case .entry(let e) = item { return e }
            return nil
        }

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].fields["journal"], "Journal of Physics")
    }

    func testParseBuiltInMonthMacros() throws {
        let input = """
        @article{Test,
            month = jan
        }
        """

        let entries = try parser.parseEntries(input)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].fields["month"], "January")
    }

    func testParseStringConcatenation() throws {
        let input = """
        @string{base = "Base"}

        @article{Test,
            title = base # " Extension"
        }
        """

        let entries = try parser.parseEntries(input)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].fields["title"], "Base Extension")
    }

    // MARK: - Quoted Values

    func testParseQuotedValue() throws {
        let input = """
        @article{Test,
            title = "Quoted Title",
            author = "Author Name"
        }
        """

        let entries = try parser.parseEntries(input)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].fields["title"], "Quoted Title")
        XCTAssertEqual(entries[0].fields["author"], "Author Name")
    }

    // MARK: - Numeric Values

    func testParseNumericYear() throws {
        let input = """
        @article{Test,
            year = 2023,
            volume = 42
        }
        """

        let entries = try parser.parseEntries(input)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].fields["year"], "2023")
        XCTAssertEqual(entries[0].fields["volume"], "42")
    }

    // MARK: - LaTeX Decoding

    func testDecodeLaTeXAccents() throws {
        let input = """
        @article{Test,
            author = {M\\"uller, Hans and Garc\\'ia, Mar\\'ia}
        }
        """

        let entries = try parser.parseEntries(input)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].fields["author"], "Müller, Hans and García, María")
    }

    // MARK: - Crossref

    func testCrossrefInheritance() throws {
        let input = """
        @proceedings{Conf2020,
            booktitle = {Conference Proceedings},
            year = {2020},
            publisher = {ACM}
        }

        @inproceedings{Paper2020,
            author = {Test Author},
            title = {Test Paper},
            crossref = {Conf2020}
        }
        """

        let entries = try parser.parseEntries(input)

        XCTAssertEqual(entries.count, 2)

        let paper = entries.first { $0.citeKey == "Paper2020" }
        XCTAssertNotNil(paper)
        XCTAssertEqual(paper?.fields["booktitle"], "Conference Proceedings")
        XCTAssertEqual(paper?.fields["year"], "2020")
        XCTAssertEqual(paper?.fields["publisher"], "ACM")
        XCTAssertEqual(paper?.fields["author"], "Test Author")
    }

    // MARK: - Error Handling

    func testParseErrorOnUnclosedBrace() {
        let input = "@article{Test, title = {Unclosed"

        XCTAssertThrowsError(try parser.parseEntries(input)) { error in
            guard case BibTeXError.parseError = error else {
                XCTFail("Expected parseError")
                return
            }
        }
    }

    // MARK: - Fixture Tests

    func testParseSimpleFixture() throws {
        let url = Bundle.module.url(forResource: "simple", withExtension: "bib", subdirectory: "Fixtures")!
        let content = try String(contentsOf: url)
        let entries = try parser.parseEntries(content)

        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.contains { $0.citeKey == "Einstein1905" })
        XCTAssertTrue(entries.contains { $0.citeKey == "Hawking1988" })
        XCTAssertTrue(entries.contains { $0.citeKey == "Turing1950" })
    }

    func testParseNestedBracesFixture() throws {
        let url = Bundle.module.url(forResource: "nested_braces", withExtension: "bib", subdirectory: "Fixtures")!
        let content = try String(contentsOf: url)
        let entries = try parser.parseEntries(content)

        XCTAssertEqual(entries.count, 2)

        let dna = entries.first { $0.citeKey == "Watson1953" }
        XCTAssertNotNil(dna)
        XCTAssertTrue(dna?.fields["title"]?.contains("{DNA}") ?? false)
    }

    func testParseStringMacrosFixture() throws {
        let url = Bundle.module.url(forResource: "string_macros", withExtension: "bib", subdirectory: "Fixtures")!
        let content = try String(contentsOf: url)
        let entries = try parser.parseEntries(content)

        XCTAssertEqual(entries.count, 3)

        let macro = entries.first { $0.citeKey == "Macro2020" }
        XCTAssertEqual(macro?.fields["journal"], "Journal of Physics")
        XCTAssertEqual(macro?.fields["month"], "January")

        let concat = entries.first { $0.citeKey == "Concat2021" }
        XCTAssertEqual(concat?.fields["journal"], "Journal of Physics Letters")
    }

    func testParseLaTeXCharsFixture() throws {
        let url = Bundle.module.url(forResource: "latex_chars", withExtension: "bib", subdirectory: "Fixtures")!
        let content = try String(contentsOf: url)
        let entries = try parser.parseEntries(content)

        XCTAssertEqual(entries.count, 3)

        let muller = entries.first { $0.citeKey == "Muller2020" }
        XCTAssertTrue(muller?.fields["author"]?.contains("Müller") ?? false)
        XCTAssertTrue(muller?.fields["author"]?.contains("García") ?? false)
    }
}
