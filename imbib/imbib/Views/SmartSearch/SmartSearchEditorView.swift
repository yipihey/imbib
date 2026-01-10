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
    let defaultFeedsToInbox: Bool
    let onSave: () -> Void

    // MARK: - State

    @State private var name: String = ""
    @State private var query: String = ""
    @State private var queryBuilderState = QueryBuilderState()
    @State private var isManuallyEditing: Bool = false
    @State private var selectedSourceIDs: Set<String> = []
    @State private var availableSources: [SourceMetadata] = []

    // Inbox options
    @State private var feedsToInbox: Bool = false
    @State private var autoRefreshEnabled: Bool = false
    @State private var refreshInterval: RefreshIntervalPreset = .daily

    // Raw query visibility (expanded by default to show generated query)
    @State private var isRawQueryExpanded: Bool = true

    // MARK: - Initialization

    init(
        smartSearch: CDSmartSearch?,
        library: CDLibrary?,
        defaultFeedsToInbox: Bool = false,
        onSave: @escaping () -> Void
    ) {
        self.smartSearch = smartSearch
        self.library = library
        self.defaultFeedsToInbox = defaultFeedsToInbox
        self.onSave = onSave
    }

    private var isEditing: Bool {
        smartSearch != nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name, prompt: Text("My papers"))
                }

                Section("Query") {
                    QueryBuilderView(
                        state: $queryBuilderState,
                        rawQuery: $query,
                        isManuallyEditing: $isManuallyEditing,
                        isRawQueryExpanded: $isRawQueryExpanded
                    )
                    .onChange(of: queryBuilderState.source) { _, newSource in
                        let sourceID = newSource == .arXiv ? "arxiv" : "ads"
                        selectedSourceIDs = [sourceID]
                    }
                }

                Section("Sources") {
                    Toggle("All Sources", isOn: Binding(
                        get: { selectedSourceIDs.isEmpty },
                        set: { useAll in
                            if useAll {
                                selectedSourceIDs.removeAll()
                            } else {
                                selectedSourceIDs = Set(availableSources.map { $0.id })
                            }
                        }
                    ))

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

                Section {
                    Toggle("Feed to Inbox", isOn: $feedsToInbox)

                    if feedsToInbox {
                        Toggle("Auto-Refresh", isOn: $autoRefreshEnabled)

                        if autoRefreshEnabled {
                            Picker("Refresh Interval", selection: $refreshInterval) {
                                ForEach(RefreshIntervalPreset.allCases, id: \.self) { preset in
                                    Text(preset.displayName).tag(preset)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Inbox")
                } footer: {
                    if feedsToInbox {
                        Text("Papers from this search will be added to your Inbox for triage.")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Smart Search" : "New Smart Search")
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
                    .disabled(name.isEmpty || (query.isEmpty && queryBuilderState.generateQuery().isEmpty))
                }
            }
            .task {
                await loadData()
            }
        }
        #if os(macOS)
        .frame(minWidth: 450, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .frame(idealWidth: 550, idealHeight: 650)
        #endif
    }

    // MARK: - Data Loading

    private func loadData() async {
        availableSources = await searchViewModel.availableSources

        if let smartSearch {
            name = smartSearch.name
            selectedSourceIDs = Set(smartSearch.sources)

            // Parse existing query into query builder
            // Detect source from selected sources
            let source: QuerySource = smartSearch.sources.contains("ads") ? .ads : .arXiv
            queryBuilderState = QueryBuilderState.parse(query: smartSearch.query, source: source)

            // IMPORTANT: Set query to the REGENERATED version to fix any malformed queries
            // This ensures field:value format is correct (e.g., author:"Name" not "author: Name")
            query = queryBuilderState.generateQuery()

            // Load inbox settings
            feedsToInbox = smartSearch.feedsToInbox
            autoRefreshEnabled = smartSearch.autoRefreshEnabled
            refreshInterval = RefreshIntervalPreset(rawValue: smartSearch.refreshIntervalSeconds) ?? .daily

            // Reset isManuallyEditing since we just loaded/regenerated the query
            // (onChange of query may have set this to true during load)
            isManuallyEditing = false
        } else {
            // Apply defaults for new smart search
            feedsToInbox = defaultFeedsToInbox
            autoRefreshEnabled = defaultFeedsToInbox  // Auto-refresh on by default for inbox feeds

            // Set initial source based on query builder's default source
            let sourceID = queryBuilderState.source == .arXiv ? "arxiv" : "ads"
            selectedSourceIDs = [sourceID]
        }
    }

    // MARK: - Save

    private func saveSmartSearch() {
        // Use manual edits if user edited the raw query directly, otherwise generate from builder
        let finalQuery = isManuallyEditing ? query : queryBuilderState.generateQuery()
        let sourceIDs = Array(selectedSourceIDs)

        if let smartSearch {
            SmartSearchRepository.shared.update(
                smartSearch,
                name: name,
                query: finalQuery,
                sourceIDs: sourceIDs
            )

            // Update inbox settings
            smartSearch.feedsToInbox = feedsToInbox
            smartSearch.autoRefreshEnabled = autoRefreshEnabled
            smartSearch.refreshIntervalSeconds = refreshInterval.seconds
            try? smartSearch.managedObjectContext?.save()

            // Invalidate cached results so next view loads fresh data
            Task {
                await SmartSearchProviderCache.shared.invalidate(smartSearch.id)
            }
        } else {
            let newSearch = SmartSearchRepository.shared.create(
                name: name,
                query: finalQuery,
                sourceIDs: sourceIDs,
                library: library
            )

            // Set inbox settings for new search
            newSearch.feedsToInbox = feedsToInbox
            newSearch.autoRefreshEnabled = autoRefreshEnabled
            newSearch.refreshIntervalSeconds = refreshInterval.seconds
            try? newSearch.managedObjectContext?.save()
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
