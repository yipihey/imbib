//
//  IOSSettingsView.swift
//  imbib-iOS
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI
import PublicationManagerCore

/// iOS settings view presented as a sheet.
struct IOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsViewModel.self) private var viewModel

    var body: some View {
        NavigationStack {
            List {
                // Sources Section
                Section("Sources") {
                    NavigationLink {
                        SourcesSettingsView()
                    } label: {
                        Label("API Keys", systemImage: "key")
                    }
                }

                // PDF Settings
                Section("PDF") {
                    NavigationLink {
                        PDFSettingsView()
                    } label: {
                        Label("PDF Settings", systemImage: "doc")
                    }
                }

                // Search Settings
                Section("Search") {
                    NavigationLink {
                        SearchSettingsView()
                    } label: {
                        Label("Search Settings", systemImage: "magnifyingglass")
                    }
                }

                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Sources Settings

struct SourcesSettingsView: View {
    @Environment(SettingsViewModel.self) private var viewModel

    var body: some View {
        List {
            ForEach(viewModel.sourceCredentials) { info in
                IOSSourceCredentialRow(info: info)
            }
        }
        .navigationTitle("API Keys")
        .task {
            await viewModel.loadCredentialStatus()
        }
    }
}

// MARK: - iOS Source Credential Row

struct IOSSourceCredentialRow: View {
    let info: SourceCredentialInfo

    @Environment(SettingsViewModel.self) private var viewModel

    @State private var apiKeyInput = ""
    @State private var emailInput = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Section {
            // Status
            HStack {
                Text("Status")
                Spacer()
                statusBadge
            }

            // API Key input (if required or optional)
            if requiresAPIKey {
                SecureField("API Key", text: $apiKeyInput)
                    .textContentType(.password)

                Button("Save API Key") {
                    saveAPIKey()
                }
                .disabled(apiKeyInput.isEmpty)
            }

            // Email input (if required or optional)
            if requiresEmail {
                TextField("Email", text: $emailInput)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)

                Button("Save Email") {
                    saveEmail()
                }
                .disabled(emailInput.isEmpty)
            }

            // Registration link
            if let url = info.registrationURL {
                Link("Get API Key", destination: url)
            }

            // No credentials needed message
            if !requiresAPIKey && !requiresEmail {
                Text("No API key required for this source")
                    .foregroundStyle(.secondary)
            }

            // Error message
            if showError {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        } header: {
            Text(info.sourceName)
        }
        .task {
            await loadExistingCredentials()
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch info.status {
        case .valid, .optionalValid:
            return .green
        case .missing, .invalid:
            return .red
        case .optionalMissing:
            return .orange
        case .notRequired:
            return .gray
        }
    }

    private var statusText: String {
        switch info.status {
        case .valid:
            return "Configured"
        case .optionalValid:
            return "Configured (optional)"
        case .missing:
            return "Required"
        case .invalid(let reason):
            return "Invalid: \(reason)"
        case .optionalMissing:
            return "Not configured"
        case .notRequired:
            return "Not required"
        }
    }

    // MARK: - Helpers

    private var requiresAPIKey: Bool {
        switch info.requirement {
        case .apiKey, .apiKeyOptional, .apiKeyAndEmail:
            return true
        case .none, .email, .emailOptional:
            return false
        }
    }

    private var requiresEmail: Bool {
        switch info.requirement {
        case .email, .emailOptional, .apiKeyAndEmail:
            return true
        case .none, .apiKey, .apiKeyOptional:
            return false
        }
    }

    private func loadExistingCredentials() async {
        if requiresAPIKey {
            if let key = await viewModel.getAPIKey(for: info.sourceID) {
                apiKeyInput = key
            }
        }
        if requiresEmail {
            if let email = await viewModel.getEmail(for: info.sourceID) {
                emailInput = email
            }
        }
    }

    private func saveAPIKey() {
        Task {
            do {
                try await viewModel.saveAPIKey(apiKeyInput, for: info.sourceID)
                showError = false
                await viewModel.loadCredentialStatus()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func saveEmail() {
        Task {
            do {
                try await viewModel.saveEmail(emailInput, for: info.sourceID)
                showError = false
                await viewModel.loadCredentialStatus()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - PDF Settings

struct PDFSettingsView: View {
    @State private var settings = PDFSettings.default
    @State private var customProxyURL = ""
    @State private var selectedProxyIndex: Int? = nil

    var body: some View {
        List {
            // Source Priority
            Section {
                Picker("PDF Source Priority", selection: $settings.sourcePriority) {
                    Text("Preprint First (arXiv)").tag(PDFSourcePriority.preprint)
                    Text("Publisher First").tag(PDFSourcePriority.publisher)
                }
            } header: {
                Text("Source Priority")
            } footer: {
                Text("Choose whether to prefer preprint versions (faster, open access) or publisher versions.")
            }

            // Library Proxy
            Section {
                Toggle("Enable Library Proxy", isOn: $settings.proxyEnabled)

                if settings.proxyEnabled {
                    Picker("Preset", selection: $selectedProxyIndex) {
                        Text("Custom").tag(nil as Int?)
                        ForEach(Array(PDFSettings.commonProxies.enumerated()), id: \.offset) { index, proxy in
                            Text(proxy.name).tag(index as Int?)
                        }
                    }

                    TextField("Proxy URL", text: $customProxyURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                }
            } header: {
                Text("Library Proxy")
            } footer: {
                Text("Use your institution's library proxy to access paywalled PDFs.")
            }
        }
        .navigationTitle("PDF Settings")
        .task {
            settings = await PDFSettingsStore.shared.settings
            customProxyURL = settings.libraryProxyURL
            selectedProxyIndex = PDFSettings.commonProxies.firstIndex { $0.url == settings.libraryProxyURL }
        }
        .onChange(of: settings.sourcePriority) { _, _ in
            saveSettings()
        }
        .onChange(of: settings.proxyEnabled) { _, _ in
            saveSettings()
        }
        .onChange(of: selectedProxyIndex) { _, newValue in
            if let index = newValue {
                customProxyURL = PDFSettings.commonProxies[index].url
            }
            saveSettings()
        }
        .onChange(of: customProxyURL) { _, _ in
            saveSettings()
        }
    }

    private func saveSettings() {
        Task {
            await PDFSettingsStore.shared.updateSourcePriority(settings.sourcePriority)
            await PDFSettingsStore.shared.updateLibraryProxy(url: customProxyURL, enabled: settings.proxyEnabled)
        }
    }
}

// MARK: - Search Settings

struct SearchSettingsView: View {
    @Environment(SettingsViewModel.self) private var viewModel
    @State private var maxResults: Int = 100

    var body: some View {
        List {
            Section {
                Stepper(
                    "Results: \(maxResults)",
                    value: $maxResults,
                    in: 10...30000,
                    step: 50
                )
            } header: {
                Text("Smart Search Results")
            } footer: {
                Text("Maximum number of results to fetch per smart search query (10–30000).")
            }
        }
        .navigationTitle("Search Settings")
        .task {
            await viewModel.loadSmartSearchSettings()
            maxResults = Int(viewModel.smartSearchSettings.defaultMaxResults)
        }
        .onChange(of: maxResults) { _, newValue in
            Task {
                await viewModel.updateDefaultMaxResults(Int16(newValue))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    IOSSettingsView()
        .environment(SettingsViewModel(
            sourceManager: SourceManager(),
            credentialManager: CredentialManager()
        ))
}
