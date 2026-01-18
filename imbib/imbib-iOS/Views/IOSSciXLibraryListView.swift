//
//  IOSSciXLibraryListView.swift
//  imbib-iOS
//
//  Created by Claude on 2026-01-18.
//

import SwiftUI
import CoreData
import PublicationManagerCore

/// iOS list view for displaying papers from a SciX online library.
struct IOSSciXLibraryListView: View {

    // MARK: - Properties

    let library: CDSciXLibrary
    @Binding var selection: CDPublication?

    // MARK: - Environment

    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - State

    @State private var publications: [CDPublication] = []
    @State private var multiSelection = Set<UUID>()
    @State private var isLoading = false
    @State private var error: String?
    @State private var filterScope: FilterScope = .current

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Publications list
            if isLoading && publications.isEmpty {
                ProgressView("Loading papers...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = error {
                errorView(error)
            } else if publications.isEmpty {
                emptyView
            } else {
                publicationsList
            }
        }
        .navigationTitle(library.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    // Sync status indicator
                    syncStatusIcon

                    // Refresh button
                    Button {
                        Task {
                            await refreshFromServer()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .refreshable {
            await refreshFromServer()
        }
        .task(id: library.id) {
            loadPublications()
            // Auto-refresh if library has no cached publications but should have some
            if publications.isEmpty && library.documentCount > 0 {
                await refreshFromServer()
            }
        }
    }

    // MARK: - Sync Status Icon

    @ViewBuilder
    private var syncStatusIcon: some View {
        switch library.syncStateEnum {
        case .synced:
            Image(systemName: "checkmark.circle")
                .foregroundColor(.green)
        case .pending:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundColor(.orange)
        case .error:
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(.red)
        }
    }

    // MARK: - Publications List

    private var publicationsList: some View {
        PublicationListView(
            publications: publications,
            selection: $multiSelection,
            selectedPublication: $selection,
            library: nil,  // SciX libraries don't have a local CDLibrary
            allLibraries: libraryManager.libraries,
            showImportButton: false,
            showSortMenu: true,
            emptyStateMessage: "No Papers",
            emptyStateDescription: "This SciX library is empty.",
            listID: .scixLibrary(library.id),
            filterScope: $filterScope,
            onDelete: nil,  // SciX deletion handled via pending changes
            onAddToLibrary: { ids, targetLibrary in
                await copyToLocalLibrary(ids: ids, library: targetLibrary)
            },
            onAddToCollection: nil  // No local collections for SciX papers
        )
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task {
                    await refreshFromServer()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Papers", systemImage: "doc.text")
        } description: {
            Text("This SciX library is empty or hasn't been synced yet.")
        } actions: {
            Button("Sync Now") {
                Task {
                    await refreshFromServer()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Data Loading

    private func loadPublications() {
        // Refresh the managed object to get latest relationships from Core Data
        if let context = library.managedObjectContext {
            context.refresh(library, mergeChanges: true)
        }
        publications = Array(library.publications ?? [])
            .sorted { ($0.dateAdded) > ($1.dateAdded) }
    }

    private func refreshFromServer() async {
        isLoading = true
        error = nil

        do {
            try await SciXSyncManager.shared.pullLibraryPapers(libraryID: library.remoteID)
            loadPublications()
        } catch let scixError as SciXLibraryError {
            error = scixError.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Actions

    private func copyToLocalLibrary(ids: Set<UUID>, library: CDLibrary) async {
        // Copy selected papers to a local library
        for publication in publications where ids.contains(publication.id) {
            publication.addToLibrary(library)
        }

        try? PersistenceController.shared.viewContext.save()
    }
}
