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
    @State private var showPDFBrowser = false

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

                // Attachments
                attachmentsSection
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
                    .foregroundStyle(publication.isRead ? Color.secondary : Color.blue)
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

            ScientificTextParser.text(abstract)
                .font(.body)
                .foregroundStyle(.secondary)
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
                        .foregroundStyle(.blue)
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
                        .foregroundStyle(.blue)
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
                        .foregroundStyle(.blue)
                    }
                }
            }
        }
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attachments")
                .font(.headline)

            if let linkedFiles = publication.linkedFiles, !linkedFiles.isEmpty {
                ForEach(Array(linkedFiles), id: \.id) { file in
                    HStack {
                        FileTypeIcon(linkedFile: file)
                        Text(file.displayName ?? file.relativePath)
                            .lineLimit(1)
                        Spacer()
                        if file.isPDF {
                            Button("View") {
                                openFile(file)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            } else {
                Text("No attachments")
                    .foregroundStyle(.secondary)

                if publication.doi != nil || publication.bibcode != nil {
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
}
