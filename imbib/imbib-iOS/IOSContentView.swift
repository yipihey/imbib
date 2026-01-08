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

    // Category search (for navigating from category chip tap)
    @State private var pendingCategorySearch: String?

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
        .onReceive(NotificationCenter.default.publisher(for: .searchCategory)) { notification in
            if let category = notification.userInfo?["category"] as? String {
                // Navigate to search with the category query
                pendingCategorySearch = "cat:\(category)"
                selectedSection = .search
            }
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
        // iOS Keyboard Shortcuts (for external keyboards on iPad)
        .onReceive(NotificationCenter.default.publisher(for: .showInbox)) { _ in
            if let inboxLibrary = InboxManager.shared.inboxLibrary {
                selectedSection = .inbox
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleReadStatus)) { _ in
            if let pub = selectedPublication {
                Task {
                    await libraryViewModel.toggleReadStatus(pub)
                }
            }
        }
        // Add keyboard shortcut buttons for accessibility (hidden visually but accessible via keyboard)
        .background {
            KeyboardShortcutButtons(
                showImportPicker: $showImportPicker,
                showExportPicker: $showExportPicker
            )
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
            IOSSearchView(
                selectedPublication: $selectedPublication,
                initialQuery: pendingCategorySearch
            )
            .onDisappear {
                // Clear pending search when leaving search view
                pendingCategorySearch = nil
            }

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
            },
            onCategoryTap: { category in
                // Navigate to search with category query
                NotificationCenter.default.post(
                    name: .searchCategory,
                    object: nil,
                    userInfo: ["category": category]
                )
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

// MARK: - iOS Search View

struct IOSSearchView: View {
    @Binding var selectedPublication: CDPublication?

    /// Optional initial query (e.g., from category chip tap)
    var initialQuery: String?

    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(LibraryViewModel.self) private var libraryViewModel

    @State private var searchText = ""
    @State private var multiSelection = Set<UUID>()
    @State private var hasAppliedInitialQuery = false
    @State private var availableSources: [SourceMetadata] = []

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding()
                .background(.bar)

            // Source filter chips
            if !availableSources.isEmpty {
                sourceFilterBar
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }

            Divider()

            // Results
            resultsList
        }
        .navigationTitle("Search")
        .toolbar {
            // Send to Inbox button
            ToolbarItem(placement: .topBarTrailing) {
                if !multiSelection.isEmpty {
                    Button {
                        sendSelectedToInbox()
                    } label: {
                        Label("Send to Inbox", systemImage: "tray.and.arrow.down")
                    }
                }
            }
        }
        .task {
            availableSources = await searchViewModel.availableSources
            // Ensure SearchViewModel has access to LibraryManager
            searchViewModel.setLibraryManager(libraryManager)
        }
        .onAppear {
            applyInitialQueryIfNeeded()
        }
        .onChange(of: initialQuery) { _, newValue in
            if newValue != nil {
                hasAppliedInitialQuery = false
                applyInitialQueryIfNeeded()
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
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

            Button("Search") {
                performSearch()
            }
            .buttonStyle(.borderedProminent)
            .disabled(searchText.isEmpty)
        }
    }

    // MARK: - Source Filter Bar

    private var sourceFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableSources, id: \.id) { source in
                    IOSSourceChip(
                        source: source,
                        isSelected: searchViewModel.selectedSourceIDs.contains(source.id)
                    ) {
                        searchViewModel.toggleSource(source.id)
                    }
                }

                Divider()
                    .frame(height: 20)

                Button("All") {
                    Task {
                        await searchViewModel.selectAllSources()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Results List

    @ViewBuilder
    private var resultsList: some View {
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

    // MARK: - Actions

    private func applyInitialQueryIfNeeded() {
        guard !hasAppliedInitialQuery, let query = initialQuery, !query.isEmpty else { return }
        hasAppliedInitialQuery = true
        searchText = query
        performSearch()
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        searchViewModel.query = searchText
        Task {
            await searchViewModel.search()
        }
    }

    private func sendSelectedToInbox() {
        guard !multiSelection.isEmpty else { return }

        let inboxManager = InboxManager.shared

        // Add selected publications to Inbox
        for id in multiSelection {
            if let publication = searchViewModel.publications.first(where: { $0.id == id }) {
                inboxManager.addToInbox(publication)
            }
        }

        // Clear selection after sending
        multiSelection.removeAll()
    }
}

// MARK: - iOS Source Chip

struct IOSSourceChip: View {
    let source: SourceMetadata
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: source.iconName)
                    .font(.caption)
                Text(source.name)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

// MARK: - iOS Keyboard Shortcut Buttons

/// Hidden buttons that provide keyboard shortcuts on iPad with external keyboard.
/// These are invisible but respond to keyboard shortcuts.
struct KeyboardShortcutButtons: View {
    @Binding var showImportPicker: Bool
    @Binding var showExportPicker: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Import (Cmd+I)
            Button("Import") {
                showImportPicker = true
            }
            .keyboardShortcut("i", modifiers: .command)

            // Export (Cmd+Shift+E)
            Button("Export") {
                showExportPicker = true
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            // Show Library (Cmd+1)
            Button("Library") {
                NotificationCenter.default.post(name: .showLibrary, object: nil)
            }
            .keyboardShortcut("1", modifiers: .command)

            // Show Search (Cmd+2)
            Button("Search") {
                NotificationCenter.default.post(name: .showSearch, object: nil)
            }
            .keyboardShortcut("2", modifiers: .command)

            // Show Inbox (Cmd+3)
            Button("Inbox") {
                NotificationCenter.default.post(name: .showInbox, object: nil)
            }
            .keyboardShortcut("3", modifiers: .command)

            // Toggle Read/Unread (Cmd+Shift+U)
            Button("Toggle Read") {
                NotificationCenter.default.post(name: .toggleReadStatus, object: nil)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            // Open Notes (Cmd+R) - if a publication is selected
            Button("Notes") {
                NotificationCenter.default.post(name: .showNotesTab, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            // PDF Tab (Cmd+4)
            Button("PDF") {
                NotificationCenter.default.post(name: .showPDFTab, object: nil)
            }
            .keyboardShortcut("4", modifiers: .command)

            // BibTeX Tab (Cmd+5)
            Button("BibTeX") {
                NotificationCenter.default.post(name: .showBibTeXTab, object: nil)
            }
            .keyboardShortcut("5", modifiers: .command)

            // Notes Tab (Cmd+6)
            Button("Notes Tab") {
                NotificationCenter.default.post(name: .showNotesTab, object: nil)
            }
            .keyboardShortcut("6", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

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
