//
//  IOSAppearanceSettingsView.swift
//  imbib-iOS
//
//  Created by Claude on 2026-01-14.
//

import SwiftUI
import PublicationManagerCore

/// iOS settings view for theme and appearance customization
struct IOSAppearanceSettingsView: View {

    // MARK: - State

    @State private var settings: ThemeSettings = ThemeSettingsStore.loadSettingsSync()

    // MARK: - Body

    var body: some View {
        List {
            // Theme Selection
            Section {
                ForEach(ThemeID.allCases.filter { $0 != .custom }, id: \.self) { themeID in
                    themeRow(for: themeID)
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("Choose a visual theme for the app")
            }

            // Accent Color
            Section {
                ColorPicker("Accent Color", selection: accentColorBinding)
            } header: {
                Text("Customization")
            } footer: {
                Text("Custom accent color overrides the selected theme")
            }

            // Unread Indicator
            Section("Unread Indicator") {
                ColorPicker("Dot Color", selection: unreadDotColorBinding)
            }

            // Links
            Section("Links") {
                ColorPicker("Link Color", selection: linkColorBinding)
            }

            // Reset
            Section {
                Button("Reset to Default") {
                    Task {
                        await ThemeSettingsStore.shared.reset()
                        settings = await ThemeSettingsStore.shared.settings
                    }
                }
            }
        }
        .navigationTitle("Appearance")
        .task {
            settings = await ThemeSettingsStore.shared.settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .themeSettingsDidChange)) { _ in
            Task {
                settings = await ThemeSettingsStore.shared.settings
            }
        }
    }

    // MARK: - Theme Row

    private func themeRow(for themeID: ThemeID) -> some View {
        let theme = ThemeSettings.predefined(themeID)

        return HStack {
            // Color swatch
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: theme.accentColorHex) ?? .blue)
                    .frame(width: 20, height: 20)

                if let dotHex = theme.unreadDotColorHex, dotHex != theme.accentColorHex {
                    Circle()
                        .fill(Color(hex: dotHex) ?? .blue)
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: 40)

            // Name and description
            VStack(alignment: .leading, spacing: 2) {
                Text(themeID.displayName)
                    .font(.body)
                Text(themeID.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Checkmark for selected
            if settings.themeID == themeID {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectTheme(themeID)
        }
    }

    // MARK: - Color Bindings

    private var accentColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: settings.accentColorHex) ?? .accentColor },
            set: { newColor in
                settings.accentColorHex = newColor.hexString
                settings.themeID = .custom
                settings.isCustom = true
                saveSettings()
            }
        )
    }

    private var unreadDotColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: settings.unreadDotColorHex ?? settings.accentColorHex) ?? .blue },
            set: { newColor in
                settings.unreadDotColorHex = newColor.hexString
                settings.themeID = .custom
                settings.isCustom = true
                saveSettings()
            }
        )
    }

    private var linkColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: settings.linkColorHex ?? settings.accentColorHex) ?? .accentColor },
            set: { newColor in
                settings.linkColorHex = newColor.hexString
                settings.themeID = .custom
                settings.isCustom = true
                saveSettings()
            }
        )
    }

    // MARK: - Actions

    private func selectTheme(_ themeID: ThemeID) {
        Task {
            await ThemeSettingsStore.shared.applyTheme(themeID)
            settings = await ThemeSettingsStore.shared.settings
        }
    }

    private func saveSettings() {
        Task {
            await ThemeSettingsStore.shared.update(settings)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct IOSAppearanceSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            IOSAppearanceSettingsView()
        }
    }
}
#endif
