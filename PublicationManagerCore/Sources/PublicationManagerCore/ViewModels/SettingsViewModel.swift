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

    // MARK: - Dependencies

    private let sourceManager: SourceManager
    private let credentialManager: CredentialManager

    // MARK: - Initialization

    public init(
        sourceManager: SourceManager = SourceManager(),
        credentialManager: CredentialManager = CredentialManager()
    ) {
        self.sourceManager = sourceManager
        self.credentialManager = credentialManager
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
}
