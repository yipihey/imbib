//
//  PDFSettingsStore.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog

// MARK: - PDF Source Priority

/// User preference for which PDF source to try first
public enum PDFSourcePriority: String, Codable, CaseIterable, Sendable {
    case preprint   // Prefer arXiv, bioRxiv, preprint servers
    case publisher  // Prefer publisher PDFs (via proxy if configured)

    public var displayName: String {
        switch self {
        case .preprint: return "Preprint (arXiv, etc.)"
        case .publisher: return "Publisher"
        }
    }

    public var description: String {
        switch self {
        case .preprint: return "Free and always accessible"
        case .publisher: return "Original version, may require proxy"
        }
    }
}

// MARK: - PDF Settings

/// Settings for PDF viewing and downloading
public struct PDFSettings: Codable, Equatable, Sendable {
    public var sourcePriority: PDFSourcePriority
    public var libraryProxyURL: String
    public var proxyEnabled: Bool

    public init(
        sourcePriority: PDFSourcePriority = .preprint,
        libraryProxyURL: String = "",
        proxyEnabled: Bool = false
    ) {
        self.sourcePriority = sourcePriority
        self.libraryProxyURL = libraryProxyURL
        self.proxyEnabled = proxyEnabled
    }

    public static let `default` = PDFSettings()

    /// Common library proxy URLs for reference
    public static let commonProxies: [(name: String, url: String)] = [
        ("Stanford", "https://stanford.idm.oclc.org/login?url="),
        ("Harvard", "https://ezp-prod1.hul.harvard.edu/login?url="),
        ("MIT", "https://libproxy.mit.edu/login?url="),
        ("Berkeley", "https://libproxy.berkeley.edu/login?url="),
        ("Yale", "https://yale.idm.oclc.org/login?url="),
        ("Princeton", "https://ezproxy.princeton.edu/login?url="),
        ("Columbia", "https://ezproxy.cul.columbia.edu/login?url="),
        ("Chicago", "https://proxy.uchicago.edu/login?url=")
    ]
}

// MARK: - PDF Settings Store

/// Actor-based store for PDF settings
/// Uses UserDefaults for persistence with in-memory caching
public actor PDFSettingsStore {
    public static let shared = PDFSettingsStore()

    private let userDefaults: UserDefaults
    private let settingsKey = "pdfSettings"
    private var cachedSettings: PDFSettings?

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Get current settings (cached or loaded from UserDefaults)
    public var settings: PDFSettings {
        if let cached = cachedSettings {
            return cached
        }
        let loaded = loadSettings()
        cachedSettings = loaded
        return loaded
    }

    /// Load settings from UserDefaults
    private func loadSettings() -> PDFSettings {
        guard let data = userDefaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(PDFSettings.self, from: data) else {
            Logger.files.infoCapture("No PDF settings found, using defaults", category: "pdf")
            return .default
        }
        Logger.files.infoCapture("Loaded PDF settings: priority=\(settings.sourcePriority.rawValue), proxy=\(settings.proxyEnabled)", category: "pdf")
        return settings
    }

    /// Save settings to UserDefaults
    private func saveSettings(_ settings: PDFSettings) {
        cachedSettings = settings
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: settingsKey)
            Logger.files.infoCapture("Saved PDF settings: priority=\(settings.sourcePriority.rawValue), proxy=\(settings.proxyEnabled)", category: "pdf")
        }
    }

    /// Update PDF source priority
    public func updateSourcePriority(_ priority: PDFSourcePriority) {
        var current = settings
        current.sourcePriority = priority
        saveSettings(current)
    }

    /// Update library proxy settings
    public func updateLibraryProxy(url: String, enabled: Bool) {
        var current = settings
        current.libraryProxyURL = url
        current.proxyEnabled = enabled
        saveSettings(current)
    }

    /// Reset settings to defaults
    public func reset() {
        userDefaults.removeObject(forKey: settingsKey)
        cachedSettings = nil
        Logger.files.infoCapture("Reset PDF settings to defaults", category: "pdf")
    }

    /// Clear cached settings (for testing)
    public func clearCache() {
        cachedSettings = nil
    }
}
