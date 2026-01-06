//
//  PDFBrowserViewModel.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-06.
//

import Foundation
import OSLog

#if canImport(WebKit)
import WebKit
#endif

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Platform-agnostic view model for the PDF browser.
///
/// This view model manages the state of an interactive web browser session
/// for downloading PDFs from publishers. It works on macOS and iOS (not tvOS).
///
/// The platform-specific view (NSViewRepresentable or UIViewRepresentable)
/// sets the `webView` reference and calls update methods from WKNavigationDelegate.
@Observable
@MainActor
public final class PDFBrowserViewModel {

    // MARK: - State

    /// Current URL displayed in the browser
    public var currentURL: URL?

    /// Page title from the web view
    public var pageTitle: String = ""

    /// Whether the page is currently loading
    public var isLoading: Bool = true

    /// Whether the browser can navigate back
    public var canGoBack: Bool = false

    /// Whether the browser can navigate forward
    public var canGoForward: Bool = false

    /// Download progress (0.0 to 1.0)
    public var downloadProgress: Double?

    /// Data of a detected PDF download
    public var detectedPDFData: Data?

    /// Filename of a detected PDF download
    public var detectedPDFFilename: String?

    /// Error message to display
    public var errorMessage: String?

    // MARK: - Context

    /// The publication we're fetching a PDF for
    public let publication: CDPublication

    /// The URL to load initially
    public let initialURL: URL

    /// The library ID for context
    public let libraryID: UUID

    // MARK: - Callbacks

    /// Called when a PDF is captured and should be saved
    public var onPDFCaptured: ((Data) async -> Void)?

    /// Called when the browser should be dismissed
    public var onDismiss: (() -> Void)?

    // MARK: - WebView Reference

    #if canImport(WebKit)
    /// Reference to the WKWebView (set by platform-specific view)
    public weak var webView: WKWebView?
    #endif

    // MARK: - Initialization

    public init(publication: CDPublication, initialURL: URL, libraryID: UUID) {
        self.publication = publication
        self.initialURL = initialURL
        self.libraryID = libraryID
        self.currentURL = initialURL

        Logger.pdfBrowser.info("PDFBrowserViewModel initialized for: \(publication.title ?? "Unknown")")
        Logger.pdfBrowser.info("Starting URL: \(initialURL.absoluteString)")
    }

    // MARK: - Navigation Actions

    /// Navigate back in browser history
    public func goBack() {
        #if canImport(WebKit)
        guard let webView = webView, webView.canGoBack else { return }
        webView.goBack()
        Logger.pdfBrowser.info("Navigating back")
        #endif
    }

    /// Navigate forward in browser history
    public func goForward() {
        #if canImport(WebKit)
        guard let webView = webView, webView.canGoForward else { return }
        webView.goForward()
        Logger.pdfBrowser.info("Navigating forward")
        #endif
    }

    /// Reload the current page
    public func reload() {
        #if canImport(WebKit)
        webView?.reload()
        Logger.pdfBrowser.info("Reloading page")
        #endif
    }

    /// Stop loading the current page
    public func stopLoading() {
        #if canImport(WebKit)
        webView?.stopLoading()
        Logger.pdfBrowser.info("Stopped loading")
        #endif
    }

    // MARK: - Clipboard

    /// Copy the current URL to the system clipboard
    public func copyURLToClipboard() {
        guard let url = currentURL else {
            Logger.pdfBrowser.warning("No URL to copy")
            return
        }

        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        Logger.pdfBrowser.info("URL copied to clipboard (macOS): \(url.absoluteString)")
        #elseif canImport(UIKit)
        UIPasteboard.general.string = url.absoluteString
        Logger.pdfBrowser.info("URL copied to clipboard (iOS): \(url.absoluteString)")
        #endif
    }

    // MARK: - PDF Capture

    /// Save the detected PDF to the library and close the browser
    public func saveDetectedPDF() async {
        guard let data = detectedPDFData else {
            Logger.pdfBrowser.warning("No PDF data to save")
            return
        }

        Logger.pdfBrowser.info("Saving detected PDF: \(self.detectedPDFFilename ?? "unknown"), \(data.count) bytes")

        await onPDFCaptured?(data)

        // Clear the detected PDF
        detectedPDFData = nil
        detectedPDFFilename = nil

        Logger.pdfBrowser.info("PDF saved successfully, closing browser")

        // Auto-close the browser window after saving
        dismiss()
    }

    /// Called when a PDF is detected by the download interceptor
    public func pdfDetected(filename: String, data: Data) {
        detectedPDFFilename = filename
        detectedPDFData = data
        downloadProgress = nil

        Logger.pdfBrowser.info("PDF detected: \(filename), \(data.count) bytes")
    }

    /// Clear any detected PDF without saving
    public func clearDetectedPDF() {
        detectedPDFData = nil
        detectedPDFFilename = nil
        Logger.pdfBrowser.info("Cleared detected PDF")
    }

    // MARK: - State Updates (called by platform view coordinator)

    #if canImport(WebKit)
    /// Update all state from the web view
    public func updateFromWebView(_ webView: WKWebView) {
        currentURL = webView.url
        pageTitle = webView.title ?? ""
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
    #endif

    /// Update state after navigation completes
    public func navigationDidFinish(url: URL?, title: String?) {
        currentURL = url
        pageTitle = title ?? ""
        isLoading = false
        errorMessage = nil

        #if canImport(WebKit)
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
        #endif

        if let url = url {
            Logger.pdfBrowser.browserNavigation("Loaded", url: url)
        }
    }

    /// Update state when navigation starts
    public func navigationDidStart() {
        isLoading = true
        errorMessage = nil
    }

    /// Update state when navigation fails
    public func navigationDidFail(error: Error) {
        isLoading = false
        errorMessage = error.localizedDescription

        Logger.pdfBrowser.error("Navigation failed: \(error.localizedDescription)")
    }

    /// Update download progress
    public func updateDownloadProgress(_ progress: Double) {
        downloadProgress = progress
    }

    /// Called when download starts
    public func downloadDidStart(filename: String) {
        downloadProgress = 0
        Logger.pdfBrowser.info("Download started: \(filename)")
    }

    /// Called when download fails
    public func downloadDidFail(error: Error) {
        downloadProgress = nil
        errorMessage = "Download failed: \(error.localizedDescription)"

        Logger.pdfBrowser.error("Download failed: \(error.localizedDescription)")
    }

    // MARK: - Dismiss

    /// Dismiss the browser window
    public func dismiss() {
        Logger.pdfBrowser.info("Dismissing browser")
        onDismiss?()
    }
}
