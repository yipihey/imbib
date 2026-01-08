//
//  QueryBuilderTypes.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-07.
//

import Foundation

// MARK: - Query Source

/// The search source for building queries
public enum QuerySource: String, CaseIterable, Identifiable, Sendable {
    case arXiv
    case ads

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .arXiv: return "arXiv"
        case .ads: return "ADS"
        }
    }

    /// Available fields for this source
    public var fields: [QueryField] {
        switch self {
        case .arXiv:
            return [.arXivAll, .arXivAuthor, .arXivTitle, .arXivAbstract, .arXivCategory, .arXivID]
        case .ads:
            return [.adsAll, .adsAuthor, .adsTitle, .adsAbstract, .adsYear, .adsBibcode, .adsArXivID, .adsDatabase]
        }
    }
}

// MARK: - Query Field

/// Field types for search queries
public enum QueryField: String, CaseIterable, Identifiable, Sendable {
    // arXiv fields
    case arXivAll
    case arXivAuthor
    case arXivTitle
    case arXivAbstract
    case arXivCategory
    case arXivID

    // ADS fields
    case adsAll
    case adsAuthor
    case adsTitle
    case adsAbstract
    case adsYear
    case adsBibcode
    case adsArXivID
    case adsDatabase

    public var id: String { rawValue }

    /// Display name for the field picker
    public var displayName: String {
        switch self {
        case .arXivAll: return "All Fields"
        case .arXivAuthor: return "Author"
        case .arXivTitle: return "Title"
        case .arXivAbstract: return "Abstract"
        case .arXivCategory: return "Category"
        case .arXivID: return "arXiv ID"

        case .adsAll: return "All Fields"
        case .adsAuthor: return "Author"
        case .adsTitle: return "Title"
        case .adsAbstract: return "Abstract"
        case .adsYear: return "Year"
        case .adsBibcode: return "Bibcode"
        case .adsArXivID: return "arXiv ID"
        case .adsDatabase: return "Database"
        }
    }

    /// The query prefix for this field
    public var prefix: String {
        switch self {
        case .arXivAll: return ""
        case .arXivAuthor: return "au:"
        case .arXivTitle: return "ti:"
        case .arXivAbstract: return "abs:"
        case .arXivCategory: return "cat:"
        case .arXivID: return "id:"

        case .adsAll: return ""
        case .adsAuthor: return "author:"
        case .adsTitle: return "title:"
        case .adsAbstract: return "abstract:"
        case .adsYear: return "year:"
        case .adsBibcode: return "bibcode:"
        case .adsArXivID: return "arxiv:"
        case .adsDatabase: return "database:"
        }
    }

    /// Whether this field requires a category picker (vs free text)
    public var requiresCategoryPicker: Bool {
        self == .arXivCategory
    }

    /// Placeholder text for the value field
    public var placeholder: String {
        switch self {
        case .arXivAll: return "search terms"
        case .arXivAuthor: return "Einstein"
        case .arXivTitle: return "relativity"
        case .arXivAbstract: return "quantum mechanics"
        case .arXivCategory: return "cs.LG"
        case .arXivID: return "2301.12345"

        case .adsAll: return "search terms"
        case .adsAuthor: return "Rubin"
        case .adsTitle: return "galaxy rotation"
        case .adsAbstract: return "dark matter"
        case .adsYear: return "2024"
        case .adsBibcode: return "2024ApJ..."
        case .adsArXivID: return "2301.12345"
        case .adsDatabase: return "astronomy"
        }
    }

    /// The source this field belongs to
    public var source: QuerySource {
        switch self {
        case .arXivAll, .arXivAuthor, .arXivTitle, .arXivAbstract, .arXivCategory, .arXivID:
            return .arXiv
        case .adsAll, .adsAuthor, .adsTitle, .adsAbstract, .adsYear, .adsBibcode, .adsArXivID, .adsDatabase:
            return .ads
        }
    }
}

// MARK: - Query Match Type

/// How to combine multiple query terms
public enum QueryMatchType: String, CaseIterable, Identifiable, Sendable {
    case all  // AND
    case any  // OR

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all: return "Match All"
        case .any: return "Match Any"
        }
    }

    public var queryOperator: String {
        switch self {
        case .all: return "AND"
        case .any: return "OR"
        }
    }
}

// MARK: - Query Term

/// A single term in a query (field + value)
public struct QueryTerm: Identifiable, Sendable {
    public let id: UUID
    public var field: QueryField
    public var value: String

    public init(id: UUID = UUID(), field: QueryField, value: String = "") {
        self.id = id
        self.field = field
        self.value = value
    }

    /// Generate the query string for this term
    public func generateQuery() -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }

        // Quote multi-word values
        let formattedValue: String
        if trimmed.contains(" ") && !trimmed.hasPrefix("\"") {
            formattedValue = "\"\(trimmed)\""
        } else {
            formattedValue = trimmed
        }

        return "\(field.prefix)\(formattedValue)"
    }
}

// MARK: - Query Builder State

/// The complete state of the query builder
public struct QueryBuilderState: Sendable {
    public var source: QuerySource
    public var matchType: QueryMatchType
    public var terms: [QueryTerm]

    public init(
        source: QuerySource = .arXiv,
        matchType: QueryMatchType = .all,
        terms: [QueryTerm]? = nil
    ) {
        self.source = source
        self.matchType = matchType
        self.terms = terms ?? [QueryTerm(field: source.fields.first ?? .arXivAll)]
    }

    /// Generate the complete query string
    public func generateQuery() -> String {
        let validTerms = terms
            .map { $0.generateQuery() }
            .filter { !$0.isEmpty }

        guard !validTerms.isEmpty else { return "" }

        if validTerms.count == 1 {
            return validTerms[0]
        }

        return validTerms.joined(separator: " \(matchType.queryOperator) ")
    }

    /// Add a new empty term with the default field for current source
    public mutating func addTerm() {
        let defaultField = source.fields.first ?? .arXivAll
        terms.append(QueryTerm(field: defaultField))
    }

    /// Remove a term by ID
    public mutating func removeTerm(id: UUID) {
        terms.removeAll { $0.id == id }
        // Always keep at least one term
        if terms.isEmpty {
            addTerm()
        }
    }

    /// Update terms when source changes (convert fields to new source)
    public mutating func updateSource(to newSource: QuerySource) {
        guard newSource != source else { return }
        source = newSource

        // Map existing terms to equivalent fields in new source
        terms = terms.map { term in
            var newTerm = term
            newTerm.field = mapField(term.field, to: newSource)
            return newTerm
        }
    }

    /// Map a field from one source to an equivalent field in another source
    private func mapField(_ field: QueryField, to targetSource: QuerySource) -> QueryField {
        // Map based on field type
        switch field {
        case .arXivAll, .adsAll:
            return targetSource == .arXiv ? .arXivAll : .adsAll
        case .arXivAuthor, .adsAuthor:
            return targetSource == .arXiv ? .arXivAuthor : .adsAuthor
        case .arXivTitle, .adsTitle:
            return targetSource == .arXiv ? .arXivTitle : .adsTitle
        case .arXivAbstract, .adsAbstract:
            return targetSource == .arXiv ? .arXivAbstract : .adsAbstract
        case .arXivID, .adsArXivID:
            return targetSource == .arXiv ? .arXivID : .adsArXivID
        case .arXivCategory:
            // No equivalent in ADS, use all fields
            return targetSource == .arXiv ? .arXivCategory : .adsAll
        case .adsYear, .adsBibcode, .adsDatabase:
            // No equivalent in arXiv, use all fields
            return targetSource == .arXiv ? .arXivAll : field
        }
    }

    /// Parse a raw query string into terms (best effort)
    public static func parse(query: String, source: QuerySource) -> QueryBuilderState {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return QueryBuilderState(source: source)
        }

        // Detect match type from query
        let matchType: QueryMatchType
        let separator: String
        if trimmed.contains(" OR ") {
            matchType = .any
            separator = " OR "
        } else {
            matchType = .all
            separator = " AND "
        }

        // Split into parts
        let parts = trimmed.components(separatedBy: separator)
        var terms: [QueryTerm] = []

        for part in parts {
            let partTrimmed = part.trimmingCharacters(in: .whitespaces)
            guard !partTrimmed.isEmpty else { continue }

            // Find matching field prefix
            var matchedField: QueryField?
            var value = partTrimmed

            for field in source.fields where !field.prefix.isEmpty {
                if partTrimmed.lowercased().hasPrefix(field.prefix.lowercased()) {
                    matchedField = field
                    value = String(partTrimmed.dropFirst(field.prefix.count))
                    break
                }
            }

            // Remove surrounding quotes if present
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count > 2 {
                value = String(value.dropFirst().dropLast())
            }

            let field = matchedField ?? (source == .arXiv ? .arXivAll : .adsAll)
            terms.append(QueryTerm(field: field, value: value))
        }

        if terms.isEmpty {
            return QueryBuilderState(source: source)
        }

        return QueryBuilderState(source: source, matchType: matchType, terms: terms)
    }
}
