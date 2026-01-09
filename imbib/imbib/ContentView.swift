//
//  ContentView.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import CoreData
import PublicationManagerCore
import OSLog

private let contentLogger = Logger(subsystem: "com.imbib.app", category: "content")

struct ContentView: View {

    // MARK: - Environment

    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - State

    @State private var selectedSection: SidebarSection? = nil
    /// Store publication ID instead of Core Data object to prevent unnecessary view rebuilds
    /// when selected publication's properties change (e.g., isRead, title)
    @State private var selectedPublicationID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showImportPreview = false
    @State private var importFileURL: URL?
    /// Selected detail tab - persisted across paper changes so PDF tab stays selected
    @State private var selectedDetailTab: DetailTab = .info
    /// Expanded libraries in sidebar - passed as binding for persistence
    @State private var expandedLibraries: Set<UUID> = []
    /// Whether initial state restoration has completed
    @State private var hasRestoredState = false

    // MARK: - Derived Selection

    /// The publication ID that the detail view should display.
    /// Updated asynchronously after selection to allow list to feel responsive.
    @State private var displayedPublicationID: UUID?

    /// Derive the selected publication for the detail view.
    private var displayedPublication: CDPublication? {
        guard let id = displayedPublicationID else { return nil }
        return libraryViewModel.publication(for: id)
    }

    /// Create a binding that maps UUID to CDPublication for list views.
    /// Updates list selection immediately, defers detail view for responsive feel.
    private var selectedPublicationBinding: Binding<CDPublication?> {
        Binding(
            get: {
                guard let id = selectedPublicationID else { return nil }
                return libraryViewModel.publication(for: id)
            },
            set: { newPublication in
                let newID = newPublication?.id
                // Update list selection immediately for instant visual feedback
                selectedPublicationID = newID

                // Defer detail view update - user sees selection change first,
                // then detail view catches up (feels more responsive)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    displayedPublicationID = newID
                }
            }
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selectedSection, expandedLibraries: $expandedLibraries)
        } content: {
            contentList
        } detail: {
            detailView
                // OPTIMIZATION: Force view replacement instead of diffing
                // id() tells SwiftUI this is a completely new view, skip expensive diff
                .id(displayedPublicationID)
                // OPTIMIZATION: Disable NavigationSplitView transition animations
                .transaction { $0.animation = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showLibrary)) { notification in
            // Select the first library if available
            if let library = notification.object as? CDLibrary {
                selectedSection = .library(library)
            } else if let firstLibrary = libraryManager.libraries.first {
                selectedSection = .library(firstLibrary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSearch)) { _ in
            selectedSection = .search
        }
        .onReceive(NotificationCenter.default.publisher(for: .importBibTeX)) { _ in
            showImportPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportBibTeX)) { _ in
            showExportPanel()
        }
        .sheet(isPresented: $showImportPreview) {
            if let url = importFileURL {
                ImportPreviewView(
                    isPresented: $showImportPreview,
                    fileURL: url
                ) { entries in
                    try await importPreviewEntries(entries)
                }
            }
        }
        .task {
            await libraryViewModel.loadPublications()
            // Restore app state after publications are loaded
            await restoreAppState()
        }
        .onAppear {
            contentLogger.info("ContentView appeared - main window is visible")
        }
        .onChange(of: selectedSection) { oldValue, newValue in
            // ADR-016: All sections now use CDPublication
            // Clear selection when switching sections
            if oldValue != newValue {
                selectedPublicationID = nil
                displayedPublicationID = nil
            }
            // Save state when section changes
            if hasRestoredState {
                saveAppState()
            }
        }
        .onChange(of: selectedPublicationID) { _, newID in
            // Clear selection if publication was deleted
            if let id = newID {
                // Check if the publication still exists and is valid
                if libraryViewModel.publication(for: id) == nil {
                    selectedPublicationID = nil
                    displayedPublicationID = nil
                }
            }
            // Save state when publication changes
            if hasRestoredState {
                saveAppState()
            }
        }
        .onChange(of: selectedDetailTab) { _, _ in
            if hasRestoredState {
                saveAppState()
            }
        }
        .onChange(of: expandedLibraries) { _, _ in
            if hasRestoredState {
                saveAppState()
            }
        }
    }

    // MARK: - State Persistence

    /// Restore app state from persistent storage
    private func restoreAppState() async {
        let state = await AppStateStore.shared.state

        // Restore expanded libraries first
        expandedLibraries = state.expandedLibraries

        // Restore detail tab
        if let tab = DetailTab(rawValue: state.selectedDetailTab) {
            selectedDetailTab = tab
        }

        // Restore sidebar selection
        if let sidebarState = state.sidebarSelection {
            selectedSection = sidebarSectionFrom(sidebarState)
        }

        // Restore selected publication (with small delay to let list load)
        if let pubID = state.selectedPublicationID {
            try? await Task.sleep(for: .milliseconds(100))
            if libraryViewModel.publication(for: pubID) != nil {
                selectedPublicationID = pubID
                displayedPublicationID = pubID
            }
        }

        hasRestoredState = true
        contentLogger.info("Restored app state: section=\(String(describing: selectedSection)), paper=\(selectedPublicationID?.uuidString ?? "none")")
    }

    /// Save current app state to persistent storage
    private func saveAppState() {
        Task {
            let state = AppState(
                sidebarSelection: sidebarSelectionStateFrom(selectedSection),
                selectedPublicationID: selectedPublicationID,
                selectedDetailTab: selectedDetailTab.rawValue,
                expandedLibraries: expandedLibraries
            )
            await AppStateStore.shared.save(state)
        }
    }

    /// Convert SidebarSelectionState (serializable) to SidebarSection (with Core Data objects)
    private func sidebarSectionFrom(_ state: SidebarSelectionState) -> SidebarSection? {
        switch state {
        case .inbox:
            return .inbox

        case .inboxFeed(let id):
            if let smartSearch = findSmartSearch(by: id) {
                return .inboxFeed(smartSearch)
            }
            return nil

        case .library(let id):
            if let library = libraryManager.libraries.first(where: { $0.id == id }) {
                return .library(library)
            }
            return nil

        case .unread(let id):
            if let library = libraryManager.libraries.first(where: { $0.id == id }) {
                return .unread(library)
            }
            return nil

        case .search:
            return .search

        case .smartSearch(let id):
            if let smartSearch = findSmartSearch(by: id) {
                return .smartSearch(smartSearch)
            }
            return nil

        case .collection(let id):
            if let collection = findCollection(by: id) {
                return .collection(collection)
            }
            return nil
        }
    }

    /// Convert SidebarSection (with Core Data objects) to SidebarSelectionState (serializable UUIDs)
    private func sidebarSelectionStateFrom(_ section: SidebarSection?) -> SidebarSelectionState? {
        guard let section = section else { return nil }

        switch section {
        case .inbox:
            return .inbox
        case .inboxFeed(let smartSearch):
            return .inboxFeed(smartSearch.id)
        case .library(let library):
            return .library(library.id)
        case .unread(let library):
            return .unread(library.id)
        case .search:
            return .search
        case .smartSearch(let smartSearch):
            return .smartSearch(smartSearch.id)
        case .collection(let collection):
            return .collection(collection.id)
        }
    }

    /// Find a smart search by UUID
    private func findSmartSearch(by id: UUID) -> CDSmartSearch? {
        let request = NSFetchRequest<CDSmartSearch>(entityName: "SmartSearch")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? PersistenceController.shared.viewContext.fetch(request).first
    }

    /// Find a collection by UUID
    private func findCollection(by id: UUID) -> CDCollection? {
        let request = NSFetchRequest<CDCollection>(entityName: "Collection")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? PersistenceController.shared.viewContext.fetch(request).first
    }

    // MARK: - Content List

    @ViewBuilder
    private var contentList: some View {
        switch selectedSection {
        case .inbox:
            // Show all papers in the Inbox library
            if let inboxLibrary = InboxManager.shared.inboxLibrary {
                UnifiedPublicationListWrapper(
                    source: .library(inboxLibrary),
                    selectedPublication: selectedPublicationBinding
                )
            } else {
                ContentUnavailableView(
                    "Inbox Empty",
                    systemImage: "tray",
                    description: Text("Add feeds to start discovering papers")
                )
            }

        case .inboxFeed(let smartSearch):
            // Show papers from a specific inbox feed (same as smart search)
            UnifiedPublicationListWrapper(
                source: .smartSearch(smartSearch),
                selectedPublication: selectedPublicationBinding
            )

        case .library(let library):
            UnifiedPublicationListWrapper(
                source: .library(library),
                selectedPublication: selectedPublicationBinding
            )

        case .unread(let library):
            UnifiedPublicationListWrapper(
                source: .library(library),
                selectedPublication: selectedPublicationBinding,
                initialFilterMode: .unread
            )

        case .search:
            SearchResultsListView(selectedPublication: selectedPublicationBinding)

        case .smartSearch(let smartSearch):
            UnifiedPublicationListWrapper(
                source: .smartSearch(smartSearch),
                selectedPublication: selectedPublicationBinding
            )

        case .collection(let collection):
            CollectionListView(collection: collection, selection: selectedPublicationBinding)

        case .none:
            ContentUnavailableView(
                "No Selection",
                systemImage: "sidebar.left",
                description: Text("Select a library or collection from the sidebar")
            )
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        // Guard against deleted Core Data objects - check isDeleted and managedObjectContext
        // DetailView.init is failable and returns nil for deleted publications
        // Uses displayedPublication (deferred) instead of immediate selection for smoother UX
        if let publication = displayedPublication,
           !publication.isDeleted,
           publication.managedObjectContext != nil,
           let libraryID = selectedLibraryID,
           let detail = DetailView(publication: publication, libraryID: libraryID, selectedTab: $selectedDetailTab) {
            detail
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "doc.text",
                description: Text("Select a publication to view details")
            )
        }
    }

    /// Extract library ID from current section selection
    private var selectedLibraryID: UUID? {
        switch selectedSection {
        case .inbox:
            return InboxManager.shared.inboxLibrary?.id
        case .inboxFeed(let smartSearch):
            // Inbox feeds belong to the Inbox library
            return InboxManager.shared.inboxLibrary?.id ?? smartSearch.library?.id
        case .library(let library), .unread(let library):
            return library.id
        case .smartSearch(let smartSearch):
            return smartSearch.library?.id
        case .collection(let collection):
            return collection.owningLibrary?.id
        default:
            return nil
        }
    }

    // MARK: - Import/Export

    private func showImportPanel() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "bib")!,
            .init(filenameExtension: "ris")!
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a BibTeX (.bib) or RIS (.ris) file to import"

        if panel.runModal() == .OK, let url = panel.url {
            importFileURL = url
            showImportPreview = true
        }
        #endif
    }

    private func importPreviewEntries(_ entries: [ImportPreviewEntry]) async throws -> Int {
        var count = 0

        for entry in entries {
            switch entry.source {
            case .bibtex(let bibtex):
                await libraryViewModel.importEntry(bibtex)
                count += 1

            case .ris(let ris):
                // Convert RIS to BibTeX and import
                let bibtex = RISBibTeXConverter.toBibTeX(ris)
                await libraryViewModel.importEntry(bibtex)
                count += 1
            }
        }

        await libraryViewModel.loadPublications()
        return count
    }

    private func showExportPanel() {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "bib")!]
        panel.nameFieldStringValue = "library.bib"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                let bibtex = await libraryViewModel.exportAll()
                do {
                    try bibtex.write(to: url, atomically: true, encoding: .utf8)
                    print("Exported to \(url.path)")
                } catch {
                    print("Export failed: \(error)")
                }
            }
        }
        #endif
    }
}

// MARK: - Sidebar Section

enum SidebarSection: Hashable {
    case inbox                         // Inbox - all papers waiting for triage
    case inboxFeed(CDSmartSearch)      // Inbox feed (smart search with feedsToInbox)
    case library(CDLibrary)           // All publications for specific library
    case unread(CDLibrary)            // Unread publications for specific library
    case search                        // Global search
    case smartSearch(CDSmartSearch)   // Smart search (library-scoped via relationship)
    case collection(CDCollection)     // Collection (library-scoped via relationship)
}

// MARK: - Collection List View

struct CollectionListView: View {
    let collection: CDCollection
    @Binding var selection: CDPublication?

    // MARK: - Environment

    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - State

    @State private var publications: [CDPublication] = []
    @State private var multiSelection = Set<UUID>()
    @State private var filterMode: LibraryFilterMode = .all
    @StateObject private var dropHandler = FileDropHandler()

    // State for duplicate file alert
    @State private var showDuplicateAlert = false
    @State private var duplicateFilename = ""

    // MARK: - Body

    var body: some View {
        PublicationListView(
            publications: publications,
            selection: $multiSelection,
            selectedPublication: $selection,
            library: collection.owningLibrary,
            allLibraries: libraryManager.libraries,
            showImportButton: false,
            showSortMenu: true,
            emptyStateMessage: "No Publications",
            emptyStateDescription: "Drag publications to this collection.",
            listID: .collection(collection.id),
            onDelete: { ids in
                await libraryViewModel.delete(ids: ids)
                refreshPublications()
            },
            onToggleRead: { publication in
                await libraryViewModel.toggleReadStatus(publication)
                refreshPublications()
            },
            onCopy: { ids in
                await libraryViewModel.copyToClipboard(ids)
            },
            onCut: { ids in
                await libraryViewModel.cutToClipboard(ids)
                refreshPublications()
            },
            onPaste: {
                try? await libraryViewModel.pasteFromClipboard()
                refreshPublications()
            },
            onAddToLibrary: { ids, targetLibrary in
                await libraryViewModel.addToLibrary(ids, library: targetLibrary)
                refreshPublications()
            },
            onAddToCollection: { ids, targetCollection in
                await libraryViewModel.addToCollection(ids, collection: targetCollection)
            },
            onRemoveFromAllCollections: { ids in
                await libraryViewModel.removeFromAllCollections(ids)
                refreshPublications()
            },
            onImport: nil,
            onOpenPDF: { publication in
                openPDF(for: publication)
            },
            onFileDrop: { publication, providers in
                Task {
                    await dropHandler.handleDrop(
                        providers: providers,
                        for: publication,
                        in: collection.owningLibrary
                    )
                    refreshPublications()
                }
            }
        )
        .navigationTitle(collection.name)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Filter", selection: $filterMode) {
                    Text("All").tag(LibraryFilterMode.all)
                    Text("Unread").tag(LibraryFilterMode.unread)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            ToolbarItem(placement: .automatic) {
                Text("\(publications.count) items")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: collection.id) {
            refreshPublications()
        }
        .onChange(of: filterMode) { _, _ in
            refreshPublications()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleReadStatus)) { _ in
            toggleReadStatusForSelected()
        }
        .onReceive(NotificationCenter.default.publisher(for: .copyPublications)) { _ in
            Task { await copySelectedPublications() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cutPublications)) { _ in
            Task { await cutSelectedPublications() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pastePublications)) { _ in
            Task {
                try? await libraryViewModel.pasteFromClipboard()
                refreshPublications()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectAllPublications)) { _ in
            selectAllPublications()
        }
        .alert("Duplicate File", isPresented: $showDuplicateAlert) {
            Button("Skip") {
                dropHandler.resolveDuplicate(proceed: false)
            }
            Button("Attach Anyway") {
                dropHandler.resolveDuplicate(proceed: true)
            }
        } message: {
            Text("This file is identical to '\(duplicateFilename)' which is already attached. Do you want to attach it anyway?")
        }
        .onChange(of: dropHandler.pendingDuplicate) { _, newValue in
            if let pending = newValue {
                duplicateFilename = pending.existingFilename
                showDuplicateAlert = true
            }
        }
    }

    // MARK: - Data Refresh

    private func refreshPublications() {
        var result = (collection.publications ?? [])
            .filter { !$0.isDeleted && $0.managedObjectContext != nil }

        if filterMode == .unread {
            result = result.filter { !$0.isRead }
        }

        publications = result.sorted { $0.dateAdded > $1.dateAdded }
    }

    // MARK: - Notification Handlers

    private func selectAllPublications() {
        multiSelection = Set(publications.map { $0.id })
    }

    private func toggleReadStatusForSelected() {
        guard !multiSelection.isEmpty else { return }

        Task {
            // Apple Mail behavior: if ANY are unread, mark ALL as read
            // If ALL are read, mark ALL as unread
            await libraryViewModel.smartToggleReadStatus(multiSelection)
            refreshPublications()
        }
    }

    private func copySelectedPublications() async {
        guard !multiSelection.isEmpty else { return }
        await libraryViewModel.copyToClipboard(multiSelection)
    }

    private func cutSelectedPublications() async {
        guard !multiSelection.isEmpty else { return }
        await libraryViewModel.cutToClipboard(multiSelection)
        refreshPublications()
    }

    // MARK: - Helpers

    private func openPDF(for publication: CDPublication) {
        if let linkedFiles = publication.linkedFiles,
           let pdfFile = linkedFiles.first(where: { $0.isPDF }),
           let libraryURL = collection.owningLibrary?.folderURL {
            let pdfURL = libraryURL.appendingPathComponent(pdfFile.relativePath)
            #if os(macOS)
            NSWorkspace.shared.open(pdfURL)
            #endif
        }
    }
}


#Preview {
    ContentView()
        .environment(LibraryManager())
        .environment(LibraryViewModel())
        .environment(SearchViewModel(
            sourceManager: SourceManager(),
            deduplicationService: DeduplicationService(),
            repository: PublicationRepository()
        ))
        .environment(SettingsViewModel(
            sourceManager: SourceManager(),
            credentialManager: CredentialManager()
        ))
}
