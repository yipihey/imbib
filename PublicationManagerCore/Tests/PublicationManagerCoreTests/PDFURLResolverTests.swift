//
//  PDFURLResolverTests.swift
//  PublicationManagerCoreTests
//
//  Created by Claude on 2026-01-04.
//

import XCTest
@testable import PublicationManagerCore

final class PDFURLResolverTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeOnlinePaper(
        id: String = "test-123",
        arxivID: String? = nil,
        remotePDFURL: URL? = nil
    ) -> OnlinePaper {
        OnlinePaper(result: SearchResult(
            id: id,
            sourceID: "test",
            title: "Test Paper",
            authors: ["Test Author"],
            year: 2024,
            venue: "Test Venue",
            abstract: "Test abstract",
            doi: "10.1234/test",
            arxivID: arxivID,
            pdfURL: remotePDFURL,
            webURL: nil
        ))
    }

    // MARK: - Preprint Priority Tests

    func testPreprintPriority_withArXiv_returnsArXivURL() {
        // Given
        let paper = makeOnlinePaper(
            arxivID: "2301.12345",
            remotePDFURL: URL(string: "https://publisher.com/paper.pdf")
        )
        let settings = PDFSettings(sourcePriority: .preprint, libraryProxyURL: "", proxyEnabled: false)

        // When
        let result = PDFURLResolver.resolve(for: paper, settings: settings)

        // Then - should prefer arXiv
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/2301.12345.pdf")
    }

    func testPreprintPriority_noArXiv_fallsBackToPublisher() {
        // Given
        let publisherURL = URL(string: "https://publisher.com/paper.pdf")!
        let paper = makeOnlinePaper(
            arxivID: nil,
            remotePDFURL: publisherURL
        )
        let settings = PDFSettings(sourcePriority: .preprint, libraryProxyURL: "", proxyEnabled: false)

        // When
        let result = PDFURLResolver.resolve(for: paper, settings: settings)

        // Then - should fall back to publisher
        XCTAssertEqual(result, publisherURL)
    }

    // MARK: - Publisher Priority Tests

    func testPublisherPriority_withRemotePDF_returnsPublisherURL() {
        // Given
        let publisherURL = URL(string: "https://publisher.com/paper.pdf")!
        let paper = makeOnlinePaper(
            arxivID: "2301.12345",
            remotePDFURL: publisherURL
        )
        let settings = PDFSettings(sourcePriority: .publisher, libraryProxyURL: "", proxyEnabled: false)

        // When
        let result = PDFURLResolver.resolve(for: paper, settings: settings)

        // Then - should prefer publisher
        XCTAssertEqual(result, publisherURL)
    }

    func testPublisherPriority_noRemotePDF_fallsBackToArXiv() {
        // Given
        let paper = makeOnlinePaper(
            arxivID: "2301.12345",
            remotePDFURL: nil
        )
        let settings = PDFSettings(sourcePriority: .publisher, libraryProxyURL: "", proxyEnabled: false)

        // When
        let result = PDFURLResolver.resolve(for: paper, settings: settings)

        // Then - should fall back to arXiv
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/2301.12345.pdf")
    }

    // MARK: - Proxy Tests

    func testProxyEnabled_appliesProxyToPublisherURL() {
        // Given
        let publisherURL = URL(string: "https://publisher.com/paper.pdf")!
        let paper = makeOnlinePaper(remotePDFURL: publisherURL)
        let proxyURL = "https://stanford.idm.oclc.org/login?url="
        let settings = PDFSettings(
            sourcePriority: .publisher,
            libraryProxyURL: proxyURL,
            proxyEnabled: true
        )

        // When
        let result = PDFURLResolver.resolve(for: paper, settings: settings)

        // Then
        XCTAssertEqual(
            result?.absoluteString,
            "https://stanford.idm.oclc.org/login?url=https://publisher.com/paper.pdf"
        )
    }

    func testProxyDisabled_doesNotApplyProxy() {
        // Given
        let publisherURL = URL(string: "https://publisher.com/paper.pdf")!
        let paper = makeOnlinePaper(remotePDFURL: publisherURL)
        let settings = PDFSettings(
            sourcePriority: .publisher,
            libraryProxyURL: "https://proxy.edu/",
            proxyEnabled: false  // Disabled
        )

        // When
        let result = PDFURLResolver.resolve(for: paper, settings: settings)

        // Then - should return original URL without proxy
        XCTAssertEqual(result, publisherURL)
    }

    func testProxyEnabled_emptyProxyURL_doesNotApplyProxy() {
        // Given
        let publisherURL = URL(string: "https://publisher.com/paper.pdf")!
        let paper = makeOnlinePaper(remotePDFURL: publisherURL)
        let settings = PDFSettings(
            sourcePriority: .publisher,
            libraryProxyURL: "",  // Empty
            proxyEnabled: true
        )

        // When
        let result = PDFURLResolver.resolve(for: paper, settings: settings)

        // Then - should return original URL
        XCTAssertEqual(result, publisherURL)
    }

    func testProxyNotAppliedToArXiv() {
        // Given - arXiv is free, proxy should only apply to publisher
        let paper = makeOnlinePaper(arxivID: "2301.12345")
        let settings = PDFSettings(
            sourcePriority: .preprint,
            libraryProxyURL: "https://proxy.edu/login?url=",
            proxyEnabled: true
        )

        // When
        let result = PDFURLResolver.resolve(for: paper, settings: settings)

        // Then - arXiv URL should NOT have proxy
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/2301.12345.pdf")
    }

    // MARK: - arXiv ID Format Tests

    func testArXivPDFURL_newFormat() {
        // Given
        let paper = makeOnlinePaper(arxivID: "2301.12345")

        // When
        let result = PDFURLResolver.arXivPDFURL(for: paper)

        // Then
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/2301.12345.pdf")
    }

    func testArXivPDFURL_newFormatWithVersion() {
        // Given - version suffix is preserved (arXiv handles redirects)
        let paper = makeOnlinePaper(arxivID: "2301.12345v2")

        // When
        let result = PDFURLResolver.arXivPDFURL(for: paper)

        // Then
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/2301.12345v2.pdf")
    }

    func testArXivPDFURL_oldFormat() {
        // Given - old format: category/YYMMNNN
        let paper = makeOnlinePaper(arxivID: "hep-th/9901001")

        // When
        let result = PDFURLResolver.arXivPDFURL(for: paper)

        // Then
        XCTAssertEqual(result?.absoluteString, "https://arxiv.org/pdf/hep-th/9901001.pdf")
    }

    func testArXivPDFURL_noArXivID_returnsNil() {
        // Given
        let paper = makeOnlinePaper(arxivID: nil)

        // When
        let result = PDFURLResolver.arXivPDFURL(for: paper)

        // Then
        XCTAssertNil(result)
    }

    func testArXivPDFURL_emptyArXivID_returnsNil() {
        // Given
        let paper = makeOnlinePaper(arxivID: "")

        // When
        let result = PDFURLResolver.arXivPDFURL(for: paper)

        // Then
        XCTAssertNil(result)
    }

    // MARK: - No PDF Available Tests

    func testNoPDFAvailable_returnsNil() {
        // Given - no arXiv ID and no remote PDF
        let paper = makeOnlinePaper(arxivID: nil, remotePDFURL: nil)
        let settings = PDFSettings.default

        // When
        let result = PDFURLResolver.resolve(for: paper, settings: settings)

        // Then
        XCTAssertNil(result)
    }

    // MARK: - hasPDF Tests

    func testHasPDF_withArXiv_returnsTrue() {
        let paper = makeOnlinePaper(arxivID: "2301.12345")
        XCTAssertTrue(PDFURLResolver.hasPDF(paper: paper))
    }

    func testHasPDF_withRemotePDF_returnsTrue() {
        let paper = makeOnlinePaper(remotePDFURL: URL(string: "https://test.com/paper.pdf"))
        XCTAssertTrue(PDFURLResolver.hasPDF(paper: paper))
    }

    func testHasPDF_withBoth_returnsTrue() {
        let paper = makeOnlinePaper(
            arxivID: "2301.12345",
            remotePDFURL: URL(string: "https://test.com/paper.pdf")
        )
        XCTAssertTrue(PDFURLResolver.hasPDF(paper: paper))
    }

    func testHasPDF_withNeither_returnsFalse() {
        let paper = makeOnlinePaper(arxivID: nil, remotePDFURL: nil)
        XCTAssertFalse(PDFURLResolver.hasPDF(paper: paper))
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

    func testAvailableSources_withBothSources() {
        // Given
        let paper = makeOnlinePaper(
            arxivID: "2301.12345",
            remotePDFURL: URL(string: "https://publisher.com/paper.pdf")
        )

        // When
        let sources = PDFURLResolver.availableSources(for: paper)

        // Then
        XCTAssertEqual(sources.count, 2)
        XCTAssertTrue(sources.contains { $0.type == .preprint && $0.name == "arXiv" })
        XCTAssertTrue(sources.contains { $0.type == .publisher && $0.name == "Publisher" })
    }

    func testAvailableSources_onlyArXiv() {
        // Given
        let paper = makeOnlinePaper(arxivID: "2301.12345")

        // When
        let sources = PDFURLResolver.availableSources(for: paper)

        // Then
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.type, .preprint)
        XCTAssertEqual(sources.first?.name, "arXiv")
        XCTAssertFalse(sources.first?.requiresProxy ?? true)
    }

    func testAvailableSources_onlyPublisher() {
        // Given
        let paper = makeOnlinePaper(remotePDFURL: URL(string: "https://publisher.com/paper.pdf"))

        // When
        let sources = PDFURLResolver.availableSources(for: paper)

        // Then
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.type, .publisher)
        XCTAssertEqual(sources.first?.name, "Publisher")
        XCTAssertTrue(sources.first?.requiresProxy ?? false)
    }

    func testAvailableSources_noSources() {
        // Given
        let paper = makeOnlinePaper()

        // When
        let sources = PDFURLResolver.availableSources(for: paper)

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
}
