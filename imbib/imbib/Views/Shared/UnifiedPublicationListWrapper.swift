//
//  UnifiedPublicationListWrapper.swift
//  imbib
//
//  Created by Claude on 2026-01-05.
//

import SwiftUI
import PublicationManagerCore
import OSLog

private let logger = Logger(subsystem: "com.imbib.app", category: "publicationlist")

// MARK: - Publication Source

/// The data source for publications in the unified list view.
enum PublicationSource: Hashable {
    case library(CDLibrary)
    case smartSearch(CDSmartSearch)

    var id: UUID {
        switch self {
        case .library(let library): return library.id
        case .smartSearch(let smartSearch): return smartSearch.id
        }
    }

    var isLibrary: Bool {
        if case .library = self { return true }
        return false
    }

    var isSmartSearch: Bool {
        if case .smartSearch = self { return true }
        return false
    }
}

// MARK: - Filter Mode

/// Filter mode for the publication list.
enum LibraryFilterMode: String, CaseIterable {
    case all
    case unread
}

// Note: SmartSearchProviderCache is now in PublicationManagerCore

// MARK: - Unified Publication List Wrapper

/// A unified wrapper view that displays publications from either a library or a smart search.
///
/// This view uses the same @State + explicit refresh pattern for both sources,
/// ensuring consistent behavior and immediate UI updates after mutations.
///
/// Features (same for both sources):
/// - @State publications with explicit refresh
/// - All/Unread filter toggle
/// - Refresh button (library = future enrichment, smart search = re-search)
/// - Loading/error states
/// - OSLog logging
struct UnifiedPublicationListWrapper: View {

    // MARK: - Properties

    let source: PublicationSource
    @Binding var selectedPublication: CDPublication?

    /// Initial filter mode (for Unread sidebar item)
    var initialFilterMode: LibraryFilterMode = .all

    // MARK: - Environment

    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - Unified State

    @State private var publications: [CDPublication] = []
    @State private var multiSelection = Set<UUID>()
    @State private var isLoading = false
    @State private var error: Error?
    @State private var filterMode: LibraryFilterMode = .all
    @State private var provider: SmartSearchProvider?
    @StateObject private var dropHandler = FileDropHandler()

    /// Whether a background refresh is in progress (for subtle UI indicator)
    @State private var isBackgroundRefreshing = false

    // State for duplicate file alert
    @State private var showDuplicateAlert = false
    @State private var duplicateFilename = ""

    // MARK: - Computed Properties

    private var navigationTitle: String {
        switch source {
        case .library(let library):
            return filterMode == .unread ? "Unread" : library.displayName
        case .smartSearch(let smartSearch):
            return smartSearch.name
        }
    }

    private var currentLibrary: CDLibrary? {
        switch source {
        case .library(let library):
            return library
        case .smartSearch(let smartSearch):
            return smartSearch.resultCollection?.library ?? smartSearch.library
        }
    }

    private var listID: ListViewID {
        switch source {
        case .library(let library):
            return .library(library.id)
        case .smartSearch(let smartSearch):
            return .smartSearch(smartSearch.id)
        }
    }

    private var emptyMessage: String {
        switch source {
        case .library:
            return "No Publications"
        case .smartSearch(let smartSearch):
            return "No Results for \"\(smartSearch.query)\""
        }
    }

    private var emptyDescription: String {
        switch source {
        case .library:
            return "Add publications to your library or search online sources."
        case .smartSearch:
            return "Click refresh to search again."
        }
    }

    // MARK: - Body

    /// Check if we're viewing the Inbox library or an Inbox feed
    private var isInboxView: Bool {
        switch source {
        case .library(let library):
            return library.isInbox
        case .smartSearch(let smartSearch):
            // Inbox feeds also support triage shortcuts
            return smartSearch.feedsToInbox
        }
    }

    var body: some View {
        contentView
            .navigationTitle(navigationTitle)
            .toolbar { toolbarContent }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.init("a")) { handleArchiveKey() }
            .onKeyPress(.init("d")) { handleDismissKey() }
            .onKeyPress(.init("s")) { handleStarKey() }
            .task(id: source.id) {
                filterMode = initialFilterMode
                // Always show cached results immediately (instant)
                refreshPublicationsList()

                // For smart searches, queue high-priority background refresh if stale
                if case .smartSearch(let smartSearch) = source {
                    await queueBackgroundRefreshIfNeeded(smartSearch)
                }
            }
            .onChange(of: filterMode) { _, _ in
                refreshPublicationsList()
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
                    refreshPublicationsList()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectAllPublications)) { _ in
                selectAllPublications()
            }
            // Listen for background smart search refresh completion
            .onReceive(NotificationCenter.default.publisher(for: .smartSearchRefreshCompleted)) { notification in
                if case .smartSearch(let smartSearch) = source,
                   let completedID = notification.object as? UUID,
                   completedID == smartSearch.id {
                    logger.info("Background refresh completed for '\(smartSearch.name)', refreshing UI")
                    isBackgroundRefreshing = false
                    refreshPublicationsList()
                }
            }
            // Inbox triage notifications (for menu access)
            .onReceive(NotificationCenter.default.publisher(for: .inboxArchive)) { _ in
                if isInboxView && !multiSelection.isEmpty {
                    archiveSelectedToDefaultLibrary()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .inboxDismiss)) { _ in
                if isInboxView && !multiSelection.isEmpty {
                    dismissSelectedFromInbox()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .inboxToggleStar)) { _ in
                if isInboxView && !multiSelection.isEmpty {
                    toggleStarForSelected()
                }
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

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        if isLoading && publications.isEmpty {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            errorView(error)
        } else {
            listView
        }
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Retry") {
                Task { await refreshFromNetwork() }
            }
        }
    }

    private var listView: some View {
        PublicationListView(
            publications: publications,
            selection: $multiSelection,
            selectedPublication: $selectedPublication,
            library: currentLibrary,
            allLibraries: libraryManager.libraries,
            showImportButton: false,
            showSortMenu: true,
            emptyStateMessage: emptyMessage,
            emptyStateDescription: emptyDescription,
            listID: listID,
            disableUnreadFilter: false,
            onDelete: { ids in
                await libraryViewModel.delete(ids: ids)
                refreshPublicationsList()
            },
            onToggleRead: { publication in
                await libraryViewModel.toggleReadStatus(publication)
                refreshPublicationsList()
            },
            onCopy: { ids in
                await libraryViewModel.copyToClipboard(ids)
            },
            onCut: { ids in
                await libraryViewModel.cutToClipboard(ids)
                refreshPublicationsList()
            },
            onPaste: {
                try? await libraryViewModel.pasteFromClipboard()
                refreshPublicationsList()
            },
            onAddToLibrary: { ids, targetLibrary in
                await libraryViewModel.addToLibrary(ids, library: targetLibrary)
                refreshPublicationsList()
            },
            onAddToCollection: { ids, collection in
                await libraryViewModel.addToCollection(ids, collection: collection)
            },
            onRemoveFromAllCollections: { ids in
                await libraryViewModel.removeFromAllCollections(ids)
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
                        in: currentLibrary
                    )
                    // Refresh to show new attachments (paperclip indicator)
                    refreshPublicationsList()
                }
            },
            // Inbox triage callbacks (only when viewing Inbox or Inbox feeds)
            onArchiveToLibrary: isInboxView ? { ids, targetLibrary in
                await archiveToLibrary(ids: ids, library: targetLibrary)
            } : nil,
            onDismiss: isInboxView ? { ids in
                await dismissFromInbox(ids: ids)
            } : nil,
            onToggleStar: isInboxView ? { ids in
                await toggleStar(ids: ids)
            } : nil,
            onMuteAuthor: isInboxView ? { authorName in
                muteAuthor(authorName)
            } : nil,
            onMutePaper: isInboxView ? { publication in
                mutePaper(publication)
            } : nil
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Filter toggle - hide for Inbox (papers always stay visible after being read)
        if !isInboxView {
            ToolbarItem(placement: .automatic) {
                Picker("Filter", selection: $filterMode) {
                    Text("All").tag(LibraryFilterMode.all)
                    Text("Unread").tag(LibraryFilterMode.unread)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }

        // Refresh button (both sources) with background refresh indicator
        ToolbarItem(placement: .automatic) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if isBackgroundRefreshing {
                // Subtle indicator for background refresh (non-blocking)
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Refreshing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await refreshFromNetwork() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(source.isLibrary ? "Refresh library" : "Refresh search results")
            }
        }

        // Result count (both sources)
        ToolbarItem(placement: .automatic) {
            Text("\(publications.count) items")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data Refresh

    /// Refresh publications from data source (synchronous read)
    private func refreshPublicationsList() {
        switch source {
        case .library(let library):
            guard let nsSet = library.publications as? NSSet else {
                publications = []
                return
            }
            var result = nsSet.compactMap { $0 as? CDPublication }
                .filter { !$0.isDeleted && $0.managedObjectContext != nil }

            // Apply filter mode (skip for Inbox - papers should stay visible after being read)
            if filterMode == .unread && !library.isInbox {
                result = result.filter { !$0.isRead }
            }

            publications = result.sorted { $0.dateAdded > $1.dateAdded }
            logger.info("Refreshed library publications: \(self.publications.count) items")

        case .smartSearch(let smartSearch):
            guard let collection = smartSearch.resultCollection else {
                publications = []
                return
            }
            var result = (collection.publications ?? [])
                .filter { !$0.isDeleted && $0.managedObjectContext != nil }

            // Apply filter mode (skip for Inbox feeds - papers should stay visible after being read)
            if filterMode == .unread && !smartSearch.feedsToInbox {
                result = result.filter { !$0.isRead }
            }

            publications = result.sorted { $0.dateAdded > $1.dateAdded }
            logger.info("Refreshed smart search publications: \(self.publications.count) items")
        }
    }

    /// Refresh from network (async operation with loading state)
    private func refreshFromNetwork() async {
        isLoading = true
        error = nil

        switch source {
        case .library(let library):
            // TODO: Future enrichment protocol
            // For now, just refresh the list
            logger.info("Library refresh requested for: \(library.displayName)")
            try? await Task.sleep(for: .milliseconds(100))
            await MainActor.run {
                refreshPublicationsList()
            }

        case .smartSearch(let smartSearch):
            logger.info("Smart search refresh requested for: \(smartSearch.name)")
            let cachedProvider = await SmartSearchProviderCache.shared.getOrCreate(
                for: smartSearch,
                sourceManager: searchViewModel.sourceManager,
                repository: libraryViewModel.repository
            )
            provider = cachedProvider

            do {
                try await cachedProvider.refresh()
                await MainActor.run {
                    SmartSearchRepository.shared.markExecuted(smartSearch)
                    refreshPublicationsList()
                }
                logger.info("Smart search refresh completed")
            } catch {
                logger.error("Smart search refresh failed: \(error.localizedDescription)")
                self.error = error
            }
        }

        isLoading = false
    }

    /// Queue a background refresh for the smart search if needed (stale or empty).
    ///
    /// This does NOT block the UI - cached results are shown immediately while
    /// the refresh happens in the background via SmartSearchRefreshService.
    private func queueBackgroundRefreshIfNeeded(_ smartSearch: CDSmartSearch) async {
        // Get provider to check staleness
        let cachedProvider = await SmartSearchProviderCache.shared.getOrCreate(
            for: smartSearch,
            sourceManager: searchViewModel.sourceManager,
            repository: libraryViewModel.repository
        )
        provider = cachedProvider

        // Check if refresh is needed (stale or empty)
        let isStale = await cachedProvider.isStale
        let isEmpty = publications.isEmpty

        if isStale || isEmpty {
            logger.info("Smart search '\(smartSearch.name)' needs refresh (stale: \(isStale), empty: \(isEmpty))")

            // Check if already being refreshed
            let alreadyRefreshing = await SmartSearchRefreshService.shared.isRefreshing(smartSearch.id)
            let alreadyQueued = await SmartSearchRefreshService.shared.isQueued(smartSearch.id)

            if alreadyRefreshing || alreadyQueued {
                logger.debug("Smart search '\(smartSearch.name)' already refreshing/queued")
                isBackgroundRefreshing = alreadyRefreshing
            } else {
                // Queue with high priority since it's the currently visible smart search
                isBackgroundRefreshing = true
                await SmartSearchRefreshService.shared.queueRefresh(smartSearch, priority: .high)
                logger.info("Queued high-priority background refresh for '\(smartSearch.name)'")
            }
        } else {
            logger.debug("Smart search '\(smartSearch.name)' is fresh, no refresh needed")
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
            refreshPublicationsList()
        }
    }

    private func copySelectedPublications() async {
        guard !multiSelection.isEmpty else { return }
        await libraryViewModel.copyToClipboard(multiSelection)
    }

    private func cutSelectedPublications() async {
        guard !multiSelection.isEmpty else { return }
        await libraryViewModel.cutToClipboard(multiSelection)
        refreshPublicationsList()
    }

    // MARK: - Inbox Triage Handlers

    /// Handle 'A' key - archive selected to default library
    private func handleArchiveKey() -> KeyPress.Result {
        guard isInboxView, !multiSelection.isEmpty else { return .ignored }
        archiveSelectedToDefaultLibrary()
        return .handled
    }

    /// Handle 'D' key - dismiss selected from inbox
    private func handleDismissKey() -> KeyPress.Result {
        guard isInboxView, !multiSelection.isEmpty else { return .ignored }
        dismissSelectedFromInbox()
        return .handled
    }

    /// Handle 'S' key - toggle star on selected
    private func handleStarKey() -> KeyPress.Result {
        guard isInboxView, !multiSelection.isEmpty else { return .ignored }
        toggleStarForSelected()
        return .handled
    }

    /// Archive selected publications to the default library
    private func archiveSelectedToDefaultLibrary() {
        guard let defaultLibrary = libraryManager.libraries.first(where: { $0.isDefault && !$0.isInbox }) else {
            logger.warning("No default library available for archiving")
            return
        }

        let inboxManager = InboxManager.shared

        for uuid in multiSelection {
            if let publication = publications.first(where: { $0.id == uuid }) {
                inboxManager.archiveToLibrary(publication, library: defaultLibrary)
            }
        }

        multiSelection.removeAll()
        refreshPublicationsList()
        logger.info("Archived \(multiSelection.count) papers to \(defaultLibrary.displayName)")
    }

    /// Dismiss selected publications from inbox
    private func dismissSelectedFromInbox() {
        let inboxManager = InboxManager.shared

        for uuid in multiSelection {
            if let publication = publications.first(where: { $0.id == uuid }) {
                inboxManager.dismissFromInbox(publication)
            }
        }

        multiSelection.removeAll()
        refreshPublicationsList()
        logger.info("Dismissed \(multiSelection.count) papers from Inbox")
    }

    /// Toggle star status for selected publications
    private func toggleStarForSelected() {
        let context = PersistenceController.shared.viewContext

        for uuid in multiSelection {
            if let publication = publications.first(where: { $0.id == uuid }) {
                publication.isStarred.toggle()
            }
        }

        try? context.save()
        refreshPublicationsList()
        logger.info("Toggled star for \(multiSelection.count) papers")
    }

    // MARK: - Inbox Triage Callback Implementations

    /// Archive publications to a specific library (for context menu)
    private func archiveToLibrary(ids: Set<UUID>, library: CDLibrary) async {
        let inboxManager = InboxManager.shared

        for uuid in ids {
            if let publication = publications.first(where: { $0.id == uuid }) {
                inboxManager.archiveToLibrary(publication, library: library)
            }
        }

        multiSelection.removeAll()
        refreshPublicationsList()
        logger.info("Archived \(ids.count) papers to \(library.displayName)")
    }

    /// Dismiss publications from inbox (for context menu)
    private func dismissFromInbox(ids: Set<UUID>) async {
        let inboxManager = InboxManager.shared

        for uuid in ids {
            if let publication = publications.first(where: { $0.id == uuid }) {
                inboxManager.dismissFromInbox(publication)
            }
        }

        multiSelection.removeAll()
        refreshPublicationsList()
        logger.info("Dismissed \(ids.count) papers from Inbox")
    }

    /// Toggle star for publications (for context menu)
    private func toggleStar(ids: Set<UUID>) async {
        let context = PersistenceController.shared.viewContext

        for uuid in ids {
            if let publication = publications.first(where: { $0.id == uuid }) {
                publication.isStarred.toggle()
            }
        }

        try? context.save()
        refreshPublicationsList()
        logger.info("Toggled star for \(ids.count) papers")
    }

    /// Mute an author
    private func muteAuthor(_ authorName: String) {
        let inboxManager = InboxManager.shared
        inboxManager.mute(type: .author, value: authorName)
        logger.info("Muted author: \(authorName)")
    }

    /// Mute a paper (by DOI or bibcode)
    private func mutePaper(_ publication: CDPublication) {
        let inboxManager = InboxManager.shared

        // Prefer DOI, then bibcode (from original source ID for ADS papers)
        if let doi = publication.doi, !doi.isEmpty {
            inboxManager.mute(type: .doi, value: doi)
            logger.info("Muted paper by DOI: \(doi)")
        } else if let bibcode = publication.originalSourceID {
            // For ADS papers, originalSourceID contains the bibcode
            inboxManager.mute(type: .bibcode, value: bibcode)
            logger.info("Muted paper by bibcode: \(bibcode)")
        } else {
            logger.warning("Cannot mute paper - no DOI or bibcode available")
        }
    }

    // MARK: - Helpers

    private func openPDF(for publication: CDPublication) {
        if let linkedFiles = publication.linkedFiles,
           let pdfFile = linkedFiles.first(where: { $0.isPDF }),
           let libraryURL = currentLibrary?.folderURL {
            let pdfURL = libraryURL.appendingPathComponent(pdfFile.relativePath)
            #if os(macOS)
            NSWorkspace.shared.open(pdfURL)
            #endif
        }
    }
}

// MARK: - Preview

#Preview {
    let libraryManager = LibraryManager(persistenceController: .preview)
    if let library = libraryManager.libraries.first {
        NavigationStack {
            UnifiedPublicationListWrapper(
                source: .library(library),
                selectedPublication: .constant(nil)
            )
        }
        .environment(LibraryViewModel())
        .environment(SearchViewModel(
            sourceManager: SourceManager(),
            deduplicationService: DeduplicationService(),
            repository: PublicationRepository()
        ))
        .environment(libraryManager)
    } else {
        Text("No library available in preview")
    }
}
