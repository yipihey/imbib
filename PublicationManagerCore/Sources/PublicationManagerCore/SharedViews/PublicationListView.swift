//
//  PublicationListView.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-05.
//

import SwiftUI

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

    // MARK: - Internal State

    @State private var searchQuery: String = ""
    @State private var showUnreadOnly: Bool = false
    @State private var sortOrder: LibrarySortOrder = .dateAdded
    @State private var hasLoadedState: Bool = false

    /// Cached row data - rebuilt when publications change
    @State private var rowDataCache: [UUID: PublicationRowData] = [:]

    // MARK: - Computed Properties

    /// Filtered and sorted row data (safe value types)
    private var filteredRowData: [PublicationRowData] {
        var result = Array(rowDataCache.values)

        // Filter by unread
        if showUnreadOnly {
            result = result.filter { !$0.isRead }
        }

        // Filter by search query
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter { rowData in
                rowData.title.lowercased().contains(query) ||
                rowData.authorString.lowercased().contains(query) ||
                rowData.citeKey.lowercased().contains(query)
            }
        }

        // Sort using data already in PublicationRowData - no CDPublication lookups needed
        return result.sorted { lhs, rhs in
            switch sortOrder {
            case .dateAdded:
                return lhs.dateAdded > rhs.dateAdded
            case .dateModified:
                return lhs.dateModified > rhs.dateModified
            case .title:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .year:
                return (lhs.year ?? 0) > (rhs.year ?? 0)
            case .citeKey:
                return lhs.citeKey.localizedCaseInsensitiveCompare(rhs.citeKey) == .orderedAscending
            case .citationCount:
                return lhs.citationCount > rhs.citationCount
            }
        }
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
        onDelete: ((Set<UUID>) async -> Void)? = nil,
        onToggleRead: ((CDPublication) async -> Void)? = nil,
        onCopy: ((Set<UUID>) async -> Void)? = nil,
        onCut: ((Set<UUID>) async -> Void)? = nil,
        onPaste: (() async -> Void)? = nil,
        onAddToLibrary: ((Set<UUID>, CDLibrary) async -> Void)? = nil,
        onAddToCollection: ((Set<UUID>, CDCollection) async -> Void)? = nil,
        onRemoveFromAllCollections: ((Set<UUID>) async -> Void)? = nil,
        onImport: (() -> Void)? = nil,
        onOpenPDF: ((CDPublication) -> Void)? = nil
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
        }
        .onAppear {
            rebuildRowData()
        }
        .onChange(of: publications.count) { _, _ in
            // Rebuild row data when publications change (add/delete)
            rebuildRowData()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("readStatusDidChange"))) { _ in
            // Rebuild row data when read status changes
            rebuildRowData()
        }
        .onChange(of: selection) { _, newValue in
            // Find publication for single-selection binding
            if let firstID = newValue.first,
               let pub = publications.first(where: { $0.id == firstID }),
               !pub.isDeleted,
               pub.managedObjectContext != nil {
                selectedPublication = pub
            } else {
                selectedPublication = nil
            }
            // Save selection state
            if hasLoadedState {
                Task { await saveState() }
            }
        }
        .onChange(of: sortOrder) { _, _ in
            if hasLoadedState {
                Task { await saveState() }
            }
        }
        .onChange(of: showUnreadOnly) { _, _ in
            if hasLoadedState {
                Task { await saveState() }
            }
        }
    }

    // MARK: - Row Data Management

    /// Rebuild the row data cache from current publications.
    /// This filters out any deleted objects and creates immutable snapshots.
    private func rebuildRowData() {
        var newCache: [UUID: PublicationRowData] = [:]
        for pub in publications {
            if let data = PublicationRowData(publication: pub) {
                newCache[pub.id] = data
            }
        }
        rowDataCache = newCache
    }

    // MARK: - State Persistence

    private func loadState() async {
        guard let listID = listID else {
            hasLoadedState = true
            return
        }

        if let state = await ListViewStateStore.shared.get(for: listID) {
            // Restore sort order
            if let order = LibrarySortOrder(rawValue: state.sortOrder) {
                sortOrder = order
            }
            showUnreadOnly = state.showUnreadOnly

            // Restore selection if publication still exists and is valid
            if let selectedID = state.selectedPublicationID,
               let publication = publications.first(where: { $0.id == selectedID }),
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
        guard let listID = listID else { return }

        let state = ListViewState(
            selectedPublicationID: selection.first,
            sortOrder: sortOrder.rawValue,
            sortAscending: false,  // Currently not configurable
            showUnreadOnly: showUnreadOnly,
            lastVisitedDate: Date()
        )

        await ListViewStateStore.shared.save(state, for: listID)
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
                }
            }
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Spacer()

            // Filter button (unread only)
            Button {
                showUnreadOnly.toggle()
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .foregroundStyle(showUnreadOnly ? .blue : .secondary)
            .help(showUnreadOnly ? "Show all publications" : "Show unread only")
            .buttonStyle(.plain)

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

            // Sort menu
            if showSortMenu {
                Menu {
                    ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                        Button(order.displayName) {
                            sortOrder = order
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .foregroundStyle(.secondary)
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Publication List

    private var publicationList: some View {
        List(filteredRowData, id: \.id, selection: $selection) { rowData in
            MailStylePublicationRow(
                data: rowData,
                showUnreadIndicator: true,
                onToggleRead: onToggleRead != nil ? {
                    // Look up CDPublication for mutation
                    if let pub = publications.first(where: { $0.id == rowData.id }) {
                        Task {
                            await onToggleRead?(pub)
                        }
                    }
                } : nil
            )
            .tag(rowData.id)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenuItems(for: ids)
        } primaryAction: { ids in
            // Double-click to open PDF
            if let first = ids.first,
               let publication = publications.first(where: { $0.id == first }),
               let onOpenPDF = onOpenPDF {
                onOpenPDF(publication)
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
        #endif
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for ids: Set<UUID>) -> some View {
        // Open PDF
        if let onOpenPDF = onOpenPDF {
            Button("Open PDF") {
                if let first = ids.first,
                   let publication = publications.first(where: { $0.id == first }) {
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
            let staticCollections: [CDCollection] = {
                guard let collections = library?.collections as? Set<CDCollection> else { return [] }
                return collections.filter { !$0.isSmartCollection && !$0.isSmartSearchResults }
                    .sorted { $0.name < $1.name }
            }()

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

    // MARK: - Helpers

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
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
        onImport: { print("Import tapped") }
    )
}
