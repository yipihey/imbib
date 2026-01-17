//
//  DropPreviewSheet.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-16.
//

import SwiftUI

// MARK: - Drop Preview Sheet

/// Sheet for previewing and confirming import operations from drag-and-drop.
public struct DropPreviewSheet: View {

    // MARK: - Properties

    @Binding var preview: DropPreviewData?
    let libraryID: UUID
    let coordinator: DragDropCoordinator

    @State private var pdfPreviews: [PDFImportPreview] = []
    @State private var bibPreview: BibImportPreview?
    @State private var isImporting = false
    @State private var error: Error?

    // MARK: - Initialization

    public init(
        preview: Binding<DropPreviewData?>,
        libraryID: UUID,
        coordinator: DragDropCoordinator
    ) {
        self._preview = preview
        self.libraryID = libraryID
        self.coordinator = coordinator
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Group {
                switch preview {
                case .pdfImport(let previews):
                    PDFImportPreviewView(
                        previews: previews,
                        onUpdatePreview: updatePDFPreview
                    )
                case .bibImport(let bib):
                    BibImportPreviewView(
                        preview: bib,
                        onUpdateEntry: updateBibEntry
                    )
                case .none:
                    ContentUnavailableView("No Preview", systemImage: "doc.questionmark")
                }
            }
            .navigationTitle(navigationTitle)
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 400)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        coordinator.cancelImport()
                        preview = nil
                    }
                    .disabled(isImporting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        performImport()
                    }
                    .disabled(isImporting || !canImport)
                }
            }
            .overlay {
                if isImporting {
                    ProgressView("Importing...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Import Error", isPresented: .constant(error != nil)) {
                Button("OK") {
                    error = nil
                }
            } message: {
                if let error {
                    Text(error.localizedDescription)
                }
            }
        }
        .onAppear {
            // Initialize state from preview
            switch preview {
            case .pdfImport(let previews):
                pdfPreviews = previews
            case .bibImport(let bib):
                bibPreview = bib
            case .none:
                break
            }
        }
    }

    // MARK: - Computed Properties

    private var navigationTitle: String {
        switch preview {
        case .pdfImport(let previews):
            return previews.count == 1 ? "Import PDF" : "Import \(previews.count) PDFs"
        case .bibImport(let bib):
            return "Import \(bib.format.rawValue)"
        case .none:
            return "Import"
        }
    }

    private var canImport: Bool {
        switch preview {
        case .pdfImport(let previews):
            return previews.contains { $0.selectedAction != .skip }
        case .bibImport(let bib):
            return bib.entries.contains { $0.isSelected }
        case .none:
            return false
        }
    }

    // MARK: - Actions

    private func updatePDFPreview(_ updated: PDFImportPreview) {
        if let index = pdfPreviews.firstIndex(where: { $0.id == updated.id }) {
            pdfPreviews[index] = updated
        }
    }

    private func updateBibEntry(_ entryID: UUID, isSelected: Bool) {
        guard var bib = bibPreview else { return }
        if let index = bib.entries.firstIndex(where: { $0.id == entryID }) {
            var entry = bib.entries[index]
            entry = BibImportEntry(
                id: entry.id,
                citeKey: entry.citeKey,
                entryType: entry.entryType,
                title: entry.title,
                authors: entry.authors,
                year: entry.year,
                isSelected: isSelected,
                isDuplicate: entry.isDuplicate,
                existingPublicationID: entry.existingPublicationID,
                rawContent: entry.rawContent
            )
            var entries = bib.entries
            entries[index] = entry
            bibPreview = BibImportPreview(
                id: bib.id,
                sourceURL: bib.sourceURL,
                format: bib.format,
                entries: entries,
                parseErrors: bib.parseErrors
            )
        }
    }

    private func performImport() {
        isImporting = true
        error = nil

        Task {
            do {
                switch preview {
                case .pdfImport:
                    try await coordinator.confirmPDFImport(pdfPreviews, to: libraryID)
                case .bibImport:
                    if let bib = bibPreview {
                        try await coordinator.confirmBibImport(bib, to: libraryID)
                    }
                case .none:
                    break
                }
                preview = nil
            } catch {
                self.error = error
            }
            isImporting = false
        }
    }
}

// MARK: - PDF Import Preview View

struct PDFImportPreviewView: View {

    let previews: [PDFImportPreview]
    let onUpdatePreview: (PDFImportPreview) -> Void

    @State private var selectedID: UUID?

    var body: some View {
        HSplitView {
            // List of PDFs
            List(previews, selection: $selectedID) { preview in
                PDFPreviewRow(preview: preview) { action in
                    var updated = preview
                    updated = PDFImportPreview(
                        id: preview.id,
                        sourceURL: preview.sourceURL,
                        filename: preview.filename,
                        fileSize: preview.fileSize,
                        extractedMetadata: preview.extractedMetadata,
                        enrichedMetadata: preview.enrichedMetadata,
                        isDuplicate: preview.isDuplicate,
                        existingPublication: preview.existingPublication,
                        status: preview.status,
                        selectedAction: action
                    )
                    onUpdatePreview(updated)
                }
            }
            .frame(minWidth: 200)

            // Detail view
            if let selectedID,
               let preview = previews.first(where: { $0.id == selectedID }) {
                PDFPreviewDetail(preview: preview)
            } else {
                ContentUnavailableView(
                    "Select a PDF",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select a PDF to see extracted metadata")
                )
            }
        }
        .onAppear {
            if selectedID == nil, let first = previews.first {
                selectedID = first.id
            }
        }
    }
}

// MARK: - PDF Preview Row

struct PDFPreviewRow: View {

    let preview: PDFImportPreview
    let onActionChange: (ImportAction) -> Void

    var body: some View {
        HStack {
            // Status indicator
            statusIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                // Title or filename
                Text(preview.enrichedMetadata?.title ?? preview.extractedMetadata?.bestTitle ?? preview.filename)
                    .font(.headline)
                    .lineLimit(1)

                // Metadata summary
                HStack(spacing: 8) {
                    if let authors = preview.enrichedMetadata?.authors, !authors.isEmpty {
                        Text(authors.first ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let year = preview.enrichedMetadata?.year {
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if preview.isDuplicate {
                        Label("Duplicate", systemImage: "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            // Action picker
            Picker("", selection: Binding(
                get: { preview.selectedAction },
                set: { onActionChange($0) }
            )) {
                Text("Import").tag(ImportAction.importAsNew)
                if preview.isDuplicate {
                    Text("Attach").tag(ImportAction.attachToExisting)
                    Text("Replace").tag(ImportAction.replace)
                }
                Text("Skip").tag(ImportAction.skip)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 100)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch preview.status {
        case .pending, .ready:
            Image(systemName: "doc.fill")
                .foregroundStyle(.blue)
        case .extractingMetadata, .enriching:
            ProgressView()
                .scaleEffect(0.6)
        case .importing:
            ProgressView()
                .scaleEffect(0.6)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        case .skipped:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - PDF Preview Detail

struct PDFPreviewDetail: View {

    let preview: PDFImportPreview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // File info
                GroupBox("File") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Filename", value: preview.filename)
                        LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: preview.fileSize, countStyle: .file))
                    }
                }

                // Extracted metadata
                if let extracted = preview.extractedMetadata {
                    GroupBox("Extracted from PDF") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let title = extracted.bestTitle {
                                LabeledContent("Title", value: title)
                            }
                            if let author = extracted.author {
                                LabeledContent("Author", value: author)
                            }
                            if let doi = extracted.extractedDOI {
                                LabeledContent("DOI", value: doi)
                            }
                            if let arxiv = extracted.extractedArXivID {
                                LabeledContent("arXiv", value: arxiv)
                            }
                            HStack {
                                Text("Confidence")
                                Spacer()
                                confidenceBadge(extracted.confidence)
                            }
                        }
                    }
                }

                // Enriched metadata
                if let enriched = preview.enrichedMetadata {
                    GroupBox("Found Online (\(enriched.source))") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let title = enriched.title {
                                LabeledContent("Title", value: title)
                            }
                            if !enriched.authors.isEmpty {
                                LabeledContent("Authors", value: enriched.authors.joined(separator: ", "))
                            }
                            if let year = enriched.year {
                                LabeledContent("Year", value: String(year))
                            }
                            if let journal = enriched.journal {
                                LabeledContent("Journal", value: journal)
                            }
                            if let doi = enriched.doi {
                                LabeledContent("DOI", value: doi)
                            }
                            if let arxiv = enriched.arxivID {
                                LabeledContent("arXiv", value: arxiv)
                            }
                        }
                    }
                }

                // Duplicate warning
                if preview.isDuplicate {
                    GroupBox {
                        Label("This PDF may be a duplicate of an existing publication.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func confidenceBadge(_ confidence: MetadataConfidence) -> some View {
        let (text, color): (String, Color) = switch confidence {
        case .none: ("None", .red)
        case .low: ("Low", .orange)
        case .medium: ("Medium", .yellow)
        case .high: ("High", .green)
        }

        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Bib Import Preview View

struct BibImportPreviewView: View {

    let preview: BibImportPreview
    let onUpdateEntry: (UUID, Bool) -> Void

    @State private var selectedID: UUID?

    var body: some View {
        HSplitView {
            // List of entries
            List(preview.entries, selection: $selectedID) { entry in
                BibEntryRow(entry: entry) { isSelected in
                    onUpdateEntry(entry.id, isSelected)
                }
            }
            .frame(minWidth: 200)

            // Detail view
            if let selectedID,
               let entry = preview.entries.first(where: { $0.id == selectedID }) {
                BibEntryDetail(entry: entry)
            } else {
                ContentUnavailableView(
                    "Select an entry",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select an entry to see details")
                )
            }
        }
        .onAppear {
            if selectedID == nil, let first = preview.entries.first {
                selectedID = first.id
            }
        }
    }
}

// MARK: - Bib Entry Row

struct BibEntryRow: View {

    let entry: BibImportEntry
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { entry.isSelected },
                set: { onToggle($0) }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title ?? entry.citeKey)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(entry.isDuplicate ? .secondary : .primary)

                HStack(spacing: 8) {
                    Text(entry.citeKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let year = entry.year {
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if entry.isDuplicate {
                        Label("Duplicate", systemImage: "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Bib Entry Detail

struct BibEntryDetail: View {

    let entry: BibImportEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Entry") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Cite Key", value: entry.citeKey)
                        LabeledContent("Type", value: entry.entryType)
                        if let title = entry.title {
                            LabeledContent("Title", value: title)
                        }
                        if !entry.authors.isEmpty {
                            LabeledContent("Authors", value: entry.authors.joined(separator: ", "))
                        }
                        if let year = entry.year {
                            LabeledContent("Year", value: String(year))
                        }
                    }
                }

                if let raw = entry.rawContent {
                    GroupBox("Raw Content") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(raw)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }

                if entry.isDuplicate {
                    GroupBox {
                        Label("An entry with this cite key already exists.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Preview

#Preview {
    let pdfPreview = PDFImportPreview(
        sourceURL: URL(fileURLWithPath: "/tmp/test.pdf"),
        filename: "Einstein_1905_Relativity.pdf",
        fileSize: 1024 * 1024 * 2,
        extractedMetadata: PDFExtractedMetadata(
            title: "On the Electrodynamics of Moving Bodies",
            author: "A. Einstein",
            extractedDOI: "10.1002/andp.19053221004",
            confidence: .high
        ),
        enrichedMetadata: EnrichedMetadata(
            title: "On the Electrodynamics of Moving Bodies",
            authors: ["Albert Einstein"],
            year: 1905,
            journal: "Annalen der Physik",
            doi: "10.1002/andp.19053221004",
            source: "Crossref"
        )
    )

    DropPreviewSheet(
        preview: .constant(.pdfImport([pdfPreview])),
        libraryID: UUID(),
        coordinator: DragDropCoordinator.shared
    )
}
