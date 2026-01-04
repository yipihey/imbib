//
//  Logger+Extensions.swift
//  PublicationManagerCore
//

import Foundation
import OSLog

// MARK: - Subsystem

private let subsystem = "com.imbib"

// MARK: - Logger Categories

public extension Logger {

    // MARK: - Data Layer

    static let persistence = Logger(subsystem: subsystem, category: "Persistence")

    // MARK: - BibTeX

    static let bibtex = Logger(subsystem: subsystem, category: "BibTeX")

    // MARK: - Sources

    static let sources = Logger(subsystem: subsystem, category: "Sources")
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let rateLimiter = Logger(subsystem: subsystem, category: "RateLimiter")
    static let deduplication = Logger(subsystem: subsystem, category: "Deduplication")

    // MARK: - Credentials

    static let credentials = Logger(subsystem: subsystem, category: "Credentials")

    // MARK: - Files

    static let files = Logger(subsystem: subsystem, category: "Files")

    // MARK: - Sync

    static let sync = Logger(subsystem: subsystem, category: "Sync")

    // MARK: - UI

    static let viewModels = Logger(subsystem: subsystem, category: "ViewModels")
    static let navigation = Logger(subsystem: subsystem, category: "Navigation")
}

// MARK: - Convenience Methods

public extension Logger {

    func entering(function: String = #function) {
        debug("→ \(function)")
    }

    func exiting(function: String = #function) {
        debug("← \(function)")
    }

    func httpRequest(_ method: String, url: URL) {
        info("HTTP \(method) \(url.absoluteString)")
    }

    func httpResponse(_ statusCode: Int, url: URL, bytes: Int? = nil) {
        if let bytes = bytes {
            info("HTTP \(statusCode) \(url.absoluteString) (\(bytes) bytes)")
        } else {
            info("HTTP \(statusCode) \(url.absoluteString)")
        }
    }
}
