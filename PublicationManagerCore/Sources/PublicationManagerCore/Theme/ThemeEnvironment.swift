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
            #if os(macOS)
            .background(WindowBackgroundSetter(color: colors.detailBackground))
            #endif
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

// MARK: - macOS Window Background

#if os(macOS)
import AppKit

/// NSViewRepresentable that sets the window background color and titlebar appearance
struct WindowBackgroundSetter: NSViewRepresentable {
    let color: Color?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        DispatchQueue.main.async {
            updateWindowAppearance(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            updateWindowAppearance(for: nsView)
        }
    }

    private func updateWindowAppearance(for view: NSView) {
        guard let window = view.window else { return }

        if let color = color {
            // Convert SwiftUI Color to NSColor
            let nsColor = NSColor(color)
            window.backgroundColor = nsColor
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
        } else {
            // Reset to system default
            window.backgroundColor = nil
            window.titlebarAppearsTransparent = false
            window.isOpaque = true
        }
    }
}
#endif

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
