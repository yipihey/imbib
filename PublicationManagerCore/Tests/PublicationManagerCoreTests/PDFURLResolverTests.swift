//
//  PDFURLResolverTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-04.
//

import XCTest
@testable import PublicationManagerCore

final class PDFURLResolverTests: XCTestCase {

    // MARK: - Properties

    private var persistenceController: PersistenceController!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        persistenceController = .preview
    }

    override func tearDown() {
        persistenceController = nil
        super.tearDown()
    }

    // MARK: - Test Helpers

    @MainActor
    private func makePublication(
        arxivID: String? = nil,
        remotePDFURL: URL? = nil
    ) -> CDPublication {
        let publication = CDPublication(context: persistenceController.viewContext)
        publication.id = UUID()
        publication.citeKey = "Test2024"
        publication.entryType = "article"
        publication.title = "Test Paper"
        publication.year = 2024
        publication.dateAdded = Date()
        publication.dateModified = Date()

        // Set arXiv ID via fields
        var fields: [String: String] = [:]
        if let arxivID = arxivID {
            fields["eprint"] = arxivID
            fields["archiveprefix"] = "arXiv"
        }
        publication.fields = fields

        // Set PDF links
        if let remotePDFURL = remotePDFURL {
            publication.pdfLinks = [PDFLink(url: remotePDFURL, type: .publisher)]
        }

        return publication
    }

    // MARK: - Preprint Priority Tests

    @MainActor
    func testPreprintPriority_withArXiv_returnsArXivURL() {
        // Given
        let publication = makePublication(
            arxivID: "2301.12345",
            remotePDFURL: URL(string: "https://publisher.com/paper.pdf")
        )
        let settings = PDFSettings(sourcePriority: .preprint, libraryProxyURL: "", proxyEnabled: false)

        // When
        let result = PDFURLResolver.resolve(for: publication, settings: settings)

        // Then - should prefer arXiv
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/2301.12345.pdf")
    }

    @MainActor
    func testPreprintPriority_noArXiv_fallsBackToPublisher() {
        // Given
        let publisherURL = URL(string: "https://publisher.com/paper.pdf")!
        let publication = makePublication(
            arxivID: nil,
            remotePDFURL: publisherURL
        )
        let settings = PDFSettings(sourcePriority: .preprint, libraryProxyURL: "", proxyEnabled: false)

        // When
        let result = PDFURLResolver.resolve(for: publication, settings: settings)

        // Then - should fall back to publisher
        XCTAssertEqual(result, publisherURL)
    }

    // MARK: - Publisher Priority Tests

    @MainActor
    func testPublisherPriority_withRemotePDF_returnsPublisherURL() {
        // Given
        let publisherURL = URL(string: "https://publisher.com/paper.pdf")!
        let publication = makePublication(
            arxivID: "2301.12345",
            remotePDFURL: publisherURL
        )
        let settings = PDFSettings(sourcePriority: .publisher, libraryProxyURL: "", proxyEnabled: false)

        // When
        let result = PDFURLResolver.resolve(for: publication, settings: settings)

        // Then - should prefer publisher
        XCTAssertEqual(result, publisherURL)
    }

    @MainActor
    func testPublisherPriority_noRemotePDF_fallsBackToArXiv() {
        // Given
        let publication = makePublication(
            arxivID: "2301.12345",
            remotePDFURL: nil
        )
        let settings = PDFSettings(sourcePriority: .publisher, libraryProxyURL: "", proxyEnabled: false)

        // When
        let result = PDFURLResolver.resolve(for: publication, settings: settings)

        // Then - should fall back to arXiv
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/2301.12345.pdf")
    }

    // MARK: - Proxy Tests

    @MainActor
    func testProxyEnabled_appliesProxyToPublisherURL() {
        // Given
        let publisherURL = URL(string: "https://publisher.com/paper.pdf")!
        let publication = makePublication(remotePDFURL: publisherURL)
        let proxyURL = "https://stanford.idm.oclc.org/login?url="
        let settings = PDFSettings(
            sourcePriority: .publisher,
            libraryProxyURL: proxyURL,
            proxyEnabled: true
        )

        // When
        let result = PDFURLResolver.resolve(for: publication, settings: settings)

        // Then
        XCTAssertEqual(
            result?.absoluteString,
            "https://stanford.idm.oclc.org/login?url=https://publisher.com/paper.pdf"
        )
    }

    @MainActor
    func testProxyDisabled_doesNotApplyProxy() {
        // Given
        let publisherURL = URL(string: "https://publisher.com/paper.pdf")!
        let publication = makePublication(remotePDFURL: publisherURL)
        let settings = PDFSettings(
            sourcePriority: .publisher,
            libraryProxyURL: "https://proxy.edu/",
            proxyEnabled: false  // Disabled
        )

        // When
        let result = PDFURLResolver.resolve(for: publication, settings: settings)

        // Then - should return original URL without proxy
        XCTAssertEqual(result, publisherURL)
    }

    @MainActor
    func testProxyEnabled_emptyProxyURL_doesNotApplyProxy() {
        // Given
        let publisherURL = URL(string: "https://publisher.com/paper.pdf")!
        let publication = makePublication(remotePDFURL: publisherURL)
        let settings = PDFSettings(
            sourcePriority: .publisher,
            libraryProxyURL: "",  // Empty
            proxyEnabled: true
        )

        // When
        let result = PDFURLResolver.resolve(for: publication, settings: settings)

        // Then - should return original URL
        XCTAssertEqual(result, publisherURL)
    }

    @MainActor
    func testProxyNotAppliedToArXiv() {
        // Given - arXiv is free, proxy should only apply to publisher
        let publication = makePublication(arxivID: "2301.12345")
        let settings = PDFSettings(
            sourcePriority: .preprint,
            libraryProxyURL: "https://proxy.edu/login?url=",
            proxyEnabled: true
        )

        // When
        let result = PDFURLResolver.resolve(for: publication, settings: settings)

        // Then - arXiv URL should NOT have proxy
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/2301.12345.pdf")
    }

    // MARK: - arXiv ID Format Tests (using direct arXivPDFURL method)

    func testArXivPDFURL_newFormat() {
        // When
        let result = PDFURLResolver.arXivPDFURL(arxivID: "2301.12345")

        // Then
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/2301.12345.pdf")
    }

    func testArXivPDFURL_newFormatWithVersion() {
        // When - version suffix is preserved (arXiv handles redirects)
        let result = PDFURLResolver.arXivPDFURL(arxivID: "2301.12345v2")

        // Then
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/2301.12345v2.pdf")
    }

    func testArXivPDFURL_oldFormat() {
        // When - old format: category/YYMMNNN
        let result = PDFURLResolver.arXivPDFURL(arxivID: "hep-th/9901001")

        // Then
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/hep-th/9901001.pdf")
    }

    func testArXivPDFURL_emptyArXivID_returnsNil() {
        // When
        let result = PDFURLResolver.arXivPDFURL(arxivID: "")

        // Then
        XCTAssertNil(result)
    }

    // MARK: - No PDF Available Tests

    @MainActor
    func testNoPDFAvailable_returnsNil() {
        // Given - no arXiv ID and no remote PDF
        let publication = makePublication(arxivID: nil, remotePDFURL: nil)
        let settings = PDFSettings.default

        // When
        let result = PDFURLResolver.resolve(for: publication, settings: settings)

        // Then
        XCTAssertNil(result)
    }

    // MARK: - hasPDF Tests

    @MainActor
    func testHasPDF_withArXiv_returnsTrue() {
        let publication = makePublication(arxivID: "2301.12345")
        XCTAssertTrue(PDFURLResolver.hasPDF(publication: publication))
    }

    @MainActor
    func testHasPDF_withRemotePDF_returnsTrue() {
        let publication = makePublication(remotePDFURL: URL(string: "https://test.com/paper.pdf"))
        XCTAssertTrue(PDFURLResolver.hasPDF(publication: publication))
    }

    @MainActor
    func testHasPDF_withBoth_returnsTrue() {
        let publication = makePublication(
            arxivID: "2301.12345",
            remotePDFURL: URL(string: "https://test.com/paper.pdf")
        )
        XCTAssertTrue(PDFURLResolver.hasPDF(publication: publication))
    }

    @MainActor
    func testHasPDF_withNeither_returnsFalse() {
        let publication = makePublication(arxivID: nil, remotePDFURL: nil)
        XCTAssertFalse(PDFURLResolver.hasPDF(publication: publication))
    }

    // MARK: - ADS Gateway Tests

    func testADSGatewayPDFURL_validBibcode() {
        // Given
        let bibcode = "2024ApJ...123..456A"

        // When
        let result = PDFURLResolver.adsGatewayPDFURL(bibcode: bibcode)

        // Then
        XCTAssertEqual(
            result?.absoluteString,
            "https://ui.adsabs.harvard.edu/link_gateway/2024ApJ...123..456A/PUB_PDF"
        )
    }

    func testADSGatewayPDFURL_emptyBibcode_returnsNil() {
        let result = PDFURLResolver.adsGatewayPDFURL(bibcode: "")
        XCTAssertNil(result)
    }

    // MARK: - Available Sources Tests

    @MainActor
    func testAvailableSources_withBothSources() {
        // Given
        let publication = makePublication(
            arxivID: "2301.12345",
            remotePDFURL: URL(string: "https://publisher.com/paper.pdf")
        )

        // When
        let sources = PDFURLResolver.availableSources(for: publication)

        // Then
        XCTAssertEqual(sources.count, 2)
        XCTAssertTrue(sources.contains { $0.type == .preprint && $0.name == "arXiv" })
        XCTAssertTrue(sources.contains { $0.type == .publisher && $0.name == "Publisher" })
    }

    @MainActor
    func testAvailableSources_onlyArXiv() {
        // Given
        let publication = makePublication(arxivID: "2301.12345")

        // When
        let sources = PDFURLResolver.availableSources(for: publication)

        // Then
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.type, .preprint)
        XCTAssertEqual(sources.first?.name, "arXiv")
        XCTAssertFalse(sources.first?.requiresProxy ?? true)
    }

    @MainActor
    func testAvailableSources_onlyPublisher() {
        // Given
        let publication = makePublication(remotePDFURL: URL(string: "https://publisher.com/paper.pdf"))

        // When
        let sources = PDFURLResolver.availableSources(for: publication)

        // Then
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.type, .publisher)
        XCTAssertEqual(sources.first?.name, "Publisher")
        XCTAssertTrue(sources.first?.requiresProxy ?? false)
    }

    @MainActor
    func testAvailableSources_noSources() {
        // Given
        let publication = makePublication()

        // When
        let sources = PDFURLResolver.availableSources(for: publication)

        // Then
        XCTAssertTrue(sources.isEmpty)
    }

    // MARK: - Apply Proxy Tests

    func testApplyProxy_addsPrefix() {
        // Given
        let url = URL(string: "https://doi.org/10.1234/test")!
        let settings = PDFSettings(
            sourcePriority: .publisher,
            libraryProxyURL: "https://proxy.edu/login?url=",
            proxyEnabled: true
        )

        // When
        let result = PDFURLResolver.applyProxy(to: url, settings: settings)

        // Then
        XCTAssertEqual(
            result.absoluteString,
            "https://proxy.edu/login?url=https://doi.org/10.1234/test"
        )
    }

    // MARK: - Auto-Download Tests (resolveForAutoDownload)

    @MainActor
    func testResolveForAutoDownload_arxivIDFromEprint_returnsArxivURL() {
        // Given - arXiv ID set via eprint field
        let publication = makePublication(arxivID: "2301.12345")
        let settings = PDFSettings.default

        // When
        let result = PDFURLResolver.resolveForAutoDownload(for: publication, settings: settings)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/2301.12345.pdf")
    }

    @MainActor
    func testResolveForAutoDownload_arxivIDFromArxividField_returnsArxivURL() {
        // Given - arXiv ID set via arxivid field (alternative field name)
        let publication = CDPublication(context: persistenceController.viewContext)
        publication.id = UUID()
        publication.citeKey = "Test2024"
        publication.entryType = "article"
        publication.title = "Test Paper"
        publication.year = 2024
        publication.dateAdded = Date()
        publication.dateModified = Date()
        publication.fields = ["arxivid": "2301.98765"]

        let settings = PDFSettings.default

        // When
        let result = PDFURLResolver.resolveForAutoDownload(for: publication, settings: settings)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/2301.98765.pdf")
    }

    @MainActor
    func testResolveForAutoDownload_arxivIDWithVersion_constructsCorrectURL() {
        // Given - arXiv ID includes version suffix
        let publication = makePublication(arxivID: "2301.12345v3")
        let settings = PDFSettings.default

        // When
        let result = PDFURLResolver.resolveForAutoDownload(for: publication, settings: settings)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/2301.12345v3.pdf")
    }

    @MainActor
    func testResolveForAutoDownload_oldStyleArxivID_constructsCorrectURL() {
        // Given - old-style arXiv ID (category/YYMMNNN)
        let publication = makePublication(arxivID: "hep-ph/0601001")
        let settings = PDFSettings.default

        // When
        let result = PDFURLResolver.resolveForAutoDownload(for: publication, settings: settings)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/hep-ph/0601001.pdf")
    }

    @MainActor
    func testResolveForAutoDownload_publisherPriority_prefersOpenAlexOverArxiv() {
        // Given - both OpenAlex and arXiv available, publisher priority setting
        let publication = CDPublication(context: persistenceController.viewContext)
        publication.id = UUID()
        publication.citeKey = "Test2024"
        publication.entryType = "article"
        publication.title = "Test Paper"
        publication.year = 2024
        publication.dateAdded = Date()
        publication.dateModified = Date()
        publication.fields = ["eprint": "2301.12345", "archiveprefix": "arXiv"]

        // Add OpenAlex PDF link
        publication.pdfLinks = [
            PDFLink(url: URL(string: "https://openalex.org/paper.pdf")!, type: .publisher, sourceID: "openalex")
        ]

        // Use publisher priority - should prefer OpenAlex over arXiv
        let settings = PDFSettings(sourcePriority: .publisher, libraryProxyURL: "", proxyEnabled: false)

        // When
        let result = PDFURLResolver.resolveForAutoDownload(for: publication, settings: settings)

        // Then - should prefer OpenAlex (publisher) over arXiv (preprint)
        XCTAssertEqual(result?.absoluteString, "https://openalex.org/paper.pdf")
    }

    @MainActor
    func testResolveForAutoDownload_preprintPriority_prefersArxivOverOpenAlex() {
        // Given - both OpenAlex and arXiv available, preprint priority setting
        let publication = CDPublication(context: persistenceController.viewContext)
        publication.id = UUID()
        publication.citeKey = "Test2024"
        publication.entryType = "article"
        publication.title = "Test Paper"
        publication.year = 2024
        publication.dateAdded = Date()
        publication.dateModified = Date()
        publication.fields = ["eprint": "2301.12345", "archiveprefix": "arXiv"]

        // Add OpenAlex PDF link
        publication.pdfLinks = [
            PDFLink(url: URL(string: "https://openalex.org/paper.pdf")!, type: .publisher, sourceID: "openalex")
        ]

        // Use preprint priority (default) - should prefer arXiv over OpenAlex
        let settings = PDFSettings(sourcePriority: .preprint, libraryProxyURL: "", proxyEnabled: false)

        // When
        let result = PDFURLResolver.resolveForAutoDownload(for: publication, settings: settings)

        // Then - should prefer arXiv (preprint) over OpenAlex (publisher)
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/2301.12345.pdf")
    }

    @MainActor
    func testResolveForAutoDownload_emptyArxivID_returnsNil() {
        // Given - empty string in eprint field
        let publication = CDPublication(context: persistenceController.viewContext)
        publication.id = UUID()
        publication.citeKey = "Test2024"
        publication.entryType = "article"
        publication.title = "Test Paper"
        publication.year = 2024
        publication.dateAdded = Date()
        publication.dateModified = Date()
        publication.fields = ["eprint": ""]  // Empty

        let settings = PDFSettings.default

        // When
        let result = PDFURLResolver.resolveForAutoDownload(for: publication, settings: settings)

        // Then
        XCTAssertNil(result)
    }

    @MainActor
    func testResolveForAutoDownload_whitespaceOnlyArxivID_returnsNil() {
        // Given - whitespace-only string in eprint field
        let publication = CDPublication(context: persistenceController.viewContext)
        publication.id = UUID()
        publication.citeKey = "Test2024"
        publication.entryType = "article"
        publication.title = "Test Paper"
        publication.year = 2024
        publication.dateAdded = Date()
        publication.dateModified = Date()
        publication.fields = ["eprint": "   "]  // Whitespace only

        let settings = PDFSettings.default

        // When
        let result = PDFURLResolver.resolveForAutoDownload(for: publication, settings: settings)

        // Then - should handle gracefully (may return URL but should trim)
        // The arXivPDFURL function trims whitespace, so empty result
        XCTAssertNil(result)
    }

    @MainActor
    func testResolveForAutoDownload_noIdentifiers_returnsNil() {
        // Given - no arXiv ID, no PDF links
        let publication = CDPublication(context: persistenceController.viewContext)
        publication.id = UUID()
        publication.citeKey = "Test2024"
        publication.entryType = "article"
        publication.title = "Test Paper"
        publication.year = 2024
        publication.dateAdded = Date()
        publication.dateModified = Date()
        publication.fields = [:]  // No identifiers

        let settings = PDFSettings.default

        // When
        let result = PDFURLResolver.resolveForAutoDownload(for: publication, settings: settings)

        // Then
        XCTAssertNil(result)
    }

    @MainActor
    func testResolveForAutoDownload_proxyNotAppliedToArxiv() {
        // Given - arXiv paper with proxy enabled
        let publication = makePublication(arxivID: "2301.12345")
        let settings = PDFSettings(
            sourcePriority: .preprint,
            libraryProxyURL: "https://proxy.edu/login?url=",
            proxyEnabled: true
        )

        // When
        let result = PDFURLResolver.resolveForAutoDownload(for: publication, settings: settings)

        // Then - arXiv URL should NOT have proxy (arXiv is free)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/2301.12345.pdf")
        XCTAssertFalse(result?.absoluteString.contains("proxy") ?? true)
    }

    @MainActor
    func testResolveForAutoDownload_publisherLinkGetsProxy() {
        // Given - publisher PDF with proxy enabled
        let publication = CDPublication(context: persistenceController.viewContext)
        publication.id = UUID()
        publication.citeKey = "Test2024"
        publication.entryType = "article"
        publication.title = "Test Paper"
        publication.year = 2024
        publication.dateAdded = Date()
        publication.dateModified = Date()
        publication.fields = [:]  // No arXiv

        // Add publisher PDF link (not OpenAlex, not arXiv)
        publication.pdfLinks = [
            PDFLink(url: URL(string: "https://publisher.com/paper.pdf")!, type: .publisher, sourceID: "crossref")
        ]

        let settings = PDFSettings(
            sourcePriority: .publisher,
            libraryProxyURL: "https://proxy.edu/login?url=",
            proxyEnabled: true
        )

        // When
        let result = PDFURLResolver.resolveForAutoDownload(for: publication, settings: settings)

        // Then - should have proxy prefix
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.absoluteString.contains("proxy.edu") ?? false)
    }

    @MainActor
    func testResolveForAutoDownload_adsScanNotProxied() {
        // Given - ADS scan PDF (always free)
        let publication = CDPublication(context: persistenceController.viewContext)
        publication.id = UUID()
        publication.citeKey = "Test1990"
        publication.entryType = "article"
        publication.title = "Old Paper"
        publication.year = 1990
        publication.dateAdded = Date()
        publication.dateModified = Date()
        publication.fields = [:]

        // Add ADS scan link (older papers scanned by ADS)
        publication.pdfLinks = [
            PDFLink(url: URL(string: "https://articles.adsabs.harvard.edu/pdf/1990ApJ...355...52B")!, type: .adsScan, sourceID: "ads")
        ]

        let settings = PDFSettings(
            sourcePriority: .publisher,
            libraryProxyURL: "https://proxy.edu/login?url=",
            proxyEnabled: true
        )

        // When
        let result = PDFURLResolver.resolveForAutoDownload(for: publication, settings: settings)

        // Then - ADS scans are free, no proxy
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.absoluteString, "https://articles.adsabs.harvard.edu/pdf/1990ApJ...355...52B")
        XCTAssertFalse(result?.absoluteString.contains("proxy") ?? true)
    }

    @MainActor
    func testResolveForAutoDownload_gatewayURLsDeprioritized() {
        // Given - both ADS link_gateway (unreliable) and arXiv available
        let publication = CDPublication(context: persistenceController.viewContext)
        publication.id = UUID()
        publication.citeKey = "Test2024"
        publication.entryType = "article"
        publication.title = "Test Paper"
        publication.year = 2024
        publication.dateAdded = Date()
        publication.dateModified = Date()
        publication.fields = ["eprint": "2301.12345"]

        // Add ADS link_gateway URL (unreliable) - should be deprioritized
        publication.pdfLinks = [
            PDFLink(url: URL(string: "https://ui.adsabs.harvard.edu/link_gateway/2024ApJ...123..456A/PUB_PDF")!, type: .publisher, sourceID: "ads")
        ]

        let settings = PDFSettings(sourcePriority: .publisher, libraryProxyURL: "", proxyEnabled: false)

        // When
        let result = PDFURLResolver.resolveForAutoDownload(for: publication, settings: settings)

        // Then - should use arXiv (fallback) instead of unreliable gateway
        // Gateway is only used as last resort
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.absoluteString.contains("arxiv.org/pdf") ?? false,
                      "Should prefer arXiv over unreliable ADS gateway URL")
    }

    @MainActor
    func testResolveForAutoDownload_gatewayUsedAsLastResort() {
        // Given - only ADS link_gateway available (no arXiv, no DOI)
        let publication = CDPublication(context: persistenceController.viewContext)
        publication.id = UUID()
        publication.citeKey = "Test2024"
        publication.entryType = "article"
        publication.title = "Test Paper"
        publication.year = 2024
        publication.dateAdded = Date()
        publication.dateModified = Date()
        publication.fields = [:]  // No arXiv

        // Only gateway URL available
        publication.pdfLinks = [
            PDFLink(url: URL(string: "https://ui.adsabs.harvard.edu/link_gateway/2024ApJ...123..456A/PUB_PDF")!, type: .publisher, sourceID: "ads")
        ]

        let settings = PDFSettings(sourcePriority: .publisher, libraryProxyURL: "", proxyEnabled: false)

        // When
        let result = PDFURLResolver.resolveForAutoDownload(for: publication, settings: settings)

        // Then - should use gateway as last resort (better than nothing)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.absoluteString.contains("link_gateway") ?? false,
                      "Should use gateway URL when no better option available")
    }

    @MainActor
    func testResolveForAutoDownload_directPDFPreferredOverGateway() {
        // Given - direct PDF URL and gateway URL available
        let publication = CDPublication(context: persistenceController.viewContext)
        publication.id = UUID()
        publication.citeKey = "Test2024"
        publication.entryType = "article"
        publication.title = "Test Paper"
        publication.year = 2024
        publication.dateAdded = Date()
        publication.dateModified = Date()
        publication.fields = [:]

        // Both direct PDF and gateway available
        publication.pdfLinks = [
            PDFLink(url: URL(string: "https://ui.adsabs.harvard.edu/link_gateway/2024ApJ...123..456A/PUB_PDF")!, type: .publisher, sourceID: "ads"),
            PDFLink(url: URL(string: "https://academic.oup.com/article-pdf/123/456.pdf")!, type: .publisher, sourceID: "crossref")
        ]

        let settings = PDFSettings(sourcePriority: .publisher, libraryProxyURL: "", proxyEnabled: false)

        // When
        let result = PDFURLResolver.resolveForAutoDownload(for: publication, settings: settings)

        // Then - should prefer direct PDF over gateway
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.absoluteString.contains("article-pdf") ?? false,
                      "Should prefer direct PDF URL over gateway URL")
    }
}
