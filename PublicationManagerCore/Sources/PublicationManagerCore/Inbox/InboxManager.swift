//
//  InboxManager.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-06.
//

import Foundation
import CoreData
import OSLog

// MARK: - Inbox Manager

/// Manages the special Inbox library for paper discovery and curation.
///
/// The Inbox is a single global library that receives papers from smart searches
/// and ad-hoc searches. Papers are automatically removed from the Inbox when
/// archived to other libraries.
///
/// Features:
/// - Single global Inbox library (created on first access)
/// - Mute list management (authors, papers, venues, categories)
/// - Unread count tracking
/// - Auto-remove on archive
@MainActor
@Observable
public final class InboxManager {

    // MARK: - Singleton

    public static let shared = InboxManager()

    // MARK: - Published State

    /// The Inbox library (lazily created on first access)
    public private(set) var inboxLibrary: CDLibrary?

    /// Number of unread papers in the Inbox
    public private(set) var unreadCount: Int = 0

    /// All muted items
    public private(set) var mutedItems: [CDMutedItem] = []

    // MARK: - Dependencies

    private let persistenceController: PersistenceController

    // MARK: - Initialization

    public init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
        loadInbox()
        loadMutedItems()
        setupObservers()
    }

    // MARK: - Inbox Library

    /// Get or create the Inbox library
    @discardableResult
    public func getOrCreateInbox() -> CDLibrary {
        if let inbox = inboxLibrary {
            return inbox
        }

        // Try to find existing inbox
        let request = NSFetchRequest<CDLibrary>(entityName: "Library")
        request.predicate = NSPredicate(format: "isInbox == YES")
        request.fetchLimit = 1

        do {
            if let existing = try persistenceController.viewContext.fetch(request).first {
                Logger.library.infoCapture("Found existing Inbox library", category: "inbox")
                inboxLibrary = existing
                updateUnreadCount()
                return existing
            }
        } catch {
            Logger.library.errorCapture("Failed to fetch Inbox: \(error.localizedDescription)", category: "inbox")
        }

        // Create new Inbox
        Logger.library.infoCapture("Creating Inbox library", category: "inbox")

        let context = persistenceController.viewContext
        let inbox = CDLibrary(context: context)
        inbox.id = UUID()
        inbox.name = "Inbox"
        inbox.isInbox = true
        inbox.isDefault = false
        inbox.dateCreated = Date()
        inbox.sortOrder = -1  // Always at top

        persistenceController.save()
        inboxLibrary = inbox

        Logger.library.infoCapture("Created Inbox library with ID: \(inbox.id)", category: "inbox")
        return inbox
    }

    /// Load the Inbox library from Core Data
    private func loadInbox() {
        let request = NSFetchRequest<CDLibrary>(entityName: "Library")
        request.predicate = NSPredicate(format: "isInbox == YES")
        request.fetchLimit = 1

        do {
            inboxLibrary = try persistenceController.viewContext.fetch(request).first
            if inboxLibrary != nil {
                Logger.library.debugCapture("Loaded Inbox library", category: "inbox")
                updateUnreadCount()
            }
        } catch {
            Logger.library.errorCapture("Failed to load Inbox: \(error.localizedDescription)", category: "inbox")
        }
    }

    // MARK: - Unread Count

    /// Update the unread count
    public func updateUnreadCount() {
        guard let inbox = inboxLibrary else {
            if unreadCount != 0 {
                unreadCount = 0
                postUnreadCountChanged()
            }
            return
        }

        // Count unread papers in Inbox
        let request = NSFetchRequest<CDPublication>(entityName: "Publication")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "ANY libraries == %@", inbox),
            NSPredicate(format: "isRead == NO")
        ])

        do {
            let newCount = try persistenceController.viewContext.count(for: request)
            if newCount != unreadCount {
                unreadCount = newCount
                postUnreadCountChanged()
            }
            Logger.library.debugCapture("Inbox unread count: \(unreadCount)", category: "inbox")
        } catch {
            Logger.library.errorCapture("Failed to count unread: \(error.localizedDescription)", category: "inbox")
            if unreadCount != 0 {
                unreadCount = 0
                postUnreadCountChanged()
            }
        }
    }

    /// Post notification when unread count changes
    private func postUnreadCountChanged() {
        NotificationCenter.default.post(
            name: .inboxUnreadCountChanged,
            object: nil,
            userInfo: ["count": unreadCount]
        )
    }

    /// Mark a paper as read in the Inbox
    public func markAsRead(_ publication: CDPublication) {
        publication.isRead = true
        persistenceController.save()
        updateUnreadCount()
    }

    /// Mark all papers in Inbox as read
    public func markAllAsRead() {
        guard let inbox = inboxLibrary else { return }

        Logger.library.infoCapture("Marking all Inbox papers as read", category: "inbox")

        let request = NSFetchRequest<CDPublication>(entityName: "Publication")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "ANY libraries == %@", inbox),
            NSPredicate(format: "isRead == NO")
        ])

        do {
            let unread = try persistenceController.viewContext.fetch(request)
            for pub in unread {
                pub.isRead = true
            }
            persistenceController.save()
            unreadCount = 0
        } catch {
            Logger.library.errorCapture("Failed to mark all as read: \(error.localizedDescription)", category: "inbox")
        }
    }

    // MARK: - Auto-Remove on Archive

    /// Set up observers for auto-remove behavior
    private func setupObservers() {
        // Listen for publications being added to libraries
        NotificationCenter.default.addObserver(
            forName: .publicationArchivedToLibrary,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let publication = notification.object as? CDPublication else { return }

            Task { @MainActor in
                self.handleArchive(publication)
            }
        }
    }

    /// Handle when a paper is archived to another library
    private func handleArchive(_ publication: CDPublication) {
        guard let inbox = inboxLibrary else { return }

        // Check if paper is in Inbox
        guard let libraries = publication.libraries, libraries.contains(inbox) else {
            return
        }

        // Check if paper is now in any non-Inbox library
        let otherLibraries = libraries.filter { !$0.isInbox }
        if !otherLibraries.isEmpty {
            // Remove from Inbox
            Logger.library.infoCapture("Auto-removing paper from Inbox: \(publication.citeKey)", category: "inbox")
            publication.removeFromLibrary(inbox)
            persistenceController.save()
            updateUnreadCount()
        }
    }

    // MARK: - Mute Management

    /// Load all muted items from Core Data
    private func loadMutedItems() {
        let request = NSFetchRequest<CDMutedItem>(entityName: "MutedItem")
        request.sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: false)]

        do {
            mutedItems = try persistenceController.viewContext.fetch(request)
            Logger.library.debugCapture("Loaded \(mutedItems.count) muted items", category: "inbox")
        } catch {
            Logger.library.errorCapture("Failed to load muted items: \(error.localizedDescription)", category: "inbox")
            mutedItems = []
        }
    }

    /// Mute an item (author, paper, venue, category)
    @discardableResult
    public func mute(type: CDMutedItem.MuteType, value: String) -> CDMutedItem {
        Logger.library.infoCapture("Muting \(type.rawValue): \(value)", category: "inbox")

        let context = persistenceController.viewContext

        // Check if already muted
        if let existing = mutedItems.first(where: { $0.type == type.rawValue && $0.value == value }) {
            return existing
        }

        let item = CDMutedItem(context: context)
        item.id = UUID()
        item.type = type.rawValue
        item.value = value
        item.dateAdded = Date()

        persistenceController.save()
        mutedItems.insert(item, at: 0)

        return item
    }

    /// Unmute an item
    public func unmute(_ item: CDMutedItem) {
        Logger.library.infoCapture("Unmuting \(item.type): \(item.value)", category: "inbox")

        persistenceController.viewContext.delete(item)
        persistenceController.save()
        mutedItems.removeAll { $0.id == item.id }
    }

    /// Check if a paper should be filtered out based on mute rules
    public func shouldFilter(paper: PaperRepresentable) -> Bool {
        shouldFilter(
            id: paper.id,
            authors: paper.authors,
            doi: paper.doi,
            venue: paper.venue,
            arxivID: paper.arxivID
        )
    }

    /// Check if a search result should be filtered out based on mute rules
    public func shouldFilter(result: SearchResult) -> Bool {
        shouldFilter(
            id: result.id,
            authors: result.authors,
            doi: result.doi,
            venue: result.venue,
            arxivID: result.arxivID
        )
    }

    /// Core mute check with explicit parameters
    public func shouldFilter(
        id: String,
        authors: [String],
        doi: String?,
        venue: String?,
        arxivID: String?
    ) -> Bool {
        for item in mutedItems {
            guard let muteType = item.muteType else { continue }

            switch muteType {
            case .author:
                // Check if any author matches
                if authors.contains(where: { $0.lowercased().contains(item.value.lowercased()) }) {
                    return true
                }

            case .doi:
                if doi?.lowercased() == item.value.lowercased() {
                    return true
                }

            case .bibcode:
                if id.lowercased() == item.value.lowercased() {
                    return true
                }

            case .venue:
                if let venue = venue?.lowercased(), venue.contains(item.value.lowercased()) {
                    return true
                }

            case .arxivCategory:
                if let arxiv = arxivID, arxiv.lowercased().hasPrefix(item.value.lowercased()) {
                    return true
                }
            }
        }

        return false
    }

    /// Get muted items by type
    public func mutedItems(ofType type: CDMutedItem.MuteType) -> [CDMutedItem] {
        mutedItems.filter { $0.type == type.rawValue }
    }

    /// Clear all muted items
    public func clearAllMutedItems() {
        Logger.library.warningCapture("Clearing all \(mutedItems.count) muted items", category: "inbox")

        for item in mutedItems {
            persistenceController.viewContext.delete(item)
        }

        persistenceController.save()
        mutedItems = []
    }

    // MARK: - Paper Operations

    /// Add a paper to the Inbox
    public func addToInbox(_ publication: CDPublication) {
        let inbox = getOrCreateInbox()

        guard !(publication.libraries?.contains(inbox) ?? false) else {
            Logger.library.debugCapture("Paper already in Inbox: \(publication.citeKey)", category: "inbox")
            return
        }

        Logger.library.infoCapture("Adding paper to Inbox: \(publication.citeKey)", category: "inbox")
        publication.addToLibrary(inbox)
        publication.isRead = false  // Mark as unread in Inbox
        persistenceController.save()
        updateUnreadCount()
    }

    /// Remove a paper from the Inbox (dismiss)
    public func dismissFromInbox(_ publication: CDPublication) {
        guard let inbox = inboxLibrary else { return }

        Logger.library.infoCapture("Dismissing paper from Inbox: \(publication.citeKey)", category: "inbox")
        publication.removeFromLibrary(inbox)

        // If paper is not in any other library, delete it
        if publication.libraries?.isEmpty ?? true {
            persistenceController.viewContext.delete(publication)
        }

        persistenceController.save()
        updateUnreadCount()
    }

    /// Archive a paper from Inbox to a target library
    public func archiveToLibrary(_ publication: CDPublication, library: CDLibrary) {
        Logger.library.infoCapture("Archiving paper '\(publication.citeKey)' to library '\(library.displayName)'", category: "inbox")

        // Add to target library
        publication.addToLibrary(library)
        persistenceController.save()

        // Post notification for auto-remove
        NotificationCenter.default.post(name: .publicationArchivedToLibrary, object: publication)
    }

    /// Get all papers in the Inbox
    public func getInboxPapers() -> [CDPublication] {
        guard let inbox = inboxLibrary else { return [] }

        let request = NSFetchRequest<CDPublication>(entityName: "Publication")
        request.predicate = NSPredicate(format: "ANY libraries == %@", inbox)
        request.sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: false)]

        do {
            return try persistenceController.viewContext.fetch(request)
        } catch {
            Logger.library.errorCapture("Failed to fetch Inbox papers: \(error.localizedDescription)", category: "inbox")
            return []
        }
    }
}

// MARK: - Notifications

public extension Notification.Name {
    /// Posted when a publication is archived from Inbox to another library
    static let publicationArchivedToLibrary = Notification.Name("publicationArchivedToLibrary")

    /// Posted when Inbox unread count changes
    static let inboxUnreadCountChanged = Notification.Name("inboxUnreadCountChanged")
}
