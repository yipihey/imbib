//
//  IOSInfoTab.swift
//  imbib-iOS
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI
import PublicationManagerCore

/// iOS Info tab showing publication details, abstract, identifiers, and attachments.
struct IOSInfoTab: View {
    let publication: CDPublication
    let libraryID: UUID

    @Environment(LibraryManager.self) private var libraryManager
    @Environment(\.themeColors) private var theme
    @State private var showPDFBrowser = false
    @State private var showFilePicker = false
    @State private var showShareSheet = false
    @State private var fileToShare: URL?
    @State private var isDownloadingPDF = false

    // State for exploration (references/citations/similar/co-reads)
    @State private var isExploringReferences = false
    @State private var isExploringCitations = false
    @State private var isExploringSimilar = false
    @State private var isExploringCoReads = false
    @State private var explorationError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                Divider()

                // Info
                infoSection

                // Abstract
                if let abstract = publication.abstract, !abstract.isEmpty {
                    abstractSection(abstract)
                }

                // Identifiers
                identifiersSection

                // Explore
                if canExploreReferences {
                    exploreSection
                }

                // PDF Sources
                if hasPDFSources {
                    pdfSourcesSection
                }

                // Attachments
                attachmentsSection

                // Record Info
                recordInfoSection
            }
            .padding()
        }
        .sheet(isPresented: $showPDFBrowser) {
            IOSPDFBrowserView(
                publication: publication,
                library: libraryManager.find(id: libraryID),
                onPDFSaved: nil
            )
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = fileToShare {
                IOSShareSheet(items: [url])
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],  // Accept any file type
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .alert("Exploration Error", isPresented: .constant(explorationError != nil)) {
            Button("OK") {
                explorationError = nil
            }
        } message: {
            if let error = explorationError {
                Text(error)
            }
        }
        .task(id: publication.id) {
            // Auto-enrich on view if needed (for ref/cite counts)
            if publication.needsEnrichment {
                await EnrichmentCoordinator.shared.queueForEnrichment(publication, priority: .recentlyViewed)
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(publication.title ?? "Untitled")
                .font(.title2)
                .fontWeight(.semibold)

            // Authors
            if !publication.authorString.isEmpty {
                Text(publication.authorString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Year and venue
            HStack {
                if publication.year > 0 {
                    Text(String(publication.year))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let venue = venueString, !venue.isEmpty {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(venue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Read status
            HStack {
                Image(systemName: publication.isRead ? "envelope.open" : "envelope.badge.fill")
                    .foregroundStyle(publication.isRead ? Color.secondary : theme.unreadDot)
                Text(publication.isRead ? "Read" : "Unread")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Information")
                .font(.headline)

            LabeledContent("Entry Type", value: publication.entryType.capitalized)
            LabeledContent("Cite Key", value: publication.citeKey)

            LabeledContent("Date Added") {
                Text(publication.dateAdded.formatted(date: .abbreviated, time: .omitted))
            }

            if publication.citationCount > 0 {
                LabeledContent("Citations") {
                    Text("\(publication.citationCount)")
                }
            }
        }
    }

    private func abstractSection(_ abstract: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Abstract")
                .font(.headline)

            MathJaxAbstractView(text: abstract, fontSize: 14, textColor: .secondary)
        }
    }

    private var identifiersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Identifiers")
                .font(.headline)

            if let doi = publication.doi {
                Button {
                    if let url = URL(string: "https://doi.org/\(doi)") {
                        _ = FileManager_Opener.shared.openURL(url)
                    }
                } label: {
                    LabeledContent("DOI") {
                        HStack {
                            Text(doi)
                            Image(systemName: "arrow.up.right.square")
                        }
                        .foregroundStyle(theme.linkColor)
                    }
                }
            }

            if let arxivID = publication.arxivID {
                Button {
                    if let url = URL(string: "https://arxiv.org/abs/\(arxivID)") {
                        _ = FileManager_Opener.shared.openURL(url)
                    }
                } label: {
                    LabeledContent("arXiv") {
                        HStack {
                            Text(arxivID)
                            Image(systemName: "arrow.up.right.square")
                        }
                        .foregroundStyle(theme.linkColor)
                    }
                }
            }

            if let bibcode = publication.bibcode {
                Button {
                    if let url = URL(string: "https://ui.adsabs.harvard.edu/abs/\(bibcode)") {
                        _ = FileManager_Opener.shared.openURL(url)
                    }
                } label: {
                    LabeledContent("ADS") {
                        HStack {
                            Text(bibcode)
                            Image(systemName: "arrow.up.right.square")
                        }
                        .foregroundStyle(theme.linkColor)
                    }
                }
            }
        }
    }

    // MARK: - Explore Section

    /// Whether this paper can be explored via ADS (has bibcode, DOI, or arXiv ID)
    private var canExploreReferences: Bool {
        publication.bibcode != nil || publication.doi != nil || publication.arxivID != nil
    }

    /// Whether any exploration is in progress
    private var isExploring: Bool {
        isExploringReferences || isExploringCitations || isExploringSimilar || isExploringCoReads
    }

    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explore")
                .font(.headline)

            // Single row of buttons using ScrollView for horizontal overflow on smaller screens
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        showReferences()
                    } label: {
                        if isExploringReferences {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(referencesButtonLabel, systemImage: "doc.text")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExploring)

                    Button {
                        showCitations()
                    } label: {
                        if isExploringCitations {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(citationsButtonLabel, systemImage: "quote.bubble")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExploring)

                    Button {
                        showSimilar()
                    } label: {
                        if isExploringSimilar {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Similar", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExploring)

                    Button {
                        showCoReads()
                    } label: {
                        if isExploringCoReads {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Co-Reads", systemImage: "books.vertical")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExploring)
                }
            }
        }
    }

    /// Label for the references button, including count if available
    private var referencesButtonLabel: String {
        if publication.referenceCount > 0 {
            return "References (\(publication.referenceCount))"
        }
        return "References"
    }

    /// Label for the citations button, including count if available
    private var citationsButtonLabel: String {
        if publication.citationCount > 0 {
            return "Citations (\(publication.citationCount))"
        }
        return "Citations"
    }

    // MARK: - PDF Sources Section

    private var hasPDFSources: Bool {
        publication.arxivID != nil || !publication.pdfLinks.isEmpty || publication.doi != nil
    }

    private var pdfSourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PDF Sources")
                .font(.headline)

            VStack(spacing: 8) {
                // arXiv direct PDF
                if let arxivID = publication.arxivID {
                    pdfSourceRow(
                        label: "arXiv",
                        url: URL(string: "https://arxiv.org/pdf/\(arxivID).pdf"),
                        icon: "doc.text"
                    )
                }

                // PDF links from publication metadata
                ForEach(Array(publication.pdfLinks.enumerated()), id: \.offset) { index, link in
                    let sourceName = link.sourceID ?? pdfSourceName(for: link.url)
                    pdfSourceRow(
                        label: sourceName,
                        url: link.url,
                        icon: "link"
                    )
                }

                // DOI resolver fallback
                if let doi = publication.doi, publication.arxivID == nil {
                    pdfSourceRow(
                        label: "Publisher (via DOI)",
                        url: URL(string: "https://doi.org/\(doi)"),
                        icon: "globe"
                    )
                }
            }
        }
    }

    private func pdfSourceRow(label: String, url: URL?, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(label)

            Spacer()

            if let url = url {
                Button {
                    downloadPDF(from: url)
                } label: {
                    if isDownloadingPDF {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .disabled(isDownloadingPDF)
            }
        }
        .padding(.vertical, 4)
    }

    private func pdfSourceName(for url: URL) -> String {
        let host = url.host ?? ""
        if host.contains("arxiv.org") { return "arXiv" }
        if host.contains("adsabs") { return "ADS" }
        if host.contains("openalex") { return "OpenAlex" }
        if host.contains("semanticscholar") { return "Semantic Scholar" }
        if host.contains("doi.org") { return "DOI Resolver" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    // MARK: - Attachments Section

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Attachments")
                    .font(.headline)

                Spacer()

                Button {
                    showFilePicker = true
                } label: {
                    Label("Add Files", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let linkedFiles = publication.linkedFiles, !linkedFiles.isEmpty {
                ForEach(Array(linkedFiles), id: \.id) { file in
                    attachmentRow(file)
                }
            } else {
                Text("No attachments")
                    .foregroundStyle(.secondary)

                if publication.doi != nil || publication.bibcode != nil || publication.arxivID != nil {
                    Button {
                        showPDFBrowser = true
                    } label: {
                        Label("Download PDF", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func attachmentRow(_ file: CDLinkedFile) -> some View {
        HStack {
            FileTypeIcon(linkedFile: file)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName ?? file.relativePath)
                    .lineLimit(1)

                if file.fileSize > 0 {
                    Text(formatFileSize(file.fileSize))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Menu {
                Button {
                    openFile(file)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                }

                Button {
                    shareFile(file)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Divider()

                Button(role: .destructive) {
                    deleteFile(file)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Record Info Section

    private var recordInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record Info")
                .font(.headline)

            LabeledContent("Cite Key", value: publication.citeKey)
            LabeledContent("Entry Type", value: publication.entryType.capitalized)

            LabeledContent("Date Added") {
                Text(publication.dateAdded.formatted(date: .abbreviated, time: .shortened))
            }

            if publication.dateModified != publication.dateAdded {
                LabeledContent("Date Modified") {
                    Text(publication.dateModified.formatted(date: .abbreviated, time: .shortened))
                }
            }

            LabeledContent("Read Status") {
                HStack {
                    Image(systemName: publication.isRead ? "checkmark.circle" : "circle")
                    Text(publication.isRead ? "Read" : "Unread")
                }
            }

            if publication.citationCount > 0 {
                LabeledContent("Citations", value: "\(publication.citationCount)")
            }

            if publication.referenceCount > 0 {
                LabeledContent("References", value: "\(publication.referenceCount)")
            }
        }
    }

    // MARK: - Computed Properties

    private var venueString: String? {
        let fields = publication.fields
        return fields["journal"] ?? fields["booktitle"] ?? fields["publisher"]
    }

    // MARK: - Actions

    private func openFile(_ file: CDLinkedFile) {
        guard let library = libraryManager.find(id: libraryID),
              let folderURL = library.folderURL else { return }

        let fileURL = folderURL.appendingPathComponent(file.relativePath)
        _ = FileManager_Opener.shared.openFile(fileURL)
    }

    private func shareFile(_ file: CDLinkedFile) {
        guard let library = libraryManager.find(id: libraryID),
              let folderURL = library.folderURL else { return }

        let fileURL = folderURL.appendingPathComponent(file.relativePath)
        fileToShare = fileURL
        showShareSheet = true
    }

    private func deleteFile(_ file: CDLinkedFile) {
        do {
            try PDFManager.shared.delete(file, in: libraryManager.find(id: libraryID))
        } catch {
            print("Failed to delete file: \(error)")
        }
    }

    private func downloadPDF(from url: URL) {
        isDownloadingPDF = true

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)

                // Verify it's a PDF
                guard data.count >= 4,
                      data.prefix(4).elementsEqual([0x25, 0x50, 0x44, 0x46]) else {
                    // Not a PDF - open browser instead
                    await MainActor.run {
                        isDownloadingPDF = false
                        showPDFBrowser = true
                    }
                    return
                }

                try PDFManager.shared.importPDF(
                    data: data,
                    for: publication,
                    in: libraryManager.find(id: libraryID)
                )

                await MainActor.run {
                    isDownloadingPDF = false
                }
            } catch {
                await MainActor.run {
                    isDownloadingPDF = false
                    showPDFBrowser = true
                }
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let data = try Data(contentsOf: url)
                    let fileExtension = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
                    try PDFManager.shared.importAttachment(
                        data: data,
                        for: publication,
                        in: libraryManager.find(id: libraryID),
                        fileExtension: fileExtension,
                        displayName: url.lastPathComponent
                    )
                } catch {
                    print("Failed to import file: \(error)")
                }
            }
        case .failure(let error):
            print("File picker error: \(error)")
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Exploration

    /// Show references using ExplorationService
    private func showReferences() {
        isExploringReferences = true
        explorationError = nil

        Task {
            do {
                // Set up ExplorationService with enrichment service and library manager
                let enrichmentService = await EnrichmentCoordinator.shared.enrichmentService
                ExplorationService.shared.setEnrichmentService(enrichmentService)
                ExplorationService.shared.setLibraryManager(libraryManager)

                // Explore references - creates collection and navigates via notification
                _ = try await ExplorationService.shared.exploreReferences(of: publication)

                await MainActor.run {
                    isExploringReferences = false
                }
            } catch {
                await MainActor.run {
                    isExploringReferences = false
                    explorationError = error.localizedDescription
                }
            }
        }
    }

    /// Show citations using ExplorationService
    private func showCitations() {
        isExploringCitations = true
        explorationError = nil

        Task {
            do {
                // Set up ExplorationService with enrichment service and library manager
                let enrichmentService = await EnrichmentCoordinator.shared.enrichmentService
                ExplorationService.shared.setEnrichmentService(enrichmentService)
                ExplorationService.shared.setLibraryManager(libraryManager)

                // Explore citations - creates collection and navigates via notification
                _ = try await ExplorationService.shared.exploreCitations(of: publication)

                await MainActor.run {
                    isExploringCitations = false
                }
            } catch {
                await MainActor.run {
                    isExploringCitations = false
                    explorationError = error.localizedDescription
                }
            }
        }
    }

    /// Show similar papers using ExplorationService
    private func showSimilar() {
        isExploringSimilar = true
        explorationError = nil

        Task {
            do {
                // Set up ExplorationService with enrichment service and library manager
                let enrichmentService = await EnrichmentCoordinator.shared.enrichmentService
                ExplorationService.shared.setEnrichmentService(enrichmentService)
                ExplorationService.shared.setLibraryManager(libraryManager)

                // Explore similar - creates collection and navigates via notification
                _ = try await ExplorationService.shared.exploreSimilar(of: publication)

                await MainActor.run {
                    isExploringSimilar = false
                }
            } catch {
                await MainActor.run {
                    isExploringSimilar = false
                    explorationError = error.localizedDescription
                }
            }
        }
    }

    /// Show co-read papers using ExplorationService
    private func showCoReads() {
        isExploringCoReads = true
        explorationError = nil

        Task {
            do {
                // Set up ExplorationService with enrichment service and library manager
                let enrichmentService = await EnrichmentCoordinator.shared.enrichmentService
                ExplorationService.shared.setEnrichmentService(enrichmentService)
                ExplorationService.shared.setLibraryManager(libraryManager)

                // Explore co-reads - creates collection and navigates via notification
                _ = try await ExplorationService.shared.exploreCoReads(of: publication)

                await MainActor.run {
                    isExploringCoReads = false
                }
            } catch {
                await MainActor.run {
                    isExploringCoReads = false
                    explorationError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Share Sheet

/// UIActivityViewController wrapper for sharing files.
private struct IOSShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
