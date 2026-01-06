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

    // MARK: - Computed Properties

    /// Publications from this library
    private var libraryPublications: [CDPublication] {
        guard let publications = library.publications as? Set<CDPublication> else {
            return []
        }

        var filtered = Array(publications)

        // Apply filter mode (unread filter is now handled by PublicationListView's toggle)
        switch filterMode {
        case .all:
            break
        case .unread:
            filtered = filtered.filter { !$0.isRead }
        }

        return filtered
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
        PublicationListView(
            publications: libraryPublications,
            selection: $multiSelection,
            selectedPublication: $selection,
            library: library,
            allLibraries: libraryManager.libraries,
            showImportButton: true,
            showSortMenu: true,
            emptyStateMessage: "No Publications",
            emptyStateDescription: "Import a BibTeX file or search online sources to add publications.",
            onDelete: { ids in
                await viewModel.delete(ids: ids)
            },
            onToggleRead: { publication in
                await viewModel.toggleReadStatus(publication)
            },
            onCopy: { ids in
                await viewModel.copyToClipboard(ids)
            },
            onCut: { ids in
                await viewModel.cutToClipboard(ids)
            },
            onPaste: {
                try? await viewModel.pasteFromClipboard()
            },
            onMoveToLibrary: { ids, targetLibrary in
                await viewModel.moveToLibrary(ids, library: targetLibrary)
            },
            onAddToCollection: { ids, collection in
                await viewModel.addToCollection(ids, collection: collection)
            },
            onImport: {
                NotificationCenter.default.post(name: .importBibTeX, object: nil)
            },
            onOpenPDF: { publication in
                openPDF(for: publication)
            }
        )
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

    // MARK: - Notification Handlers

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
