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
/// the type of ADS URL being shared.
public struct ShareExtensionView: View {

    // MARK: - Properties

    /// The URL being shared
    public let sharedURL: URL

    /// Callback when user confirms the action
    public let onConfirm: (ShareExtensionService.SharedItem) -> Void

    /// Callback when user cancels
    public let onCancel: () -> Void

    // MARK: - State

    @State private var parsedURL: ADSURLParser.ADSURLType?
    @State private var smartSearchName: String = ""
    @State private var selectedLibraryID: UUID?
    @State private var addToInbox: Bool = true
    @State private var isProcessing: Bool = false

    // MARK: - Environment

    private let availableLibraries: [SharedLibraryInfo]

    // MARK: - Initialization

    public init(
        sharedURL: URL,
        availableLibraries: [SharedLibraryInfo] = [],
        onConfirm: @escaping (ShareExtensionService.SharedItem) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sharedURL = sharedURL
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
                }
            } else {
                invalidURLView
            }
        }
        .onAppear {
            parsedURL = ADSURLParser.parse(sharedURL)
            if case .search(_, let title) = parsedURL {
                smartSearchName = title ?? ""
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

            // Query preview (read-only)
            VStack(alignment: .leading, spacing: 4) {
                Text("Query")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(query)
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
                    confirmSmartSearch(query: query)
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

    private func confirmSmartSearch(query: String) {
        isProcessing = true

        let item = ShareExtensionService.SharedItem(
            url: sharedURL,
            type: .smartSearch,
            name: smartSearchName,
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
            libraryID: addToInbox ? nil : selectedLibraryID,
            createdAt: Date()
        )

        onConfirm(item)
    }
}

// MARK: - Preview

#Preview("Smart Search URL") {
    ShareExtensionView(
        sharedURL: URL(string: "https://ui.adsabs.harvard.edu/search/q=author%3AAbel%2CTom")!,
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
