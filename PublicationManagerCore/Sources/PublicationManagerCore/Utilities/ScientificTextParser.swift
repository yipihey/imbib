//
//  ScientificTextParser.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-05.
//

import SwiftUI

/// Parses scientific text with subscripts, superscripts, and HTML entities.
///
/// Handles:
/// - `<SUB>...</SUB>` and `<sub>...</sub>` → subscript
/// - `<SUP>...</SUP>` and `<sup>...</sup>` → superscript
/// - `&lt;` → <
/// - `&gt;` → >
/// - `&amp;` → &
/// - `^{...}` or `^X` (single char) → superscript (LaTeX-style)
/// - `_{...}` or `_X` (single char) → subscript (LaTeX-style)
public struct ScientificTextParser {

    /// Parse scientific text and return an AttributedString with proper formatting
    public static func parse(_ text: String) -> AttributedString {
        var result = AttributedString()
        var remaining = text

        // First pass: decode HTML entities
        remaining = decodeHTMLEntities(remaining)

        // Parse the text into segments
        while !remaining.isEmpty {
            if let match = findNextTag(in: remaining) {
                // Add text before the tag
                if match.prefixRange.lowerBound > remaining.startIndex {
                    let prefix = String(remaining[remaining.startIndex..<match.prefixRange.lowerBound])
                    result.append(AttributedString(prefix))
                }

                // Add the formatted content
                var formatted = AttributedString(match.content)
                switch match.type {
                case .sub:
                    formatted.baselineOffset = -4
                    formatted.font = .system(size: 10)
                case .sup:
                    formatted.baselineOffset = 6
                    formatted.font = .system(size: 10)
                }
                result.append(formatted)

                // Continue with the rest
                remaining = String(remaining[match.suffixRange.upperBound...])
            } else {
                // No more tags, add remaining text
                result.append(AttributedString(remaining))
                break
            }
        }

        return result
    }

    /// Parse and return a SwiftUI Text view
    public static func text(_ string: String) -> Text {
        Text(parse(string))
    }

    // MARK: - Private

    private enum TagType {
        case sub
        case sup
    }

    private struct TagMatch {
        let type: TagType
        let content: String
        let prefixRange: Range<String.Index>  // Range of opening tag
        let suffixRange: Range<String.Index>  // Range of closing tag
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        return result
    }

    private static func findNextTag(in text: String) -> TagMatch? {
        var earliest: TagMatch?
        var earliestIndex: String.Index?

        // Check for HTML-style tags
        let htmlPatterns: [(String, String, TagType)] = [
            ("<sub>", "</sub>", .sub),
            ("<SUB>", "</SUB>", .sub),
            ("<sup>", "</sup>", .sup),
            ("<SUP>", "</SUP>", .sup),
        ]

        for (open, close, type) in htmlPatterns {
            if let openRange = text.range(of: open, options: .caseInsensitive),
               let closeRange = text.range(of: close, options: .caseInsensitive, range: openRange.upperBound..<text.endIndex) {
                if earliestIndex == nil || openRange.lowerBound < earliestIndex! {
                    let content = String(text[openRange.upperBound..<closeRange.lowerBound])
                    earliest = TagMatch(type: type, content: content, prefixRange: openRange, suffixRange: closeRange)
                    earliestIndex = openRange.lowerBound
                }
            }
        }

        // Check for LaTeX-style ^{...} or ^X
        if let caretIndex = text.firstIndex(of: "^") {
            if earliestIndex == nil || caretIndex < earliestIndex! {
                let afterCaret = text.index(after: caretIndex)
                if afterCaret < text.endIndex {
                    if text[afterCaret] == "{" {
                        // ^{...} style
                        if let closeIndex = text[afterCaret...].firstIndex(of: "}") {
                            let contentStart = text.index(after: afterCaret)
                            let content = String(text[contentStart..<closeIndex])
                            let openRange = caretIndex..<text.index(after: afterCaret)
                            let closeRange = closeIndex..<text.index(after: closeIndex)
                            earliest = TagMatch(type: .sup, content: content, prefixRange: openRange, suffixRange: closeRange)
                            earliestIndex = caretIndex
                        }
                    } else {
                        // ^X single character style
                        let content = String(text[afterCaret])
                        let openRange = caretIndex..<afterCaret
                        let closeRange = afterCaret..<text.index(after: afterCaret)
                        earliest = TagMatch(type: .sup, content: content, prefixRange: openRange, suffixRange: closeRange)
                        earliestIndex = caretIndex
                    }
                }
            }
        }

        // Check for LaTeX-style _{...} or _X (only if followed by { or digit)
        if let underscoreIndex = text.firstIndex(of: "_") {
            if earliestIndex == nil || underscoreIndex < earliestIndex! {
                let afterUnderscore = text.index(after: underscoreIndex)
                if afterUnderscore < text.endIndex {
                    let nextChar = text[afterUnderscore]
                    if nextChar == "{" {
                        // _{...} style
                        if let closeIndex = text[afterUnderscore...].firstIndex(of: "}") {
                            let contentStart = text.index(after: afterUnderscore)
                            let content = String(text[contentStart..<closeIndex])
                            let openRange = underscoreIndex..<text.index(after: afterUnderscore)
                            let closeRange = closeIndex..<text.index(after: closeIndex)
                            earliest = TagMatch(type: .sub, content: content, prefixRange: openRange, suffixRange: closeRange)
                            earliestIndex = underscoreIndex
                        }
                    } else if nextChar.isNumber {
                        // _X single digit style (common in scientific notation like H_2O)
                        let content = String(nextChar)
                        let openRange = underscoreIndex..<afterUnderscore
                        let closeRange = afterUnderscore..<text.index(after: afterUnderscore)
                        earliest = TagMatch(type: .sub, content: content, prefixRange: openRange, suffixRange: closeRange)
                        earliestIndex = underscoreIndex
                    }
                }
            }
        }

        return earliest
    }
}

// MARK: - SwiftUI View Extension

public extension View {
    /// Apply scientific text parsing to a text field
    func scientificText(_ text: String) -> some View {
        ScientificTextParser.text(text)
    }
}
