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

    // MARK: - Keyboard Navigation

    /// Navigate to next paper in list (↓ key)
    static let navigateNextPaper = Notification.Name("navigateNextPaper")

    /// Navigate to previous paper in list (↑ key)
    static let navigatePreviousPaper = Notification.Name("navigatePreviousPaper")

    /// Navigate to first paper in list (⌘↑)
    static let navigateFirstPaper = Notification.Name("navigateFirstPaper")

    /// Navigate to last paper in list (⌘↓)
    static let navigateLastPaper = Notification.Name("navigateLastPaper")

    /// Navigate to next unread paper (⌥↓)
    static let navigateNextUnread = Notification.Name("navigateNextUnread")

    /// Navigate to previous unread paper (⌥↑)
    static let navigatePreviousUnread = Notification.Name("navigatePreviousUnread")

    /// Open selected paper / show detail (Return key)
    static let openSelectedPaper = Notification.Name("openSelectedPaper")

    // MARK: - View Switching

    /// Show inbox view (⌘3)
    static let showInbox = Notification.Name("showInbox")

    /// Show PDF tab in detail view (⌘4)
    static let showPDFTab = Notification.Name("showPDFTab")

    /// Show BibTeX tab in detail view (⌘5)
    static let showBibTeXTab = Notification.Name("showBibTeXTab")

    /// Show Notes tab in detail view (⌘6 or ⌘R)
    static let showNotesTab = Notification.Name("showNotesTab")

    /// Toggle detail pane visibility (⌘0)
    static let toggleDetailPane = Notification.Name("toggleDetailPane")

    /// Toggle sidebar visibility (⌃⌘S)
    static let toggleSidebar = Notification.Name("toggleSidebar")

    /// Focus sidebar (⌥⌘1)
    static let focusSidebar = Notification.Name("focusSidebar")

    /// Focus list view (⌥⌘2)
    static let focusList = Notification.Name("focusList")

    /// Focus detail view (⌥⌘3)
    static let focusDetail = Notification.Name("focusDetail")

    // MARK: - Paper Actions

    /// Open references/citations for selected paper (⇧⌘R)
    static let openReferences = Notification.Name("openReferences")

    /// Mark all visible papers as read (⌥⌘U)
    static let markAllAsRead = Notification.Name("markAllAsRead")

    /// Delete selected papers (⌘Delete)
    static let deleteSelectedPapers = Notification.Name("deleteSelectedPapers")

    /// Archive selected papers to library (⌃⌘A)
    static let archiveToLibrary = Notification.Name("archiveToLibrary")

    /// Dismiss selected papers from inbox (⇧⌘J)
    static let dismissFromInbox = Notification.Name("dismissFromInbox")

    /// Move selected papers to collection (⌃⌘M)
    static let moveToCollection = Notification.Name("moveToCollection")

    /// Add selected papers to collection (⌘L)
    static let addToCollection = Notification.Name("addToCollection")

    /// Remove selected papers from current collection (⇧⌘L)
    static let removeFromCollection = Notification.Name("removeFromCollection")

    /// Share selected papers (⇧⌘F)
    static let sharePapers = Notification.Name("sharePapers")

    // MARK: - Search Actions

    /// Focus search field (⌘F)
    static let focusSearch = Notification.Name("focusSearch")

    /// Toggle unread filter (⌘\\)
    static let toggleUnreadFilter = Notification.Name("toggleUnreadFilter")

    /// Toggle PDF filter - papers with attachments (⇧⌘\\)
    static let togglePDFFilter = Notification.Name("togglePDFFilter")

    // MARK: - Clipboard Extensions

    /// Copy as formatted citation (⇧⌘C)
    static let copyAsCitation = Notification.Name("copyAsCitation")

    /// Copy DOI or URL (⌥⌘C)
    static let copyIdentifier = Notification.Name("copyIdentifier")

    // MARK: - PDF Viewer

    /// Go to specific page in PDF (⌘G)
    static let pdfGoToPage = Notification.Name("pdfGoToPage")

    /// PDF page down (Space)
    static let pdfPageDown = Notification.Name("pdfPageDown")

    /// PDF page up (Shift+Space)
    static let pdfPageUp = Notification.Name("pdfPageUp")

    /// PDF zoom in (⌘+)
    static let pdfZoomIn = Notification.Name("pdfZoomIn")

    /// PDF zoom out (⌘-)
    static let pdfZoomOut = Notification.Name("pdfZoomOut")

    /// PDF actual size (⌘0 in PDF context)
    static let pdfActualSize = Notification.Name("pdfActualSize")

    /// PDF fit to window (⌘9)
    static let pdfFitToWindow = Notification.Name("pdfFitToWindow")

    // MARK: - App Actions

    /// Refresh/sync data (⇧⌘N)
    static let refreshData = Notification.Name("refreshData")

    /// Show keyboard shortcuts window (⌘/)
    static let showKeyboardShortcuts = Notification.Name("showKeyboardShortcuts")

    // MARK: - Exploration Navigation

    /// Navigate to a collection in the sidebar (userInfo["collection"] = CDCollection)
    static let navigateToCollection = Notification.Name("navigateToCollection")

    /// Exploration library changed (collection added/removed)
    static let explorationLibraryDidChange = Notification.Name("explorationLibraryDidChange")

    /// Navigate back in history (⌘[)
    static let navigateBack = Notification.Name("navigateBack")

    /// Navigate forward in history (⌘])
    static let navigateForward = Notification.Name("navigateForward")

    /// Navigate to a smart search in the sidebar (object = UUID of smart search)
    static let navigateToSmartSearch = Notification.Name("navigateToSmartSearch")

    // MARK: - Search Form Navigation

    /// Reset search form view to show input form instead of results
    /// Posted when user clicks a search form in sidebar (even if already selected)
    static let resetSearchFormView = Notification.Name("resetSearchFormView")

    /// Navigate to Search section (object = optional library UUID to create search for)
    static let navigateToSearchSection = Notification.Name("navigateToSearchSection")

    /// Edit a smart search by navigating to Search section with its query
    /// Object = UUID of the smart search to edit
    static let editSmartSearch = Notification.Name("editSmartSearch")

    // MARK: - Inbox Triage Extensions

    /// Mark inbox item as read (R key - single key when in inbox)
    static let inboxMarkRead = Notification.Name("inboxMarkRead")

    /// Mark inbox item as unread (U key - single key when in inbox)
    static let inboxMarkUnread = Notification.Name("inboxMarkUnread")

    /// Navigate next (J key - vim style)
    static let inboxNextItem = Notification.Name("inboxNextItem")

    /// Navigate previous (K key - vim style)
    static let inboxPreviousItem = Notification.Name("inboxPreviousItem")

    /// Open inbox item (O key - vim style)
    static let inboxOpenItem = Notification.Name("inboxOpenItem")
}
