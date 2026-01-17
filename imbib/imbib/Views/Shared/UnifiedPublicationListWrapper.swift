//
//  UnifiedPublicationListWrapper.swift
//  imbib
//
//  Created by Claude on 2026-01-05.
//

import SwiftUI
import PublicationManagerCore
import CoreData
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
/// - All/Unread filter (via Cmd+\\ keyboard shortcut)
/// - Refresh button (library = future enrichment, smart search = re-search)
/// - Loading/error states
/// - OSLog logging
struct UnifiedPublicationListWrapper: View {

    // MARK: - Properties

    let source: PublicationSource
    @Binding var selectedPublication: CDPublication?
    /// Multi-selection IDs for bulk operations
    @Binding var selectedPublicationIDs: Set<UUID>

    /// Initial filter mode (for Unread sidebar item)
    var initialFilterMode: LibraryFilterMode = .all

    /// Called when "Download PDFs" is requested for selected publications
    var onDownloadPDFs: ((Set<UUID>) -> Void)?

    // MARK: - Environment

    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - Unified State

    @State private var publications: [CDPublication] = []
    // selectedPublicationIDs is now a binding: selectedPublicationIDs
    @State private var isLoading = false
    @State private var error: Error?
    @State private var filterMode: LibraryFilterMode = .all
    @State private var filterScope: FilterScope = .current
    @State private var provider: SmartSearchProvider?
    @StateObject private var dropHandler = FileDropHandler()

    /// Whether a background refresh is in progress (for subtle UI indicator)
    @State private var isBackgroundRefreshing = false

    // State for duplicate file alert
    @State private var showDuplicateAlert = false
    @State private var duplicateFilename = ""

    /// Snapshot of publication IDs visible when unread filter was applied.
    /// Enables Apple Mail behavior: items stay visible after being marked as read
    /// until the user navigates away or explicitly refreshes.
    @State private var unreadFilterSnapshot: Set<UUID>?

    // MARK: - Computed Properties

    /// Check if the source (library or smart search) is still valid (not deleted)
    private var isSourceValid: Bool {
        switch source {
        case .library(let library):
            return library.managedObjectContext != nil && !library.isDeleted
        case .smartSearch(let smartSearch):
            return smartSearch.managedObjectContext != nil && !smartSearch.isDeleted
        }
    }

    private var navigationTitle: String {
        switch source {
        case .library(let library):
            guard library.managedObjectContext != nil else { return "" }
            return filterMode == .unread ? "Unread" : library.displayName
        case .smartSearch(let smartSearch):
            guard smartSearch.managedObjectContext != nil else { return "" }
            return smartSearch.name
        }
    }

    private var currentLibrary: CDLibrary? {
        guard isSourceValid else { return nil }
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
        guard isSourceValid else { return false }
        switch source {
        case .library(let library):
            return library.isInbox
        case .smartSearch(let smartSearch):
            // Inbox feeds also support triage shortcuts
            return smartSearch.feedsToInbox
        }
    }

    var body: some View {
        // Guard against deleted source - return empty view to prevent crash
        if !isSourceValid {
            Color.clear
        } else {
            bodyContent
        }
    }

    /// Main body content separated to help compiler type-checking
    @ViewBuilder
    private var bodyContent: some View {
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
                filterScope = .current  // Reset scope on navigation
                unreadFilterSnapshot = nil  // Reset snapshot on navigation

                // If starting with unread filter, capture snapshot after loading data
                if initialFilterMode == .unread {
                    refreshPublicationsList()
                    unreadFilterSnapshot = captureUnreadSnapshot()
                } else {
                    refreshPublicationsList()
                }

                if case .smartSearch(let smartSearch) = source {
                    await queueBackgroundRefreshIfNeeded(smartSearch)
                }
            }
            .onChange(of: filterMode) { _, newMode in
                // Capture snapshot when switching TO unread filter (Apple Mail behavior)
                if newMode == .unread {
                    unreadFilterSnapshot = captureUnreadSnapshot()
                } else {
                    unreadFilterSnapshot = nil
                }
                refreshPublicationsList()
            }
            .onChange(of: filterScope) { _, _ in
                refreshPublicationsList()
            }
            .modifier(NotificationModifiers(
                onToggleReadStatus: toggleReadStatusForSelected,
                onCopyPublications: { Task { await copySelectedPublications() } },
                onCutPublications: { Task { await cutSelectedPublications() } },
                onPastePublications: {
                    Task {
                        try? await libraryViewModel.pasteFromClipboard()
                        refreshPublicationsList()
                    }
                },
                onSelectAll: selectAllPublications
            ))
            .modifier(SmartSearchRefreshModifier(
                source: source,
                onRefreshComplete: { smartSearchName in
                    logger.info("Background refresh completed for '\(smartSearchName)', refreshing UI")
                    isBackgroundRefreshing = false
                    refreshPublicationsList()
                }
            ))
            .modifier(InboxTriageModifier(
                isInboxView: isInboxView,
                hasSelection: !selectedPublicationIDs.isEmpty,
                onArchive: archiveSelectedToDefaultLibrary,
                onDismiss: dismissSelectedFromInbox,
                onToggleStar: toggleStarForSelected
            ))
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
            selection: $selectedPublicationIDs,
            selectedPublication: $selectedPublication,
            library: currentLibrary,
            allLibraries: libraryManager.libraries,
            showImportButton: false,
            showSortMenu: true,
            emptyStateMessage: emptyMessage,
            emptyStateDescription: emptyDescription,
            listID: listID,
            disableUnreadFilter: false,
            filterScope: $filterScope,
            onDelete: { ids in
                // Remove from local state FIRST to prevent SwiftUI from rendering deleted objects
                publications.removeAll { ids.contains($0.id) }
                // Clear selection for deleted items
                selectedPublicationIDs.subtract(ids)
                // Then delete from Core Data
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
            onDownloadPDFs: onDownloadPDFs,
            // Archive callback - available for all views (moves papers to target library)
            onArchiveToLibrary: { ids, targetLibrary in
                await archiveToLibrary(ids: ids, targetLibrary: targetLibrary)
            },
            // Inbox-specific triage callbacks
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
            } : nil,
            // Refresh callback (shown as small button in list header)
            onRefresh: {
                await refreshFromNetwork()
            },
            isRefreshing: isLoading || isBackgroundRefreshing
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Toolbar is now mostly empty - refresh moved to inline toolbar in list view
        // EmptyView is needed for the ToolbarContentBuilder
        ToolbarItem(placement: .automatic) {
            EmptyView()
        }
    }

    // MARK: - Data Refresh

    /// Refresh publications from data source (synchronous read)
    private func refreshPublicationsList() {
        // Handle cross-scope fetching
        switch filterScope {
        case .current:
            refreshCurrentScopePublications()
        case .allLibraries, .inbox, .everything:
            publications = fetchPublications(for: filterScope)
            logger.info("Refreshed \(filterScope.rawValue): \(self.publications.count) items")
        }
    }

    /// Refresh publications for the current source (library or smart search)
    ///
    /// Simplified: All papers in a library are in `library.publications`.
    /// No merge logic needed - smart search results are added to the library relationship.
    private func refreshCurrentScopePublications() {
        guard isSourceValid else {
            publications = []
            return
        }
        switch source {
        case .library(let library):
            // Simple: just use the library's publications relationship
            var result = (library.publications ?? [])
                .filter { !$0.isDeleted && $0.managedObjectContext != nil }

            // Apply filter mode with Apple Mail behavior:
            // Items stay visible after being read if they were visible when filter was applied.
            // Skip for Inbox - papers should stay visible after being read regardless.
            if filterMode == .unread && !library.isInbox {
                if let snapshot = unreadFilterSnapshot {
                    // Keep items in snapshot visible (Apple Mail behavior)
                    result = result.filter { !$0.isRead || snapshot.contains($0.id) }
                } else {
                    // No snapshot - strict filter (fresh application)
                    result = result.filter { !$0.isRead }
                }
            }

            publications = result.sorted { $0.dateAdded > $1.dateAdded }
            logger.info("Refreshed library: \(self.publications.count) items")

        case .smartSearch(let smartSearch):
            // Show result collection (organizational view within the library)
            guard let collection = smartSearch.resultCollection else {
                publications = []
                return
            }
            var result = (collection.publications ?? [])
                .filter { !$0.isDeleted && $0.managedObjectContext != nil }

            // Apply filter mode with Apple Mail behavior.
            // Skip for Inbox feeds - papers should stay visible after being read regardless.
            if filterMode == .unread && !smartSearch.feedsToInbox {
                if let snapshot = unreadFilterSnapshot {
                    // Keep items in snapshot visible (Apple Mail behavior)
                    result = result.filter { !$0.isRead || snapshot.contains($0.id) }
                } else {
                    // No snapshot - strict filter (fresh application)
                    result = result.filter { !$0.isRead }
                }
            }

            publications = result.sorted { $0.dateAdded > $1.dateAdded }
            logger.info("Refreshed smart search: \(self.publications.count) items")
        }
    }

    /// Fetch publications for a given scope.
    ///
    /// Unified method replaces fetchAllLibrariesPublications, fetchInboxPublications, fetchEverythingPublications.
    /// - Parameter scope: Which libraries to include
    /// - Returns: Array of publications sorted by dateAdded (newest first)
    private func fetchPublications(for scope: FilterScope) -> [CDPublication] {
        // Determine which libraries to include based on scope
        let libraries: [CDLibrary] = switch scope {
        case .current:
            // For current scope, get from source (handled separately in refreshCurrentScopePublications)
            if case .library(let lib) = source { [lib] } else { [] }
        case .allLibraries:
            libraryManager.libraries.filter { !$0.isInbox }
        case .inbox:
            libraryManager.libraries.filter { $0.isInbox }
        case .everything:
            libraryManager.libraries
        }

        // Collect all publications from the selected libraries
        var allPublications = Set<CDPublication>()
        for library in libraries {
            let pubs = (library.publications ?? [])
                .filter { !$0.isDeleted && $0.managedObjectContext != nil }
            allPublications.formUnion(pubs)
        }

        return Array(allPublications).sorted { $0.dateAdded > $1.dateAdded }
    }

    /// Refresh from network (async operation with loading state)
    private func refreshFromNetwork() async {
        guard isSourceValid else {
            isLoading = false
            return
        }

        // Reset snapshot on explicit refresh (Apple Mail behavior)
        unreadFilterSnapshot = nil

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

            // Route group feeds to GroupFeedRefreshService for staggered per-author searches
            if smartSearch.isGroupFeed {
                logger.info("Routing group feed '\(smartSearch.name)' to GroupFeedRefreshService")
                do {
                    _ = try await GroupFeedRefreshService.shared.refreshGroupFeed(smartSearch)
                    await MainActor.run {
                        refreshPublicationsList()
                    }
                    logger.info("Group feed refresh completed for '\(smartSearch.name)'")
                } catch {
                    logger.error("Group feed refresh failed: \(error.localizedDescription)")
                    self.error = error
                }
            } else {
                // Regular smart search - use provider
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
        }

        isLoading = false
    }

    /// Queue a background refresh for the smart search if needed (stale or empty).
    ///
    /// This does NOT block the UI - cached results are shown immediately while
    /// the refresh happens in the background via SmartSearchRefreshService.
    private func queueBackgroundRefreshIfNeeded(_ smartSearch: CDSmartSearch) async {
        // Guard against deleted smart search
        guard smartSearch.managedObjectContext != nil, !smartSearch.isDeleted else { return }

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
        selectedPublicationIDs = Set(publications.map { $0.id })
    }

    private func toggleReadStatusForSelected() {
        guard !selectedPublicationIDs.isEmpty else { return }

        Task {
            // Apple Mail behavior: if ANY are unread, mark ALL as read
            // If ALL are read, mark ALL as unread
            await libraryViewModel.smartToggleReadStatus(selectedPublicationIDs)
            refreshPublicationsList()
        }
    }

    private func copySelectedPublications() async {
        guard !selectedPublicationIDs.isEmpty else { return }
        await libraryViewModel.copyToClipboard(selectedPublicationIDs)
    }

    private func cutSelectedPublications() async {
        guard !selectedPublicationIDs.isEmpty else { return }
        await libraryViewModel.cutToClipboard(selectedPublicationIDs)
        refreshPublicationsList()
    }

    // MARK: - Text Field Focus Detection

    /// Check if a text field is currently focused (to avoid intercepting text input)
    private func isTextFieldFocused() -> Bool {
        #if os(macOS)
        guard let window = NSApp.keyWindow,
              let firstResponder = window.firstResponder else {
            return false
        }
        // NSTextView is used by TextEditor, TextField, and other text controls
        return firstResponder is NSTextView
        #else
        return false  // iOS uses different focus management
        #endif
    }

    // MARK: - Inbox Triage Handlers

    /// Handle 'A' key - archive selected to default library
    private func handleArchiveKey() -> KeyPress.Result {
        guard !isTextFieldFocused(), isInboxView, !selectedPublicationIDs.isEmpty else { return .ignored }
        archiveSelectedToDefaultLibrary()
        return .handled
    }

    /// Handle 'D' key - dismiss selected from inbox
    private func handleDismissKey() -> KeyPress.Result {
        guard !isTextFieldFocused(), isInboxView, !selectedPublicationIDs.isEmpty else { return .ignored }
        dismissSelectedFromInbox()
        return .handled
    }

    /// Handle 'S' key - toggle star on selected (works everywhere, not just inbox)
    private func handleStarKey() -> KeyPress.Result {
        guard !isTextFieldFocused(), !selectedPublicationIDs.isEmpty else { return .ignored }
        toggleStarForSelected()
        return .handled
    }

    /// Archive selected publications to the Archive library (created on first use if needed)
    private func archiveSelectedToDefaultLibrary() {
        // Use the Archive library (created automatically on first use)
        let archiveLibrary = libraryManager.getOrCreateArchiveLibrary()

        let ids = selectedPublicationIDs
        Task {
            await archiveToLibrary(ids: ids, targetLibrary: archiveLibrary)
        }
    }

    /// Dismiss selected publications from inbox (moves to Dismissed library, not delete)
    private func dismissSelectedFromInbox() {
        let inboxManager = InboxManager.shared
        let dismissedLibrary = libraryManager.getOrCreateDismissedLibrary()

        for uuid in selectedPublicationIDs {
            if let publication = publications.first(where: { $0.id == uuid }) {
                // Track dismissal to prevent paper from reappearing in feeds
                inboxManager.trackDismissal(publication)

                // Remove from Inbox library
                if let inbox = inboxManager.inboxLibrary {
                    publication.removeFromLibrary(inbox)
                }

                // Also remove from smart search result collection if viewing a feed
                if case .smartSearch(let smartSearch) = source,
                   let resultCollection = smartSearch.resultCollection {
                    publication.removeFromCollection(resultCollection)
                }

                // Add to Dismissed library (NOT delete)
                publication.addToLibrary(dismissedLibrary)
            }
        }

        // Save changes
        PersistenceController.shared.save()
        inboxManager.updateUnreadCount()

        let count = selectedPublicationIDs.count
        selectedPublicationIDs.removeAll()
        refreshPublicationsList()
        logger.info("Dismissed \(count) papers from Inbox to Dismissed library")
    }

    /// Toggle star status for selected publications
    private func toggleStarForSelected() {
        let context = PersistenceController.shared.viewContext

        for uuid in selectedPublicationIDs {
            if let publication = publications.first(where: { $0.id == uuid }) {
                publication.isStarred.toggle()
            }
        }

        try? context.save()
        refreshPublicationsList()
        logger.info("Toggled star for \(selectedPublicationIDs.count) papers")
    }

    // MARK: - Archive Implementation

    /// Archive publications to a target library (adds to target AND removes from current).
    /// Selects the next paper in the list after archiving.
    private func archiveToLibrary(ids: Set<UUID>, targetLibrary: CDLibrary) async {
        // Find next paper to select before removing current selection
        let nextPaperID = findNextPaperAfter(ids: ids)

        // For Inbox, use InboxManager which handles special Inbox logic
        if isInboxView {
            let inboxManager = InboxManager.shared
            for uuid in ids {
                if let publication = publications.first(where: { $0.id == uuid }) {
                    inboxManager.archiveToLibrary(publication, library: targetLibrary)
                }
            }
            logger.info("Archived \(ids.count) papers from Inbox to \(targetLibrary.displayName)")
        } else if case .smartSearch(let smartSearch) = source {
            // For smart searches: add to target library, remove from result collection
            await libraryViewModel.addToLibrary(ids, library: targetLibrary)

            // Remove from smart search result collection
            if let resultCollection = smartSearch.resultCollection {
                let pubs = ids.compactMap { id in publications.first(where: { $0.id == id }) }
                for pub in pubs {
                    pub.removeFromCollection(resultCollection)
                }
                try? PersistenceController.shared.viewContext.save()
            }
            logger.info("Archived \(ids.count) papers from smart search '\(smartSearch.name)' to \(targetLibrary.displayName)")
        } else if let sourceLibrary = currentLibrary {
            // For regular libraries: add to target, remove from source
            await libraryViewModel.addToLibrary(ids, library: targetLibrary)
            await libraryViewModel.removeFromLibrary(ids, library: sourceLibrary)
            logger.info("Archived \(ids.count) papers from \(sourceLibrary.displayName) to \(targetLibrary.displayName)")
        } else {
            logger.warning("Cannot archive - no source library")
            return
        }

        // Select next paper (or clear if none left)
        if let nextID = nextPaperID,
           let nextPub = publications.first(where: { $0.id == nextID }) {
            selectedPublicationIDs = [nextID]
            selectedPublication = nextPub
        } else {
            selectedPublicationIDs.removeAll()
            selectedPublication = nil
        }

        refreshPublicationsList()
    }

    /// Find the next paper ID to select after removing the given IDs.
    /// Returns the paper immediately after the last selected one, or the one before if at end.
    private func findNextPaperAfter(ids: Set<UUID>) -> UUID? {
        // Find indices of selected papers
        let selectedIndices = publications.enumerated()
            .filter { ids.contains($0.element.id) }
            .map { $0.offset }
            .sorted()

        guard let lastIndex = selectedIndices.last else { return nil }

        // Try next paper after the last selected
        let nextIndex = lastIndex + 1
        if nextIndex < publications.count && !ids.contains(publications[nextIndex].id) {
            return publications[nextIndex].id
        }

        // Try paper before the first selected
        if let firstIndex = selectedIndices.first, firstIndex > 0 {
            let prevIndex = firstIndex - 1
            if !ids.contains(publications[prevIndex].id) {
                return publications[prevIndex].id
            }
        }

        // Find any remaining paper not in the selection
        for pub in publications where !ids.contains(pub.id) {
            return pub.id
        }

        return nil
    }

    // MARK: - Inbox Triage Callback Implementations

    /// Dismiss publications from inbox (for context menu) - moves to Dismissed library, not delete
    private func dismissFromInbox(ids: Set<UUID>) async {
        let inboxManager = InboxManager.shared
        let dismissedLibrary = libraryManager.getOrCreateDismissedLibrary()

        for uuid in ids {
            if let publication = publications.first(where: { $0.id == uuid }) {
                // Track dismissal to prevent paper from reappearing in feeds
                inboxManager.trackDismissal(publication)

                // Remove from Inbox library
                if let inbox = inboxManager.inboxLibrary {
                    publication.removeFromLibrary(inbox)
                }

                // Also remove from smart search result collection if viewing a feed
                if case .smartSearch(let smartSearch) = source,
                   let resultCollection = smartSearch.resultCollection {
                    publication.removeFromCollection(resultCollection)
                }

                // Add to Dismissed library (NOT delete)
                publication.addToLibrary(dismissedLibrary)
            }
        }

        // Save changes
        PersistenceController.shared.save()
        inboxManager.updateUnreadCount()

        selectedPublicationIDs.removeAll()
        refreshPublicationsList()
        logger.info("Dismissed \(ids.count) papers from Inbox to Dismissed library")
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

    /// Capture current unread publication IDs for Apple Mail-style snapshot.
    /// Items in the snapshot stay visible even after being marked as read.
    private func captureUnreadSnapshot() -> Set<UUID> {
        guard isSourceValid else { return [] }
        switch source {
        case .library(let library):
            let unread = (library.publications ?? [])
                .filter { !$0.isDeleted && $0.managedObjectContext != nil && !$0.isRead }
            return Set(unread.map { $0.id })
        case .smartSearch(let smartSearch):
            guard let collection = smartSearch.resultCollection else { return [] }
            let unread = (collection.publications ?? [])
                .filter { !$0.isDeleted && $0.managedObjectContext != nil && !$0.isRead }
            return Set(unread.map { $0.id })
        }
    }
}

// MARK: - View Modifiers (extracted to help compiler type-checking)

/// Handles notification subscriptions for clipboard and selection operations
private struct NotificationModifiers: ViewModifier {
    let onToggleReadStatus: () -> Void
    let onCopyPublications: () -> Void
    let onCutPublications: () -> Void
    let onPastePublications: () -> Void
    let onSelectAll: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .toggleReadStatus)) { _ in
                onToggleReadStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: .copyPublications)) { _ in
                onCopyPublications()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cutPublications)) { _ in
                onCutPublications()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pastePublications)) { _ in
                onPastePublications()
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectAllPublications)) { _ in
                onSelectAll()
            }
    }
}

/// Handles smart search refresh completion notifications
private struct SmartSearchRefreshModifier: ViewModifier {
    let source: PublicationSource
    let onRefreshComplete: (String) -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .smartSearchRefreshCompleted)) { notification in
                if case .smartSearch(let smartSearch) = source,
                   let completedID = notification.object as? UUID,
                   completedID == smartSearch.id {
                    onRefreshComplete(smartSearch.name)
                }
            }
    }
}

/// Handles inbox triage notification subscriptions
private struct InboxTriageModifier: ViewModifier {
    let isInboxView: Bool
    let hasSelection: Bool
    let onArchive: () -> Void
    let onDismiss: () -> Void
    let onToggleStar: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .inboxArchive)) { _ in
                if isInboxView && hasSelection {
                    onArchive()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .inboxDismiss)) { _ in
                if isInboxView && hasSelection {
                    onDismiss()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .inboxToggleStar)) { _ in
                if isInboxView && hasSelection {
                    onToggleStar()
                }
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
                selectedPublication: .constant(nil),
                selectedPublicationIDs: .constant([])
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
