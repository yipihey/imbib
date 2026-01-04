//
//  Logger+Extensions.swift
//  PublicationManagerCore
//

import Foundation
import OSLog

// MARK: - Subsystem

private let subsystem = "com.imbib"

// MARK: - Category Names

/// Maps Logger instances to their category names for LogStore capture
private var loggerCategories: [ObjectIdentifier: String] = [:]

// MARK: - Logger Categories

public extension Logger {

    // MARK: - Data Layer

    static let persistence = Logger(subsystem: subsystem, category: "persistence")

    // MARK: - BibTeX

    static let bibtex = Logger(subsystem: subsystem, category: "bibtex")

    // MARK: - Sources

    static let sources = Logger(subsystem: subsystem, category: "sources")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let rateLimiter = Logger(subsystem: subsystem, category: "ratelimit")
    static let deduplication = Logger(subsystem: subsystem, category: "dedup")

    // MARK: - Credentials

    static let credentials = Logger(subsystem: subsystem, category: "credentials")

    // MARK: - Files

    static let files = Logger(subsystem: subsystem, category: "files")

    // MARK: - Sync

    static let sync = Logger(subsystem: subsystem, category: "sync")

    // MARK: - UI

    static let viewModels = Logger(subsystem: subsystem, category: "viewmodels")
    static let navigation = Logger(subsystem: subsystem, category: "navigation")
}

// MARK: - Capturing Log Methods

public extension Logger {

    /// Log debug message and capture to LogStore
    func debugCapture(_ message: String, category: String) {
        debug("\(message)")
        captureToStore(level: .debug, category: category, message: message)
    }

    /// Log info message and capture to LogStore
    func infoCapture(_ message: String, category: String) {
        info("\(message)")
        captureToStore(level: .info, category: category, message: message)
    }

    /// Log warning message and capture to LogStore
    func warningCapture(_ message: String, category: String) {
        warning("\(message)")
        captureToStore(level: .warning, category: category, message: message)
    }

    /// Log error message and capture to LogStore
    func errorCapture(_ message: String, category: String) {
        error("\(message)")
        captureToStore(level: .error, category: category, message: message)
    }

    private func captureToStore(level: LogLevel, category: String, message: String) {
        Task { @MainActor in
            LogStore.shared.log(level: level, category: category, message: message)
        }
    }
}

// MARK: - Convenience Methods

public extension Logger {

    func entering(function: String = #function, category: String = "trace") {
        debugCapture("→ \(function)", category: category)
    }

    func exiting(function: String = #function, category: String = "trace") {
        debugCapture("← \(function)", category: category)
    }

    func httpRequest(_ method: String, url: URL) {
        infoCapture("HTTP \(method) \(url.absoluteString)", category: "network")
    }

    func httpResponse(_ statusCode: Int, url: URL, bytes: Int? = nil) {
        if let bytes = bytes {
            infoCapture("HTTP \(statusCode) \(url.absoluteString) (\(bytes) bytes)", category: "network")
        } else {
            infoCapture("HTTP \(statusCode) \(url.absoluteString)", category: "network")
        }
    }
}

// MARK: - Global Logging Functions

/// Convenience functions for logging with automatic capture

public func logDebug(_ message: String, category: String = "app") {
    Logger.viewModels.debugCapture(message, category: category)
}

public func logInfo(_ message: String, category: String = "app") {
    Logger.viewModels.infoCapture(message, category: category)
}

public func logWarning(_ message: String, category: String = "app") {
    Logger.viewModels.warningCapture(message, category: category)
}

public func logError(_ message: String, category: String = "app") {
    Logger.viewModels.errorCapture(message, category: category)
}
