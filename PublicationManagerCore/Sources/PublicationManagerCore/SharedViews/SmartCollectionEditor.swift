//
//  SmartCollectionEditor.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI

// MARK: - Smart Collection Editor

/// Editor for creating and editing smart collections.
public struct SmartCollectionEditor: View {

    // MARK: - Properties

    @Binding var isPresented: Bool
    let collection: CDCollection?
    let onSave: (String, String) -> Void  // (name, predicate)

    @State private var name: String = ""
    @State private var rules: [SmartCollectionRule] = []
    @State private var matchType: MatchType = .all

    // MARK: - Initialization

    public init(
        isPresented: Binding<Bool>,
        collection: CDCollection? = nil,
        onSave: @escaping (String, String) -> Void
    ) {
        self._isPresented = isPresented
        self.collection = collection
        self.onSave = onSave
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Form {
                // Name
                Section("Name") {
                    TextField("Collection Name", text: $name)
                }

                // Match type
                Section("Match") {
                    Picker("Match", selection: $matchType) {
                        Text("All of the following").tag(MatchType.all)
                        Text("Any of the following").tag(MatchType.any)
                    }
                    .pickerStyle(.segmented)
                }

                // Rules
                Section("Rules") {
                    ForEach($rules) { $rule in
                        RuleRow(rule: $rule)
                    }
                    .onDelete(perform: deleteRule)

                    Button {
                        addRule()
                    } label: {
                        Label("Add Rule", systemImage: "plus.circle")
                    }
                }

                // Preview
                if !rules.isEmpty {
                    Section("Predicate Preview") {
                        Text(buildPredicate())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(collection == nil ? "New Smart Collection" : "Edit Smart Collection")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(name.isEmpty || rules.isEmpty)
                }
            }
            .onAppear {
                loadFromCollection()
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }

    // MARK: - Actions

    private func addRule() {
        rules.append(SmartCollectionRule())
    }

    private func deleteRule(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
    }

    private func loadFromCollection() {
        guard let collection else {
            // New collection - start with one empty rule
            rules = [SmartCollectionRule()]
            return
        }

        name = collection.name

        // Parse existing predicate
        if let predicate = collection.predicate {
            let parsed = SmartCollectionRule.parse(predicate: predicate)
            matchType = parsed.matchType
            rules = parsed.rules.isEmpty ? [SmartCollectionRule()] : parsed.rules
        } else {
            rules = [SmartCollectionRule()]
        }
    }

    private func buildPredicate() -> String {
        let validRules = rules.filter { $0.isValid }
        guard !validRules.isEmpty else { return "" }

        let predicates = validRules.map { $0.toPredicate() }

        switch matchType {
        case .all:
            return predicates.joined(separator: " AND ")
        case .any:
            return predicates.joined(separator: " OR ")
        }
    }

    private func save() {
        let predicate = buildPredicate()
        onSave(name, predicate)
        isPresented = false
    }
}

// MARK: - Match Type

public enum MatchType: String, CaseIterable {
    case all
    case any
}

// MARK: - Smart Collection Rule

public struct SmartCollectionRule: Identifiable {
    public let id = UUID()
    public var field: RuleField = .title
    public var comparison: RuleComparison = .contains
    public var value: String = ""

    public init(field: RuleField = .title, comparison: RuleComparison = .contains, value: String = "") {
        self.field = field
        self.comparison = comparison
        self.value = value
    }

    public var isValid: Bool {
        !value.isEmpty
    }

    public func toPredicate() -> String {
        let fieldName = field.predicateKey
        let escapedValue = value.replacingOccurrences(of: "'", with: "\\'")

        switch comparison {
        case .contains:
            return "\(fieldName) CONTAINS[cd] '\(escapedValue)'"
        case .doesNotContain:
            return "NOT (\(fieldName) CONTAINS[cd] '\(escapedValue)')"
        case .equals:
            return "\(fieldName) ==[cd] '\(escapedValue)'"
        case .notEquals:
            return "\(fieldName) !=[cd] '\(escapedValue)'"
        case .beginsWith:
            return "\(fieldName) BEGINSWITH[cd] '\(escapedValue)'"
        case .endsWith:
            return "\(fieldName) ENDSWITH[cd] '\(escapedValue)'"
        case .greaterThan:
            return "\(fieldName) > \(escapedValue)"
        case .lessThan:
            return "\(fieldName) < \(escapedValue)"
        case .isTrue:
            return "\(fieldName) == YES"
        case .isFalse:
            return "\(fieldName) == NO"
        }
    }

    /// Parse a predicate string into rules
    public static func parse(predicate: String) -> (matchType: MatchType, rules: [SmartCollectionRule]) {
        // Determine match type
        let matchType: MatchType = predicate.contains(" AND ") ? .all : .any

        // Split by AND/OR
        let separator = matchType == .all ? " AND " : " OR "
        let parts = predicate.components(separatedBy: separator)

        var rules: [SmartCollectionRule] = []

        for part in parts {
            if let rule = parseRule(part.trimmingCharacters(in: .whitespaces)) {
                rules.append(rule)
            }
        }

        return (matchType, rules)
    }

    private static func parseRule(_ part: String) -> SmartCollectionRule? {
        // Try to parse common patterns
        // Pattern: field CONTAINS[cd] 'value'
        if let match = part.range(of: #"(\w+)\s+CONTAINS\[cd\]\s+'([^']+)'"#, options: .regularExpression) {
            let matched = String(part[match])
            let components = matched.components(separatedBy: " CONTAINS[cd] ")
            if components.count == 2 {
                let fieldName = components[0]
                let value = components[1].trimmingCharacters(in: CharacterSet(charactersIn: "'"))
                if let field = RuleField.from(predicateKey: fieldName) {
                    return SmartCollectionRule(field: field, comparison: .contains, value: value)
                }
            }
        }

        // Pattern: field > value (for year)
        if let match = part.range(of: #"(\w+)\s+>\s+(\d+)"#, options: .regularExpression) {
            let matched = String(part[match])
            let components = matched.components(separatedBy: " > ")
            if components.count == 2 {
                let fieldName = components[0]
                let value = components[1]
                if let field = RuleField.from(predicateKey: fieldName) {
                    return SmartCollectionRule(field: field, comparison: .greaterThan, value: value)
                }
            }
        }

        // Pattern: field < value (for year)
        if let match = part.range(of: #"(\w+)\s+<\s+(\d+)"#, options: .regularExpression) {
            let matched = String(part[match])
            let components = matched.components(separatedBy: " < ")
            if components.count == 2 {
                let fieldName = components[0]
                let value = components[1]
                if let field = RuleField.from(predicateKey: fieldName) {
                    return SmartCollectionRule(field: field, comparison: .lessThan, value: value)
                }
            }
        }

        return nil
    }
}

// MARK: - Rule Field

public enum RuleField: String, CaseIterable, Identifiable {
    case title
    case author
    case year
    case journal
    case citeKey
    case entryType
    case abstract
    case keywords
    case doi

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .title: return "Title"
        case .author: return "Author"
        case .year: return "Year"
        case .journal: return "Journal"
        case .citeKey: return "Cite Key"
        case .entryType: return "Entry Type"
        case .abstract: return "Abstract"
        case .keywords: return "Keywords"
        case .doi: return "DOI"
        }
    }

    public var predicateKey: String {
        switch self {
        case .title: return "title"
        case .author: return "authorString"
        case .year: return "year"
        case .journal: return "journal"
        case .citeKey: return "citeKey"
        case .entryType: return "entryType"
        case .abstract: return "abstract"
        case .keywords: return "keywords"
        case .doi: return "doi"
        }
    }

    public var availableComparisons: [RuleComparison] {
        switch self {
        case .year:
            return [.equals, .greaterThan, .lessThan]
        case .title, .author, .journal, .abstract, .keywords:
            return [.contains, .doesNotContain, .equals, .beginsWith, .endsWith]
        case .citeKey, .entryType, .doi:
            return [.contains, .equals, .beginsWith]
        }
    }

    public static func from(predicateKey: String) -> RuleField? {
        RuleField.allCases.first { $0.predicateKey == predicateKey }
    }
}

// MARK: - Rule Comparison

public enum RuleComparison: String, CaseIterable, Identifiable {
    case contains
    case doesNotContain
    case equals
    case notEquals
    case beginsWith
    case endsWith
    case greaterThan
    case lessThan
    case isTrue
    case isFalse

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .contains: return "contains"
        case .doesNotContain: return "does not contain"
        case .equals: return "is"
        case .notEquals: return "is not"
        case .beginsWith: return "begins with"
        case .endsWith: return "ends with"
        case .greaterThan: return "is greater than"
        case .lessThan: return "is less than"
        case .isTrue: return "is true"
        case .isFalse: return "is false"
        }
    }
}

// MARK: - Rule Row View

struct RuleRow: View {
    @Binding var rule: SmartCollectionRule

    var body: some View {
        HStack {
            // Field picker
            Picker("Field", selection: $rule.field) {
                ForEach(RuleField.allCases) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .labelsHidden()
            #if os(macOS)
            .frame(width: 100)
            #endif

            // Comparison picker
            Picker("Comparison", selection: $rule.comparison) {
                ForEach(rule.field.availableComparisons) { comparison in
                    Text(comparison.displayName).tag(comparison)
                }
            }
            .labelsHidden()
            #if os(macOS)
            .frame(width: 140)
            #endif
            .onChange(of: rule.field) { _, newField in
                // Reset comparison if not available for new field
                if !newField.availableComparisons.contains(rule.comparison) {
                    rule.comparison = newField.availableComparisons.first ?? .contains
                }
            }

            // Value field
            if rule.comparison != .isTrue && rule.comparison != .isFalse {
                TextField("Value", text: $rule.value)
                    #if os(macOS)
                    .textFieldStyle(.roundedBorder)
                    #endif
            }
        }
    }
}

// MARK: - Preview

#Preview("New Smart Collection") {
    struct PreviewContainer: View {
        @State private var isPresented = true

        var body: some View {
            SmartCollectionEditor(isPresented: $isPresented) { name, predicate in
                print("Created: \(name) - \(predicate)")
            }
        }
    }

    return PreviewContainer()
}
