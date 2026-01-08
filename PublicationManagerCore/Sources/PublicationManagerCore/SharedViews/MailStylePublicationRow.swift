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
///
/// ## Thread Safety
///
/// This view accepts `PublicationRowData` (a value type) instead of `CDPublication`
/// directly. This eliminates crashes during bulk deletion where Core Data objects
/// become invalid while SwiftUI is still rendering.
///
/// ## Performance
///
/// This view conforms to `Equatable` to prevent unnecessary re-renders when parent
/// views rebuild. SwiftUI compares only `data` and `settings` - closures are ignored
/// since they don't affect visual output.
public struct MailStylePublicationRow: View, Equatable {

    // MARK: - Equatable

    public static func == (lhs: MailStylePublicationRow, rhs: MailStylePublicationRow) -> Bool {
        // Only compare data and settings - closures don't affect visual output
        lhs.data == rhs.data && lhs.settings == rhs.settings
    }

    // MARK: - Properties

    /// Immutable snapshot of publication data for display
    public let data: PublicationRowData

    /// List view settings controlling display options
    public var settings: ListViewSettings = .default

    /// Action when toggle read/unread is requested
    public var onToggleRead: (() -> Void)?

    /// Action when a category chip is tapped
    public var onCategoryTap: ((String) -> Void)?

    // MARK: - Computed Properties

    private var isUnread: Bool { !data.isRead }

    /// Author string with year for display
    private var authorYearString: String {
        if settings.showYear, let year = data.year {
            return "\(data.authorString) · \(year)"
        }
        return data.authorString
    }

    /// Content spacing based on row density
    private var contentSpacing: CGFloat {
        settings.rowDensity.contentSpacing
    }

    /// Row padding based on row density
    private var rowPadding: CGFloat {
        settings.rowDensity.rowPadding
    }

    // MARK: - Initialization

    public init(
        data: PublicationRowData,
        settings: ListViewSettings = .default,
        onToggleRead: (() -> Void)? = nil,
        onCategoryTap: ((String) -> Void)? = nil
    ) {
        self.data = data
        self.settings = settings
        self.onToggleRead = onToggleRead
        self.onCategoryTap = onCategoryTap
    }

    // MARK: - Body

    public var body: some View {
        // No guard needed - data is an immutable value type that cannot become invalid
        rowContent
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: MailStyleTokens.dotContentSpacing) {
            // Blue dot for unread (conditional)
            if settings.showUnreadIndicator {
                Circle()
                    .fill(isUnread ? MailStyleTokens.unreadDotColor : .clear)
                    .frame(
                        width: MailStyleTokens.unreadDotSize,
                        height: MailStyleTokens.unreadDotSize
                    )
                    .padding(.top, 6)
            }

            // Content
            VStack(alignment: .leading, spacing: contentSpacing) {
                // Row 1: Authors [· Year] + [Citation Count]
                HStack {
                    Text(authorYearString)
                        .font(isUnread ? MailStyleTokens.authorFontUnread : MailStyleTokens.authorFont)
                        .lineLimit(MailStyleTokens.authorLineLimit)

                    Spacer()

                    if settings.showCitationCount && data.citationCount > 0 {
                        Text("\(data.citationCount)")
                            .font(MailStyleTokens.dateFont)
                            .foregroundStyle(MailStyleTokens.secondaryTextColor)
                    }
                }

                // Row 2: Title (conditional)
                if settings.showTitle {
                    Text(data.title)
                        .font(MailStyleTokens.titleFont)
                        .fontWeight(isUnread ? .medium : .regular)
                        .lineLimit(MailStyleTokens.titleLineLimit)
                }

                // Row 2.5: Venue (conditional)
                if settings.showVenue, let venue = data.venue, !venue.isEmpty {
                    Text(venue)
                        .font(MailStyleTokens.abstractFont)
                        .foregroundStyle(MailStyleTokens.secondaryTextColor)
                        .lineLimit(1)
                }

                // Row 2.75: Category chips disabled for performance
                // CategoryChipsRow creates multiple views per row which impacts scroll performance
                // Categories are still visible in the detail view

                // Row 3: Attachment indicator + Abstract preview (conditional)
                if (settings.showAttachmentIndicator && data.hasPDF) || settings.abstractLineLimit > 0 {
                    HStack(spacing: 4) {
                        if settings.showAttachmentIndicator && data.hasPDF {
                            Image(systemName: "paperclip")
                                .font(MailStyleTokens.attachmentFont)
                                .foregroundStyle(MailStyleTokens.tertiaryTextColor)
                        }

                        if settings.abstractLineLimit > 0, let abstract = data.abstract, !abstract.isEmpty {
                            // PERFORMANCE: Plain text with truncation - ScientificTextParser
                            // is only used in detail view where formatting matters
                            Text(String(abstract.prefix(300)))
                                .font(MailStyleTokens.abstractFont)
                                .foregroundStyle(MailStyleTokens.secondaryTextColor)
                                .lineLimit(settings.abstractLineLimit)
                        }
                    }
                }
            }
        }
        .padding(.vertical, rowPadding)
        .contentShape(Rectangle())
        .draggable(data.id) {
            // Drag preview
            Label(data.title, systemImage: "doc.text")
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

        // Standard context menu items
        Button {
            copyTitle()
        } label: {
            Label("Copy Title", systemImage: "doc.on.doc")
        }

        if let doi = data.doi {
            Button {
                copyDOI(doi)
            } label: {
                Label("Copy DOI", systemImage: "link")
            }
        }
    }

    // MARK: - Actions

    private func copyTitle() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(data.title, forType: .string)
        #else
        UIPasteboard.general.string = data.title
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
    // Create mock data for preview
    let unreadData = PublicationRowData(
        id: UUID(),
        citeKey: "Einstein1905",
        title: "On the Electrodynamics of Moving Bodies",
        authorString: "Einstein",
        year: 1905,
        abstract: "It is known that Maxwell's electrodynamics—as usually understood at the present time—when applied to moving bodies, leads to asymmetries which do not appear to be inherent in the phenomena.",
        isRead: false,
        hasPDF: true,
        citationCount: 42,
        doi: "10.1002/andp.19053221004"
    )

    let readData = PublicationRowData(
        id: UUID(),
        citeKey: "Hawking1974",
        title: "Black hole explosions?",
        authorString: "Hawking",
        year: 1974,
        abstract: "Quantum gravitational effects are usually ignored in calculations of the formation and evolution of black holes.",
        isRead: true,
        hasPDF: false,
        citationCount: 1500,
        doi: nil
    )

    return List {
        MailStylePublicationRow(data: unreadData)
        MailStylePublicationRow(data: readData)
    }
}

// MARK: - PublicationRowData Extension for Preview

extension PublicationRowData {
    /// Convenience initializer for previews and testing
    init(
        id: UUID,
        citeKey: String,
        title: String,
        authorString: String,
        year: Int?,
        abstract: String?,
        isRead: Bool,
        hasPDF: Bool,
        citationCount: Int,
        doi: String?,
        venue: String? = nil,
        dateAdded: Date = Date(),
        dateModified: Date = Date(),
        primaryCategory: String? = nil,
        categories: [String] = []
    ) {
        self.id = id
        self.citeKey = citeKey
        self.title = title
        self.authorString = authorString
        self.year = year
        self.abstract = abstract
        self.isRead = isRead
        self.hasPDF = hasPDF
        self.citationCount = citationCount
        self.doi = doi
        self.venue = venue
        self.dateAdded = dateAdded
        self.dateModified = dateModified
        self.primaryCategory = primaryCategory
        self.categories = categories
    }
}
