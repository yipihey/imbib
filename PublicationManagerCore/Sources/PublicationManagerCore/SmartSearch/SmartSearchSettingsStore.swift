//
//  SmartSearchSettingsStore.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-05.
//

import Foundation
import OSLog

// MARK: - Smart Search Settings

/// Settings for smart search behavior
public struct SmartSearchSettings: Codable, Equatable, Sendable {
    /// Default maximum number of results to retrieve per smart search
    public var defaultMaxResults: Int16

    public init(defaultMaxResults: Int16 = 50) {
        self.defaultMaxResults = defaultMaxResults
    }

    public static let `default` = SmartSearchSettings()
}

// MARK: - Smart Search Settings Store

/// Actor-based store for smart search settings
/// Uses UserDefaults for persistence with in-memory caching
public actor SmartSearchSettingsStore {
    public static let shared = SmartSearchSettingsStore()

    private let userDefaults: UserDefaults
    private let settingsKey = "smartSearchSettings"
    private var cachedSettings: SmartSearchSettings?

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Get current settings (cached or loaded from UserDefaults)
    public var settings: SmartSearchSettings {
        if let cached = cachedSettings {
            return cached
        }
        let loaded = loadSettings()
        cachedSettings = loaded
        return loaded
    }

    /// Load settings from UserDefaults
    private func loadSettings() -> SmartSearchSettings {
        guard let data = userDefaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(SmartSearchSettings.self, from: data) else {
            Logger.smartSearch.infoCapture("No smart search settings found, using defaults", category: "smartsearch")
            return .default
        }
        Logger.smartSearch.infoCapture("Loaded smart search settings: maxResults=\(settings.defaultMaxResults)", category: "smartsearch")
        return settings
    }

    /// Save settings to UserDefaults
    private func saveSettings(_ settings: SmartSearchSettings) {
        cachedSettings = settings
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: settingsKey)
            Logger.smartSearch.infoCapture("Saved smart search settings: maxResults=\(settings.defaultMaxResults)", category: "smartsearch")
        }
    }

    /// Update default maximum results
    public func updateDefaultMaxResults(_ maxResults: Int16) {
        var current = settings
        current.defaultMaxResults = maxResults
        saveSettings(current)
    }

    /// Reset settings to defaults
    public func reset() {
        userDefaults.removeObject(forKey: settingsKey)
        cachedSettings = nil
        Logger.smartSearch.infoCapture("Reset smart search settings to defaults", category: "smartsearch")
    }

    /// Clear cached settings (for testing)
    public func clearCache() {
        cachedSettings = nil
    }
}
