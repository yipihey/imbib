//
//  MathMLParser.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-07.
//

import Foundation

/// Parses MathML from scientific abstracts and converts to readable Unicode text.
///
/// Handles `<inline-formula>` and `<mml:math>` tags from ADS and other sources.
/// MathML elements are converted to Unicode equivalents where possible:
/// - `<mml:mi>` → direct text (identifiers)
/// - `<mml:mo>` → Unicode operators
/// - `<mml:mn>` → direct text (numbers)
/// - `<mml:msup>` → Unicode superscripts
/// - `<mml:msub>` → Unicode subscripts
/// - `<mml:mrow>` → pass-through (grouping)
/// - `<mml:mtext>` → direct text
public struct MathMLParser {

    // MARK: - Unicode Character Maps

    /// Superscript Unicode characters
    private static let superscriptMap: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        "n": "ⁿ", "i": "ⁱ", "a": "ᵃ", "b": "ᵇ", "c": "ᶜ",
        "d": "ᵈ", "e": "ᵉ", "f": "ᶠ", "g": "ᵍ", "h": "ʰ",
        "j": "ʲ", "k": "ᵏ", "l": "ˡ", "m": "ᵐ", "o": "ᵒ",
        "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ",
        "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ",
    ]

    /// Subscript Unicode characters
    private static let subscriptMap: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ",
        "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ",
        "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ",
        "v": "ᵥ", "x": "ₓ",
    ]

    // MARK: - Public Interface

    /// Parse text containing MathML and convert to readable Unicode text.
    ///
    /// Example input:
    /// ```
    /// Text with <inline-formula><mml:math><mml:mi>S</mml:mi><mml:mo>/</mml:mo><mml:mi>N</mml:mi></mml:math></inline-formula> ratio
    /// ```
    /// Example output:
    /// ```
    /// Text with S/N ratio
    /// ```
    public static func parse(_ text: String) -> String {
        var result = text

        // Process <inline-formula>...</inline-formula> tags
        result = processInlineFormulas(result)

        // Process standalone <mml:math>...</mml:math> tags (without inline-formula wrapper)
        result = processStandaloneMathML(result)

        return result
    }

    // MARK: - Private Methods

    /// Process inline-formula tags and extract their content
    private static func processInlineFormulas(_ text: String) -> String {
        var result = text
        let pattern = "<inline-formula[^>]*>(.*?)</inline-formula>"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return result
        }

        let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))

        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let contentRange = Range(match.range(at: 1), in: result) else {
                continue
            }

            let mathMLContent = String(result[contentRange])
            let parsedContent = parseMathML(mathMLContent)
            result.replaceSubrange(fullRange, with: parsedContent)
        }

        return result
    }

    /// Process standalone mml:math tags
    private static func processStandaloneMathML(_ text: String) -> String {
        var result = text
        let pattern = "<mml:math[^>]*>(.*?)</mml:math>"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return result
        }

        let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))

        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let contentRange = Range(match.range(at: 1), in: result) else {
                continue
            }

            let mathMLContent = String(result[contentRange])
            let parsedContent = parseMathML(mathMLContent)
            result.replaceSubrange(fullRange, with: parsedContent)
        }

        return result
    }

    /// Parse MathML content and convert to Unicode text
    private static func parseMathML(_ content: String) -> String {
        var result = content

        // Process msup (superscript) first - before stripping tags
        result = processSuperscripts(result)

        // Process msub (subscript) - before stripping tags
        result = processSubscripts(result)

        // Now strip remaining MathML tags and extract text content
        result = stripMathMLTags(result)

        // Normalize whitespace
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespaces)

        return result
    }

    /// Process msup elements and convert to Unicode superscript
    private static func processSuperscripts(_ text: String) -> String {
        var result = text
        let pattern = "<mml:msup[^>]*>(.*?)</mml:msup>"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return result
        }

        var matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))

        // Keep processing until no more matches (handles nested elements)
        while !matches.isEmpty {
            // Process in reverse order to preserve indices
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let contentRange = Range(match.range(at: 1), in: result) else {
                    continue
                }

                let innerContent = String(result[contentRange])
                // msup has two children: base and superscript
                let parts = extractMsupParts(innerContent)
                let base = stripMathMLTags(parts.base)
                let sup = convertToSuperscript(stripMathMLTags(parts.superscript))
                result.replaceSubrange(fullRange, with: base + sup)
            }

            matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))
        }

        return result
    }

    /// Process msub elements and convert to Unicode subscript
    private static func processSubscripts(_ text: String) -> String {
        var result = text
        let pattern = "<mml:msub[^>]*>(.*?)</mml:msub>"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return result
        }

        var matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))

        // Keep processing until no more matches (handles nested elements)
        while !matches.isEmpty {
            // Process in reverse order to preserve indices
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let contentRange = Range(match.range(at: 1), in: result) else {
                    continue
                }

                let innerContent = String(result[contentRange])
                // msub has two children: base and subscript
                let parts = extractMsubParts(innerContent)
                let base = stripMathMLTags(parts.base)
                let sub = convertToSubscript(stripMathMLTags(parts.subscript))
                result.replaceSubrange(fullRange, with: base + sub)
            }

            matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))
        }

        return result
    }

    /// Extract base and superscript parts from msup content
    private static func extractMsupParts(_ content: String) -> (base: String, superscript: String) {
        // msup should have exactly two child elements
        let children = extractTopLevelElements(content)
        if children.count >= 2 {
            return (children[0], children[1])
        } else if children.count == 1 {
            return (children[0], "")
        }
        return (content, "")
    }

    /// Extract base and subscript parts from msub content
    private static func extractMsubParts(_ content: String) -> (base: String, subscript: String) {
        // msub should have exactly two child elements
        let children = extractTopLevelElements(content)
        if children.count >= 2 {
            return (children[0], children[1])
        } else if children.count == 1 {
            return (children[0], "")
        }
        return (content, "")
    }

    /// Extract top-level MathML elements from content using stack-based parsing
    /// This handles nested elements correctly (e.g., mrow containing other elements)
    private static func extractTopLevelElements(_ content: String) -> [String] {
        var elements: [String] = []
        var i = content.startIndex
        var depth = 0
        var currentElementStart: String.Index?
        var currentTagName: String?

        while i < content.endIndex {
            // Look for opening tag
            if content[i] == "<" && i < content.index(before: content.endIndex) {
                let rest = String(content[i...])

                // Check for self-closing tag: <mml:xxx ... />
                if let selfClose = rest.range(of: #"^<mml:[a-z]+[^>]*/>"#, options: [.regularExpression, .caseInsensitive]) {
                    if depth == 0 {
                        let tagEnd = content.index(i, offsetBy: rest.distance(from: rest.startIndex, to: selfClose.upperBound))
                        elements.append(String(content[i..<tagEnd]))
                        i = tagEnd
                        continue
                    }
                }

                // Check for opening tag: <mml:xxx>
                if let openMatch = rest.range(of: #"^<mml:([a-z]+)[^>]*>"#, options: [.regularExpression, .caseInsensitive]) {
                    if depth == 0 {
                        currentElementStart = i
                        // Extract tag name for matching
                        if let tagRange = rest.range(of: #"^<mml:([a-z]+)"#, options: [.regularExpression, .caseInsensitive]) {
                            let tagText = String(rest[tagRange])
                            currentTagName = String(tagText.dropFirst(5)) // Remove "<mml:"
                        }
                    }
                    depth += 1
                    i = content.index(i, offsetBy: rest.distance(from: rest.startIndex, to: openMatch.upperBound))
                    continue
                }

                // Check for closing tag: </mml:xxx>
                if let closeMatch = rest.range(of: #"^</mml:([a-z]+)>"#, options: [.regularExpression, .caseInsensitive]) {
                    depth -= 1
                    let tagEnd = content.index(i, offsetBy: rest.distance(from: rest.startIndex, to: closeMatch.upperBound))
                    if depth == 0, let start = currentElementStart {
                        elements.append(String(content[start..<tagEnd]))
                        currentElementStart = nil
                        currentTagName = nil
                    }
                    i = tagEnd
                    continue
                }
            }

            i = content.index(after: i)
        }

        // If no elements found, return the content as-is
        if elements.isEmpty {
            return [content.trimmingCharacters(in: .whitespaces)]
        }

        return elements
    }

    /// Strip all MathML tags and return plain text content
    private static func stripMathMLTags(_ text: String) -> String {
        var result = text

        // Remove all MathML tags but keep their content
        let tagPattern = "</?mml:[a-z]+[^>]*>"
        if let regex = try? NSRegularExpression(pattern: tagPattern, options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        return result
    }

    /// Convert text to Unicode superscript characters where possible
    private static func convertToSuperscript(_ text: String) -> String {
        var result = ""
        for char in text {
            if let supChar = superscriptMap[char] {
                result.append(supChar)
            } else if let supChar = superscriptMap[Character(char.lowercased())] {
                result.append(supChar)
            } else {
                // Character not available in Unicode superscript, use as-is
                result.append(char)
            }
        }
        return result
    }

    /// Convert text to Unicode subscript characters where possible
    private static func convertToSubscript(_ text: String) -> String {
        var result = ""
        for char in text {
            if let subChar = subscriptMap[char] {
                result.append(subChar)
            } else if let subChar = subscriptMap[Character(char.lowercased())] {
                result.append(subChar)
            } else {
                // Character not available in Unicode subscript, use as-is
                result.append(char)
            }
        }
        return result
    }
}
