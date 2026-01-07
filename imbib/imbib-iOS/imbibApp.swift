//
//  imbibApp.swift
//  imbib-iOS
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI
import PublicationManagerCore
import OSLog
import UserNotifications

private let appLogger = Logger(subsystem: "com.imbib.app", category: "app")

@main
struct imbibApp: App {

    // MARK: - State

    @State private var libraryManager: LibraryManager
    @State private var libraryViewModel: LibraryViewModel
    @State private var searchViewModel: SearchViewModel
    @State private var settingsViewModel: SettingsViewModel

    // MARK: - Initialization

    init() {
        appLogger.info("imbib iOS app initializing...")

        // Use shared credential manager singleton for persistence
        let credentialManager = CredentialManager.shared
        let sourceManager = SourceManager(credentialManager: credentialManager)
        let repository = PublicationRepository()
        let deduplicationService = DeduplicationService()

        appLogger.info("Created shared dependencies")

        // Initialize LibraryManager first
        _libraryManager = State(initialValue: LibraryManager())

        appLogger.info("LibraryManager initialized")

        // Initialize ViewModels
        _libraryViewModel = State(initialValue: LibraryViewModel(repository: repository))
        _searchViewModel = State(initialValue: SearchViewModel(
            sourceManager: sourceManager,
            deduplicationService: deduplicationService,
            repository: repository
        ))
        _settingsViewModel = State(initialValue: SettingsViewModel(
            sourceManager: sourceManager,
            credentialManager: credentialManager
        ))

        appLogger.info("ViewModels initialized")

        // Register built-in sources and start enrichment
        Task {
            await sourceManager.registerBuiltInSources()
            appLogger.info("Built-in sources registered")

            // Register browser URL providers for interactive PDF downloads
            await BrowserURLProviderRegistry.shared.register(ADSSource.self, priority: 10)
            appLogger.info("BrowserURLProviders registered")

            // Start background enrichment coordinator
            await EnrichmentCoordinator.shared.start()
            appLogger.info("EnrichmentCoordinator started")

            // Start Inbox coordinator (scheduling, fetch service)
            await InboxCoordinator.shared.start()
            appLogger.info("InboxCoordinator started")
        }

        // Request notification permissions for badge
        requestNotificationPermissions()

        appLogger.info("imbib iOS app initialization complete")
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            IOSContentView()
                .environment(libraryManager)
                .environment(libraryViewModel)
                .environment(searchViewModel)
                .environment(settingsViewModel)
                .onAppear {
                    setupBadgeObserver()
                }
        }
    }

    // MARK: - Badge Management

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge]) { granted, error in
            if granted {
                appLogger.info("Badge notification permission granted")
            } else if let error = error {
                appLogger.error("Badge permission error: \(error.localizedDescription)")
            }
        }
    }

    private func setupBadgeObserver() {
        // Set initial badge
        updateAppBadge(InboxManager.shared.unreadCount)

        // Observe unread count changes
        NotificationCenter.default.addObserver(
            forName: .inboxUnreadCountChanged,
            object: nil,
            queue: .main
        ) { notification in
            if let count = notification.userInfo?["count"] as? Int {
                updateAppBadge(count)
            }
        }
    }
}

/// Update the app icon badge with unread count
private func updateAppBadge(_ count: Int) {
    UNUserNotificationCenter.current().setBadgeCount(count) { error in
        if let error = error {
            appLogger.error("Failed to set badge: \(error.localizedDescription)")
        }
    }
}

// MARK: - Notification Names (shared with macOS)

extension Notification.Name {
    static let importBibTeX = Notification.Name("importBibTeX")
    static let exportBibTeX = Notification.Name("exportBibTeX")
    static let showLibrary = Notification.Name("showLibrary")
    static let showSearch = Notification.Name("showSearch")
    static let toggleReadStatus = Notification.Name("toggleReadStatus")
    static let readStatusDidChange = Notification.Name("readStatusDidChange")
    static let copyPublications = Notification.Name("copyPublications")
    static let cutPublications = Notification.Name("cutPublications")
    static let pastePublications = Notification.Name("pastePublications")
    static let selectAllPublications = Notification.Name("selectAllPublications")

    // Inbox triage actions
    static let inboxArchive = Notification.Name("inboxArchive")
    static let inboxDismiss = Notification.Name("inboxDismiss")
    static let inboxToggleStar = Notification.Name("inboxToggleStar")
}
