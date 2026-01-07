//
//  IOSSmartSearchResultsView.swift
//  imbib-iOS
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI
import PublicationManagerCore

/// iOS smart search results view.
struct SmartSearchResultsView: View {
    let smartSearch: CDSmartSearch
    @Binding var selectedPublication: CDPublication?

    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(SearchViewModel.self) private var searchViewModel

    @State private var publications: [CDPublication] = []
    @State private var multiSelection = Set<UUID>()
    @State private var isRefreshing = false
    @State private var errorMessage: String?

    var body: some View {
        PublicationListView(
            publications: publications,
            selection: $multiSelection,
            selectedPublication: $selectedPublication,
            library: smartSearch.library,
            allLibraries: libraryManager.libraries,
            showImportButton: false,
            showSortMenu: true,
            emptyStateMessage: "No Results",
            emptyStateDescription: "This smart search has no matching papers.",
            listID: .smartSearch(smartSearch.id),
            onDelete: { ids in
                await libraryViewModel.delete(ids: ids)
                await refreshResults()
            },
            onToggleRead: { publication in
                await libraryViewModel.toggleReadStatus(publication)
                await refreshResults()
            },
            onCopy: { ids in
                await libraryViewModel.copyToClipboard(ids)
            },
            onCut: { ids in
                await libraryViewModel.cutToClipboard(ids)
                await refreshResults()
            },
            onPaste: {
                try? await libraryViewModel.pasteFromClipboard()
                await refreshResults()
            },
            onAddToLibrary: { ids, targetLibrary in
                await libraryViewModel.addToLibrary(ids, library: targetLibrary)
                await refreshResults()
            },
            onAddToCollection: { ids, targetCollection in
                await libraryViewModel.addToCollection(ids, collection: targetCollection)
            },
            onRemoveFromAllCollections: { ids in
                await libraryViewModel.removeFromAllCollections(ids)
                await refreshResults()
            },
            onImport: nil,
            onOpenPDF: { publication in
                openPDF(for: publication)
            }
        )
        .navigationTitle(smartSearch.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refreshResults() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            }
        }
        .task(id: smartSearch.id) {
            await refreshResults()
        }
        .onChange(of: smartSearch.id) { _, _ in
            // Also trigger refresh when smart search changes (e.g., after creation)
            publications = []  // Clear immediately for visual feedback
            Task { await refreshResults() }
        }
        .onAppear {
            // Force refresh if publications are empty (new smart search)
            if publications.isEmpty {
                Task { await refreshResults() }
            }
        }
        .refreshable {
            await refreshResults()
        }
        .alert("Search Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    @MainActor
    private func refreshResults() async {
        isRefreshing = true
        defer { isRefreshing = false }

        // Get provider from cache using the app's configured source manager
        let provider = await SmartSearchProviderCache.shared.getOrCreate(
            for: smartSearch,
            sourceManager: searchViewModel.sourceManager,
            repository: searchViewModel.repository
        )

        // Refresh the provider
        do {
            try await provider.refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            print("Smart search error: \(error)")
        }

        // Get publications from the smart search's result collection
        if let collection = smartSearch.resultCollection {
            publications = (collection.publications ?? [])
                .filter { !$0.isDeleted && $0.managedObjectContext != nil }
                .sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    private func openPDF(for publication: CDPublication) {
        if let linkedFiles = publication.linkedFiles,
           let pdfFile = linkedFiles.first(where: { $0.isPDF }),
           let libraryURL = smartSearch.library?.folderURL {
            let pdfURL = libraryURL.appendingPathComponent(pdfFile.relativePath)
            _ = FileManager_Opener.shared.openFile(pdfURL)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SmartSearchResultsView(
            smartSearch: CDSmartSearch(),
            selectedPublication: .constant(nil)
        )
        .environment(LibraryViewModel())
        .environment(LibraryManager())
    }
}
