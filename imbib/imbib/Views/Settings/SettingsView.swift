//
//  SettingsView.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore

struct SettingsView: View {

    // MARK: - State

    @State private var selectedTab: SettingsTab = .general

    // MARK: - Body

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)

            ViewingSettingsTab()
                .tabItem { Label("Viewing", systemImage: "eye") }
                .tag(SettingsTab.viewing)

            NotesSettingsTab()
                .tabItem { Label("Notes", systemImage: "note.text") }
                .tag(SettingsTab.notes)

            SourcesSettingsTab()
                .tabItem { Label("Sources", systemImage: "globe") }
                .tag(SettingsTab.sources)

            PDFSettingsTab()
                .tabItem { Label("PDF", systemImage: "doc.richtext") }
                .tag(SettingsTab.pdf)

            InboxSettingsTab()
                .tabItem { Label("Inbox", systemImage: "tray") }
                .tag(SettingsTab.inbox)

            ImportExportSettingsTab()
                .tabItem { Label("Import/Export", systemImage: "arrow.up.arrow.down") }
                .tag(SettingsTab.importExport)
        }
        .frame(width: 550, height: 500)
    }
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable {
    case general
    case viewing
    case notes
    case sources
    case pdf
    case inbox
    case importExport
}

// MARK: - General Settings

struct GeneralSettingsTab: View {

    @Environment(SettingsViewModel.self) private var viewModel

    @AppStorage("libraryLocation") private var libraryLocation: String = ""
    @AppStorage("openPDFInExternalViewer") private var openPDFExternally = false

    var body: some View {
        Form {
            Section("Library") {
                HStack {
                    TextField("Library Location", text: $libraryLocation)
                        .disabled(true)

                    Button("Choose...") {
                        chooseLibraryLocation()
                    }
                }

                Toggle("Open PDFs in external viewer", isOn: $openPDFExternally)
            }

            Section("Smart Search") {
                HStack {
                    Text("Default result limit:")

                    TextField(
                        "Limit",
                        value: Binding(
                            get: { Int(viewModel.smartSearchSettings.defaultMaxResults) },
                            set: { newValue in
                                let clamped = max(10, min(30000, newValue))
                                Task {
                                    await viewModel.updateDefaultMaxResults(Int16(clamped))
                                }
                            }
                        ),
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)

                    Stepper(
                        "",
                        value: Binding(
                            get: { Int(viewModel.smartSearchSettings.defaultMaxResults) },
                            set: { newValue in
                                Task {
                                    await viewModel.updateDefaultMaxResults(Int16(newValue))
                                }
                            }
                        ),
                        in: 10...30000,
                        step: 50
                    )
                    .labelsHidden()
                }

                Text("Maximum records to retrieve per smart search query (10–30000)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
        .padding()
        .task {
            await viewModel.loadSmartSearchSettings()
        }
    }

    private func chooseLibraryLocation() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            libraryLocation = url.path
        }
        #endif
    }
}

// MARK: - Sources Settings

struct SourcesSettingsTab: View {

    @Environment(SettingsViewModel.self) private var viewModel

    var body: some View {
        List {
            ForEach(viewModel.sourceCredentials) { info in
                SourceCredentialRow(info: info)
            }
        }
        .task {
            await viewModel.loadCredentialStatus()
        }
    }
}

// MARK: - Source Credential Row

struct SourceCredentialRow: View {
    let info: SourceCredentialInfo

    @Environment(SettingsViewModel.self) private var viewModel

    @State private var isExpanded = false
    @State private var apiKeyInput = ""
    @State private var emailInput = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                // API Key input (if required or optional)
                if requiresAPIKey {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            SecureField("Enter API key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)

                            Button("Save") {
                                saveAPIKey()
                            }
                            .disabled(apiKeyInput.isEmpty)
                        }
                    }
                }

                // Email input (if required or optional)
                if requiresEmail {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email (for API identification)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField("Enter email", text: $emailInput)
                                .textFieldStyle(.roundedBorder)

                            Button("Save") {
                                saveEmail()
                            }
                            .disabled(emailInput.isEmpty)
                        }
                    }
                }

                // Registration link
                if let url = info.registrationURL {
                    Link("Get API Key", destination: url)
                        .font(.caption)
                }

                // Error message
                if showError {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 8)
        } label: {
            HStack {
                Text(info.sourceName)
                    .font(.headline)

                Spacer()

                statusBadge
            }
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
            return "No credentials needed"
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

// MARK: - Inbox Settings

struct InboxSettingsTab: View {

    @Environment(SettingsViewModel.self) private var viewModel

    @State private var mutedItems: [CDMutedItem] = []
    @State private var selectedMuteType: CDMutedItem.MuteType = .author
    @State private var newMuteValue: String = ""

    var body: some View {
        Form {
            Section("Age Limit") {
                Picker("Keep papers for", selection: Binding(
                    get: { viewModel.inboxSettings.ageLimit },
                    set: { newValue in
                        Task {
                            await viewModel.updateInboxAgeLimit(newValue)
                        }
                    }
                )) {
                    ForEach(AgeLimitPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                Text("Papers older than this limit (based on when they were added to the Inbox) will be hidden")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Muted Items") {
                if mutedItems.isEmpty {
                    Text("No muted items")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    List {
                        ForEach(groupedMutedItems.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { muteType in
                            Section(muteType.displayName) {
                                ForEach(groupedMutedItems[muteType] ?? [], id: \.id) { item in
                                    MutedItemRow(item: item) {
                                        unmute(item)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 200)
                }
            }

            Section("Add Mute Rule") {
                Picker("Type", selection: $selectedMuteType) {
                    ForEach(CDMutedItem.MuteType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    TextField(placeholderText, text: $newMuteValue)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        addMuteRule()
                    }
                    .disabled(newMuteValue.isEmpty)
                }

                Text(helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Actions") {
                Button("Clear All Muted Items", role: .destructive) {
                    clearAllMutedItems()
                }
                .disabled(mutedItems.isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await viewModel.loadInboxSettings()
            loadMutedItems()
        }
    }

    // MARK: - Grouped Items

    private var groupedMutedItems: [CDMutedItem.MuteType: [CDMutedItem]] {
        Dictionary(grouping: mutedItems) { item in
            item.muteType ?? .author
        }
    }

    // MARK: - Placeholder Text

    private var placeholderText: String {
        switch selectedMuteType {
        case .author:
            return "Author name (e.g., Einstein)"
        case .doi:
            return "DOI (e.g., 10.1234/example)"
        case .bibcode:
            return "Bibcode (e.g., 2024ApJ...123..456E)"
        case .venue:
            return "Venue name (e.g., Nature)"
        case .arxivCategory:
            return "arXiv category (e.g., astro-ph.CO)"
        }
    }

    private var helpText: String {
        switch selectedMuteType {
        case .author:
            return "Papers by this author will be hidden from Inbox feeds"
        case .doi:
            return "This specific paper will be hidden"
        case .bibcode:
            return "This specific paper (by ADS bibcode) will be hidden"
        case .venue:
            return "Papers from journals/conferences containing this name will be hidden"
        case .arxivCategory:
            return "Papers from this arXiv category will be hidden"
        }
    }

    // MARK: - Actions

    private func loadMutedItems() {
        mutedItems = InboxManager.shared.mutedItems
    }

    private func addMuteRule() {
        guard !newMuteValue.isEmpty else { return }
        InboxManager.shared.mute(type: selectedMuteType, value: newMuteValue)
        newMuteValue = ""
        loadMutedItems()
    }

    private func unmute(_ item: CDMutedItem) {
        InboxManager.shared.unmute(item)
        loadMutedItems()
    }

    private func clearAllMutedItems() {
        InboxManager.shared.clearAllMutedItems()
        loadMutedItems()
    }
}

// MARK: - Muted Item Row

struct MutedItemRow: View {
    let item: CDMutedItem
    let onUnmute: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.value)
                    .font(.body)

                Text("Added \(item.dateAdded.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onUnmute()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Unmute")
        }
    }
}

// MARK: - MuteType Display Name

extension CDMutedItem.MuteType {
    var displayName: String {
        switch self {
        case .author: return "Authors"
        case .doi: return "Papers (DOI)"
        case .bibcode: return "Papers (Bibcode)"
        case .venue: return "Venues"
        case .arxivCategory: return "arXiv Categories"
        }
    }
}

// MARK: - Import/Export Settings

struct ImportExportSettingsTab: View {

    @AppStorage("autoGenerateCiteKeys") private var autoGenerateCiteKeys = true
    @AppStorage("defaultEntryType") private var defaultEntryType = "article"
    @AppStorage("exportPreserveRawBibTeX") private var preserveRawBibTeX = true

    var body: some View {
        Form {
            Section("Import") {
                Toggle("Auto-generate cite keys", isOn: $autoGenerateCiteKeys)

                Picker("Default entry type", selection: $defaultEntryType) {
                    Text("Article").tag("article")
                    Text("Book").tag("book")
                    Text("InProceedings").tag("inproceedings")
                    Text("Misc").tag("misc")
                }
            }

            Section("Export") {
                Toggle("Preserve original BibTeX formatting", isOn: $preserveRawBibTeX)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
        .environment(SettingsViewModel(
            sourceManager: SourceManager(),
            credentialManager: CredentialManager()
        ))
}
