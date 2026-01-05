//
//  SearchView.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore

/// Displays ad-hoc search results as CDPublication entities.
///
/// ADR-016: Search results are auto-imported to the active library's "Last Search"
/// collection. This provides full library capabilities (editing, notes, etc.)
/// for all search results.
struct SearchResultsListView: View {

    // MARK: - Environment

    @Environment(SearchViewModel.self) private var viewModel
    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - State

    @State private var searchText: String = ""
    @State private var availableSources: [SourceMetadata] = []
    @FocusState private var isSearchFocused: Bool

    // MARK: - Bindings (for selection)

    @Binding var selectedPublication: CDPublication?

    // MARK: - Initialization

    init(selectedPublication: Binding<CDPublication?> = .constant(nil)) {
        self._selectedPublication = selectedPublication
    }

    // MARK: - Body

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            // Search bar and source filters
            searchHeader

            Divider()

            // Results
            resultsList
        }
        .navigationTitle("Search")
        .task {
            availableSources = await viewModel.availableSources
            // Ensure SearchViewModel has access to LibraryManager
            viewModel.setLibraryManager(libraryManager)
        }
    }

    // MARK: - Search Header

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search publications...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit {
                        performSearch()
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button("Search") {
                    performSearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchText.isEmpty)
            }
            .padding(8)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Source filter chips
            SourceFilterBar(availableSources: availableSources)
        }
        .padding()
    }

    // MARK: - Results List

    @ViewBuilder
    private var resultsList: some View {
        @Bindable var viewModel = viewModel

        if viewModel.isSearching {
            ProgressView("Searching...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.publications.isEmpty {
            emptyState
        } else {
            List(viewModel.publications, id: \.id, selection: $viewModel.selectedPublicationIDs) { publication in
                PublicationSearchRow(publication: publication)
                    .tag(publication.id)
            }
            .onChange(of: viewModel.selectedPublicationIDs) { _, newValue in
                if let firstID = newValue.first {
                    selectedPublication = viewModel.publications.first { $0.id == firstID }
                } else {
                    selectedPublication = nil
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Search Publications", systemImage: "magnifyingglass")
        } description: {
            Text("Enter a query to search across multiple sources.")
        }
    }

    // MARK: - Actions

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        Task {
            viewModel.query = searchText
            await viewModel.search()
        }
    }
}

// MARK: - Publication Search Row

/// A row for displaying a CDPublication in search results
private struct PublicationSearchRow: View {
    let publication: CDPublication

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(publication.title ?? "Untitled")
                .font(.headline)
                .lineLimit(2)

            HStack {
                Text(publication.authorString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if publication.year > 0 {
                    Text("(\(publication.year))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Show source badge if available
            if let sourceID = publication.originalSourceID {
                HStack(spacing: 4) {
                    Image(systemName: sourceIcon(for: sourceID))
                        .font(.caption)
                    Text(sourceID.capitalized)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func sourceIcon(for sourceID: String) -> String {
        switch sourceID.lowercased() {
        case "arxiv": return "doc.text"
        case "crossref": return "globe"
        case "ads": return "star"
        case "pubmed": return "cross.case"
        case "semanticscholar": return "brain"
        case "openalex": return "book"
        case "dblp": return "server.rack"
        default: return "magnifyingglass"
        }
    }
}

// MARK: - Source Filter Bar

struct SourceFilterBar: View {

    @Environment(SearchViewModel.self) private var viewModel
    let availableSources: [SourceMetadata]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableSources, id: \.id) { source in
                    SourceChip(
                        source: source,
                        isSelected: viewModel.selectedSourceIDs.contains(source.id)
                    ) {
                        viewModel.toggleSource(source.id)
                    }
                }

                Divider()
                    .frame(height: 20)

                Button("Select All") {
                    Task {
                        await viewModel.selectAllSources()
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
        }
    }
}

// MARK: - Source Chip

struct SourceChip: View {
    let source: SourceMetadata
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: source.iconName)
                    .font(.caption)
                Text(source.name)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    SearchResultsListView(selectedPublication: .constant(nil))
        .environment(SearchViewModel(
            sourceManager: SourceManager(),
            deduplicationService: DeduplicationService(),
            repository: PublicationRepository()
        ))
        .environment(LibraryManager())
}
