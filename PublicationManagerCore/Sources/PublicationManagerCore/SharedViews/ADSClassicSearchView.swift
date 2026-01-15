//
//  ADSClassicSearchView.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-14.
//

import SwiftUI

#if os(macOS)

// MARK: - Year Picker

/// A picker for selecting a year with optional "Any" value
public struct YearPicker: View {
    let label: String
    @Binding var selection: Int?

    private let currentYear = Calendar.current.component(.year, from: Date())
    private let startYear = 1800

    public init(_ label: String, selection: Binding<Int?>) {
        self.label = label
        self._selection = selection
    }

    public var body: some View {
        Picker(label, selection: $selection) {
            Text("Any").tag(nil as Int?)
            ForEach((startYear...currentYear).reversed(), id: \.self) { year in
                Text(String(year)).tag(year as Int?)
            }
        }
        #if os(macOS)
        .pickerStyle(.menu)
        #endif
    }
}

// MARK: - ADS Classic Search View

/// Multi-field search form matching the classic ADS interface
public struct ADSClassicSearchView: View {

    // MARK: - Environment

    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(LibraryViewModel.self) private var libraryViewModel

    // MARK: - Bindings

    @Binding var selectedPublication: CDPublication?

    // MARK: - Form State

    @State private var authors: String = ""
    @State private var isAddingToInbox: Bool = false
    @State private var objects: String = ""
    @State private var titleWords: String = ""
    @State private var titleLogic: QueryLogic = .and
    @State private var abstractWords: String = ""
    @State private var abstractLogic: QueryLogic = .and
    @State private var yearFrom: Int? = nil
    @State private var yearTo: Int? = nil
    @State private var database: ADSDatabase = .all
    @State private var refereedOnly: Bool = false
    @State private var articlesOnly: Bool = false

    // MARK: - Initialization

    public init(selectedPublication: Binding<CDPublication?>) {
        self._selectedPublication = selectedPublication
    }

    // MARK: - State for Layout

    @State private var isFormExpanded: Bool = true

    // MARK: - Body

    public var body: some View {
        @Bindable var viewModel = searchViewModel

        VStack(spacing: 0) {
            // Collapsible form section
            DisclosureGroup(isExpanded: $isFormExpanded) {
                formContent
            } label: {
                HStack {
                    Label("Search Criteria", systemImage: "list.bullet.rectangle")
                        .font(.headline)
                    Spacer()
                    if !isFormEmpty {
                        Text("Fields filled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()

            Divider()

            // Results section
            resultsContent
        }
    }

    // MARK: - Form Content

    @ViewBuilder
    private var formContent: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Authors")
                        .font(.headline)
                    TextEditor(text: $authors)
                        .font(.body)
                        .frame(minHeight: 60, maxHeight: 100)
                        .border(Color.secondary.opacity(0.3), width: 1)
                    Text("One author per line (Last, First M)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Objects")
                        .font(.headline)
                    TextField("SIMBAD/NED object names", text: $objects)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title")
                        .font(.headline)
                    HStack {
                        TextField("Title words", text: $titleWords)
                            .textFieldStyle(.roundedBorder)
                        logicPicker(selection: $titleLogic)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Abstract / Keywords")
                        .font(.headline)
                    HStack {
                        TextField("Abstract words", text: $abstractWords)
                            .textFieldStyle(.roundedBorder)
                        logicPicker(selection: $abstractLogic)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Publication Date")
                        .font(.headline)
                    HStack {
                        YearPicker("From", selection: $yearFrom)
                        Text("to")
                            .foregroundStyle(.secondary)
                        YearPicker("To", selection: $yearTo)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Database")
                        .font(.headline)
                    Picker("Collection", selection: $database) {
                        ForEach(ADSDatabase.allCases, id: \.self) { db in
                            Text(db.displayName).tag(db)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Filters")
                        .font(.headline)
                    HStack(spacing: 20) {
                        Toggle("Refereed only", isOn: $refereedOnly)
                        Toggle("Articles only", isOn: $articlesOnly)
                    }
                    .toggleStyle(.checkbox)
                }
            }

            // Action buttons
            Section {
                HStack {
                    Button("Clear") {
                        clearForm()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        addToInbox()
                    } label: {
                        if isAddingToInbox {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Add to Inbox")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isFormEmpty || isAddingToInbox)

                    Button("Search") {
                        performSearch()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isFormEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Results Content

    @ViewBuilder
    private var resultsContent: some View {
        @Bindable var viewModel = searchViewModel

        if viewModel.isSearching {
            ProgressView("Searching...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.publications.isEmpty && viewModel.query.isEmpty {
            ContentUnavailableView {
                Label("ADS Classic Search", systemImage: "list.bullet.rectangle")
            } description: {
                Text("Fill in the form and click Search to find publications.")
            }
        } else if viewModel.publications.isEmpty {
            ContentUnavailableView {
                Label("No Results", systemImage: "magnifyingglass")
            } description: {
                Text("No publications found matching your criteria.")
            }
        } else {
            PublicationListView(
                publications: viewModel.publications,
                selection: $viewModel.selectedPublicationIDs,
                selectedPublication: $selectedPublication,
                library: libraryManager.activeLibrary,
                allLibraries: libraryManager.libraries,
                showImportButton: false,
                showSortMenu: true,
                emptyStateMessage: "No Results",
                emptyStateDescription: "Fill in the form and click Search.",
                listID: libraryManager.activeLibrary?.lastSearchCollection.map { .lastSearch($0.id) },
                filterScope: .constant(.current),
                onDelete: { ids in
                    await libraryViewModel.delete(ids: ids)
                },
                onToggleRead: { publication in
                    await libraryViewModel.toggleReadStatus(publication)
                },
                onCopy: { ids in
                    await libraryViewModel.copyToClipboard(ids)
                },
                onCut: { ids in
                    await libraryViewModel.cutToClipboard(ids)
                },
                onPaste: {
                    try? await libraryViewModel.pasteFromClipboard()
                },
                onAddToLibrary: { ids, targetLibrary in
                    await libraryViewModel.addToLibrary(ids, library: targetLibrary)
                },
                onAddToCollection: { ids, collection in
                    await libraryViewModel.addToCollection(ids, collection: collection)
                },
                onRemoveFromAllCollections: { ids in
                    await libraryViewModel.removeFromAllCollections(ids)
                },
                onOpenPDF: { _ in }
            )
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func logicPicker(selection: Binding<QueryLogic>) -> some View {
        Picker("", selection: selection) {
            Text("AND").tag(QueryLogic.and)
            Text("OR").tag(QueryLogic.or)
        }
        .pickerStyle(.segmented)
        .frame(width: 100)
    }

    // MARK: - Computed Properties

    private var isFormEmpty: Bool {
        SearchFormQueryBuilder.isClassicFormEmpty(
            authors: authors,
            objects: objects,
            titleWords: titleWords,
            abstractWords: abstractWords,
            yearFrom: yearFrom,
            yearTo: yearTo
        )
    }

    // MARK: - Actions

    private func performSearch() {
        let query = SearchFormQueryBuilder.buildClassicQuery(
            authors: authors,
            objects: objects,
            titleWords: titleWords,
            titleLogic: titleLogic,
            abstractWords: abstractWords,
            abstractLogic: abstractLogic,
            yearFrom: yearFrom,
            yearTo: yearTo,
            database: database,
            refereedOnly: refereedOnly,
            articlesOnly: articlesOnly
        )

        searchViewModel.query = query
        searchViewModel.selectedSourceIDs = Set(database.sourceIDs)

        Task {
            await searchViewModel.search()
        }
    }

    private func addToInbox() {
        let query = SearchFormQueryBuilder.buildClassicQuery(
            authors: authors,
            objects: objects,
            titleWords: titleWords,
            titleLogic: titleLogic,
            abstractWords: abstractWords,
            abstractLogic: abstractLogic,
            yearFrom: yearFrom,
            yearTo: yearTo,
            database: database,
            refereedOnly: refereedOnly,
            articlesOnly: articlesOnly
        )

        searchViewModel.query = query
        searchViewModel.selectedSourceIDs = Set(database.sourceIDs)

        isAddingToInbox = true

        Task {
            // First perform the search to get results
            await searchViewModel.search()

            // Then add all results to the inbox
            let inboxManager = InboxManager.shared
            for publication in searchViewModel.publications {
                inboxManager.addToInbox(publication)
            }

            isAddingToInbox = false
        }
    }

    private func clearForm() {
        authors = ""
        objects = ""
        titleWords = ""
        titleLogic = .and
        abstractWords = ""
        abstractLogic = .and
        yearFrom = nil
        yearTo = nil
        database = .all
        refereedOnly = false
        articlesOnly = false
    }
}

// MARK: - ADS Classic Search Form View (Detail Pane)

/// Form-only view for the detail pane (right side)
/// Results are shown in the middle pane via SearchResultsListView
public struct ADSClassicSearchFormView: View {

    // MARK: - Environment

    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - Local State (not persisted)

    @State private var isAddingToInbox: Bool = false

    // MARK: - Initialization

    public init() {}

    // MARK: - Body

    public var body: some View {
        @Bindable var viewModel = searchViewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Label("ADS Classic Search", systemImage: "list.bullet.rectangle")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Multi-field search matching the classic ADS interface")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                // Authors
                VStack(alignment: .leading, spacing: 4) {
                    Text("Authors")
                        .font(.headline)
                    TextEditor(text: $viewModel.classicFormState.authors)
                        .font(.body)
                        .frame(minHeight: 60, maxHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    Text("One author per line (Last, First M)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Objects
                VStack(alignment: .leading, spacing: 4) {
                    Text("Objects")
                        .font(.headline)
                    TextField("SIMBAD/NED object names", text: $viewModel.classicFormState.objects)
                        .textFieldStyle(.roundedBorder)
                }

                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title")
                        .font(.headline)
                    HStack {
                        TextField("Title words", text: $viewModel.classicFormState.titleWords)
                            .textFieldStyle(.roundedBorder)
                        logicPicker(selection: $viewModel.classicFormState.titleLogic)
                    }
                }

                // Abstract
                VStack(alignment: .leading, spacing: 4) {
                    Text("Abstract / Keywords")
                        .font(.headline)
                    HStack {
                        TextField("Abstract words", text: $viewModel.classicFormState.abstractWords)
                            .textFieldStyle(.roundedBorder)
                        logicPicker(selection: $viewModel.classicFormState.abstractLogic)
                    }
                }

                // Publication Date
                VStack(alignment: .leading, spacing: 4) {
                    Text("Publication Date")
                        .font(.headline)
                    HStack {
                        YearPicker("From", selection: $viewModel.classicFormState.yearFrom)
                        Text("to")
                            .foregroundStyle(.secondary)
                        YearPicker("To", selection: $viewModel.classicFormState.yearTo)
                    }
                }

                // Database
                VStack(alignment: .leading, spacing: 4) {
                    Text("Database")
                        .font(.headline)
                    Picker("Collection", selection: $viewModel.classicFormState.database) {
                        ForEach(ADSDatabase.allCases, id: \.self) { db in
                            Text(db.displayName).tag(db)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Filters
                VStack(alignment: .leading, spacing: 8) {
                    Text("Filters")
                        .font(.headline)
                    HStack(spacing: 20) {
                        Toggle("Refereed only", isOn: $viewModel.classicFormState.refereedOnly)
                        Toggle("Articles only", isOn: $viewModel.classicFormState.articlesOnly)
                    }
                    .toggleStyle(.checkbox)
                }

                Divider()
                    .padding(.vertical, 8)

                // Edit mode header
                if searchViewModel.isEditMode, let smartSearch = searchViewModel.editingSmartSearch {
                    HStack {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Editing: \(smartSearch.name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") {
                            searchViewModel.exitEditMode()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Action buttons
                HStack {
                    Button("Clear") {
                        clearForm()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if searchViewModel.isEditMode {
                        // Edit mode: Save button
                        Button("Save") {
                            searchViewModel.saveToSmartSearch()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isFormEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                    } else {
                        // Normal mode: Add to Inbox and Search buttons
                        Button {
                            addToInbox()
                        } label: {
                            if isAddingToInbox {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Add to Inbox")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isFormEmpty || isAddingToInbox)

                        Button("Search") {
                            performSearch()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isFormEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .task {
            // Ensure SearchViewModel has access to LibraryManager
            searchViewModel.setLibraryManager(libraryManager)
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func logicPicker(selection: Binding<QueryLogic>) -> some View {
        Picker("", selection: selection) {
            Text("AND").tag(QueryLogic.and)
            Text("OR").tag(QueryLogic.or)
        }
        .pickerStyle(.segmented)
        .frame(width: 100)
    }

    // MARK: - Computed Properties

    private var isFormEmpty: Bool {
        searchViewModel.classicFormState.isEmpty
    }

    // MARK: - Actions

    private func performSearch() {
        let state = searchViewModel.classicFormState
        let query = SearchFormQueryBuilder.buildClassicQuery(
            authors: state.authors,
            objects: state.objects,
            titleWords: state.titleWords,
            titleLogic: state.titleLogic,
            abstractWords: state.abstractWords,
            abstractLogic: state.abstractLogic,
            yearFrom: state.yearFrom,
            yearTo: state.yearTo,
            database: state.database,
            refereedOnly: state.refereedOnly,
            articlesOnly: state.articlesOnly
        )

        searchViewModel.query = query
        searchViewModel.selectedSourceIDs = Set(state.database.sourceIDs)

        Task {
            await searchViewModel.search()
        }
    }

    private func addToInbox() {
        let state = searchViewModel.classicFormState
        let query = SearchFormQueryBuilder.buildClassicQuery(
            authors: state.authors,
            objects: state.objects,
            titleWords: state.titleWords,
            titleLogic: state.titleLogic,
            abstractWords: state.abstractWords,
            abstractLogic: state.abstractLogic,
            yearFrom: state.yearFrom,
            yearTo: state.yearTo,
            database: state.database,
            refereedOnly: state.refereedOnly,
            articlesOnly: state.articlesOnly
        )

        searchViewModel.query = query
        searchViewModel.selectedSourceIDs = Set(state.database.sourceIDs)

        isAddingToInbox = true

        Task {
            await searchViewModel.search()

            let inboxManager = InboxManager.shared
            for publication in searchViewModel.publications {
                inboxManager.addToInbox(publication)
            }

            isAddingToInbox = false
        }
    }

    private func clearForm() {
        searchViewModel.classicFormState.clear()
    }
}

#endif  // os(macOS)
