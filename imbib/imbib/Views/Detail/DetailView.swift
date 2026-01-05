//
//  DetailView.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore
import OSLog
#if os(macOS)
import AppKit
#endif

private let logger = Logger(subsystem: "com.imbib.app", category: "unifieddetail")

// MARK: - Unified Detail View

/// A unified detail view that works with any PaperRepresentable.
///
/// This view provides a consistent experience for viewing both online search results
/// and local library papers, with editing capabilities enabled for persistent papers.
struct DetailView: View {

    // MARK: - Properties

    /// The paper to display (any PaperRepresentable)
    let paper: any PaperRepresentable

    /// The underlying Core Data publication (enables editing for library papers)
    let publication: CDPublication?

    // MARK: - Environment

    @Environment(LibraryViewModel.self) private var viewModel
    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - State

    @State private var selectedTab: DetailTab = .metadata

    // MARK: - Computed Properties

    /// Whether this paper supports editing (local library papers only)
    private var canEdit: Bool {
        publication != nil
    }

    /// Whether this is a persistent (library) paper
    private var isPersistent: Bool {
        paper.sourceType.isPersistent
    }

    // MARK: - Initialization

    init(paper: any PaperRepresentable, publication: CDPublication? = nil) {
        self.paper = paper
        self.publication = publication
    }

    /// Primary initializer for CDPublication (ADR-016: all papers are CDPublication)
    init(publication: CDPublication, libraryID: UUID) {
        let localPaper = LocalPaper(publication: publication, libraryID: libraryID)
        self.paper = localPaper
        self.publication = publication
    }

    // MARK: - Body

    var body: some View {
        TabView(selection: $selectedTab) {
            MetadataTab(paper: paper, publication: publication)
                .tabItem { Label("Metadata", systemImage: "doc.text") }
                .tag(DetailTab.metadata)

            BibTeXTab(paper: paper, publication: publication)
                .tabItem { Label("BibTeX", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag(DetailTab.bibtex)

            PDFTab(paper: paper, publication: publication)
                .tabItem { Label("PDF", systemImage: "doc.richtext") }
                .tag(DetailTab.pdf)

            // Notes tab only for persistent papers
            if canEdit, let pub = publication {
                NotesTab(publication: pub)
                    .tabItem { Label("Notes", systemImage: "note.text") }
                    .tag(DetailTab.notes)
            }
        }
        .navigationTitle(paper.title)
        #if os(macOS)
        .navigationSubtitle(navigationSubtitle)
        #endif
        .toolbar {
            toolbarContent
        }
        .task(id: publication?.id) {
            // Auto-mark as read after brief delay (Apple Mail style)
            await autoMarkAsRead()
        }
    }

    // MARK: - Auto-Mark as Read

    private func autoMarkAsRead() async {
        guard let pub = publication, !pub.isRead else { return }

        // Wait 1 second before marking as read (like Mail)
        do {
            try await Task.sleep(for: .seconds(1))
            await viewModel.markAsRead(pub)
            logger.debug("Auto-marked as read: \(pub.citeKey)")
        } catch {
            // Task was cancelled (user navigated away quickly)
        }
    }

    // MARK: - Navigation Subtitle

    private var navigationSubtitle: String {
        if let pub = publication {
            return pub.citeKey
        }
        return paper.authorDisplayString
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            // Open PDF button (for papers with PDF)
            if paper.hasPDF {
                Button {
                    openPDF()
                } label: {
                    Label("Open PDF", systemImage: "doc.richtext")
                }
            }

            // Copy BibTeX button
            Button {
                copyBibTeX()
            } label: {
                Label("Copy BibTeX", systemImage: "doc.on.doc")
            }

            // Open in Browser (for papers with web URL)
            if let webURL = publication?.webURLObject {
                Link(destination: webURL) {
                    Label("Open in Browser", systemImage: "safari")
                }
            }

            // Share button (for library papers)
            if let pub = publication {
                ShareLink(item: pub.citeKey) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Actions

    private func openPDF() {
        Task {
            if let url = await paper.pdfURL() {
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #endif
            }
        }
    }

    private func copyBibTeX() {
        Task {
            let bibtex: String
            if let pub = publication {
                // For library papers, use stored BibTeX
                let entry = pub.toBibTeXEntry()
                bibtex = BibTeXExporter().export([entry])
            } else {
                // For online papers, generate from metadata
                let entry = BibTeXExporter.generateEntry(from: paper)
                bibtex = BibTeXExporter().export([entry])
            }

            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(bibtex, forType: .string)
            #endif
        }
    }
}

// MARK: - Unified Detail Tab

enum DetailTab: String, CaseIterable {
    case metadata
    case bibtex
    case pdf
    case notes
}

// MARK: - Metadata Tab

struct MetadataTab: View {
    let paper: any PaperRepresentable
    let publication: CDPublication?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title (with scientific text parsing for sub/superscripts)
                    metadataSection("Title") {
                        ScientificTextParser.text(paper.title)
                            .textSelection(.enabled)
                    }
                    .id("top")

                    // Authors
                    metadataSection("Authors") {
                        Text(paper.authors.isEmpty ? "Unknown" : paper.authors.joined(separator: ", "))
                            .textSelection(.enabled)
                    }

                    // Year
                    if let year = paper.year {
                        metadataSection("Year") {
                            Text(String(year))
                        }
                    }

                    // Venue/Journal (expand macros to full names)
                    if let venue = paper.venue {
                        metadataSection("Venue") {
                            Text(JournalMacros.expand(venue))
                                .textSelection(.enabled)
                        }
                    }

                    // DOI
                    if let doi = paper.doi {
                        metadataSection("DOI") {
                            Link(doi, destination: URL(string: "https://doi.org/\(doi)")!)
                        }
                    }

                    // arXiv ID
                    if let arxivID = paper.arxivID {
                        metadataSection("arXiv") {
                            Link(arxivID, destination: URL(string: "https://arxiv.org/abs/\(arxivID)")!)
                        }
                    }

                    // Bibcode (ADS)
                    if let bibcode = paper.bibcode {
                        metadataSection("Bibcode") {
                            Link(bibcode, destination: URL(string: "https://ui.adsabs.harvard.edu/abs/\(bibcode)")!)
                        }
                    }

                    // PubMed ID
                    if let pmid = paper.pmid {
                        metadataSection("PubMed") {
                            Link(pmid, destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)")!)
                        }
                    }

                    // Web URL (from CDPublication's webURL field)
                    if let pub = publication, let webURL = pub.webURLObject {
                        metadataSection("Web Link") {
                            Link(webURL.host ?? webURL.absoluteString, destination: webURL)
                        }
                    }

                    // Abstract (with scientific text parsing for sub/superscripts)
                    if let abstract = paper.abstract, !abstract.isEmpty {
                        metadataSection("Abstract") {
                            ScientificTextParser.text(abstract)
                                .textSelection(.enabled)
                        }
                    }

                    // Source info
                    metadataSection("Source") {
                        Text(sourceDescription)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding()
            }
            .onChange(of: paper.id, initial: true) { _, _ in
                proxy.scrollTo("top", anchor: .top)
            }
        }
    }

    private var sourceDescription: String {
        switch paper.sourceType {
        case .local:
            return "Library"
        case .smartSearch:
            return "Smart Search"
        case .adHocSearch(let sourceID):
            return sourceID.capitalized
        }
    }

    @ViewBuilder
    private func metadataSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}

// MARK: - BibTeX Tab

struct BibTeXTab: View {
    let paper: any PaperRepresentable
    let publication: CDPublication?

    @Environment(LibraryViewModel.self) private var viewModel
    @State private var bibtexContent: String = ""
    @State private var isEditing = false
    @State private var hasChanges = false
    @State private var isLoading = false

    /// Whether editing is enabled (only for library papers)
    private var canEdit: Bool {
        publication != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar (only show edit controls for library papers)
            if canEdit {
                editableToolbar
            }

            // Editor / Display
            if isLoading {
                ProgressView("Loading BibTeX...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if bibtexContent.isEmpty {
                ContentUnavailableView(
                    "No BibTeX",
                    systemImage: "doc.text",
                    description: Text("BibTeX is not available for this paper")
                )
            } else {
                BibTeXEditor(
                    text: $bibtexContent,
                    isEditable: isEditing,
                    showLineNumbers: true
                ) { _ in
                    saveBibTeX()
                }
                .onChange(of: bibtexContent) { _, _ in
                    if isEditing {
                        hasChanges = true
                    }
                }
            }
        }
        .onChange(of: paper.id, initial: true) { _, _ in
            // Reset state and reload when paper changes
            bibtexContent = ""
            isEditing = false
            hasChanges = false
            loadBibTeX()
        }
    }

    @ViewBuilder
    private var editableToolbar: some View {
        HStack {
            if isEditing {
                Button("Cancel") {
                    bibtexContent = generateBibTeX()
                    isEditing = false
                    hasChanges = false
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Save") {
                    saveBibTeX()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges)
            } else {
                Spacer()

                Button {
                    isEditing = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func loadBibTeX() {
        isLoading = true
        bibtexContent = generateBibTeX()
        isLoading = false
    }

    private func generateBibTeX() -> String {
        // ADR-016: All papers are now CDPublication
        if let pub = publication {
            let entry = pub.toBibTeXEntry()
            return BibTeXExporter().export([entry])
        }
        // Fallback for any edge cases (should not happen)
        let entry = BibTeXExporter.generateEntry(from: paper)
        return BibTeXExporter().export([entry])
    }

    private func saveBibTeX() {
        guard let pub = publication else { return }

        Task {
            do {
                let items = try BibTeXParser().parse(bibtexContent)
                guard let entry = items.compactMap({ item -> BibTeXEntry? in
                    if case .entry(let entry) = item { return entry }
                    return nil
                }).first else {
                    return
                }

                await viewModel.updateFromBibTeX(pub, entry: entry)

                await MainActor.run {
                    isEditing = false
                    hasChanges = false
                }
            } catch {
                logger.error("Failed to parse BibTeX: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - PDF Tab

struct PDFTab: View {
    let paper: any PaperRepresentable
    let publication: CDPublication?

    @Environment(LibraryManager.self) private var libraryManager
    @State private var linkedFile: CDLinkedFile?
    @State private var isDownloading = false
    @State private var downloadError: Error?
    @State private var hasRemotePDF = false
    @State private var checkPDFTask: Task<Void, Never>?
    @State private var showFileImporter = false

    var body: some View {
        Group {
            // ADR-016: All papers are now CDPublication
            if let linked = linkedFile, let pub = publication {
                // Has linked PDF file → show viewer
                PDFViewerWithControls(
                    linkedFile: linked,
                    library: libraryManager.activeLibrary,
                    publicationID: pub.id
                )
            } else if isDownloading {
                downloadingView
            } else if let error = downloadError {
                errorView(error)
            } else if hasRemotePDF {
                // No local PDF but remote available → show download prompt
                noPDFLibraryView
            } else {
                // No PDF available anywhere
                noPDFView
            }
        }
        .onChange(of: paper.id, initial: true) { _, _ in
            resetAndCheckPDF()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Subviews

    private var downloadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Downloading PDF...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label("Download Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Retry") {
                Task { await downloadPDF() }
            }
        }
    }

    private var noPDFLibraryView: some View {
        ContentUnavailableView {
            Label("PDF Available", systemImage: "doc.richtext")
        } description: {
            Text("Download from online source or add a local file.")
        } actions: {
            Button("Download PDF") {
                Task { await downloadPDF() }
            }
            .buttonStyle(.borderedProminent)

            Button("Add PDF...") {
                showFileImporter = true
            }
            .buttonStyle(.bordered)
        }
    }

    private var noPDFView: some View {
        ContentUnavailableView(
            "No PDF",
            systemImage: "doc.richtext",
            description: Text("No PDF is available for this paper.")
        )
    }

    // MARK: - Actions

    private func resetAndCheckPDF() {
        checkPDFTask?.cancel()

        linkedFile = nil
        downloadError = nil
        isDownloading = false
        hasRemotePDF = false

        checkPDFTask = Task {
            // ADR-016: All papers are now CDPublication
            guard let pub = publication else {
                return
            }

            // Check for linked PDF files
            let linkedFiles = pub.linkedFiles ?? []
            if let firstPDF = linkedFiles.first(where: { $0.isPDF }) ?? linkedFiles.first {
                await MainActor.run {
                    linkedFile = firstPDF
                }
                return
            }

            // No local PDF - check if remote PDF is available
            await MainActor.run {
                hasRemotePDF = PDFURLResolver.hasPDF(publication: pub)
            }
        }
    }

    private func downloadPDF() async {
        guard let pub = publication else {
            logger.warning("[PDFTab] No publication available for PDF download")
            return
        }

        // Use PDFURLResolver to get the best URL based on user settings
        let settings = await PDFSettingsStore.shared.settings
        guard let resolvedURL = PDFURLResolver.resolve(for: pub, settings: settings) else {
            logger.warning("[PDFTab] No PDF URL could be resolved for paper: \(paper.id)")
            return
        }

        logger.info("[PDFTab] Downloading PDF from: \(resolvedURL.absoluteString)")

        isDownloading = true
        downloadError = nil

        do {
            // Download to temp location
            let (tempURL, _) = try await URLSession.shared.download(from: resolvedURL)

            // Import into library using PDFManager
            guard let library = libraryManager.activeLibrary else {
                throw PDFDownloadError.noActiveLibrary
            }

            try PDFManager.shared.importPDF(from: tempURL, for: pub, in: library)

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

            await MainActor.run {
                logger.info("[PDFTab] PDF downloaded and imported successfully")
                resetAndCheckPDF()
            }
        } catch {
            await MainActor.run {
                downloadError = error
                logger.error("[PDFTab] PDF download failed: \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            isDownloading = false
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first, let pub = publication else { return }

            Task {
                do {
                    // Import PDF using PDFManager
                    guard let library = libraryManager.activeLibrary else {
                        logger.error("[PDFTab] No active library for PDF import")
                        return
                    }

                    // Import the PDF - PDFManager takes CDPublication directly
                    try PDFManager.shared.importPDF(from: url, for: pub, in: library)

                    // Refresh to show the new PDF
                    await MainActor.run {
                        resetAndCheckPDF()
                    }

                    logger.info("[PDFTab] PDF imported successfully")
                } catch {
                    logger.error("[PDFTab] PDF import failed: \(error.localizedDescription)")
                    await MainActor.run {
                        downloadError = error
                    }
                }
            }

        case .failure(let error):
            logger.error("[PDFTab] File import failed: \(error.localizedDescription)")
            downloadError = error
        }
    }
}

// MARK: - Notes Tab

struct NotesTab: View {
    let publication: CDPublication

    @Environment(LibraryViewModel.self) private var viewModel
    @State private var notes: String = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        TextEditor(text: $notes)
            .font(.body)
            .padding()
            .onChange(of: publication.id, initial: true) { _, _ in
                saveTask?.cancel()
                notes = publication.fields["note"] ?? ""
            }
            .onChange(of: notes) { oldValue, newValue in
                let targetPublication = publication

                saveTask?.cancel()
                saveTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    guard targetPublication.id == self.publication.id else { return }
                    await viewModel.updateField(targetPublication, field: "note", value: newValue)
                }
            }
    }
}

// MARK: - PDF Download Error

enum PDFDownloadError: LocalizedError {
    case noActiveLibrary
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .noActiveLibrary:
            return "No active library for PDF import"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        }
    }
}

// MARK: - Preview

#Preview {
    // Create a sample CDPublication for preview
    let publication = PersistenceController.preview.viewContext.performAndWait {
        let pub = CDPublication(context: PersistenceController.preview.viewContext)
        pub.id = UUID()
        pub.citeKey = "Smith2024Deep"
        pub.entryType = "inproceedings"
        pub.title = "Deep Learning for Natural Language Processing"
        pub.year = 2024
        pub.dateAdded = Date()
        pub.dateModified = Date()
        pub.abstract = "This paper presents a novel approach to natural language processing using deep learning techniques..."

        var fields: [String: String] = [:]
        fields["author"] = "Smith, John and Doe, Jane and Wilson, Bob"
        fields["booktitle"] = "Conference on Machine Learning"
        fields["doi"] = "10.1234/example.2024.001"
        pub.fields = fields

        return pub
    }

    let libraryID = UUID()

    NavigationStack {
        DetailView(publication: publication, libraryID: libraryID)
    }
    .environment(LibraryViewModel())
    .environment(LibraryManager(persistenceController: .preview))
}
