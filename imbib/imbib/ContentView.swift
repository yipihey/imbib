//
//  ContentView.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore
import OSLog

private let contentLogger = Logger(subsystem: "com.imbib.app", category: "content")

struct ContentView: View {

    // MARK: - Environment

    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - State

    @State private var selectedSection: SidebarSection? = nil
    @State private var selectedPublication: CDPublication?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showImportPreview = false
    @State private var importFileURL: URL?

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selectedSection)
        } content: {
            contentList
        } detail: {
            detailView
        }
        .onReceive(NotificationCenter.default.publisher(for: .showLibrary)) { notification in
            // Select the first library if available
            if let library = notification.object as? CDLibrary {
                selectedSection = .library(library)
            } else if let firstLibrary = libraryManager.libraries.first {
                selectedSection = .library(firstLibrary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSearch)) { _ in
            selectedSection = .search
        }
        .onReceive(NotificationCenter.default.publisher(for: .importBibTeX)) { _ in
            showImportPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportBibTeX)) { _ in
            showExportPanel()
        }
        .sheet(isPresented: $showImportPreview) {
            if let url = importFileURL {
                ImportPreviewView(
                    isPresented: $showImportPreview,
                    fileURL: url
                ) { entries in
                    try await importPreviewEntries(entries)
                }
            }
        }
        .task {
            await libraryViewModel.loadPublications()
        }
        .onAppear {
            contentLogger.info("ContentView appeared - main window is visible")
        }
        .onChange(of: selectedSection) { _, _ in
            // ADR-016: All sections now use CDPublication
            // Clear selection when switching sections
            selectedPublication = nil
        }
        .onChange(of: selectedPublication) { _, newValue in
            // Clear selection if publication was deleted
            if let pub = newValue, (pub.isDeleted || pub.managedObjectContext == nil) {
                selectedPublication = nil
            }
        }
    }

    // MARK: - Content List

    @ViewBuilder
    private var contentList: some View {
        switch selectedSection {
        case .library(let library):
            UnifiedPublicationListWrapper(
                source: .library(library),
                selectedPublication: $selectedPublication
            )

        case .unread(let library):
            UnifiedPublicationListWrapper(
                source: .library(library),
                selectedPublication: $selectedPublication,
                initialFilterMode: .unread
            )

        case .search:
            SearchResultsListView(selectedPublication: $selectedPublication)

        case .smartSearch(let smartSearch):
            UnifiedPublicationListWrapper(
                source: .smartSearch(smartSearch),
                selectedPublication: $selectedPublication
            )

        case .collection(let collection):
            CollectionListView(collection: collection, selection: $selectedPublication)

        case .none:
            ContentUnavailableView(
                "No Selection",
                systemImage: "sidebar.left",
                description: Text("Select a library or collection from the sidebar")
            )
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        // Guard against deleted Core Data objects - check isDeleted and managedObjectContext
        // DetailView.init is failable and returns nil for deleted publications
        if let publication = selectedPublication,
           !publication.isDeleted,
           publication.managedObjectContext != nil,
           let libraryID = selectedLibraryID,
           let detail = DetailView(publication: publication, libraryID: libraryID) {
            detail
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "doc.text",
                description: Text("Select a publication to view details")
            )
        }
    }

    /// Extract library ID from current section selection
    private var selectedLibraryID: UUID? {
        switch selectedSection {
        case .library(let library), .unread(let library):
            return library.id
        case .smartSearch(let smartSearch):
            return smartSearch.library?.id
        case .collection(let collection):
            return collection.owningLibrary?.id
        default:
            return nil
        }
    }

    // MARK: - Import/Export

    private func showImportPanel() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "bib")!,
            .init(filenameExtension: "ris")!
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a BibTeX (.bib) or RIS (.ris) file to import"

        if panel.runModal() == .OK, let url = panel.url {
            importFileURL = url
            showImportPreview = true
        }
        #endif
    }

    private func importPreviewEntries(_ entries: [ImportPreviewEntry]) async throws -> Int {
        var count = 0

        for entry in entries {
            switch entry.source {
            case .bibtex(let bibtex):
                await libraryViewModel.importEntry(bibtex)
                count += 1

            case .ris(let ris):
                // Convert RIS to BibTeX and import
                let bibtex = RISBibTeXConverter.toBibTeX(ris)
                await libraryViewModel.importEntry(bibtex)
                count += 1
            }
        }

        await libraryViewModel.loadPublications()
        return count
    }

    private func showExportPanel() {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "bib")!]
        panel.nameFieldStringValue = "library.bib"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                let bibtex = await libraryViewModel.exportAll()
                do {
                    try bibtex.write(to: url, atomically: true, encoding: .utf8)
                    print("Exported to \(url.path)")
                } catch {
                    print("Export failed: \(error)")
                }
            }
        }
        #endif
    }
}

// MARK: - Sidebar Section

enum SidebarSection: Hashable {
    case library(CDLibrary)           // All publications for specific library
    case unread(CDLibrary)            // Unread publications for specific library
    case search                        // Global search
    case smartSearch(CDSmartSearch)   // Smart search (library-scoped via relationship)
    case collection(CDCollection)     // Collection (library-scoped via relationship)
}

// MARK: - Placeholder Views

struct CollectionListView: View {
    let collection: CDCollection
    @Binding var selection: CDPublication?

    var body: some View {
        Text("Collection: \(collection.name)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


#Preview {
    ContentView()
        .environment(LibraryManager())
        .environment(LibraryViewModel())
        .environment(SearchViewModel(
            sourceManager: SourceManager(),
            deduplicationService: DeduplicationService(),
            repository: PublicationRepository()
        ))
        .environment(SettingsViewModel(
            sourceManager: SourceManager(),
            credentialManager: CredentialManager()
        ))
}
