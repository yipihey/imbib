//
//  PaperDetailView.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore
import OSLog

private let logger = Logger(subsystem: "com.imbib.app", category: "paperdetail")

// MARK: - BibTeX Generation Helper

/// Generate a BibTeX entry from an OnlinePaper's metadata without network fetch
private func generateBibTeXEntry(from paper: OnlinePaper) -> BibTeXEntry {
    // Generate cite key: LastName + Year + FirstTitleWord
    let lastNamePart = paper.authors.first?
        .components(separatedBy: ",").first?
        .components(separatedBy: " ").last?
        .filter { $0.isLetter } ?? "Unknown"
    let yearPart = paper.year.map { String($0) } ?? ""
    let titleWord = paper.title
        .components(separatedBy: .whitespaces)
        .first { $0.count > 3 }?
        .filter { $0.isLetter }
        .capitalized ?? ""
    let citeKey = "\(lastNamePart)\(yearPart)\(titleWord)"

    // Determine entry type
    let entryType: String
    if paper.arxivID != nil {
        entryType = "article"
    } else if let venue = paper.venue?.lowercased() {
        if venue.contains("proceedings") || venue.contains("conference") {
            entryType = "inproceedings"
        } else {
            entryType = "article"
        }
    } else {
        entryType = "article"
    }

    // Build fields
    var fields: [String: String] = [:]
    fields["title"] = paper.title

    // Format authors as "Last, First and Last, First"
    if !paper.authors.isEmpty {
        fields["author"] = paper.authors.joined(separator: " and ")
    }

    if let year = paper.year {
        fields["year"] = String(year)
    }

    if let venue = paper.venue {
        if entryType == "inproceedings" {
            fields["booktitle"] = venue
        } else {
            fields["journal"] = venue
        }
    }

    if let abstract = paper.abstract {
        fields["abstract"] = abstract
    }

    if let doi = paper.doi {
        fields["doi"] = doi
    }

    if let arxivID = paper.arxivID {
        fields["eprint"] = arxivID
        fields["archiveprefix"] = "arXiv"
    }

    if let bibcode = paper.bibcode {
        fields["adsurl"] = "https://ui.adsabs.harvard.edu/abs/\(bibcode)"
    }

    return BibTeXEntry(citeKey: citeKey, entryType: entryType, fields: fields)
}

/// Detail view for online papers (OnlinePaper/PaperRepresentable).
/// Displays Metadata, BibTeX, and PDF tabs for search results.
struct PaperDetailView: View {

    // MARK: - Properties

    let paper: OnlinePaper

    // MARK: - State

    @State private var selectedTab: PaperDetailTab = .metadata

    // MARK: - Body

    var body: some View {
        let _ = Logger.viewModels.infoCapture("[PaperDetailView] body called for: \(paper.title)", category: "selection")
        TabView(selection: $selectedTab) {
            PaperMetadataTabView(paper: paper)
                .tabItem { Label("Metadata", systemImage: "doc.text") }
                .tag(PaperDetailTab.metadata)

            PaperBibTeXTabView(paper: paper)
                .tabItem { Label("BibTeX", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag(PaperDetailTab.bibtex)

            PaperPDFTabView(paper: paper)
                .tabItem { Label("PDF", systemImage: "doc.richtext") }
                .tag(PaperDetailTab.pdf)
        }
        .navigationTitle(paper.title)
        #if os(macOS)
        .navigationSubtitle(paper.authorDisplayString)
        #endif
        .toolbar {
            toolbarContent
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if paper.remotePDFURL != nil {
                Button {
                    openPDF()
                } label: {
                    Label("Open PDF", systemImage: "doc.richtext")
                }
            }

            Button {
                copyBibTeX()
            } label: {
                Label("Copy BibTeX", systemImage: "doc.on.doc")
            }

            if let webURL = paper.webURL {
                Link(destination: webURL) {
                    Label("Open in Browser", systemImage: "safari")
                }
            }
        }
    }

    // MARK: - Actions

    private func openPDF() {
        guard let url = paper.remotePDFURL else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    private func copyBibTeX() {
        let entry = generateBibTeXEntry(from: paper)
        let bibtex = BibTeXExporter().export([entry])
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bibtex, forType: .string)
        #endif
    }
}

// MARK: - Paper Detail Tab

enum PaperDetailTab: String, CaseIterable {
    case metadata
    case bibtex
    case pdf
}

// MARK: - Metadata Tab

struct PaperMetadataTabView: View {
    let paper: OnlinePaper

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    metadataSection("Title") {
                        Text(paper.title)
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

                    // Web URL
                    if let webURL = paper.webURL {
                        metadataSection("Web Link") {
                            Link(webURL.host ?? webURL.absoluteString, destination: webURL)
                        }
                    }

                    // Abstract
                    if let abstract = paper.abstract, !abstract.isEmpty {
                        metadataSection("Abstract") {
                            Text(abstract)
                                .textSelection(.enabled)
                        }
                    }

                    // Source
                    metadataSection("Source") {
                        Text(paper.sourceID)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding()
            }
            .onChange(of: paper.id, initial: true) { _, _ in
                // Scroll to top when paper changes (initial: true fires on first appear)
                proxy.scrollTo("top", anchor: .top)
            }
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

struct PaperBibTeXTabView: View {
    let paper: OnlinePaper

    @State private var bibtexContent: String = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Generating BibTeX...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if bibtexContent.isEmpty {
                ContentUnavailableView(
                    "No BibTeX",
                    systemImage: "doc.text",
                    description: Text("BibTeX is not available for this paper")
                )
            } else {
                // Read-only BibTeX display
                BibTeXEditor(
                    text: .constant(bibtexContent),
                    isEditable: false,
                    showLineNumbers: true
                ) { _ in }
            }
        }
        .onChange(of: paper.id, initial: true) { _, _ in
            // Reset state and reload when paper changes (initial: true fires on first appear)
            bibtexContent = ""
            isLoading = true
            loadBibTeX()
        }
    }

    private func loadBibTeX() {
        isLoading = true

        // Generate BibTeX locally from paper metadata - no network request needed
        let entry = generateBibTeXEntry(from: paper)
        bibtexContent = BibTeXExporter().export([entry])
        isLoading = false

        // Cache for session (fire and forget)
        Task {
            await SessionCache.shared.cacheBibTeX(bibtexContent, for: paper.id)
        }
    }
}

// MARK: - PDF Tab

struct PaperPDFTabView: View {
    let paper: OnlinePaper

    @State private var localPDFURL: URL?
    @State private var isDownloading = false
    @State private var downloadError: Error?
    @State private var hasPDF = false
    @State private var checkPDFTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let localURL = localPDFURL {
                PDFKitViewer(url: localURL)
            } else if isDownloading {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Downloading PDF...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = downloadError {
                ContentUnavailableView {
                    Label("Download Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Retry") {
                        Task { await downloadPDF() }
                    }
                }
            } else if hasPDF {
                ContentUnavailableView {
                    Label("PDF Available", systemImage: "doc.richtext")
                } description: {
                    Text("Click to download and view the PDF")
                } actions: {
                    Button("Download PDF") {
                        Task { await downloadPDF() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView(
                    "No PDF",
                    systemImage: "doc.richtext",
                    description: Text("No PDF is available for this paper.")
                )
            }
        }
        .onChange(of: paper.id, initial: true) { _, _ in
            // Cancel any in-flight task to prevent race conditions
            checkPDFTask?.cancel()

            // Reset state synchronously
            localPDFURL = nil
            downloadError = nil
            isDownloading = false
            hasPDF = false

            // Start new task
            checkPDFTask = Task {
                // Check if already cached
                if let cached = await SessionCache.shared.getCachedPDF(for: paper.id) {
                    localPDFURL = cached
                }
                // Check if PDF is available using resolver
                hasPDF = PDFURLResolver.hasPDF(paper: paper)
            }
        }
    }

    private func downloadPDF() async {
        // Use PDFURLResolver to get the best URL based on user settings
        guard let resolvedURL = await PDFURLResolver.resolve(for: paper) else {
            Logger.files.warning("[PaperPDFTabView] No PDF URL could be resolved for paper: \(paper.id)")
            return
        }

        Logger.files.infoCapture("[PaperPDFTabView] Downloading PDF from: \(resolvedURL.absoluteString)", category: "pdf")

        isDownloading = true
        downloadError = nil

        do {
            let cachedURL = try await SessionCache.shared.cachePDF(from: resolvedURL, for: paper.id)
            await MainActor.run {
                localPDFURL = cachedURL
                Logger.files.infoCapture("[PaperPDFTabView] PDF downloaded and cached: \(cachedURL.path)", category: "pdf")
            }
        } catch {
            await MainActor.run {
                downloadError = error
                Logger.files.error("[PaperPDFTabView] PDF download failed: \(error.localizedDescription)")
            }
        }

        await MainActor.run {
            isDownloading = false
        }
    }
}

#Preview {
    // Create a mock OnlinePaper for preview
    let result = SearchResult(
        id: "test-123",
        sourceID: "arxiv",
        title: "Deep Learning for Natural Language Processing",
        authors: ["John Smith", "Jane Doe", "Bob Wilson"],
        year: 2024,
        venue: "Conference on Machine Learning",
        abstract: "This paper presents a novel approach to natural language processing using deep learning techniques...",
        doi: "10.1234/example.2024.001"
    )
    let paper = OnlinePaper(result: result)

    NavigationStack {
        PaperDetailView(paper: paper)
    }
}
