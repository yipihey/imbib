//
//  QuickAnnotationSettingsStore.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-09.
//

import Foundation
import OSLog

// MARK: - Quick Annotation Settings Store

/// Actor-based store for quick annotation settings.
/// Uses UserDefaults for persistence with in-memory caching.
public actor QuickAnnotationSettingsStore {
    public static let shared = QuickAnnotationSettingsStore()

    private let userDefaults: UserDefaults
    private let settingsKey = "quickAnnotationSettings"
    private var cachedSettings: QuickAnnotationSettings?

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Get current settings (cached or loaded from UserDefaults)
    public var settings: QuickAnnotationSettings {
        if let cached = cachedSettings {
            return cached
        }
        let loaded = loadSettings()
        cachedSettings = loaded
        return loaded
    }

    /// Load settings from UserDefaults
    private func loadSettings() -> QuickAnnotationSettings {
        guard let data = userDefaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(QuickAnnotationSettings.self, from: data) else {
            Logger.notes.infoCapture("No quick annotation settings found, using defaults", category: "notes")
            return .defaults
        }
        Logger.notes.infoCapture("Loaded quick annotation settings: \(settings.fields.count) fields", category: "notes")
        return settings
    }

    /// Save settings to UserDefaults
    private func saveSettings(_ settings: QuickAnnotationSettings) {
        cachedSettings = settings
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: settingsKey)
            Logger.notes.infoCapture("Saved quick annotation settings", category: "notes")
        }
    }

    /// Update all settings
    public func update(_ settings: QuickAnnotationSettings) {
        saveSettings(settings)
    }

    /// Update a single field
    public func updateField(_ field: QuickAnnotationField) {
        var current = settings
        if let index = current.fields.firstIndex(where: { $0.id == field.id }) {
            current.fields[index] = field
            saveSettings(current)
        }
    }

    /// Add a new field
    public func addField(_ field: QuickAnnotationField) {
        var current = settings
        current.fields.append(field)
        saveSettings(current)
        Logger.notes.infoCapture("Added quick annotation field: \(field.label)", category: "notes")
    }

    /// Delete a field by ID
    public func deleteField(id: String) {
        var current = settings
        current.fields.removeAll { $0.id == id }
        saveSettings(current)
        Logger.notes.infoCapture("Deleted quick annotation field: \(id)", category: "notes")
    }

    /// Reorder fields
    public func reorderFields(from source: IndexSet, to destination: Int) {
        var current = settings
        current.fields.move(fromOffsets: source, toOffset: destination)
        saveSettings(current)
    }

    /// Reset settings to defaults
    public func resetToDefaults() {
        userDefaults.removeObject(forKey: settingsKey)
        cachedSettings = nil
        Logger.notes.infoCapture("Reset quick annotation settings to defaults", category: "notes")
    }

    /// Clear cached settings (for testing)
    public func clearCache() {
        cachedSettings = nil
    }
}

// MARK: - Logger Extension

extension Logger {
    static let notes = Logger(subsystem: "com.imbib.PublicationManagerCore", category: "notes")
}
