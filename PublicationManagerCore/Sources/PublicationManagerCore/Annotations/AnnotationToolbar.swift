//
//  AnnotationToolbar.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-14.
//

import SwiftUI

// MARK: - Annotation Tool

/// Available annotation tools
public enum AnnotationTool: String, CaseIterable, Identifiable {
    case highlight
    case underline
    case strikethrough
    case textNote

    public var id: String { rawValue }

    /// SF Symbol name for this tool
    public var iconName: String {
        switch self {
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .strikethrough: return "strikethrough"
        case .textNote: return "note.text"
        }
    }

    /// Display name for tooltips
    public var displayName: String {
        switch self {
        case .highlight: return "Highlight"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        case .textNote: return "Add Note"
        }
    }

    /// Keyboard shortcut hint
    public var shortcutHint: String {
        switch self {
        case .highlight: return "H"
        case .underline: return "U"
        case .strikethrough: return "S"
        case .textNote: return "N"
        }
    }
}

// MARK: - Annotation Toolbar

/// Floating toolbar for PDF annotation tools.
///
/// Displays buttons for highlight, underline, strikethrough, and text notes,
/// along with a color picker for the current tool.
public struct AnnotationToolbar: View {

    // MARK: - Properties

    @Binding public var selectedTool: AnnotationTool?
    @Binding public var highlightColor: HighlightColor
    public var hasSelection: Bool
    public var onHighlight: () -> Void
    public var onUnderline: () -> Void
    public var onStrikethrough: () -> Void
    public var onAddNote: () -> Void

    // MARK: - Initialization

    public init(
        selectedTool: Binding<AnnotationTool?>,
        highlightColor: Binding<HighlightColor>,
        hasSelection: Bool,
        onHighlight: @escaping () -> Void,
        onUnderline: @escaping () -> Void,
        onStrikethrough: @escaping () -> Void,
        onAddNote: @escaping () -> Void
    ) {
        self._selectedTool = selectedTool
        self._highlightColor = highlightColor
        self.hasSelection = hasSelection
        self.onHighlight = onHighlight
        self.onUnderline = onUnderline
        self.onStrikethrough = onStrikethrough
        self.onAddNote = onAddNote
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: 12) {
            // Highlight with color menu
            highlightButton

            // Underline
            toolButton(
                tool: .underline,
                action: onUnderline
            )

            // Strikethrough
            toolButton(
                tool: .strikethrough,
                action: onStrikethrough
            )

            // Text note
            toolButton(
                tool: .textNote,
                action: onAddNote
            )

            Divider()
                .frame(height: 20)

            // Color picker
            colorPicker
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    }

    // MARK: - Highlight Button

    private var highlightButton: some View {
        Menu {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button {
                    highlightColor = color
                    onHighlight()
                } label: {
                    Label(color.displayName, systemImage: "circle.fill")
                }
            }
        } label: {
            Image(systemName: "highlighter")
                .font(.system(size: 16))
                .foregroundStyle(Color(highlightColor.platformColor))
                .frame(width: 28, height: 28)
        } primaryAction: {
            onHighlight()
        }
        .buttonStyle(.plain)
        .help("Highlight selection (\(AnnotationTool.highlight.shortcutHint))")
        .disabled(!hasSelection)
        .opacity(hasSelection ? 1.0 : 0.5)
    }

    // MARK: - Tool Button

    private func toolButton(tool: AnnotationTool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: tool.iconName)
                .font(.system(size: 16))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("\(tool.displayName) (\(tool.shortcutHint))")
        .disabled(tool != .textNote && !hasSelection)
        .opacity((tool != .textNote && !hasSelection) ? 0.5 : 1.0)
    }

    // MARK: - Color Picker

    private var colorPicker: some View {
        HStack(spacing: 4) {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Circle()
                    .fill(Color(color.platformColor))
                    .frame(width: 16, height: 16)
                    .overlay {
                        if color == highlightColor {
                            Circle()
                                .stroke(Color.primary, lineWidth: 2)
                        }
                    }
                    .onTapGesture {
                        highlightColor = color
                    }
            }
        }
    }
}

// MARK: - Selection Context Menu

/// Compact context menu that appears near text selections in the PDF viewer.
/// Provides quick access to annotation tools.
public struct SelectionContextMenu: View {

    // MARK: - Properties

    public var onHighlight: (HighlightColor) -> Void
    public var onUnderline: () -> Void
    public var onStrikethrough: () -> Void
    public var onAddNote: () -> Void
    public var onCopy: () -> Void

    // MARK: - Initialization

    public init(
        onHighlight: @escaping (HighlightColor) -> Void,
        onUnderline: @escaping () -> Void,
        onStrikethrough: @escaping () -> Void,
        onAddNote: @escaping () -> Void,
        onCopy: @escaping () -> Void
    ) {
        self.onHighlight = onHighlight
        self.onUnderline = onUnderline
        self.onStrikethrough = onStrikethrough
        self.onAddNote = onAddNote
        self.onCopy = onCopy
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: 8) {
            // Quick highlight buttons - most common colors
            ForEach([HighlightColor.yellow, .green, .blue], id: \.self) { color in
                Button {
                    onHighlight(color)
                } label: {
                    Circle()
                        .fill(Color(color.platformColor))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            Divider()
                .frame(height: 24)

            // Underline
            Button(action: onUnderline) {
                Image(systemName: "underline")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            // Strikethrough
            Button(action: onStrikethrough) {
                Image(systemName: "strikethrough")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            // Add note
            Button(action: onAddNote) {
                Image(systemName: "note.text")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 24)

            // Copy
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Preview

#Preview("Annotation Toolbar") {
    VStack(spacing: 40) {
        AnnotationToolbar(
            selectedTool: .constant(nil),
            highlightColor: .constant(.yellow),
            hasSelection: true,
            onHighlight: {},
            onUnderline: {},
            onStrikethrough: {},
            onAddNote: {}
        )

        AnnotationToolbar(
            selectedTool: .constant(.highlight),
            highlightColor: .constant(.green),
            hasSelection: false,
            onHighlight: {},
            onUnderline: {},
            onStrikethrough: {},
            onAddNote: {}
        )

        SelectionContextMenu(
            onHighlight: { _ in },
            onUnderline: {},
            onStrikethrough: {},
            onAddNote: {},
            onCopy: {}
        )
    }
    .padding()
}
