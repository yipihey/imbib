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
    @Environment(LibraryViewModel.self) private var libraryViewModel
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

    // MARK: - Notification Handlers

    private func selectAllPublications() {
        viewModel.selectedPublicationIDs = Set(viewModel.publications.map { $0.id })
    }

    private func toggleReadStatusForSelected() {
        guard !viewModel.selectedPublicationIDs.isEmpty else { return }

        Task {
            // Apple Mail behavior: if ANY are unread, mark ALL as read
            // If ALL are read, mark ALL as unread
            await libraryViewModel.smartToggleReadStatus(viewModel.selectedPublicationIDs)
        }
    }

    private func copySelectedPublications() async {
        guard !viewModel.selectedPublicationIDs.isEmpty else { return }
        await libraryViewModel.copyToClipboard(viewModel.selectedPublicationIDs)
    }

    private func cutSelectedPublications() async {
        guard !viewModel.selectedPublicationIDs.isEmpty else { return }
        await libraryViewModel.cutToClipboard(viewModel.selectedPublicationIDs)
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

                // Send to Inbox button
                if !viewModel.publications.isEmpty {
                    Divider()
                        .frame(height: 20)

                    Button {
                        sendSelectedToInbox()
                    } label: {
                        Label("Send to Inbox", systemImage: "tray.and.arrow.down")
                    }
                    .help("Send selected publications to Inbox")
                    .disabled(viewModel.selectedPublicationIDs.isEmpty)
                }
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
            PublicationListView(
                publications: viewModel.publications,
                selection: $viewModel.selectedPublicationIDs,
                selectedPublication: $selectedPublication,
                library: libraryManager.activeLibrary,
                allLibraries: libraryManager.libraries,
                showImportButton: false,  // Search view doesn't need import
                showSortMenu: true,
                emptyStateMessage: "No Results",
                emptyStateDescription: "Enter a query to search across multiple sources.",
                listID: libraryManager.activeLibrary?.lastSearchCollection.map { .lastSearch($0.id) },
                onDelete: { ids in
                    await libraryViewModel.delete(ids: ids)
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
                onAddToLibrary: { ids, targetLibrary in
                    await libraryViewModel.addToLibrary(ids, library: targetLibrary)
                },
                onAddToCollection: { ids, collection in
                    await libraryViewModel.addToCollection(ids, collection: collection)
                },
                onRemoveFromAllCollections: { ids in
                    await libraryViewModel.removeFromAllCollections(ids)
                },
                onOpenPDF: { publication in
                    openPDF(for: publication)
                }
            )
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

    private func sendSelectedToInbox() {
        let selectedIDs = viewModel.selectedPublicationIDs
        guard !selectedIDs.isEmpty else { return }

        let inboxManager = InboxManager.shared

        // Add selected publications to Inbox
        for id in selectedIDs {
            if let publication = viewModel.publications.first(where: { $0.id == id }) {
                inboxManager.addToInbox(publication)
            }
        }

        // Clear selection after sending
        viewModel.clearSelection()
    }

    private func openPDF(for publication: CDPublication) {
        // Open the first PDF if available
        if let linkedFiles = publication.linkedFiles,
           let pdfFile = linkedFiles.first(where: { $0.isPDF }),
           let libraryURL = libraryManager.activeLibrary?.folderURL {
            let pdfURL = libraryURL.appendingPathComponent(pdfFile.relativePath)
            #if os(macOS)
            NSWorkspace.shared.open(pdfURL)
            #endif
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
        .environment(LibraryViewModel(repository: PublicationRepository()))
        .environment(LibraryManager())
}
