//
//  ImportExportSettingsStore.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-18.
//

import Foundation
import OSLog

// MARK: - Import/Export Settings

/// Settings for import and export behavior.
public struct ImportExportSettings: Equatable, Sendable {
    /// Whether to auto-generate cite keys when importing entries with missing/generic cite keys
    public var autoGenerateCiteKeys: Bool

    /// Default entry type for entries without a specified type
    public var defaultEntryType: String

    /// Whether to preserve original BibTeX formatting when exporting
    public var exportPreserveRawBibTeX: Bool

    /// Whether to open PDFs in external viewer instead of built-in viewer
    public var openPDFExternally: Bool

    public init(
        autoGenerateCiteKeys: Bool = true,
        defaultEntryType: String = "article",
        exportPreserveRawBibTeX: Bool = true,
        openPDFExternally: Bool = false
    ) {
        self.autoGenerateCiteKeys = autoGenerateCiteKeys
        self.defaultEntryType = defaultEntryType
        self.exportPreserveRawBibTeX = exportPreserveRawBibTeX
        self.openPDFExternally = openPDFExternally
    }

    public static let `default` = ImportExportSettings()
}

// MARK: - Import/Export Settings Store

/// Actor for reading and updating import/export settings.
/// These settings are stored in UserDefaults (synced with @AppStorage).
public actor ImportExportSettingsStore {

    // MARK: - Shared Instance

    public static let shared = ImportExportSettingsStore()

    // MARK: - Keys

    private enum Keys {
        static let autoGenerateCiteKeys = "autoGenerateCiteKeys"
        static let defaultEntryType = "defaultEntryType"
        static let exportPreserveRawBibTeX = "exportPreserveRawBibTeX"
        static let openPDFExternally = "openPDFInExternalViewer"
    }

    // MARK: - Initialization

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Register defaults
        defaults.register(defaults: [
            Keys.autoGenerateCiteKeys: true,
            Keys.defaultEntryType: "article",
            Keys.exportPreserveRawBibTeX: true,
            Keys.openPDFExternally: false
        ])
    }

    // MARK: - Current Settings

    /// Get the current settings
    public var settings: ImportExportSettings {
        ImportExportSettings(
            autoGenerateCiteKeys: defaults.bool(forKey: Keys.autoGenerateCiteKeys),
            defaultEntryType: defaults.string(forKey: Keys.defaultEntryType) ?? "article",
            exportPreserveRawBibTeX: defaults.bool(forKey: Keys.exportPreserveRawBibTeX),
            openPDFExternally: defaults.bool(forKey: Keys.openPDFExternally)
        )
    }

    // MARK: - Individual Properties

    /// Whether to auto-generate cite keys for entries with missing/generic cite keys
    public var autoGenerateCiteKeys: Bool {
        defaults.bool(forKey: Keys.autoGenerateCiteKeys)
    }

    /// Default entry type for entries without a specified type
    public var defaultEntryType: String {
        defaults.string(forKey: Keys.defaultEntryType) ?? "article"
    }

    /// Whether to preserve raw BibTeX on export
    public var exportPreserveRawBibTeX: Bool {
        defaults.bool(forKey: Keys.exportPreserveRawBibTeX)
    }

    /// Whether to open PDFs in external viewer
    public var openPDFExternally: Bool {
        defaults.bool(forKey: Keys.openPDFExternally)
    }

    // MARK: - Update Methods

    public func updateAutoGenerateCiteKeys(_ value: Bool) {
        defaults.set(value, forKey: Keys.autoGenerateCiteKeys)
        Logger.settings.infoCapture(
            "Auto-generate cite keys \(value ? "enabled" : "disabled")",
            category: "settings"
        )
    }

    public func updateDefaultEntryType(_ value: String) {
        defaults.set(value, forKey: Keys.defaultEntryType)
        Logger.settings.infoCapture(
            "Default entry type set to '\(value)'",
            category: "settings"
        )
    }

    public func updateExportPreserveRawBibTeX(_ value: Bool) {
        defaults.set(value, forKey: Keys.exportPreserveRawBibTeX)
        Logger.settings.infoCapture(
            "Preserve raw BibTeX on export \(value ? "enabled" : "disabled")",
            category: "settings"
        )
    }

    public func updateOpenPDFExternally(_ value: Bool) {
        defaults.set(value, forKey: Keys.openPDFExternally)
        Logger.settings.infoCapture(
            "Open PDFs externally \(value ? "enabled" : "disabled")",
            category: "settings"
        )
    }

    public func update(_ settings: ImportExportSettings) {
        defaults.set(settings.autoGenerateCiteKeys, forKey: Keys.autoGenerateCiteKeys)
        defaults.set(settings.defaultEntryType, forKey: Keys.defaultEntryType)
        defaults.set(settings.exportPreserveRawBibTeX, forKey: Keys.exportPreserveRawBibTeX)
        defaults.set(settings.openPDFExternally, forKey: Keys.openPDFExternally)
    }

    // MARK: - Reset

    public func resetToDefaults() {
        update(.default)
        Logger.settings.infoCapture(
            "Import/export settings reset to defaults",
            category: "settings"
        )
    }
}
