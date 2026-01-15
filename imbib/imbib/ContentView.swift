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
    /// Multi-selection for bulk operations (BibTeX export, etc.)
    @State private var selectedPublicationIDs = Set<UUID>()

    /// Whether to show search form (true) or results (false) in list pane
    /// Form is shown initially; switches to results after search executes
    @State private var showSearchFormInList: Bool = true

    /// Data for batch PDF download sheet (nil = not shown)
    @State private var batchDownloadData: BatchDownloadData?

    /// Navigation history for browser-style back/forward
    private var navigationHistory = NavigationHistoryStore.shared

    /// Flag to skip history push when navigating via back/forward
    @State private var isNavigatingViaHistory = false

    // MARK: - Derived Selection

    /// The publication ID that the detail view should display.
    /// Updated asynchronously after selection to allow list to feel responsive.
    @State private var displayedPublicationID: UUID?

    /// Derive the selected publication for the detail view.
    private var displayedPublication: CDPublication? {
        guard let id = displayedPublicationID else { return nil }
        return libraryViewModel.publication(for: id)
    }

    /// Get the selected publications for multi-selection operations (e.g., BibTeX export).
    private var selectedPublications: [CDPublication] {
        selectedPublicationIDs.compactMap { libraryViewModel.publication(for: $0) }
    }

    /// Whether multiple papers are selected.
    private var isMultiSelection: Bool {
        selectedPublicationIDs.count > 1
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
        let _ = contentLogger.info("⏱ ContentView.body START")
        NavigationSplitView(columnVisibility: $columnVisibility) {
            let _ = contentLogger.info("⏱ SidebarView creating")
            SidebarView(selection: $selectedSection, expandedLibraries: $expandedLibraries)
        } content: {
            let _ = contentLogger.info("⏱ contentList creating")
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
        .onReceive(NotificationCenter.default.publisher(for: .resetSearchFormView)) { _ in
            // Reset to show search form in list pane and clear detail pane
            showSearchFormInList = true
            displayedPublicationID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCollection)) { notification in
            // Auto-select first publication when navigating to exploration collection
            if let firstPubID = notification.userInfo?["firstPublicationID"] as? UUID {
                // Small delay to let the list view load first
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    selectedPublicationID = firstPubID
                    displayedPublicationID = firstPubID
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSmartSearch)) { notification in
            // Navigate to a smart search in the sidebar (typically from Search section → Exploration)
            guard let smartSearchID = notification.object as? UUID else { return }
            // Find the smart search in the exploration library
            if let explorationLib = libraryManager.explorationLibrary,
               let smartSearch = explorationLib.smartSearches?.first(where: { $0.id == smartSearchID }) {
                isNavigatingViaHistory = true
                selectedSection = .smartSearch(smartSearch)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .editSmartSearch)) { notification in
            handleEditSmartSearch(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSearchSection)) { _ in
            handleNavigateToSearchSection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateBack)) { _ in
            navigateBack()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateForward)) { _ in
            navigateForward()
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
        .sheet(item: $batchDownloadData) { data in
            PDFBatchDownloadView(publications: data.publications, library: data.library)
        }
        .task {
            // Load publications for the lookup cache (improves navigation speed)
            // This runs async after the UI is visible, so it doesn't block startup
            await libraryViewModel.loadPublications()
            // Restore app state after publications are loaded
            await restoreAppState()
        }
        .onAppear {
            contentLogger.info("⏱ ContentView.onAppear - window visible")
        }
        .onChange(of: selectedSection) { oldValue, newValue in
            // ADR-016: All sections now use CDPublication
            // Clear selection when switching sections (but not for search forms - keep detail pane)
            if oldValue != newValue {
                // For search forms, don't clear the selection - keep detail pane showing current paper
                if case .searchForm = newValue {
                    // Reset to show form in list pane
                    showSearchFormInList = true
                } else {
                    selectedPublicationID = nil
                    displayedPublicationID = nil
                }

                // Track navigation history (skip if navigating via back/forward)
                if !isNavigatingViaHistory {
                    if let state = sidebarSelectionStateFrom(newValue) {
                        navigationHistory.push(state)
                    }
                }
                isNavigatingViaHistory = false
            }
            // Save state when section changes
            if hasRestoredState {
                saveAppState()
            }
        }
        .onChange(of: searchViewModel.isSearching) { wasSearching, isSearching in
            // When search completes (isSearching goes from true to false), switch to results view
            if wasSearching && !isSearching {
                showSearchFormInList = false
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

    // MARK: - Navigation History

    /// Navigate back in history (Cmd+[)
    func navigateBack() {
        guard let state = navigationHistory.goBack() else { return }
        isNavigatingViaHistory = true
        if let section = sidebarSectionFrom(state) {
            selectedSection = section
        } else {
            // If section is invalid (e.g., collection was deleted), try again
            navigateBack()
        }
    }

    /// Navigate forward in history (Cmd+])
    func navigateForward() {
        guard let state = navigationHistory.goForward() else { return }
        isNavigatingViaHistory = true
        if let section = sidebarSectionFrom(state) {
            selectedSection = section
        } else {
            // If section is invalid (e.g., collection was deleted), try again
            navigateForward()
        }
    }

    // MARK: - Notification Handlers

    /// Handle editSmartSearch notification - loads smart search into search form for editing
    private func handleEditSmartSearch(_ notification: NotificationCenter.Publisher.Output) {
        guard let smartSearchID = notification.object as? UUID else { return }

        // Find the smart search
        guard let smartSearch = findSmartSearch(by: smartSearchID) else { return }

        // Load the smart search into the search view model
        searchViewModel.loadSmartSearch(smartSearch)

        // Navigate to the appropriate search form based on detected form type
        let formType: SearchFormType
        switch searchViewModel.editFormType {
        case .classic:
            formType = .adsClassic
        case .modern:
            formType = .adsModern
        case .paper:
            formType = .adsPaper
        case .arxiv:
            formType = .arxivAdvanced
        }

        // Navigate to the search form and show the form in the list pane
        showSearchFormInList = true
        selectedSection = .searchForm(formType)

        contentLogger.info("Editing smart search '\(smartSearch.name)' using \(String(describing: formType)) form")
    }

    /// Handle navigateToSearchSection notification - navigates to default search form
    private func handleNavigateToSearchSection() {
        showSearchFormInList = true
        selectedSection = .searchForm(.adsClassic)  // Default to Classic form
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

        case .search:
            return .search

        case .searchForm(let formType):
            return .searchForm(formType)

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

        case .scixLibrary(let id):
            if let scixLibrary = findSciXLibrary(by: id) {
                return .scixLibrary(scixLibrary)
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
        case .search:
            return .search
        case .searchForm(let formType):
            return .searchForm(formType)
        case .smartSearch(let smartSearch):
            return .smartSearch(smartSearch.id)
        case .collection(let collection):
            return .collection(collection.id)
        case .scixLibrary(let scixLibrary):
            return .scixLibrary(scixLibrary.id)
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

    /// Find a SciX library by UUID
    private func findSciXLibrary(by id: UUID) -> CDSciXLibrary? {
        let request = NSFetchRequest<CDSciXLibrary>(entityName: "SciXLibrary")
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
                    selectedPublication: selectedPublicationBinding,
                    selectedPublicationIDs: $selectedPublicationIDs,
                    onDownloadPDFs: handleDownloadPDFs
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
                selectedPublication: selectedPublicationBinding,
                selectedPublicationIDs: $selectedPublicationIDs,
                onDownloadPDFs: handleDownloadPDFs
            )

        case .library(let library):
            UnifiedPublicationListWrapper(
                source: .library(library),
                selectedPublication: selectedPublicationBinding,
                selectedPublicationIDs: $selectedPublicationIDs,
                onDownloadPDFs: handleDownloadPDFs
            )

        case .search:
            SearchResultsListView(selectedPublication: selectedPublicationBinding)

        case .searchForm(let formType):
            // Show form in list pane initially, then results after search executes
            if showSearchFormInList {
                searchFormForListPane(formType: formType)
            } else {
                SearchResultsListView(selectedPublication: selectedPublicationBinding)
            }

        case .smartSearch(let smartSearch):
            UnifiedPublicationListWrapper(
                source: .smartSearch(smartSearch),
                selectedPublication: selectedPublicationBinding,
                selectedPublicationIDs: $selectedPublicationIDs,
                onDownloadPDFs: handleDownloadPDFs
            )

        case .collection(let collection):
            CollectionListView(collection: collection, selection: selectedPublicationBinding)

        case .scixLibrary(let scixLibrary):
            SciXLibraryListView(library: scixLibrary, selection: selectedPublicationBinding)

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
        // Multi-selection on BibTeX tab: show combined BibTeX view
        if isMultiSelection && selectedDetailTab == .bibtex {
            MultiSelectionBibTeXView(
                publications: selectedPublications,
                onDownloadPDFs: {
                    handleDownloadPDFs(selectedPublicationIDs)
                }
            )
            // Force view recreation when selection changes
            .id(selectedPublicationIDs)
        }
        // Guard against deleted Core Data objects - check isDeleted and managedObjectContext
        // DetailView.init is failable and returns nil for deleted publications
        // Uses displayedPublication (deferred) instead of immediate selection for smoother UX
        // In multi-selection mode, show the first selected paper's details (PDF/Info/Notes tabs still work)
        else if let publication = displayedPublication,
           !publication.isDeleted,
           publication.managedObjectContext != nil,
           let libraryID = selectedLibraryID,
           let detail = DetailView(
               publication: publication,
               libraryID: libraryID,
               selectedTab: $selectedDetailTab,
               isMultiSelection: isMultiSelection,
               selectedPublicationIDs: selectedPublicationIDs,
               onDownloadPDFs: { handleDownloadPDFs(selectedPublicationIDs) }
           ) {
            detail
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "doc.text",
                description: Text("Select a publication to view details")
            )
        }
    }

    // MARK: - Search Form for List Pane

    /// Render search form in the list pane (middle column)
    @ViewBuilder
    private func searchFormForListPane(formType: SearchFormType) -> some View {
        switch formType {
        case .adsModern:
            ADSModernSearchFormView()
                .navigationTitle("ADS Modern Search")

        case .adsClassic:
            ADSClassicSearchFormView()
                .navigationTitle("ADS Classic Search")

        case .adsPaper:
            ADSPaperSearchFormView()
                .navigationTitle("ADS Paper Search")

        case .arxivAdvanced:
            ArXivAdvancedSearchFormView()
                .navigationTitle("arXiv Advanced Search")
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
        case .library(let library):
            return library.id
        case .smartSearch(let smartSearch):
            return smartSearch.library?.id
        case .collection(let collection):
            return collection.effectiveLibrary?.id
        case .scixLibrary(let scixLibrary):
            // SciX libraries use their own ID (not a local CDLibrary)
            return scixLibrary.id
        case .search, .searchForm:
            // Search results are imported to the active library's "Last Search" collection
            return libraryManager.activeLibrary?.id
        default:
            return nil
        }
    }

    /// Get the current CDLibrary for batch PDF downloads
    private var currentLibrary: CDLibrary? {
        switch selectedSection {
        case .inbox:
            return InboxManager.shared.inboxLibrary
        case .inboxFeed(let smartSearch):
            return InboxManager.shared.inboxLibrary ?? smartSearch.library
        case .library(let library):
            return library
        case .smartSearch(let smartSearch):
            return smartSearch.library
        case .collection(let collection):
            return collection.effectiveLibrary
        case .search, .searchForm:
            return libraryManager.activeLibrary
        default:
            return nil
        }
    }

    // MARK: - Batch PDF Download

    /// Handle "Download PDFs" context menu action
    private func handleDownloadPDFs(_ ids: Set<UUID>) {
        let publications = ids.compactMap { libraryViewModel.publication(for: $0) }
        guard !publications.isEmpty, let library = currentLibrary else { return }

        contentLogger.info("[BatchDownload] Starting batch download for \(publications.count) papers")
        batchDownloadData = BatchDownloadData(publications: publications, library: library)
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
    case search                        // Global search (legacy, kept for compatibility)
    case searchForm(SearchFormType)   // Specific search form (ADS Modern, Classic, Paper)
    case smartSearch(CDSmartSearch)   // Smart search (library-scoped via relationship)
    case collection(CDCollection)     // Collection (library-scoped via relationship)
    case scixLibrary(CDSciXLibrary)   // SciX online library
}

// MARK: - Batch Download Data

/// Data for the batch PDF download sheet.
/// Using Identifiable allows sheet(item:) to properly capture the data when shown.
struct BatchDownloadData: Identifiable {
    let id = UUID()
    let publications: [CDPublication]
    let library: CDLibrary
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
    @State private var filterScope: FilterScope = .current
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
            library: collection.effectiveLibrary,
            allLibraries: libraryManager.libraries,
            showImportButton: false,
            showSortMenu: true,
            emptyStateMessage: "No Publications",
            emptyStateDescription: "Drag publications to this collection.",
            listID: .collection(collection.id),
            filterScope: $filterScope,
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
                        in: collection.effectiveLibrary
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
        Task {
            var result: [CDPublication]

            if collection.isSmartCollection {
                // Execute predicate for smart collections
                result = await libraryViewModel.executeSmartCollection(collection)
            } else {
                // For static collections, use direct relationship
                result = Array(collection.publications ?? [])
                    .filter { !$0.isDeleted && $0.managedObjectContext != nil }
            }

            if filterMode == .unread {
                result = result.filter { !$0.isRead }
            }

            publications = result.sorted { $0.dateAdded > $1.dateAdded }
        }
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
           let libraryURL = collection.effectiveLibrary?.folderURL {
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
