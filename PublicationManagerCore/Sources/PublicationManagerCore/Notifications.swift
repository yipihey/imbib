//
//  Notifications.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-07.
//

import Foundation

// MARK: - App Notification Names

/// Centralized notification names used by both macOS and iOS apps.
///
/// These notifications are used for app-level actions that need to be
/// triggered from menus, keyboard shortcuts, or other UI elements.
public extension Notification.Name {

    // MARK: - File Operations

    /// Import BibTeX file
    static let importBibTeX = Notification.Name("importBibTeX")

    /// Export library to BibTeX
    static let exportBibTeX = Notification.Name("exportBibTeX")

    // MARK: - Navigation

    /// Show library view
    static let showLibrary = Notification.Name("showLibrary")

    /// Show search view
    static let showSearch = Notification.Name("showSearch")

    // MARK: - Publication Actions

    /// Toggle read/unread status of selected publications
    static let toggleReadStatus = Notification.Name("toggleReadStatus")

    /// Read status changed (for UI updates)
    static let readStatusDidChange = Notification.Name("readStatusDidChange")

    // MARK: - Clipboard Operations

    /// Copy selected publications to clipboard
    static let copyPublications = Notification.Name("copyPublications")

    /// Cut selected publications to clipboard
    static let cutPublications = Notification.Name("cutPublications")

    /// Paste publications from clipboard
    static let pastePublications = Notification.Name("pastePublications")

    /// Select all publications in current view
    static let selectAllPublications = Notification.Name("selectAllPublications")

    // MARK: - Inbox Triage Actions

    /// Archive selected inbox items to default library (A key)
    static let inboxArchive = Notification.Name("inboxArchive")

    /// Dismiss selected inbox items (D key)
    static let inboxDismiss = Notification.Name("inboxDismiss")

    /// Toggle star/flag on selected inbox items (S key)
    static let inboxToggleStar = Notification.Name("inboxToggleStar")

    // MARK: - Category Search

    /// Search for papers in a specific arXiv category (userInfo["category"] = String)
    static let searchCategory = Notification.Name("searchCategory")
}
