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
                    // Process any pending shared URLs from share extension
                    Task {
                        await handlePendingSharedURLs()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: ShareExtensionService.sharedURLReceivedNotification)) { _ in
                    Task {
                        await handlePendingSharedURLs()
                    }
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

    // MARK: - Share Extension Handling

    /// Process pending shared URLs from the share extension
    @MainActor
    private func handlePendingSharedURLs() async {
        let pendingItems = ShareExtensionService.shared.getPendingItems()

        guard !pendingItems.isEmpty else {
            // Update available libraries for share extension
            updateShareExtensionLibraries()
            return
        }

        appLogger.info("Processing \(pendingItems.count) pending shared items")

        for item in pendingItems {
            do {
                switch item.type {
                case .smartSearch:
                    try await createSmartSearchFromSharedItem(item)
                case .paper:
                    try await importPaperFromSharedItem(item)
                }
                ShareExtensionService.shared.removeItem(item)
                appLogger.info("Successfully processed shared item: \(item.type.rawValue)")
            } catch {
                appLogger.error("Failed to process shared item: \(error.localizedDescription)")
                ShareExtensionService.shared.removeItem(item)
            }
        }

        // Update available libraries for share extension
        updateShareExtensionLibraries()
    }

    /// Create a smart search from a shared item
    @MainActor
    private func createSmartSearchFromSharedItem(_ item: ShareExtensionService.SharedItem) async throws {
        // Parse the URL to get the query
        guard case .search(let query, _) = ADSURLParser.parse(item.url) else {
            throw ShareExtensionError.invalidURL
        }

        // Find the target library
        let targetLibrary: CDLibrary
        if let libraryID = item.libraryID,
           let library = libraryManager.find(id: libraryID) {
            targetLibrary = library
        } else if let defaultLibrary = libraryManager.defaultLibrary {
            targetLibrary = defaultLibrary
        } else {
            throw ShareExtensionError.noLibrary
        }

        // Create the smart search
        let name = item.name ?? "Shared Search"
        _ = SmartSearchRepository.shared.create(
            name: name,
            query: query,
            sourceIDs: ["ads"],
            library: targetLibrary,
            maxResults: 100
        )

        appLogger.info("Created smart search '\(name)' from shared URL")
    }

    /// Import a paper from a shared item
    @MainActor
    private func importPaperFromSharedItem(_ item: ShareExtensionService.SharedItem) async throws {
        // Parse the URL to get the bibcode
        guard case .paper(let bibcode) = ADSURLParser.parse(item.url) else {
            throw ShareExtensionError.invalidURL
        }

        // Search for the paper using ADS
        let searchQuery = "bibcode:\(bibcode)"
        let results = try await searchViewModel.search(query: searchQuery, sourceIDs: ["ads"])

        guard let firstResult = results.first else {
            throw ShareExtensionError.paperNotFound
        }

        // Import to library or Inbox
        if let libraryID = item.libraryID,
           let library = libraryManager.find(id: libraryID) {
            // Import to specific library
            await libraryViewModel.importSearchResults([firstResult], to: library)
        } else {
            // Import to Inbox
            await InboxManager.shared.addPaper(from: firstResult)
        }

        appLogger.info("Imported paper \(bibcode) from shared URL")
    }

    /// Update the list of available libraries in the share extension
    private func updateShareExtensionLibraries() {
        let libraryInfos = libraryManager.libraries
            .filter { !$0.isInbox }
            .map { library in
                SharedLibraryInfo(
                    id: library.id,
                    name: library.displayName,
                    isDefault: library.id == libraryManager.defaultLibrary?.id
                )
            }

        ShareExtensionService.shared.updateAvailableLibraries(libraryInfos)
        appLogger.debug("Updated share extension with \(libraryInfos.count) libraries")
    }
}

/// Errors for share extension handling
enum ShareExtensionError: LocalizedError {
    case invalidURL
    case noLibrary
    case paperNotFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid ADS URL"
        case .noLibrary:
            return "No library available"
        case .paperNotFound:
            return "Paper not found in ADS"
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
