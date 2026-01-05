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

    // MARK: - State

    @State private var provider: SmartSearchProvider?
    @State private var isLoading = false
    @State private var error: Error?
    @State private var selectedPublicationIDs: Set<UUID> = []

    // MARK: - Computed

    /// Publications from the smart search's result collection
    private var publications: [CDPublication] {
        guard let collection = smartSearch.resultCollection else { return [] }
        return Array(collection.publications ?? [])
            .sorted { ($0.dateAdded) > ($1.dateAdded) }
    }

    // MARK: - Body

    var body: some View {
        contentView
            .navigationTitle(smartSearch.name)
            .toolbar {
                toolbarContent
            }
            .task(id: smartSearch.id) {
                // Only auto-refresh if collection is empty (first time or after clear)
                if publications.isEmpty {
                    await loadOrRefresh(forceRefresh: true)
                }
            }
            .onChange(of: selectedPublicationIDs) { _, newValue in
                handleSelectionChange(newValue)
            }
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
        List(publications, id: \.id, selection: $selectedPublicationIDs) { publication in
            MailStylePublicationRow(
                publication: publication,
                showUnreadIndicator: true,
                onToggleRead: {
                    Task {
                        await libraryViewModel.toggleReadStatus(publication)
                    }
                }
            )
            .tag(publication.id)
        }
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

    // MARK: - Selection Handling

    private func handleSelectionChange(_ newValue: Set<UUID>) {
        Logger.viewModels.infoCapture("[SmartSearch] selectedPublicationIDs changed: \(newValue.map { $0.uuidString }.joined(separator: ", "))", category: "selection")
        if let firstID = newValue.first {
            let found = publications.first { $0.id == firstID }
            Logger.viewModels.infoCapture("[SmartSearch] Found publication: \(found?.title ?? "nil")", category: "selection")
            selectedPublication = found
        } else {
            selectedPublication = nil
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
            }
        } catch {
            self.error = error
        }

        isLoading = false
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
}
