//
//  MailStylePublicationRow.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-05.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - UUID Transferable Extension

extension UTType {
    /// UTType for dragging publication UUIDs between views
    public static let publicationID = UTType(exportedAs: "com.imbib.publication-id")
}

extension UUID: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .publicationID)
    }
}

/// A publication row styled after Apple Mail message rows
///
/// Layout:
/// ```
/// ┌─────────────────────────────────────────────────────────────┐
/// │ ● │ Einstein, A. · 1905                              42 │
/// │   │ On the Electrodynamics of Moving Bodies                │
/// │   │ 📎 We consider Maxwell's equations in a moving frame...│
/// └─────────────────────────────────────────────────────────────┘
/// ```
///
/// - Row 1: Blue dot (unread) | Authors (bold) · Year | Citation count (right-aligned)
/// - Row 2: Title
/// - Row 3: Paperclip icon (if PDF) | Abstract preview (2 lines max)
public struct MailStylePublicationRow: View {

    // MARK: - Properties

    @ObservedObject public var publication: CDPublication

    /// Whether to show the unread indicator dot
    public var showUnreadIndicator: Bool = true

    /// Action when toggle read/unread is requested
    public var onToggleRead: (() -> Void)?

    // MARK: - Computed Properties

    private var isUnread: Bool { !publication.isRead }

    // MARK: - Initialization

    public init(
        publication: CDPublication,
        showUnreadIndicator: Bool = true,
        onToggleRead: (() -> Void)? = nil
    ) {
        self.publication = publication
        self.showUnreadIndicator = showUnreadIndicator
        self.onToggleRead = onToggleRead
    }

    // MARK: - Body

    @ViewBuilder
    public var body: some View {
        // Guard against deleted Core Data objects during List re-render after bulk deletion
        if publication.managedObjectContext == nil {
            EmptyView()
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: MailStyleTokens.dotContentSpacing) {
            // Blue dot for unread
            if showUnreadIndicator {
                Circle()
                    .fill(isUnread ? MailStyleTokens.unreadDotColor : .clear)
                    .frame(
                        width: MailStyleTokens.unreadDotSize,
                        height: MailStyleTokens.unreadDotSize
                    )
                    .padding(.top, 6)
            }

            // Content
            VStack(alignment: .leading, spacing: MailStyleTokens.contentSpacing) {
                // Row 1: Authors · Year + Citation Count
                HStack {
                    Text(authorYearString)
                        .font(isUnread ? MailStyleTokens.authorFontUnread : MailStyleTokens.authorFont)
                        .lineLimit(MailStyleTokens.authorLineLimit)

                    Spacer()

                    if publication.citationCount > 0 {
                        Text("\(publication.citationCount)")
                            .font(MailStyleTokens.dateFont)
                            .foregroundStyle(MailStyleTokens.secondaryTextColor)
                    }
                }

                // Row 2: Title
                Text(publication.title ?? "Untitled")
                    .font(MailStyleTokens.titleFont)
                    .fontWeight(isUnread ? .medium : .regular)
                    .lineLimit(MailStyleTokens.titleLineLimit)

                // Row 3: Attachment indicator + Abstract preview
                HStack(spacing: 4) {
                    if hasPDF {
                        Image(systemName: "paperclip")
                            .font(MailStyleTokens.attachmentFont)
                            .foregroundStyle(MailStyleTokens.tertiaryTextColor)
                    }

                    if let abstract = publication.abstract, !abstract.isEmpty {
                        Text(abstract)
                            .font(MailStyleTokens.abstractFont)
                            .foregroundStyle(MailStyleTokens.secondaryTextColor)
                            .lineLimit(MailStyleTokens.abstractLineLimit)
                    }
                }
            }
        }
        .padding(.vertical, MailStyleTokens.rowVerticalPadding)
        .contentShape(Rectangle())
        .draggable(publication.id) {
            // Drag preview
            Label(publication.title ?? "Publication", systemImage: "doc.text")
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .contextMenu {
            contextMenuContent
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        if let onToggleRead = onToggleRead {
            Button {
                onToggleRead()
            } label: {
                Label(
                    isUnread ? "Mark as Read" : "Mark as Unread",
                    systemImage: isUnread ? "envelope.open" : "envelope.badge"
                )
            }

            Divider()
        }

        // Standard context menu items can be added here
        Button {
            copyTitle()
        } label: {
            Label("Copy Title", systemImage: "doc.on.doc")
        }

        if let doi = publication.doi {
            Button {
                copyDOI(doi)
            } label: {
                Label("Copy DOI", systemImage: "link")
            }
        }
    }

    // MARK: - Author & Year String

    private var authorYearString: String {
        let authors = authorString

        // Try Int16 year first, then fallback to fields["year"]
        var yearValue: Int = Int(publication.year)
        if yearValue == 0, let yearStr = publication.fields["year"], let parsed = Int(yearStr) {
            yearValue = parsed
        }

        if yearValue > 0 {
            return "\(authors) · \(yearValue)"
        }
        return authors
    }

    private var authorString: String {
        // Get authors from CDAuthor entities if available
        let sortedAuthors = publication.sortedAuthors
        if !sortedAuthors.isEmpty {
            // Clean braces from display names (ADS-style escaping)
            return formatAuthorList(sortedAuthors.map { BibTeXFieldCleaner.cleanAuthorName($0.displayName) })
        }

        // Fall back to raw author field (BibTeX format with " and ")
        guard let rawAuthor = publication.fields["author"] else {
            return "Unknown Author"
        }

        let authors = rawAuthor.components(separatedBy: " and ")
            .map { BibTeXFieldCleaner.cleanAuthorName($0) }
            .filter { !$0.isEmpty }

        return formatAuthorList(authors)
    }

    /// Format author list for Mail-style display
    /// - 1 author: "LastName"
    /// - 2 authors: "LastName1, LastName2"
    /// - 3 authors: "LastName1, LastName2, LastName3"
    /// - 4+ authors: "LastName1, LastName2 ... LastNameN"
    private func formatAuthorList(_ authors: [String]) -> String {
        guard !authors.isEmpty else {
            return "Unknown Author"
        }

        let lastNames = authors.map { extractLastName(from: $0) }

        switch lastNames.count {
        case 1:
            return lastNames[0]
        case 2:
            return "\(lastNames[0]), \(lastNames[1])"
        case 3:
            return "\(lastNames[0]), \(lastNames[1]), \(lastNames[2])"
        default:
            // 4+ authors: first two ... last
            return "\(lastNames[0]), \(lastNames[1]) ... \(lastNames[lastNames.count - 1])"
        }
    }

    private func extractLastName(from author: String) -> String {
        let trimmed = author.trimmingCharacters(in: .whitespaces)

        if trimmed.contains(",") {
            // "Last, First" format
            return trimmed.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? trimmed
        } else {
            // "First Last" format - get the last word
            let parts = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
            return parts.last ?? trimmed
        }
    }

    // MARK: - PDF Check

    private var hasPDF: Bool {
        // Check for local linked files
        if let linkedFiles = publication.linkedFiles, !linkedFiles.isEmpty {
            return linkedFiles.contains { $0.isPDF }
        }
        // Check for remote PDF links
        return !publication.pdfLinks.isEmpty
    }

    // MARK: - Actions

    private func copyTitle() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(publication.title ?? "", forType: .string)
        #else
        UIPasteboard.general.string = publication.title ?? ""
        #endif
    }

    private func copyDOI(_ doi: String) {
        let doiURL = doi.hasPrefix("http") ? doi : "https://doi.org/\(doi)"
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(doiURL, forType: .string)
        #else
        UIPasteboard.general.string = doiURL
        #endif
    }
}

// MARK: - Preview

#Preview {
    let context = PersistenceController.preview.viewContext
    let publication = context.performAndWait {
        let pub = CDPublication(context: context)
        pub.id = UUID()
        pub.citeKey = "Einstein1905"
        pub.entryType = "article"
        pub.title = "On the Electrodynamics of Moving Bodies"
        pub.year = 1905
        pub.abstract = "It is known that Maxwell's electrodynamics—as usually understood at the present time—when applied to moving bodies, leads to asymmetries which do not appear to be inherent in the phenomena."
        pub.dateAdded = Date()
        pub.dateModified = Date()
        pub.isRead = false
        pub.fields = ["author": "Einstein, Albert"]
        return pub
    }

    let readPublication = context.performAndWait {
        let pub = CDPublication(context: context)
        pub.id = UUID()
        pub.citeKey = "Hawking1974"
        pub.entryType = "article"
        pub.title = "Black hole explosions?"
        pub.year = 1974
        pub.abstract = "Quantum gravitational effects are usually ignored in calculations of the formation and evolution of black holes."
        pub.dateAdded = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        pub.dateModified = Date()
        pub.isRead = true
        pub.fields = ["author": "Hawking, Stephen W."]
        return pub
    }

    return List {
        MailStylePublicationRow(publication: publication)
        MailStylePublicationRow(publication: readPublication)
    }
}
