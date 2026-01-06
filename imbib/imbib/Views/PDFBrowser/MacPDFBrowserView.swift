//
//  MacPDFBrowserView.swift
//  imbib
//
//  Created by Claude on 2026-01-06.
//

#if os(macOS)
import SwiftUI
import WebKit
import PublicationManagerCore
import OSLog

// MARK: - Main Browser View

/// macOS-specific PDF browser view with WKWebView.
///
/// Provides full browser functionality for navigating publisher
/// authentication flows and capturing PDFs.
struct MacPDFBrowserView: View {

    // MARK: - Properties

    @Bindable var viewModel: PDFBrowserViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header with publication info
            publicationHeader

            Divider()

            // Toolbar
            PDFBrowserToolbar(viewModel: viewModel)

            Divider()

            // WebView
            MacWebViewRepresentable(viewModel: viewModel)

            // Status bar
            PDFBrowserStatusBar(viewModel: viewModel)
        }
        .frame(minWidth: 900, minHeight: 700)
        .onDisappear {
            viewModel.onDismiss?()
        }
    }

    // MARK: - Publication Header

    @ViewBuilder
    private var publicationHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.publication.title ?? "Unknown Title")
                    .font(.headline)
                    .lineLimit(1)

                let authors = viewModel.publication.authorString
                if !authors.isEmpty {
                    Text(authors)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - WebView Representable

/// NSViewRepresentable wrapper for WKWebView.
struct MacWebViewRepresentable: NSViewRepresentable {

    @Bindable var viewModel: PDFBrowserViewModel

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        Logger.pdfBrowser.info("Creating WKWebView for PDF browser")

        // Get configuration with shared process pool for cookie persistence
        let config = PDFBrowserSession.shared.webViewConfiguration()

        // Enable developer extras for debugging
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Store reference in view model
        viewModel.webView = webView

        // Load initial URL
        Logger.pdfBrowser.info("Loading initial URL: \(viewModel.initialURL.absoluteString)")
        webView.load(URLRequest(url: viewModel.initialURL))

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No updates needed - state flows through coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {

        let viewModel: PDFBrowserViewModel
        let interceptor: PDFDownloadInterceptor

        // Track current download
        private var downloadData = Data()
        private var downloadFilename: String = ""
        private var downloadExpectedLength: Int64 = 0

        init(viewModel: PDFBrowserViewModel) {
            self.viewModel = viewModel
            self.interceptor = PDFDownloadInterceptor()
            super.init()

            // Wire up interceptor callbacks
            interceptor.onPDFDownloaded = { [weak self] filename, data in
                Task { @MainActor in
                    self?.viewModel.detectedPDFFilename = filename
                    self?.viewModel.detectedPDFData = data
                    Logger.pdfBrowser.info("PDF detected: \(filename), \(data.count) bytes")
                }
            }

            interceptor.onDownloadProgress = { [weak self] progress in
                Task { @MainActor in
                    self?.viewModel.downloadProgress = progress
                }
            }

            interceptor.onDownloadFailed = { [weak self] error in
                Task { @MainActor in
                    self?.viewModel.errorMessage = "Download failed: \(error.localizedDescription)"
                    self?.viewModel.downloadProgress = nil
                }
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.isLoading = true
                viewModel.updateFromWebView(webView)
                Logger.pdfBrowser.browserNavigation("Started", url: webView.url ?? viewModel.initialURL)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.isLoading = false
                viewModel.updateFromWebView(webView)
                Logger.pdfBrowser.browserNavigation("Finished", url: webView.url ?? viewModel.initialURL)

                // Check if current page is a PDF
                checkForPDFContent(webView)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                viewModel.isLoading = false
                viewModel.errorMessage = error.localizedDescription
                Logger.pdfBrowser.error("Navigation failed: \(error.localizedDescription)")
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                viewModel.isLoading = false
                // Ignore cancelled navigations (user clicked another link)
                if (error as NSError).code != NSURLErrorCancelled {
                    viewModel.errorMessage = error.localizedDescription
                    Logger.pdfBrowser.error("Provisional navigation failed: \(error.localizedDescription)")
                }
            }
        }

        func webView(_ webView: WKWebView,
                    decidePolicyFor navigationAction: WKNavigationAction,
                    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Check if this is a download request
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }

            // Check for PDF content type hint in URL
            if let url = navigationAction.request.url {
                let urlString = url.absoluteString.lowercased()
                if urlString.hasSuffix(".pdf") {
                    Logger.pdfBrowser.info("Detected PDF URL, initiating download: \(url.absoluteString)")
                    decisionHandler(.download)
                    return
                }
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                    decidePolicyFor navigationResponse: WKNavigationResponse,
                    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            // Check if response is a PDF
            if let mimeType = navigationResponse.response.mimeType?.lowercased() {
                if mimeType == "application/pdf" || mimeType == "application/x-pdf" {
                    Logger.pdfBrowser.info("Response is PDF, downloading: \(navigationResponse.response.url?.absoluteString ?? "unknown")")
                    decisionHandler(.download)
                    return
                }
            }

            // Check Content-Disposition header for attachment
            if let httpResponse = navigationResponse.response as? HTTPURLResponse,
               let contentDisposition = httpResponse.allHeaderFields["Content-Disposition"] as? String {
                if contentDisposition.contains("attachment") {
                    Logger.pdfBrowser.info("Response has attachment disposition, downloading")
                    decisionHandler(.download)
                    return
                }
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
            Logger.pdfBrowser.info("Navigation became download")
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
            Logger.pdfBrowser.info("Response became download")
        }

        // MARK: - WKDownloadDelegate

        func download(_ download: WKDownload,
                     decideDestinationUsing response: URLResponse,
                     suggestedFilename: String) async -> URL? {
            downloadFilename = suggestedFilename
            downloadExpectedLength = response.expectedContentLength
            downloadData = Data()

            Logger.pdfBrowser.browserDownload("Started", filename: suggestedFilename)

            Task { @MainActor in
                viewModel.downloadProgress = 0
            }

            // Return nil to handle data in memory
            return nil
        }

        func download(_ download: WKDownload, didReceive data: Data) {
            downloadData.append(data)
            if downloadExpectedLength > 0 {
                let progress = Double(downloadData.count) / Double(downloadExpectedLength)
                Task { @MainActor in
                    viewModel.downloadProgress = progress
                }
            }
        }

        func downloadDidFinish(_ download: WKDownload) {
            Logger.pdfBrowser.browserDownload("Finished", filename: downloadFilename, bytes: downloadData.count)

            // Check if it's a PDF
            if isPDF(data: downloadData) {
                Task { @MainActor in
                    viewModel.detectedPDFFilename = downloadFilename
                    viewModel.detectedPDFData = downloadData
                    viewModel.downloadProgress = nil
                }
            } else {
                Task { @MainActor in
                    viewModel.errorMessage = "Downloaded file is not a PDF"
                    viewModel.downloadProgress = nil
                }
                Logger.pdfBrowser.warning("Downloaded file is not a PDF: \(self.downloadFilename)")
            }

            downloadData = Data()
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            Logger.pdfBrowser.error("Download failed: \(error.localizedDescription)")
            Task { @MainActor in
                viewModel.errorMessage = "Download failed: \(error.localizedDescription)"
                viewModel.downloadProgress = nil
            }
            downloadData = Data()
        }

        // MARK: - WKUIDelegate

        func webView(_ webView: WKWebView,
                    createWebViewWith configuration: WKWebViewConfiguration,
                    for navigationAction: WKNavigationAction,
                    windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Handle target="_blank" links by loading in current view
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        // MARK: - Helpers

        private func isPDF(data: Data) -> Bool {
            guard data.count >= 4 else { return false }
            let magic = data.prefix(4)
            return magic == Data([0x25, 0x50, 0x44, 0x46])  // %PDF
        }

        private func checkForPDFContent(_ webView: WKWebView) {
            // Check if the current page's MIME type is PDF
            // This catches inline PDFs that weren't downloaded
            webView.evaluateJavaScript("document.contentType") { [weak self] result, error in
                if let contentType = result as? String,
                   contentType.lowercased().contains("pdf") {
                    Logger.pdfBrowser.info("Page content is PDF, attempting capture")
                    self?.captureInlinePDF(webView)
                }
            }
        }

        private func captureInlinePDF(_ webView: WKWebView) {
            // For inline PDFs, we need to fetch the data
            guard let url = webView.url else { return }

            Task {
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)

                    if isPDF(data: data) {
                        let filename = response.suggestedFilename ?? url.lastPathComponent
                        await MainActor.run {
                            viewModel.detectedPDFFilename = filename
                            viewModel.detectedPDFData = data
                        }
                        Logger.pdfBrowser.info("Captured inline PDF: \(filename), \(data.count) bytes")
                    }
                } catch {
                    Logger.pdfBrowser.error("Failed to capture inline PDF: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct MacPDFBrowserView_Previews: PreviewProvider {
    static var previews: some View {
        Text("MacPDFBrowserView requires CDPublication")
            .frame(width: 800, height: 600)
    }
}
#endif

#endif // os(macOS)
