//
//  IOSSidebarView.swift
//  imbib-iOS
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI
import PublicationManagerCore
import os

/// iOS sidebar with library navigation, smart searches, and collections.
///
/// Adapts the macOS sidebar for iOS with appropriate touch targets and navigation patterns.
struct IOSSidebarView: View {

    // MARK: - Environment

    @Environment(LibraryManager.self) private var libraryManager
    @Environment(LibraryViewModel.self) private var libraryViewModel

    // MARK: - Bindings

    @Binding var selection: SidebarSection?
    var onNavigateToSmartSearch: ((CDSmartSearch) -> Void)?  // Callback for iPhone navigation

    // MARK: - State

    @State private var showNewLibrarySheet = false
    @State private var showNewSmartSearchSheet = false
    @State private var showNewCollectionSheet = false
    @State private var showArXivCategoryBrowser = false
    @State private var selectedLibraryForAction: CDLibrary?
    @State private var editingSmartSearch: CDSmartSearch?
    @State private var refreshID = UUID()  // Used to force list refresh

    // MARK: - Body

    var body: some View {
        List(selection: $selection) {
            // Inbox Section
            inboxSection

            // Search Section
            Section {
                Label("Search", systemImage: "magnifyingglass")
                    .tag(SidebarSection.search)
            }

            // Libraries
            ForEach(libraryManager.libraries.filter { !$0.isInbox }) { library in
                librarySection(for: library)
            }
            .id(refreshID)  // Force refresh when smart searches change
        }
        .listStyle(.sidebar)
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            // Refresh when Core Data saves (new smart search, collection, etc.)
            refreshID = UUID()
        }
        .navigationTitle("imbib")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Menu {
                        Button {
                            showNewLibrarySheet = true
                        } label: {
                            Label("New Library", systemImage: "folder.badge.plus")
                        }

                        // Use selected library or default to first non-inbox library
                        if let library = selectedLibraryForAction ?? libraryManager.libraries.first(where: { !$0.isInbox }) {
                            Divider()

                            // Show which library is targeted
                            Section("Add to \(library.displayName)") {
                                Button {
                                    selectedLibraryForAction = library
                                    showNewSmartSearchSheet = true
                                } label: {
                                    Label("New Smart Search", systemImage: "magnifyingglass.circle")
                                }

                                Button {
                                    selectedLibraryForAction = library
                                    showNewCollectionSheet = true
                                } label: {
                                    Label("New Collection", systemImage: "folder")
                                }
                            }
                        }

                        Divider()

                        // arXiv category browser
                        Button {
                            showArXivCategoryBrowser = true
                        } label: {
                            Label("Browse arXiv Categories", systemImage: "list.bullet.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }

                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showNewLibrarySheet) {
            NewLibrarySheet(isPresented: $showNewLibrarySheet)
        }
        .sheet(isPresented: $showNewSmartSearchSheet) {
            if let library = selectedLibraryForAction {
                IOSSmartSearchEditorSheet(
                    isPresented: $showNewSmartSearchSheet,
                    library: library,
                    onCreated: { newSmartSearch in
                        // Navigate to the new smart search
                        selection = .smartSearch(newSmartSearch)
                        // Use callback for iPhone navigation (needs small delay for sheet dismiss)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onNavigateToSmartSearch?(newSmartSearch)
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showNewCollectionSheet) {
            if let library = selectedLibraryForAction {
                NewCollectionSheet(
                    isPresented: $showNewCollectionSheet,
                    library: library
                )
            }
        }
        .sheet(item: $editingSmartSearch) { smartSearch in
            IOSSmartSearchEditorSheet(
                isPresented: Binding(
                    get: { editingSmartSearch != nil },
                    set: { if !$0 { editingSmartSearch = nil } }
                ),
                library: smartSearch.library,
                smartSearch: smartSearch,
                onSaved: { _ in
                    editingSmartSearch = nil
                }
            )
        }
        .sheet(isPresented: $showArXivCategoryBrowser) {
            IOSArXivCategoryBrowserSheet(
                isPresented: $showArXivCategoryBrowser,
                library: selectedLibraryForAction ?? libraryManager.libraries.first(where: { !$0.isInbox })
            )
        }
        .onChange(of: selection) { _, newValue in
            // Track which library is selected for contextual actions
            switch newValue {
            case .library(let lib), .unread(let lib):
                selectedLibraryForAction = lib
            case .smartSearch(let ss):
                selectedLibraryForAction = ss.library
            case .collection(let col):
                selectedLibraryForAction = col.owningLibrary
            default:
                break
            }
        }
    }

    // MARK: - Inbox Section

    @ViewBuilder
    private var inboxSection: some View {
        Section("Inbox") {
            // Main Inbox
            HStack {
                Label("Inbox", systemImage: "tray")
                Spacer()
                if InboxManager.shared.unreadCount > 0 {
                    Text("\(InboxManager.shared.unreadCount)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            .tag(SidebarSection.inbox)

            // Inbox Feeds (Smart Searches that feed to inbox)
            if let inboxLib = InboxManager.shared.inboxLibrary,
               let feedSet = inboxLib.smartSearches?.filter({ $0.feedsToInbox }),
               !feedSet.isEmpty {
                ForEach(Array(feedSet)) { feed in
                    Label(feed.name, systemImage: "antenna.radiowaves.left.and.right")
                        .tag(SidebarSection.inboxFeed(feed))
                }
            }
        }
    }

    // MARK: - Library Section

    /// Check if this library is the currently selected one for actions
    private func isLibrarySelected(_ library: CDLibrary) -> Bool {
        selectedLibraryForAction?.id == library.id
    }

    @ViewBuilder
    private func librarySection(for library: CDLibrary) -> some View {
        Section {
            // All Publications
            HStack {
                Label("All Publications", systemImage: "books.vertical")
                Spacer()
                Text("\(library.publications?.count ?? 0)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .tag(SidebarSection.library(library))

            // Unread
            let unreadCount = library.publications?.filter { !$0.isRead }.count ?? 0
            if unreadCount > 0 {
                HStack {
                    Label("Unread", systemImage: "circle.fill")
                        .foregroundStyle(.blue)
                    Spacer()
                    Text("\(unreadCount)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .tag(SidebarSection.unread(library))
            }

            // Smart Searches
            if let searchSet = library.smartSearches?.filter({ !$0.feedsToInbox }), !searchSet.isEmpty {
                DisclosureGroup("Smart Searches") {
                    ForEach(Array(searchSet)) { search in
                        Label(search.name, systemImage: "magnifyingglass.circle")
                            .tag(SidebarSection.smartSearch(search))
                            .contextMenu {
                                Button {
                                    editingSmartSearch = search
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    deleteSmartSearch(search)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteSmartSearch(search)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingSmartSearch = search
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                }
            }

            // Collections
            if let collectionSet = library.collections, !collectionSet.isEmpty {
                DisclosureGroup("Collections") {
                    ForEach(Array(collectionSet)) { collection in
                        HStack {
                            Label(collection.name, systemImage: "folder")
                            Spacer()
                            Text("\(collection.publications?.count ?? 0)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .tag(SidebarSection.collection(collection))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteCollection(collection)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text(library.displayName)
                if isLibrarySelected(library) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Actions

    private func deleteSmartSearch(_ search: CDSmartSearch) {
        if case .smartSearch(search) = selection {
            selection = nil
        }
        Task {
            await SmartSearchRepository().delete(search)
        }
    }

    private func deleteCollection(_ collection: CDCollection) {
        if case .collection(collection) = selection {
            selection = nil
        }
        // Delete collection using its managed object context
        if let context = collection.managedObjectContext {
            context.delete(collection)
            try? context.save()
        }
    }
}

// MARK: - New Library Sheet

struct NewLibrarySheet: View {
    @Binding var isPresented: Bool
    @Environment(LibraryManager.self) private var libraryManager

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Library Name", text: $name)
                }

                Section {
                    Text("On iOS, libraries are stored in the app's container and synced via iCloud.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createLibrary()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func createLibrary() {
        Task { @MainActor in
            // On iOS, create library in app container
            let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let libraryURL = containerURL.appendingPathComponent("\(name).bib")

            // Create empty .bib file
            try? "".write(to: libraryURL, atomically: true, encoding: .utf8)

            libraryManager.createLibrary(name: name, bibFileURL: libraryURL)
            isPresented = false
        }
    }
}

// MARK: - New Collection Sheet

struct NewCollectionSheet: View {
    @Binding var isPresented: Bool
    let library: CDLibrary

    @Environment(LibraryViewModel.self) private var libraryViewModel
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Collection Name", text: $name)
            }
            .navigationTitle("New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createCollection()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func createCollection() {
        // Create collection directly in Core Data
        guard let context = library.managedObjectContext else {
            isPresented = false
            return
        }

        let collection = CDCollection(context: context)
        collection.id = UUID()
        collection.name = name
        collection.isSmartCollection = false
        collection.owningLibrary = library
        library.collections?.insert(collection)

        try? context.save()
        isPresented = false
    }
}

// MARK: - arXiv Search Field Enum

/// Search field options for arXiv queries
enum ArXivSearchField: String, CaseIterable, Identifiable {
    case all = "all"
    case title = "ti"
    case author = "au"
    case abstract = "abs"
    case category = "cat"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All Fields"
        case .title: return "Title"
        case .author: return "Author"
        case .abstract: return "Abstract"
        case .category: return "Category"
        }
    }

    var helpText: String {
        switch self {
        case .all: return "Search across all fields"
        case .title: return "Search in paper titles"
        case .author: return "Search by author name"
        case .abstract: return "Search in abstracts"
        case .category: return "Filter by arXiv category (e.g., cs.LG)"
        }
    }
}

// MARK: - iOS Smart Search Editor Sheet

struct IOSSmartSearchEditorSheet: View {
    @Binding var isPresented: Bool
    let library: CDLibrary?
    let smartSearch: CDSmartSearch?  // nil for create, non-nil for edit
    let defaultFeedsToInbox: Bool
    let onSaved: ((CDSmartSearch) -> Void)?

    @Environment(SettingsViewModel.self) private var settingsViewModel
    @Environment(SearchViewModel.self) private var searchViewModel

    @State private var name = ""
    @State private var query = ""
    @State private var maxResults: Int = 100
    @State private var credentialStatus: [SourceCredentialInfo] = []

    // Multi-source selection (like macOS)
    @State private var selectedSourceIDs: Set<String> = []
    @State private var availableSources: [SourceMetadata] = []

    // Inbox feed options (like macOS)
    @State private var feedsToInbox: Bool = false
    @State private var autoRefreshEnabled: Bool = false
    @State private var refreshInterval: RefreshIntervalPreset = .sixHours

    // arXiv field-specific search
    @State private var arxivSearchField: ArXivSearchField = .all
    @State private var arxivCategory: String = ""
    @State private var showCategoryPicker = false

    private var isEditing: Bool { smartSearch != nil }

    /// Check if arXiv is one of the selected sources
    private var hasArXivSelected: Bool {
        selectedSourceIDs.contains("arxiv") || selectedSourceIDs.isEmpty
    }

    /// Get warning messages for missing credentials
    private var credentialWarnings: [String] {
        let selectedIDs = selectedSourceIDs.isEmpty
            ? Set(availableSources.map { $0.id })
            : selectedSourceIDs

        return credentialStatus
            .filter { selectedIDs.contains($0.sourceID) && $0.status == .missing }
            .map { "\($0.sourceName) requires an API key." }
    }

    // Convenience initializer for creating new smart search
    init(isPresented: Binding<Bool>, library: CDLibrary, onCreated: ((CDSmartSearch) -> Void)? = nil) {
        self._isPresented = isPresented
        self.library = library
        self.smartSearch = nil
        self.defaultFeedsToInbox = false
        self.onSaved = onCreated
    }

    // Full initializer for editing or creating with defaults
    init(
        isPresented: Binding<Bool>,
        library: CDLibrary?,
        smartSearch: CDSmartSearch? = nil,
        defaultFeedsToInbox: Bool = false,
        onSaved: ((CDSmartSearch) -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self.library = library
        self.smartSearch = smartSearch
        self.defaultFeedsToInbox = defaultFeedsToInbox
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Smart Search Name", text: $name)
                }

                // Multi-source selection (matching macOS)
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

                    // Warning if sources require missing credentials
                    if !credentialWarnings.isEmpty {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(credentialWarnings, id: \.self) { warning in
                                    Text(warning)
                                        .font(.caption)
                                }
                                Text("Configure API keys in Settings.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Query section with arXiv field selector
                Section {
                    // Show arXiv field selector when arXiv is one of the selected sources
                    if hasArXivSelected {
                        Picker("arXiv Field", selection: $arxivSearchField) {
                            ForEach(ArXivSearchField.allCases) { field in
                                Text(field.displayName).tag(field)
                            }
                        }

                        // Category picker for category field
                        if arxivSearchField == .category {
                            Button {
                                showCategoryPicker = true
                            } label: {
                                HStack {
                                    Text("Category")
                                    Spacer()
                                    if arxivCategory.isEmpty {
                                        Text("Select...")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(arxivCategory)
                                            .foregroundStyle(.primary)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }

                        // Help text for arXiv field
                        Text(arxivSearchField.helpText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Query text field (always shown unless category-only)
                    if !(hasArXivSelected && arxivSearchField == .category) {
                        TextField("Search Query", text: $query)
                            .autocapitalization(.none)
                    }
                } header: {
                    Text("Query")
                }

                // Inbox feed options (matching macOS)
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

                Section {
                    Stepper("Max Results: \(maxResults)", value: $maxResults, in: 10...1000, step: 10)
                }
            }
            .navigationTitle(isEditing ? "Edit Smart Search" : "New Smart Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        saveSmartSearch()
                    }
                    .disabled(name.isEmpty || !hasValidQuery)
                }
            }
            .task {
                await loadData()
            }
            .sheet(isPresented: $showCategoryPicker) {
                IOSArXivCategoryPickerSheet(
                    selectedCategory: $arxivCategory,
                    isPresented: $showCategoryPicker
                )
            }
        }
    }

    /// Check if the query is valid (non-empty query or selected category)
    private var hasValidQuery: Bool {
        if hasArXivSelected && arxivSearchField == .category {
            return !arxivCategory.isEmpty
        }
        return !query.isEmpty
    }

    /// Build the final query with field prefix for arXiv
    private var finalQuery: String {
        if hasArXivSelected && arxivSearchField != .all {
            switch arxivSearchField {
            case .all:
                return query
            case .title:
                return "ti:\(query)"
            case .author:
                return "au:\(query)"
            case .abstract:
                return "abs:\(query)"
            case .category:
                return "cat:\(arxivCategory)"
            }
        }
        return query
    }

    private func loadData() async {
        // Load available sources
        availableSources = await searchViewModel.availableSources

        // Load credential status to show warnings
        await settingsViewModel.loadCredentialStatus()
        credentialStatus = settingsViewModel.sourceCredentials

        // Load existing values if editing
        if let smartSearch {
            name = smartSearch.name
            selectedSourceIDs = Set(smartSearch.sources)
            maxResults = Int(smartSearch.maxResults)

            // Load inbox settings
            feedsToInbox = smartSearch.feedsToInbox
            autoRefreshEnabled = smartSearch.autoRefreshEnabled
            refreshInterval = RefreshIntervalPreset(rawValue: smartSearch.refreshIntervalSeconds) ?? .sixHours

            // Parse arXiv field-specific queries
            let existingQuery = smartSearch.query
            if smartSearch.sources.contains("arxiv") || smartSearch.sources.isEmpty {
                if existingQuery.hasPrefix("ti:") {
                    arxivSearchField = .title
                    query = String(existingQuery.dropFirst(3))
                } else if existingQuery.hasPrefix("au:") {
                    arxivSearchField = .author
                    query = String(existingQuery.dropFirst(3))
                } else if existingQuery.hasPrefix("abs:") {
                    arxivSearchField = .abstract
                    query = String(existingQuery.dropFirst(4))
                } else if existingQuery.hasPrefix("cat:") {
                    arxivSearchField = .category
                    arxivCategory = String(existingQuery.dropFirst(4))
                } else {
                    arxivSearchField = .all
                    query = existingQuery
                }
            } else {
                query = existingQuery
            }
        } else {
            // Apply defaults for new smart search
            feedsToInbox = defaultFeedsToInbox
            autoRefreshEnabled = defaultFeedsToInbox  // Auto-refresh on by default for inbox feeds
        }
    }

    private func saveSmartSearch() {
        let queryToSave = finalQuery
        let sourceIDs = Array(selectedSourceIDs)

        if let smartSearch {
            // Update existing
            SmartSearchRepository.shared.update(
                smartSearch,
                name: name,
                query: queryToSave,
                sourceIDs: sourceIDs
            )
            smartSearch.maxResults = Int16(maxResults)

            // Update inbox settings
            smartSearch.feedsToInbox = feedsToInbox
            smartSearch.autoRefreshEnabled = autoRefreshEnabled
            smartSearch.refreshIntervalSeconds = refreshInterval.seconds

            try? smartSearch.managedObjectContext?.save()

            // Invalidate cache so results refresh
            Task {
                await SmartSearchProviderCache.shared.invalidate(smartSearch.id)
            }

            isPresented = false
            onSaved?(smartSearch)
        } else if let library {
            // Create new smart search
            let newSearch = SmartSearchRepository.shared.create(
                name: name,
                query: queryToSave,
                sourceIDs: sourceIDs,
                library: library,
                maxResults: Int16(maxResults)
            )

            // Set inbox settings after creation
            newSearch.feedsToInbox = feedsToInbox
            newSearch.autoRefreshEnabled = autoRefreshEnabled
            newSearch.refreshIntervalSeconds = refreshInterval.seconds
            try? newSearch.managedObjectContext?.save()

            isPresented = false
            onSaved?(newSearch)
        }
    }
}

// MARK: - iOS arXiv Category Browser Sheet

/// Sheet wrapper for ArXivCategoryBrowser on iOS.
///
/// Allows users to browse arXiv categories and create feeds to track new papers.
struct IOSArXivCategoryBrowserSheet: View {
    @Binding var isPresented: Bool
    let library: CDLibrary?

    var body: some View {
        NavigationStack {
            ArXivCategoryBrowser(
                onFollow: { category, feedName in
                    createCategoryFeed(category: category, name: feedName)
                },
                onDismiss: {
                    isPresented = false
                }
            )
            .navigationTitle("arXiv Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }

    private func createCategoryFeed(category: ArXivCategory, name: String) {
        guard let library else { return }

        // Create smart search with category query
        let smartSearch = SmartSearchRepository.shared.create(
            name: name,
            query: "cat:\(category.id)",
            sourceIDs: ["arxiv"],
            library: library,
            maxResults: 100
        )

        // Set inbox feed settings
        smartSearch.feedsToInbox = true
        smartSearch.autoRefreshEnabled = true
        smartSearch.refreshIntervalSeconds = 86400  // Daily refresh
        try? smartSearch.managedObjectContext?.save()

        // Log creation
        os_log(.info, "Created arXiv category feed: %{public}@ for category %{public}@",
               smartSearch.name, category.id)

        isPresented = false
    }
}

// MARK: - iOS arXiv Category Picker Sheet

/// A simple category picker for selecting an arXiv category in smart search editor.
struct IOSArXivCategoryPickerSheet: View {
    @Binding var selectedCategory: String
    @Binding var isPresented: Bool

    @State private var searchText = ""

    private var filteredCategories: [ArXivCategory] {
        if searchText.isEmpty {
            return ArXivCategories.all
        }
        let lowercased = searchText.lowercased()
        return ArXivCategories.all.filter { category in
            category.id.lowercased().contains(lowercased) ||
            category.name.lowercased().contains(lowercased) ||
            category.group.lowercased().contains(lowercased)
        }
    }

    private var groupedCategories: [(String, [ArXivCategory])] {
        Dictionary(grouping: filteredCategories) { $0.group }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.sorted { $0.id < $1.id }) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedCategories, id: \.0) { group, categories in
                    Section(group) {
                        ForEach(categories) { category in
                            Button {
                                selectedCategory = category.id
                                isPresented = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(category.id)
                                            .font(.headline)
                                        Text(category.name)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if selectedCategory == category.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search categories")
            .navigationTitle("Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        IOSSidebarView(selection: .constant(nil))
            .environment(LibraryManager())
            .environment(LibraryViewModel())
    }
}
