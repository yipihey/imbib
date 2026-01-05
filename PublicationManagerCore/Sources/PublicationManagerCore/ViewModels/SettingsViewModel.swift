//
//  SettingsViewModel.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog
import SwiftUI

// MARK: - Settings View Model

/// View model for application settings.
@MainActor
@Observable
public final class SettingsViewModel {

    // MARK: - Published State

    public private(set) var sourceCredentials: [SourceCredentialInfo] = []
    public private(set) var isLoading = false
    public private(set) var error: Error?

    // MARK: - Enrichment Settings State

    public private(set) var enrichmentSettings: EnrichmentSettings = .default
    public private(set) var isLoadingEnrichment = false

    // MARK: - Dependencies

    private let sourceManager: SourceManager
    private let credentialManager: CredentialManager
    private let enrichmentSettingsStore: EnrichmentSettingsStore

    // MARK: - Initialization

    public init(
        sourceManager: SourceManager = SourceManager(),
        credentialManager: CredentialManager = .shared,
        enrichmentSettingsStore: EnrichmentSettingsStore = .shared
    ) {
        self.sourceManager = sourceManager
        self.credentialManager = credentialManager
        self.enrichmentSettingsStore = enrichmentSettingsStore
    }

    // MARK: - Loading

    public func loadCredentialStatus() async {
        Logger.viewModels.entering()
        defer { Logger.viewModels.exiting() }

        isLoading = true
        sourceCredentials = await sourceManager.credentialStatus()
        isLoading = false
    }

    // MARK: - Credential Management

    public func saveAPIKey(_ apiKey: String, for sourceID: String) async throws {
        Logger.viewModels.info("Saving API key for \(sourceID)")

        guard credentialManager.validate(apiKey, type: .apiKey) else {
            throw CredentialError.invalid("Invalid API key format")
        }

        try await credentialManager.storeAPIKey(apiKey, for: sourceID)
        await loadCredentialStatus()
    }

    public func saveEmail(_ email: String, for sourceID: String) async throws {
        Logger.viewModels.info("Saving email for \(sourceID)")

        guard credentialManager.validate(email, type: .email) else {
            throw CredentialError.invalid("Invalid email format")
        }

        try await credentialManager.storeEmail(email, for: sourceID)
        await loadCredentialStatus()
    }

    public func deleteCredentials(for sourceID: String) async {
        Logger.viewModels.info("Deleting credentials for \(sourceID)")

        await credentialManager.deleteAll(for: sourceID)
        await loadCredentialStatus()
    }

    public func getAPIKey(for sourceID: String) async -> String? {
        await credentialManager.apiKey(for: sourceID)
    }

    public func getEmail(for sourceID: String) async -> String? {
        await credentialManager.email(for: sourceID)
    }

    // MARK: - Enrichment Settings

    /// Load current enrichment settings
    public func loadEnrichmentSettings() async {
        isLoadingEnrichment = true
        enrichmentSettings = await enrichmentSettingsStore.settings
        isLoadingEnrichment = false
    }

    /// Update the preferred enrichment source
    public func updatePreferredSource(_ source: EnrichmentSource) async {
        await enrichmentSettingsStore.updatePreferredSource(source)
        enrichmentSettings = await enrichmentSettingsStore.settings
        Logger.enrichment.infoCapture(
            "Preferred citation source changed to \(source.displayName)",
            category: "enrichment"
        )
    }

    /// Update the source priority order
    public func updateSourcePriority(_ priority: [EnrichmentSource]) async {
        await enrichmentSettingsStore.updateSourcePriority(priority)
        enrichmentSettings = await enrichmentSettingsStore.settings
        Logger.enrichment.infoCapture(
            "Source priority updated: \(priority.map { $0.displayName }.joined(separator: " → "))",
            category: "enrichment"
        )
    }

    /// Move a source to a new position in the priority list
    public func moveSource(_ source: EnrichmentSource, to index: Int) async {
        await enrichmentSettingsStore.moveSource(source, to: index)
        enrichmentSettings = await enrichmentSettingsStore.settings
    }

    /// Update auto-sync enabled setting
    public func updateAutoSyncEnabled(_ enabled: Bool) async {
        await enrichmentSettingsStore.updateAutoSyncEnabled(enabled)
        enrichmentSettings = await enrichmentSettingsStore.settings
        Logger.enrichment.infoCapture(
            "Background sync \(enabled ? "enabled" : "disabled")",
            category: "enrichment"
        )
    }

    /// Update refresh interval in days
    public func updateRefreshIntervalDays(_ days: Int) async {
        await enrichmentSettingsStore.updateRefreshIntervalDays(days)
        enrichmentSettings = await enrichmentSettingsStore.settings
        Logger.enrichment.infoCapture(
            "Enrichment refresh interval set to \(days) days",
            category: "enrichment"
        )
    }

    /// Reset enrichment settings to defaults
    public func resetEnrichmentSettingsToDefaults() async {
        await enrichmentSettingsStore.resetToDefaults()
        enrichmentSettings = await enrichmentSettingsStore.settings
        Logger.enrichment.infoCapture(
            "Enrichment settings reset to defaults",
            category: "enrichment"
        )
    }
}
