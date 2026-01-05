//
//  MailStyleTokens.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-05.
//

import SwiftUI

/// Design tokens for Apple Mail-style publication rows
///
/// These constants define the visual appearance of publication list rows,
/// following Apple Mail's design language with:
/// - Blue dot for unread items
/// - Bold author names (like sender names)
/// - Title as subject line
/// - Abstract preview as message preview
public enum MailStyleTokens {

    // MARK: - Colors

    /// Blue dot color for unread publications
    public static let unreadDotColor = Color.blue

    /// Secondary text color for dates, abstracts, etc.
    public static let secondaryTextColor = Color.secondary

    /// Tertiary text color for metadata like attachment icons
    #if os(macOS)
    public static let tertiaryTextColor = Color(nsColor: .tertiaryLabelColor)
    #else
    public static let tertiaryTextColor = Color(uiColor: .tertiaryLabel)
    #endif

    // MARK: - Spacing

    /// Vertical padding for each row
    public static let rowVerticalPadding: CGFloat = 8

    /// Horizontal padding for row content
    public static let rowHorizontalPadding: CGFloat = 12

    /// Size of the unread indicator dot
    public static let unreadDotSize: CGFloat = 10

    /// Spacing between content lines
    public static let contentSpacing: CGFloat = 2

    /// Spacing between dot and content
    public static let dotContentSpacing: CGFloat = 8

    // MARK: - Fonts

    /// Font for authors when read
    public static let authorFont = Font.system(.body, weight: .semibold)

    /// Font for authors when unread (bolder)
    public static let authorFontUnread = Font.system(.body, weight: .bold)

    /// Font for title
    public static let titleFont = Font.system(.body)

    /// Font for abstract preview
    public static let abstractFont = Font.system(.subheadline)

    /// Font for date
    public static let dateFont = Font.system(.caption)

    /// Font for attachment indicator
    public static let attachmentFont = Font.system(.caption)

    // MARK: - Line Limits

    /// Maximum lines for title
    public static let titleLineLimit = 1

    /// Maximum lines for abstract preview
    public static let abstractLineLimit = 2

    /// Maximum lines for authors
    public static let authorLineLimit = 1
}
