//
//  EnrichmentSettingsView.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI

// MARK: - Enrichment Settings View

/// A settings view for configuring publication enrichment behavior.
///
/// Allows users to:
/// - Set their preferred citation source
/// - Reorder source priority via drag-and-drop
/// - Enable/disable automatic background sync
/// - Set the refresh interval for stale data
///
/// ## Usage
///
/// ```swift
/// EnrichmentSettingsView(viewModel: settingsViewModel)
///     .task {
///         await viewModel.loadEnrichmentSettings()
///     }
/// ```
public struct EnrichmentSettingsView: View {

    // MARK: - Properties

    @Bindable public var viewModel: SettingsViewModel

    // MARK: - State

    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif

    // MARK: - Initialization

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body

    public var body: some View {
        Form {
            // Preferred Source Section
            Section {
                Picker("Preferred Source", selection: preferredSourceBinding) {
                    ForEach(EnrichmentSource.allCases) { source in
                        Text(source.displayName).tag(source)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Citation Display")
            } footer: {
                Text("The source used for displaying citation counts in your library.")
            }

            // Source Priority Section
            Section {
                ForEach(viewModel.enrichmentSettings.sourcePriority) { source in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)

                        Text(source.displayName)

                        Spacer()

                        if source == viewModel.enrichmentSettings.sourcePriority.first {
                            Text("Primary")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { indices, destination in
                    Task {
                        await moveSource(from: indices, to: destination)
                    }
                }
            } header: {
                HStack {
                    Text("Source Priority")
                    Spacer()
                    #if os(iOS)
                    Button(editMode == .active ? "Done" : "Edit") {
                        withAnimation {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                    .font(.caption)
                    #endif
                }
            } footer: {
                Text("Drag to reorder. The first available source will be used for enrichment.")
            }
            #if os(iOS)
            .environment(\.editMode, $editMode)
            #endif

            // Auto-Sync Section
            Section {
                Toggle("Enable Background Sync", isOn: autoSyncBinding)

                if viewModel.enrichmentSettings.autoSyncEnabled {
                    Picker("Refresh Interval", selection: refreshIntervalBinding) {
                        Text("Daily").tag(1)
                        Text("Every 3 Days").tag(3)
                        Text("Weekly").tag(7)
                        Text("Every 2 Weeks").tag(14)
                        Text("Monthly").tag(30)
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Background Sync")
            } footer: {
                if viewModel.enrichmentSettings.autoSyncEnabled {
                    Text("Papers older than \(viewModel.enrichmentSettings.refreshIntervalDays) days will be automatically refreshed.")
                } else {
                    Text("Enrichment data will only be fetched when you manually refresh.")
                }
            }

            // Reset Section
            Section {
                Button("Reset to Defaults", role: .destructive) {
                    Task {
                        await viewModel.resetEnrichmentSettingsToDefaults()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Enrichment")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Bindings

    private var preferredSourceBinding: Binding<EnrichmentSource> {
        Binding(
            get: { viewModel.enrichmentSettings.preferredSource },
            set: { newValue in
                Task {
                    await viewModel.updatePreferredSource(newValue)
                }
            }
        )
    }

    private var autoSyncBinding: Binding<Bool> {
        Binding(
            get: { viewModel.enrichmentSettings.autoSyncEnabled },
            set: { newValue in
                Task {
                    await viewModel.updateAutoSyncEnabled(newValue)
                }
            }
        )
    }

    private var refreshIntervalBinding: Binding<Int> {
        Binding(
            get: { viewModel.enrichmentSettings.refreshIntervalDays },
            set: { newValue in
                Task {
                    await viewModel.updateRefreshIntervalDays(newValue)
                }
            }
        )
    }

    // MARK: - Actions

    private func moveSource(from indices: IndexSet, to destination: Int) async {
        var priority = viewModel.enrichmentSettings.sourcePriority
        priority.move(fromOffsets: indices, toOffset: destination)
        await viewModel.updateSourcePriority(priority)
    }
}

// MARK: - Source Priority Row

/// A row displaying a source with drag handle for reordering
public struct SourcePriorityRow: View {

    public let source: EnrichmentSource
    public let isPrimary: Bool

    public init(source: EnrichmentSource, isPrimary: Bool = false) {
        self.source = source
        self.isPrimary = isPrimary
    }

    public var body: some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading) {
                Text(source.displayName)
                    .font(.body)

                Text(sourceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isPrimary {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var sourceDescription: String {
        switch source {
        case .ads:
            return "Astronomy publications, citations, references"
        }
    }
}

// MARK: - Compact Enrichment Settings

/// A compact version of enrichment settings for inline display
public struct CompactEnrichmentSettingsView: View {

    @Bindable public var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Preferred source
            HStack {
                Text("Citation Source:")
                    .foregroundStyle(.secondary)

                Picker("", selection: Binding(
                    get: { viewModel.enrichmentSettings.preferredSource },
                    set: { newValue in Task { await viewModel.updatePreferredSource(newValue) } }
                )) {
                    ForEach(EnrichmentSource.allCases) { source in
                        Text(source.displayName).tag(source)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            // Auto-sync toggle
            Toggle("Auto-sync citations", isOn: Binding(
                get: { viewModel.enrichmentSettings.autoSyncEnabled },
                set: { newValue in Task { await viewModel.updateAutoSyncEnabled(newValue) } }
            ))
            .toggleStyle(.switch)
        }
        .padding()
    }
}

// MARK: - Preview

#Preview("Enrichment Settings") {
    NavigationStack {
        EnrichmentSettingsView(viewModel: SettingsViewModel())
    }
}

#Preview("Compact Settings") {
    CompactEnrichmentSettingsView(viewModel: SettingsViewModel())
        .frame(width: 300)
}
