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
                .help("App preferences")

            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(SettingsTab.appearance)
                .help("Theme and colors")

            ViewingSettingsTab()
                .tabItem { Label("Viewing", systemImage: "eye") }
                .tag(SettingsTab.viewing)
                .help("List display options")

            NotesSettingsTab()
                .tabItem { Label("Notes", systemImage: "note.text") }
                .tag(SettingsTab.notes)
                .help("Note editor settings")

            SourcesSettingsTab()
                .tabItem { Label("Sources", systemImage: "globe") }
                .tag(SettingsTab.sources)
                .help("API keys for online sources")

            PDFSettingsTab()
                .tabItem { Label("PDF", systemImage: "doc.richtext") }
                .tag(SettingsTab.pdf)
                .help("PDF download settings")

            InboxSettingsTab()
                .tabItem { Label("Inbox", systemImage: "tray") }
                .tag(SettingsTab.inbox)
                .help("Feed subscriptions and mute rules")

            ImportExportSettingsTab()
                .tabItem { Label("Import/Export", systemImage: "arrow.up.arrow.down") }
                .tag(SettingsTab.importExport)
                .help("File format options")

            KeyboardShortcutsSettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.keyboardShortcuts)
                .help("Customize keyboard shortcuts")

            AdvancedSettingsTab()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
                .tag(SettingsTab.advanced)
                .help("Developer tools and advanced settings")
        }
        .frame(width: 650, height: 550)
    }
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable {
    case general
    case appearance
    case viewing
    case notes
    case sources
    case pdf
    case inbox
    case importExport
    case keyboardShortcuts
    case advanced
}

// MARK: - General Settings

struct GeneralSettingsTab: View {

    @Environment(SettingsViewModel.self) private var viewModel

    @AppStorage("libraryLocation") private var libraryLocation: String = ""
    @AppStorage("openPDFInExternalViewer") private var openPDFExternally = false

    @State private var automationSettings = AutomationSettings.default

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

            Section("Automation") {
                Toggle("Enable automation API", isOn: $automationSettings.isEnabled)
                    .help("Allow external programs and AI agents to control imbib via URL schemes")
                    .onChange(of: automationSettings.isEnabled) { _, _ in
                        saveAutomationSettings()
                    }

                Toggle("Log automation requests", isOn: $automationSettings.logRequests)
                    .help("Record automation commands in the Console window")
                    .disabled(!automationSettings.isEnabled)
                    .onChange(of: automationSettings.logRequests) { _, _ in
                        saveAutomationSettings()
                    }

                Text("When enabled, imbib responds to `imbib://` URL commands from CLI tools and AI agents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
        .padding()
        .task {
            await viewModel.loadSmartSearchSettings()
            automationSettings = await AutomationSettingsStore.shared.settings
        }
    }

    private func saveAutomationSettings() {
        Task {
            await AutomationSettingsStore.shared.update(automationSettings)
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
                        .help("Get API key from source website")
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
                .help(statusTooltip)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusTooltip: String {
        switch info.status {
        case .valid, .optionalValid:
            return "API key configured"
        case .missing, .invalid:
            return "API key required"
        case .optionalMissing:
            return "Optional - enhances results"
        case .notRequired:
            return "No credentials needed"
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
    @Environment(LibraryManager.self) private var libraryManager

    @State private var mutedItems: [CDMutedItem] = []
    @State private var dismissedPaperCount: Int = 0
    @State private var selectedMuteType: CDMutedItem.MuteType = .author
    @State private var newMuteValue: String = ""
    @State private var selectedArchiveLibraryID: UUID?

    var body: some View {
        Form {
            Section("Archive Destination") {
                Picker("Archive to", selection: $selectedArchiveLibraryID) {
                    Text("Auto (create Archive library)").tag(nil as UUID?)
                    ForEach(availableArchiveLibraries, id: \.id) { library in
                        Text(library.displayName).tag(library.id as UUID?)
                    }
                }
                .onChange(of: selectedArchiveLibraryID) { _, newValue in
                    saveArchiveLibrarySetting(newValue)
                }

                Text("When you press A on a paper in the Inbox, it will be moved to this library")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                .help("Hide papers older than this")

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
                .help("Choose what type of content to mute")

                HStack {
                    TextField(placeholderText, text: $newMuteValue)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        addMuteRule()
                    }
                    .disabled(newMuteValue.isEmpty)
                    .help("Add this mute rule")
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
                .help("Remove all mute rules")

                Button("Clear Dismissed Papers (\(dismissedPaperCount))", role: .destructive) {
                    clearDismissedPapers()
                }
                .disabled(dismissedPaperCount == 0)
                .help("Allow previously dismissed papers to reappear in feeds")

                Text("Dismissed papers are hidden from future feed results. Clear this to allow them to reappear.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await viewModel.loadInboxSettings()
            loadMutedItems()
            loadDismissedPaperCount()
            loadArchiveLibrarySetting()
        }
    }

    // MARK: - Archive Library

    /// Libraries available as archive destinations (excludes Inbox, Dismissed, system libraries)
    private var availableArchiveLibraries: [CDLibrary] {
        libraryManager.libraries.filter { library in
            !library.isInbox &&
            !library.isDismissedLibrary &&
            !library.isSystemLibrary
        }.sorted { $0.displayName < $1.displayName }
    }

    private func loadArchiveLibrarySetting() {
        selectedArchiveLibraryID = UserDefaults.standard.string(forKey: "archiveLibraryID")
            .flatMap { UUID(uuidString: $0) }
    }

    private func saveArchiveLibrarySetting(_ id: UUID?) {
        if let id = id {
            UserDefaults.standard.set(id.uuidString, forKey: "archiveLibraryID")
        } else {
            UserDefaults.standard.removeObject(forKey: "archiveLibraryID")
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

    private func loadDismissedPaperCount() {
        dismissedPaperCount = InboxManager.shared.dismissedPaperCount
    }

    private func clearDismissedPapers() {
        InboxManager.shared.clearAllDismissedPapers()
        loadDismissedPaperCount()
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

// MARK: - Advanced Settings

struct AdvancedSettingsTab: View {

    @State private var isOptionKeyPressed = false
    @State private var showingResetConfirmation = false
    @State private var showingResetInProgress = false
    @State private var resetError: String?
    @State private var showingDefaultSetEditor = false

    var body: some View {
        Form {
            // Developer section - visible when Option key is held
            if isOptionKeyPressed {
                Section("Developer") {
                    Button("Reset to First Run...", role: .destructive) {
                        showingResetConfirmation = true
                    }
                    .disabled(showingResetInProgress)
                    .help("Delete all libraries, papers, and settings (preserves API keys)")

                    Button("Edit Default Library Set...") {
                        showingDefaultSetEditor = true
                    }
                    .help("Configure what new users see on first launch")

                    Text("Hold Option key to show these options")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Developer") {
                    Text("Hold the Option key to reveal developer tools")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }

            Section("Diagnostics") {
                HStack {
                    Text("First Run Status:")
                    Spacer()
                    Text(FirstRunManager.shared.isFirstRun ? "Yes" : "No")
                        .foregroundStyle(.secondary)
                }

                if let error = resetError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            startOptionKeyMonitoring()
        }
        .onDisappear {
            stopOptionKeyMonitoring()
        }
        .confirmationDialog(
            "Reset to First Run?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                performReset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all libraries, papers, collections, smart searches, and settings. API keys will be preserved.\n\nThe app will need to be restarted after the reset.")
        }
        .sheet(isPresented: $showingDefaultSetEditor) {
            DefaultLibrarySetEditor()
        }
        .overlay {
            if showingResetInProgress {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Resetting...")
                        .font(.headline)
                }
                .padding(40)
                .background(.regularMaterial)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Option Key Monitoring

    private var eventMonitor: Any?

    private func startOptionKeyMonitoring() {
        #if os(macOS)
        // Use a local event monitor to detect Option key state
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            isOptionKeyPressed = event.modifierFlags.contains(.option)
            return event
        }
        #endif
    }

    private func stopOptionKeyMonitoring() {
        // Local monitors are automatically removed when the view disappears
    }

    // MARK: - Reset Action

    private func performReset() {
        showingResetInProgress = true
        resetError = nil

        Task {
            do {
                try await FirstRunManager.shared.resetToFirstRun()
                showingResetInProgress = false

                // Show alert that restart is needed
                #if os(macOS)
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Reset Complete"
                    alert.informativeText = "The app has been reset to first-run state. Please restart the app to complete the process."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "Quit Now")
                    alert.addButton(withTitle: "Later")

                    if alert.runModal() == .alertFirstButtonReturn {
                        NSApplication.shared.terminate(nil)
                    }
                }
                #endif
            } catch {
                await MainActor.run {
                    showingResetInProgress = false
                    resetError = error.localizedDescription
                }
            }
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
