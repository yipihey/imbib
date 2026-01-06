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

    @State private var selectedTab: DetailTab = .info

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
    /// Returns nil if the publication has been deleted
    init?(publication: CDPublication, libraryID: UUID) {
        // Guard against deleted Core Data objects
        guard let localPaper = LocalPaper(publication: publication, libraryID: libraryID) else {
            return nil
        }
        self.paper = localPaper
        self.publication = publication
    }

    // MARK: - Body

    var body: some View {
        TabView(selection: $selectedTab) {
            InfoTab(paper: paper, publication: publication)
                .tabItem { Label("Info", systemImage: "info.circle") }
                .tag(DetailTab.info)

            BibTeXTab(paper: paper, publication: publication)
                .tabItem { Label("BibTeX", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag(DetailTab.bibtex)

            PDFTab(paper: paper, publication: publication, selectedTab: $selectedTab)
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
    case info
    case bibtex
    case pdf
    case notes
}

// MARK: - Info Tab

struct InfoTab: View {
    let paper: any PaperRepresentable
    let publication: CDPublication?

    @Environment(LibraryManager.self) private var libraryManager

    // State for attachment deletion
    @State private var fileToDelete: CDLinkedFile?
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: - Email-Style Header
                    headerSection
                        .id("top")

                    Divider()

                    // MARK: - Identifiers (compact row)
                    if hasIdentifiers {
                        identifiersSection
                        Divider()
                    }

                    // MARK: - Abstract (Body)
                    if let abstract = paper.abstract, !abstract.isEmpty {
                        infoSection("Abstract") {
                            ScientificTextParser.text(abstract)
                                .textSelection(.enabled)
                        }
                        Divider()
                    }

                    // MARK: - Attachments (PDF files)
                    if let pub = publication, let linkedFiles = pub.linkedFiles, !linkedFiles.isEmpty {
                        attachmentsSection(Array(linkedFiles))
                        Divider()
                    }

                    // MARK: - Record Info
                    if let pub = publication {
                        recordInfoSection(pub)
                    }

                    Spacer()
                }
                .padding()
            }
            .onChange(of: paper.id, initial: true) { _, _ in
                proxy.scrollTo("top", anchor: .top)
            }
        }
        .confirmationDialog(
            "Delete Attachment?",
            isPresented: $showDeleteConfirmation,
            presenting: fileToDelete
        ) { file in
            Button("Delete", role: .destructive) {
                deleteFile(file)
            }
        } message: { file in
            Text("Delete \"\(file.filename)\"? This cannot be undone.")
        }
    }

    // MARK: - Header Section (Email-Style)

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // From: Authors
            infoRow("From") {
                Text(paper.authors.isEmpty ? "Unknown" : paper.authors.joined(separator: "; "))
                    .textSelection(.enabled)
            }

            // Year
            if let year = paper.year {
                infoRow("Year") {
                    Text(String(year))
                }
            }

            // Subject: Title
            infoRow("Subject") {
                ScientificTextParser.text(paper.title)
                    .font(.headline)
                    .textSelection(.enabled)
            }

            // Venue
            if let venue = paper.venue {
                infoRow("Venue") {
                    Text(JournalMacros.expand(venue))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Identifiers Section

    private var hasIdentifiers: Bool {
        paper.doi != nil || paper.arxivID != nil || paper.bibcode != nil || paper.pmid != nil
    }

    @ViewBuilder
    private var identifiersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Identifiers")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            FlowLayout(spacing: 12) {
                if let doi = paper.doi {
                    identifierLink("DOI", value: doi, url: "https://doi.org/\(doi)")
                }
                if let arxivID = paper.arxivID {
                    identifierLink("arXiv", value: arxivID, url: "https://arxiv.org/abs/\(arxivID)")
                }
                if let bibcode = paper.bibcode {
                    identifierLink("ADS", value: bibcode, url: "https://ui.adsabs.harvard.edu/abs/\(bibcode)")
                }
                if let pmid = paper.pmid {
                    identifierLink("PubMed", value: pmid, url: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)")
                }
            }
        }
    }

    @ViewBuilder
    private func identifierLink(_ label: String, value: String, url: String) -> some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let linkURL = URL(string: url) {
                Link(value, destination: linkURL)
                    .font(.caption)
            } else {
                Text(value)
                    .font(.caption)
            }
        }
    }

    // MARK: - Attachments Section

    @ViewBuilder
    private func attachmentsSection(_ linkedFiles: [CDLinkedFile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attachments (\(linkedFiles.count))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(linkedFiles, id: \.id) { file in
                attachmentRow(file)
            }
        }
    }

    @ViewBuilder
    private func attachmentRow(_ file: CDLinkedFile) -> some View {
        HStack {
            Image(systemName: file.isPDF ? "doc.fill" : "paperclip")
                .foregroundStyle(.secondary)

            Text(file.filename)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let size = getFileSize(for: file) {
                Text(formatFileSize(size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Open") {
                openFile(file)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            #if os(macOS)
            Button {
                showInFinder(file)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Show in Finder")
            #endif

            // Delete button
            Button {
                fileToDelete = file
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .help("Delete attachment")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }

    // MARK: - Record Info Section

    @ViewBuilder
    private func recordInfoSection(_ pub: CDPublication) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Record Info")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Cite Key")
                        .foregroundStyle(.secondary)
                    Text(pub.citeKey)
                        .textSelection(.enabled)
                }

                GridRow {
                    Text("Entry Type")
                        .foregroundStyle(.secondary)
                    Text(pub.entryType.capitalized)
                }

                GridRow {
                    Text("Added")
                        .foregroundStyle(.secondary)
                    Text(pub.dateAdded.formatted(date: .abbreviated, time: .omitted))
                }

                GridRow {
                    Text("Modified")
                        .foregroundStyle(.secondary)
                    Text(pub.dateModified.formatted(date: .abbreviated, time: .omitted))
                }

                GridRow {
                    Text("Read Status")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text(pub.isRead ? "Read" : "Unread")
                        if pub.isRead {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }

                if pub.citationCount > 0 {
                    GridRow {
                        Text("Citations")
                            .foregroundStyle(.secondary)
                        Text(pub.citationCount.formatted())
                    }
                }
            }
            .font(.callout)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func infoRow(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(label):")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            content()
        }
    }

    @ViewBuilder
    private func infoSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func getFileSize(for file: CDLinkedFile) -> Int64? {
        guard let url = PDFManager.shared.resolveURL(for: file, in: libraryManager.activeLibrary) else {
            return nil
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return attrs[.size] as? Int64
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func openFile(_ file: CDLinkedFile) {
        guard let url = PDFManager.shared.resolveURL(for: file, in: libraryManager.activeLibrary) else {
            return
        }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    #if os(macOS)
    private func showInFinder(_ file: CDLinkedFile) {
        guard let url = PDFManager.shared.resolveURL(for: file, in: libraryManager.activeLibrary) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    #endif

    private func deleteFile(_ file: CDLinkedFile) {
        do {
            try PDFManager.shared.delete(file, in: libraryManager.activeLibrary)
            Logger.files.infoCapture("Deleted attachment: \(file.filename)", category: "pdf")
        } catch {
            Logger.files.errorCapture("Failed to delete attachment: \(error)", category: "pdf")
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
    @Binding var selectedTab: DetailTab

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
                    publicationID: pub.id,
                    onCorruptPDF: { corruptFile in
                        Task {
                            await handleCorruptPDF(corruptFile)
                        }
                    }
                )
                .id(pub.id)  // Force view recreation when paper changes to reset @State
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
        .onChange(of: selectedTab) { oldTab, newTab in
            // Only check PDF when switching TO the PDF tab
            if newTab == .pdf {
                resetAndCheckPDF()
            }
        }
        .onChange(of: paper.id) { _, _ in
            // Only check PDF if the PDF tab is currently visible
            if selectedTab == .pdf {
                resetAndCheckPDF()
            }
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
            let hasRemote = PDFURLResolver.hasPDF(publication: pub)
            await MainActor.run {
                hasRemotePDF = hasRemote
            }

            // Auto-download if setting enabled AND remote PDF available
            let settings = await PDFSettingsStore.shared.settings
            if settings.autoDownloadEnabled && hasRemote {
                await downloadPDF()
            }
        }
    }

    private func downloadPDF() async {
        guard let pub = publication else {
            logger.warning("[PDFTab] No publication available for PDF download")
            return
        }

        // Use resolveForAutoDownload with OpenAlex → Publisher → arXiv priority
        let settings = await PDFSettingsStore.shared.settings
        guard let resolvedURL = PDFURLResolver.resolveForAutoDownload(for: pub, settings: settings) else {
            logger.warning("[PDFTab] No PDF URL could be resolved for paper: \(paper.id)")
            return
        }

        logger.info("[PDFTab] Downloading PDF from: \(resolvedURL.absoluteString)")

        isDownloading = true
        downloadError = nil

        do {
            // Download to temp location
            let (tempURL, _) = try await URLSession.shared.download(from: resolvedURL)

            // Validate it's actually a PDF (check for %PDF header)
            let fileHandle = try FileHandle(forReadingFrom: tempURL)
            let header = fileHandle.readData(ofLength: 4)
            try fileHandle.close()

            guard header.count >= 4,
                  header[0] == 0x25, // %
                  header[1] == 0x50, // P
                  header[2] == 0x44, // D
                  header[3] == 0x46  // F
            else {
                // Not a valid PDF - likely HTML error page
                logger.warning("[PDFTab] Downloaded file is not a valid PDF (invalid header)")
                try? FileManager.default.removeItem(at: tempURL)
                throw PDFDownloadError.downloadFailed("Downloaded file is not a valid PDF")
            }

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

    private func handleCorruptPDF(_ corruptFile: CDLinkedFile) async {
        logger.warning("[PDFTab] Corrupt PDF detected, attempting recovery: \(corruptFile.filename)")

        do {
            // 1. Delete corrupt file from disk and Core Data
            try PDFManager.shared.delete(corruptFile, in: libraryManager.activeLibrary)

            // 2. Reset state and trigger re-download
            await MainActor.run {
                linkedFile = nil
                resetAndCheckPDF()  // Will see no local PDF and try to download
            }

            logger.info("[PDFTab] Corrupt PDF cleanup complete, re-downloading...")
        } catch {
            logger.error("[PDFTab] Failed to clean up corrupt PDF: \(error)")
            await MainActor.run {
                downloadError = error
            }
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

// MARK: - Flow Layout

/// A layout that arranges views horizontally and wraps to new lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return layout(sizes: sizes, containerWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let offsets = layout(sizes: sizes, containerWidth: bounds.width).offsets

        for (subview, offset) in zip(subviews, offsets) {
            subview.place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func layout(sizes: [CGSize], containerWidth: CGFloat) -> (offsets: [CGPoint], size: CGSize) {
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for size in sizes {
            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxWidth = max(maxWidth, currentX - spacing)
        }

        return (offsets, CGSize(width: maxWidth, height: currentY + lineHeight))
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
