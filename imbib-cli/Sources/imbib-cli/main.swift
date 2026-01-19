//
//  main.swift
//  imbib-cli
//
//  A command-line interface for controlling the imbib app.
//
//  Created by Claude on 2026-01-09.
//

import ArgumentParser
import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// imbib CLI - Control imbib from the command line.
///
/// This tool sends URL scheme commands to the imbib app.
/// Requires imbib to be running with automation enabled.
@main
struct ImbibCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "imbib",
        abstract: "Control imbib from the command line",
        discussion: """
            This CLI sends URL scheme commands to the imbib app.
            Make sure imbib is running and automation is enabled in Settings > General.

            Examples:
              imbib search "dark matter"
              imbib navigate inbox
              imbib selected toggle-read
              imbib paper Einstein1905 open-pdf
            """,
        version: "1.0.0",
        subcommands: [
            SearchCommand.self,
            NavigateCommand.self,
            FocusCommand.self,
            PaperCommand.self,
            SelectedCommand.self,
            InboxCommand.self,
            PDFCommand.self,
            AppCommand.self,
            ImportCommand.self,
            ExportCommand.self,
            RawCommand.self
        ],
        defaultSubcommand: nil
    )
}

// MARK: - URL Launcher

/// Opens imbib:// URLs using the system.
enum URLLauncher {
    /// Open a URL scheme command.
    static func open(_ urlString: String) async throws {
        guard let url = URL(string: urlString) else {
            throw CLIError.invalidURL(urlString)
        }

        #if canImport(AppKit)
        let workspace = NSWorkspace.shared
        let configuration = NSWorkspace.OpenConfiguration()

        try await workspace.open(url, configuration: configuration)
        #else
        throw CLIError.unsupportedPlatform
        #endif
    }

    /// Build and open a URL with the given path and query parameters.
    static func open(path: String, queryItems: [URLQueryItem] = []) async throws {
        var components = URLComponents()
        components.scheme = "imbib"
        components.host = path.components(separatedBy: "/").first ?? path

        // Handle paths like "paper/Einstein1905/open-pdf"
        let pathParts = path.components(separatedBy: "/")
        if pathParts.count > 1 {
            components.path = "/" + pathParts.dropFirst().joined(separator: "/")
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw CLIError.invalidURL(path)
        }

        try await open(url.absoluteString)
    }
}

// MARK: - CLI Error

enum CLIError: LocalizedError {
    case invalidURL(String)
    case unsupportedPlatform
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .unsupportedPlatform:
            return "This command is only supported on macOS"
        case .executionFailed(let reason):
            return "Command failed: \(reason)"
        }
    }
}

// MARK: - Search Command

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search for papers"
    )

    @Argument(help: "Search query")
    var query: String

    @Option(name: .shortAndLong, help: "Source to search (ads, arxiv, crossref, etc.)")
    var source: String?

    @Option(name: .shortAndLong, help: "Maximum number of results")
    var max: Int?

    func run() async throws {
        var items = [URLQueryItem(name: "query", value: query)]
        if let source = source {
            items.append(URLQueryItem(name: "source", value: source))
        }
        if let max = max {
            items.append(URLQueryItem(name: "max", value: String(max)))
        }

        try await URLLauncher.open(path: "search", queryItems: items)
        print("Searching for: \(query)")
    }
}

// MARK: - Navigate Command

struct NavigateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "navigate",
        abstract: "Navigate to a view",
        aliases: ["nav", "go"]
    )

    @Argument(help: "Target: library, search, inbox, pdf-tab, bibtex-tab, notes-tab")
    var target: String

    func run() async throws {
        try await URLLauncher.open(path: "navigate/\(target)")
        print("Navigating to: \(target)")
    }
}

// MARK: - Focus Command

struct FocusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focus",
        abstract: "Focus a UI area"
    )

    @Argument(help: "Target: sidebar, list, detail, search")
    var target: String

    func run() async throws {
        try await URLLauncher.open(path: "focus/\(target)")
        print("Focusing: \(target)")
    }
}

// MARK: - Paper Command

struct PaperCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "paper",
        abstract: "Perform action on a specific paper"
    )

    @Argument(help: "Cite key of the paper")
    var citeKey: String

    @Argument(help: "Action: open, open-pdf, open-notes, toggle-read, mark-read, mark-unread, delete, copy-bibtex, copy-citation, share")
    var action: String

    @Option(name: .long, help: "Library ID for keep action")
    var library: String?

    @Option(name: .long, help: "Collection ID for add-to/remove-from collection")
    var collection: String?

    func run() async throws {
        var items: [URLQueryItem] = []
        if let library = library {
            items.append(URLQueryItem(name: "library", value: library))
        }
        if let collection = collection {
            items.append(URLQueryItem(name: "collection", value: collection))
        }

        try await URLLauncher.open(path: "paper/\(citeKey)/\(action)", queryItems: items)
        print("Paper '\(citeKey)': \(action)")
    }
}

// MARK: - Selected Command

struct SelectedCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "selected",
        abstract: "Perform action on selected papers"
    )

    @Argument(help: "Action: open, toggle-read, mark-read, mark-unread, mark-all-read, delete, keep, copy, cut, share, copy-citation, copy-identifier")
    var action: String

    func run() async throws {
        try await URLLauncher.open(path: "selected/\(action)")
        print("Selected papers: \(action)")
    }
}

// MARK: - Inbox Command

struct InboxCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inbox",
        abstract: "Inbox actions"
    )

    @Argument(help: "Action: show, keep, dismiss, toggle-star, mark-read, mark-unread, next, previous, open")
    var action: String = "show"

    func run() async throws {
        try await URLLauncher.open(path: "inbox/\(action)")
        print("Inbox: \(action)")
    }
}

// MARK: - PDF Command

struct PDFCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pdf",
        abstract: "PDF viewer actions"
    )

    @Argument(help: "Action: go-to-page, page-down, page-up, zoom-in, zoom-out, actual-size, fit-to-window")
    var action: String

    @Option(name: .shortAndLong, help: "Page number (for go-to-page)")
    var page: Int?

    func run() async throws {
        var items: [URLQueryItem] = []
        if let page = page {
            items.append(URLQueryItem(name: "page", value: String(page)))
        }

        try await URLLauncher.open(path: "pdf/\(action)", queryItems: items)
        print("PDF: \(action)")
    }
}

// MARK: - App Command

struct AppCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app",
        abstract: "App-level actions"
    )

    @Argument(help: "Action: refresh, toggle-sidebar, toggle-detail-pane, toggle-unread-filter, toggle-pdf-filter, show-keyboard-shortcuts")
    var action: String

    func run() async throws {
        try await URLLauncher.open(path: "app/\(action)")
        print("App: \(action)")
    }
}

// MARK: - Import Command

struct ImportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import BibTeX or RIS file"
    )

    @Argument(help: "File path to import")
    var file: String?

    @Option(name: .shortAndLong, help: "Format: bibtex, ris")
    var format: String = "bibtex"

    @Option(name: .shortAndLong, help: "Library ID to import into")
    var library: String?

    func run() async throws {
        var items: [URLQueryItem] = [URLQueryItem(name: "format", value: format)]
        if let file = file {
            items.append(URLQueryItem(name: "file", value: file))
        }
        if let library = library {
            items.append(URLQueryItem(name: "library", value: library))
        }

        try await URLLauncher.open(path: "import", queryItems: items)
        print("Importing \(format)...")
    }
}

// MARK: - Export Command

struct ExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export library"
    )

    @Option(name: .shortAndLong, help: "Format: bibtex, ris, csv")
    var format: String = "bibtex"

    @Option(name: .shortAndLong, help: "Library ID to export")
    var library: String?

    func run() async throws {
        var items: [URLQueryItem] = [URLQueryItem(name: "format", value: format)]
        if let library = library {
            items.append(URLQueryItem(name: "library", value: library))
        }

        try await URLLauncher.open(path: "export", queryItems: items)
        print("Exporting as \(format)...")
    }
}

// MARK: - Raw Command

struct RawCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "raw",
        abstract: "Send raw URL command"
    )

    @Argument(help: "Raw URL path (e.g., 'search?query=test')")
    var path: String

    func run() async throws {
        let url = "imbib://\(path)"
        try await URLLauncher.open(url)
        print("Sent: \(url)")
    }
}
