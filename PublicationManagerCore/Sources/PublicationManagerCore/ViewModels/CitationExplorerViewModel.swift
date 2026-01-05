//
//  CitationExplorerViewModel.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog

// MARK: - Citation Explorer View Model

/// View model for the citation explorer, managing navigation through papers
/// and their references/citations.
///
/// Provides a navigation stack for drilling into references and citations,
/// with support for breadcrumb navigation, bulk import, and enrichment.
///
/// ## Usage
///
/// ```swift
/// let viewModel = CitationExplorerViewModel(
///     enrichmentService: EnrichmentService.shared
/// )
///
/// await viewModel.start(with: paper)
/// await viewModel.pushPaper(paperStub)
/// viewModel.popPaper()
/// ```
@MainActor
@Observable
public final class CitationExplorerViewModel {

    // MARK: - Navigation Item

    /// An item in the navigation stack representing a paper being explored
    public struct NavigationItem: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let authors: [String]
        public let year: Int?
        public let identifiers: [IdentifierType: String]

        /// The enrichment data for this paper (fetched asynchronously)
        public var enrichmentData: EnrichmentData?

        /// Whether enrichment is in progress
        public var isLoading: Bool = false

        /// Error if enrichment failed
        public var error: Error?

        public init(
            id: String,
            title: String,
            authors: [String],
            year: Int? = nil,
            identifiers: [IdentifierType: String] = [:],
            enrichmentData: EnrichmentData? = nil
        ) {
            self.id = id
            self.title = title
            self.authors = authors
            self.year = year
            self.identifiers = identifiers
            self.enrichmentData = enrichmentData
        }

        public static func == (lhs: NavigationItem, rhs: NavigationItem) -> Bool {
            lhs.id == rhs.id
        }
    }

    // MARK: - Published State

    /// The navigation stack of papers being explored
    public private(set) var navigationStack: [NavigationItem] = []

    /// The current paper at the top of the stack
    public var currentPaper: NavigationItem? {
        navigationStack.last
    }

    /// Whether any loading is in progress
    public var isLoading: Bool {
        currentPaper?.isLoading ?? false
    }

    /// Whether we can go back in the navigation
    public var canGoBack: Bool {
        navigationStack.count > 1
    }

    /// Breadcrumb titles for navigation
    public var breadcrumbs: [String] {
        navigationStack.map { formatBreadcrumb(for: $0) }
    }

    // MARK: - Selection State

    /// Currently selected paper IDs for import
    public var selectedPapers: Set<String> = []

    /// Currently displayed tab (references or citations)
    public var selectedTab: ReferenceTab = .references

    // MARK: - Dependencies

    private let enrichmentService: EnrichmentService

    // MARK: - Initialization

    public init(enrichmentService: EnrichmentService) {
        self.enrichmentService = enrichmentService
    }

    // MARK: - Navigation

    /// Start exploring from a paper stub
    public func start(with stub: PaperStub) async {
        var identifiers: [IdentifierType: String] = [:]
        if let doi = stub.doi { identifiers[.doi] = doi }
        if let arxiv = stub.arxivID { identifiers[.arxiv] = arxiv }

        let item = NavigationItem(
            id: stub.id,
            title: stub.title,
            authors: stub.authors,
            year: stub.year,
            identifiers: identifiers
        )

        await pushItem(item)
    }

    /// Start exploring from a local paper
    public func start(with paper: any PaperRepresentable) async {
        let item = NavigationItem(
            id: paper.id,
            title: paper.title,
            authors: paper.authors,
            year: paper.year,
            identifiers: paper.allIdentifiers
        )

        await pushItem(item)
    }

    /// Push a new paper onto the navigation stack
    public func pushPaper(_ stub: PaperStub) async {
        var identifiers: [IdentifierType: String] = [:]
        if let doi = stub.doi { identifiers[.doi] = doi }
        if let arxiv = stub.arxivID { identifiers[.arxiv] = arxiv }

        let item = NavigationItem(
            id: stub.id,
            title: stub.title,
            authors: stub.authors,
            year: stub.year,
            identifiers: identifiers
        )

        await pushItem(item)
    }

    /// Pop the current paper from the navigation stack
    public func popPaper() {
        guard navigationStack.count > 1 else { return }
        navigationStack.removeLast()
        selectedPapers.removeAll()
        Logger.viewModels.debug("CitationExplorer: popped to \(self.currentPaper?.title ?? "root")")
    }

    /// Navigate to a specific level in the breadcrumb
    public func navigateToBreadcrumb(at index: Int) {
        guard index >= 0, index < navigationStack.count else { return }
        navigationStack.removeSubrange((index + 1)...)
        selectedPapers.removeAll()
        Logger.viewModels.debug("CitationExplorer: navigated to breadcrumb \(index)")
    }

    /// Reset navigation to the root paper only
    public func resetNavigation() {
        guard navigationStack.count > 1 else { return }
        navigationStack.removeSubrange(1...)
        selectedPapers.removeAll()
        Logger.viewModels.debug("CitationExplorer: reset to root")
    }

    // MARK: - Enrichment

    /// Refresh enrichment data for the current paper
    public func refreshCurrentEnrichment() async {
        guard var current = currentPaper else { return }

        setCurrentLoading(true)

        do {
            let result = try await enrichmentService.enrichNow(
                identifiers: current.identifiers
            )
            current.enrichmentData = result.data
            current.error = nil
            updateCurrentItem(current)
            Logger.viewModels.info("CitationExplorer: enriched \(current.title)")
        } catch {
            current.error = error
            updateCurrentItem(current)
            Logger.viewModels.error("CitationExplorer: enrichment failed: \(error.localizedDescription)")
        }

        setCurrentLoading(false)
    }

    // MARK: - Selection

    /// Toggle selection of a paper stub
    public func toggleSelection(_ stub: PaperStub) {
        if selectedPapers.contains(stub.id) {
            selectedPapers.remove(stub.id)
        } else {
            selectedPapers.insert(stub.id)
        }
    }

    /// Select all papers in the current view
    public func selectAll() {
        let papers = currentPapers
        selectedPapers = Set(papers.map { $0.id })
    }

    /// Clear all selections
    public func clearSelection() {
        selectedPapers.removeAll()
    }

    /// Get the currently visible papers (references or citations)
    public var currentPapers: [PaperStub] {
        guard let enrichment = currentPaper?.enrichmentData else { return [] }
        switch selectedTab {
        case .references:
            return enrichment.references ?? []
        case .citations:
            return enrichment.citations ?? []
        }
    }

    /// Get selected paper stubs for import
    public var selectedPaperStubs: [PaperStub] {
        currentPapers.filter { selectedPapers.contains($0.id) }
    }

    // MARK: - Private Helpers

    private func pushItem(_ item: NavigationItem) async {
        navigationStack.append(item)
        selectedPapers.removeAll()
        Logger.viewModels.debug("CitationExplorer: pushed \(item.title)")

        // Fetch enrichment for the new paper
        await refreshCurrentEnrichment()
    }

    private func setCurrentLoading(_ loading: Bool) {
        guard var current = currentPaper, !navigationStack.isEmpty else { return }
        current.isLoading = loading
        navigationStack[navigationStack.count - 1] = current
    }

    private func updateCurrentItem(_ item: NavigationItem) {
        guard !navigationStack.isEmpty else { return }
        navigationStack[navigationStack.count - 1] = item
    }

    private func formatBreadcrumb(for item: NavigationItem) -> String {
        // Use first author + year if available, otherwise truncated title
        let firstAuthor = item.authors.first ?? "Unknown"
        if let year = item.year {
            return "\(firstAuthor) (\(year))"
        } else {
            let truncated = String(item.title.prefix(20))
            return truncated.count < item.title.count ? "\(truncated)..." : truncated
        }
    }
}

// MARK: - Testing Support

extension CitationExplorerViewModel {

    /// Set up navigation stack directly for testing purposes.
    ///
    /// - Warning: This method should only be used in tests.
    public func setNavigationStack(_ items: [NavigationItem]) {
        navigationStack = items
    }
}

// MARK: - Import Support

extension CitationExplorerViewModel {

    /// Import selected papers to the library
    ///
    /// - Parameter importer: A closure that imports a paper stub and returns whether it succeeded
    /// - Returns: The number of successfully imported papers
    @discardableResult
    public func importSelected(using importer: (PaperStub) async throws -> Void) async -> Int {
        let toImport = selectedPaperStubs
        var successCount = 0

        for stub in toImport {
            do {
                try await importer(stub)
                successCount += 1
                selectedPapers.remove(stub.id)
            } catch {
                Logger.viewModels.error("CitationExplorer: failed to import \(stub.title): \(error.localizedDescription)")
            }
        }

        Logger.viewModels.info("CitationExplorer: imported \(successCount)/\(toImport.count) papers")
        return successCount
    }
}
