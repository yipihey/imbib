//
//  LibraryListView.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore

struct LibraryListView: View {

    // MARK: - Environment

    @Environment(LibraryViewModel.self) private var viewModel

    // MARK: - Properties

    @Binding var selection: CDPublication?

    // MARK: - State

    @State private var multiSelection = Set<UUID>()

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.publications.isEmpty {
                emptyState
            } else {
                publicationList
            }
        }
        .navigationTitle("Library")
        .toolbar {
            toolbarContent
        }
        .searchable(
            text: Binding(
                get: { viewModel.searchQuery },
                set: { viewModel.searchQuery = $0 }
            ),
            prompt: "Search publications"
        )
    }

    // MARK: - Publication List

    private var publicationList: some View {
        List(viewModel.publications, id: \.id, selection: $multiSelection) { publication in
            PublicationRow(publication: publication)
                .tag(publication.id)
        }
        .onChange(of: multiSelection) { oldValue, newValue in
            if let first = newValue.first {
                selection = viewModel.publications.first { $0.id == first }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenuItems(for: ids)
        } primaryAction: { ids in
            // Double-click to open PDF
            if let first = ids.first,
               let publication = viewModel.publications.first(where: { $0.id == first }) {
                openPDF(for: publication)
            }
        }
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                NotificationCenter.default.post(name: .importBibTeX, object: nil)
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }

            Menu {
                ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                    Button(order.displayName) {
                        viewModel.sortOrder = order
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for ids: Set<UUID>) -> some View {
        Button("Open PDF") {
            if let first = ids.first,
               let publication = viewModel.publications.first(where: { $0.id == first }) {
                openPDF(for: publication)
            }
        }

        Button("Copy Cite Key") {
            if let first = ids.first,
               let publication = viewModel.publications.first(where: { $0.id == first }) {
                copyToClipboard(publication.citeKey)
            }
        }

        Divider()

        Button("Delete", role: .destructive) {
            Task {
                await viewModel.delete(ids: ids)
            }
        }
    }

    // MARK: - Helpers

    private func openPDF(for publication: CDPublication) {
        // TODO: Implement PDF opening
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Publication Row

struct PublicationRow: View {
    let publication: CDPublication

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(publication.title ?? "Untitled")
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(formatAuthors(publication.authorString))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if publication.year > 0 {
                    Text("(\(String(publication.year)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Text(publication.entryType.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Capsule())

                if let venue = venue {
                    Text(venue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var venue: String? {
        publication.fields["journal"] ?? publication.fields["booktitle"]
    }

    private func formatAuthors(_ authors: String) -> String {
        if authors.isEmpty { return "Unknown authors" }
        let authorList = authors.components(separatedBy: ", ")
        if authorList.count > 2 {
            return "\(authorList[0]) et al."
        }
        return authors
    }
}

#Preview {
    LibraryListView(selection: .constant(nil))
        .environment(LibraryViewModel())
}
