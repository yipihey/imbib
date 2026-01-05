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

    @State private var expandedLibraries: Set<UUID> = []
    @State private var showingNewSmartSearch = false
    @State private var editingSmartSearch: CDSmartSearch?
    @State private var showingNewSmartCollection = false
    @State private var editingCollection: CDCollection?
    @State private var showingNewLibrary = false
    @State private var libraryToDelete: CDLibrary?
    @State private var showDeleteConfirmation = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Main list
            List(selection: $selection) {
                // Libraries Section
                Section("Libraries") {
                    ForEach(libraryManager.libraries, id: \.id) { library in
                        libraryDisclosureGroup(for: library)
                    }
                }

                // Search Section
                Section("Search") {
                    Label("Search Sources", systemImage: "magnifyingglass")
                        .tag(SidebarSection.search)
                }
            }
            .listStyle(.sidebar)

            // Bottom toolbar
            Divider()
            bottomToolbar
        }
        .navigationTitle("imbib")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        #endif
        .sheet(isPresented: $showingNewSmartSearch) {
            if let library = selectedLibrary {
                SmartSearchEditorView(smartSearch: nil, library: library) {
                    // Refresh handled by Core Data observation
                }
            }
        }
        .sheet(item: $editingSmartSearch) { smartSearch in
            SmartSearchEditorView(smartSearch: smartSearch, library: smartSearch.library) {
                // Refresh handled by Core Data observation
            }
        }
        .sheet(isPresented: $showingNewLibrary) {
            NewLibrarySheet()
        }
        .sheet(isPresented: $showingNewSmartCollection) {
            if let library = selectedLibrary {
                SmartCollectionEditor(isPresented: $showingNewSmartCollection) { name, predicate in
                    Task {
                        await createSmartCollection(name: name, predicate: predicate, in: library)
                    }
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
        .alert("Delete Library?", isPresented: $showDeleteConfirmation, presenting: libraryToDelete) { library in
            Button("Delete", role: .destructive) {
                deleteLibrary(library)
            }
            Button("Cancel", role: .cancel) {}
        } message: { library in
            Text("Are you sure you want to delete \"\(library.displayName)\"? This will remove all publications and cannot be undone.")
        }
        .task {
            // Auto-expand the first library if none expanded
            if expandedLibraries.isEmpty, let firstLibrary = libraryManager.libraries.first {
                expandedLibraries.insert(firstLibrary.id)
            }
        }
    }

    // MARK: - Library Disclosure Group

    @ViewBuilder
    private func libraryDisclosureGroup(for library: CDLibrary) -> some View {
        DisclosureGroup(
            isExpanded: expansionBinding(for: library.id)
        ) {
            // All Publications
            Label("All Publications", systemImage: "books.vertical")
                .tag(SidebarSection.library(library))

            // Unread with badge
            HStack {
                Label("Unread", systemImage: "circle.fill")
                    .foregroundStyle(.blue)
                Spacer()
                if let count = unreadCount(for: library), count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
            .tag(SidebarSection.unread(library))

            // Smart Searches for this library
            if let smartSearches = library.smartSearches as? Set<CDSmartSearch>, !smartSearches.isEmpty {
                ForEach(Array(smartSearches).sorted(by: { $0.name < $1.name }), id: \.id) { smartSearch in
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
            }

            // Collections for this library
            if let collections = library.collections as? Set<CDCollection>, !collections.isEmpty {
                ForEach(Array(collections).sorted(by: { $0.name < $1.name }), id: \.id) { collection in
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
            }

            // Add buttons for smart search and collection
            Menu {
                Button {
                    showingNewSmartSearch = true
                } label: {
                    Label("New Smart Search", systemImage: "magnifyingglass.circle")
                }
                Button {
                    showingNewSmartCollection = true
                } label: {
                    Label("New Smart Collection", systemImage: "folder.badge.gearshape")
                }
                Button {
                    createStaticCollection(in: library)
                } label: {
                    Label("New Collection", systemImage: "folder.badge.plus")
                }
            } label: {
                Label("Add...", systemImage: "plus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } label: {
            Label(library.displayName, systemImage: "building.columns")
                .contextMenu {
                    Button("Delete Library", role: .destructive) {
                        libraryToDelete = library
                        showDeleteConfirmation = true
                    }
                }
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 16) {
            Button {
                showingNewLibrary = true
            } label: {
                Image(systemName: "plus")
            }
            .help("Add Library")

            Button {
                if let library = selectedLibrary {
                    libraryToDelete = library
                    showDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "minus")
            }
            .disabled(selectedLibrary == nil)
            .help("Remove Library")

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .buttonStyle(.borderless)
    }

    // MARK: - Helpers

    private func expansionBinding(for libraryID: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedLibraries.contains(libraryID) },
            set: { isExpanded in
                if isExpanded {
                    expandedLibraries.insert(libraryID)
                } else {
                    expandedLibraries.remove(libraryID)
                }
            }
        )
    }

    /// Get the currently selected library from the selection
    private var selectedLibrary: CDLibrary? {
        switch selection {
        case .library(let library), .unread(let library):
            return library
        case .smartSearch(let smartSearch):
            return smartSearch.library
        case .collection(let collection):
            return collection.library
        default:
            return nil
        }
    }

    private func unreadCount(for library: CDLibrary) -> Int? {
        // Count unread publications in this library
        guard let publications = library.publications as? Set<CDPublication> else { return nil }
        return publications.filter { !$0.isRead }.count
    }

    // MARK: - Smart Search Management

    private func deleteSmartSearch(_ smartSearch: CDSmartSearch) {
        let searchID = smartSearch.id
        SmartSearchRepository.shared.delete(smartSearch)
        Task {
            await SmartSearchProviderCache.shared.invalidate(searchID)
        }
    }

    // MARK: - Collection Management

    private func createSmartCollection(name: String, predicate: String, in library: CDLibrary) async {
        // Create collection directly in Core Data
        let context = library.managedObjectContext ?? PersistenceController.shared.viewContext
        let collection = CDCollection(context: context)
        collection.id = UUID()
        collection.name = name
        collection.isSmartCollection = true
        collection.predicate = predicate
        collection.library = library
        try? context.save()
    }

    private func createStaticCollection(in library: CDLibrary) {
        let context = library.managedObjectContext ?? PersistenceController.shared.viewContext
        let collection = CDCollection(context: context)
        collection.id = UUID()
        collection.name = "New Collection"
        collection.isSmartCollection = false
        collection.library = library
        try? context.save()
    }

    private func updateCollection(_ collection: CDCollection, name: String, predicate: String) async {
        collection.name = name
        collection.predicate = predicate
        try? collection.managedObjectContext?.save()
    }

    private func deleteCollection(_ collection: CDCollection) {
        guard let context = collection.managedObjectContext else { return }
        context.delete(collection)
        try? context.save()
    }

    // MARK: - Library Management

    private func deleteLibrary(_ library: CDLibrary) {
        try? libraryManager.deleteLibrary(library, deleteFiles: false)
        // Clear selection if we deleted the selected library
        if selectedLibrary?.id == library.id {
            selection = nil
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

// MARK: - New Library Sheet

struct NewLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryManager.self) private var libraryManager

    @State private var name = ""
    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Library Name") {
                    TextField("Name", text: $name, prompt: Text("My Library"))
                }

                #if os(macOS)
                Section("Location") {
                    Button("Choose Folder...") {
                        showFilePicker = true
                    }
                    Text("Select a folder to store your library files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                #endif
            }
            .navigationTitle("New Library")
            #if os(macOS)
            .frame(minWidth: 350, minHeight: 200)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
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
        #if os(macOS)
        // On macOS, show folder picker then create
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder for your library"

        if panel.runModal() == .OK, let url = panel.url {
            let bibURL = url.appendingPathComponent("\(name.isEmpty ? "Library" : name).bib")
            _ = libraryManager.createLibrary(
                name: name.isEmpty ? "New Library" : name,
                bibFileURL: bibURL,
                papersDirectoryURL: url.appendingPathComponent("Papers")
            )
            dismiss()
        }
        #else
        // On iOS, create in app container
        _ = libraryManager.createLibrary(name: name.isEmpty ? "New Library" : name)
        dismiss()
        #endif
    }
}

#Preview {
    SidebarView(selection: .constant(nil))
        .environment(LibraryManager(persistenceController: .preview))
}
