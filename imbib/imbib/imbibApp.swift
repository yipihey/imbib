//
//  imbibApp.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore

@main
struct imbibApp: App {

    // MARK: - State

    @State private var libraryManager: LibraryManager
    @State private var libraryViewModel: LibraryViewModel
    @State private var searchViewModel: SearchViewModel
    @State private var settingsViewModel: SettingsViewModel

    // MARK: - Initialization

    init() {
        // Create shared dependencies
        let credentialManager = CredentialManager()
        let sourceManager = SourceManager(credentialManager: credentialManager)
        let repository = PublicationRepository()
        let deduplicationService = DeduplicationService()

        // Initialize LibraryManager first
        _libraryManager = State(initialValue: LibraryManager())

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

        // Register built-in sources
        Task {
            await sourceManager.registerBuiltInSources()
        }
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(libraryManager)
                .environment(libraryViewModel)
                .environment(searchViewModel)
                .environment(settingsViewModel)
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
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let importBibTeX = Notification.Name("importBibTeX")
    static let exportBibTeX = Notification.Name("exportBibTeX")
    static let showLibrary = Notification.Name("showLibrary")
    static let showSearch = Notification.Name("showSearch")
}
