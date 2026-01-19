//
//  imbibApp.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore
import OSLog
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

private let appLogger = Logger(subsystem: "com.imbib.app", category: "app")

// MARK: - App Delegate for URL Scheme Handling

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    private func debugLog(_ message: String) {
        // Use NSLog which works in sandboxed apps and shows in Console.app
        NSLog("[DEBUG] %@", message)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("AppDelegate.applicationDidFinishLaunching called")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        debugLog("AppDelegate.application(open:) called with \(urls.count) URLs")
        for url in urls {
            debugLog("Processing URL: \(url.absoluteString)")
            if url.scheme == "imbib" {
                Task {
                    await URLSchemeHandler.shared.handle(url)
                }
            }
        }
    }
}
#endif

@main
struct imbibApp: App {

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    // MARK: - State

    @State private var libraryManager: LibraryManager
    @State private var libraryViewModel: LibraryViewModel
    @State private var searchViewModel: SearchViewModel
    @State private var settingsViewModel: SettingsViewModel
    @State private var shareExtensionHandler: ShareExtensionHandler?

    /// Development mode: edit the bundled default library set
    private let isEditingDefaultSet: Bool

    // MARK: - Initialization

    init() {
        let appStart = CFAbsoluteTimeGetCurrent()

        // Check for development mode flags
        #if os(macOS)
        isEditingDefaultSet = CommandLine.arguments.contains("--edit-default-set")
        if isEditingDefaultSet {
            appLogger.info("Running in edit-default-set mode")
        }

        // Handle --reset-to-first-run flag (synchronous reset before app loads)
        if FirstRunManager.shouldResetOnLaunch {
            appLogger.warning("--reset-to-first-run flag detected, performing synchronous reset")
            // Note: This is a blocking call intentionally - we need to reset before continuing
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await FirstRunManager.shared.resetIfNeeded()
                semaphore.signal()
            }
            semaphore.wait()
            appLogger.info("Reset to first-run state complete")
        }
        #else
        isEditingDefaultSet = false
        #endif
        appLogger.info("imbib app initializing...")

        // Run data migrations (backfill indexed fields, year from rawFields, etc.)
        var stepStart = CFAbsoluteTimeGetCurrent()
        PersistenceController.shared.runMigrations()
        appLogger.info("⏱ Migrations complete: \(Int((CFAbsoluteTimeGetCurrent() - stepStart) * 1000))ms")

        // Use shared credential manager singleton for persistence
        stepStart = CFAbsoluteTimeGetCurrent()
        let credentialManager = CredentialManager.shared
        let sourceManager = SourceManager(credentialManager: credentialManager)
        let repository = PublicationRepository()
        let deduplicationService = DeduplicationService()
        appLogger.info("⏱ Created shared dependencies: \(Int((CFAbsoluteTimeGetCurrent() - stepStart) * 1000))ms")

        // Initialize LibraryManager first
        stepStart = CFAbsoluteTimeGetCurrent()
        _libraryManager = State(initialValue: LibraryManager())
        appLogger.info("⏱ LibraryManager initialized: \(Int((CFAbsoluteTimeGetCurrent() - stepStart) * 1000))ms")

        // Initialize ViewModels
        stepStart = CFAbsoluteTimeGetCurrent()
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
        appLogger.info("⏱ ViewModels initialized: \(Int((CFAbsoluteTimeGetCurrent() - stepStart) * 1000))ms")

        // Initialize share extension handler (needs sourceManager)
        // Note: Cannot use _shareExtensionHandler here because LibraryManager is @State
        // Will be set in onAppear instead

        // Set up Darwin notification observers for extensions (before Task)
        // This must be done early, before the app might receive notifications
        appLogger.info("⏱ Before Darwin notification setup")
        ShareExtensionHandler.setupDarwinNotificationObserver()
        SafariImportHandler.shared.setupNotificationObserver()
        appLogger.info("⏱ After Darwin notification setup")

        // Register built-in sources and start enrichment
        Task {
            await sourceManager.registerBuiltInSources()
            appLogger.info("Built-in sources registered")

            // Register browser URL providers for interactive PDF downloads
            // Higher priority = tried first. ArXiv has highest priority (direct PDF, always free)
            await BrowserURLProviderRegistry.shared.register(ArXivSource.self, priority: 20)
            await BrowserURLProviderRegistry.shared.register(SciXSource.self, priority: 11)
            await BrowserURLProviderRegistry.shared.register(ADSSource.self, priority: 10)
            appLogger.info("BrowserURLProviders registered")

            // Configure staggered smart search refresh service (before InboxCoordinator)
            await SmartSearchRefreshService.shared.configure(
                sourceManager: sourceManager,
                repository: repository
            )
            appLogger.info("SmartSearchRefreshService configured")

            // Start background enrichment coordinator
            await EnrichmentCoordinator.shared.start()
            appLogger.info("EnrichmentCoordinator started")

            // Start Inbox coordinator (scheduling, fetch service)
            await InboxCoordinator.shared.start()
            appLogger.info("InboxCoordinator started")
        }

        appLogger.info("⏱ TOTAL app init: \(Int((CFAbsoluteTimeGetCurrent() - appStart) * 1000))ms")
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .withTheme()
                .environment(libraryManager)
                .environment(libraryViewModel)
                .environment(searchViewModel)
                .environment(settingsViewModel)
                .onAppear {
                    ensureMainWindowVisible()
                    // Initialize share extension handler
                    if shareExtensionHandler == nil {
                        shareExtensionHandler = ShareExtensionHandler(
                            libraryManager: libraryManager,
                            sourceManager: searchViewModel.sourceManager
                        )
                    }
                    // Note: App Group access is deferred until the Safari extension is actually used.
                    // This avoids the TCC "access data from other apps" dialog at startup.
                    // When a Darwin notification arrives from the extension, we process imports
                    // and sync data back to the App Group at that time.
                }
                .onReceive(NotificationCenter.default.publisher(for: ShareExtensionService.sharedURLReceivedNotification)) { _ in
                    Task {
                        await shareExtensionHandler?.handlePendingSharedItems()
                    }
                }
                #if os(iOS)
                .onOpenURL { url in
                    // Handle automation URL schemes (imbib://...)
                    if url.scheme == "imbib" {
                        Task {
                            await URLSchemeHandler.shared.handle(url)
                        }
                    }
                }
                #endif
        }
        .commands {
            AppCommands()
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(settingsViewModel)
                .environment(libraryManager)
        }

        Window("Console", id: "console") {
            ConsoleView()
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .defaultSize(width: 800, height: 400)

        Window("Keyboard Shortcuts", id: "keyboard-shortcuts") {
            KeyboardShortcutsView()
        }
        .keyboardShortcut("/", modifiers: .command)
        .defaultSize(width: 450, height: 700)
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
}

#if os(macOS)
/// Update the dock badge with unread count
@MainActor
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

    /// Check if running in edit-default-set development mode
    private var isEditingDefaultSet: Bool {
        CommandLine.arguments.contains("--edit-default-set")
    }

    var body: some Commands {
        // Development mode: Export default set
        if isEditingDefaultSet {
            CommandGroup(before: .newItem) {
                Button("Export as Default Library Set...") {
                    exportDefaultLibrarySet()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()
            }
        }

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

            Button("Copy as Citation") {
                NotificationCenter.default.post(name: .copyAsCitation, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Copy DOI/URL") {
                NotificationCenter.default.post(name: .copyIdentifier, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])

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

            // Find submenu
            Menu("Find") {
                Button("Focus Search") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
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

            Button("Show Inbox") {
                NotificationCenter.default.post(name: .showInbox, object: nil)
            }
            .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button("Show PDF Tab") {
                NotificationCenter.default.post(name: .showPDFTab, object: nil)
            }
            .keyboardShortcut("4", modifiers: .command)

            Button("Show BibTeX Tab") {
                NotificationCenter.default.post(name: .showBibTeXTab, object: nil)
            }
            .keyboardShortcut("5", modifiers: .command)

            Button("Show Notes Tab") {
                NotificationCenter.default.post(name: .showNotesTab, object: nil)
            }
            .keyboardShortcut("6", modifiers: .command)

            Divider()

            Button("Toggle Detail Pane") {
                NotificationCenter.default.post(name: .toggleDetailPane, object: nil)
            }
            .keyboardShortcut("0", modifiers: .command)

            Button("Toggle Sidebar") {
                NotificationCenter.default.post(name: .toggleSidebar, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.control, .command])

            Divider()

            Button("Focus Sidebar") {
                NotificationCenter.default.post(name: .focusSidebar, object: nil)
            }
            .keyboardShortcut("1", modifiers: [.command, .option])

            Button("Focus List") {
                NotificationCenter.default.post(name: .focusList, object: nil)
            }
            .keyboardShortcut("2", modifiers: [.command, .option])

            Button("Focus Detail") {
                NotificationCenter.default.post(name: .focusDetail, object: nil)
            }
            .keyboardShortcut("3", modifiers: [.command, .option])

            Divider()

            Button("Show Console") {
                openWindow(id: "console")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }

        // Paper menu (new)
        CommandMenu("Paper") {
            Button("Open PDF") {
                NotificationCenter.default.post(name: .openSelectedPaper, object: nil)
            }
            .keyboardShortcut(.return, modifiers: [])

            Button("Open Notes") {
                NotificationCenter.default.post(name: .showNotesTab, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Open References") {
                NotificationCenter.default.post(name: .openReferences, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Toggle Read/Unread") {
                NotificationCenter.default.post(name: .toggleReadStatus, object: nil)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            Button("Mark All as Read") {
                NotificationCenter.default.post(name: .markAllAsRead, object: nil)
            }
            .keyboardShortcut("u", modifiers: [.command, .option])

            Divider()

            Button("Keep to Library") {
                NotificationCenter.default.post(name: .keepToLibrary, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.control, .command])

            Button("Dismiss from Inbox") {
                NotificationCenter.default.post(name: .dismissFromInbox, object: nil)
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])

            Divider()

            Button("Move to Collection...") {
                NotificationCenter.default.post(name: .moveToCollection, object: nil)
            }
            .keyboardShortcut("m", modifiers: [.control, .command])

            Button("Add to Collection...") {
                NotificationCenter.default.post(name: .addToCollection, object: nil)
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Remove from Collection") {
                NotificationCenter.default.post(name: .removeFromCollection, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Divider()

            Button("Share...") {
                NotificationCenter.default.post(name: .sharePapers, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("Delete") {
                NotificationCenter.default.post(name: .deleteSelectedPapers, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: .command)
        }

        // Annotate menu (PDF annotations)
        CommandMenu("Annotate") {
            Button("Highlight Selection") {
                NotificationCenter.default.post(name: .highlightSelection, object: nil)
            }
            .keyboardShortcut("h", modifiers: .control)

            Button("Underline Selection") {
                NotificationCenter.default.post(name: .underlineSelection, object: nil)
            }
            .keyboardShortcut("u", modifiers: .control)

            Button("Strikethrough Selection") {
                NotificationCenter.default.post(name: .strikethroughSelection, object: nil)
            }
            .keyboardShortcut("t", modifiers: .control)

            Divider()

            Button("Add Note at Selection") {
                NotificationCenter.default.post(name: .addNoteAtSelection, object: nil)
            }
            .keyboardShortcut("n", modifiers: .control)

            Divider()

            Menu("Highlight Color") {
                Button("Yellow") {
                    NotificationCenter.default.post(
                        name: .highlightSelection,
                        object: nil,
                        userInfo: ["color": "yellow"]
                    )
                }
                Button("Green") {
                    NotificationCenter.default.post(
                        name: .highlightSelection,
                        object: nil,
                        userInfo: ["color": "green"]
                    )
                }
                Button("Blue") {
                    NotificationCenter.default.post(
                        name: .highlightSelection,
                        object: nil,
                        userInfo: ["color": "blue"]
                    )
                }
                Button("Pink") {
                    NotificationCenter.default.post(
                        name: .highlightSelection,
                        object: nil,
                        userInfo: ["color": "pink"]
                    )
                }
                Button("Purple") {
                    NotificationCenter.default.post(
                        name: .highlightSelection,
                        object: nil,
                        userInfo: ["color": "purple"]
                    )
                }
            }
        }

        // Go menu (new)
        CommandMenu("Go") {
            Button("Back") {
                NotificationCenter.default.post(name: .navigateBack, object: nil)
            }
            .keyboardShortcut("[", modifiers: .command)

            Button("Forward") {
                NotificationCenter.default.post(name: .navigateForward, object: nil)
            }
            .keyboardShortcut("]", modifiers: .command)

            Divider()

            Button("Next Paper") {
                NotificationCenter.default.post(name: .navigateNextPaper, object: nil)
            }
            .keyboardShortcut(.downArrow, modifiers: [])

            Button("Previous Paper") {
                NotificationCenter.default.post(name: .navigatePreviousPaper, object: nil)
            }
            .keyboardShortcut(.upArrow, modifiers: [])

            Button("First Paper") {
                NotificationCenter.default.post(name: .navigateFirstPaper, object: nil)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)

            Button("Last Paper") {
                NotificationCenter.default.post(name: .navigateLastPaper, object: nil)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)

            Divider()

            Button("Next Unread") {
                NotificationCenter.default.post(name: .navigateNextUnread, object: nil)
            }
            .keyboardShortcut(.downArrow, modifiers: .option)

            Button("Previous Unread") {
                NotificationCenter.default.post(name: .navigatePreviousUnread, object: nil)
            }
            .keyboardShortcut(.upArrow, modifiers: .option)

            Divider()

            Button("Go to Page...") {
                NotificationCenter.default.post(name: .pdfGoToPage, object: nil)
            }
            .keyboardShortcut("g", modifiers: .command)
        }

        // Window menu additions
        CommandGroup(after: .windowArrangement) {
            Divider()

            Button("Refresh") {
                NotificationCenter.default.post(name: .refreshData, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Toggle Unread Filter") {
                NotificationCenter.default.post(name: .toggleUnreadFilter, object: nil)
            }
            .keyboardShortcut("\\", modifiers: .command)

            Button("Toggle PDF Filter") {
                NotificationCenter.default.post(name: .togglePDFFilter, object: nil)
            }
            .keyboardShortcut("\\", modifiers: [.command, .shift])
        }

        // Help menu
        CommandGroup(replacing: .help) {
            Button("imbib Help") {
                if let url = URL(string: "https://github.com/imbib/imbib") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Keyboard Shortcuts") {
                openWindow(id: "keyboard-shortcuts")
            }
            .keyboardShortcut("/", modifiers: .command)

            Divider()

            Button("Release Notes") {
                if let url = URL(string: "https://github.com/imbib/imbib/releases") {
                    NSWorkspace.shared.open(url)
                }
            }
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

    /// Export current libraries as a default library set (development mode)
    private func exportDefaultLibrarySet() {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "DefaultLibrarySet.json"
        panel.message = "Export current libraries as the default set for new users"
        panel.prompt = "Export"

        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in
                do {
                    try DefaultLibrarySetManager.shared.exportCurrentAsDefaultSet(to: url)
                    appLogger.info("Exported default library set to: \(url.lastPathComponent)")

                    // Show success alert
                    let alert = NSAlert()
                    alert.messageText = "Export Successful"
                    alert.informativeText = "Default library set exported to \(url.lastPathComponent)"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                } catch {
                    appLogger.error("Failed to export default library set: \(error.localizedDescription)")

                    // Show error alert
                    let alert = NSAlert()
                    alert.messageText = "Export Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
        #endif
    }
}

// Note: Notification.Name extensions are now defined in PublicationManagerCore/Notifications.swift
