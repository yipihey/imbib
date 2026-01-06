//
//  SmartSearchResultsView.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore
import OSLog

private let logger = Logger(subsystem: "com.imbib.app", category: "smartsearch")

// MARK: - Provider Cache

/// Caches SmartSearchProvider instances to avoid re-fetching when switching between views
actor SmartSearchProviderCache {
    static let shared = SmartSearchProviderCache()

    private var providers: [UUID: SmartSearchProvider] = [:]

    func getOrCreate(
        for smartSearch: CDSmartSearch,
        sourceManager: SourceManager,
        repository: PublicationRepository
    ) -> SmartSearchProvider {
        if let existing = providers[smartSearch.id] {
            return existing
        }
        let provider = SmartSearchProvider(
            from: smartSearch,
            sourceManager: sourceManager,
            repository: repository
        )
        providers[smartSearch.id] = provider
        return provider
    }

    /// Invalidate cached provider (call when smart search is edited)
    func invalidate(_ id: UUID) {
        providers.removeValue(forKey: id)
    }
}

// MARK: - Smart Search Results View

/// Displays the results of a smart search as CDPublication entities.
///
/// ADR-016: Smart search results are auto-imported as CDPublication entities
/// stored in the smart search's associated CDCollection. This provides full
/// library capabilities (editing, notes, etc.) for all search results.
struct SmartSearchResultsView: View {

    // MARK: - Properties

    let smartSearch: CDSmartSearch
    @Binding var selectedPublication: CDPublication?

    // MARK: - Environment

    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - State

    @State private var provider: SmartSearchProvider?
    @State private var isLoading = false
    @State private var error: Error?
    @State private var selectedPublicationIDs: Set<UUID> = []
    @State private var publications: [CDPublication] = []

    // MARK: - Helpers

    /// Refresh publications from the smart search's result collection
    private func refreshPublicationsList() {
        guard let collection = smartSearch.resultCollection else {
            publications = []
            return
        }
        // Filter out deleted publications (managedObjectContext becomes nil)
        publications = (collection.publications ?? [])
            .filter { $0.managedObjectContext != nil }
            .sorted { ($0.dateAdded) > ($1.dateAdded) }
    }

    /// Get the library for this smart search (from the result collection or owning library)
    private var library: CDLibrary? {
        smartSearch.resultCollection?.library ?? smartSearch.library
    }

    // MARK: - Body

    var body: some View {
        contentView
            .navigationTitle(smartSearch.name)
            .toolbar {
                toolbarContent
            }
            .task(id: smartSearch.id) {
                // Load cached publications first
                refreshPublicationsList()
                // Only auto-refresh from network if collection is empty
                if publications.isEmpty {
                    await loadOrRefresh(forceRefresh: true)
                }
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
                Task { try? await libraryViewModel.pasteFromClipboard() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectAllPublications)) { _ in
                selectAllPublications()
            }
    }

    // MARK: - Selection

    private func selectAllPublications() {
        selectedPublicationIDs = Set(publications.map { $0.id })
    }

    // MARK: - Toggle Read Status

    private func toggleReadStatusForSelected() {
        guard !selectedPublicationIDs.isEmpty else { return }

        Task {
            for uuid in selectedPublicationIDs {
                if let publication = publications.first(where: { $0.id == uuid }) {
                    await libraryViewModel.toggleReadStatus(publication)
                }
            }
        }
    }

    private func copySelectedPublications() async {
        guard !selectedPublicationIDs.isEmpty else { return }
        await libraryViewModel.copyToClipboard(selectedPublicationIDs)
    }

    private func cutSelectedPublications() async {
        guard !selectedPublicationIDs.isEmpty else { return }
        await libraryViewModel.cutToClipboard(selectedPublicationIDs)
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        if isLoading && publications.isEmpty {
            loadingView
        } else if let error {
            errorView(error)
        } else if publications.isEmpty {
            emptyView
        } else {
            listView
        }
    }

    private var loadingView: some View {
        ProgressView("Searching...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Search Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Retry") {
                Task { await loadOrRefresh(forceRefresh: true) }
            }
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "magnifyingglass")
        } description: {
            Text("No papers found for \"\(smartSearch.query)\".\nClick refresh to search.")
        } actions: {
            Button("Search Now") {
                Task { await loadOrRefresh(forceRefresh: true) }
            }
        }
    }

    private var listView: some View {
        PublicationListView(
            publications: publications,
            selection: $selectedPublicationIDs,
            selectedPublication: $selectedPublication,
            library: library,
            allLibraries: libraryManager.libraries,
            showImportButton: false,  // Smart search doesn't need import
            showSortMenu: true,
            emptyStateMessage: "No Results",
            emptyStateDescription: "No papers found for \"\(smartSearch.query)\".",
            listID: .smartSearch(smartSearch.id),
            onDelete: { ids in
                await libraryViewModel.delete(ids: ids)
                refreshPublicationsList()
            },
            onToggleRead: { publication in
                await libraryViewModel.toggleReadStatus(publication)
            },
            onCopy: { ids in
                await libraryViewModel.copyToClipboard(ids)
            },
            onCut: { ids in
                await libraryViewModel.cutToClipboard(ids)
            },
            onPaste: {
                try? await libraryViewModel.pasteFromClipboard()
            },
            onMoveToLibrary: { ids, targetLibrary in
                await libraryViewModel.moveToLibrary(ids, library: targetLibrary)
                refreshPublicationsList()
            },
            onAddToCollection: { ids, collection in
                await libraryViewModel.addToCollection(ids, collection: collection)
            },
            onOpenPDF: { publication in
                openPDF(for: publication)
            }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await loadOrRefresh(forceRefresh: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh search results")
            }
        }

        ToolbarItem(placement: .automatic) {
            Text("\(publications.count) results")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Search Execution

    private func loadOrRefresh(forceRefresh: Bool) async {
        isLoading = true
        error = nil

        // Get or create cached provider
        let cachedProvider = await SmartSearchProviderCache.shared.getOrCreate(
            for: smartSearch,
            sourceManager: searchViewModel.sourceManager,
            repository: libraryViewModel.repository
        )
        provider = cachedProvider

        // Check if we have existing results in the collection
        let hasResults = !publications.isEmpty

        if hasResults && !forceRefresh {
            // Use existing results - no network fetch
            isLoading = false
            return
        }

        // No results or force refresh - fetch from network and auto-import
        do {
            try await cachedProvider.refresh()
            await MainActor.run {
                SmartSearchRepository.shared.markExecuted(smartSearch)
                // Update the cached publications list after network fetch
                refreshPublicationsList()
            }
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Helpers

    private func openPDF(for publication: CDPublication) {
        // Open the first PDF if available
        if let linkedFiles = publication.linkedFiles,
           let pdfFile = linkedFiles.first(where: { $0.isPDF }),
           let libraryURL = library?.folderURL {
            let pdfURL = libraryURL.appendingPathComponent(pdfFile.relativePath)
            #if os(macOS)
            NSWorkspace.shared.open(pdfURL)
            #endif
        }
    }
}

#Preview {
    // Create a mock smart search for preview
    let context = PersistenceController.preview.viewContext
    let smartSearch = CDSmartSearch(context: context)
    smartSearch.id = UUID()
    smartSearch.name = "Quantum Computing"
    smartSearch.query = "quantum computing"
    smartSearch.dateCreated = Date()

    // Create a result collection
    let collection = CDCollection(context: context)
    collection.id = UUID()
    collection.name = "Quantum Computing"
    collection.isSmartSearchResults = true
    smartSearch.resultCollection = collection

    return NavigationStack {
        SmartSearchResultsView(smartSearch: smartSearch, selectedPublication: .constant(nil))
    }
    .environment(SearchViewModel(
        sourceManager: SourceManager(),
        deduplicationService: DeduplicationService(),
        repository: PublicationRepository()
    ))
    .environment(LibraryViewModel(repository: PublicationRepository()))
    .environment(LibraryManager())
}
