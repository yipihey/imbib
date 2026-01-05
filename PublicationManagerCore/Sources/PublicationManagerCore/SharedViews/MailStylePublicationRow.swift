//
//  MailStylePublicationRow.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-05.
//

import SwiftUI

/// A publication row styled after Apple Mail message rows
///
/// Layout:
/// ```
/// ┌─────────────────────────────────────────────────────────────┐
/// │ ● │ Einstein, A.                         Today 3:42 PM │
/// │   │ On the Electrodynamics of Moving Bodies                │
/// │   │ 📎 We consider Maxwell's equations in a moving frame...│
/// └─────────────────────────────────────────────────────────────┘
/// ```
///
/// - Row 1: Blue dot (unread) | Authors (bold) | Date (right-aligned)
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

    public var body: some View {
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
                // Row 1: Authors + Date
                HStack {
                    Text(authorString)
                        .font(isUnread ? MailStyleTokens.authorFontUnread : MailStyleTokens.authorFont)
                        .lineLimit(MailStyleTokens.authorLineLimit)

                    Spacer()

                    Text(formattedDate)
                        .font(MailStyleTokens.dateFont)
                        .foregroundStyle(MailStyleTokens.secondaryTextColor)
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

    // MARK: - Author String

    private var authorString: String {
        // First try authorString from publication (which handles CDAuthor entities)
        let fromEntities = publication.authorString
        if !fromEntities.isEmpty {
            return formatAuthorDisplay(fromEntities)
        }

        // Fall back to raw author field
        guard let rawAuthor = publication.fields["author"] else {
            return "Unknown Author"
        }

        return formatAuthorDisplay(rawAuthor)
    }

    /// Format author string for Mail-style display
    /// "LastName, F." for single author, "LastName, F. et al." for multiple
    private func formatAuthorDisplay(_ authorString: String) -> String {
        let authors = authorString.components(separatedBy: " and ")

        guard let firstAuthor = authors.first else {
            return "Unknown Author"
        }

        // Parse first author name
        let lastName = extractLastName(from: firstAuthor)
        let initial = extractInitial(from: firstAuthor)

        let displayName: String
        if let initial = initial {
            displayName = "\(lastName), \(initial)."
        } else {
            displayName = lastName
        }

        if authors.count > 1 {
            return "\(displayName) et al."
        } else {
            return displayName
        }
    }

    private func extractLastName(from author: String) -> String {
        let trimmed = author.trimmingCharacters(in: .whitespaces)

        if trimmed.contains(",") {
            // "Last, First" format
            return trimmed.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? trimmed
        } else {
            // "First Last" format
            return trimmed.components(separatedBy: " ").last ?? trimmed
        }
    }

    private func extractInitial(from author: String) -> Character? {
        let trimmed = author.trimmingCharacters(in: .whitespaces)

        if trimmed.contains(",") {
            // "Last, First" format
            let parts = trimmed.components(separatedBy: ",")
            if parts.count > 1 {
                let firstName = parts[1].trimmingCharacters(in: .whitespaces)
                return firstName.first
            }
        } else {
            // "First Last" format
            return trimmed.first
        }
        return nil
    }

    // MARK: - Date Formatting

    private var formattedDate: String {
        let date = publication.dateAdded

        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            // Today: show time only
            return date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day,
                  daysAgo < 7 {
            // Within last week: show weekday
            return date.formatted(.dateTime.weekday(.wide))
        } else {
            // Older: show abbreviated date
            return date.formatted(date: .abbreviated, time: .omitted)
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
