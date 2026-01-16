//
//  SidebarView.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import CoreData
import PublicationManagerCore
import UniformTypeIdentifiers

struct SidebarView: View {

    // MARK: - Properties

    @Binding var selection: SidebarSection?
    @Binding var expandedLibraries: Set<UUID>

    // MARK: - Environment

    @Environment(LibraryManager.self) private var libraryManager
    @Environment(\.themeColors) private var theme

    // MARK: - Observed Objects

    /// Observe SmartSearchRepository to refresh when smart searches change
    @ObservedObject private var smartSearchRepository = SmartSearchRepository.shared

    /// Observe SciXLibraryRepository for SciX libraries
    @ObservedObject private var scixRepository = SciXLibraryRepository.shared

    // MARK: - State
    @State private var newSmartCollectionLibrary: CDLibrary?  // Non-nil triggers sheet for this library
    @State private var editingCollection: CDCollection?
    @State private var showingNewLibrary = false
    @State private var libraryToDelete: CDLibrary?
    @State private var showDeleteConfirmation = false
    @State private var dropTargetedCollection: UUID?
    @State private var dropTargetedLibrary: UUID?
    @State private var dropTargetedLibraryHeader: UUID?
    @State private var refreshTrigger = UUID()  // Triggers re-render when read status changes
    @State private var renamingCollection: CDCollection?  // Collection being renamed inline
    @State private var hasSciXAPIKey = false  // Whether SciX API key is configured
    @State private var explorationRefreshTrigger = UUID()  // Refresh exploration section
    @State private var explorationMultiSelection: Set<UUID> = []  // Multi-selection for bulk delete (Option+click)
    @State private var lastSelectedExplorationID: UUID?  // For Shift+click range selection
    @State private var expandedExplorationCollections: Set<UUID> = []  // Expanded state for tree disclosure groups
    @State private var searchMultiSelection: Set<UUID> = []  // Multi-selection for smart searches
    @State private var lastSelectedSearchID: UUID?  // For Shift+click range selection on searches

    // Section ordering and collapsed state (persisted)
    @State private var sectionOrder: [SidebarSectionType] = SidebarSectionOrderStore.loadOrderSync()
    @State private var collapsedSections: Set<SidebarSectionType> = SidebarCollapsedStateStore.loadCollapsedSync()

    // Search form ordering and visibility (persisted)
    @State private var searchFormOrder: [SearchFormType] = SearchFormStore.loadOrderSync()
    @State private var hiddenSearchForms: Set<SearchFormType> = SearchFormStore.loadHiddenSync()

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Main list with optional theme tint
            List(selection: $selection) {
                // All sections in user-defined order, all collapsible and moveable
                ForEach(sectionOrder) { sectionType in
                    sectionView(for: sectionType)
                        .id(sectionType == .exploration ? explorationRefreshTrigger : nil)
                }
                .onMove(perform: moveSections)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(theme.detailBackground != nil || theme.sidebarTint != nil ? .hidden : .automatic)
            .background {
                if let tint = theme.sidebarTint {
                    tint.opacity(theme.sidebarTintOpacity)
                }
            }

            // Bottom toolbar
            Divider()
            bottomToolbar
        }
        .navigationTitle("imbib")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        #endif
        // Smart search creation/editing now uses Search section forms
        // See ADR for unified search experience
        .sheet(isPresented: $showingNewLibrary) {
            NewLibrarySheet()
        }
        .sheet(item: $newSmartCollectionLibrary) { library in
            SmartCollectionEditor(isPresented: .constant(true)) { name, predicate in
                Task {
                    await createSmartCollection(name: name, predicate: predicate, in: library)
                }
                newSmartCollectionLibrary = nil  // Dismiss sheet
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
            // Load all smart searches (not filtered by library) for sidebar display
            smartSearchRepository.loadSmartSearches(for: nil)

            // Check for ADS API key (SciX uses ADS API) and load libraries if available
            if let _ = await CredentialManager.shared.apiKey(for: "ads") {
                hasSciXAPIKey = true
                // Load cached libraries from Core Data
                scixRepository.loadLibraries()
                // Optionally trigger a background refresh from server
                Task.detached {
                    try? await SciXSyncManager.shared.pullLibraries()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readStatusDidChange)) { _ in
            // Force re-render to update unread counts
            refreshTrigger = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .explorationLibraryDidChange)) { _ in
            // Refresh exploration section
            explorationRefreshTrigger = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCollection)) { notification in
            // Navigate to the collection in the sidebar
            if let collection = notification.userInfo?["collection"] as? CDCollection {
                // Expand all ancestors so the collection is visible in the tree
                expandAncestors(of: collection)
                selection = .collection(collection)
                explorationRefreshTrigger = UUID()
            }
        }
        // Auto-expand ancestors and set exploration context when selection changes
        .onChange(of: selection) { _, newSelection in
            if case .collection(let collection) = newSelection {
                expandAncestors(of: collection)
                // Set exploration context for building tree hierarchy
                ExplorationService.shared.currentExplorationContext = collection
            } else {
                // Clear exploration context when not viewing an exploration collection
                ExplorationService.shared.currentExplorationContext = nil
            }
        }
        .id(refreshTrigger)  // Re-render when refreshTrigger changes
    }

    // MARK: - Section Views

    /// Returns the appropriate section view for a given section type
    @ViewBuilder
    private func sectionView(for sectionType: SidebarSectionType) -> some View {
        switch sectionType {
        case .inbox:
            collapsibleSection(for: .inbox) {
                inboxSectionContent
            }
        case .libraries:
            collapsibleSection(for: .libraries) {
                librariesSectionContent
            }
        case .scixLibraries:
            if hasSciXAPIKey && !scixRepository.libraries.isEmpty {
                collapsibleSection(for: .scixLibraries) {
                    scixLibrariesSectionContent
                }
            }
        case .search:
            collapsibleSection(for: .search) {
                searchSectionContent
            }
        case .exploration:
            if let library = libraryManager.explorationLibrary,
               let collections = library.collections,
               !collections.isEmpty {
                collapsibleSection(for: .exploration) {
                    explorationSectionContent
                }
            }
        }
    }

    /// Wraps section content in a collapsible Section with standard header
    @ViewBuilder
    private func collapsibleSection<Content: View>(
        for sectionType: SidebarSectionType,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isCollapsed = collapsedSections.contains(sectionType)

        Section {
            if !isCollapsed {
                content()
            }
        } header: {
            HStack(spacing: 4) {
                // Collapse/expand button
                Button {
                    toggleSectionCollapsed(sectionType)
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)

                // Section title
                Text(sectionType.displayName)

                Spacer()

                // Additional header content based on section type
                sectionHeaderExtras(for: sectionType)
            }
        }
    }

    /// Toggle collapsed state for a section
    private func toggleSectionCollapsed(_ sectionType: SidebarSectionType) {
        if collapsedSections.contains(sectionType) {
            collapsedSections.remove(sectionType)
        } else {
            collapsedSections.insert(sectionType)
        }
        // Persist
        Task {
            await SidebarCollapsedStateStore.shared.save(collapsedSections)
        }
    }

    /// Additional header content for specific section types
    @ViewBuilder
    private func sectionHeaderExtras(for sectionType: SidebarSectionType) -> some View {
        switch sectionType {
        case .inbox:
            // Add feed button - navigates to Search section
            Button {
                // Navigate to Search section for creating new feed
                NotificationCenter.default.post(name: .navigateToSearchSection, object: nil)
            } label: {
                Image(systemName: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Create search from Search section")
        case .libraries:
            // Add library button
            Button {
                showingNewLibrary = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Add Library")
        case .exploration:
            // Navigation buttons + selection count
            HStack(spacing: 4) {
                // Back/forward navigation buttons
                NavigationButtonBar(
                    navigationHistory: NavigationHistoryStore.shared,
                    onBack: { NotificationCenter.default.post(name: .navigateBack, object: nil) },
                    onForward: { NotificationCenter.default.post(name: .navigateForward, object: nil) }
                )

                // Show selection count when multi-selected
                if explorationMultiSelection.count > 1 {
                    Text("\(explorationMultiSelection.count) selected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        default:
            EmptyView()
        }
    }

    /// Libraries section content (without Section wrapper)
    @ViewBuilder
    private var librariesSectionContent: some View {
        ForEach(libraryManager.libraries.filter { !$0.isInbox }, id: \.id) { library in
            libraryDisclosureGroup(for: library)
        }
        .onMove { indices, destination in
            libraryManager.moveLibraries(from: indices, to: destination)
        }
    }

    /// SciX Libraries section content (without Section wrapper)
    @ViewBuilder
    private var scixLibrariesSectionContent: some View {
        ForEach(scixRepository.libraries, id: \.id) { library in
            scixLibraryRow(for: library)
        }
    }

    /// Search section content (without Section wrapper)
    @ViewBuilder
    private var searchSectionContent: some View {
        // Visible search forms in user-defined order
        ForEach(visibleSearchForms) { formType in
            Label(formType.displayName, systemImage: formType.icon)
                .tag(SidebarSection.searchForm(formType))
                .contentShape(Rectangle())
                .onTapGesture {
                    // Reset to show form in list pane (not results)
                    // This fires even when re-clicking the already-selected form
                    NotificationCenter.default.post(name: .resetSearchFormView, object: nil)
                    // Manually set selection since onTapGesture consumes the tap
                    selection = .searchForm(formType)
                }
                .contextMenu {
                    Button("Hide") {
                        hideSearchForm(formType)
                    }
                }
        }
        .onMove(perform: moveSearchForms)

        // Show hidden forms menu if any are hidden
        if !hiddenSearchForms.isEmpty {
            Menu {
                ForEach(Array(hiddenSearchForms).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { formType in
                    Button("Show \(formType.displayName)") {
                        showSearchForm(formType)
                    }
                }

                Divider()

                Button("Show All") {
                    showAllSearchForms()
                }
            } label: {
                Label("Show Hidden Forms...", systemImage: "eye")
            }
        }
    }

    /// Get visible search forms in order
    private var visibleSearchForms: [SearchFormType] {
        searchFormOrder.filter { !hiddenSearchForms.contains($0) }
    }

    /// Move search forms via drag-and-drop
    private func moveSearchForms(from source: IndexSet, to destination: Int) {
        // Get the visible forms
        var visible = visibleSearchForms

        // Perform the move on visible forms
        visible.move(fromOffsets: source, toOffset: destination)

        // Rebuild the full order preserving hidden forms in their relative positions
        var newOrder: [SearchFormType] = []
        var visibleIndex = 0

        for formType in searchFormOrder {
            if hiddenSearchForms.contains(formType) {
                // Keep hidden forms in their current relative position
                newOrder.append(formType)
            } else {
                // Insert visible forms in their new order
                if visibleIndex < visible.count {
                    newOrder.append(visible[visibleIndex])
                    visibleIndex += 1
                }
            }
        }

        // Add any remaining visible forms
        while visibleIndex < visible.count {
            newOrder.append(visible[visibleIndex])
            visibleIndex += 1
        }

        withAnimation {
            searchFormOrder = newOrder
        }

        Task {
            await SearchFormStore.shared.save(newOrder)
        }
    }

    /// Hide a search form
    private func hideSearchForm(_ formType: SearchFormType) {
        withAnimation {
            hiddenSearchForms.insert(formType)
        }
        Task {
            await SearchFormStore.shared.hide(formType)
        }
    }

    /// Show a hidden search form
    private func showSearchForm(_ formType: SearchFormType) {
        withAnimation {
            hiddenSearchForms.remove(formType)
        }
        Task {
            await SearchFormStore.shared.show(formType)
        }
    }

    /// Show all hidden search forms
    private func showAllSearchForms() {
        withAnimation {
            hiddenSearchForms.removeAll()
        }
        Task {
            await SearchFormStore.shared.setHidden([])
        }
    }

    /// Smart searches in the exploration library (searches executed from Search section)
    private var explorationSmartSearches: [CDSmartSearch] {
        guard let library = libraryManager.explorationLibrary,
              let searches = library.smartSearches else { return [] }
        return Array(searches).sorted { ($0.dateCreated) > ($1.dateCreated) }
    }

    /// Exploration section content (without Section wrapper)
    @ViewBuilder
    private var explorationSectionContent: some View {
        // Search results from Search section (smart searches in exploration library)
        ForEach(explorationSmartSearches) { smartSearch in
            explorationSearchRow(smartSearch)
        }

        // Exploration collections (Refs, Cites, Similar, Co-Reads) - hierarchical tree display
        if let library = libraryManager.explorationLibrary,
           let collections = library.collections,
           !collections.isEmpty {
            // Add separator if both searches and collections exist
            if !explorationSmartSearches.isEmpty {
                Divider()
                    .padding(.vertical, 4)
            }

            // Flatten and filter based on expanded state
            let allCollections = flattenedExplorationCollections(from: collections)
            let visibleCollections = filterVisibleCollections(allCollections)

            ForEach(visibleCollections, id: \.id) { collection in
                ExplorationTreeRow(
                    collection: collection,
                    allCollections: allCollections,
                    selection: $selection,
                    expandedCollections: $expandedExplorationCollections,
                    multiSelection: $explorationMultiSelection,
                    lastSelectedID: $lastSelectedExplorationID,
                    onDelete: deleteExplorationCollection,
                    onDeleteMultiple: deleteSelectedExplorationCollections
                )
            }
        }
    }

    /// Row for a search smart search in the exploration section
    @ViewBuilder
    private func explorationSearchRow(_ smartSearch: CDSmartSearch) -> some View {
        let isSelected = selection == .smartSearch(smartSearch)
        let isMultiSelected = searchMultiSelection.contains(smartSearch.id)
        let count = smartSearch.resultCollection?.publications?.count ?? 0

        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.purple)
                .frame(width: 16)

            Text(smartSearch.name)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
        .tag(SidebarSection.smartSearch(smartSearch))
        .listRowBackground(
            isMultiSelected || isSelected
                ? Color.accentColor.opacity(0.2)
                : Color.clear
        )
        // Option+Click to toggle multi-selection
        .gesture(
            TapGesture()
                .modifiers(.option)
                .onEnded { _ in
                    if searchMultiSelection.contains(smartSearch.id) {
                        searchMultiSelection.remove(smartSearch.id)
                    } else {
                        searchMultiSelection.insert(smartSearch.id)
                    }
                    lastSelectedSearchID = smartSearch.id
                }
        )
        // Shift+Click for range selection
        .gesture(
            TapGesture()
                .modifiers(.shift)
                .onEnded { _ in
                    handleShiftClickSearch(smartSearch: smartSearch, allSearches: explorationSmartSearches)
                }
        )
        // Normal click clears multi-selection and navigates
        .onTapGesture {
            searchMultiSelection.removeAll()
            searchMultiSelection.insert(smartSearch.id)
            lastSelectedSearchID = smartSearch.id
            selection = .smartSearch(smartSearch)
        }
        .contextMenu {
            // Show batch delete if multiple searches selected
            if searchMultiSelection.count > 1 {
                Button("Delete \(searchMultiSelection.count) Searches", role: .destructive) {
                    deleteSelectedSmartSearches()
                }
            } else {
                Button("Edit Search...") {
                    // Navigate to Search section with this smart search's query
                    NotificationCenter.default.post(name: .editSmartSearch, object: smartSearch.id)
                }

                Divider()

                Button("Delete", role: .destructive) {
                    SmartSearchRepository.shared.delete(smartSearch)
                    if selection == .smartSearch(smartSearch) {
                        selection = nil
                    }
                    searchMultiSelection.remove(smartSearch.id)
                    explorationRefreshTrigger = UUID()
                }
            }
        }
    }

    /// Handle Shift+click for range selection on smart searches
    private func handleShiftClickSearch(smartSearch: CDSmartSearch, allSearches: [CDSmartSearch]) {
        guard let lastID = lastSelectedSearchID,
              let lastIndex = allSearches.firstIndex(where: { $0.id == lastID }),
              let currentIndex = allSearches.firstIndex(where: { $0.id == smartSearch.id }) else {
            // No previous selection, just add this one
            searchMultiSelection.insert(smartSearch.id)
            lastSelectedSearchID = smartSearch.id
            return
        }

        // Select range between last and current
        let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
        for i in range {
            searchMultiSelection.insert(allSearches[i].id)
        }
    }

    /// Delete all selected smart searches
    private func deleteSelectedSmartSearches() {
        // Clear main selection if any selected search is being deleted
        if case .smartSearch(let selected) = selection,
           searchMultiSelection.contains(selected.id) {
            selection = nil
        }

        // Delete all selected smart searches
        for smartSearch in explorationSmartSearches where searchMultiSelection.contains(smartSearch.id) {
            SmartSearchRepository.shared.delete(smartSearch)
        }

        searchMultiSelection.removeAll()
        lastSelectedSearchID = nil
        explorationRefreshTrigger = UUID()
    }

    /// Delete all selected exploration collections
    private func deleteSelectedExplorationCollections() {
        // Clear main selection if any selected collection is being deleted
        if case .collection(let selected) = selection,
           explorationMultiSelection.contains(selected.id) {
            selection = nil
        }

        // Delete all selected collections
        if let library = libraryManager.explorationLibrary,
           let collections = library.collections {
            for collection in collections where explorationMultiSelection.contains(collection.id) {
                libraryManager.deleteExplorationCollection(collection)
            }
        }

        explorationMultiSelection.removeAll()
        lastSelectedExplorationID = nil
        explorationRefreshTrigger = UUID()
    }

    /// Determine the SF Symbol icon for an exploration collection based on its name prefix.
    ///
    /// - "Refs:" → arrow.down.doc (papers this paper cites)
    /// - "Cites:" → arrow.up.doc (papers citing this paper)
    /// - "Similar:" → doc.on.doc (related papers by content)
    /// - "Co-Reads:" → person.2.fill (papers frequently read together)
    private func explorationIcon(for collection: CDCollection) -> String {
        if collection.name.hasPrefix("Refs:") { return "arrow.down.doc" }
        if collection.name.hasPrefix("Cites:") { return "arrow.up.doc" }
        if collection.name.hasPrefix("Similar:") { return "doc.on.doc" }
        if collection.name.hasPrefix("Co-Reads:") { return "person.2.fill" }
        return "doc.text.magnifyingglass"
    }

    /// Check if this collection is the last child of its parent.
    private func isLastChild(_ collection: CDCollection, in allCollections: [CDCollection]) -> Bool {
        guard let parentID = collection.parentCollection?.id else {
            // Root level - check if it's the last root
            let rootCollections = allCollections.filter { $0.parentCollection == nil }
            return rootCollections.last?.id == collection.id
        }

        // Find siblings (children of the same parent)
        let siblings = allCollections.filter { $0.parentCollection?.id == parentID }
        return siblings.last?.id == collection.id
    }

    /// Check if an ancestor at the given depth level has siblings after it.
    /// Used to determine whether to draw a vertical tree line at that level.
    private func hasAncestorSiblingBelow(_ collection: CDCollection, at level: Int, in allCollections: [CDCollection]) -> Bool {
        // Walk up the tree to the ancestor at the specified level
        var current: CDCollection? = collection
        var currentLevel = Int(collection.depth)

        while currentLevel > level, let c = current {
            current = c.parentCollection
            currentLevel -= 1
        }

        // Check if this ancestor has siblings below it
        guard let ancestor = current else { return false }
        return !isLastChild(ancestor, in: allCollections)
    }

    /// Flatten collection hierarchy into a list with proper ordering
    private func flattenedExplorationCollections(from collections: Set<CDCollection>) -> [CDCollection] {
        var result: [CDCollection] = []

        func addWithChildren(_ collection: CDCollection) {
            result.append(collection)
            for child in collection.sortedChildren {
                addWithChildren(child)
            }
        }

        // Start with root collections
        for collection in Array(collections).filter({ $0.parentCollection == nil }).sorted(by: { $0.name < $1.name }) {
            addWithChildren(collection)
        }

        return result
    }

    /// Filter flattened collections to show only visible ones based on expanded state.
    /// A collection is visible if all its ancestors are expanded.
    private func filterVisibleCollections(_ collections: [CDCollection]) -> [CDCollection] {
        collections.filter { collection in
            // Root collections are always visible
            guard collection.parentCollection != nil else { return true }

            // Check if all ancestors are expanded
            for ancestor in collection.ancestors {
                if !expandedExplorationCollections.contains(ancestor.id) {
                    return false
                }
            }
            return true
        }
    }

    /// Row for an exploration collection (with tree lines and type-specific icons)
    /// Uses Finder-style selection: Option+click to toggle, Shift+click for range
    @ViewBuilder
    private func explorationCollectionRow(_ collection: CDCollection, allCollections: [CDCollection]) -> some View {
        let isMultiSelected = explorationMultiSelection.contains(collection.id)
        let depth = Int(collection.depth)
        let isLast = isLastChild(collection, in: allCollections)

        HStack(spacing: 0) {
            // Tree lines for each level
            if depth > 0 {
                ForEach(0..<depth, id: \.self) { level in
                    if level == depth - 1 {
                        // Final level: draw └ or ├
                        Text(isLast ? "└" : "├")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.quaternary)
                            .frame(width: 12)
                    } else {
                        // Parent levels: draw │ if siblings below, else space
                        if hasAncestorSiblingBelow(collection, at: level, in: allCollections) {
                            Text("│")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.quaternary)
                                .frame(width: 12)
                        } else {
                            Spacer().frame(width: 12)
                        }
                    }
                }
            }

            // Type-specific icon
            Image(systemName: explorationIcon(for: collection))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.trailing, 4)

            // Collection name
            Text(collection.name)
                .lineLimit(1)

            Spacer()

            if collection.matchingPublicationCount > 0 {
                CountBadge(count: collection.matchingPublicationCount)
            }
        }
        .contentShape(Rectangle())
        // Visual feedback for multi-selection
        .listRowBackground(
            isMultiSelected
                ? Color.accentColor.opacity(0.2)
                : nil
        )
        .gesture(
            TapGesture()
                .modifiers(.option)
                .onEnded { _ in
                    // Option+click: Toggle selection
                    if explorationMultiSelection.contains(collection.id) {
                        explorationMultiSelection.remove(collection.id)
                    } else {
                        explorationMultiSelection.insert(collection.id)
                    }
                    lastSelectedExplorationID = collection.id
                }
        )
        .simultaneousGesture(
            TapGesture()
                .modifiers(.shift)
                .onEnded { _ in
                    // Shift+click: Range selection
                    handleShiftClick(collection: collection, allCollections: allCollections)
                }
        )
        .onTapGesture {
            // Normal click: Clear multi-selection and navigate
            explorationMultiSelection.removeAll()
            explorationMultiSelection.insert(collection.id)
            lastSelectedExplorationID = collection.id
            selection = .collection(collection)
        }
        .tag(SidebarSection.collection(collection))
        .contextMenu {
            if explorationMultiSelection.count > 1 && explorationMultiSelection.contains(collection.id) {
                // Multi-selection context menu
                Button("Delete \(explorationMultiSelection.count) Items", role: .destructive) {
                    deleteSelectedExplorationCollections()
                }
            } else {
                // Single item context menu
                Button("Delete", role: .destructive) {
                    deleteExplorationCollection(collection)
                }
            }
        }
    }

    /// Handle Shift+click for range selection in exploration section
    private func handleShiftClick(collection: CDCollection, allCollections: [CDCollection]) {
        guard let lastID = lastSelectedExplorationID,
              let lastIndex = allCollections.firstIndex(where: { $0.id == lastID }),
              let currentIndex = allCollections.firstIndex(where: { $0.id == collection.id }) else {
            // No previous selection, just select this one
            explorationMultiSelection.insert(collection.id)
            lastSelectedExplorationID = collection.id
            return
        }

        // Select range from last to current
        let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
        for i in range {
            explorationMultiSelection.insert(allCollections[i].id)
        }
    }

    /// Delete an exploration collection
    private func deleteExplorationCollection(_ collection: CDCollection) {
        // Clear selection if this collection is selected
        if case .collection(let selected) = selection, selected.id == collection.id {
            selection = nil
        }

        libraryManager.deleteExplorationCollection(collection)
        explorationRefreshTrigger = UUID()
    }

    /// Expand all ancestors of a collection to make it visible in the tree
    private func expandAncestors(of collection: CDCollection) {
        for ancestor in collection.ancestors {
            expandedExplorationCollections.insert(ancestor.id)
        }
    }

    // MARK: - Section Reordering

    /// Handle drag-and-drop reordering of sections
    private func moveSections(from source: IndexSet, to destination: Int) {
        withAnimation {
            sectionOrder.move(fromOffsets: source, toOffset: destination)
        }
        Task {
            await SidebarSectionOrderStore.shared.save(sectionOrder)
        }
    }

    // MARK: - Library Disclosure Group

    @ViewBuilder
    private func libraryDisclosureGroup(for library: CDLibrary) -> some View {
        DisclosureGroup(
            isExpanded: expansionBinding(for: library.id)
        ) {
            // All Publications - drop target for moving papers to library
            SidebarDropTarget(
                isTargeted: dropTargetedLibrary == library.id,
                showPlusBadge: true
            ) {
                Label("All Publications", systemImage: "books.vertical")
            }
            .tag(SidebarSection.library(library))
            .onDrop(of: [.publicationID], isTargeted: makeLibraryTargetBinding(library.id)) { providers in
                handleDrop(providers: providers) { uuids in
                    Task {
                        await addPublicationsToLibrary(uuids, library: library)
                    }
                }
                return true
            }

            // Smart Searches for this library (use repository for change observation)
            let librarySmartSearches = smartSearchRepository.smartSearches.filter { $0.library?.id == library.id }
            if !librarySmartSearches.isEmpty {
                ForEach(librarySmartSearches.sorted(by: { $0.name < $1.name }), id: \.id) { smartSearch in
                    SmartSearchRow(smartSearch: smartSearch, count: resultCount(for: smartSearch))
                        .tag(SidebarSection.smartSearch(smartSearch))
                        .contextMenu {
                            Button("Edit") {
                                // Navigate to Search section with this smart search's query
                                NotificationCenter.default.post(name: .editSmartSearch, object: smartSearch.id)
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
                    collectionDropTarget(for: collection)
                        .tag(SidebarSection.collection(collection))
                        .contextMenu {
                            Button("Rename") {
                                renamingCollection = collection
                            }
                            if collection.isSmartCollection {
                                Button("Edit") {
                                    editingCollection = collection
                                }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                deleteCollection(collection)
                            }
                        }
                }
            }

            // Add buttons for smart search and collection
            Menu {
                Button {
                    // Navigate to Search section for creating new smart search
                    NotificationCenter.default.post(name: .navigateToSearchSection, object: library.id)
                } label: {
                    Label("New Smart Search", systemImage: "magnifyingglass.circle")
                }
                Button {
                    newSmartCollectionLibrary = library
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
            // Library header - also a drop target
            // Clicking the header selects "All Publications" and expands the library
            libraryHeaderDropTarget(for: library)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Select this library's "All Publications"
                    selection = .library(library)
                    // Expand if not already expanded
                    if !expandedLibraries.contains(library.id) {
                        expandedLibraries.insert(library.id)
                    }
                }
                .contextMenu {
                    Button("Delete Library", role: .destructive) {
                        libraryToDelete = library
                        showDeleteConfirmation = true
                    }
                }
        }
    }

    // MARK: - SciX Libraries Section Header

    /// Section header for SciX Libraries with help tooltip
    private var scixLibrariesSectionHeader: some View {
        HStack {
            Text("SciX Libraries")

            Spacer()

            // Help button that opens SciX libraries documentation
            Button {
                if let url = URL(string: "https://ui.adsabs.harvard.edu/help/libraries/") {
                    #if os(macOS)
                    NSWorkspace.shared.open(url)
                    #else
                    UIApplication.shared.open(url)
                    #endif
                }
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Learn about SciX Libraries - click to open help page")
        }
        .help("""
            SciX Libraries are cloud-based collections synced with NASA ADS/SciX.

            • Access your libraries from any device
            • Share and collaborate with other researchers
            • Set operations: union, intersection, difference
            • Citation helper finds related papers

            Click the ? to learn more.
            """)
    }

    // MARK: - SciX Library Row

    @ViewBuilder
    private func scixLibraryRow(for library: CDSciXLibrary) -> some View {
        HStack {
            // Cloud icon (different from local libraries)
            Image(systemName: "cloud")
                .foregroundColor(.blue)
                .help("Cloud-synced library from NASA ADS/SciX")

            Text(library.displayName)

            Spacer()

            // Permission level indicator
            Image(systemName: library.permissionLevelEnum.icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .help(permissionTooltip(library.permissionLevelEnum))

            // Pending changes indicator
            if library.hasPendingChanges {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .help("Changes pending sync to SciX")
            }

            // Paper count
            if library.documentCount > 0 {
                CountBadge(count: Int(library.documentCount))
            }
        }
        .tag(SidebarSection.scixLibrary(library))
        .contextMenu {
            Button {
                // Open library on SciX/ADS web interface
                if let url = URL(string: "https://ui.adsabs.harvard.edu/user/libraries/\(library.remoteID)") {
                    #if os(macOS)
                    NSWorkspace.shared.open(url)
                    #else
                    UIApplication.shared.open(url)
                    #endif
                }
            } label: {
                Label("Open on SciX", systemImage: "safari")
            }

            Button {
                Task {
                    try? await SciXSyncManager.shared.pullLibraryPapers(libraryID: library.remoteID)
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            if library.canManagePermissions {
                Button {
                    // TODO: Show permissions sheet
                } label: {
                    Label("Share...", systemImage: "person.2")
                }
            }

            if library.permissionLevelEnum == .owner {
                Divider()
                Button(role: .destructive) {
                    // TODO: Show delete confirmation
                } label: {
                    Label("Delete Library", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Library Header Drop Target

    @ViewBuilder
    private func libraryHeaderDropTarget(for library: CDLibrary) -> some View {
        let count = publicationCount(for: library)
        SidebarDropTarget(
            isTargeted: dropTargetedLibraryHeader == library.id,
            showPlusBadge: true
        ) {
            HStack {
                Label(library.displayName, systemImage: "building.columns")
                Spacer()
                if count > 0 {
                    CountBadge(count: count)
                }
            }
        }
        .onDrop(of: [.publicationID], isTargeted: makeLibraryHeaderTargetBinding(library.id)) { providers in
            // Auto-expand collapsed library when dropping on header
            if !expandedLibraries.contains(library.id) {
                expandedLibraries.insert(library.id)
            }
            handleDrop(providers: providers) { uuids in
                Task {
                    await addPublicationsToLibrary(uuids, library: library)
                }
            }
            return true
        }
    }

    // MARK: - Collection Drop Target

    @ViewBuilder
    private func collectionDropTarget(for collection: CDCollection) -> some View {
        let count = publicationCount(for: collection)
        let isEditing = renamingCollection?.id == collection.id
        if collection.isSmartCollection {
            // Smart collections don't accept drops
            CollectionRow(
                collection: collection,
                count: count,
                isEditing: isEditing,
                onRename: { newName in renameCollection(collection, to: newName) }
            )
        } else {
            // Static collections accept drops
            SidebarDropTarget(
                isTargeted: dropTargetedCollection == collection.id,
                showPlusBadge: true
            ) {
                CollectionRow(
                    collection: collection,
                    count: count,
                    isEditing: isEditing,
                    onRename: { newName in renameCollection(collection, to: newName) }
                )
            }
            .onDrop(of: [.publicationID], isTargeted: makeCollectionTargetBinding(collection.id)) { providers in
                handleDrop(providers: providers) { uuids in
                    Task {
                        await addPublications(uuids, to: collection)
                    }
                }
                return true
            }
        }
    }

    // MARK: - Drop Target Bindings

    private func makeLibraryTargetBinding(_ libraryID: UUID) -> Binding<Bool> {
        Binding(
            get: { dropTargetedLibrary == libraryID },
            set: { isTargeted in
                dropTargetedLibrary = isTargeted ? libraryID : nil
            }
        )
    }

    private func makeLibraryHeaderTargetBinding(_ libraryID: UUID) -> Binding<Bool> {
        Binding(
            get: { dropTargetedLibraryHeader == libraryID },
            set: { isTargeted in
                dropTargetedLibraryHeader = isTargeted ? libraryID : nil
                // Auto-expand after hovering for a moment
                if isTargeted && !expandedLibraries.contains(libraryID) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if dropTargetedLibraryHeader == libraryID {
                            expandedLibraries.insert(libraryID)
                        }
                    }
                }
            }
        )
    }

    private func makeCollectionTargetBinding(_ collectionID: UUID) -> Binding<Bool> {
        Binding(
            get: { dropTargetedCollection == collectionID },
            set: { isTargeted in
                dropTargetedCollection = isTargeted ? collectionID : nil
            }
        )
    }

    // MARK: - Drop Handler

    private func handleDrop(providers: [NSItemProvider], action: @escaping ([UUID]) -> Void) {
        var collectedUUIDs: [UUID] = []
        let group = DispatchGroup()

        for provider in providers {
            // Try to load as our custom publication ID type
            if provider.hasItemConformingToTypeIdentifier(UTType.publicationID.identifier) {
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: UTType.publicationID.identifier) { data, error in
                    defer { group.leave() }
                    if let data = data {
                        // UUID is encoded as JSON via CodableRepresentation
                        if let uuid = try? JSONDecoder().decode(UUID.self, from: data) {
                            collectedUUIDs.append(uuid)
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) {
            if !collectedUUIDs.isEmpty {
                action(collectedUUIDs)
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

    // MARK: - Inbox Section

    /// Inbox section content (without Section wrapper)
    @ViewBuilder
    private var inboxSectionContent: some View {
        // Inbox header with unread badge
        HStack {
            Label("All Publications", systemImage: "tray.full")
            Spacer()
            if inboxUnreadCount > 0 {
                Text("\(inboxUnreadCount)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .tag(SidebarSection.inbox)

        // Inbox feeds (smart searches with feedsToInbox)
        ForEach(inboxFeeds, id: \.id) { feed in
            HStack {
                Label(feed.name, systemImage: "antenna.radiowaves.left.and.right")
                    .help(tooltipForFeed(feed))
                Spacer()
                // Show unread count for this feed
                let unreadCount = unreadCountForFeed(feed)
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            .tag(SidebarSection.inboxFeed(feed))
            .contextMenu {
                Button("Refresh Now") {
                    Task {
                        await refreshInboxFeed(feed)
                    }
                }
                Button("Edit") {
                    // Check feed type and route to appropriate editor
                    if feed.isGroupFeed {
                        // Navigate to Group arXiv Feed form
                        selection = .searchForm(.arxivGroupFeed)
                        // Delay notification to ensure view is mounted
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NotificationCenter.default.post(name: .editGroupArXivFeed, object: feed)
                        }
                    } else if isArXivCategoryFeed(feed) {
                        // Navigate to arXiv Feed form
                        selection = .searchForm(.arxivFeed)
                        // Delay notification to ensure view is mounted
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            NotificationCenter.default.post(name: .editArXivFeed, object: feed)
                        }
                    } else {
                        // Navigate to Search section with this feed's query
                        NotificationCenter.default.post(name: .editSmartSearch, object: feed.id)
                    }
                }
                Divider()
                Button("Remove from Inbox", role: .destructive) {
                    removeFromInbox(feed)
                }
            }
        }
    }

    /// Get all smart searches that feed to the Inbox
    private var inboxFeeds: [CDSmartSearch] {
        // Fetch all smart searches with feedsToInbox enabled
        let request = NSFetchRequest<CDSmartSearch>(entityName: "SmartSearch")
        request.predicate = NSPredicate(format: "feedsToInbox == YES")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            return try PersistenceController.shared.viewContext.fetch(request)
        } catch {
            return []
        }
    }

    /// Get unread count for the Inbox
    private var inboxUnreadCount: Int {
        InboxManager.shared.unreadCount
    }

    /// Get unread count for a specific inbox feed
    private func unreadCountForFeed(_ feed: CDSmartSearch) -> Int {
        guard let collection = feed.resultCollection,
              let publications = collection.publications else {
            return 0
        }
        return publications.filter { !$0.isRead && !$0.isDeleted }.count
    }

    /// Generate tooltip text for a feed
    private func tooltipForFeed(_ feed: CDSmartSearch) -> String {
        if feed.isGroupFeed {
            // Group feed: show authors and categories
            let authors = feed.groupFeedAuthors()
            let categories = feed.groupFeedCategories()

            var lines: [String] = []

            if !authors.isEmpty {
                lines.append("Authors:")
                for author in authors {
                    lines.append("  • \(author)")
                }
            }

            if !categories.isEmpty {
                if !lines.isEmpty { lines.append("") }
                lines.append("Categories:")
                for category in categories.sorted() {
                    lines.append("  • \(category)")
                }
            }

            return lines.isEmpty ? "Group feed" : lines.joined(separator: "\n")
        } else if isArXivCategoryFeed(feed) {
            // arXiv category feed: show categories from query
            let categories = parseArXivCategories(from: feed.query)
            if categories.isEmpty {
                return "arXiv category feed"
            }
            var lines = ["Categories:"]
            for category in categories.sorted() {
                lines.append("  • \(category)")
            }
            return lines.joined(separator: "\n")
        } else {
            // Regular smart search: show query
            return "Query: \(feed.query)"
        }
    }

    /// Parse arXiv categories from a category feed query
    private func parseArXivCategories(from query: String) -> [String] {
        // Category feeds typically have queries like: cat:astro-ph.GA OR cat:astro-ph.CO
        var categories: [String] = []
        let pattern = #"cat:([a-zA-Z\-]+\.[A-Z]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(query.startIndex..., in: query)
            let matches = regex.matches(in: query, options: [], range: range)
            for match in matches {
                if let catRange = Range(match.range(at: 1), in: query) {
                    categories.append(String(query[catRange]))
                }
            }
        }
        return categories
    }

    /// Refresh a specific inbox feed
    private func refreshInboxFeed(_ feed: CDSmartSearch) async {
        guard let scheduler = await InboxCoordinator.shared.scheduler else { return }
        do {
            _ = try await scheduler.refreshFeed(feed)
            await MainActor.run {
                refreshTrigger = UUID()
            }
        } catch {
            // Handle error silently for now
        }
    }

    /// Remove a feed from Inbox (disable feedsToInbox)
    private func removeFromInbox(_ feed: CDSmartSearch) {
        feed.feedsToInbox = false
        feed.autoRefreshEnabled = false
        try? feed.managedObjectContext?.save()
        refreshTrigger = UUID()
    }

    /// Check if a feed is an arXiv category feed (query contains only cat: patterns)
    private func isArXivCategoryFeed(_ feed: CDSmartSearch) -> Bool {
        let query = feed.query
        // arXiv feeds use only "arxiv" source and have cat: patterns in their query
        guard feed.sources == ["arxiv"] else { return false }
        guard query.contains("cat:") else { return false }

        // Check that the query is primarily category-based (no search terms like ti:, au:, abs:)
        let hasSearchTerms = query.contains("ti:") || query.contains("au:") ||
                             query.contains("abs:") || query.contains("co:") ||
                             query.contains("jr:") || query.contains("rn:") ||
                             query.contains("id:") || query.contains("doi:")
        return !hasSearchTerms
    }

    // MARK: - Helpers

    /// Convert permission level to tooltip string
    private func permissionTooltip(_ level: CDSciXLibrary.PermissionLevel) -> String {
        switch level {
        case .owner: return "Owner"
        case .admin: return "Admin"
        case .write: return "Can edit"
        case .read: return "Read only"
        }
    }

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
        case .inbox:
            return InboxManager.shared.inboxLibrary
        case .inboxFeed(let feed):
            return feed.library ?? InboxManager.shared.inboxLibrary
        case .library(let library):
            return library
        case .smartSearch(let smartSearch):
            return smartSearch.library
        case .collection(let collection):
            return collection.library
        default:
            return nil
        }
    }

    private func publicationCount(for library: CDLibrary) -> Int {
        allPublications(for: library).count
    }

    /// Get all publications for a library.
    ///
    /// Simplified: All papers are in `library.publications` (smart search results included).
    private func allPublications(for library: CDLibrary) -> Set<CDPublication> {
        (library.publications ?? []).filter { !$0.isDeleted }
    }

    private func publicationCount(for collection: CDCollection) -> Int {
        // Use matchingPublicationCount which handles both static and smart collections
        collection.matchingPublicationCount
    }

    private func resultCount(for smartSearch: CDSmartSearch) -> Int {
        smartSearch.resultCollection?.publications?.count ?? 0
    }

    // MARK: - Smart Search Management

    private func deleteSmartSearch(_ smartSearch: CDSmartSearch) {
        // Clear selection BEFORE deletion to prevent accessing deleted object
        if case .smartSearch(let selected) = selection, selected.id == smartSearch.id {
            selection = nil
        }

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

        // Trigger sidebar refresh to show the new collection
        await MainActor.run {
            refreshTrigger = UUID()
        }
    }

    private func createStaticCollection(in library: CDLibrary) {
        let context = library.managedObjectContext ?? PersistenceController.shared.viewContext
        let collection = CDCollection(context: context)
        collection.id = UUID()
        collection.name = "New Collection"
        collection.isSmartCollection = false
        collection.library = library
        try? context.save()

        // Trigger sidebar refresh and enter rename mode
        refreshTrigger = UUID()
        renamingCollection = collection
    }

    private func renameCollection(_ collection: CDCollection, to newName: String) {
        guard !newName.isEmpty else {
            renamingCollection = nil
            return
        }
        collection.name = newName
        try? collection.managedObjectContext?.save()
        renamingCollection = nil
        refreshTrigger = UUID()
    }

    private func updateCollection(_ collection: CDCollection, name: String, predicate: String) async {
        collection.name = name
        collection.predicate = predicate
        try? collection.managedObjectContext?.save()
    }

    private func deleteCollection(_ collection: CDCollection) {
        // Clear selection BEFORE deletion to prevent accessing deleted object
        if case .collection(let selected) = selection, selected.id == collection.id {
            selection = nil
        }

        guard let context = collection.managedObjectContext else { return }
        context.delete(collection)
        try? context.save()
    }

    // MARK: - Library Management

    private func deleteLibrary(_ library: CDLibrary) {
        // Clear selection BEFORE deletion if ANY item from this library is selected
        if let currentSelection = selection {
            switch currentSelection {
            case .inbox, .inboxFeed:
                break  // Inbox is not affected by library deletion
            case .library(let lib):
                if lib.id == library.id { selection = nil }
            case .smartSearch(let ss):
                if ss.library?.id == library.id { selection = nil }
            case .collection(let col):
                if col.library?.id == library.id { selection = nil }
            case .search, .searchForm, .scixLibrary:
                break  // Not affected by library deletion
            }
        }

        try? libraryManager.deleteLibrary(library, deleteFiles: false)
    }

    // MARK: - Drop Handlers

    /// Add publications to a static collection (also adds to the collection's owning library)
    private func addPublications(_ uuids: [UUID], to collection: CDCollection) async {
        guard !collection.isSmartCollection else { return }
        let context = PersistenceController.shared.viewContext

        await context.perform {
            for uuid in uuids {
                let request = NSFetchRequest<CDPublication>(entityName: "Publication")
                request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
                request.fetchLimit = 1

                if let publication = try? context.fetch(request).first {
                    // Add to collection
                    var current = collection.publications ?? []
                    current.insert(publication)
                    collection.publications = current

                    // Also add to the collection's library
                    if let collectionLibrary = collection.effectiveLibrary {
                        publication.addToLibrary(collectionLibrary)
                    }
                }
            }
            try? context.save()
        }

        // Trigger sidebar refresh to update counts
        await MainActor.run {
            refreshTrigger = UUID()
        }
    }

    /// Add publications to a library (publications can belong to multiple libraries)
    private func addPublicationsToLibrary(_ uuids: [UUID], library: CDLibrary) async {
        let context = PersistenceController.shared.viewContext

        await context.perform {
            for uuid in uuids {
                let request = NSFetchRequest<CDPublication>(entityName: "Publication")
                request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
                request.fetchLimit = 1

                if let publication = try? context.fetch(request).first {
                    publication.addToLibrary(library)
                }
            }
            try? context.save()
        }

        // Trigger sidebar refresh to update counts
        await MainActor.run {
            refreshTrigger = UUID()
        }
    }
}

// MARK: - Count Badge

struct CountBadge: View {
    let count: Int
    var color: Color = .secondary

    var body: some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// MARK: - Smart Search Row

struct SmartSearchRow: View {
    let smartSearch: CDSmartSearch
    var count: Int = 0

    var body: some View {
        HStack {
            Label(smartSearch.name, systemImage: "magnifyingglass.circle.fill")
                .help(smartSearch.query)  // Show query on hover
            Spacer()
            if count > 0 {
                CountBadge(count: count)
            }
        }
    }
}

// MARK: - Collection Row

struct CollectionRow: View {
    @ObservedObject var collection: CDCollection
    var count: Int = 0
    var isEditing: Bool = false
    var onRename: ((String) -> Void)?

    @State private var editedName: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Label {
                if isEditing {
                    TextField("Collection Name", text: $editedName)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onSubmit {
                            onRename?(editedName)
                        }
                        .onAppear {
                            editedName = collection.name
                            isFocused = true
                        }
                } else {
                    Text(collection.name)
                }
            } icon: {
                Image(systemName: collection.isSmartCollection ? "folder.badge.gearshape" : "folder")
                    .help(collection.isSmartCollection ? "Smart collection - auto-populated by filter rules" : "Collection")
            }
            Spacer()
            if count > 0 {
                CountBadge(count: count)
            }
        }
    }
}

// MARK: - Sidebar Drop Target

/// A view wrapper that provides visual feedback for drag and drop targets
struct SidebarDropTarget<Content: View>: View {
    let isTargeted: Bool
    let showPlusBadge: Bool
    @ViewBuilder let content: () -> Content

    init(
        isTargeted: Bool,
        showPlusBadge: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isTargeted = isTargeted
        self.showPlusBadge = showPlusBadge
        self.content = content
    }

    var body: some View {
        HStack(spacing: 0) {
            content()

            Spacer()

            // Green plus badge when targeted
            if isTargeted && showPlusBadge {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isTargeted ? Color.accentColor.opacity(0.2) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isTargeted ? Color.accentColor : .clear, lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .contentShape(Rectangle())
    }
}

// MARK: - New Library Sheet

#if os(macOS)
enum LibraryStorageType: String, CaseIterable {
    case iCloud = "iCloud"
    case local = "Local Folder"
}
#endif

struct NewLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryManager.self) private var libraryManager

    @State private var name = ""
    #if os(macOS)
    @State private var storageType: LibraryStorageType = .iCloud
    @State private var selectedFolderURL: URL?
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section("Library Name") {
                    TextField("Name", text: $name, prompt: Text("My Library"))
                }

                #if os(macOS)
                Section("Storage") {
                    Picker("Storage", selection: $storageType) {
                        ForEach(LibraryStorageType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if storageType == .iCloud {
                        Text("Library will sync across your devices via iCloud")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if storageType == .local {
                    Section("Location") {
                        HStack {
                            if let url = selectedFolderURL {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.secondary)
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                            }
                            Button(selectedFolderURL == nil ? "Choose Folder..." : "Change...") {
                                chooseFolder()
                            }
                        }
                        Text("Select a folder to store your library files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                #endif
            }
            .navigationTitle("New Library")
            #if os(macOS)
            .frame(minWidth: 380, minHeight: storageType == .local ? 280 : 200)
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
                    .disabled(!canCreate)
                }
            }
        }
    }

    private var canCreate: Bool {
        guard !name.isEmpty else { return false }
        #if os(macOS)
        if storageType == .local {
            return selectedFolderURL != nil
        }
        #endif
        return true
    }

    #if os(macOS)
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a folder for your library"

        if panel.runModal() == .OK {
            selectedFolderURL = panel.url
        }
    }
    #endif

    private func createLibrary() {
        let libraryName = name.isEmpty ? "New Library" : name

        #if os(macOS)
        if storageType == .iCloud {
            // iCloud: Create in Core Data (synced via CloudKit)
            _ = libraryManager.createLibrary(name: libraryName)
        } else if let url = selectedFolderURL {
            // Local: Create with file-based storage
            let bibURL = url.appendingPathComponent("\(libraryName).bib")
            _ = libraryManager.createLibrary(
                name: libraryName,
                bibFileURL: bibURL,
                papersDirectoryURL: url.appendingPathComponent("Papers")
            )
        }
        #else
        // On iOS, always create iCloud library
        _ = libraryManager.createLibrary(name: libraryName)
        #endif

        dismiss()
    }
}

#Preview {
    SidebarView(selection: .constant(nil), expandedLibraries: .constant([]))
        .environment(LibraryManager(persistenceController: .preview))
}
