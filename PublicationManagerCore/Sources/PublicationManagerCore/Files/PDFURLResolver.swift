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

    /// Check if publication has any PDF source available
    public static func hasPDF(publication: CDPublication) -> Bool {
        publication.arxivID != nil || publication.bestRemotePDFURL != nil
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
