//
//  CitationExplorerSheet.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI

// MARK: - Citation Explorer Sheet

/// A sheet for exploring citations and references with recursive navigation.
///
/// Provides a drill-down interface for exploring the citation graph of a paper,
/// with support for bulk import and breadcrumb navigation.
///
/// ## Usage
///
/// ```swift
/// .sheet(isPresented: $showExplorer) {
///     CitationExplorerSheet(
///         viewModel: explorerViewModel,
///         onImport: { stubs in
///             for stub in stubs {
///                 try await importPaper(stub)
///             }
///         },
///         onDismiss: { showExplorer = false }
///     )
/// }
/// ```
public struct CitationExplorerSheet: View {

    // MARK: - Properties

    @Bindable public var viewModel: CitationExplorerViewModel

    /// Action to import papers
    public var onImport: (([PaperStub]) async throws -> Void)?

    /// Action when sheet is dismissed
    public var onDismiss: (() -> Void)?

    // MARK: - State

    @State private var isImporting: Bool = false
    @State private var importError: Error?
    @State private var showImportError: Bool = false

    // MARK: - Initialization

    public init(
        viewModel: CitationExplorerViewModel,
        onImport: (([PaperStub]) async throws -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onImport = onImport
        self.onDismiss = onDismiss
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Breadcrumb navigation
                if viewModel.canGoBack {
                    breadcrumbBar
                }

                // Current paper header
                if let paper = viewModel.currentPaper {
                    currentPaperHeader(paper)
                }

                // Tab picker
                Picker("View", selection: $viewModel.selectedTab) {
                    Text("References (\(referenceCount))").tag(ReferenceTab.references)
                    Text("Citations (\(citationCount))").tag(ReferenceTab.citations)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Content
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.currentPapers.isEmpty {
                    emptyStateView
                } else {
                    paperListView
                }

                // Import bar
                if !viewModel.selectedPapers.isEmpty && onImport != nil {
                    importBar
                }
            }
            .navigationTitle("Citation Explorer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss?()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await viewModel.refreshCurrentEnrichment()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .alert("Import Error", isPresented: $showImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let error = importError {
                    Text(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Subviews

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(viewModel.breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        viewModel.navigateToBreadcrumb(at: index)
                    } label: {
                        Text(crumb)
                            .font(.caption)
                            .foregroundStyle(index == viewModel.breadcrumbs.count - 1 ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.secondary.opacity(0.1))
    }

    private func currentPaperHeader(_ paper: CitationExplorerViewModel.NavigationItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(paper.title)
                .font(.headline)
                .lineLimit(2)

            Text(formatAuthors(paper.authors))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let year = paper.year {
                Text(String(year))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = paper.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.05))
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading enrichment data...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: viewModel.selectedTab == .references ? "doc.text" : "quote.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(viewModel.selectedTab == .references ? "No References" : "No Citations")
                .font(.headline)

            Text("No data available for this paper.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Retry") {
                Task {
                    await viewModel.refreshCurrentEnrichment()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var paperListView: some View {
        List {
            ForEach(viewModel.currentPapers) { stub in
                ExplorerPaperRow(
                    paper: stub,
                    isSelected: viewModel.selectedPapers.contains(stub.id),
                    onSelect: {
                        viewModel.toggleSelection(stub)
                    },
                    onNavigate: {
                        Task {
                            await viewModel.pushPaper(stub)
                        }
                    }
                )
            }
        }
        .listStyle(.plain)
    }

    private var importBar: some View {
        HStack {
            Text("\(viewModel.selectedPapers.count) selected")
                .foregroundStyle(.secondary)

            Spacer()

            Button("Clear") {
                viewModel.clearSelection()
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    await importSelected()
                }
            } label: {
                if isImporting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Label("Import", systemImage: "plus.circle")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isImporting)
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Computed Properties

    private var referenceCount: Int {
        viewModel.currentPaper?.enrichmentData?.references?.count ??
        viewModel.currentPaper?.enrichmentData?.referenceCount ?? 0
    }

    private var citationCount: Int {
        viewModel.currentPaper?.enrichmentData?.citations?.count ??
        viewModel.currentPaper?.enrichmentData?.citationCount ?? 0
    }

    // MARK: - Actions

    private func importSelected() async {
        guard let onImport = onImport else { return }

        isImporting = true

        do {
            let stubs = viewModel.selectedPaperStubs
            try await onImport(stubs)
            viewModel.clearSelection()
        } catch {
            importError = error
            showImportError = true
        }

        isImporting = false
    }

    // MARK: - Helpers

    private func formatAuthors(_ authors: [String]) -> String {
        if authors.isEmpty {
            return "Unknown authors"
        } else if authors.count == 1 {
            return authors[0]
        } else if authors.count <= 3 {
            return authors.joined(separator: ", ")
        } else {
            return "\(authors[0]) et al."
        }
    }
}

// MARK: - Explorer Paper Row

/// A row for papers in the citation explorer
public struct ExplorerPaperRow: View {

    public let paper: PaperStub
    public let isSelected: Bool
    public var onSelect: (() -> Void)?
    public var onNavigate: (() -> Void)?

    @State private var libraryState: LibraryState = .unknown

    public init(
        paper: PaperStub,
        isSelected: Bool,
        onSelect: (() -> Void)? = nil,
        onNavigate: (() -> Void)? = nil
    ) {
        self.paper = paper
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onNavigate = onNavigate
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Selection indicator
            selectionIndicator
                .onTapGesture {
                    if libraryState != .inLibrary {
                        onSelect?()
                    }
                }

            // Paper content
            VStack(alignment: .leading, spacing: 4) {
                Text(paper.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Text(authorString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let year = paper.year {
                        Text(String(year))
                            .font(.caption2)
                    }

                    if let venue = paper.venue {
                        Text(venue)
                            .font(.caption2)
                            .lineLimit(1)
                    }

                    if let count = paper.citationCount, count > 0 {
                        Label("\(count)", systemImage: "quote.bubble")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Navigate button
            Button {
                onNavigate?()
            } label: {
                Image(systemName: "chevron.right.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .task {
            await checkLibraryState()
        }
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        switch libraryState {
        case .inLibrary:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case .checking:
            ProgressView()
                .scaleEffect(0.6)

        case .notInLibrary, .unknown:
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
    }

    private var authorString: String {
        if paper.authors.isEmpty {
            return "Unknown authors"
        } else if paper.authors.count == 1 {
            return paper.authors[0]
        } else if paper.authors.count <= 3 {
            return paper.authors.joined(separator: ", ")
        } else {
            return "\(paper.authors[0]) et al."
        }
    }

    private func checkLibraryState() async {
        libraryState = .checking

        var identifiers: [IdentifierType: String] = [:]
        if let doi = paper.doi {
            identifiers[.doi] = doi
        }
        if let arxivID = paper.arxivID {
            identifiers[.arxiv] = arxivID
        }

        if !identifiers.isEmpty {
            let isInLibrary = await DefaultLibraryLookupService.shared.contains(
                identifiers: identifiers
            )
            libraryState = isInLibrary ? .inLibrary : .notInLibrary
        } else {
            libraryState = .unknown
        }
    }
}

// MARK: - Preview

#Preview("Citation Explorer") {
    // Preview shows static content since we can't easily mock EnrichmentService
    Text("Citation Explorer Preview")
        .font(.headline)
}
