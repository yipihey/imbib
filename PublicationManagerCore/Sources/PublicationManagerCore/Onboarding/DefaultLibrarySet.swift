//
//  DefaultLibrarySet.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-07.
//

import Foundation

// MARK: - Default Library Set

/// The top-level structure representing a bundled default library set.
///
/// This is used for onboarding to provide first-time users with example
/// libraries, smart searches, and collections.
public struct DefaultLibrarySet: Codable, Sendable {
    /// Schema version for future migrations
    public let version: Int

    /// Libraries to create
    public let libraries: [DefaultLibrary]

    public init(version: Int = 1, libraries: [DefaultLibrary]) {
        self.version = version
        self.libraries = libraries
    }
}

// MARK: - Default Library

/// A library definition for the default set.
public struct DefaultLibrary: Codable, Sendable, Identifiable {
    public var id: UUID { UUID() }  // Generate new UUID on each use

    /// Library display name
    public let name: String

    /// Whether this should be the default library
    public let isDefault: Bool

    /// Smart searches to create in this library
    public let smartSearches: [DefaultSmartSearch]?

    /// Collections to create in this library
    public let collections: [DefaultCollection]?

    public init(
        name: String,
        isDefault: Bool = false,
        smartSearches: [DefaultSmartSearch]? = nil,
        collections: [DefaultCollection]? = nil
    ) {
        self.name = name
        self.isDefault = isDefault
        self.smartSearches = smartSearches
        self.collections = collections
    }

    enum CodingKeys: String, CodingKey {
        case name, isDefault, smartSearches, collections
    }
}

// MARK: - Default Smart Search

/// A smart search definition for the default set.
public struct DefaultSmartSearch: Codable, Sendable, Identifiable {
    public var id: UUID { UUID() }  // Generate new UUID on each use

    /// Display name
    public let name: String

    /// Search query
    public let query: String

    /// Source IDs to use (empty = all sources)
    public let sourceIDs: [String]?

    /// Whether results feed to inbox
    public let feedsToInbox: Bool?

    /// Whether auto-refresh is enabled
    public let autoRefreshEnabled: Bool?

    /// Refresh interval in seconds (default: 21600 = 6 hours)
    public let refreshIntervalSeconds: Int?

    public init(
        name: String,
        query: String,
        sourceIDs: [String]? = nil,
        feedsToInbox: Bool? = nil,
        autoRefreshEnabled: Bool? = nil,
        refreshIntervalSeconds: Int? = nil
    ) {
        self.name = name
        self.query = query
        self.sourceIDs = sourceIDs
        self.feedsToInbox = feedsToInbox
        self.autoRefreshEnabled = autoRefreshEnabled
        self.refreshIntervalSeconds = refreshIntervalSeconds
    }

    enum CodingKeys: String, CodingKey {
        case name, query, sourceIDs, feedsToInbox, autoRefreshEnabled, refreshIntervalSeconds
    }
}

// MARK: - Default Collection

/// A collection definition for the default set.
public struct DefaultCollection: Codable, Sendable, Identifiable {
    public var id: UUID { UUID() }  // Generate new UUID on each use

    /// Collection name
    public let name: String

    public init(name: String) {
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case name
    }
}

// MARK: - Default Library Set Error

public enum DefaultLibrarySetError: LocalizedError {
    case bundleNotFound
    case decodingFailed(Error)
    case encodingFailed(Error)
    case writeFailed(Error)
    case noLibrariesToExport

    public var errorDescription: String? {
        switch self {
        case .bundleNotFound:
            return "Default library set file not found in app bundle"
        case .decodingFailed(let error):
            return "Failed to decode default library set: \(error.localizedDescription)"
        case .encodingFailed(let error):
            return "Failed to encode library set: \(error.localizedDescription)"
        case .writeFailed(let error):
            return "Failed to write library set file: \(error.localizedDescription)"
        case .noLibrariesToExport:
            return "No libraries to export"
        }
    }
}
