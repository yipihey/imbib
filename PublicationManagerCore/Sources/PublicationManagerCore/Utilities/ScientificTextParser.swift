//
//  ScientificTextParser.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-05.
//

import SwiftUI

/// Parses scientific text with subscripts, superscripts, LaTeX, and HTML entities.
///
/// Handles:
/// - `<SUB>...</SUB>` and `<sub>...</sub>` → subscript
/// - `<SUP>...</SUP>` and `<sup>...</sup>` → superscript
/// - `&lt;` → <, `&gt;` → >, `&amp;` → &
/// - `^{...}` or `^X` (single char) → superscript (LaTeX-style)
/// - `_{...}` or `_X` (single char) → subscript (LaTeX-style)
/// - `$...$` → italic (inline math mode)
/// - `\textbf{...}` → bold
/// - `\textit{...}`, `\emph{...}` → italic
/// - Greek letters: `\alpha`, `\beta`, `\phi`, etc. → Unicode equivalents
///
/// Performance: Results are cached using NSCache. Repeated parses of the same text
/// are near-instant after the first parse.
public struct ScientificTextParser {

    // MARK: - Cache

    /// Wrapper class to store AttributedString in NSCache (requires reference type)
    private final class CachedAttributedString {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    /// Cache for parsed results (thread-safe, auto-evicts under memory pressure)
    private static let cache: NSCache<NSString, CachedAttributedString> = {
        let cache = NSCache<NSString, CachedAttributedString>()
        cache.countLimit = 500  // Max 500 entries
        return cache
    }()

    /// Clear the parse cache (useful for testing or memory warnings)
    public static func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - Public Interface

    /// Parse scientific text and return an AttributedString with proper formatting.
    /// Results are cached for performance.
    public static func parse(_ text: String) -> AttributedString {
        // Empty strings don't need parsing
        guard !text.isEmpty else { return AttributedString() }

        let key = text as NSString

        // Check cache first
        if let cached = cache.object(forKey: key) {
            return cached.value
        }

        // Parse and cache
        let result = parseUncached(text)
        cache.setObject(CachedAttributedString(result), forKey: key)
        return result
    }

    /// Parse without caching (internal implementation)
    private static func parseUncached(_ text: String) -> AttributedString {
        var result = AttributedString()
        var remaining = text

        // First pass: parse MathML (inline-formula, mml:math tags)
        remaining = MathMLParser.parse(remaining)

        // Second pass: decode HTML entities and LaTeX symbols
        remaining = decodeHTMLEntities(remaining)

        // Parse the text into segments
        while !remaining.isEmpty {
            if let match = findNextTag(in: remaining) {
                // Add text before the tag
                if match.prefixRange.lowerBound > remaining.startIndex {
                    let prefix = String(remaining[remaining.startIndex..<match.prefixRange.lowerBound])
                    result.append(AttributedString(prefix))
                }

                // Add the formatted content - recursively parse for nested formatting
                let parsedContent = parse(match.content)
                var formatted = parsedContent
                switch match.type {
                case .sub:
                    formatted = AttributedString(match.content)
                    formatted.baselineOffset = -4
                    formatted.font = .system(size: 10)
                case .sup:
                    formatted = AttributedString(match.content)
                    formatted.baselineOffset = 6
                    formatted.font = .system(size: 10)
                case .math, .italic:
                    // Apply italic to the parsed content
                    for run in formatted.runs {
                        let range = run.range
                        formatted[range].font = Font.body.italic()
                    }
                case .bold:
                    // Apply bold to the parsed content
                    for run in formatted.runs {
                        let range = run.range
                        formatted[range].font = Font.body.bold()
                    }
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
        case math      // $...$
        case bold      // \textbf{...}
        case italic    // \textit{...}, \emph{...}
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

        // Replace LaTeX Greek letters with Unicode
        result = replaceGreekLetters(result)

        // Strip LaTeX font commands without braces (e.g., \rm, \it, \bf)
        result = stripFontCommands(result)

        // Strip standalone LaTeX braces (not preceded by ^ or _)
        result = stripStandaloneBraces(result)
        return result
    }

    /// Strip LaTeX font-switching commands without braces
    private static func stripFontCommands(_ text: String) -> String {
        var result = text
        // Common font commands used in subscripts/superscripts
        // These switch font for subsequent text without braces
        let fontCommands = [
            "\\rm ", "\\it ", "\\bf ", "\\sf ", "\\tt ",
            "\\rm{", "\\it{", "\\bf{", "\\sf{", "\\tt{",
            "\\textrm ", "\\textit ", "\\textbf ",
        ]
        for cmd in fontCommands {
            // Replace with space (for space-terminated) or just remove (for brace-terminated)
            let replacement = cmd.hasSuffix(" ") ? "" : ""
            result = result.replacingOccurrences(of: cmd, with: replacement)
        }
        return result
    }

    /// Replace LaTeX Greek letter commands with Unicode characters
    private static func replaceGreekLetters(_ text: String) -> String {
        var result = text

        // Lowercase Greek
        let greekLower: [(String, String)] = [
            ("\\alpha", "α"), ("\\beta", "β"), ("\\gamma", "γ"), ("\\delta", "δ"),
            ("\\epsilon", "ε"), ("\\varepsilon", "ε"), ("\\zeta", "ζ"), ("\\eta", "η"),
            ("\\theta", "θ"), ("\\vartheta", "ϑ"), ("\\iota", "ι"), ("\\kappa", "κ"),
            ("\\lambda", "λ"), ("\\mu", "μ"), ("\\nu", "ν"), ("\\xi", "ξ"),
            ("\\pi", "π"), ("\\varpi", "ϖ"), ("\\rho", "ρ"), ("\\varrho", "ϱ"),
            ("\\sigma", "σ"), ("\\varsigma", "ς"), ("\\tau", "τ"), ("\\upsilon", "υ"),
            ("\\phi", "φ"), ("\\varphi", "ϕ"), ("\\chi", "χ"), ("\\psi", "ψ"),
            ("\\omega", "ω"),
        ]

        // Uppercase Greek
        let greekUpper: [(String, String)] = [
            ("\\Gamma", "Γ"), ("\\Delta", "Δ"), ("\\Theta", "Θ"), ("\\Lambda", "Λ"),
            ("\\Xi", "Ξ"), ("\\Pi", "Π"), ("\\Sigma", "Σ"), ("\\Upsilon", "Υ"),
            ("\\Phi", "Φ"), ("\\Psi", "Ψ"), ("\\Omega", "Ω"),
        ]

        // Common math symbols
        let mathSymbols: [(String, String)] = [
            ("\\infty", "∞"), ("\\partial", "∂"), ("\\nabla", "∇"),
            ("\\pm", "±"), ("\\mp", "∓"), ("\\times", "×"), ("\\div", "÷"),
            ("\\cdot", "·"), ("\\leq", "≤"), ("\\geq", "≥"), ("\\neq", "≠"),
            ("\\approx", "≈"), ("\\equiv", "≡"), ("\\sim", "∼"), ("\\simeq", "≃"),
            ("\\propto", "∝"), ("\\sum", "∑"), ("\\prod", "∏"), ("\\int", "∫"),
            ("\\sqrt", "√"), ("\\forall", "∀"), ("\\exists", "∃"),
            ("\\in", "∈"), ("\\notin", "∉"), ("\\subset", "⊂"), ("\\supset", "⊃"),
            ("\\cup", "∪"), ("\\cap", "∩"), ("\\emptyset", "∅"),
            ("\\rightarrow", "→"), ("\\leftarrow", "←"), ("\\Rightarrow", "⇒"),
            ("\\Leftarrow", "⇐"), ("\\leftrightarrow", "↔"), ("\\Leftrightarrow", "⇔"),
            // Script/special letters
            ("\\ell", "ℓ"), ("\\hbar", "ℏ"), ("\\Re", "ℜ"), ("\\Im", "ℑ"),
            ("\\aleph", "ℵ"), ("\\wp", "℘"),
            // Additional operators
            ("\\ll", "≪"), ("\\gg", "≫"), ("\\lesssim", "≲"), ("\\gtrsim", "≳"),
            ("\\asymp", "≍"), ("\\dagger", "†"), ("\\ddagger", "‡"),
            ("\\prime", "′"), ("\\circ", "∘"), ("\\bullet", "•"),
        ]

        for (latex, unicode) in greekLower + greekUpper + mathSymbols {
            result = result.replacingOccurrences(of: latex, with: unicode)
        }

        return result
    }

    /// Remove standalone LaTeX braces like {pc} → pc
    /// Preserves braces that are part of ^{...} or _{...} notation
    private static func stripStandaloneBraces(_ text: String) -> String {
        var result = ""
        var i = text.startIndex
        var insideSpecialBrace = false  // Track if we're inside ^{...} or _{...}

        while i < text.endIndex {
            let char = text[i]

            if char == "{" {
                // Check if this brace is preceded by ^ or _ (LaTeX sub/superscript)
                let isPrecededBySpecial: Bool
                if i > text.startIndex {
                    let prevIndex = text.index(before: i)
                    let prevChar = text[prevIndex]
                    isPrecededBySpecial = (prevChar == "^" || prevChar == "_")
                } else {
                    isPrecededBySpecial = false
                }

                if isPrecededBySpecial {
                    // Keep the brace - it's part of ^{...} or _{...}
                    result.append(char)
                    insideSpecialBrace = true
                } else {
                    // Find closing brace and extract content
                    if let closeIndex = text[i...].firstIndex(of: "}") {
                        let contentStart = text.index(after: i)
                        if contentStart < closeIndex {
                            result.append(contentsOf: text[contentStart..<closeIndex])
                        }
                        i = closeIndex
                    } else {
                        // No closing brace, keep the opening one
                        result.append(char)
                    }
                }
            } else if char == "}" {
                if insideSpecialBrace {
                    // Keep the closing brace - it's part of ^{...} or _{...}
                    result.append(char)
                    insideSpecialBrace = false
                }
                // Standalone closing braces are skipped
            } else {
                result.append(char)
            }

            i = text.index(after: i)
        }

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

        // Check for $...$ math mode (single $ only, not $$)
        if let dollarIndex = text.firstIndex(of: "$") {
            // Make sure it's not $$ (display math)
            let afterDollar = text.index(after: dollarIndex)
            if afterDollar < text.endIndex && text[afterDollar] != "$" {
                // Find closing $
                if let closeIndex = text[afterDollar...].firstIndex(of: "$") {
                    if earliestIndex == nil || dollarIndex < earliestIndex! {
                        let content = String(text[afterDollar..<closeIndex])
                        let openRange = dollarIndex..<afterDollar
                        let closeRange = closeIndex..<text.index(after: closeIndex)
                        earliest = TagMatch(type: .math, content: content, prefixRange: openRange, suffixRange: closeRange)
                        earliestIndex = dollarIndex
                    }
                }
            }
        }

        // Check for \textbf{...}, \textit{...}, \emph{...}
        let latexCommands: [(String, TagType)] = [
            ("\\textbf{", .bold),
            ("\\textit{", .italic),
            ("\\emph{", .italic),
            ("\\mathbf{", .bold),
            ("\\mathit{", .italic),
            ("\\mathrm{", .italic),  // Roman math - just use italic for now
        ]

        for (command, type) in latexCommands {
            if let cmdRange = text.range(of: command) {
                if earliestIndex == nil || cmdRange.lowerBound < earliestIndex! {
                    // Find matching closing brace
                    if let closeIndex = findMatchingBrace(in: text, from: cmdRange.upperBound) {
                        let content = String(text[cmdRange.upperBound..<closeIndex])
                        let closeRange = closeIndex..<text.index(after: closeIndex)
                        earliest = TagMatch(type: type, content: content, prefixRange: cmdRange, suffixRange: closeRange)
                        earliestIndex = cmdRange.lowerBound
                    }
                }
            }
        }

        return earliest
    }

    /// Find matching closing brace, handling nested braces
    private static func findMatchingBrace(in text: String, from start: String.Index) -> String.Index? {
        var depth = 1
        var i = start

        while i < text.endIndex {
            let char = text[i]
            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    return i
                }
            }
            i = text.index(after: i)
        }

        return nil
    }
}

// MARK: - SwiftUI View Extension

public extension View {
    /// Apply scientific text parsing to a text field
    func scientificText(_ text: String) -> some View {
        ScientificTextParser.text(text)
    }
}
