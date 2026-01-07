//
//  InboxCoordinator.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-06.
//

import Foundation
import OSLog

// MARK: - Inbox Coordinator

/// Coordinates Inbox services: scheduling, fetching, and management.
///
/// This is the main entry point for Inbox functionality. It creates and manages:
/// - InboxManager: Inbox library and mute management
/// - PaperFetchService: Unified fetch pipeline
/// - InboxScheduler: Automatic feed refresh
///
/// ## Usage
///
/// Start on app launch:
/// ```swift
/// Task {
///     await InboxCoordinator.shared.start()
/// }
/// ```
@MainActor
public final class InboxCoordinator {

    // MARK: - Singleton

    public static let shared = InboxCoordinator()

    // MARK: - Dependencies

    /// The inbox manager (created on first access)
    public var inboxManager: InboxManager { InboxManager.shared }

    /// The paper fetch service
    public private(set) var paperFetchService: PaperFetchService?

    /// The inbox scheduler
    public private(set) var scheduler: InboxScheduler?

    // MARK: - State

    private var isStarted = false

    // MARK: - Initialization

    private init() {}

    // MARK: - Lifecycle

    /// Start Inbox services.
    ///
    /// This should be called on app launch after other services are initialized.
    public func start() async {
        guard !isStarted else {
            Logger.library.debug("InboxCoordinator already started")
            return
        }

        Logger.library.infoCapture("Starting InboxCoordinator...", category: "inbox")

        // Initialize Inbox library if needed
        _ = inboxManager.getOrCreateInbox()
        Logger.library.debugCapture("Inbox library initialized", category: "inbox")

        // Create fetch service with shared dependencies
        let sourceManager = SourceManager(credentialManager: CredentialManager.shared)
        let repository = PublicationRepository()

        // Register built-in sources if not already done
        await sourceManager.registerBuiltInSources()

        let fetchService = PaperFetchService(
            sourceManager: sourceManager,
            repository: repository
        )
        self.paperFetchService = fetchService
        Logger.library.debugCapture("PaperFetchService created", category: "inbox")

        // Create and start scheduler
        let inboxScheduler = InboxScheduler(
            paperFetchService: fetchService
        )
        self.scheduler = inboxScheduler

        await inboxScheduler.start()
        Logger.library.infoCapture("InboxScheduler started", category: "inbox")

        isStarted = true
        Logger.library.infoCapture("InboxCoordinator started successfully", category: "inbox")
    }

    /// Stop Inbox services.
    public func stop() async {
        guard isStarted else { return }

        Logger.library.infoCapture("Stopping InboxCoordinator...", category: "inbox")

        await scheduler?.stop()
        scheduler = nil
        paperFetchService = nil

        isStarted = false
        Logger.library.infoCapture("InboxCoordinator stopped", category: "inbox")
    }

    // MARK: - Convenience Methods

    /// Trigger an immediate refresh of all due feeds.
    @discardableResult
    public func refreshAllFeeds() async -> Int {
        guard let scheduler = scheduler else {
            Logger.library.warning("InboxCoordinator: scheduler not started")
            return 0
        }
        return await scheduler.triggerImmediateCheck()
    }

    /// Send search results to the Inbox.
    @discardableResult
    public func sendToInbox(results: [SearchResult]) async -> Int {
        guard let fetchService = paperFetchService else {
            Logger.library.warning("InboxCoordinator: fetch service not started")
            return 0
        }
        return await fetchService.sendToInbox(results: results)
    }

    /// Get scheduler statistics.
    public func schedulerStatistics() async -> InboxSchedulerStatistics? {
        await scheduler?.statistics
    }
}
