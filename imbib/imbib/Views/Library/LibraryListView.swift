//
//  LibraryListView.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore

/// Filter mode for library list
enum LibraryFilterMode {
    case all
    case unread
}

struct LibraryListView: View {

    // MARK: - Environment

    @Environment(LibraryViewModel.self) private var viewModel
    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - Properties

    /// The library to display publications from
    let library: CDLibrary

    @Binding var selection: CDPublication?

    /// Filter mode for the publication list
    var filterMode: LibraryFilterMode = .all

    // MARK: - State

    @State private var multiSelection = Set<UUID>()
    @State private var showUnreadOnly = false

    // MARK: - Computed Properties

    /// Publications from this library, filtered by the current filter mode
    private var libraryPublications: [CDPublication] {
        guard let publications = library.publications as? Set<CDPublication> else {
            return []
        }

        var filtered = Array(publications)

        // Apply filter mode or showUnreadOnly toggle
        if showUnreadOnly {
            filtered = filtered.filter { !$0.isRead }
        } else {
            switch filterMode {
            case .all:
                break
            case .unread:
                filtered = filtered.filter { !$0.isRead }
            }
        }

        // Apply search query if present
        if !viewModel.searchQuery.isEmpty {
            let query = viewModel.searchQuery.lowercased()
            filtered = filtered.filter { pub in
                pub.title?.lowercased().contains(query) == true ||
                pub.authorString.lowercased().contains(query) ||
                pub.citeKey.lowercased().contains(query)
            }
        }

        // Sort by the current sort order
        return filtered.sorted { lhs, rhs in
            switch viewModel.sortOrder {
            case .dateAdded:
                return lhs.dateAdded > rhs.dateAdded  // Newest first
            case .dateModified:
                return lhs.dateModified > rhs.dateModified  // Most recent first
            case .title:
                return (lhs.title ?? "") < (rhs.title ?? "")
            case .year:
                return lhs.year > rhs.year  // Newest first
            case .citeKey:
                return lhs.citeKey < rhs.citeKey
            case .citationCount:
                return lhs.citationCount > rhs.citationCount  // Most cited first
            }
        }
    }

    /// Title based on filter mode
    private var navigationTitle: String {
        switch filterMode {
        case .all: return library.displayName
        case .unread: return "Unread"
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Inline toolbar above the list
            HStack(spacing: 12) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search publications", text: Binding(
                        get: { viewModel.searchQuery },
                        set: { viewModel.searchQuery = $0 }
                    ))
                    .textFieldStyle(.plain)
                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            viewModel.searchQuery = ""
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

                // Filter button
                Button {
                    showUnreadOnly.toggle()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .foregroundStyle(showUnreadOnly ? .blue : .secondary)
                .help(showUnreadOnly ? "Show all publications" : "Show unread only")
                .buttonStyle(.plain)

                // Import button
                Button {
                    NotificationCenter.default.post(name: .importBibTeX, object: nil)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .foregroundStyle(.secondary)
                .help("Import BibTeX")
                .buttonStyle(.plain)

                // Sort menu
                Menu {
                    ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                        Button(order.displayName) {
                            viewModel.sortOrder = order
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .foregroundStyle(.secondary)
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Content
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if libraryPublications.isEmpty {
                    emptyState
                } else {
                    publicationList
                }
            }
        }
        .navigationTitle(navigationTitle)
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
            Task { try? await viewModel.pasteFromClipboard() }
        }
    }

    // MARK: - Toggle Read Status

    private func toggleReadStatusForSelected() {
        guard !multiSelection.isEmpty else { return }

        Task {
            for uuid in multiSelection {
                if let publication = libraryPublications.first(where: { $0.id == uuid }) {
                    await viewModel.toggleReadStatus(publication)
                }
            }
        }
    }

    // MARK: - Publication List

    private var publicationList: some View {
        List(libraryPublications, id: \.id, selection: $multiSelection) { publication in
            MailStylePublicationRow(
                publication: publication,
                showUnreadIndicator: true,
                onToggleRead: {
                    Task {
                        await viewModel.toggleReadStatus(publication)
                    }
                }
            )
            .tag(publication.id)
        }
        .onChange(of: multiSelection) { _, newValue in
            if let first = newValue.first {
                selection = libraryPublications.first { $0.id == first }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenuItems(for: ids)
        } primaryAction: { ids in
            // Double-click to open PDF
            if let first = ids.first,
               let publication = libraryPublications.first(where: { $0.id == first }) {
                openPDF(for: publication)
            }
        }
        #if os(macOS)
        .onDeleteCommand {
            Task { await viewModel.delete(ids: multiSelection) }
        }
        #endif
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Publications", systemImage: "books.vertical")
        } description: {
            Text("Import a BibTeX file or search online sources to add publications.")
        } actions: {
            Button("Import BibTeX...") {
                NotificationCenter.default.post(name: .importBibTeX, object: nil)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for ids: Set<UUID>) -> some View {
        // Open PDF
        Button("Open PDF") {
            if let first = ids.first,
               let publication = libraryPublications.first(where: { $0.id == first }) {
                openPDF(for: publication)
            }
        }

        Divider()

        // Copy/Cut (clipboard operations - BibTeX format)
        Button("Copy") {
            Task { await viewModel.copyToClipboard(ids) }
        }

        Button("Cut") {
            Task { await viewModel.cutToClipboard(ids) }
        }

        Button("Copy Cite Key") {
            if let first = ids.first,
               let publication = libraryPublications.first(where: { $0.id == first }) {
                copyToClipboard(publication.citeKey)
            }
        }

        Divider()

        // Move To Library submenu (direct UUID-based operation)
        Menu("Move To Library") {
            ForEach(libraryManager.libraries, id: \.id) { targetLibrary in
                if targetLibrary.id != library.id {
                    Button(targetLibrary.displayName) {
                        Task {
                            await viewModel.moveToLibrary(ids, library: targetLibrary)
                        }
                    }
                }
            }
        }

        // Add To Collection submenu (direct UUID-based operation)
        if let collections = library.collections as? Set<CDCollection>,
           !collections.isEmpty {
            let staticCollections = collections.filter { !$0.isSmartCollection }.sorted { $0.name < $1.name }
            if !staticCollections.isEmpty {
                Menu("Add To Collection") {
                    ForEach(staticCollections, id: \.id) { collection in
                        Button(collection.name) {
                            Task {
                                await viewModel.addToCollection(ids, collection: collection)
                            }
                        }
                    }
                }
            }
        }

        Divider()

        // Delete
        Button("Delete", role: .destructive) {
            Task {
                await viewModel.delete(ids: ids)
            }
        }
    }

    // MARK: - Clipboard Actions

    private func copySelectedPublications() async {
        guard !multiSelection.isEmpty else { return }
        await viewModel.copyToClipboard(multiSelection)
    }

    private func cutSelectedPublications() async {
        guard !multiSelection.isEmpty else { return }
        await viewModel.cutToClipboard(multiSelection)
    }

    // MARK: - Helpers

    private func openPDF(for publication: CDPublication) {
        // Open the first PDF if available
        if let linkedFiles = publication.linkedFiles,
           let pdfFile = linkedFiles.first(where: { $0.isPDF }),
           let libraryURL = library.folderURL {
            let pdfURL = libraryURL.appendingPathComponent(pdfFile.relativePath)
            #if os(macOS)
            NSWorkspace.shared.open(pdfURL)
            #endif
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Preview

#Preview {
    // Preview requires a CDLibrary - use preview persistence controller
    let libraryManager = LibraryManager(persistenceController: .preview)
    if let library = libraryManager.libraries.first {
        LibraryListView(library: library, selection: .constant(nil))
            .environment(LibraryViewModel())
            .environment(libraryManager)
    } else {
        Text("No library available in preview")
    }
}
