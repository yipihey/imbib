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

    func getOrCreate(for smartSearch: CDSmartSearch, sourceManager: SourceManager) -> SmartSearchProvider {
        if let existing = providers[smartSearch.id] {
            return existing
        }
        let provider = SmartSearchProvider(from: smartSearch, sourceManager: sourceManager)
        providers[smartSearch.id] = provider
        return provider
    }

    /// Invalidate cached provider (call when smart search is edited)
    func invalidate(_ id: UUID) {
        providers.removeValue(forKey: id)
    }
}

// MARK: - Smart Search Results View

struct SmartSearchResultsView: View {

    // MARK: - Properties

    let smartSearch: CDSmartSearch
    @Binding var selectedPaper: OnlinePaper?

    // MARK: - Environment

    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LibraryViewModel.self) private var libraryViewModel

    // MARK: - State

    @State private var provider: SmartSearchProvider?
    @State private var papers: [OnlinePaper] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var selectedPaperIDs: Set<String> = []
    @State private var libraryRefreshTrigger = 0

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading && papers.isEmpty {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                ContentUnavailableView {
                    Label("Search Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Retry") {
                        Task { await loadOrRefresh(forceRefresh: true) }
                    }
                }
            } else if papers.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No papers found for \"\(smartSearch.query)\"")
                )
            } else {
                List(papers, selection: $selectedPaperIDs) { paper in
                    UnifiedPaperRow(
                        paper: paper,
                        showLibraryIndicator: true,
                        showSourceBadges: true,
                        onImport: {
                            Task { await importPaper(paper) }
                        },
                        libraryCheckTrigger: libraryRefreshTrigger
                    )
                    .tag(paper.id)
                }
            }
        }
        .navigationTitle(smartSearch.name)
        .toolbar {
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
                Text("\(papers.count) results")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: smartSearch.id) {
            await loadOrRefresh(forceRefresh: false)
        }
        .onChange(of: selectedPaperIDs) { _, newValue in
            Logger.viewModels.infoCapture("[SmartSearch] selectedPaperIDs changed: \(newValue.joined(separator: ", "))", category: "selection")
            if let firstID = newValue.first {
                let found = papers.first { $0.id == firstID }
                Logger.viewModels.infoCapture("[SmartSearch] Found paper: \(found?.title ?? "nil") id: \(found?.id ?? "nil")", category: "selection")
                selectedPaper = found
            } else {
                selectedPaper = nil
            }
        }
    }

    // MARK: - Search Execution

    private func loadOrRefresh(forceRefresh: Bool) async {
        isLoading = true
        error = nil

        // Get or create cached provider
        let cachedProvider = await SmartSearchProviderCache.shared.getOrCreate(
            for: smartSearch,
            sourceManager: searchViewModel.sourceManager
        )
        provider = cachedProvider

        // Check if we have cached results
        let hasCachedResults = await cachedProvider.count > 0

        if hasCachedResults && !forceRefresh {
            // Use cached results - no network fetch
            papers = await cachedProvider.papers
            isLoading = false
            return
        }

        // No cache or force refresh - fetch from network
        do {
            try await cachedProvider.refresh()
            papers = await cachedProvider.papers
            SmartSearchRepository.shared.markExecuted(smartSearch)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Import

    private func importPaper(_ paper: OnlinePaper) async {
        // Fast local import - no network request needed
        let publication = await libraryViewModel.importPaperLocally(paper)
        Logger.viewModels.infoCapture("[SmartSearch] Imported: \(publication.citeKey)", category: "import")

        // Trigger library state re-check for all rows
        libraryRefreshTrigger += 1
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

    return NavigationStack {
        SmartSearchResultsView(smartSearch: smartSearch, selectedPaper: .constant(nil))
    }
    .environment(SearchViewModel(
        sourceManager: SourceManager(),
        deduplicationService: DeduplicationService(),
        repository: PublicationRepository()
    ))
}
