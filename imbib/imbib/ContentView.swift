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

    // MARK: - State

    @State private var selectedSection: SidebarSection? = .library
    @State private var selectedPublication: CDPublication?
    @State private var selectedOnlinePaper: OnlinePaper?
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
        .onReceive(NotificationCenter.default.publisher(for: .showLibrary)) { _ in
            selectedSection = .library
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
        .onChange(of: selectedSection) { _, newValue in
            // Clear online paper selection when switching away from smart search
            if case .smartSearch = newValue {
                // Keep selection
            } else {
                selectedOnlinePaper = nil
            }
        }
        .onChange(of: selectedOnlinePaper) { _, newValue in
            Logger.viewModels.infoCapture("[ContentView] selectedOnlinePaper changed: \(newValue?.title ?? "nil") id: \(newValue?.id ?? "nil")", category: "selection")
        }
    }

    // MARK: - Content List

    @ViewBuilder
    private var contentList: some View {
        switch selectedSection {
        case .library, .recentlyAdded, .recentlyRead:
            LibraryListView(selection: $selectedPublication)

        case .search:
            SearchResultsListView()

        case .smartSearch(let smartSearch):
            SmartSearchResultsView(smartSearch: smartSearch, selectedPaper: $selectedOnlinePaper)

        case .collection(let collection):
            CollectionListView(collection: collection, selection: $selectedPublication)

        case .tag(let tag):
            TagListView(tag: tag, selection: $selectedPublication)

        case .none:
            Text("Select a section")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if let publication = selectedPublication {
            PublicationDetailView(publication: publication)
        } else if let onlinePaper = selectedOnlinePaper {
            PaperDetailView(paper: onlinePaper)
                .id(onlinePaper.id)
        } else if case .search = selectedSection {
            SearchDetailView()
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "doc.text",
                description: Text("Select a publication to view details")
            )
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
    case library
    case recentlyAdded
    case recentlyRead
    case search
    case smartSearch(CDSmartSearch)
    case collection(CDCollection)
    case tag(CDTag)
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

struct TagListView: View {
    let tag: CDTag
    @Binding var selection: CDPublication?

    var body: some View {
        Text("Tag: \(tag.name)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SearchDetailView: View {
    @Environment(SearchViewModel.self) private var viewModel

    var body: some View {
        if viewModel.selectedResults.isEmpty {
            ContentUnavailableView(
                "No Selection",
                systemImage: "magnifyingglass",
                description: Text("Select a search result to view details")
            )
        } else {
            Text("Selected \(viewModel.selectedResults.count) results")
        }
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
