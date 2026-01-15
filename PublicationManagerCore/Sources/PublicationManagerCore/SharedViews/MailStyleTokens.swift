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
///
/// Many colors can be customized via the theming system. Use the
/// theme-aware accessors when a ThemeColors is available.
public enum MailStyleTokens {

    // MARK: - Default Colors

    /// Default blue dot color for unread publications
    public static let unreadDotColor = Color.blue

    /// Secondary text color for dates, abstracts, etc.
    public static let secondaryTextColor = Color.secondary

    /// Tertiary text color for metadata like attachment icons
    #if os(macOS)
    public static let tertiaryTextColor = Color(nsColor: .tertiaryLabelColor)
    #else
    public static let tertiaryTextColor = Color(uiColor: .tertiaryLabel)
    #endif

    // MARK: - Theme-Aware Colors

    /// Get unread dot color from theme
    public static func unreadDotColor(from theme: ThemeColors) -> Color {
        theme.unreadDot
    }

    /// Get accent color from theme
    public static func accentColor(from theme: ThemeColors) -> Color {
        theme.accent
    }

    /// Get icon tint color from theme
    public static func iconTint(from theme: ThemeColors) -> Color {
        theme.iconTint
    }

    /// Get secondary text color from theme
    public static func secondaryTextColor(from theme: ThemeColors) -> Color {
        theme.secondaryText
    }

    /// Get tertiary text color from theme
    public static func tertiaryTextColor(from theme: ThemeColors) -> Color {
        theme.tertiaryText
    }

    /// Get link color from theme
    public static func linkColor(from theme: ThemeColors) -> Color {
        theme.linkColor
    }

    /// Get detail view background from theme (nil = system default)
    public static func detailBackground(from theme: ThemeColors) -> Color? {
        theme.detailBackground
    }

    /// Get row separator color from theme (nil = system default)
    public static func rowSeparator(from theme: ThemeColors) -> Color? {
        theme.rowSeparator
    }

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

    // MARK: - Date Formatting

    /// Format a date in Apple Mail style (time/yesterday/weekday/date)
    ///
    /// - Today: "10:30 AM"
    /// - Yesterday: "Yesterday"
    /// - Within past week: "Monday"
    /// - Older: "Jan 5"
    ///
    /// - Parameter date: The date to format
    /// - Returns: Formatted date string
    public static func formatRelativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        // Today: show time only
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }

        // Yesterday
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        // Within past week: show weekday name
        let daysAgo = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        if daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"  // Full weekday name
            return formatter.string(from: date)
        }

        // Older: show abbreviated date
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
