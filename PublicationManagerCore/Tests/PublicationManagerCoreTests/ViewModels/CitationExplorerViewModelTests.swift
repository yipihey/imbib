//
//  CitationExplorerViewModelTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-04.
//

import XCTest
@testable import PublicationManagerCore

/// Tests for CitationExplorerViewModel navigation, selection, and state management.
///
/// Note: These tests focus on the synchronous behavior of the ViewModel.
/// Integration tests with actual EnrichmentService would be in a separate file.
@MainActor
final class CitationExplorerViewModelTests: XCTestCase {

    // MARK: - NavigationItem Tests

    func testNavigationItem_equality() {
        let item1 = CitationExplorerViewModel.NavigationItem(
            id: "test-1",
            title: "Test Paper",
            authors: ["Author"]
        )
        let item2 = CitationExplorerViewModel.NavigationItem(
            id: "test-1",
            title: "Different Title",
            authors: ["Different Author"]
        )
        let item3 = CitationExplorerViewModel.NavigationItem(
            id: "test-2",
            title: "Test Paper",
            authors: ["Author"]
        )

        // Same ID = equal
        XCTAssertEqual(item1, item2)
        // Different ID = not equal
        XCTAssertNotEqual(item1, item3)
    }

    func testNavigationItem_identifiers() {
        let item = CitationExplorerViewModel.NavigationItem(
            id: "test",
            title: "Paper",
            authors: [],
            identifiers: [.doi: "10.1234/test", .arxiv: "2301.00001"]
        )

        XCTAssertEqual(item.identifiers[.doi], "10.1234/test")
        XCTAssertEqual(item.identifiers[.arxiv], "2301.00001")
    }

    func testNavigationItem_enrichmentData() {
        var item = CitationExplorerViewModel.NavigationItem(
            id: "test",
            title: "Paper",
            authors: []
        )

        XCTAssertNil(item.enrichmentData)

        item.enrichmentData = EnrichmentData(
            citationCount: 100,
            source: .semanticScholar
        )

        XCTAssertEqual(item.enrichmentData?.citationCount, 100)
    }

    // MARK: - Selection Tests

    func testToggleSelection_addsToSet() {
        // Create a fresh viewmodel with a mock service for these tests
        let viewModel = createViewModelWithMockStack()

        let stub = PaperStub(id: "s1", title: "Paper 1", authors: [])

        viewModel.toggleSelection(stub)

        XCTAssertTrue(viewModel.selectedPapers.contains("s1"))
    }

    func testToggleSelection_removesFromSet() {
        let viewModel = createViewModelWithMockStack()
        viewModel.selectedPapers.insert("s1")

        let stub = PaperStub(id: "s1", title: "Paper 1", authors: [])
        viewModel.toggleSelection(stub)

        XCTAssertFalse(viewModel.selectedPapers.contains("s1"))
    }

    func testClearSelection_emptiesSet() {
        let viewModel = createViewModelWithMockStack()
        viewModel.selectedPapers = ["a", "b", "c"]

        viewModel.clearSelection()

        XCTAssertTrue(viewModel.selectedPapers.isEmpty)
    }

    // MARK: - Current Papers Tests

    func testCurrentPapers_emptyWhenNoEnrichment() {
        let viewModel = createViewModelWithMockStack()

        // No enrichment data means no papers
        XCTAssertTrue(viewModel.currentPapers.isEmpty)
    }

    func testSelectedPaperStubs_emptyWhenNothingSelected() {
        let viewModel = createViewModelWithMockStack()

        XCTAssertTrue(viewModel.selectedPaperStubs.isEmpty)
    }

    // MARK: - Tab Selection Tests

    func testSelectedTab_defaultsToReferences() {
        let viewModel = createViewModelWithMockStack()

        XCTAssertEqual(viewModel.selectedTab, .references)
    }

    func testSelectedTab_canBeChanged() {
        let viewModel = createViewModelWithMockStack()

        viewModel.selectedTab = .citations

        XCTAssertEqual(viewModel.selectedTab, .citations)
    }

    // MARK: - Navigation State Tests

    func testCanGoBack_falseWhenStackEmpty() {
        let viewModel = createViewModelWithMockStack()

        XCTAssertFalse(viewModel.canGoBack)
    }

    func testCanGoBack_falseWithOneItem() {
        let viewModel = createViewModelWithMockStack(itemCount: 1)

        XCTAssertFalse(viewModel.canGoBack)
    }

    func testCanGoBack_trueWithMultipleItems() {
        let viewModel = createViewModelWithMockStack(itemCount: 2)

        XCTAssertTrue(viewModel.canGoBack)
    }

    func testCurrentPaper_nilWhenEmpty() {
        let viewModel = createViewModelWithMockStack()

        XCTAssertNil(viewModel.currentPaper)
    }

    func testCurrentPaper_returnsTopOfStack() {
        let viewModel = createViewModelWithMockStack(itemCount: 3)

        // Stack should have paper-0, paper-1, paper-2
        XCTAssertEqual(viewModel.currentPaper?.id, "paper-2")
    }

    // MARK: - Pop Navigation Tests

    func testPopPaper_removesTopItem() {
        let viewModel = createViewModelWithMockStack(itemCount: 3)

        viewModel.popPaper()

        XCTAssertEqual(viewModel.navigationStack.count, 2)
        XCTAssertEqual(viewModel.currentPaper?.id, "paper-1")
    }

    func testPopPaper_clearsSelection() {
        let viewModel = createViewModelWithMockStack(itemCount: 2)
        viewModel.selectedPapers = ["some-paper"]

        viewModel.popPaper()

        XCTAssertTrue(viewModel.selectedPapers.isEmpty)
    }

    func testPopPaper_doesNothingAtRoot() {
        let viewModel = createViewModelWithMockStack(itemCount: 1)

        viewModel.popPaper()

        XCTAssertEqual(viewModel.navigationStack.count, 1)
    }

    func testPopPaper_doesNothingWhenEmpty() {
        let viewModel = createViewModelWithMockStack()

        viewModel.popPaper()

        XCTAssertTrue(viewModel.navigationStack.isEmpty)
    }

    // MARK: - Breadcrumb Navigation Tests

    func testNavigateToBreadcrumb_popsToLevel() {
        let viewModel = createViewModelWithMockStack(itemCount: 4)

        // Navigate to index 1 (second item)
        viewModel.navigateToBreadcrumb(at: 1)

        XCTAssertEqual(viewModel.navigationStack.count, 2)
        XCTAssertEqual(viewModel.currentPaper?.id, "paper-1")
    }

    func testNavigateToBreadcrumb_clearsSelection() {
        let viewModel = createViewModelWithMockStack(itemCount: 3)
        viewModel.selectedPapers = ["some-paper"]

        viewModel.navigateToBreadcrumb(at: 0)

        XCTAssertTrue(viewModel.selectedPapers.isEmpty)
    }

    func testNavigateToBreadcrumb_invalidIndexIsNoOp() {
        let viewModel = createViewModelWithMockStack(itemCount: 2)

        viewModel.navigateToBreadcrumb(at: 10)

        XCTAssertEqual(viewModel.navigationStack.count, 2)
    }

    func testNavigateToBreadcrumb_negativeIndexIsNoOp() {
        let viewModel = createViewModelWithMockStack(itemCount: 2)

        viewModel.navigateToBreadcrumb(at: -1)

        XCTAssertEqual(viewModel.navigationStack.count, 2)
    }

    // MARK: - Reset Navigation Tests

    func testResetNavigation_keepOnlyRoot() {
        let viewModel = createViewModelWithMockStack(itemCount: 5)

        viewModel.resetNavigation()

        XCTAssertEqual(viewModel.navigationStack.count, 1)
        XCTAssertEqual(viewModel.currentPaper?.id, "paper-0")
    }

    func testResetNavigation_clearsSelection() {
        let viewModel = createViewModelWithMockStack(itemCount: 3)
        viewModel.selectedPapers = ["p1", "p2"]

        viewModel.resetNavigation()

        XCTAssertTrue(viewModel.selectedPapers.isEmpty)
    }

    func testResetNavigation_noOpIfOnlyOneItem() {
        let viewModel = createViewModelWithMockStack(itemCount: 1)

        viewModel.resetNavigation()

        XCTAssertEqual(viewModel.navigationStack.count, 1)
    }

    // MARK: - Breadcrumbs Tests

    func testBreadcrumbs_formatsWithAuthorAndYear() {
        let viewModel = createViewModelWithMockStack()

        // Manually add an item with known author and year
        let item = CitationExplorerViewModel.NavigationItem(
            id: "test",
            title: "Long Paper Title",
            authors: ["Einstein", "Bohr"],
            year: 1935
        )
        viewModel.setNavigationStack([item])

        let breadcrumb = viewModel.breadcrumbs.first
        XCTAssertEqual(breadcrumb, "Einstein (1935)")
    }

    func testBreadcrumbs_truncatesLongTitleWhenNoYear() {
        let viewModel = createViewModelWithMockStack()

        let item = CitationExplorerViewModel.NavigationItem(
            id: "test",
            title: "This is a very long paper title that should be truncated",
            authors: []
        )
        viewModel.setNavigationStack([item])

        let breadcrumb = viewModel.breadcrumbs.first ?? ""
        XCTAssertTrue(breadcrumb.hasSuffix("..."))
        XCTAssertLessThanOrEqual(breadcrumb.count, 24) // 20 chars + "..."
    }

    func testBreadcrumbs_countMatchesStackSize() {
        let viewModel = createViewModelWithMockStack(itemCount: 3)

        XCTAssertEqual(viewModel.breadcrumbs.count, 3)
    }

    // MARK: - Loading State Tests

    func testIsLoading_reflectsCurrentPaperState() {
        let viewModel = createViewModelWithMockStack()

        var item = CitationExplorerViewModel.NavigationItem(
            id: "test",
            title: "Paper",
            authors: []
        )
        item.isLoading = false
        viewModel.setNavigationStack([item])

        XCTAssertFalse(viewModel.isLoading)

        // Update to loading
        item.isLoading = true
        viewModel.setNavigationStack([item])

        XCTAssertTrue(viewModel.isLoading)
    }

    func testIsLoading_falseWhenStackEmpty() {
        let viewModel = createViewModelWithMockStack()

        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - ReferenceTab Tests

    func testReferenceTab_allCases() {
        XCTAssertEqual(ReferenceTab.allCases.count, 2)
        XCTAssertTrue(ReferenceTab.allCases.contains(.references))
        XCTAssertTrue(ReferenceTab.allCases.contains(.citations))
    }

    func testReferenceTab_displayNames() {
        XCTAssertEqual(ReferenceTab.references.displayName, "References")
        XCTAssertEqual(ReferenceTab.citations.displayName, "Citations")
    }

    func testReferenceTab_identifiable() {
        XCTAssertEqual(ReferenceTab.references.id, "references")
        XCTAssertEqual(ReferenceTab.citations.id, "citations")
    }

    // MARK: - Helpers

    /// Create a view model with a mock navigation stack for testing
    private func createViewModelWithMockStack(itemCount: Int = 0) -> CitationExplorerViewModel {
        // Create with a minimal EnrichmentService (tests won't actually call it)
        let service = EnrichmentService(plugins: [])
        let viewModel = CitationExplorerViewModel(enrichmentService: service)

        // Manually populate navigation stack for testing
        var items: [CitationExplorerViewModel.NavigationItem] = []
        for i in 0..<itemCount {
            let item = CitationExplorerViewModel.NavigationItem(
                id: "paper-\(i)",
                title: "Paper \(i)",
                authors: ["Author \(i)"],
                year: 2020 + i
            )
            items.append(item)
        }
        viewModel.setNavigationStack(items)

        return viewModel
    }
}
