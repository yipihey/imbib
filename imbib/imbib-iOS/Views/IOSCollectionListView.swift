//
//  IOSCollectionListView.swift
//  imbib-iOS
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI
import PublicationManagerCore

// MARK: - Filter Mode (shared with macOS)

enum LibraryFilterMode: String, CaseIterable {
    case all
    case unread
}

/// iOS collection list view with swipe actions for common operations.
struct IOSCollectionListView: View {
    let collection: CDCollection
    @Binding var selection: CDPublication?

    // MARK: - Environment

    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - State

    @State private var publications: [CDPublication] = []
    @State private var multiSelection = Set<UUID>()
    @State private var filterMode: LibraryFilterMode = .all

    // MARK: - Body

    var body: some View {
        PublicationListView(
            publications: publications,
            selection: $multiSelection,
            selectedPublication: $selection,
            library: collection.owningLibrary,
            allLibraries: libraryManager.libraries,
            showImportButton: false,
            showSortMenu: true,
            emptyStateMessage: "No Publications",
            emptyStateDescription: "Add publications to this collection.",
            listID: .collection(collection.id),
            onDelete: { ids in
                await libraryViewModel.delete(ids: ids)
                refreshPublications()
            },
            onToggleRead: { publication in
                await libraryViewModel.toggleReadStatus(publication)
                refreshPublications()
            },
            onCopy: { ids in
                await libraryViewModel.copyToClipboard(ids)
            },
            onCut: { ids in
                await libraryViewModel.cutToClipboard(ids)
                refreshPublications()
            },
            onPaste: {
                try? await libraryViewModel.pasteFromClipboard()
                refreshPublications()
            },
            onAddToLibrary: { ids, targetLibrary in
                await libraryViewModel.addToLibrary(ids, library: targetLibrary)
                refreshPublications()
            },
            onAddToCollection: { ids, targetCollection in
                await libraryViewModel.addToCollection(ids, collection: targetCollection)
            },
            onRemoveFromAllCollections: { ids in
                await libraryViewModel.removeFromAllCollections(ids)
                refreshPublications()
            },
            onImport: nil,
            onOpenPDF: { publication in
                openPDF(for: publication)
            }
        )
        .navigationTitle(collection.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Filter", selection: $filterMode) {
                    Text("All").tag(LibraryFilterMode.all)
                    Text("Unread").tag(LibraryFilterMode.unread)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .task(id: collection.id) {
            refreshPublications()
        }
        .onChange(of: filterMode) { _, _ in
            refreshPublications()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleReadStatus)) { _ in
            toggleReadStatusForSelected()
        }
        .refreshable {
            refreshPublications()
        }
    }

    // MARK: - Data Refresh

    private func refreshPublications() {
        Task {
            var result: [CDPublication]

            if collection.isSmartCollection {
                // Execute predicate for smart collections
                result = await PublicationRepository.shared.executeSmartCollection(collection)
            } else {
                // For static collections, use direct relationship
                result = Array(collection.publications ?? [])
                    .filter { !$0.isDeleted && $0.managedObjectContext != nil }
            }

            if filterMode == .unread {
                result = result.filter { !$0.isRead }
            }

            publications = result.sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    // MARK: - Actions

    private func toggleReadStatusForSelected() {
        guard !multiSelection.isEmpty else { return }

        Task {
            await libraryViewModel.smartToggleReadStatus(multiSelection)
            refreshPublications()
        }
    }

    private func openPDF(for publication: CDPublication) {
        if let linkedFiles = publication.linkedFiles,
           let pdfFile = linkedFiles.first(where: { $0.isPDF }),
           let libraryURL = collection.owningLibrary?.folderURL {
            let pdfURL = libraryURL.appendingPathComponent(pdfFile.relativePath)
            _ = FileManager_Opener.shared.openFile(pdfURL)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        IOSCollectionListView(
            collection: CDCollection(),
            selection: .constant(nil)
        )
        .environment(LibraryViewModel())
        .environment(LibraryManager())
    }
}
