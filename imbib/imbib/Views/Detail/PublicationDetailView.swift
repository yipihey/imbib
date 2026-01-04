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

                // Journal/Venue
                if let journal = publication.fields["journal"] {
                    metadataSection("Journal") {
                        Text(journal)
                            .textSelection(.enabled)
                    }
                } else if let booktitle = publication.fields["booktitle"] {
                    metadataSection("Book/Proceedings") {
                        Text(booktitle)
                            .textSelection(.enabled)
                    }
                }

                // DOI
                if let doi = publication.doi {
                    metadataSection("DOI") {
                        Link(doi, destination: URL(string: "https://doi.org/\(doi)")!)
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

    private var bibtexContent: String {
        let entry = publication.toBibTeXEntry()
        return BibTeXExporter().export([entry])
    }

    var body: some View {
        ScrollView {
            Text(bibtexContent)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
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
            .onAppear {
                notes = publication.fields["note"] ?? ""
            }
            .onChange(of: publication.id) { oldValue, newValue in
                // Save current notes before switching
                saveTask?.cancel()
                // Update notes when switching publications
                notes = publication.fields["note"] ?? ""
            }
            .onChange(of: notes) { oldValue, newValue in
                // Debounce saves - cancel previous task and schedule new one
                saveTask?.cancel()
                saveTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    await viewModel.updateField(publication, field: "note", value: newValue)
                }
            }
    }
}

#Preview {
    Text("Publication Detail Preview")
        .frame(width: 600, height: 400)
}
