//
//  IOSPDFTab.swift
//  imbib-iOS
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI
import PublicationManagerCore

/// iOS PDF tab for viewing embedded PDFs.
struct IOSPDFTab: View {
    let publication: CDPublication
    let libraryID: UUID

    @Environment(LibraryManager.self) private var libraryManager

    var body: some View {
        if let linkedFile = publication.linkedFiles?.first(where: { $0.isPDF }),
           let library = libraryManager.find(id: libraryID) {
            // Show embedded PDF viewer
            PDFViewerWithControls(
                linkedFile: linkedFile,
                library: library,
                publicationID: publication.id
            )
        } else {
            // Show download options
            IOSNoPDFView(publication: publication, libraryID: libraryID)
        }
    }
}
