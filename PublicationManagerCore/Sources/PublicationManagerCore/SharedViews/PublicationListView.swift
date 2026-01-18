//
//  PublicationListView.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-05.
//

import SwiftUI
import OSLog

// MARK: - Filter Scope

/// Scope for filtering publications in the search field
public enum FilterScope: String, CaseIterable, Identifiable {
    case current = "Current"
    case allLibraries = "All Libraries"
    case inbox = "Inbox"
    case everything = "Everything"

    public var id: String { rawValue }
}

// MARK: - Filter Cache

/// Cache key for memoizing filtered row data
private struct FilterCacheKey: Equatable {
    let rowDataVersion: Int
    let showUnreadOnly: Bool
    let disableUnreadFilter: Bool
    let searchQuery: String
    let sortOrder: LibrarySortOrder
    let sortAscending: Bool  // Direction toggle
    let searchInPDFs: Bool
    let pdfMatchCount: Int  // Track PDF matches by count (Set isn't Equatable for hash)
}

/// Memoization cache for filtered row data.
/// Uses a class to avoid @State changes that would trigger re-renders.
private final class FilteredRowDataCache: ObservableObject {
    private var cachedKey: FilterCacheKey?
    private var cachedResult: [PublicationRowData]?

    func getCached(for key: FilterCacheKey) -> [PublicationRowData]? {
        guard cachedKey == key else { return nil }
        return cachedResult
    }

    func cache(_ result: [PublicationRowData], for key: FilterCacheKey) {
        cachedKey = key
        cachedResult = result
    }

    func invalidate() {
        cachedKey = nil
        cachedResult = nil
    }
}

/// Unified publication list view used by Library, Smart Search, and Ad-hoc Search.
///
/// Per ADR-016, all papers are CDPublication entities and should have identical
/// capabilities regardless of where they're viewed. This component provides:
/// - Mail-style publication rows
/// - Inline toolbar (search, filter, import, sort)
/// - Full context menu
/// - Keyboard delete support
/// - Multi-selection
/// - State persistence (selection, sort order, filters) via ListViewStateStore
///
/// ## Thread Safety
///
/// This view converts `[CDPublication]` to `[PublicationRowData]` (value types)
/// before rendering. This eliminates crashes during bulk deletion where Core Data
/// objects become invalid while SwiftUI is still rendering.
public struct PublicationListView: View {

    // MARK: - Properties

    /// All publications to display (before filtering/sorting)
    public let publications: [CDPublication]

    /// Multi-selection binding
    @Binding public var selection: Set<UUID>

    /// Single-selection binding (updated when selection changes)
    @Binding public var selectedPublication: CDPublication?

    /// Library for context menu operations (Add to Library, Add to Collection)
    public var library: CDLibrary?

    /// All available libraries for "Add to Library" menu
    public var allLibraries: [CDLibrary] = []

    /// Whether to show the import button
    public var showImportButton: Bool = true

    /// Whether to show the sort menu
    public var showSortMenu: Bool = true

    /// Custom empty state message
    public var emptyStateMessage: String = "No publications found."

    /// Custom empty state description
    public var emptyStateDescription: String = "Import a BibTeX file or search online sources to add publications."

    /// Identifier for state persistence (nil = no persistence)
    public var listID: ListViewID?

    /// When true, the unread filter is disabled and all papers are shown.
    /// Used for Inbox view where papers should remain visible after being marked as read.
    public var disableUnreadFilter: Bool = false

    /// Whether this list is showing Inbox items (enables Inbox-specific swipe actions)
    public var isInInbox: Bool = false

    /// Binding to the filter scope (controls which publications are searched)
    @Binding public var filterScope: FilterScope

    // MARK: - Callbacks

    /// Called when delete is requested (via context menu or keyboard)
    public var onDelete: ((Set<UUID>) async -> Void)?

    /// Called when toggle read is requested
    public var onToggleRead: ((CDPublication) async -> Void)?

    /// Called when copy is requested
    public var onCopy: ((Set<UUID>) async -> Void)?

    /// Called when cut is requested
    public var onCut: ((Set<UUID>) async -> Void)?

    /// Called when paste is requested
    public var onPaste: (() async -> Void)?

    /// Called when add to library is requested (publications can belong to multiple libraries)
    public var onAddToLibrary: ((Set<UUID>, CDLibrary) async -> Void)?

    /// Called when add to collection is requested
    public var onAddToCollection: ((Set<UUID>, CDCollection) async -> Void)?

    /// Called when remove from all collections is requested ("All Publications")
    public var onRemoveFromAllCollections: ((Set<UUID>) async -> Void)?

    /// Called when import is requested (import button clicked)
    public var onImport: (() -> Void)?

    /// Called when open PDF is requested
    public var onOpenPDF: ((CDPublication) -> Void)?

    /// Called when files are dropped onto a publication row
    public var onFileDrop: ((CDPublication, [NSItemProvider]) -> Void)?

    /// Called when "Download PDFs" is requested for selected publications
    public var onDownloadPDFs: ((Set<UUID>) -> Void)?

    // MARK: - Inbox Triage Callbacks

    /// Called when archive to library is requested (Inbox: adds to library AND removes from Inbox)
    public var onArchiveToLibrary: ((Set<UUID>, CDLibrary) async -> Void)?

    /// Called when dismiss is requested (Inbox: remove from Inbox)
    public var onDismiss: ((Set<UUID>) async -> Void)?

    /// Called when toggle star is requested
    public var onToggleStar: ((Set<UUID>) async -> Void)?

    /// Called when mute author is requested
    public var onMuteAuthor: ((String) -> Void)?

    /// Called when mute paper is requested (by DOI or bibcode)
    public var onMutePaper: ((CDPublication) -> Void)?

    /// Called when a category chip is tapped (e.g., to search for that category)
    public var onCategoryTap: ((String) -> Void)?

    /// Called when refresh is requested (for smart searches and feeds)
    public var onRefresh: (() async -> Void)?

    // MARK: - Enhanced Context Menu Callbacks

    /// Called when Open in Browser is requested (arXiv, ADS, DOI)
    public var onOpenInBrowser: ((CDPublication, BrowserDestination) -> Void)?

    /// Called when Download PDF is requested (for papers without PDF)
    public var onDownloadPDF: ((CDPublication) -> Void)?

    /// Called when View/Edit BibTeX is requested
    public var onViewEditBibTeX: ((CDPublication) -> Void)?

    /// Called when Share (system share sheet) is requested
    public var onShare: ((CDPublication) -> Void)?

    /// Called when Share by Email is requested (with PDF + BibTeX attachments)
    public var onShareByEmail: ((CDPublication) -> Void)?

    /// Called when Explore References is requested
    public var onExploreReferences: ((CDPublication) -> Void)?

    /// Called when Explore Citations is requested
    public var onExploreCitations: ((CDPublication) -> Void)?

    /// Called when Explore Similar Papers is requested
    public var onExploreSimilar: ((CDPublication) -> Void)?

    /// Whether a refresh is in progress (shows loading indicator)
    public var isRefreshing: Bool = false

    // MARK: - Internal State

    @State private var searchQuery: String = ""
    @State private var showUnreadOnly: Bool = false
    @State private var sortOrder: LibrarySortOrder = .dateAdded
    @State private var sortAscending: Bool = false  // Toggle by clicking same sort option again
    @State private var hasLoadedState: Bool = false

    /// Whether to include PDF content in search (uses Spotlight on macOS, PDFKit on iOS)
    @State private var searchInPDFs: Bool = false

    /// Publication IDs that match the PDF content search (async populated)
    @State private var pdfSearchMatches: Set<UUID> = []

    /// Task for ongoing PDF search (cancelled when query changes)
    @State private var pdfSearchTask: Task<Void, Never>?

    /// Whether PDF search is in progress
    @State private var isPDFSearching: Bool = false

    /// Cached row data - rebuilt when publications change
    @State private var rowDataCache: [UUID: PublicationRowData] = [:]

    /// Cached publication lookup - O(1) instead of O(n) linear scans
    @State private var publicationsByID: [UUID: CDPublication] = [:]

    /// ID of row currently targeted by file drop
    @State private var dropTargetedRowID: UUID?

    /// List view settings for row customization
    /// Uses synchronous load to avoid first-render with defaults
    @State private var listViewSettings: ListViewSettings = ListViewSettingsStore.loadSettingsSync()

    /// Debounce task for saving state (prevents rapid saves on fast selection changes)
    @State private var saveStateTask: Task<Void, Never>?

    /// Memoization cache for filtered row data (class reference to avoid state changes)
    @StateObject private var filterCache = FilteredRowDataCache()

    /// Scroll proxy for programmatic scrolling to selection (set by ScrollViewReader)
    @State private var scrollProxy: ScrollViewProxy?

    /// Theme colors for list background tint
    @Environment(\.themeColors) private var theme

    // MARK: - Computed Properties

    /// Static collections (non-smart) from the current library, for "Add to Collection" menus
    private var staticCollections: [CDCollection] {
        guard let collections = library?.collections as? Set<CDCollection> else { return [] }
        return collections.filter { !$0.isSmartCollection && !$0.isSmartSearchResults }
            .sorted { $0.name < $1.name }
    }

    /// Filtered and sorted row data - memoized to avoid repeated computation
    private var filteredRowData: [PublicationRowData] {
        // Create cache key from all inputs
        let cacheKey = FilterCacheKey(
            rowDataVersion: rowDataCache.count,
            showUnreadOnly: showUnreadOnly,
            disableUnreadFilter: disableUnreadFilter,
            searchQuery: searchQuery,
            sortOrder: sortOrder,
            sortAscending: sortAscending,
            searchInPDFs: searchInPDFs,
            pdfMatchCount: pdfSearchMatches.count
        )

        // Return cached result if inputs haven't changed
        if let cached = filterCache.getCached(for: cacheKey) {
            return cached
        }

        // Compute and cache
        let start = CFAbsoluteTimeGetCurrent()
        var result = Array(rowDataCache.values)

        // Filter by unread (skip for Inbox where disableUnreadFilter is true)
        if showUnreadOnly && !disableUnreadFilter {
            result = result.filter { !$0.isRead }
        }

        // Filter by search query (metadata + optionally PDF content)
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter { rowData in
                // Always check metadata fields
                let matchesMetadata = rowData.title.lowercased().contains(query) ||
                    rowData.authorString.lowercased().contains(query) ||
                    rowData.citeKey.lowercased().contains(query)

                // If PDF search is enabled, also include PDF content matches
                if searchInPDFs && pdfSearchMatches.contains(rowData.id) {
                    return true
                }

                return matchesMetadata
            }
        }

        // Sort using data already in PublicationRowData - no CDPublication lookups needed
        // Each case returns the "default direction" comparison, then we flip if sortAscending differs
        let sorted = result.sorted { lhs, rhs in
            let defaultComparison: Bool = switch sortOrder {
            case .dateAdded:
                lhs.dateAdded > rhs.dateAdded  // Default descending (newest first)
            case .dateModified:
                lhs.dateModified > rhs.dateModified  // Default descending (newest first)
            case .title:
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending  // Default ascending (A-Z)
            case .year:
                (lhs.year ?? 0) > (rhs.year ?? 0)  // Default descending (newest first)
            case .citeKey:
                lhs.citeKey.localizedCaseInsensitiveCompare(rhs.citeKey) == .orderedAscending  // Default ascending (A-Z)
            case .citationCount:
                lhs.citationCount > rhs.citationCount  // Default descending (highest first)
            }
            // Flip result if sortAscending differs from the field's default direction
            return sortAscending == sortOrder.defaultAscending ? defaultComparison : !defaultComparison
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        Logger.performance.infoCapture("⏱ filteredRowData: \(String(format: "%.1f", elapsed))ms (\(sorted.count) items)", category: "performance")

        filterCache.cache(sorted, for: cacheKey)
        return sorted
    }

    // MARK: - Initialization

    public init(
        publications: [CDPublication],
        selection: Binding<Set<UUID>>,
        selectedPublication: Binding<CDPublication?>,
        library: CDLibrary? = nil,
        allLibraries: [CDLibrary] = [],
        showImportButton: Bool = true,
        showSortMenu: Bool = true,
        emptyStateMessage: String = "No publications found.",
        emptyStateDescription: String = "Import a BibTeX file or search online sources to add publications.",
        listID: ListViewID? = nil,
        disableUnreadFilter: Bool = false,
        isInInbox: Bool = false,
        filterScope: Binding<FilterScope>,
        onDelete: ((Set<UUID>) async -> Void)? = nil,
        onToggleRead: ((CDPublication) async -> Void)? = nil,
        onCopy: ((Set<UUID>) async -> Void)? = nil,
        onCut: ((Set<UUID>) async -> Void)? = nil,
        onPaste: (() async -> Void)? = nil,
        onAddToLibrary: ((Set<UUID>, CDLibrary) async -> Void)? = nil,
        onAddToCollection: ((Set<UUID>, CDCollection) async -> Void)? = nil,
        onRemoveFromAllCollections: ((Set<UUID>) async -> Void)? = nil,
        onImport: (() -> Void)? = nil,
        onOpenPDF: ((CDPublication) -> Void)? = nil,
        onFileDrop: ((CDPublication, [NSItemProvider]) -> Void)? = nil,
        onDownloadPDFs: ((Set<UUID>) -> Void)? = nil,
        // Inbox triage callbacks
        onArchiveToLibrary: ((Set<UUID>, CDLibrary) async -> Void)? = nil,
        onDismiss: ((Set<UUID>) async -> Void)? = nil,
        onToggleStar: ((Set<UUID>) async -> Void)? = nil,
        onMuteAuthor: ((String) -> Void)? = nil,
        onMutePaper: ((CDPublication) -> Void)? = nil,
        // Category tap callback
        onCategoryTap: ((String) -> Void)? = nil,
        // Refresh callback and state
        onRefresh: (() async -> Void)? = nil,
        isRefreshing: Bool = false,
        // Enhanced context menu callbacks
        onOpenInBrowser: ((CDPublication, BrowserDestination) -> Void)? = nil,
        onDownloadPDF: ((CDPublication) -> Void)? = nil,
        onViewEditBibTeX: ((CDPublication) -> Void)? = nil,
        onShare: ((CDPublication) -> Void)? = nil,
        onShareByEmail: ((CDPublication) -> Void)? = nil,
        onExploreReferences: ((CDPublication) -> Void)? = nil,
        onExploreCitations: ((CDPublication) -> Void)? = nil,
        onExploreSimilar: ((CDPublication) -> Void)? = nil
    ) {
        self.publications = publications
        self._selection = selection
        self._selectedPublication = selectedPublication
        self.library = library
        self.allLibraries = allLibraries
        self.showImportButton = showImportButton
        self.showSortMenu = showSortMenu
        self.emptyStateMessage = emptyStateMessage
        self.emptyStateDescription = emptyStateDescription
        self.listID = listID
        self.disableUnreadFilter = disableUnreadFilter
        self.isInInbox = isInInbox
        self._filterScope = filterScope
        self.onDelete = onDelete
        self.onToggleRead = onToggleRead
        self.onCopy = onCopy
        self.onCut = onCut
        self.onPaste = onPaste
        self.onAddToLibrary = onAddToLibrary
        self.onAddToCollection = onAddToCollection
        self.onRemoveFromAllCollections = onRemoveFromAllCollections
        self.onImport = onImport
        self.onOpenPDF = onOpenPDF
        self.onFileDrop = onFileDrop
        self.onDownloadPDFs = onDownloadPDFs
        // Inbox triage
        self.onArchiveToLibrary = onArchiveToLibrary
        self.onDismiss = onDismiss
        self.onToggleStar = onToggleStar
        self.onMuteAuthor = onMuteAuthor
        self.onMutePaper = onMutePaper
        // Category tap
        self.onCategoryTap = onCategoryTap
        // Refresh
        self.onRefresh = onRefresh
        self.isRefreshing = isRefreshing
        // Enhanced context menu
        self.onOpenInBrowser = onOpenInBrowser
        self.onDownloadPDF = onDownloadPDF
        self.onViewEditBibTeX = onViewEditBibTeX
        self.onShare = onShare
        self.onShareByEmail = onShareByEmail
        self.onExploreReferences = onExploreReferences
        self.onExploreCitations = onExploreCitations
        self.onExploreSimilar = onExploreSimilar
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Inline toolbar
            inlineToolbar

            Divider()

            // Content
            if filteredRowData.isEmpty {
                emptyState
            } else {
                publicationList
            }
        }
        .task(id: listID) {
            await loadState()
            listViewSettings = await ListViewSettingsStore.shared.settings
        }
        .onAppear {
            rebuildRowData()
        }
        .onChange(of: publications.count) { _, _ in
            // Rebuild row data when publications change (add/delete)
            rebuildRowData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("readStatusDidChange"))) { notification in
            // Smart update: only rebuild the changed row (O(1) instead of O(n))
            if let changedID = notification.object as? UUID {
                updateSingleRowData(for: changedID)
            } else {
                // Fallback: unknown change, rebuild all
                rebuildRowData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .listViewSettingsDidChange)) { _ in
            // Reload settings when they change
            Task {
                listViewSettings = await ListViewSettingsStore.shared.settings
            }
        }
        .onChange(of: selection) { _, newValue in
            // Update selection synchronously - the detail view defers its own update
            if let firstID = newValue.first,
               let publication = publicationsByID[firstID],
               !publication.isDeleted,
               publication.managedObjectContext != nil {
                selectedPublication = publication
            } else {
                selectedPublication = nil
            }

            if hasLoadedState {
                debouncedSaveState()
            }
        }
        .onChange(of: sortOrder) { _, _ in
            if hasLoadedState {
                debouncedSaveState()
            }
        }
        .onChange(of: showUnreadOnly) { _, _ in
            if hasLoadedState {
                debouncedSaveState()
            }
        }
        .onChange(of: searchQuery) { _, newQuery in
            // Trigger PDF search if enabled and query changed
            if searchInPDFs && !newQuery.isEmpty {
                triggerPDFSearch()
            } else if newQuery.isEmpty {
                // Clear PDF matches when query is cleared
                pdfSearchMatches.removeAll()
            }
        }
    }

    // MARK: - PDF Search

    /// Trigger an async PDF content search
    private func triggerPDFSearch() {
        // Cancel any existing search
        pdfSearchTask?.cancel()

        guard !searchQuery.isEmpty else {
            pdfSearchMatches.removeAll()
            return
        }

        isPDFSearching = true

        pdfSearchTask = Task {
            let matches = await PDFSearchService.shared.search(
                query: searchQuery,
                in: publications,
                library: library
            )

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            await MainActor.run {
                pdfSearchMatches = matches
                isPDFSearching = false
                filterCache.invalidate()  // Force recompute with new PDF matches
            }
        }
    }

    // MARK: - Row Data Management

    /// Rebuild both caches from current publications.
    /// - rowDataCache: [UUID: PublicationRowData] for display
    /// - publicationsByID: [UUID: CDPublication] for O(1) mutation lookups
    private func rebuildRowData() {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            Logger.performance.info("⏱ rebuildRowData: \(elapsed, format: .fixed(precision: 1))ms (\(publications.count) items)")
        }

        var newRowCache: [UUID: PublicationRowData] = [:]
        var newPubCache: [UUID: CDPublication] = [:]

        for pub in publications {
            newPubCache[pub.id] = pub
            if let data = PublicationRowData(publication: pub) {
                newRowCache[pub.id] = data
            }
        }

        rowDataCache = newRowCache
        publicationsByID = newPubCache

        // Invalidate filtered data cache - it will be recomputed on next access
        filterCache.invalidate()
    }

    /// Update a single row in the cache (O(1) instead of full rebuild).
    /// Used when only one publication's read status changed.
    private func updateSingleRowData(for publicationID: UUID) {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            Logger.performance.info("⏱ updateSingleRowData: \(elapsed, format: .fixed(precision: 2))ms")
        }

        guard let publication = publicationsByID[publicationID],
              !publication.isDeleted,
              publication.managedObjectContext != nil,
              let updatedData = PublicationRowData(publication: publication) else {
            return
        }
        rowDataCache[publicationID] = updatedData

        // Invalidate filtered data cache - read status change may affect unread filter
        filterCache.invalidate()
    }

    // MARK: - State Persistence

    private func loadState() async {
        guard let listID = listID else {
            hasLoadedState = true
            return
        }

        if let state = await ListViewStateStore.shared.get(for: listID) {
            // Restore sort order and direction
            if let order = LibrarySortOrder(rawValue: state.sortOrder) {
                sortOrder = order
                sortAscending = state.sortAscending
            }
            showUnreadOnly = state.showUnreadOnly

            // Restore selection if publication still exists and is valid
            if let selectedID = state.selectedPublicationID,
               let publication = publicationsByID[selectedID],  // O(1) lookup instead of O(n)
               !publication.isDeleted,
               publication.managedObjectContext != nil {
                selection = [selectedID]
                // Also update selectedPublication directly - onChange may not fire during initial load
                selectedPublication = publication
            }
        }

        hasLoadedState = true
    }

    private func saveState() async {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            Logger.performance.info("⏱ saveState: \(elapsed, format: .fixed(precision: 1))ms")
        }

        guard let listID = listID else { return }

        let state = ListViewState(
            selectedPublicationID: selection.first,
            sortOrder: sortOrder.rawValue,
            sortAscending: sortAscending,
            showUnreadOnly: showUnreadOnly,
            lastVisitedDate: Date()
        )

        await ListViewStateStore.shared.save(state, for: listID)
    }

    /// Debounced save - waits 300ms before saving to avoid rapid saves during fast navigation
    private func debouncedSaveState() {
        // Cancel any pending save
        saveStateTask?.cancel()

        // Schedule new save with delay
        saveStateTask = Task {
            do {
                // Wait 300ms before saving (allows rapid selection changes without I/O overhead)
                try await Task.sleep(for: .milliseconds(300))
                await saveState()
            } catch {
                // Task was cancelled - a new selection happened, skip this save
            }
        }
    }

    // MARK: - Inline Toolbar

    private var inlineToolbar: some View {
        HStack(spacing: 12) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search publications", text: $searchQuery)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .help("Filter by title, author, or cite key")

            // Scope picker (search across different sources)
            Menu {
                ForEach(FilterScope.allCases) { scope in
                    Button {
                        filterScope = scope
                    } label: {
                        if scope == filterScope {
                            Label(scope.rawValue, systemImage: "checkmark")
                        } else {
                            Text(scope.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(filterScope.rawValue)
                        .font(.caption)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundColor(filterScope == .current ? Color.secondary : Color.accentColor)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Search scope: \(filterScope.rawValue)")

            // PDF search toggle
            Button {
                searchInPDFs.toggle()
                if searchInPDFs && !searchQuery.isEmpty {
                    triggerPDFSearch()
                } else if !searchInPDFs {
                    pdfSearchMatches.removeAll()
                    filterCache.invalidate()
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "doc.text.magnifyingglass")
                    if isPDFSearching {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            }
            .foregroundStyle(searchInPDFs ? .blue : .secondary)
            .help(searchInPDFs ? "Disable PDF content search" : "Include PDF content in search")
            .buttonStyle(.plain)

            // Refresh button (only shown when onRefresh callback is provided)
            if let onRefresh = onRefresh {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Button {
                        Task { await onRefresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                    .help("Refresh")
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Import button
            if showImportButton, let onImport = onImport {
                Button {
                    onImport()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .foregroundStyle(.secondary)
                .help("Import BibTeX")
                .buttonStyle(.plain)
            }

            // Sort menu - click same option again to toggle ascending/descending
            if showSortMenu {
                Menu {
                    ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                        Button {
                            if sortOrder == order {
                                // Same order selected - toggle direction
                                sortAscending.toggle()
                            } else {
                                // Different order - set new order with default direction
                                sortOrder = order
                                sortAscending = order.defaultAscending
                            }
                        } label: {
                            HStack {
                                Text(order.displayName)
                                Spacer()
                                if sortOrder == order {
                                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .foregroundStyle(.secondary)
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Change sort order (click again to reverse)")
            }

            // Total count display
            countDisplay
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Display of filtered/total count
    private var countDisplay: some View {
        let filteredCount = filteredRowData.count
        let totalCount = publications.count
        let isFiltered = !searchQuery.isEmpty || showUnreadOnly

        return Group {
            if isFiltered && filteredCount != totalCount {
                Text("\(filteredCount) of \(totalCount)")
            } else {
                Text("\(filteredCount) papers")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    // MARK: - Publication List

    private var publicationList: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(Array(filteredRowData.enumerated()), id: \.element.id) { index, rowData in
                    makePublicationRow(data: rowData, index: index)
                        .tag(rowData.id)
                        .id(rowData.id)  // For ScrollViewReader
                }
            }
            // OPTIMIZATION: Disable selection animations for instant visual feedback
            .animation(nil, value: selection)
            .transaction { $0.animation = nil }
            .contextMenu(forSelectionType: UUID.self) { ids in
                contextMenuItems(for: ids)
            } primaryAction: { ids in
                // Double-click to open PDF - O(1) lookup
                if let first = ids.first,
                   let publication = publicationsByID[first],
                   let onOpenPDF = onOpenPDF {
                    onOpenPDF(publication)
                }
            }
            .onAppear {
                scrollProxy = proxy
            }
            // Apply transparent background when theme has custom background color
            .scrollContentBackground(theme.detailBackground != nil || theme.listBackgroundTint != nil ? .hidden : .automatic)
            .background {
                if let tint = theme.listBackgroundTint {
                    tint.opacity(theme.listBackgroundTintOpacity)
                }
            }
        #if os(macOS)
        .onDeleteCommand {
            if let onDelete = onDelete {
                let idsToDelete = selection
                // Clear selection immediately before deletion to prevent accessing deleted objects
                selection.removeAll()
                selectedPublication = nil
                Task { await onDelete(idsToDelete) }
            }
        }
        // Keyboard navigation handlers from menu/notifications
        .onReceive(NotificationCenter.default.publisher(for: .navigateNextPaper)) { _ in
            navigateToNext()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigatePreviousPaper)) { _ in
            navigateToPrevious()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateFirstPaper)) { _ in
            navigateToFirst()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateLastPaper)) { _ in
            navigateToLast()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateNextUnread)) { _ in
            navigateToNextUnread()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigatePreviousUnread)) { _ in
            navigateToPreviousUnread()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSelectedPaper)) { _ in
            openSelectedPaper()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleReadStatus)) { _ in
            toggleReadOnSelected()
        }
        .onReceive(NotificationCenter.default.publisher(for: .markAllAsRead)) { _ in
            markAllAsRead()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleUnreadFilter)) { _ in
            if !disableUnreadFilter {
                showUnreadOnly.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteSelectedPapers)) { _ in
            deleteSelected()
        }
        #endif
        }  // End ScrollViewReader
    }

    // MARK: - Keyboard Navigation

    /// Select a row and scroll to make it visible
    private func selectAndScrollTo(_ id: UUID) {
        selection = [id]
        withAnimation(.easeInOut(duration: 0.15)) {
            scrollProxy?.scrollTo(id, anchor: .center)
        }
    }

    /// Navigate to next paper in the filtered list
    private func navigateToNext() {
        let rows = filteredRowData
        guard !rows.isEmpty else { return }

        if let currentID = selection.first,
           let currentIndex = rows.firstIndex(where: { $0.id == currentID }) {
            let nextIndex = min(currentIndex + 1, rows.count - 1)
            selectAndScrollTo(rows[nextIndex].id)
        } else {
            // No selection, select first
            selectAndScrollTo(rows[0].id)
        }
    }

    /// Navigate to previous paper in the filtered list
    private func navigateToPrevious() {
        let rows = filteredRowData
        guard !rows.isEmpty else { return }

        if let currentID = selection.first,
           let currentIndex = rows.firstIndex(where: { $0.id == currentID }) {
            let prevIndex = max(currentIndex - 1, 0)
            selectAndScrollTo(rows[prevIndex].id)
        } else {
            // No selection, select first
            selectAndScrollTo(rows[0].id)
        }
    }

    /// Navigate to first paper
    private func navigateToFirst() {
        let rows = filteredRowData
        guard !rows.isEmpty else { return }
        selectAndScrollTo(rows[0].id)
    }

    /// Navigate to last paper
    private func navigateToLast() {
        let rows = filteredRowData
        guard !rows.isEmpty else { return }
        selectAndScrollTo(rows[rows.count - 1].id)
    }

    /// Navigate to next unread paper
    private func navigateToNextUnread() {
        let rows = filteredRowData
        guard !rows.isEmpty else { return }

        let startIndex: Int
        if let currentID = selection.first,
           let currentIndex = rows.firstIndex(where: { $0.id == currentID }) {
            startIndex = currentIndex + 1
        } else {
            startIndex = 0
        }

        // Search from current position to end
        for i in startIndex..<rows.count {
            if !rows[i].isRead {
                selectAndScrollTo(rows[i].id)
                return
            }
        }

        // Wrap around: search from beginning to current position
        for i in 0..<startIndex {
            if !rows[i].isRead {
                selectAndScrollTo(rows[i].id)
                return
            }
        }
    }

    /// Navigate to previous unread paper
    private func navigateToPreviousUnread() {
        let rows = filteredRowData
        guard !rows.isEmpty else { return }

        let startIndex: Int
        if let currentID = selection.first,
           let currentIndex = rows.firstIndex(where: { $0.id == currentID }) {
            startIndex = currentIndex - 1
        } else {
            startIndex = rows.count - 1
        }

        // Search backwards from current position
        for i in stride(from: startIndex, through: 0, by: -1) {
            if !rows[i].isRead {
                selectAndScrollTo(rows[i].id)
                return
            }
        }

        // Wrap around: search backwards from end
        for i in stride(from: rows.count - 1, through: max(0, startIndex + 1), by: -1) {
            if !rows[i].isRead {
                selectAndScrollTo(rows[i].id)
                return
            }
        }
    }

    /// Open selected paper (show PDF tab)
    private func openSelectedPaper() {
        guard let firstID = selection.first,
              let publication = publicationsByID[firstID],  // O(1) lookup
              !publication.isDeleted,
              publication.managedObjectContext != nil,
              let onOpenPDF = onOpenPDF else { return }

        onOpenPDF(publication)
    }

    /// Toggle read status on selected papers
    private func toggleReadOnSelected() {
        guard let onToggleRead = onToggleRead else { return }

        for id in selection {
            if let publication = publicationsByID[id],  // O(1) lookup
               !publication.isDeleted,
               publication.managedObjectContext != nil {
                Task {
                    await onToggleRead(publication)
                }
            }
        }
    }

    /// Mark all visible papers as read
    private func markAllAsRead() {
        guard let onToggleRead = onToggleRead else { return }

        for rowData in filteredRowData {
            if !rowData.isRead,
               let publication = publicationsByID[rowData.id],  // O(1) lookup
               !publication.isDeleted,
               publication.managedObjectContext != nil {
                Task {
                    await onToggleRead(publication)
                }
            }
        }
    }

    /// Delete selected papers
    private func deleteSelected() {
        guard let onDelete = onDelete, !selection.isEmpty else { return }

        let idsToDelete = selection
        // Clear selection immediately before deletion
        selection.removeAll()
        selectedPublication = nil
        Task { await onDelete(idsToDelete) }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for ids: Set<UUID>) -> some View {
        // Open PDF
        if let onOpenPDF = onOpenPDF {
            Button("Open PDF") {
                if let first = ids.first,
                   let publication = publicationsByID[first] {  // O(1) lookup
                    onOpenPDF(publication)
                }
            }

            Divider()
        }

        // Copy/Cut
        if let onCopy = onCopy {
            Button("Copy") {
                Task { await onCopy(ids) }
            }
        }

        if let onCut = onCut {
            Button("Cut") {
                Task { await onCut(ids) }
            }
        }

        // Copy Cite Key
        Button("Copy Cite Key") {
            if let first = ids.first,
               let rowData = rowDataCache[first] {
                copyToClipboard(rowData.citeKey)
            }
        }

        // Download PDFs (only shown when multiple papers selected)
        if let onDownloadPDFs = onDownloadPDFs, ids.count > 1 {
            Divider()
            Button {
                onDownloadPDFs(ids)
            } label: {
                Label("Download PDFs", systemImage: "arrow.down.doc")
            }
        }

        Divider()

        // Add to Library submenu (publications can belong to multiple libraries)
        // Each library is a submenu showing "All Publications" plus any collections
        if let onAddToLibrary = onAddToLibrary, !allLibraries.isEmpty {
            let otherLibraries = allLibraries.filter { $0.id != library?.id }
            if !otherLibraries.isEmpty {
                Menu("Add to Library") {
                    ForEach(otherLibraries, id: \.id) { targetLibrary in
                        let targetCollections = (targetLibrary.collections as? Set<CDCollection>)?
                            .filter { !$0.isSmartCollection && !$0.isSmartSearchResults }
                            .sorted { $0.name < $1.name } ?? []

                        Menu(targetLibrary.displayName) {
                            Button("All Publications") {
                                Task {
                                    await onAddToLibrary(ids, targetLibrary)
                                }
                            }
                            if !targetCollections.isEmpty {
                                Divider()
                                ForEach(targetCollections, id: \.id) { collection in
                                    Button(collection.name) {
                                        Task {
                                            await onAddToLibrary(ids, targetLibrary)
                                            if let onAddToCollection = onAddToCollection {
                                                await onAddToCollection(ids, collection)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Add to Collection submenu (with "All Publications" option to remove from all collections)
        if onAddToCollection != nil || onRemoveFromAllCollections != nil {
            // Show menu if we have collections OR have the remove callback
            if !staticCollections.isEmpty || onRemoveFromAllCollections != nil {
                Menu("Add to Collection") {
                    // "All Publications" removes from all collections
                    if let onRemoveFromAllCollections = onRemoveFromAllCollections {
                        Button("All Publications") {
                            Task {
                                await onRemoveFromAllCollections(ids)
                            }
                        }

                        if !staticCollections.isEmpty {
                            Divider()
                        }
                    }

                    // Static collections
                    if let onAddToCollection = onAddToCollection {
                        ForEach(staticCollections, id: \.id) { collection in
                            Button(collection.name) {
                                Task {
                                    await onAddToCollection(ids, collection)
                                }
                            }
                        }
                    }
                }
            }
        }

        // MARK: Archive/Triage Actions

        // Archive to Library (adds to target library AND removes from current library)
        // Available for all views, not just Inbox
        if let onArchiveToLibrary = onArchiveToLibrary, !allLibraries.isEmpty {
            // Filter out current library and Inbox from archive targets
            let archiveLibraries = allLibraries.filter { $0.id != library?.id && !$0.isInbox }
            if !archiveLibraries.isEmpty {
                Menu("Archive to Library") {
                    ForEach(archiveLibraries, id: \.id) { targetLibrary in
                        Button(targetLibrary.displayName) {
                            Task {
                                await onArchiveToLibrary(ids, targetLibrary)
                            }
                        }
                    }
                }
            }
        }

        // Dismiss from Inbox
        if let onDismiss = onDismiss {
            Button("Dismiss from Inbox") {
                Task { await onDismiss(ids) }
            }
        }

        // Mute options
        if onMuteAuthor != nil || onMutePaper != nil {
            Divider()

            if let onMuteAuthor = onMuteAuthor {
                // Get first author of first selected publication - O(1) lookup
                if let first = ids.first,
                   let publication = publicationsByID[first],
                   let firstAuthor = publication.sortedAuthors.first {
                    let authorName = firstAuthor.displayName
                    Button("Mute Author: \(authorName)") {
                        onMuteAuthor(authorName)
                    }
                }
            }

            if let onMutePaper = onMutePaper {
                if let first = ids.first,
                   let publication = publicationsByID[first] {  // O(1) lookup
                    Button("Mute This Paper") {
                        onMutePaper(publication)
                    }
                }
            }
        }

        Divider()

        // Delete
        if let onDelete = onDelete {
            Button("Delete", role: .destructive) {
                // Clear selection immediately before deletion
                selection.removeAll()
                selectedPublication = nil
                Task {
                    await onDelete(ids)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyStateMessage, systemImage: "books.vertical")
        } description: {
            Text(emptyStateDescription)
        } actions: {
            if showImportButton, let onImport = onImport {
                Button("Import BibTeX...") {
                    onImport()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Row Builder

    /// Build a publication row with all callbacks wired up.
    /// This is extracted to a helper method to avoid "expression too complex" compiler errors.
    @ViewBuilder
    private func makePublicationRow(data rowData: PublicationRowData, index: Int) -> some View {
        let deleteHandler: (() -> Void)? = onDelete != nil ? {
            Task { await onDelete?([rowData.id]) }
        } : nil

        let archiveHandler: (() -> Void)? = {
            guard onArchiveToLibrary != nil else { return nil }
            let nonInboxLibraries = allLibraries.filter { !$0.isInbox }
            guard !nonInboxLibraries.isEmpty else { return nil }
            return {
                if let targetLibrary = nonInboxLibraries.first {
                    Task { await onArchiveToLibrary?([rowData.id], targetLibrary) }
                }
            }
        }()

        let dismissHandler: (() -> Void)? = onDismiss != nil ? {
            Task { await onDismiss?([rowData.id]) }
        } : nil

        let toggleReadHandler: (() -> Void)? = onToggleRead != nil ? {
            if let pub = publicationsByID[rowData.id] {
                Task { await onToggleRead?(pub) }
            }
        } : nil

        let openPDFHandler: (() -> Void)? = (onOpenPDF != nil && rowData.hasPDF) ? {
            if let pub = publicationsByID[rowData.id] {
                onOpenPDF?(pub)
            }
        } : nil

        let copyBibTeXHandler: (() -> Void)? = onCopy != nil ? {
            Task { await onCopy?([rowData.id]) }
        } : nil

        let addToCollectionHandler: ((CDCollection) -> Void)? = onAddToCollection != nil ? { collection in
            Task { await onAddToCollection?([rowData.id], collection) }
        } : nil

        let muteAuthorHandler: (() -> Void)? = onMuteAuthor != nil ? {
            let firstName = rowData.authorString.split(separator: ",").first.map(String.init) ?? rowData.authorString
            onMuteAuthor?(firstName)
        } : nil

        let mutePaperHandler: (() -> Void)? = onMutePaper != nil ? {
            if let pub = publicationsByID[rowData.id] {
                onMutePaper?(pub)
            }
        } : nil

        // New context menu handlers
        let openInBrowserHandler: ((BrowserDestination) -> Void)? = onOpenInBrowser != nil ? { destination in
            if let pub = publicationsByID[rowData.id] {
                onOpenInBrowser?(pub, destination)
            }
        } : nil

        let downloadPDFHandler: (() -> Void)? = (onDownloadPDF != nil && !rowData.hasPDF) ? {
            if let pub = publicationsByID[rowData.id] {
                onDownloadPDF?(pub)
            }
        } : nil

        let viewEditBibTeXHandler: (() -> Void)? = onViewEditBibTeX != nil ? {
            if let pub = publicationsByID[rowData.id] {
                onViewEditBibTeX?(pub)
            }
        } : nil

        let shareHandler: (() -> Void)? = onShare != nil ? {
            if let pub = publicationsByID[rowData.id] {
                onShare?(pub)
            }
        } : nil

        let shareByEmailHandler: (() -> Void)? = onShareByEmail != nil ? {
            if let pub = publicationsByID[rowData.id] {
                onShareByEmail?(pub)
            }
        } : nil

        let exploreReferencesHandler: (() -> Void)? = onExploreReferences != nil ? {
            if let pub = publicationsByID[rowData.id] {
                onExploreReferences?(pub)
            }
        } : nil

        let exploreCitationsHandler: (() -> Void)? = onExploreCitations != nil ? {
            if let pub = publicationsByID[rowData.id] {
                onExploreCitations?(pub)
            }
        } : nil

        let exploreSimilarHandler: (() -> Void)? = onExploreSimilar != nil ? {
            if let pub = publicationsByID[rowData.id] {
                onExploreSimilar?(pub)
            }
        } : nil

        let addToLibraryHandler: ((CDLibrary) -> Void)? = onAddToLibrary != nil ? { library in
            Task { await onAddToLibrary?([rowData.id], library) }
        } : nil

        MailStylePublicationRow(
            data: rowData,
            settings: listViewSettings,
            rowNumber: index + 1,
            onToggleRead: toggleReadHandler,
            onCategoryTap: onCategoryTap,
            onDelete: deleteHandler,
            onArchive: archiveHandler,
            onDismiss: dismissHandler,
            isInInbox: isInInbox,
            onOpenPDF: openPDFHandler,
            onCopyCiteKey: { copyToClipboard(rowData.citeKey) },
            onCopyBibTeX: copyBibTeXHandler,
            onAddToCollection: addToCollectionHandler,
            onMuteAuthor: muteAuthorHandler,
            onMutePaper: mutePaperHandler,
            collections: staticCollections,
            hasPDF: rowData.hasPDF,
            // New context menu callbacks
            onOpenInBrowser: openInBrowserHandler,
            onDownloadPDF: downloadPDFHandler,
            onViewEditBibTeX: viewEditBibTeXHandler,
            onShare: shareHandler,
            onShareByEmail: shareByEmailHandler,
            onExploreReferences: exploreReferencesHandler,
            onExploreCitations: exploreCitationsHandler,
            onExploreSimilar: exploreSimilarHandler,
            onAddToLibrary: addToLibraryHandler,
            libraries: allLibraries.filter { !$0.isInbox }  // Exclude Inbox from library list
        )
    }

    // MARK: - Helpers

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    /// Handle file drop on a publication row
    private func handleFileDrop(providers: [NSItemProvider], for publicationID: UUID) -> Bool {
        guard let onFileDrop = onFileDrop,
              let publication = publicationsByID[publicationID],  // O(1) lookup
              !publication.isDeleted,
              publication.managedObjectContext != nil else {
            return false
        }

        onFileDrop(publication, providers)
        return true
    }
}

// MARK: - Preview

#Preview {
    let context = PersistenceController.preview.viewContext
    let publications: [CDPublication] = context.performAndWait {
        let pub1 = CDPublication(context: context)
        pub1.id = UUID()
        pub1.citeKey = "Einstein1905"
        pub1.entryType = "article"
        pub1.title = "On the Electrodynamics of Moving Bodies"
        pub1.year = 1905
        pub1.dateAdded = Date()
        pub1.dateModified = Date()
        pub1.isRead = false
        pub1.fields = ["author": "Einstein, Albert"]

        let pub2 = CDPublication(context: context)
        pub2.id = UUID()
        pub2.citeKey = "Hawking1974"
        pub2.entryType = "article"
        pub2.title = "Black hole explosions?"
        pub2.year = 1974
        pub2.dateAdded = Date()
        pub2.dateModified = Date()
        pub2.isRead = true
        pub2.fields = ["author": "Hawking, Stephen W."]

        return [pub1, pub2]
    }

    return PublicationListView(
        publications: publications,
        selection: .constant([]),
        selectedPublication: .constant(nil),
        showImportButton: true,
        showSortMenu: true,
        filterScope: .constant(.current),
        onImport: { print("Import tapped") }
    )
}
