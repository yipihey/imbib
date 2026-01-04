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
            } else if viewModel.papers.isEmpty {
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
        List(viewModel.papers, id: \.uuid, selection: $multiSelection) { paper in
            UnifiedPaperRow(
                paper: paper,
                showLibraryIndicator: false, // Already in library
                showSourceBadges: false      // Local papers don't need source badges
            )
            .tag(paper.uuid)
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
               let paper = viewModel.papers.first(where: { $0.uuid == first }) {
                openPDF(for: paper)
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
               let paper = viewModel.papers.first(where: { $0.uuid == first }) {
                openPDF(for: paper)
            }
        }

        Button("Copy Cite Key") {
            if let first = ids.first,
               let paper = viewModel.papers.first(where: { $0.uuid == first }) {
                copyToClipboard(paper.citeKey)
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

    private func openPDF(for paper: LocalPaper) {
        // TODO: Implement PDF opening
        // paper.primaryPDFPath contains the relative path if available
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
    LibraryListView(selection: .constant(nil))
        .environment(LibraryViewModel())
}
