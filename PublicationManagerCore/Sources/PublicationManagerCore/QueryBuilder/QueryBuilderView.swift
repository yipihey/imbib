//
//  QueryBuilderView.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI

// MARK: - Query Builder View

/// Visual query builder for constructing arXiv and ADS search queries
public struct QueryBuilderView: View {
    @Binding var state: QueryBuilderState
    @Binding var rawQuery: String
    @State private var isRawQueryExpanded = false
    @State private var isManuallyEditing = false
    @State private var isSyncing = false  // Prevents feedback loop when syncing

    public init(state: Binding<QueryBuilderState>, rawQuery: Binding<String>) {
        self._state = state
        self._rawQuery = rawQuery
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Source and match type pickers
            HStack(spacing: 16) {
                Picker("Source", selection: $state.source) {
                    ForEach(QuerySource.allCases) { source in
                        Text(source.displayName).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .onChange(of: state.source) { _, newSource in
                    state.updateSource(to: newSource)
                    syncRawQuery()
                }

                Picker("Match", selection: $state.matchType) {
                    ForEach(QueryMatchType.allCases) { matchType in
                        Text(matchType.displayName).tag(matchType)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .onChange(of: state.matchType) { _, _ in
                    syncRawQuery()
                }

                Spacer()
            }

            // Query terms
            ForEach($state.terms) { $term in
                QueryTermRow(
                    term: $term,
                    availableFields: state.source.fields,
                    canDelete: state.terms.count > 1,
                    onDelete: {
                        state.removeTerm(id: term.id)
                        syncRawQuery()
                    },
                    onValueChange: {
                        syncRawQuery()
                    }
                )
            }

            // Add condition button
            Button {
                state.addTerm()
            } label: {
                Label("Add Condition", systemImage: "plus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            // Raw query disclosure
            DisclosureGroup("Raw Query", isExpanded: $isRawQueryExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Query", text: $rawQuery, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onSubmit {
                            parseRawQuery()
                        }
                        .onChange(of: rawQuery) { _, _ in
                            // Only mark as manually editing if this isn't a programmatic sync
                            if !isSyncing {
                                isManuallyEditing = true
                            }
                        }

                    Text("Edit directly or use the builder above")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .onChange(of: isRawQueryExpanded) { _, expanded in
                if expanded {
                    // Sync raw query when expanding
                    syncRawQuery()
                }
            }
        }
        .onAppear {
            // Initialize raw query if empty
            if rawQuery.isEmpty && !state.terms.allSatisfy({ $0.value.isEmpty }) {
                syncRawQuery()
            }
        }
    }

    private func syncRawQuery() {
        guard !isManuallyEditing else { return }
        isSyncing = true
        rawQuery = state.generateQuery()
        isSyncing = false
    }

    private func parseRawQuery() {
        isManuallyEditing = false
        state = QueryBuilderState.parse(query: rawQuery, source: state.source)
    }
}

// MARK: - Query Term Row

/// A single row in the query builder: field picker + value + delete button
struct QueryTermRow: View {
    @Binding var term: QueryTerm
    let availableFields: [QueryField]
    let canDelete: Bool
    let onDelete: () -> Void
    let onValueChange: () -> Void

    @State private var showPicker = false

    var body: some View {
        HStack(spacing: 8) {
            // Field picker
            Picker("Field", selection: $term.field) {
                ForEach(availableFields) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .labelsHidden()
            .frame(width: 180)
            .onChange(of: term.field) { _, newField in
                // Clear value when switching to/from special picker field
                if newField.requiresSpecialPicker || term.field.requiresSpecialPicker {
                    term.value = ""
                }
                onValueChange()
            }

            // Value input - depends on picker type
            switch term.field.pickerType {
            case .arXivCategory:
                // Category picker button
                pickerButton(placeholder: "Select category...")
                    .sheet(isPresented: $showPicker) {
                        ArXivCategoryPickerView(selectedCategory: $term.value)
                            .onChange(of: term.value) { _, _ in
                                onValueChange()
                            }
                    }

            case .adsProperty:
                // Property picker button
                pickerButton(placeholder: "Select property...")
                    .sheet(isPresented: $showPicker) {
                        ADSPropertyPickerView(selectedProperty: $term.value)
                            .onChange(of: term.value) { _, _ in
                                onValueChange()
                            }
                    }

            case .none:
                // Text field
                TextField(term.field.placeholder, text: $term.value)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: term.value) { _, _ in
                        onValueChange()
                    }
            }

            // Delete button
            Button {
                onDelete()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .opacity(canDelete ? 1 : 0.3)
            .disabled(!canDelete)
        }
    }

    @ViewBuilder
    private func pickerButton(placeholder: String) -> some View {
        Button {
            showPicker = true
        } label: {
            HStack {
                if term.value.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                } else {
                    Text(term.value)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ADS Property Picker View

/// A picker for selecting ADS property values
struct ADSPropertyPickerView: View {
    @Binding var selectedProperty: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(ADSPropertyGroup.allCases) { group in
                    Section(group.displayName) {
                        ForEach(group.properties) { property in
                            Button {
                                selectedProperty = property.rawValue
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(property.displayName)
                                            .foregroundStyle(.primary)
                                        Text(property.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedProperty == property.rawValue {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Select Property")
            #if os(macOS)
            .frame(minWidth: 350, minHeight: 400)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct QueryBuilderView_Previews: PreviewProvider {
    static var previews: some View {
        QueryBuilderPreview()
            .padding()
            .frame(width: 500)
    }
}

struct QueryBuilderPreview: View {
    @State private var state = QueryBuilderState(
        source: .arXiv,
        matchType: .all,
        terms: [
            QueryTerm(field: .arXivAuthor, value: "Einstein"),
            QueryTerm(field: .arXivTitle, value: "relativity")
        ]
    )
    @State private var rawQuery = ""

    var body: some View {
        QueryBuilderView(state: $state, rawQuery: $rawQuery)
    }
}
#endif
