//
//  PDFURLResolver.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog

// MARK: - PDF URL Resolver

/// Resolves the best PDF URL for a publication based on user settings
public struct PDFURLResolver {

    // MARK: - Main Resolution (CDPublication)

    /// Resolve the best PDF URL for a publication based on settings
    ///
    /// This method applies user preferences to determine which PDF source to try first:
    /// - `.preprint`: Try arXiv/preprint sources first, then fall back to publisher
    /// - `.publisher`: Try publisher PDF first (with proxy if configured), then fall back to preprint
    ///
    /// - Parameters:
    ///   - publication: The publication to resolve a PDF URL for
    ///   - settings: User's PDF settings
    /// - Returns: The resolved PDF URL, or nil if no PDF is available
    public static func resolve(
        for publication: CDPublication,
        settings: PDFSettings
    ) -> URL? {
        Logger.files.infoCapture(
            "[PDFURLResolver] Resolving PDF for: '\(publication.title?.prefix(50) ?? "untitled")...', priority: \(settings.sourcePriority.rawValue)",
            category: "pdf"
        )

        let result: URL?
        switch settings.sourcePriority {
        case .preprint:
            // Try preprint sources first (arXiv)
            result = publication.arxivPDFURL ?? publisherPDFURL(for: publication, settings: settings)
        case .publisher:
            // Try publisher first, fall back to preprint
            result = publisherPDFURL(for: publication, settings: settings) ?? publication.arxivPDFURL
        }

        if let url = result {
            Logger.files.infoCapture("[PDFURLResolver] Resolved PDF URL: \(url.absoluteString)", category: "pdf")
        } else {
            Logger.files.infoCapture("[PDFURLResolver] No PDF URL available", category: "pdf")
        }

        return result
    }

    /// Async version that fetches settings from PDFSettingsStore
    public static func resolve(for publication: CDPublication) async -> URL? {
        let settings = await PDFSettingsStore.shared.settings
        return resolve(for: publication, settings: settings)
    }

    // MARK: - Auto-Download Resolution (OpenAlex Priority)

    /// Resolve PDF URL with OpenAlex → Publisher → arXiv priority for auto-download
    ///
    /// This method uses a fixed priority order optimized for automatic downloads:
    /// 1. OpenAlex (Open Access - typically free)
    /// 2. Other publisher PDFs (may require proxy)
    /// 3. arXiv preprints (last resort)
    ///
    /// - Parameters:
    ///   - publication: The publication to resolve a PDF URL for
    ///   - settings: User's PDF settings (for proxy configuration)
    /// - Returns: The resolved PDF URL, or nil if no PDF is available
    public static func resolveForAutoDownload(
        for publication: CDPublication,
        settings: PDFSettings
    ) -> URL? {
        Logger.files.infoCapture(
            "[PDFURLResolver] Resolving PDF for auto-download: '\(publication.title?.prefix(50) ?? "untitled")...'",
            category: "pdf"
        )

        // Log all available URLs for debugging
        logAllAvailableURLs(for: publication, settings: settings)

        let links = publication.pdfLinks

        // 1. Try OpenAlex first (Open Access - typically free)
        if let openAlexLink = links.first(where: { $0.sourceID == "openalex" }) {
            Logger.files.infoCapture("[PDFURLResolver] Using OpenAlex OA URL", category: "pdf")
            return applyProxy(to: openAlexLink.url, settings: settings)
        }

        // 2. Try other publisher PDFs (non-OpenAlex, non-arXiv)
        if let publisherLink = links.first(where: {
            $0.type == .publisher && $0.sourceID != "openalex" && $0.sourceID != "arxiv"
        }) {
            Logger.files.infoCapture("[PDFURLResolver] Using publisher PDF from \(publisherLink.sourceID ?? "unknown")", category: "pdf")
            return applyProxy(to: publisherLink.url, settings: settings)
        }

        // 3. Try ADS scanned articles (hosted directly by ADS, always free)
        if let adsScanLink = links.first(where: { $0.type == .adsScan }) {
            Logger.files.infoCapture("[PDFURLResolver] Using ADS scan PDF", category: "pdf")
            return adsScanLink.url
        }

        // 4. Try arXiv
        if let arxivID = publication.arxivID {
            Logger.files.infoCapture("[PDFURLResolver] Using arXiv PDF", category: "pdf")
            return arXivPDFURL(arxivID: arxivID)
        }

        // 5. Fallback: any available preprint link
        if let preprintLink = links.first(where: { $0.type == .preprint }) {
            Logger.files.infoCapture("[PDFURLResolver] Using preprint PDF from \(preprintLink.sourceID ?? "unknown")", category: "pdf")
            return preprintLink.url
        }

        Logger.files.infoCapture("[PDFURLResolver] No PDF URL available for auto-download", category: "pdf")
        return nil
    }

    /// Async version that fetches settings from PDFSettingsStore
    public static func resolveForAutoDownload(for publication: CDPublication) async -> URL? {
        let settings = await PDFSettingsStore.shared.settings
        return resolveForAutoDownload(for: publication, settings: settings)
    }

    // MARK: - arXiv PDF URL

    /// Generate arXiv PDF URL from an arXiv ID string
    public static func arXivPDFURL(arxivID: String) -> URL? {
        guard !arxivID.isEmpty else { return nil }
        let cleanID = arxivID.trimmingCharacters(in: .whitespaces)
        return URL(string: "https://arxiv.org/pdf/\(cleanID).pdf")
    }

    // MARK: - Publisher PDF URL

    /// Get publisher PDF URL for a publication, applying proxy if configured
    ///
    /// - Parameters:
    ///   - publication: The publication
    ///   - settings: User's PDF settings (for proxy configuration)
    /// - Returns: Publisher PDF URL (possibly proxied), or nil if no remote PDF
    public static func publisherPDFURL(for publication: CDPublication, settings: PDFSettings) -> URL? {
        // First check bestRemotePDFURL (from pdfLinks array)
        if let remotePDF = publication.bestRemotePDFURL {
            return applyProxy(to: remotePDF, settings: settings)
        }
        return nil
    }

    // MARK: - Proxy Application

    /// Apply library proxy to a URL if configured
    ///
    /// Library proxies work by prepending a URL prefix. For example:
    /// - Original: `https://doi.org/10.1234/example`
    /// - Proxied: `https://stanford.idm.oclc.org/login?url=https://doi.org/10.1234/example`
    ///
    /// - Parameters:
    ///   - url: The original URL
    ///   - settings: User's PDF settings
    /// - Returns: Proxied URL if proxy is enabled, otherwise the original URL
    public static func applyProxy(to url: URL, settings: PDFSettings) -> URL {
        guard settings.proxyEnabled,
              !settings.libraryProxyURL.isEmpty else {
            return url
        }

        let proxyURL = settings.libraryProxyURL.trimmingCharacters(in: .whitespaces)

        Logger.files.infoCapture("[PDFURLResolver] Applying library proxy: \(proxyURL)", category: "pdf")

        let proxiedURLString = proxyURL + url.absoluteString
        guard let proxiedURL = URL(string: proxiedURLString) else {
            Logger.files.warning("[PDFURLResolver] Failed to create proxied URL, using original")
            return url
        }

        return proxiedURL
    }

    // MARK: - ADS Abstract Page

    /// Generate ADS abstract page URL for accessing full text sources
    ///
    /// The ADS abstract page shows all available full text sources and is more
    /// reliable than the link_gateway URLs which often return 404.
    ///
    /// - Parameter bibcode: The ADS bibcode
    /// - Returns: ADS abstract page URL
    public static func adsAbstractURL(bibcode: String) -> URL? {
        guard !bibcode.isEmpty else { return nil }
        return URL(string: "https://ui.adsabs.harvard.edu/abs/\(bibcode)/abstract")
    }

    /// Generate ADS link gateway URL for publisher PDF access
    ///
    /// - Warning: This method is deprecated. The link_gateway URLs are unreliable
    ///   and often return 404. Use `adsAbstractURL(bibcode:)` instead.
    ///
    /// - Parameter bibcode: The ADS bibcode
    /// - Returns: ADS gateway URL (unreliable)
    @available(*, deprecated, message: "Use adsAbstractURL(bibcode:) instead - link_gateway URLs are unreliable")
    public static func adsGatewayPDFURL(bibcode: String) -> URL? {
        guard !bibcode.isEmpty else { return nil }
        return URL(string: "https://ui.adsabs.harvard.edu/link_gateway/\(bibcode)/PUB_PDF")
    }

    // MARK: - Convenience Methods

    /// Check if publication has any PDF source available
    public static func hasPDF(publication: CDPublication) -> Bool {
        // Check for arXiv, remote PDF links, or ADS scans
        if publication.arxivID != nil { return true }
        if publication.bestRemotePDFURL != nil { return true }
        // Check for ADS scan links
        if publication.pdfLinks.contains(where: { $0.type == .adsScan }) { return true }
        return false
    }

    /// Get available PDF sources for a publication
    public static func availableSources(for publication: CDPublication) -> [PDFSourceInfo] {
        var sources: [PDFSourceInfo] = []

        if let arxivID = publication.arxivID,
           let url = arXivPDFURL(arxivID: arxivID) {
            sources.append(PDFSourceInfo(
                type: .preprint,
                name: "arXiv",
                url: url,
                requiresProxy: false
            ))
        }

        if let remotePDF = publication.bestRemotePDFURL {
            sources.append(PDFSourceInfo(
                type: .publisher,
                name: "Publisher",
                url: remotePDF,
                requiresProxy: true
            ))
        }

        return sources
    }

    // MARK: - Debug Logging

    /// Log all available PDF URLs for a publication (for debugging failed downloads)
    private static func logAllAvailableURLs(for publication: CDPublication, settings: PDFSettings) {
        let links = publication.pdfLinks
        let arxivID = publication.arxivID
        let doi = publication.doi
        let bibcode = publication.bibcode

        Logger.files.infoCapture("──────────────────────────────────────────", category: "pdf")
        Logger.files.infoCapture("[PDFURLResolver] Available PDF URLs for '\(publication.citeKey)':", category: "pdf")

        // Log identifiers
        if let doi = doi {
            Logger.files.infoCapture("  DOI: \(doi)", category: "pdf")
        }
        if let arxivID = arxivID {
            Logger.files.infoCapture("  arXiv ID: \(arxivID)", category: "pdf")
        }
        if let bibcode = bibcode {
            Logger.files.infoCapture("  Bibcode: \(bibcode)", category: "pdf")
        }

        // Log all pdfLinks
        if links.isEmpty {
            Logger.files.infoCapture("  pdfLinks: (none)", category: "pdf")
        } else {
            Logger.files.infoCapture("  pdfLinks (\(links.count) total):", category: "pdf")
            for (i, link) in links.enumerated() {
                let sourceID = link.sourceID ?? "unknown"
                let typeStr = String(describing: link.type)
                let proxied = settings.proxyEnabled ? " [+proxy]" : ""
                Logger.files.infoCapture("    [\(i+1)] \(sourceID) (\(typeStr))\(proxied): \(link.url.absoluteString)", category: "pdf")
            }
        }

        // Log arXiv URL if available
        if let arxivID = arxivID, let arxivURL = arXivPDFURL(arxivID: arxivID) {
            Logger.files.infoCapture("  arXiv PDF: \(arxivURL.absoluteString)", category: "pdf")
        }

        // Log DOI resolver URL
        if let doi = doi {
            Logger.files.infoCapture("  DOI resolver: https://doi.org/\(doi)", category: "pdf")
        }

        // Log ADS abstract URL
        if let bibcode = bibcode, let adsURL = adsAbstractURL(bibcode: bibcode) {
            Logger.files.infoCapture("  ADS abstract: \(adsURL.absoluteString)", category: "pdf")
        }

        Logger.files.infoCapture("──────────────────────────────────────────", category: "pdf")
    }
}

// MARK: - PDF Source Info

/// Information about a PDF source
public struct PDFSourceInfo: Sendable {
    public let type: PDFSourceType
    public let name: String
    public let url: URL
    public let requiresProxy: Bool

    public enum PDFSourceType: String, Sendable {
        case preprint
        case publisher
    }
}
