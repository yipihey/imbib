//
//  IOSDetailView.swift
//  imbib-iOS
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI
import PublicationManagerCore

/// Tab selection for iOS detail view.
enum IOSDetailTab: String, CaseIterable {
    case info
    case bibtex
    case pdf
    case notes

    var label: String {
        switch self {
        case .info: return "Info"
        case .bibtex: return "BibTeX"
        case .pdf: return "PDF"
        case .notes: return "Notes"
        }
    }

    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .bibtex: return "doc.text"
        case .pdf: return "doc.richtext"
        case .notes: return "note.text"
        }
    }
}

/// iOS detail view showing publication information with tabbed interface.
///
/// Matches macOS DetailView with 4 tabs: Info, BibTeX, PDF, Notes.
struct DetailView: View {
    let publication: CDPublication
    let libraryID: UUID
    @Binding var selectedPublication: CDPublication?

    @Environment(LibraryViewModel.self) private var libraryViewModel
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: IOSDetailTab = .info
    @State private var isPDFFullscreen: Bool = false

    init?(publication: CDPublication, libraryID: UUID, selectedPublication: Binding<CDPublication?>) {
        guard !publication.isDeleted, publication.managedObjectContext != nil else {
            return nil
        }
        self.publication = publication
        self.libraryID = libraryID
        self._selectedPublication = selectedPublication
    }

    var body: some View {
        Group {
            if isPDFFullscreen {
                // Fullscreen PDF - no tab bar, no navigation bar
                IOSPDFTab(publication: publication, libraryID: libraryID, isFullscreen: $isPDFFullscreen)
            } else {
                // Normal tabbed view
                TabView(selection: $selectedTab) {
                    IOSInfoTab(publication: publication, libraryID: libraryID)
                        .tabItem { Label(IOSDetailTab.info.label, systemImage: IOSDetailTab.info.icon) }
                        .tag(IOSDetailTab.info)

                    IOSBibTeXTab(publication: publication)
                        .tabItem { Label(IOSDetailTab.bibtex.label, systemImage: IOSDetailTab.bibtex.icon) }
                        .tag(IOSDetailTab.bibtex)

                    IOSPDFTab(publication: publication, libraryID: libraryID, isFullscreen: $isPDFFullscreen)
                        .tabItem { Label(IOSDetailTab.pdf.label, systemImage: IOSDetailTab.pdf.icon) }
                        .tag(IOSDetailTab.pdf)

                    IOSNotesTab(publication: publication)
                        .tabItem { Label(IOSDetailTab.notes.label, systemImage: IOSDetailTab.notes.icon) }
                        .tag(IOSDetailTab.notes)
                }
            }
        }
        .navigationTitle(isPDFFullscreen ? "" : (publication.title ?? "Details"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(isPDFFullscreen ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if !isPDFFullscreen {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        goBack()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    moreMenu
                }
            }
        }
    }

    // MARK: - Navigation

    private func goBack() {
        // Use dismiss to pop navigation (same as swipe gesture)
        // Also clear selection to keep state in sync
        dismiss()
        selectedPublication = nil
    }

    // MARK: - More Menu

    private var moreMenu: some View {
        Menu {
            Button {
                toggleReadStatus()
            } label: {
                Label(
                    publication.isRead ? "Mark as Unread" : "Mark as Read",
                    systemImage: publication.isRead ? "envelope.badge" : "envelope.open"
                )
            }

            Button {
                copyBibTeX()
            } label: {
                Label("Copy BibTeX", systemImage: "doc.on.doc")
            }

            Button {
                copyCiteKey()
            } label: {
                Label("Copy Cite Key", systemImage: "key")
            }

            Divider()

            if let doi = publication.doi {
                Button {
                    openURL("https://doi.org/\(doi)")
                } label: {
                    Label("Open DOI", systemImage: "arrow.up.right.square")
                }
            }

            if let arxivID = publication.arxivID {
                Button {
                    openURL("https://arxiv.org/abs/\(arxivID)")
                } label: {
                    Label("Open arXiv", systemImage: "arrow.up.right.square")
                }
            }

            if let bibcode = publication.bibcode {
                Button {
                    openURL("https://ui.adsabs.harvard.edu/abs/\(bibcode)")
                } label: {
                    Label("Open ADS", systemImage: "arrow.up.right.square")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - Actions

    private func toggleReadStatus() {
        Task {
            await libraryViewModel.toggleReadStatus(publication)
        }
    }

    private func copyBibTeX() {
        Task {
            await libraryViewModel.copyToClipboard([publication.id])
        }
    }

    private func copyCiteKey() {
        UIPasteboard.general.string = publication.citeKey
    }

    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            _ = FileManager_Opener.shared.openURL(url)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        if let view = DetailView(
            publication: CDPublication(),
            libraryID: UUID(),
            selectedPublication: .constant(nil)
        ) {
            view
                .environment(LibraryViewModel())
                .environment(LibraryManager())
        }
    }
}
