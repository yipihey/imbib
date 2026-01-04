//
//  SmartSearchResultsView.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore

struct SmartSearchResultsView: View {

    // MARK: - Properties

    let smartSearch: CDSmartSearch

    // MARK: - Environment

    @Environment(SearchViewModel.self) private var searchViewModel

    // MARK: - State

    @State private var provider: SmartSearchProvider?
    @State private var papers: [OnlinePaper] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var selectedPaperIDs: Set<String> = []

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
                        Task { await executeSearch() }
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
                        showSourceBadges: true
                    ) {
                        Task { await importPaper(paper) }
                    }
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
                        Task { await executeSearch() }
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
            await executeSearch()
        }
    }

    // MARK: - Search Execution

    private func executeSearch() async {
        isLoading = true
        error = nil

        // Create a fresh provider using the shared sourceManager
        let newProvider = SmartSearchProvider(from: smartSearch, sourceManager: searchViewModel.sourceManager)
        provider = newProvider

        do {
            try await newProvider.refresh()
            papers = await newProvider.papers
            SmartSearchRepository.shared.markExecuted(smartSearch)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Import

    private func importPaper(_ paper: OnlinePaper) async {
        // TODO: Implement paper import
        print("Would import: \(paper.title)")
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
        SmartSearchResultsView(smartSearch: smartSearch)
    }
    .environment(SearchViewModel(
        sourceManager: SourceManager(),
        deduplicationService: DeduplicationService(),
        repository: PublicationRepository()
    ))
}
