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

    // MARK: - Auto-Download Resolution

    /// Resolve PDF URL for auto-download, respecting user's priority setting
    ///
    /// This method applies user preferences while avoiding unreliable URLs:
    /// - `.preprint`: Try arXiv/preprints first, then publisher
    /// - `.publisher`: Try publisher first (via DOI or direct links), then preprints
    ///
    /// URL reliability order (within each category):
    /// 1. Direct PDF URLs (arxiv.org/pdf, direct publisher links)
    /// 2. OpenAlex Open Access URLs
    /// 3. DOI with content negotiation (for publisher)
    /// 4. ADS scanned articles (always work)
    /// 5. ADS link_gateway (often unreliable - last resort)
    ///
    /// - Parameters:
    ///   - publication: The publication to resolve a PDF URL for
    ///   - settings: User's PDF settings (priority, proxy configuration)
    /// - Returns: The resolved PDF URL, or nil if no PDF is available
    public static func resolveForAutoDownload(
        for publication: CDPublication,
        settings: PDFSettings
    ) -> URL? {
        Logger.files.infoCapture(
            "[PDFURLResolver] Resolving PDF for auto-download: '\(publication.title?.prefix(50) ?? "untitled")...', priority: \(settings.sourcePriority.rawValue)",
            category: "pdf"
        )

        // Log all available URLs for debugging
        logAllAvailableURLs(for: publication, settings: settings)

        // Apply user's priority setting
        // Note: Gateway URLs (like ADS link_gateway) are unreliable and only used as absolute last resort
        let result: URL?
        switch settings.sourcePriority {
        case .preprint:
            // Try preprint sources first, then publisher
            result = resolvePreprintURL(for: publication, settings: settings)
                ?? resolvePublisherURL(for: publication, settings: settings)
        case .publisher:
            // Try publisher first, then preprint
            result = resolvePublisherURL(for: publication, settings: settings)
                ?? resolvePreprintURL(for: publication, settings: settings)
        }

        // If we have a result, use it
        if result != nil {
            return result
        }

        // Absolute last resort: unreliable gateway URLs
        return resolveGatewayURL(for: publication, settings: settings)
    }

    /// Resolve best preprint/arXiv PDF URL
    private static func resolvePreprintURL(
        for publication: CDPublication,
        settings: PDFSettings
    ) -> URL? {
        // 1. Direct arXiv PDF (most reliable)
        if let arxivID = publication.arxivID, !arxivID.isEmpty {
            if let url = arXivPDFURL(arxivID: arxivID) {
                Logger.files.infoCapture("[PDFURLResolver] Using direct arXiv PDF: \(arxivID)", category: "pdf")
                return url
            }
        }

        let links = publication.pdfLinks

        // 2. Preprint links from pdfLinks (may include arXiv added by sources)
        if let preprintLink = links.first(where: { $0.type == .preprint && isDirectPDFURL($0.url) }) {
            Logger.files.infoCapture("[PDFURLResolver] Using preprint PDF from \(preprintLink.sourceID ?? "unknown")", category: "pdf")
            return preprintLink.url
        }

        // 3. Any preprint link (even if not direct PDF)
        if let preprintLink = links.first(where: { $0.type == .preprint }) {
            Logger.files.infoCapture("[PDFURLResolver] Using preprint link from \(preprintLink.sourceID ?? "unknown")", category: "pdf")
            return preprintLink.url
        }

        return nil
    }

    /// Resolve best publisher PDF URL, avoiding unreliable gateway URLs
    private static func resolvePublisherURL(
        for publication: CDPublication,
        settings: PDFSettings
    ) -> URL? {
        let links = publication.pdfLinks

        // 1. OpenAlex Open Access (typically reliable and free)
        if let openAlexLink = links.first(where: { $0.sourceID == "openalex" }) {
            Logger.files.infoCapture("[PDFURLResolver] Using OpenAlex OA URL", category: "pdf")
            return applyProxy(to: openAlexLink.url, settings: settings)
        }

        // 2. Direct publisher PDF URLs (not gateway URLs)
        if let directLink = links.first(where: {
            $0.type == .publisher && isDirectPDFURL($0.url) && !isGatewayURL($0.url)
        }) {
            Logger.files.infoCapture("[PDFURLResolver] Using direct publisher PDF", category: "pdf")
            return applyProxy(to: directLink.url, settings: settings)
        }

        // 3. ADS scanned articles (always free and reliable)
        if let adsScanLink = links.first(where: { $0.type == .adsScan }) {
            Logger.files.infoCapture("[PDFURLResolver] Using ADS scan PDF", category: "pdf")
            return adsScanLink.url
        }

        // 4. DOI-based PDF URL (use DOI resolver - more reliable than gateway)
        if let doi = publication.doi, !doi.isEmpty {
            let doiURL = URL(string: "https://doi.org/\(doi)")
            Logger.files.infoCapture("[PDFURLResolver] Using DOI resolver: \(doi)", category: "pdf")
            return applyProxy(to: doiURL!, settings: settings)
        }

        // Note: Gateway URLs are NOT returned here - they're only used as absolute last resort
        // in resolveGatewayURL() after both publisher AND preprint methods have failed
        return nil
    }

    /// Resolve gateway URLs as absolute last resort (often unreliable)
    private static func resolveGatewayURL(
        for publication: CDPublication,
        settings: PDFSettings
    ) -> URL? {
        let links = publication.pdfLinks

        // ADS link_gateway URLs - often unreliable but sometimes work
        if let gatewayLink = links.first(where: { $0.type == .publisher && isGatewayURL($0.url) }) {
            Logger.files.infoCapture("[PDFURLResolver] Using ADS gateway (unreliable last resort): \(gatewayLink.url.absoluteString)", category: "pdf")
            return applyProxy(to: gatewayLink.url, settings: settings)
        }

        return nil
    }

    /// Check if URL appears to be a direct PDF link
    private static func isDirectPDFURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let host = url.host?.lowercased() ?? ""

        // Direct PDF file extensions
        if path.hasSuffix(".pdf") { return true }

        // Known direct PDF hosts
        if host.contains("arxiv.org") && path.contains("/pdf/") { return true }
        if host.contains("article-pdf") { return true }  // OUP, etc.

        return false
    }

    /// Check if URL is a gateway/redirect URL (often unreliable)
    private static func isGatewayURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let urlString = url.absoluteString.lowercased()

        // ADS link_gateway URLs are notoriously unreliable
        if urlString.contains("link_gateway") { return true }

        // Generic gateway patterns
        if path.contains("/gateway/") { return true }
        if path.contains("/redirect/") { return true }

        return false
    }

    /// Async version that fetches settings from PDFSettingsStore
    public static func resolveForAutoDownload(for publication: CDPublication) async -> URL? {
        let settings = await PDFSettingsStore.shared.settings
        return resolveForAutoDownload(for: publication, settings: settings)
    }

    // MARK: - arXiv PDF URL

    /// Generate arXiv PDF URL from an arXiv ID string
    public static func arXivPDFURL(arxivID: String) -> URL? {
        let cleanID = arxivID.trimmingCharacters(in: .whitespaces)
        guard !cleanID.isEmpty else { return nil }
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

        // Log raw identifier fields for debugging extraction issues
        Logger.files.infoCapture("  [Fields] eprint='\(publication.fields["eprint"] ?? "nil")' arxivid='\(publication.fields["arxivid"] ?? "nil")' arxiv='\(publication.fields["arxiv"] ?? "nil")'", category: "pdf")
        Logger.files.infoCapture("  [Extracted] arxivID property='\(arxivID ?? "nil")'", category: "pdf")

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
