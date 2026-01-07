//
//  IOSContentView.swift
//  imbib-iOS
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI
import PublicationManagerCore
import UniformTypeIdentifiers
import OSLog

private let contentLogger = Logger(subsystem: "com.imbib.app", category: "content")

struct IOSContentView: View {

    // MARK: - Environment

    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - State

    @State private var selectedSection: SidebarSection? = nil
    @State private var selectedPublication: CDPublication?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // File import/export
    @State private var showImportPicker = false
    @State private var showExportPicker = false
    @State private var showImportPreview = false
    @State private var importFileURL: URL?

    // Settings
    @State private var showSettings = false

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            IOSSidebarView(
                selection: $selectedSection,
                onNavigateToSmartSearch: { smartSearch in
                    // On iPhone, explicitly navigate to content column
                    selectedSection = .smartSearch(smartSearch)
                    columnVisibility = .detailOnly
                }
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
        } content: {
            contentList
        } detail: {
            detailView
        }
        .onReceive(NotificationCenter.default.publisher(for: .showLibrary)) { notification in
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
            showImportPicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportBibTeX)) { _ in
            showExportPicker = true
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [
                UTType(filenameExtension: "bib") ?? .plainText,
                UTType(filenameExtension: "ris") ?? .plainText
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importFileURL = url
                    showImportPreview = true
                }
            case .failure(let error):
                contentLogger.error("Import picker error: \(error.localizedDescription)")
            }
        }
        .fileExporter(
            isPresented: $showExportPicker,
            document: BibTeXDocument(content: ""),
            contentType: UTType(filenameExtension: "bib") ?? .plainText,
            defaultFilename: "library.bib"
        ) { result in
            switch result {
            case .success(let url):
                contentLogger.info("Exported to \(url.path)")
            case .failure(let error):
                contentLogger.error("Export error: \(error.localizedDescription)")
            }
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
        .sheet(isPresented: $showSettings) {
            IOSSettingsView()
        }
        .task {
            await libraryViewModel.loadPublications()
        }
        .onAppear {
            contentLogger.info("IOSContentView appeared")
        }
        .onChange(of: selectedSection) { _, _ in
            selectedPublication = nil
        }
        .onChange(of: selectedPublication) { _, newValue in
            if let pub = newValue, (pub.isDeleted || pub.managedObjectContext == nil) {
                selectedPublication = nil
            }
        }
    }

    // MARK: - Content List

    @ViewBuilder
    private var contentList: some View {
        switch selectedSection {
        case .inbox:
            if let inboxLibrary = InboxManager.shared.inboxLibrary {
                IOSLibraryListView(library: inboxLibrary, selection: $selectedPublication)
            } else {
                ContentUnavailableView(
                    "Inbox Empty",
                    systemImage: "tray",
                    description: Text("Add feeds to start discovering papers")
                )
            }

        case .inboxFeed(let smartSearch):
            SmartSearchResultsView(smartSearch: smartSearch, selectedPublication: $selectedPublication)

        case .library(let library):
            IOSLibraryListView(library: library, selection: $selectedPublication)

        case .unread(let library):
            IOSLibraryListView(library: library, selection: $selectedPublication, showUnreadOnly: true)

        case .search:
            IOSSearchView(selectedPublication: $selectedPublication)

        case .smartSearch(let smartSearch):
            SmartSearchResultsView(smartSearch: smartSearch, selectedPublication: $selectedPublication)

        case .collection(let collection):
            IOSCollectionListView(collection: collection, selection: $selectedPublication)

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
        case .inbox:
            return InboxManager.shared.inboxLibrary?.id
        case .inboxFeed(let smartSearch):
            return InboxManager.shared.inboxLibrary?.id ?? smartSearch.library?.id
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

    // MARK: - Import

    private func importPreviewEntries(_ entries: [ImportPreviewEntry]) async throws -> Int {
        var count = 0

        for entry in entries {
            switch entry.source {
            case .bibtex(let bibtex):
                await libraryViewModel.importEntry(bibtex)
                count += 1

            case .ris(let ris):
                let bibtex = RISBibTeXConverter.toBibTeX(ris)
                await libraryViewModel.importEntry(bibtex)
                count += 1
            }
        }

        await libraryViewModel.loadPublications()
        return count
    }
}

// MARK: - BibTeX Document (for export)

struct BibTeXDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "bib") ?? .plainText] }

    var content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = String(data: data, encoding: .utf8) ?? ""
        } else {
            content = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = content.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Sidebar Section (shared with macOS)

enum SidebarSection: Hashable {
    case inbox
    case inboxFeed(CDSmartSearch)
    case library(CDLibrary)
    case unread(CDLibrary)
    case search
    case smartSearch(CDSmartSearch)
    case collection(CDCollection)
}

// MARK: - iOS Library List View (simple wrapper)

struct IOSLibraryListView: View {
    let library: CDLibrary
    @Binding var selection: CDPublication?
    var showUnreadOnly: Bool = false

    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(LibraryManager.self) private var libraryManager

    @State private var publications: [CDPublication] = []
    @State private var multiSelection = Set<UUID>()

    var body: some View {
        PublicationListView(
            publications: publications,
            selection: $multiSelection,
            selectedPublication: $selection,
            library: library,
            allLibraries: libraryManager.libraries,
            showImportButton: true,
            showSortMenu: true,
            emptyStateMessage: "No Publications",
            emptyStateDescription: "Import BibTeX files or search online to add papers.",
            listID: .library(library.id),
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
            onImport: {
                NotificationCenter.default.post(name: .importBibTeX, object: nil)
            },
            onOpenPDF: { publication in
                openPDF(for: publication)
            }
        )
        .navigationTitle(library.displayName)
        .task(id: library.id) {
            refreshPublications()
        }
        .refreshable {
            refreshPublications()
        }
    }

    private func refreshPublications() {
        var result = (library.publications ?? [])
            .filter { !$0.isDeleted && $0.managedObjectContext != nil }

        if showUnreadOnly {
            result = result.filter { !$0.isRead }
        }

        publications = result.sorted { $0.dateAdded > $1.dateAdded }
    }

    private func openPDF(for publication: CDPublication) {
        if let linkedFiles = publication.linkedFiles,
           let pdfFile = linkedFiles.first(where: { $0.isPDF }),
           let libraryURL = library.folderURL {
            let pdfURL = libraryURL.appendingPathComponent(pdfFile.relativePath)
            _ = FileManager_Opener.shared.openFile(pdfURL)
        }
    }
}

// MARK: - iOS Search View (placeholder)

struct IOSSearchView: View {
    @Binding var selectedPublication: CDPublication?
    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LibraryManager.self) private var libraryManager

    @State private var searchText = ""
    @State private var multiSelection = Set<UUID>()

    var body: some View {
        VStack {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
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
            }
            .padding()
            .background(.bar)

            // Results
            if searchViewModel.isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchViewModel.publications.isEmpty {
                ContentUnavailableView(
                    "Search Online",
                    systemImage: "magnifyingglass",
                    description: Text("Search arXiv, ADS, Crossref, and more")
                )
            } else {
                List(searchViewModel.publications, id: \.id, selection: $multiSelection) { publication in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(publication.title ?? "Untitled")
                            .font(.headline)
                            .lineLimit(2)
                        Text(publication.authorString)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if publication.year > 0 {
                            Text(String(publication.year))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Search")
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        searchViewModel.query = searchText
        Task {
            await searchViewModel.search()
        }
    }
}

// MARK: - Preview

#Preview {
    IOSContentView()
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
