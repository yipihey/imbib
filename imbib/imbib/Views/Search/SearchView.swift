//
//  SearchView.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore

struct SearchResultsListView: View {

    // MARK: - Environment

    @Environment(SearchViewModel.self) private var viewModel

    // MARK: - State

    @State private var searchText: String = ""
    @State private var availableSources: [SourceMetadata] = []
    @FocusState private var isSearchFocused: Bool

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
        } else if viewModel.results.isEmpty {
            emptyState
        } else {
            List(viewModel.results, selection: $viewModel.selectedResults) { result in
                SearchResultRow(result: result)
                    .tag(result.id)
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

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: DeduplicatedResult

    @Environment(SearchViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title
            Text(result.primary.title)
                .font(.headline)
                .lineLimit(2)

            // Authors
            Text(formatAuthors(result.primary.authors))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Metadata row
            HStack(spacing: 8) {
                // Source badges
                ForEach(result.sourceIDs, id: \.self) { sourceID in
                    Text(sourceID.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                }

                // Year
                if let year = result.primary.year {
                    Text("\(year)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Venue
                if let venue = result.primary.venue {
                    Text(venue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Import button
                Button {
                    Task {
                        try? await viewModel.importResult(result)
                    }
                } label: {
                    Label("Import", systemImage: "plus.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
            }

            // Abstract (if available)
            if let abstract = result.primary.abstract, !abstract.isEmpty {
                Text(abstract)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatAuthors(_ authors: [String]) -> String {
        if authors.isEmpty { return "Unknown authors" }
        if authors.count > 2 {
            return "\(authors[0]) et al."
        }
        return authors.joined(separator: ", ")
    }
}

#Preview {
    SearchResultsListView()
        .environment(SearchViewModel(
            sourceManager: SourceManager(),
            deduplicationService: DeduplicationService(),
            repository: PublicationRepository()
        ))
}
