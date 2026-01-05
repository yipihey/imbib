//
//  PDFURLResolver.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog

// MARK: - PDF URL Resolver

/// Resolves the best PDF URL for an online paper based on user settings
public struct PDFURLResolver {

    // MARK: - Main Resolution

    /// Resolve the best PDF URL for an online paper based on settings
    ///
    /// This method applies user preferences to determine which PDF source to try first:
    /// - `.preprint`: Try arXiv/preprint sources first, then fall back to publisher
    /// - `.publisher`: Try publisher PDF first (with proxy if configured), then fall back to preprint
    ///
    /// - Parameters:
    ///   - paper: The online paper to resolve a PDF URL for
    ///   - settings: User's PDF settings
    /// - Returns: The resolved PDF URL, or nil if no PDF is available
    public static func resolve(
        for paper: OnlinePaper,
        settings: PDFSettings
    ) -> URL? {
        Logger.files.infoCapture(
            "[PDFURLResolver] Resolving PDF for: '\(paper.title.prefix(50))...', priority: \(settings.sourcePriority.rawValue)",
            category: "pdf"
        )

        let result: URL?
        switch settings.sourcePriority {
        case .preprint:
            // Try preprint sources first
            result = arXivPDFURL(for: paper) ?? publisherPDFURL(for: paper, settings: settings)
        case .publisher:
            // Try publisher first, fall back to preprint
            result = publisherPDFURL(for: paper, settings: settings) ?? arXivPDFURL(for: paper)
        }

        if let url = result {
            Logger.files.infoCapture("[PDFURLResolver] Resolved PDF URL: \(url.absoluteString)", category: "pdf")
        } else {
            Logger.files.infoCapture("[PDFURLResolver] No PDF URL available", category: "pdf")
        }

        return result
    }

    /// Async version that fetches settings from PDFSettingsStore
    public static func resolve(for paper: OnlinePaper) async -> URL? {
        let settings = await PDFSettingsStore.shared.settings
        return resolve(for: paper, settings: settings)
    }

    // MARK: - arXiv PDF URL

    /// Generate arXiv PDF URL if paper has arXiv ID
    ///
    /// Handles various arXiv ID formats:
    /// - New format: `2301.12345` or `2301.12345v2`
    /// - Old format: `hep-th/9901001` or `hep-th/9901001v1`
    ///
    /// - Parameter paper: The online paper
    /// - Returns: arXiv PDF URL, or nil if no arXiv ID
    public static func arXivPDFURL(for paper: OnlinePaper) -> URL? {
        guard let arxivID = paper.arxivID, !arxivID.isEmpty else {
            return nil
        }

        // Clean arXiv ID - keep the base ID without version for consistent caching
        // But actually, arXiv redirects versioned URLs to the correct PDF, so we can use the original
        let cleanID = arxivID.trimmingCharacters(in: .whitespaces)

        Logger.files.infoCapture("[PDFURLResolver] Generating arXiv PDF URL for ID: \(cleanID)", category: "pdf")

        return URL(string: "https://arxiv.org/pdf/\(cleanID).pdf")
    }

    /// Generate arXiv PDF URL from an arXiv ID string
    public static func arXivPDFURL(arxivID: String) -> URL? {
        guard !arxivID.isEmpty else { return nil }
        let cleanID = arxivID.trimmingCharacters(in: .whitespaces)
        return URL(string: "https://arxiv.org/pdf/\(cleanID).pdf")
    }

    // MARK: - Publisher PDF URL

    /// Get publisher PDF URL, applying proxy if configured
    ///
    /// - Parameters:
    ///   - paper: The online paper
    ///   - settings: User's PDF settings (for proxy configuration)
    /// - Returns: Publisher PDF URL (possibly proxied), or nil if no remote PDF
    public static func publisherPDFURL(for paper: OnlinePaper, settings: PDFSettings) -> URL? {
        guard let remotePDF = paper.remotePDFURL else {
            return nil
        }

        return applyProxy(to: remotePDF, settings: settings)
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

    // MARK: - ADS Link Gateway

    /// Generate ADS link gateway URL for publisher PDF access
    ///
    /// The ADS link gateway (`/link_gateway/{bibcode}/PUB_PDF`) redirects to the
    /// publisher PDF. This may require authentication or institutional access.
    ///
    /// - Parameter bibcode: The ADS bibcode
    /// - Returns: ADS gateway URL
    public static func adsGatewayPDFURL(bibcode: String) -> URL? {
        guard !bibcode.isEmpty else { return nil }
        return URL(string: "https://ui.adsabs.harvard.edu/link_gateway/\(bibcode)/PUB_PDF")
    }

    // MARK: - Convenience Methods

    /// Check if paper has any PDF source available
    public static func hasPDF(paper: OnlinePaper) -> Bool {
        paper.arxivID != nil || paper.remotePDFURL != nil
    }

    /// Get available PDF sources for a paper
    public static func availableSources(for paper: OnlinePaper) -> [PDFSourceInfo] {
        var sources: [PDFSourceInfo] = []

        if let arxivID = paper.arxivID,
           let url = arXivPDFURL(arxivID: arxivID) {
            sources.append(PDFSourceInfo(
                type: .preprint,
                name: "arXiv",
                url: url,
                requiresProxy: false
            ))
        }

        if let remotePDF = paper.remotePDFURL {
            sources.append(PDFSourceInfo(
                type: .publisher,
                name: "Publisher",
                url: remotePDF,
                requiresProxy: true
            ))
        }

        return sources
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
