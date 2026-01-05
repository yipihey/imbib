//
//  PublicationDetailView.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore

struct PublicationDetailView: View {

    // MARK: - Properties

    let publication: CDPublication

    // MARK: - State

    @State private var selectedTab: DetailTab = .metadata

    // MARK: - Body

    var body: some View {
        TabView(selection: $selectedTab) {
            MetadataTabView(publication: publication)
                .tabItem { Label("Metadata", systemImage: "doc.text") }
                .tag(DetailTab.metadata)

            BibTeXTabView(publication: publication)
                .tabItem { Label("BibTeX", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag(DetailTab.bibtex)

            PDFTabView(publication: publication)
                .tabItem { Label("PDF", systemImage: "doc.richtext") }
                .tag(DetailTab.pdf)

            NotesTabView(publication: publication)
                .tabItem { Label("Notes", systemImage: "note.text") }
                .tag(DetailTab.notes)
        }
        .navigationTitle(publication.title ?? "Untitled")
        #if os(macOS)
        .navigationSubtitle(publication.citeKey)
        #endif
        .toolbar {
            toolbarContent
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                openPDF()
            } label: {
                Label("Open PDF", systemImage: "doc.richtext")
            }
            .disabled((publication.linkedFiles ?? []).isEmpty)

            Button {
                copyBibTeX()
            } label: {
                Label("Copy BibTeX", systemImage: "doc.on.doc")
            }

            ShareLink(item: publication.citeKey) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: - Actions

    private func openPDF() {
        // TODO: Implement PDF opening
    }

    private func copyBibTeX() {
        let entry = publication.toBibTeXEntry()
        let bibtex = BibTeXExporter().export([entry])

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bibtex, forType: .string)
        #endif
    }
}

// MARK: - Detail Tab

enum DetailTab: String, CaseIterable {
    case metadata
    case bibtex
    case pdf
    case notes
}

// MARK: - Metadata Tab

struct MetadataTabView: View {
    let publication: CDPublication

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                metadataSection("Title") {
                    Text(publication.title ?? "Untitled")
                        .textSelection(.enabled)
                }

                // Authors
                metadataSection("Authors") {
                    Text(publication.authorString.isEmpty ? "Unknown" : publication.authorString)
                        .textSelection(.enabled)
                }

                // Year
                if publication.year > 0 {
                    metadataSection("Year") {
                        Text(String(publication.year))
                    }
                }

                // Journal/Venue (expand macros to full names)
                if let journal = publication.fields["journal"] {
                    metadataSection("Journal") {
                        Text(JournalMacros.expand(journal))
                            .textSelection(.enabled)
                    }
                } else if let booktitle = publication.fields["booktitle"] {
                    metadataSection("Book/Proceedings") {
                        Text(JournalMacros.expand(booktitle))
                            .textSelection(.enabled)
                    }
                }

                // DOI
                if let doi = publication.doi {
                    metadataSection("DOI") {
                        Link(doi, destination: URL(string: "https://doi.org/\(doi)")!)
                    }
                }

                // URL field
                if let urlString = publication.fields["url"], let url = URL(string: urlString) {
                    metadataSection("URL") {
                        Link(url.host ?? urlString, destination: url)
                    }
                }

                // BibDesk URLs (bdsk-url-1, bdsk-url-2, etc.)
                let bdskURLs = publication.fields
                    .filter { $0.key.hasPrefix("bdsk-url-") }
                    .sorted { $0.key < $1.key }
                    .compactMap { URL(string: $0.value) }

                if !bdskURLs.isEmpty {
                    metadataSection("Web Links") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(bdskURLs, id: \.absoluteString) { url in
                                Link(url.host ?? url.absoluteString, destination: url)
                            }
                        }
                    }
                }

                // Abstract
                if let abstract = publication.abstract, !abstract.isEmpty {
                    metadataSection("Abstract") {
                        Text(abstract)
                            .textSelection(.enabled)
                    }
                }

                // Keywords
                if let keywords = publication.fields["keywords"], !keywords.isEmpty {
                    metadataSection("Keywords") {
                        Text(keywords)
                            .textSelection(.enabled)
                    }
                }

                Spacer()
            }
            .padding()
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

struct BibTeXTabView: View {
    let publication: CDPublication

    @Environment(LibraryViewModel.self) private var viewModel
    @State private var bibtexContent: String = ""
    @State private var isEditing = false
    @State private var hasChanges = false

    // Use ObjectIdentifier for safe comparison (avoids Core Data UUID bridging issues)
    private var publicationIdentity: ObjectIdentifier {
        ObjectIdentifier(publication)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                if isEditing {
                    Button("Cancel") {
                        // Revert to original
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

            // Editor
            BibTeXEditor(
                text: $bibtexContent,
                isEditable: isEditing,
                showLineNumbers: true
            ) { newContent in
                saveBibTeX()
            }
            .onChange(of: bibtexContent) { _, _ in
                if isEditing {
                    hasChanges = true
                }
            }
        }
        .onChange(of: publicationIdentity, initial: true) { _, _ in
            // Reset state and reload when publication changes (initial: true fires on first appear)
            bibtexContent = generateBibTeX()
            isEditing = false
            hasChanges = false
        }
    }

    private func generateBibTeX() -> String {
        let entry = publication.toBibTeXEntry()
        return BibTeXExporter().export([entry])
    }

    private func saveBibTeX() {
        Task {
            do {
                // Parse the edited BibTeX
                let items = try BibTeXParser().parse(bibtexContent)
                // Extract the first entry from parsed items
                guard let entry = items.compactMap({ item -> BibTeXEntry? in
                    if case .entry(let entry) = item { return entry }
                    return nil
                }).first else {
                    return
                }

                // Update the publication with new values
                await viewModel.updateFromBibTeX(publication, entry: entry)

                await MainActor.run {
                    isEditing = false
                    hasChanges = false
                }
            } catch {
                // TODO: Show error to user
                print("Failed to parse BibTeX: \(error)")
            }
        }
    }
}

// MARK: - PDF Tab

struct PDFTabView: View {
    let publication: CDPublication
    @Environment(LibraryManager.self) private var libraryManager

    var body: some View {
        let linkedFiles = publication.linkedFiles ?? []
        if let firstFile = linkedFiles.first(where: { $0.isPDF }) ?? linkedFiles.first {
            PDFViewerWithControls(
                linkedFile: firstFile,
                library: libraryManager.activeLibrary
            )
        } else {
            noPDFView
        }
    }

    private var noPDFView: some View {
        ContentUnavailableView {
            Label("No PDF", systemImage: "doc.richtext")
        } description: {
            Text("This publication has no linked PDF file.")
        } actions: {
            Button("Add PDF...") {
                // TODO: Implement PDF linking
            }
        }
    }
}

// MARK: - Notes Tab

struct NotesTabView: View {
    let publication: CDPublication

    @Environment(LibraryViewModel.self) private var viewModel
    @State private var notes: String = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        TextEditor(text: $notes)
            .font(.body)
            .padding()
            .onChange(of: publication.id, initial: true) { _, _ in
                // Reset state when publication changes (initial: true fires on first appear)
                saveTask?.cancel()
                notes = publication.fields["note"] ?? ""
            }
            .onChange(of: notes) { oldValue, newValue in
                // Capture current publication to guard against race condition
                // (user might switch publications during the 500ms debounce delay)
                let targetPublication = publication

                // Debounce saves - cancel previous task and schedule new one
                saveTask?.cancel()
                saveTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    // Only save if still viewing same publication
                    guard targetPublication.id == self.publication.id else { return }
                    await viewModel.updateField(targetPublication, field: "note", value: newValue)
                }
            }
    }
}

#Preview {
    Text("Publication Detail Preview")
        .frame(width: 600, height: 400)
}
