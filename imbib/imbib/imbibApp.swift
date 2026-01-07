//
//  imbibApp.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore
import OSLog
#if os(macOS)
import AppKit
#endif

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
        appLogger.info("imbib app initializing...")

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

        appLogger.info("imbib app initialization complete")
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(libraryManager)
                .environment(libraryViewModel)
                .environment(searchViewModel)
                .environment(settingsViewModel)
                .onAppear {
                    ensureMainWindowVisible()
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
        .commands {
            AppCommands()
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(settingsViewModel)
        }

        Window("Console", id: "console") {
            ConsoleView()
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .defaultSize(width: 800, height: 400)
        #endif
    }

    // MARK: - Window Management

    #if os(macOS)
    /// Ensure the main window is visible and frontmost on launch
    private func ensureMainWindowVisible() {
        DispatchQueue.main.async {
            // Find the main window (the one with ContentView)
            if let mainWindow = NSApplication.shared.windows.first(where: { window in
                window.contentView?.subviews.contains(where: { $0.className.contains("ContentView") }) ?? false
                    || window.title.isEmpty || window.title == "imbib"
            }) {
                mainWindow.makeKeyAndOrderFront(nil)
                appLogger.info("Main window made visible and frontmost")
            } else if NSApplication.shared.windows.isEmpty {
                // No windows at all - this shouldn't happen with WindowGroup
                appLogger.warning("No windows found on launch")
            } else {
                // Fallback: make any non-console window visible
                for window in NSApplication.shared.windows {
                    if window.title != "Console" {
                        window.makeKeyAndOrderFront(nil)
                        appLogger.info("Made window '\(window.title)' visible")
                        break
                    }
                }
            }

            // Set up dock badge observer and initial badge
            setupDockBadge()
        }
    }

    /// Set up dock badge for Inbox unread count
    private func setupDockBadge() {
        // Set initial badge
        updateDockBadge(InboxManager.shared.unreadCount)

        // Observe unread count changes
        NotificationCenter.default.addObserver(
            forName: .inboxUnreadCountChanged,
            object: nil,
            queue: .main
        ) { notification in
            if let count = notification.userInfo?["count"] as? Int {
                updateDockBadge(count)
            }
        }
    }
    #endif

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
                // Keep item in queue for retry? Or remove it?
                // For now, remove to avoid infinite retry loops
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

#if os(macOS)
/// Update the dock badge with unread count
private func updateDockBadge(_ count: Int) {
    if count > 0 {
        NSApp.dockTile.badgeLabel = "\(count)"
    } else {
        NSApp.dockTile.badgeLabel = nil
    }
}
#endif

// MARK: - App Commands

struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // File menu
        CommandGroup(after: .newItem) {
            Button("Import BibTeX...") {
                NotificationCenter.default.post(name: .importBibTeX, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command])

            Button("Export Library...") {
                NotificationCenter.default.post(name: .exportBibTeX, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        // View menu
        CommandGroup(after: .sidebar) {
            Button("Show Library") {
                NotificationCenter.default.post(name: .showLibrary, object: nil)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Show Search") {
                NotificationCenter.default.post(name: .showSearch, object: nil)
            }
            .keyboardShortcut("2", modifiers: .command)

            Divider()

            Button("Show Console") {
                openWindow(id: "console")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }

        // Edit menu - context-aware pasteboard commands
        // When a text field has focus, use system clipboard; otherwise, use publication clipboard
        CommandGroup(replacing: .pasteboard) {
            Button("Copy") {
                if isTextFieldFocused() {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                } else {
                    NotificationCenter.default.post(name: .copyPublications, object: nil)
                }
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Cut") {
                if isTextFieldFocused() {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                } else {
                    NotificationCenter.default.post(name: .cutPublications, object: nil)
                }
            }
            .keyboardShortcut("x", modifiers: .command)

            Button("Paste") {
                if isTextFieldFocused() {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                } else {
                    NotificationCenter.default.post(name: .pastePublications, object: nil)
                }
            }
            .keyboardShortcut("v", modifiers: .command)

            Divider()

            Button("Select All") {
                if isTextFieldFocused() {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                } else {
                    NotificationCenter.default.post(name: .selectAllPublications, object: nil)
                }
            }
            .keyboardShortcut("a", modifiers: .command)

            Divider()

            Button("Toggle Read/Unread") {
                NotificationCenter.default.post(name: .toggleReadStatus, object: nil)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
        }
    }

    /// Check if a text field or text view currently has keyboard focus
    private func isTextFieldFocused() -> Bool {
        guard let window = NSApp.keyWindow,
              let firstResponder = window.firstResponder else {
            return false
        }
        // NSTextView is used by TextEditor, TextField, and other text controls
        return firstResponder is NSTextView
    }
}

// MARK: - Notification Names

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
    static let inboxArchive = Notification.Name("inboxArchive")         // A key - archive to default library
    static let inboxDismiss = Notification.Name("inboxDismiss")         // D key - dismiss from inbox
    static let inboxToggleStar = Notification.Name("inboxToggleStar")   // S key - toggle star/flag
}
