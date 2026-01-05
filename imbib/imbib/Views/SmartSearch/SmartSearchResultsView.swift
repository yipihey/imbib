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
