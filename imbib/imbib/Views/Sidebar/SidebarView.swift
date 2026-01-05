//
//  SidebarView.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore

struct SidebarView: View {

    // MARK: - Properties

    @Binding var selection: SidebarSection?

    // MARK: - Environment

    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - State

    @State private var collections: [CDCollection] = []
    @State private var tags: [CDTag] = []
    @State private var smartSearches: [CDSmartSearch] = []
    @State private var showingNewSmartSearch = false
    @State private var editingSmartSearch: CDSmartSearch?
    @State private var showingLibraryPicker = false
    @State private var showingNewSmartCollection = false
    @State private var editingCollection: CDCollection?

    // MARK: - Body

    var body: some View {
        List(selection: $selection) {
            // Library Header with Picker
            Section {
                libraryHeaderButton
            }

            // Library Section
            Section("Library") {
                Label("All Publications", systemImage: "books.vertical")
                    .tag(SidebarSection.library)

                Label("Recently Added", systemImage: "clock")
                    .tag(SidebarSection.recentlyAdded)

                Label("Recently Read", systemImage: "book")
                    .tag(SidebarSection.recentlyRead)
            }

            // Search Section
            Section("Search") {
                Label("Search Sources", systemImage: "magnifyingglass")
                    .tag(SidebarSection.search)
            }

            // Smart Searches Section (library-specific)
            Section {
                ForEach(smartSearches, id: \.id) { smartSearch in
                    SmartSearchRow(smartSearch: smartSearch)
                        .tag(SidebarSection.smartSearch(smartSearch))
                        .contextMenu {
                            Button("Edit") {
                                editingSmartSearch = smartSearch
                            }
                            Button("Delete", role: .destructive) {
                                deleteSmartSearch(smartSearch)
                            }
                        }
                }
            } header: {
                HStack {
                    Text("Smart Searches")
                    Spacer()
                    Button {
                        showingNewSmartSearch = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Collections Section
            Section {
                ForEach(collections, id: \.id) { collection in
                    CollectionRow(collection: collection)
                        .tag(SidebarSection.collection(collection))
                        .contextMenu {
                            if collection.isSmartCollection {
                                Button("Edit") {
                                    editingCollection = collection
                                }
                            }
                            Button("Delete", role: .destructive) {
                                deleteCollection(collection)
                            }
                        }
                }
            } header: {
                HStack {
                    Text("Collections")
                    Spacer()
                    Menu {
                        Button {
                            showingNewSmartCollection = true
                        } label: {
                            Label("New Smart Collection", systemImage: "folder.badge.gearshape")
                        }
                        Button {
                            createStaticCollection()
                        } label: {
                            Label("New Collection", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }

            // Tags Section
            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags, id: \.id) { tag in
                        TagRow(tag: tag)
                            .tag(SidebarSection.tag(tag))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("imbib")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 300)
        #endif
        .task {
            await loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .activeLibraryChanged)) { _ in
            loadSmartSearches()
        }
        .sheet(isPresented: $showingNewSmartSearch) {
            SmartSearchEditorView(smartSearch: nil, library: libraryManager.activeLibrary) {
                loadSmartSearches()
            }
        }
        .sheet(item: $editingSmartSearch) { smartSearch in
            SmartSearchEditorView(smartSearch: smartSearch, library: libraryManager.activeLibrary) {
                loadSmartSearches()
            }
        }
        .sheet(isPresented: $showingLibraryPicker) {
            LibraryPickerView()
        }
        .sheet(isPresented: $showingNewSmartCollection) {
            SmartCollectionEditor(isPresented: $showingNewSmartCollection) { name, predicate in
                Task {
                    await createSmartCollection(name: name, predicate: predicate)
                }
            }
        }
        .sheet(item: $editingCollection) { collection in
            SmartCollectionEditor(isPresented: .constant(true), collection: collection) { name, predicate in
                Task {
                    await updateCollection(collection, name: name, predicate: predicate)
                }
                editingCollection = nil
            }
        }
    }

    // MARK: - Library Header

    private var libraryHeaderButton: some View {
        Button {
            showingLibraryPicker = true
        } label: {
            HStack {
                Image(systemName: "building.columns")
                VStack(alignment: .leading, spacing: 2) {
                    Text(libraryManager.activeLibrary?.displayName ?? "No Library")
                        .font(.headline)
                    if libraryManager.libraries.count > 1 {
                        Text("\(libraryManager.libraries.count) libraries")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Loading

    private func loadData() async {
        let collectionRepo = CollectionRepository()
        let tagRepo = TagRepository()

        collections = await collectionRepo.fetchAll()
        tags = await tagRepo.fetchAll()
        loadSmartSearches()
    }

    private func loadSmartSearches() {
        SmartSearchRepository.shared.loadSmartSearches(for: libraryManager.activeLibrary)
        smartSearches = SmartSearchRepository.shared.smartSearches
    }

    private func deleteSmartSearch(_ smartSearch: CDSmartSearch) {
        let searchID = smartSearch.id
        SmartSearchRepository.shared.delete(smartSearch)
        // Clear cached results
        Task {
            await SmartSearchProviderCache.shared.invalidate(searchID)
        }
        loadSmartSearches()
    }

    // MARK: - Collection Management

    private func loadCollections() async {
        let collectionRepo = CollectionRepository()
        collections = await collectionRepo.fetchAll()
    }

    private func createSmartCollection(name: String, predicate: String) async {
        let collectionRepo = CollectionRepository()
        await collectionRepo.create(name: name, isSmartCollection: true, predicate: predicate)
        await loadCollections()
    }

    private func createStaticCollection() {
        Task {
            let collectionRepo = CollectionRepository()
            await collectionRepo.create(name: "New Collection", isSmartCollection: false)
            await loadCollections()
        }
    }

    private func updateCollection(_ collection: CDCollection, name: String, predicate: String) async {
        let collectionRepo = CollectionRepository()
        await collectionRepo.update(collection, name: name, predicate: predicate)
        await loadCollections()
    }

    private func deleteCollection(_ collection: CDCollection) {
        Task {
            let collectionRepo = CollectionRepository()
            await collectionRepo.delete(collection)
            await loadCollections()
        }
    }
}

// MARK: - Smart Search Row

struct SmartSearchRow: View {
    let smartSearch: CDSmartSearch

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(smartSearch.name)
                Text(smartSearch.query)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "magnifyingglass.circle.fill")
        }
    }
}

// MARK: - Collection Row

struct CollectionRow: View {
    let collection: CDCollection

    var body: some View {
        Label {
            Text(collection.name)
        } icon: {
            Image(systemName: collection.isSmartCollection ? "folder.badge.gearshape" : "folder")
        }
    }
}

// MARK: - Tag Row

struct TagRow: View {
    let tag: CDTag

    var body: some View {
        Label {
            HStack {
                Text(tag.name)
                Spacer()
                Text("\(tag.publications?.count ?? 0)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } icon: {
            Image(systemName: "tag")
        }
    }
}

#Preview {
    SidebarView(selection: .constant(.library))
        .environment(LibraryManager())
}
