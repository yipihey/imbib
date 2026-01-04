//
//  BibTeXTypes.swift
//  PublicationManagerCore
//

import Foundation

// MARK: - BibTeX Entry

/// A complete BibTeX bibliographic entry.
public struct BibTeXEntry: Sendable, Equatable, Identifiable, Codable {

    public var id: String { citeKey }

    /// The citation key (e.g., "Einstein1905")
    public var citeKey: String

    /// The entry type (e.g., "article", "book")
    public var entryType: String

    /// The fields as string key-value pairs
    public var fields: [String: String]

    /// Original raw BibTeX for round-trip preservation
    public var rawBibTeX: String?

    public init(
        citeKey: String,
        entryType: String,
        fields: [String: String] = [:],
        rawBibTeX: String? = nil
    ) {
        self.citeKey = citeKey
        self.entryType = entryType.lowercased()
        self.fields = fields
        self.rawBibTeX = rawBibTeX
    }
}

// MARK: - Field Access

public extension BibTeXEntry {

    /// Get a field value (case-insensitive key lookup)
    subscript(field: String) -> String? {
        get { fields[field.lowercased()] }
        set { fields[field.lowercased()] = newValue }
    }

    var title: String? { self["title"] }
    var author: String? { self["author"] }
    var year: String? { self["year"] }
    var journal: String? { self["journal"] }
    var booktitle: String? { self["booktitle"] }
    var doi: String? { self["doi"] }
    var url: String? { self["url"] }
    var abstract: String? { self["abstract"] }

    /// Parse year as integer
    var yearInt: Int? {
        guard let yearStr = year else { return nil }
        return Int(yearStr)
    }

    /// Parse authors into array
    var authorList: [String] {
        guard let author = author else { return [] }
        return author
            .components(separatedBy: " and ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// First author's last name
    var firstAuthorLastName: String? {
        guard let first = authorList.first else { return nil }
        if first.contains(",") {
            return first.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
        }
        return first.components(separatedBy: " ").last
    }
}

// MARK: - Standard Entry Types

public extension BibTeXEntry {

    static let standardTypes: Set<String> = [
        "article", "book", "booklet", "conference", "inbook",
        "incollection", "inproceedings", "manual", "mastersthesis",
        "misc", "phdthesis", "proceedings", "techreport", "unpublished"
    ]

    var isStandardType: Bool {
        Self.standardTypes.contains(entryType)
    }
}

// MARK: - BibTeX Item (for parsing)

/// Top-level items in a BibTeX file
public enum BibTeXItem: Sendable, Equatable {
    case entry(BibTeXEntry)
    case stringMacro(name: String, value: String)
    case preamble(String)
    case comment(String)
}
