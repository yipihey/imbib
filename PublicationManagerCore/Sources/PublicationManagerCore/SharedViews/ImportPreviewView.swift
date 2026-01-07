//
//  ImportPreviewView.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import OSLog
#if os(macOS)
import AppKit
#endif

// MARK: - Import Preview Entry

/// A unified preview entry that can represent either BibTeX or RIS data.
public struct ImportPreviewEntry: Identifiable {
    public let id: String
    public let title: String
    public let authors: String
    public let year: String
    public let entryType: String
    public let source: ImportSource
    public var isSelected: Bool

    public enum ImportSource {
        case bibtex(BibTeXEntry)
        case ris(RISEntry)
    }

    public init(from entry: BibTeXEntry) {
        self.id = entry.citeKey
        self.title = entry.fields["title"] ?? "Untitled"
        self.authors = entry.fields["author"] ?? "Unknown"
        self.year = entry.fields["year"] ?? ""
        self.entryType = entry.entryType
        self.source = .bibtex(entry)
        self.isSelected = true
    }

    public init(from entry: RISEntry) {
        self.id = entry.id
        self.title = entry.title ?? "Untitled"
        self.authors = entry.authors.joined(separator: "; ")
        self.year = entry.year.map(String.init) ?? ""
        self.entryType = entry.type.rawValue
        self.source = .ris(entry)
        self.isSelected = true
    }
}

// MARK: - Import Preview View

/// View for previewing entries before import.
public struct ImportPreviewView: View {

    // MARK: - Properties

    @Binding var isPresented: Bool
    let fileURL: URL
    let onImport: ([ImportPreviewEntry]) async throws -> Int

    @State private var entries: [ImportPreviewEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var importResult: Int?
    @State private var selectedEntryID: String?

    // MARK: - Initialization

    public init(
        isPresented: Binding<Bool>,
        fileURL: URL,
        onImport: @escaping ([ImportPreviewEntry]) async throws -> Int
    ) {
        self._isPresented = isPresented
        self.fileURL = fileURL
        self.onImport = onImport
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import Preview")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 450)
        #endif
        .task {
            await parseFile()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingView
        } else if let error = errorMessage {
            errorView(error)
        } else if entries.isEmpty {
            emptyView
        } else {
            entryList
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Parsing \(fileURL.lastPathComponent)...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Parse Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Close") {
                isPresented = false
            }
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Entries Found", systemImage: "doc.text")
        } description: {
            Text("The file doesn't contain any valid entries.")
        } actions: {
            Button("Close") {
                isPresented = false
            }
        }
    }

    private var entryList: some View {
        VStack(spacing: 0) {
            // Header with stats
            headerBar

            Divider()

            // Split view: list on left, detail on right
            #if os(macOS)
            HSplitView {
                // Entry list
                List(selection: $selectedEntryID) {
                    ForEach($entries) { $entry in
                        ImportPreviewRow(entry: $entry)
                            .tag(entry.id)
                    }
                }
                .listStyle(.inset)
                .frame(minWidth: 250)

                // Detail view
                if let entry = entries.first(where: { $0.id == selectedEntryID }) {
                    ImportPreviewDetail(entry: entry)
                        .frame(minWidth: 300)
                } else {
                    Text("Select an entry to view details")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            #else
            // iOS: List only, tap to see detail in sheet
            List(selection: $selectedEntryID) {
                ForEach($entries) { $entry in
                    ImportPreviewRow(entry: $entry)
                        .tag(entry.id)
                }
            }
            .listStyle(.inset)
            .sheet(item: Binding(
                get: { entries.first { $0.id == selectedEntryID } },
                set: { _ in selectedEntryID = nil }
            )) { entry in
                NavigationStack {
                    ImportPreviewDetail(entry: entry)
                        .navigationTitle("Entry Details")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { selectedEntryID = nil }
                            }
                        }
                }
            }
            #endif
        }
    }

    private var headerBar: some View {
        HStack {
            // File info
            Label(fileURL.lastPathComponent, systemImage: formatIcon)
                .font(.headline)

            Spacer()

            // Selection controls
            let selectedCount = entries.filter(\.isSelected).count

            Text("\(selectedCount) of \(entries.count) selected")
                .foregroundStyle(.secondary)

            Button("Select All") {
                for i in entries.indices {
                    entries[i].isSelected = true
                }
            }
            .disabled(selectedCount == entries.count)

            Button("Deselect All") {
                for i in entries.indices {
                    entries[i].isSelected = false
                }
            }
            .disabled(selectedCount == 0)
        }
        .padding()
        .background(.bar)
    }

    private var formatIcon: String {
        switch fileURL.pathExtension.lowercased() {
        case "bib", "bibtex":
            return "text.badge.checkmark"
        case "ris":
            return "doc.badge.arrow.up"
        default:
            return "doc.text"
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                isPresented = false
            }
            .disabled(isImporting)
        }

        ToolbarItem(placement: .confirmationAction) {
            if isImporting {
                ProgressView()
                    .scaleEffect(0.8)
            } else if let count = importResult {
                Label("Imported \(count)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Import") {
                    Task { await performImport() }
                }
                .disabled(entries.filter(\.isSelected).isEmpty)
            }
        }
    }

    // MARK: - Actions

    private func parseFile() async {
        isLoading = true
        errorMessage = nil

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let ext = fileURL.pathExtension.lowercased()

            switch ext {
            case "bib", "bibtex":
                let parser = BibTeXParser()
                let bibtexEntries = try parser.parseEntries(content)
                entries = bibtexEntries.map { ImportPreviewEntry(from: $0) }

            case "ris":
                let parser = RISParser()
                let risEntries = try parser.parse(content)
                entries = risEntries.map { ImportPreviewEntry(from: $0) }

            default:
                throw ImportError.unsupportedFormat(ext)
            }

            // Auto-select first entry
            selectedEntryID = entries.first?.id

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func performImport() async {
        isImporting = true

        do {
            let selected = entries.filter(\.isSelected)
            let count = try await onImport(selected)
            importResult = count

            // Close after short delay
            try? await Task.sleep(for: .seconds(1))
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
            isImporting = false
        }
    }
}

// MARK: - Import Preview Row

struct ImportPreviewRow: View {
    @Binding var entry: ImportPreviewEntry

    var body: some View {
        HStack {
            Toggle("", isOn: $entry.isSelected)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .lineLimit(2)
                    .font(.body)

                HStack(spacing: 8) {
                    Text(entry.authors)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)

                    if !entry.year.isEmpty {
                        Text("(\(entry.year))")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
            }

            Spacer()

            Text(entry.entryType)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.fill.tertiary)
                .clipShape(Capsule())
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Import Preview Detail

struct ImportPreviewDetail: View {
    let entry: ImportPreviewEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text(entry.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .textSelection(.enabled)

                // Metadata
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Authors")
                            .foregroundStyle(.secondary)
                        Text(entry.authors)
                            .textSelection(.enabled)
                    }

                    if !entry.year.isEmpty {
                        GridRow {
                            Text("Year")
                                .foregroundStyle(.secondary)
                            Text(entry.year)
                        }
                    }

                    GridRow {
                        Text("Type")
                            .foregroundStyle(.secondary)
                        Text(entry.entryType)
                    }

                    GridRow {
                        Text("Cite Key")
                            .foregroundStyle(.secondary)
                        Text(entry.id)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                Divider()

                // Raw content preview
                Text("Raw Entry")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: true) {
                    Text(rawContent)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding()
                .background(.fill.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding()
        }
    }

    private var rawContent: String {
        switch entry.source {
        case .bibtex(let bibtex):
            return bibtex.rawBibTeX ?? BibTeXExporter().export([bibtex])
        case .ris(let ris):
            return ris.rawRIS ?? RISExporter().export([ris])
        }
    }
}

// MARK: - Preview

#Preview("Import Preview") {
    ImportPreviewView(
        isPresented: .constant(true),
        fileURL: URL(fileURLWithPath: "/tmp/sample.bib")
    ) { entries in
        try? await Task.sleep(for: .seconds(1))
        return entries.count
    }
}
