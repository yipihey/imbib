//
//  IOSSidebarView.swift
//  imbib-iOS
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI
import PublicationManagerCore

/// iOS sidebar with library navigation, smart searches, and collections.
///
/// Adapts the macOS sidebar for iOS with appropriate touch targets and navigation patterns.
struct IOSSidebarView: View {

    // MARK: - Environment

    @Environment(LibraryManager.self) private var libraryManager
    @Environment(LibraryViewModel.self) private var libraryViewModel

    // MARK: - Bindings

    @Binding var selection: SidebarSection?

    // MARK: - State

    @State private var showNewLibrarySheet = false
    @State private var showNewSmartSearchSheet = false
    @State private var showNewCollectionSheet = false
    @State private var selectedLibraryForAction: CDLibrary?

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
        }
        .listStyle(.sidebar)
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

                        if let library = selectedLibraryForAction {
                            Divider()

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
                    library: library
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

    @ViewBuilder
    private func librarySection(for library: CDLibrary) -> some View {
        Section(library.displayName) {
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
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteSmartSearch(search)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
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

// MARK: - iOS Smart Search Editor Sheet

struct IOSSmartSearchEditorSheet: View {
    @Binding var isPresented: Bool
    let library: CDLibrary

    @State private var name = ""
    @State private var query = ""
    @State private var sourceID = "ads"
    @State private var maxResults: Int = 100

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Smart Search Name", text: $name)
                }

                Section("Query") {
                    TextField("Search Query", text: $query)
                        .autocapitalization(.none)
                }

                Section("Source") {
                    Picker("Source", selection: $sourceID) {
                        Text("ADS").tag("ads")
                        Text("arXiv").tag("arxiv")
                        Text("Crossref").tag("crossref")
                        Text("Semantic Scholar").tag("semanticscholar")
                    }
                }

                Section {
                    Stepper("Max Results: \(maxResults)", value: $maxResults, in: 10...1000, step: 10)
                }
            }
            .navigationTitle("New Smart Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createSmartSearch()
                    }
                    .disabled(name.isEmpty || query.isEmpty)
                }
            }
        }
    }

    private func createSmartSearch() {
        Task {
            let repository = SmartSearchRepository()
            _ = repository.create(
                name: name,
                query: query,
                sourceIDs: [sourceID],
                library: library,
                maxResults: Int16(maxResults)
            )
            isPresented = false
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
