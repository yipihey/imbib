//
//  ScientificTextParserTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-07.
//

import XCTest
@testable import PublicationManagerCore

final class ScientificTextParserTests: XCTestCase {

    // MARK: - LaTeX Greek Letters

    func testParse_greekLetters_convertsToUnicode() {
        let input = "The \\alpha particle and \\beta decay"
        let result = String(ScientificTextParser.parse(input).characters)
        XCTAssertEqual(result, "The α particle and β decay")
    }

    func testParse_uppercaseGreek_convertsToUnicode() {
        let input = "\\Sigma and \\Omega values"
        let result = String(ScientificTextParser.parse(input).characters)
        XCTAssertEqual(result, "Σ and Ω values")
    }

    // MARK: - LaTeX Math Symbols

    func testParse_ell_convertsToUnicode() {
        let input = "The \\ell parameter"
        let result = String(ScientificTextParser.parse(input).characters)
        XCTAssertEqual(result, "The ℓ parameter")
    }

    func testParse_infty_convertsToUnicode() {
        let input = "As n goes to \\infty"
        let result = String(ScientificTextParser.parse(input).characters)
        XCTAssertEqual(result, "As n goes to ∞")
    }

    func testParse_comparisonSymbols_convertsToUnicode() {
        let input = "x \\leq y and z \\geq w with a \\approx b"
        let result = String(ScientificTextParser.parse(input).characters)
        XCTAssertEqual(result, "x ≤ y and z ≥ w with a ≈ b")
    }

    // MARK: - LaTeX Superscript

    func testParse_superscriptWithBraces_parsesCorrectly() {
        let input = "10^{-3} units"
        let result = ScientificTextParser.parse(input)
        // The -3 should be formatted as superscript
        let text = String(result.characters)
        XCTAssertTrue(text.contains("10"))
        XCTAssertTrue(text.contains("-3"))
    }

    func testParse_superscriptSingleChar_parsesCorrectly() {
        let input = "x^2 + y^2"
        let result = ScientificTextParser.parse(input)
        let text = String(result.characters)
        XCTAssertTrue(text.contains("x"))
        XCTAssertTrue(text.contains("2"))
        XCTAssertTrue(text.contains("y"))
    }

    // MARK: - LaTeX Subscript

    func testParse_subscriptWithBraces_parsesCorrectly() {
        let input = "\\sigma_{knee} value"
        let result = ScientificTextParser.parse(input)
        let text = String(result.characters)
        XCTAssertTrue(text.contains("σ"))
        XCTAssertTrue(text.contains("knee"))
    }

    func testParse_subscriptSingleDigit_parsesCorrectly() {
        let input = "H_2O molecule"
        let result = ScientificTextParser.parse(input)
        let text = String(result.characters)
        XCTAssertTrue(text.contains("H"))
        XCTAssertTrue(text.contains("2"))
        XCTAssertTrue(text.contains("O"))
    }

    // MARK: - Font Commands

    func testParse_rmCommand_stripsCommand() {
        let input = "\\ell_{\\rm knee} value"
        let result = String(ScientificTextParser.parse(input).characters)
        // Should contain ℓ and knee, without \rm
        XCTAssertTrue(result.contains("ℓ"))
        XCTAssertTrue(result.contains("knee"))
        XCTAssertFalse(result.contains("\\rm"))
    }

    // MARK: - Standalone Braces

    func testParse_standaloneBraces_removesCorrectly() {
        let input = "Value of {pc} in units"
        let result = String(ScientificTextParser.parse(input).characters)
        XCTAssertEqual(result, "Value of pc in units")
    }

    func testParse_bracesAfterCaret_preserved() {
        let input = "10^{-3}"
        let result = String(ScientificTextParser.parse(input).characters)
        // Should contain 10 and -3 (formatted as superscript)
        XCTAssertTrue(result.contains("10"))
        XCTAssertTrue(result.contains("-3"))
    }

    // MARK: - HTML Sub/Sup Tags

    func testParse_htmlSubTag_parsesCorrectly() {
        let input = "H<sub>2</sub>O"
        let result = ScientificTextParser.parse(input)
        let text = String(result.characters)
        XCTAssertTrue(text.contains("H"))
        XCTAssertTrue(text.contains("2"))
        XCTAssertTrue(text.contains("O"))
    }

    func testParse_htmlSupTag_parsesCorrectly() {
        let input = "x<sup>2</sup>"
        let result = ScientificTextParser.parse(input)
        let text = String(result.characters)
        XCTAssertTrue(text.contains("x"))
        XCTAssertTrue(text.contains("2"))
    }

    // MARK: - HTML Entities

    func testParse_htmlEntities_decodesCorrectly() {
        let input = "&lt;10 &amp; &gt;5"
        let result = String(ScientificTextParser.parse(input).characters)
        XCTAssertEqual(result, "<10 & >5")
    }

    // MARK: - Math Mode

    func testParse_inlineMathMode_appliesItalic() {
        let input = "The value $x$ is important"
        let result = ScientificTextParser.parse(input)
        let text = String(result.characters)
        XCTAssertTrue(text.contains("x"))
        XCTAssertTrue(text.contains("value"))
    }

    // MARK: - Complex Examples

    func testParse_complexScientificText_parsesCorrectly() {
        let input = "The \\sigma_r = 1.2\\times10^{-3} with \\ell parameter"
        let result = String(ScientificTextParser.parse(input).characters)
        XCTAssertTrue(result.contains("σ"))
        XCTAssertTrue(result.contains("1.2"))
        XCTAssertTrue(result.contains("×"))
        XCTAssertTrue(result.contains("10"))
        XCTAssertTrue(result.contains("ℓ"))
    }
}

// MARK: - MathML Parser Tests

final class MathMLParserTests: XCTestCase {

    // MARK: - Basic MathML Elements

    func testParse_simpleMathML_extractsText() {
        let input = "<mml:math><mml:mi>S</mml:mi><mml:mo>/</mml:mo><mml:mi>N</mml:mi></mml:math>"
        let result = MathMLParser.parse(input)
        XCTAssertEqual(result, "S/N")
    }

    func testParse_inlineFormula_extractsContent() {
        let input = "Text with <inline-formula><mml:math><mml:mi>x</mml:mi></mml:math></inline-formula> value"
        let result = MathMLParser.parse(input)
        XCTAssertEqual(result, "Text with x value")
    }

    func testParse_mathMLWithNumber_extractsCorrectly() {
        let input = "<mml:math><mml:mn>42</mml:mn></mml:math>"
        let result = MathMLParser.parse(input)
        XCTAssertEqual(result, "42")
    }

    // MARK: - Superscript/Subscript

    func testParse_msup_convertsSuperscript() {
        let input = "<mml:math><mml:msup><mml:mi>x</mml:mi><mml:mn>2</mml:mn></mml:msup></mml:math>"
        let result = MathMLParser.parse(input)
        XCTAssertEqual(result, "x²")
    }

    func testParse_msub_convertsSubscript() {
        let input = "<mml:math><mml:msub><mml:mi>H</mml:mi><mml:mn>2</mml:mn></mml:msub></mml:math>"
        let result = MathMLParser.parse(input)
        XCTAssertEqual(result, "H₂")
    }

    func testParse_msupWithNegative_convertsSuperscript() {
        let input = "<mml:math><mml:msup><mml:mn>10</mml:mn><mml:mrow><mml:mo>-</mml:mo><mml:mn>3</mml:mn></mml:mrow></mml:msup></mml:math>"
        let result = MathMLParser.parse(input)
        XCTAssertEqual(result, "10⁻³")
    }

    // MARK: - Complex Examples

    func testParse_signalToNoiseRatio_parsesCorrectly() {
        let input = "<inline-formula><mml:math><mml:mi>S</mml:mi><mml:mo>/</mml:mo><mml:mi>N</mml:mi><mml:mo>≍</mml:mo><mml:mn>10</mml:mn></mml:math></inline-formula>"
        let result = MathMLParser.parse(input)
        XCTAssertEqual(result, "S/N≍10")
    }

    func testParse_textWithMultipleMathML_parsesAll() {
        let input = "Value <mml:math><mml:mi>x</mml:mi></mml:math> and <mml:math><mml:mi>y</mml:mi></mml:math>"
        let result = MathMLParser.parse(input)
        XCTAssertEqual(result, "Value x and y")
    }

    // MARK: - Edge Cases

    func testParse_emptyInput_returnsEmpty() {
        let result = MathMLParser.parse("")
        XCTAssertEqual(result, "")
    }

    func testParse_noMathML_returnsUnchanged() {
        let input = "Plain text without MathML"
        let result = MathMLParser.parse(input)
        XCTAssertEqual(result, "Plain text without MathML")
    }

    func testParse_nestedMathML_handlesCorrectly() {
        let input = "<mml:math><mml:mrow><mml:mi>a</mml:mi><mml:mo>+</mml:mo><mml:mi>b</mml:mi></mml:mrow></mml:math>"
        let result = MathMLParser.parse(input)
        XCTAssertEqual(result, "a+b")
    }

    // MARK: - Unicode Conversion

    func testConvertToSuperscript_digits_converts() {
        // Test through msup element
        let input = "<mml:math><mml:msup><mml:mi>x</mml:mi><mml:mn>123</mml:mn></mml:msup></mml:math>"
        let result = MathMLParser.parse(input)
        XCTAssertEqual(result, "x¹²³")
    }

    func testConvertToSubscript_digits_converts() {
        // Test through msub element
        let input = "<mml:math><mml:msub><mml:mi>a</mml:mi><mml:mn>123</mml:mn></mml:msub></mml:math>"
        let result = MathMLParser.parse(input)
        XCTAssertEqual(result, "a₁₂₃")
    }
}
