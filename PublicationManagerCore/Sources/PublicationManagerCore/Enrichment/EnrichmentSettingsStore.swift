//
//  EnrichmentSettingsStore.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog

// MARK: - Enrichment Settings Store

/// Persistent storage for enrichment settings using UserDefaults.
///
/// This actor provides thread-safe access to enrichment settings and
/// persists changes to UserDefaults for cross-session storage.
///
/// ## Usage
///
/// ```swift
/// // Get shared instance
/// let store = EnrichmentSettingsStore.shared
///
/// // Read settings
/// let settings = await store.settings
///
/// // Update settings
/// await store.update(\.autoSyncEnabled, to: false)
/// await store.updateSettings(newSettings)
/// ```
public actor EnrichmentSettingsStore: EnrichmentSettingsProvider {

    // MARK: - Shared Instance

    /// Shared instance using standard UserDefaults.
    public static let shared = EnrichmentSettingsStore()

    // MARK: - Constants

    /// UserDefaults key for storing enrichment settings.
    public static let userDefaultsKey = "com.imbib.enrichmentSettings"

    // MARK: - Properties

    private let userDefaults: UserDefaults
    private var cachedSettings: EnrichmentSettings

    // MARK: - Initialization

    /// Create a settings store with the specified UserDefaults.
    ///
    /// - Parameter userDefaults: UserDefaults instance to use (defaults to .standard)
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.cachedSettings = Self.loadSettings(from: userDefaults)
    }

    // MARK: - Read Settings

    /// Current enrichment settings.
    public var settings: EnrichmentSettings {
        cachedSettings
    }

    // MARK: - EnrichmentSettingsProvider Conformance

    public var preferredSource: EnrichmentSource {
        cachedSettings.preferredSource
    }

    public var sourcePriority: [EnrichmentSource] {
        cachedSettings.sourcePriority
    }

    public var autoSyncEnabled: Bool {
        cachedSettings.autoSyncEnabled
    }

    public var refreshIntervalDays: Int {
        cachedSettings.refreshIntervalDays
    }

    // MARK: - Update Settings

    /// Update all settings at once.
    ///
    /// - Parameter newSettings: New settings to save
    public func updateSettings(_ newSettings: EnrichmentSettings) {
        cachedSettings = newSettings
        saveSettings()
        Logger.enrichment.info("EnrichmentSettingsStore: updated all settings")
    }

    /// Update the preferred source.
    ///
    /// - Parameter source: New preferred source
    public func updatePreferredSource(_ source: EnrichmentSource) {
        cachedSettings.preferredSource = source
        saveSettings()
        Logger.enrichment.debug("EnrichmentSettingsStore: preferred source -> \(source.rawValue)")
    }

    /// Update the source priority order.
    ///
    /// - Parameter priority: New priority order
    public func updateSourcePriority(_ priority: [EnrichmentSource]) {
        cachedSettings.sourcePriority = priority
        saveSettings()
        Logger.enrichment.debug("EnrichmentSettingsStore: source priority updated")
    }

    /// Update auto-sync enabled setting.
    ///
    /// - Parameter enabled: Whether auto-sync should be enabled
    public func updateAutoSyncEnabled(_ enabled: Bool) {
        cachedSettings.autoSyncEnabled = enabled
        saveSettings()
        Logger.enrichment.debug("EnrichmentSettingsStore: auto-sync -> \(enabled)")
    }

    /// Update refresh interval in days.
    ///
    /// - Parameter days: Number of days between enrichment refreshes
    public func updateRefreshIntervalDays(_ days: Int) {
        cachedSettings.refreshIntervalDays = max(1, days)  // Minimum 1 day
        saveSettings()
        Logger.enrichment.debug("EnrichmentSettingsStore: refresh interval -> \(days) days")
    }

    /// Move a source to a different position in the priority list.
    ///
    /// - Parameters:
    ///   - source: Source to move
    ///   - index: New position (clamped to valid range)
    public func moveSource(_ source: EnrichmentSource, to index: Int) {
        var priority = cachedSettings.sourcePriority
        guard let currentIndex = priority.firstIndex(of: source) else { return }

        priority.remove(at: currentIndex)
        let newIndex = max(0, min(index, priority.count))
        priority.insert(source, at: newIndex)

        cachedSettings.sourcePriority = priority
        saveSettings()
        Logger.enrichment.debug("EnrichmentSettingsStore: moved \(source.rawValue) to index \(newIndex)")
    }

    /// Reset settings to defaults.
    public func resetToDefaults() {
        cachedSettings = .default
        saveSettings()
        Logger.enrichment.info("EnrichmentSettingsStore: reset to defaults")
    }

    // MARK: - Private Helpers

    /// Save current settings to UserDefaults.
    private func saveSettings() {
        do {
            let data = try JSONEncoder().encode(cachedSettings)
            userDefaults.set(data, forKey: Self.userDefaultsKey)
        } catch {
            Logger.enrichment.error("EnrichmentSettingsStore: failed to save settings: \(error.localizedDescription)")
        }
    }

    /// Load settings from UserDefaults (static for use in init).
    private static func loadSettings(from userDefaults: UserDefaults) -> EnrichmentSettings {
        guard let data = userDefaults.data(forKey: userDefaultsKey) else {
            Logger.enrichment.debug("EnrichmentSettingsStore: no saved settings, using defaults")
            return .default
        }

        do {
            let settings = try JSONDecoder().decode(EnrichmentSettings.self, from: data)
            Logger.enrichment.debug("EnrichmentSettingsStore: loaded saved settings")
            return settings
        } catch {
            Logger.enrichment.warning("EnrichmentSettingsStore: failed to decode settings, using defaults: \(error.localizedDescription)")
            return .default
        }
    }
}

// MARK: - Convenience Extensions

extension EnrichmentSettingsStore {
    /// Check if a source is in the priority list.
    public func isSourceEnabled(_ source: EnrichmentSource) -> Bool {
        cachedSettings.sourcePriority.contains(source)
    }

    /// Get the priority rank of a source (0 = highest priority).
    public func priorityRank(of source: EnrichmentSource) -> Int? {
        cachedSettings.sourcePriority.firstIndex(of: source)
    }

    /// Get the highest priority source that's enabled.
    public var topPrioritySource: EnrichmentSource? {
        cachedSettings.sourcePriority.first
    }
}
