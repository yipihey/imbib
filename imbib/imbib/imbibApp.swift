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
        }
    }
    #endif
}

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
}
