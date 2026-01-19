//
//  IOSPDFTab.swift
//  imbib-iOS
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI
import PublicationManagerCore
import OSLog

private let pdfLogger = Logger(subsystem: "com.imbib.app", category: "pdf-tab")

/// PDF tab state
private enum PDFTabState: Equatable {
    case loading
    case hasPDF(CDLinkedFile)
    case downloading(progress: Double)
    case downloadFailed(message: String)
    case noPDF
}

/// iOS PDF tab for viewing embedded PDFs with auto-download support.
struct IOSPDFTab: View {
    let publication: CDPublication
    let libraryID: UUID
    @Binding var isFullscreen: Bool

    @Environment(LibraryManager.self) private var libraryManager

    @State private var state: PDFTabState = .loading
    @State private var showPDFBrowser = false
    @State private var downloadTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .hasPDF(let linkedFile):
                if let library = libraryManager.find(id: libraryID) {
                    PDFViewerWithControls(
                        linkedFile: linkedFile,
                        library: library,
                        publicationID: publication.id,
                        isFullscreen: $isFullscreen
                    )
                }

            case .downloading(let progress):
                downloadingView(progress: progress)

            case .downloadFailed(let message):
                downloadFailedView(message: message)

            case .noPDF:
                IOSNoPDFView(publication: publication, libraryID: libraryID)
            }
        }
        .task(id: publication.id) {
            await checkPDFState()
        }
        .onChange(of: publication.linkedFiles?.count) { _, _ in
            Task {
                await checkPDFState()
            }
        }
        .sheet(isPresented: $showPDFBrowser) {
            IOSPDFBrowserView(
                publication: publication,
                library: libraryManager.find(id: libraryID),
                onPDFSaved: {
                    Task {
                        await checkPDFState()
                    }
                }
            )
        }
    }

    // MARK: - Downloading View

    private func downloadingView(progress: Double) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(value: progress) {
                Text("Downloading PDF...")
            } currentValueLabel: {
                Text("\(Int(progress * 100))%")
            }
            .progressViewStyle(.linear)
            .frame(maxWidth: 200)

            Button("Cancel") {
                downloadTask?.cancel()
                state = .noPDF
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
    }

    // MARK: - Download Failed View

    private func downloadFailedView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text("Download Failed")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    Task {
                        await attemptAutoDownload()
                    }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showPDFBrowser = true
                } label: {
                    Label("Open in Browser", systemImage: "globe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }

    // MARK: - State Management

    private func checkPDFState() async {
        pdfLogger.info("Checking PDF state for \(publication.citeKey)")

        // Check if we already have a PDF
        if let linkedFile = publication.linkedFiles?.first(where: { $0.isPDF }) {
            pdfLogger.info("Found existing PDF: \(linkedFile.relativePath)")
            state = .hasPDF(linkedFile)
            return
        }

        // Check if we can auto-download
        if publication.arxivID != nil || publication.doi != nil || publication.bibcode != nil {
            // Try auto-download
            await attemptAutoDownload()
        } else {
            state = .noPDF
        }
    }

    private func attemptAutoDownload() async {
        pdfLogger.info("Attempting auto-download for \(publication.citeKey)")
        state = .downloading(progress: 0)

        downloadTask = Task {
            do {
                // Resolve PDF URL
                guard let pdfURL = await resolvePDFURL() else {
                    pdfLogger.warning("No PDF URL resolved")
                    state = .noPDF
                    return
                }

                pdfLogger.info("Resolved PDF URL: \(pdfURL.absoluteString)")

                // Download the PDF
                state = .downloading(progress: 0.2)
                let (data, response) = try await URLSession.shared.data(from: pdfURL)

                guard !Task.isCancelled else { return }

                state = .downloading(progress: 0.6)

                // Verify it's a PDF
                guard isPDF(data) else {
                    pdfLogger.warning("Downloaded data is not a PDF")
                    state = .downloadFailed(message: "The file is not a valid PDF. Try the browser option.")
                    return
                }

                state = .downloading(progress: 0.8)

                // Save the PDF
                try PDFManager.shared.importPDF(
                    data: data,
                    for: publication,
                    in: libraryManager.find(id: libraryID)
                )

                pdfLogger.info("PDF saved successfully")

                state = .downloading(progress: 1.0)

                // Check for the new PDF
                try? await Task.sleep(for: .milliseconds(500))
                await checkPDFState()

            } catch is CancellationError {
                pdfLogger.info("Download cancelled")
            } catch {
                pdfLogger.error("Download failed: \(error.localizedDescription)")
                state = .downloadFailed(message: error.localizedDescription)
            }
        }

        await downloadTask?.value
    }

    private func resolvePDFURL() async -> URL? {
        // Priority 1: arXiv direct PDF (always open access)
        if let arxivID = publication.arxivID {
            return URL(string: "https://arxiv.org/pdf/\(arxivID).pdf")
        }

        // Priority 2: Use publication's best remote PDF URL (handles pdfLinks with priorities)
        if let bestURL = publication.bestRemotePDFURL {
            return bestURL
        }

        // Priority 3: PDF links from publication metadata
        let pdfLinks = publication.pdfLinks
        if let firstLink = pdfLinks.first {
            return firstLink.url
        }

        return nil
    }

    private func isPDF(_ data: Data) -> Bool {
        // Check for PDF magic bytes: %PDF
        guard data.count >= 4 else { return false }
        return data.prefix(4).elementsEqual([0x25, 0x50, 0x44, 0x46])
    }
}
