//
//  ShareExtensionView.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI

/// SwiftUI view for the share extension dialog.
///
/// Displays either a smart search creation form or paper import form based on
/// the type of ADS URL being shared. When a page title is provided (via JavaScript
/// preprocessing), it's used as the clean query for smart searches.
public struct ShareExtensionView: View {

    // MARK: - Properties

    /// The URL being shared
    public let sharedURL: URL

    /// The page title extracted via JavaScript preprocessing
    /// For ADS search pages, this contains the clean query
    public let pageTitle: String?

    /// Callback when user confirms the action
    public let onConfirm: (ShareExtensionService.SharedItem) -> Void

    /// Callback when user cancels
    public let onCancel: () -> Void

    // MARK: - State

    @State private var parsedURL: ADSURLParser.ADSURLType?
    @State private var smartSearchName: String = ""
    @State private var smartSearchQuery: String = ""
    @State private var selectedLibraryID: UUID?
    @State private var addToInbox: Bool = true
    @State private var isProcessing: Bool = false

    // MARK: - Environment

    private let availableLibraries: [SharedLibraryInfo]

    // MARK: - Initialization

    public init(
        sharedURL: URL,
        pageTitle: String? = nil,
        availableLibraries: [SharedLibraryInfo] = [],
        onConfirm: @escaping (ShareExtensionService.SharedItem) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sharedURL = sharedURL
        self.pageTitle = pageTitle
        self.availableLibraries = availableLibraries.isEmpty
            ? ShareExtensionService.shared.getAvailableLibraries()
            : availableLibraries
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if let urlType = parsedURL {
                switch urlType {
                case .search(let query, let title):
                    smartSearchForm(query: query, suggestedTitle: title)
                case .paper(let bibcode):
                    paperImportForm(bibcode: bibcode)
                case .docsSelection(let query):
                    docsSelectionForm(query: query)
                }
            } else {
                invalidURLView
            }
        }
        .onAppear {
            parsedURL = ADSURLParser.parse(sharedURL)
            if case .search(let urlQuery, _) = parsedURL {
                // If we have a page title from JavaScript preprocessing, use it as the query
                // The ADS page title IS the clean search query
                if let title = pageTitle, !title.isEmpty {
                    // Use page title as both the name and query
                    smartSearchName = title
                    smartSearchQuery = title
                } else {
                    // Fall back to URL-parsed query
                    smartSearchName = urlQuery
                    smartSearchQuery = urlQuery
                }
            }
            // Default to first library
            selectedLibraryID = availableLibraries.first(where: { $0.isDefault })?.id
                ?? availableLibraries.first?.id
        }
    }

    // MARK: - Smart Search Form

    private func smartSearchForm(query: String, suggestedTitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Label("Create Smart Search", systemImage: "magnifyingglass.circle")
                .font(.headline)

            // Name field
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Smart Search Name", text: $smartSearchName)
                    .textFieldStyle(.roundedBorder)
            }

            // Query preview (read-only) - show the actual query that will be used
            VStack(alignment: .leading, spacing: 4) {
                Text("Query")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(smartSearchQuery)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
            }

            // Library picker
            if !availableLibraries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Library", selection: $selectedLibraryID) {
                        ForEach(availableLibraries) { library in
                            Text(library.name).tag(library.id as UUID?)
                        }
                    }
                    .labelsHidden()
                    #if os(macOS)
                    .pickerStyle(.menu)
                    #endif
                }
            }

            Spacer()

            // Buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    confirmSmartSearch()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(smartSearchName.isEmpty || isProcessing)
            }
        }
        .padding()
        .frame(minWidth: 300, minHeight: 250)
    }

    // MARK: - Paper Import Form

    private func paperImportForm(bibcode: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Label("Import Paper", systemImage: "doc.badge.plus")
                .font(.headline)

            // Bibcode display
            VStack(alignment: .leading, spacing: 4) {
                Text("Bibcode")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(bibcode)
                    .font(.system(.body, design: .monospaced))
            }

            // Destination
            VStack(alignment: .leading, spacing: 8) {
                Text("Destination")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Toggle("Add to Inbox", isOn: $addToInbox)

                if !addToInbox && !availableLibraries.isEmpty {
                    Picker("Library", selection: $selectedLibraryID) {
                        ForEach(availableLibraries) { library in
                            Text(library.name).tag(library.id as UUID?)
                        }
                    }
                    .labelsHidden()
                    #if os(macOS)
                    .pickerStyle(.menu)
                    #endif
                }
            }

            Spacer()

            // Buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Import") {
                    confirmPaperImport(bibcode: bibcode)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isProcessing)
            }
        }
        .padding()
        .frame(minWidth: 300, minHeight: 200)
    }

    // MARK: - Docs Selection Form

    /// Form for importing papers from a temporary ADS selection (docs() URL).
    /// Always imports to Inbox - no naming or library picker needed.
    private func docsSelectionForm(query: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Label("Import Selected Papers", systemImage: "square.and.arrow.down.on.square")
                .font(.headline)

            // Info text
            Text("This will import all papers from your ADS selection to Inbox.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Query display (truncated hash)
            VStack(alignment: .leading, spacing: 4) {
                Text("Selection")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(query)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Import to Inbox") {
                    confirmDocsSelection(query: query)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isProcessing)
            }
        }
        .padding()
        .frame(minWidth: 300, minHeight: 200)
    }

    // MARK: - Invalid URL View

    private var invalidURLView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Invalid ADS URL")
                .font(.headline)

            Text("This URL is not a recognized ADS search or paper URL.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(sharedURL.absoluteString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Button("Close") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding()
        .frame(minWidth: 300, minHeight: 200)
    }

    // MARK: - Actions

    private func confirmSmartSearch() {
        isProcessing = true

        // Store the query in the name field (for the main app to create the smart search)
        // The main app will use ADSURLParser to get the URL query, but we override with pageTitle
        let item = ShareExtensionService.SharedItem(
            url: sharedURL,
            type: .smartSearch,
            name: smartSearchName,
            query: smartSearchQuery,
            libraryID: selectedLibraryID,
            createdAt: Date()
        )

        onConfirm(item)
    }

    private func confirmPaperImport(bibcode: String) {
        isProcessing = true

        let item = ShareExtensionService.SharedItem(
            url: sharedURL,
            type: .paper,
            name: nil,
            query: nil,
            libraryID: addToInbox ? nil : selectedLibraryID,
            createdAt: Date()
        )

        onConfirm(item)
    }

    private func confirmDocsSelection(query: String) {
        isProcessing = true

        let item = ShareExtensionService.SharedItem(
            url: sharedURL,
            type: .docsSelection,
            name: nil,
            query: query,
            libraryID: nil,  // Always to Inbox
            createdAt: Date()
        )

        onConfirm(item)
    }
}

// MARK: - Preview

#Preview("Smart Search URL") {
    ShareExtensionView(
        sharedURL: URL(string: "https://ui.adsabs.harvard.edu/search/q=author%3AAbel%2CTom")!,
        pageTitle: "author:Abel,Tom property:article property:refereed",
        availableLibraries: [
            SharedLibraryInfo(id: UUID(), name: "Main Library", isDefault: true),
            SharedLibraryInfo(id: UUID(), name: "Project Alpha", isDefault: false)
        ],
        onConfirm: { item in
            print("Confirmed: \(item)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}

#Preview("Paper URL") {
    ShareExtensionView(
        sharedURL: URL(string: "https://ui.adsabs.harvard.edu/abs/2024ApJ...123..456B/abstract")!,
        availableLibraries: [
            SharedLibraryInfo(id: UUID(), name: "Main Library", isDefault: true)
        ],
        onConfirm: { item in
            print("Confirmed: \(item)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}

#Preview("Invalid URL") {
    ShareExtensionView(
        sharedURL: URL(string: "https://example.com")!,
        availableLibraries: [],
        onConfirm: { _ in },
        onCancel: {}
    )
}
