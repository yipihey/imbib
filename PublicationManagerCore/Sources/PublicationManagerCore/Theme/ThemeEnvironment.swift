//
//  ThemeEnvironment.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-14.
//

import SwiftUI

// MARK: - Theme Colors Environment Key

private struct ThemeColorsKey: EnvironmentKey {
    static let defaultValue = ThemeColors.default
}

public extension EnvironmentValues {
    /// The current theme colors resolved for the current color scheme
    var themeColors: ThemeColors {
        get { self[ThemeColorsKey.self] }
        set { self[ThemeColorsKey.self] = newValue }
    }
}

// MARK: - Theme Provider

/// View modifier that provides theme colors to the view hierarchy.
///
/// This modifier:
/// - Loads theme settings from ThemeSettingsStore
/// - Listens for theme change notifications
/// - Resolves colors based on current colorScheme (light/dark)
/// - Applies the system tint color
///
/// Usage:
/// ```swift
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///                 .withTheme()
///         }
///     }
/// }
/// ```
public struct ThemeProvider: ViewModifier {

    @Environment(\.colorScheme) private var colorScheme
    @State private var settings: ThemeSettings = ThemeSettingsStore.loadSettingsSync()

    public init() {}

    public func body(content: Content) -> some View {
        let colors = ThemeColors(from: settings, colorScheme: colorScheme)

        content
            .environment(\.themeColors, colors)
            .tint(colors.accent)
            .task {
                settings = await ThemeSettingsStore.shared.settings
            }
            .onReceive(NotificationCenter.default.publisher(for: .themeSettingsDidChange)) { _ in
                Task {
                    settings = await ThemeSettingsStore.shared.settings
                }
            }
    }
}

// MARK: - View Extension

public extension View {
    /// Apply the theme provider to inject theme colors into the environment
    func withTheme() -> some View {
        modifier(ThemeProvider())
    }
}

// MARK: - Preview Helper

/// A view modifier for previews that applies a specific theme
public struct PreviewTheme: ViewModifier {
    let themeID: ThemeID
    let colorScheme: ColorScheme

    public init(_ themeID: ThemeID, colorScheme: ColorScheme = .light) {
        self.themeID = themeID
        self.colorScheme = colorScheme
    }

    public func body(content: Content) -> some View {
        let settings = ThemeSettings.predefined(themeID)
        let colors = ThemeColors(from: settings, colorScheme: colorScheme)

        content
            .environment(\.themeColors, colors)
            .environment(\.colorScheme, colorScheme)
            .tint(colors.accent)
    }
}

public extension View {
    /// Apply a specific theme for previews
    func previewTheme(_ themeID: ThemeID, colorScheme: ColorScheme = .light) -> some View {
        modifier(PreviewTheme(themeID, colorScheme: colorScheme))
    }
}
