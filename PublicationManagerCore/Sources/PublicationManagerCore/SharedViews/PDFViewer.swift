//
//  PDFViewer.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PDFKit
import OSLog

// MARK: - Notification Names

extension Notification.Name {
    static let pdfViewerNavigateToSelection = Notification.Name("pdfViewerNavigateToSelection")
}

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

        // Observe search navigation requests
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.navigateToSelection(_:)),
            name: .pdfViewerNavigateToSelection,
            object: nil
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

        @objc func navigateToSelection(_ notification: Notification) {
            guard let pdfView = pdfView,
                  let selection = notification.userInfo?["selection"] as? PDFSelection else { return }

            DispatchQueue.main.async {
                pdfView.setCurrentSelection(selection, animate: true)
                pdfView.scrollSelectionToVisible(nil)
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

        // Observe search navigation requests
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.navigateToSelection(_:)),
            name: .pdfViewerNavigateToSelection,
            object: nil
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

        @objc func navigateToSelection(_ notification: Notification) {
            guard let pdfView = pdfView,
                  let selection = notification.userInfo?["selection"] as? PDFSelection else { return }

            DispatchQueue.main.async {
                pdfView.setCurrentSelection(selection, animate: true)
                pdfView.scrollSelectionToVisible(nil)
            }
        }
    }
}

#endif

// MARK: - Online Paper PDF Viewer

// Note: OnlinePaperPDFViewer has been removed as part of ADR-016.
// PDFs for all papers (including search results) are now handled via PDFManager
// which downloads and stores PDFs in the library folder as linked files.

// MARK: - PDF Viewer with Controls

/// PDF viewer with toolbar controls for zoom and navigation.
public struct PDFViewerWithControls: View {

    // MARK: - Properties

    private let source: PDFSource
    private let publicationID: UUID?

    @State private var pdfDocument: PDFDocument?
    @State private var error: PDFViewerError?
    @State private var isLoading = true
    @State private var currentPage = 1
    @State private var totalPages = 0
    @State private var scaleFactor: CGFloat = 1.0
    @State private var saveTask: Task<Void, Never>?

    // Search state
    @State private var searchQuery: String = ""
    @State private var searchResults: [PDFSelection] = []
    @State private var currentSearchIndex: Int = 0
    @State private var isSearching: Bool = false

    // MARK: - Initialization

    public init(url: URL, publicationID: UUID? = nil) {
        self.source = .url(url)
        self.publicationID = publicationID
    }

    public init(data: Data, publicationID: UUID? = nil) {
        self.source = .data(data)
        self.publicationID = publicationID
    }

    public init(linkedFile: CDLinkedFile, library: CDLibrary? = nil, publicationID: UUID? = nil) {
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
        self.publicationID = publicationID
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
        .onChange(of: currentPage) { _, newPage in
            schedulePositionSave()
        }
        .onChange(of: scaleFactor) { _, newScale in
            schedulePositionSave()
        }
        .onDisappear {
            savePositionImmediately()
        }
    }

    // MARK: - Reading Position

    private func loadSavedPosition() async {
        guard let pubID = publicationID else { return }

        if let position = await ReadingPositionStore.shared.get(for: pubID) {
            await MainActor.run {
                // Only apply if within valid range
                if position.pageNumber >= 1 && position.pageNumber <= totalPages {
                    currentPage = position.pageNumber
                }
                if position.zoomLevel >= 0.25 && position.zoomLevel <= 4.0 {
                    scaleFactor = position.zoomLevel
                }
                Logger.files.debugCapture("Restored reading position: page \(position.pageNumber), zoom \(Int(position.zoomLevel * 100))%", category: "pdf")
            }
        }
    }

    private func schedulePositionSave() {
        guard publicationID != nil else { return }

        // Cancel existing save task
        saveTask?.cancel()

        // Schedule debounced save (500ms delay)
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await savePosition()
        }
    }

    private func savePositionImmediately() {
        guard publicationID != nil else { return }

        saveTask?.cancel()
        Task {
            await savePosition()
        }
    }

    private func savePosition() async {
        guard let pubID = publicationID else { return }

        let position = ReadingPosition(
            pageNumber: currentPage,
            zoomLevel: scaleFactor,
            lastReadDate: Date()
        )
        await ReadingPositionStore.shared.save(position, for: pubID)
    }

    // MARK: - Search

    private func performSearch() {
        guard !searchQuery.isEmpty, let document = pdfDocument else {
            searchResults = []
            currentSearchIndex = 0
            return
        }

        isSearching = true

        // Perform search (synchronous, but fast for most PDFs)
        let results = document.findString(searchQuery, withOptions: [.caseInsensitive])

        searchResults = results
        currentSearchIndex = results.isEmpty ? 0 : 0
        isSearching = false

        Logger.files.debugCapture("Search found \(results.count) results for '\(searchQuery)'", category: "pdf")

        // Navigate to first result
        if !results.isEmpty {
            navigateToSearchResult(at: 0)
        }
    }

    private func clearSearch() {
        searchQuery = ""
        searchResults = []
        currentSearchIndex = 0
    }

    private func previousSearchResult() {
        guard !searchResults.isEmpty else { return }
        if currentSearchIndex > 0 {
            currentSearchIndex -= 1
            navigateToSearchResult(at: currentSearchIndex)
        }
    }

    private func nextSearchResult() {
        guard !searchResults.isEmpty else { return }
        if currentSearchIndex < searchResults.count - 1 {
            currentSearchIndex += 1
            navigateToSearchResult(at: currentSearchIndex)
        }
    }

    private func navigateToSearchResult(at index: Int) {
        guard index >= 0, index < searchResults.count else { return }
        let selection = searchResults[index]

        // Post notification that coordinator will handle
        NotificationCenter.default.post(
            name: .pdfViewerNavigateToSelection,
            object: nil,
            userInfo: ["selection": selection]
        )
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

            Divider()
                .frame(height: 20)

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .onSubmit {
                        performSearch()
                    }

                if !searchQuery.isEmpty {
                    Button {
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if !searchResults.isEmpty {
                    Text("\(currentSearchIndex + 1)/\(searchResults.count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Button {
                        previousSearchResult()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(currentSearchIndex <= 0)

                    Button {
                        nextSearchResult()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(currentSearchIndex >= searchResults.count - 1)
                }

                if isSearching {
                    ProgressView()
                        .controlSize(.small)
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
            // Load saved reading position after document is ready
            await loadSavedPosition()
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
