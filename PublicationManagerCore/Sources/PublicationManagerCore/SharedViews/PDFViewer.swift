//
//  PDFViewer.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PDFKit
import OSLog

// MARK: - PDF Viewer

/// Cross-platform PDF viewer using PDFKit.
///
/// Supports:
/// - Loading from file URL or data
/// - Zoom controls
/// - Page navigation
/// - Search (future)
/// - Thumbnails (future)
public struct PDFKitViewer: View {

    // MARK: - Properties

    private let source: PDFSource
    @State private var pdfDocument: PDFDocument?
    @State private var error: PDFViewerError?
    @State private var isLoading = true

    // MARK: - Initialization

    /// Create viewer for a file URL
    public init(url: URL) {
        self.source = .url(url)
    }

    /// Create viewer for PDF data
    public init(data: Data) {
        self.source = .data(data)
    }

    /// Create viewer for a linked file (resolves path relative to library)
    public init(linkedFile: CDLinkedFile, library: CDLibrary? = nil) {
        if let library, let bibURL = library.resolveURL() {
            let baseURL = bibURL.deletingLastPathComponent()
            let fileURL = baseURL.appendingPathComponent(linkedFile.relativePath)
            self.source = .url(fileURL)
        } else {
            // Fall back to app support directory
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("imbib")
            let fileURL = appSupport.appendingPathComponent(linkedFile.relativePath)
            self.source = .url(fileURL)
        }
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading PDF...")
            } else if let error {
                errorView(error)
            } else if let document = pdfDocument {
                PDFKitViewRepresentable(document: document)
            } else {
                errorView(.documentNotLoaded)
            }
        }
        .task {
            await loadDocument()
        }
    }

    // MARK: - Loading

    private func loadDocument() async {
        isLoading = true
        error = nil

        do {
            let document = try await loadPDFDocument()
            await MainActor.run {
                self.pdfDocument = document
                self.isLoading = false
            }
        } catch let err as PDFViewerError {
            await MainActor.run {
                self.error = err
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = .loadFailed(error)
                self.isLoading = false
            }
        }
    }

    private func loadPDFDocument() async throws -> PDFDocument {
        switch source {
        case .url(let url):
            Logger.files.debugCapture("Loading PDF from: \(url.path)", category: "pdf")

            // Check if file exists
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw PDFViewerError.fileNotFound(url)
            }

            // Try to access security-scoped resource
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            guard let document = PDFDocument(url: url) else {
                throw PDFViewerError.invalidPDF(url)
            }

            Logger.files.infoCapture("Loaded PDF with \(document.pageCount) pages", category: "pdf")
            return document

        case .data(let data):
            Logger.files.debugCapture("Loading PDF from data (\(data.count) bytes)", category: "pdf")

            guard let document = PDFDocument(data: data) else {
                throw PDFViewerError.invalidData
            }

            Logger.files.infoCapture("Loaded PDF with \(document.pageCount) pages", category: "pdf")
            return document
        }
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(_ error: PDFViewerError) -> some View {
        ContentUnavailableView {
            Label("Unable to Load PDF", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Try Again") {
                Task { await loadDocument() }
            }
        }
    }
}

// MARK: - PDF Source

private enum PDFSource {
    case url(URL)
    case data(Data)
}

// MARK: - PDF Viewer Error

public enum PDFViewerError: LocalizedError {
    case fileNotFound(URL)
    case invalidPDF(URL)
    case invalidData
    case documentNotLoaded
    case loadFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "PDF file not found: \(url.lastPathComponent)"
        case .invalidPDF(let url):
            return "Invalid or corrupted PDF: \(url.lastPathComponent)"
        case .invalidData:
            return "Invalid PDF data"
        case .documentNotLoaded:
            return "PDF document could not be loaded"
        case .loadFailed(let error):
            return "Failed to load PDF: \(error.localizedDescription)"
        }
    }
}

// MARK: - Platform-Specific PDFKit View

#if os(macOS)

/// macOS PDFKit wrapper (basic, read-only)
struct PDFKitViewRepresentable: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .textBackgroundColor
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
    }
}

/// macOS PDFKit wrapper with controls
struct ControlledPDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int
    @Binding var scaleFactor: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .textBackgroundColor

        // Observe page changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        // Observe scale changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scaleChanged(_:)),
            name: .PDFViewScaleChanged,
            object: pdfView
        )

        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }

        // Update page if changed externally
        if let page = pdfView.document?.page(at: currentPage - 1),
           pdfView.currentPage !== page {
            pdfView.go(to: page)
        }

        // Update scale if changed externally
        let targetScale = scaleFactor
        if abs(pdfView.scaleFactor - targetScale) > 0.01 {
            pdfView.scaleFactor = targetScale
        }
    }

    class Coordinator: NSObject {
        var parent: ControlledPDFKitView
        weak var pdfView: PDFView?

        init(_ parent: ControlledPDFKitView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = pdfView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else { return }

            let pageIndex = document.index(for: currentPage)

            DispatchQueue.main.async { [weak self] in
                self?.parent.currentPage = pageIndex + 1
            }
        }

        @objc func scaleChanged(_ notification: Notification) {
            guard let pdfView = pdfView else { return }
            let scale = pdfView.scaleFactor
            DispatchQueue.main.async { [weak self] in
                self?.parent.scaleFactor = scale
            }
        }
    }
}

#else

/// iOS/iPadOS PDFKit wrapper (basic, read-only)
struct PDFKitViewRepresentable: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .systemBackground
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
    }
}

/// iOS PDFKit wrapper with controls
struct ControlledPDFKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int
    @Binding var scaleFactor: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .systemBackground

        // Observe page changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        // Observe scale changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scaleChanged(_:)),
            name: .PDFViewScaleChanged,
            object: pdfView
        )

        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }

        // Update page if changed externally
        if let page = pdfView.document?.page(at: currentPage - 1),
           pdfView.currentPage !== page {
            pdfView.go(to: page)
        }

        // Update scale if changed externally
        let targetScale = scaleFactor
        if abs(pdfView.scaleFactor - targetScale) > 0.01 {
            pdfView.scaleFactor = targetScale
        }
    }

    class Coordinator: NSObject {
        var parent: ControlledPDFKitView
        weak var pdfView: PDFView?

        init(_ parent: ControlledPDFKitView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = pdfView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else { return }

            let pageIndex = document.index(for: currentPage)

            DispatchQueue.main.async { [weak self] in
                self?.parent.currentPage = pageIndex + 1
            }
        }

        @objc func scaleChanged(_ notification: Notification) {
            guard let pdfView = pdfView else { return }
            let scale = pdfView.scaleFactor
            DispatchQueue.main.async { [weak self] in
                self?.parent.scaleFactor = scale
            }
        }
    }
}

#endif

// MARK: - Online Paper PDF Viewer

/// PDF viewer for online papers that downloads from remote URL if needed.
///
/// Uses SessionCache to:
/// 1. Check if PDF is already cached
/// 2. Download and cache if not
/// 3. Display from cache
public struct OnlinePaperPDFViewer: View {

    let paper: OnlinePaper

    @State private var localURL: URL?
    @State private var isDownloading = false
    @State private var error: String?

    public init(paper: OnlinePaper) {
        self.paper = paper
    }

    public var body: some View {
        Group {
            if isDownloading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Downloading PDF...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let localURL {
                PDFViewerWithControls(url: localURL)
            } else if let error {
                errorView(error)
            } else {
                noPDFView
            }
        }
        .task {
            await loadPDF()
        }
    }

    private func loadPDF() async {
        // Check if we have a remote PDF URL
        guard let remotePDFURL = paper.remotePDFURL else {
            return
        }

        isDownloading = true
        error = nil

        do {
            // Try to get cached or download
            let cachedURL = try await SessionCache.shared.cachePDF(from: remotePDFURL, for: paper.id)
            await MainActor.run {
                self.localURL = cachedURL
                self.isDownloading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isDownloading = false
            }
        }
    }

    private var noPDFView: some View {
        ContentUnavailableView {
            Label("No PDF Available", systemImage: "doc.richtext")
        } description: {
            Text("This paper does not have a PDF link.")
        }
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Download Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await loadPDF() }
            }
        }
    }
}

// MARK: - PDF Viewer with Controls

/// PDF viewer with toolbar controls for zoom and navigation.
public struct PDFViewerWithControls: View {

    // MARK: - Properties

    private let source: PDFSource
    @State private var pdfDocument: PDFDocument?
    @State private var error: PDFViewerError?
    @State private var isLoading = true
    @State private var currentPage = 1
    @State private var totalPages = 0
    @State private var scaleFactor: CGFloat = 1.0

    // MARK: - Initialization

    public init(url: URL) {
        self.source = .url(url)
    }

    public init(data: Data) {
        self.source = .data(data)
    }

    public init(linkedFile: CDLinkedFile, library: CDLibrary? = nil) {
        if let library, let bibURL = library.resolveURL() {
            let baseURL = bibURL.deletingLastPathComponent()
            let fileURL = baseURL.appendingPathComponent(linkedFile.relativePath)
            self.source = .url(fileURL)
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("imbib")
            let fileURL = appSupport.appendingPathComponent(linkedFile.relativePath)
            self.source = .url(fileURL)
        }
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // PDF Content
            Group {
                if isLoading {
                    ProgressView("Loading PDF...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    errorView(error)
                } else if let document = pdfDocument {
                    ControlledPDFKitView(
                        document: document,
                        currentPage: $currentPage,
                        scaleFactor: $scaleFactor
                    )
                } else {
                    errorView(.documentNotLoaded)
                }
            }

            // Toolbar
            if pdfDocument != nil {
                pdfToolbar
            }
        }
        .task {
            await loadDocument()
        }
    }

    // MARK: - Toolbar

    private var pdfToolbar: some View {
        HStack(spacing: 16) {
            // Page Navigation
            HStack(spacing: 8) {
                Button {
                    goToPreviousPage()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentPage <= 1)

                Text("\(currentPage) / \(totalPages)")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(minWidth: 60)

                Button {
                    goToNextPage()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentPage >= totalPages)
            }

            Divider()
                .frame(height: 20)

            // Zoom Controls
            HStack(spacing: 8) {
                Button {
                    zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(scaleFactor <= 0.25)

                Text("\(Int(scaleFactor * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(minWidth: 50)

                Button {
                    zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .disabled(scaleFactor >= 4.0)

                Button {
                    resetZoom()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
            }

            Spacer()

            // Open in External App
            if case .url(let url) = source {
                Button {
                    openInExternalApp(url: url)
                } label: {
                    Label("Open in Preview", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Loading

    private func loadDocument() async {
        isLoading = true
        error = nil

        do {
            let document = try await loadPDFDocument()
            await MainActor.run {
                self.pdfDocument = document
                self.totalPages = document.pageCount
                self.isLoading = false
            }
        } catch let err as PDFViewerError {
            await MainActor.run {
                self.error = err
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = .loadFailed(error)
                self.isLoading = false
            }
        }
    }

    private func loadPDFDocument() async throws -> PDFDocument {
        switch source {
        case .url(let url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw PDFViewerError.fileNotFound(url)
            }

            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            guard let document = PDFDocument(url: url) else {
                throw PDFViewerError.invalidPDF(url)
            }

            return document

        case .data(let data):
            guard let document = PDFDocument(data: data) else {
                throw PDFViewerError.invalidData
            }
            return document
        }
    }

    // MARK: - Actions

    private func goToPreviousPage() {
        if currentPage > 1 {
            currentPage -= 1
        }
    }

    private func goToNextPage() {
        if currentPage < totalPages {
            currentPage += 1
        }
    }

    private func zoomIn() {
        scaleFactor = min(scaleFactor * 1.25, 4.0)
    }

    private func zoomOut() {
        scaleFactor = max(scaleFactor / 1.25, 0.25)
    }

    private func resetZoom() {
        scaleFactor = 1.0
    }

    private func openInExternalApp(url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        // iOS would use UIApplication.shared.open() but needs UIKit import
        #endif
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(_ error: PDFViewerError) -> some View {
        ContentUnavailableView {
            Label("Unable to Load PDF", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Try Again") {
                Task { await loadDocument() }
            }
        }
    }
}
