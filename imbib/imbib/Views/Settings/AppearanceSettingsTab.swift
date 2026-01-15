//
//  AppearanceSettingsTab.swift
//  imbib
//
//  Created by Claude on 2026-01-14.
//

import SwiftUI
import PublicationManagerCore

// MARK: - Appearance Settings Tab

/// Settings tab for customizing app appearance and themes
struct AppearanceSettingsTab: View {

    // MARK: - State

    @State private var settings: ThemeSettings = ThemeSettingsStore.loadSettingsSync()
    @State private var showAdvanced = false

    // MARK: - Body

    var body: some View {
        Form {
            // Theme Selection
            Section {
                themePicker
            } header: {
                Text("Theme")
            } footer: {
                Text("Choose a predefined theme or customize colors")
            }

            // Accent Color
            Section("Accent Color") {
                accentColorPicker
            }

            // Advanced Options
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                advancedOptions
            }

            // Reset
            Section {
                resetButton
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            settings = await ThemeSettingsStore.shared.settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .themeSettingsDidChange)) { _ in
            Task {
                settings = await ThemeSettingsStore.shared.settings
            }
        }
    }

    // MARK: - Theme Picker

    private var themePicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 130))], spacing: 12) {
            ForEach(ThemeID.allCases.filter { $0 != .custom }, id: \.self) { themeID in
                ThemePreviewCard(
                    themeID: themeID,
                    isSelected: settings.themeID == themeID
                )
                .onTapGesture {
                    selectTheme(themeID)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Accent Color Picker

    private var accentColorPicker: some View {
        HStack {
            Text("Accent Color")
            Spacer()
            ColorPicker("", selection: accentColorBinding)
                .labelsHidden()
            Text(settings.accentColorHex)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 70)
        }
    }

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

    // MARK: - Advanced Options

    private var advancedOptions: some View {
        Group {
            // Unread Dot Color
            Section("Unread Indicator") {
                HStack {
                    Text("Dot Color")
                    Spacer()
                    ColorPicker("", selection: unreadDotColorBinding)
                        .labelsHidden()
                    Text(settings.unreadDotColorHex ?? settings.accentColorHex)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 70)
                }
            }

            // Sidebar Style
            Section("Sidebar") {
                Picker("Style", selection: $settings.sidebarStyle) {
                    ForEach(SidebarStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .onChange(of: settings.sidebarStyle) { _, _ in
                    settings.themeID = .custom
                    settings.isCustom = true
                    saveSettings()
                }

                if settings.sidebarStyle != .system {
                    HStack {
                        Text("Tint Color")
                        Spacer()
                        ColorPicker("", selection: sidebarTintBinding)
                            .labelsHidden()
                    }
                }
            }

            // List Background
            Section("List Background") {
                HStack {
                    Text("Background Tint")
                    Spacer()
                    ColorPicker("", selection: listBackgroundTintBinding)
                        .labelsHidden()
                }

                HStack {
                    Text("Tint Intensity")
                    Slider(value: $settings.listBackgroundTintOpacity, in: 0...0.1, step: 0.01)
                        .onChange(of: settings.listBackgroundTintOpacity) { _, _ in
                            settings.themeID = .custom
                            settings.isCustom = true
                            saveSettings()
                        }
                    Text("\(Int(settings.listBackgroundTintOpacity * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 35)
                }
            }

            // Typography
            Section("Typography") {
                Toggle("Use serif fonts for titles", isOn: $settings.useSerifTitles)
                    .onChange(of: settings.useSerifTitles) { _, _ in
                        settings.themeID = .custom
                        settings.isCustom = true
                        saveSettings()
                    }
            }
        }
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

    private var sidebarTintBinding: Binding<Color> {
        Binding(
            get: { Color(hex: settings.sidebarTintHex ?? settings.accentColorHex) ?? .accentColor },
            set: { newColor in
                settings.sidebarTintHex = newColor.hexString
                settings.themeID = .custom
                settings.isCustom = true
                saveSettings()
            }
        )
    }

    private var listBackgroundTintBinding: Binding<Color> {
        Binding(
            get: { Color(hex: settings.listBackgroundTintHex ?? "#FFFFFF") ?? .white },
            set: { newColor in
                settings.listBackgroundTintHex = newColor.hexString
                settings.themeID = .custom
                settings.isCustom = true
                saveSettings()
            }
        )
    }

    // MARK: - Reset Button

    private var resetButton: some View {
        Button("Reset to Default Theme") {
            Task {
                await ThemeSettingsStore.shared.reset()
                settings = await ThemeSettingsStore.shared.settings
            }
        }
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

// MARK: - Theme Preview Card

struct ThemePreviewCard: View {
    let themeID: ThemeID
    let isSelected: Bool

    @State private var isHovered = false

    private var theme: ThemeSettings {
        ThemeSettings.predefined(themeID)
    }

    var body: some View {
        VStack(spacing: 6) {
            // Color swatch preview
            HStack(spacing: 4) {
                // Accent color
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: theme.accentColorHex) ?? .blue)
                    .frame(width: 30, height: 40)

                // Unread dot color
                Circle()
                    .fill(Color(hex: theme.unreadDotColorHex ?? theme.accentColorHex) ?? .blue)
                    .frame(width: 12, height: 12)

                // Sidebar tint (if applicable)
                if theme.sidebarStyle != .system, let tint = theme.sidebarTintHex {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: tint)?.opacity(0.3) ?? .clear)
                        .frame(width: 20, height: 40)
                }
            }
            .frame(height: 44)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )

            // Theme name
            Text(themeID.displayName)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AppearanceSettingsTab_Previews: PreviewProvider {
    static var previews: some View {
        AppearanceSettingsTab()
            .frame(width: 650, height: 550)
    }
}
#endif
