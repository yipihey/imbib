//
//  SmartSearchEditorView.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore

struct SmartSearchEditorView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(SearchViewModel.self) private var searchViewModel

    // MARK: - Properties

    let smartSearch: CDSmartSearch?
    let library: CDLibrary?
    let onSave: () -> Void

    // MARK: - State

    @State private var name: String = ""
    @State private var query: String = ""
    @State private var selectedSourceIDs: Set<String> = []
    @State private var availableSources: [SourceMetadata] = []

    private var isEditing: Bool {
        smartSearch != nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    LabeledContent("Name") {
                        TextField("", text: $name, prompt: Text("My papers").foregroundColor(.secondary))
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("query:") {
                        TextField("", text: $query, prompt: Text("author: Rubin, Vera").foregroundColor(.secondary))
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Section("Sources") {
                    Toggle("All Sources", isOn: Binding(
                        get: { selectedSourceIDs.isEmpty },
                        set: { useAll in
                            if useAll {
                                selectedSourceIDs.removeAll()
                            } else {
                                // Select all sources so user can deselect unwanted ones
                                selectedSourceIDs = Set(availableSources.map { $0.id })
                            }
                        }
                    ))

                    if !availableSources.isEmpty {
                        ForEach(availableSources, id: \.id) { source in
                            Toggle(source.name, isOn: Binding(
                                get: { selectedSourceIDs.contains(source.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedSourceIDs.insert(source.id)
                                    } else {
                                        selectedSourceIDs.remove(source.id)
                                    }
                                }
                            ))
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Smart Search" : "New Smart Search")
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 300)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSmartSearch()
                    }
                    .disabled(name.isEmpty || query.isEmpty)
                }
            }
            .task {
                await loadData()
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        availableSources = await searchViewModel.availableSources

        if let smartSearch {
            name = smartSearch.name
            query = smartSearch.query
            selectedSourceIDs = Set(smartSearch.sources)
        }
    }

    // MARK: - Save

    private func saveSmartSearch() {
        let sourceIDs = Array(selectedSourceIDs)

        if let smartSearch {
            SmartSearchRepository.shared.update(
                smartSearch,
                name: name,
                query: query,
                sourceIDs: sourceIDs
            )
            // Invalidate cached results so next view loads fresh data
            Task {
                await SmartSearchProviderCache.shared.invalidate(smartSearch.id)
            }
        } else {
            SmartSearchRepository.shared.create(
                name: name,
                query: query,
                sourceIDs: sourceIDs,
                library: library
            )
        }

        onSave()
        dismiss()
    }
}

#Preview("New") {
    SmartSearchEditorView(smartSearch: nil, library: nil) {
        print("Saved")
    }
    .environment(SearchViewModel(
        sourceManager: SourceManager(),
        deduplicationService: DeduplicationService(),
        repository: PublicationRepository()
    ))
}
