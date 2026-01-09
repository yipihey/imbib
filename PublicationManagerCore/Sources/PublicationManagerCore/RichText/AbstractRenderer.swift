//
//  AbstractRenderer.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-09.
//

import SwiftUI

// MARK: - Abstract Renderer

/// Renders scientific abstracts with full LaTeX support via SwiftMath.
///
/// Replaces ScientificTextParser with proper equation rendering:
/// - Fractions (\frac{}{})
/// - Square roots (\sqrt{})
/// - Integrals, sums, limits
/// - Greek letters
/// - Subscripts and superscripts
///
/// Usage:
/// ```swift
/// AbstractRenderer(text: abstract)
/// AbstractRenderer(text: abstract, fontSize: 16)
/// ```
public struct AbstractRenderer: View {

    // MARK: - Properties

    /// The abstract text to render
    public let text: String

    /// Font size for text content
    public var fontSize: CGFloat

    /// Text color
    public var textColor: Color

    // MARK: - Parsed Content

    private let segments: [AbstractSegment]

    // MARK: - Initialization

    public init(
        text: String,
        fontSize: CGFloat = 14,
        textColor: Color = .primary
    ) {
        self.text = text
        self.fontSize = fontSize
        self.textColor = textColor
        self.segments = AbstractParser.parse(text)
    }

    // MARK: - Body

    public var body: some View {
        // Use a flow layout for inline rendering
        WrappingHStack(alignment: .firstTextBaseline, spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                segmentView(segment)
            }
        }
    }

    // MARK: - Segment Rendering

    @ViewBuilder
    private func segmentView(_ segment: AbstractSegment) -> some View {
        switch segment {
        case .text(let str):
            // Split text into words for wrapping
            ForEach(Array(str.split(separator: " ", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, word in
                Text(String(word) + " ")
                    .font(.system(size: fontSize))
                    .foregroundStyle(textColor)
            }

        case .inlineMath(let latex):
            InlineMathView(latex: latex, fontSize: fontSize, textColor: textColor)

        case .displayMath(let latex):
            // Display math gets its own line
            DisplayMathView(latex: latex, fontSize: fontSize + 2, textColor: textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
    }
}

// MARK: - Wrapping HStack

/// A layout that wraps content horizontally like text.
struct WrappingHStack: Layout {
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            if index < result.positions.count {
                let position = result.positions[index]
                subview.place(
                    at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                    proposal: ProposedViewSize(subview.sizeThatFits(.unspecified))
                )
            }
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            // Check if we need to wrap
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))

            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}

// MARK: - Convenience Extension

public extension View {
    /// Renders abstract text with LaTeX support.
    func abstractText(_ text: String, fontSize: CGFloat = 14) -> some View {
        AbstractRenderer(text: text, fontSize: fontSize)
    }
}

// MARK: - Preview

#Preview("Simple Abstract") {
    ScrollView {
        AbstractRenderer(
            text: """
            We present observations of the H$\\alpha$ emission line in the spectrum of the star. \
            The measured flux is $F = 10^{-15}$ erg s$^{-1}$ cm$^{-2}$. \
            Using the standard relation $L = 4\\pi d^2 F$, we derive the luminosity.
            """
        )
        .padding()
    }
}

#Preview("MathML Abstract") {
    ScrollView {
        AbstractRenderer(
            text: """
            We report the detection of a signal-to-noise ratio of <inline-formula><mml:math><mml:mi>S</mml:mi><mml:mo>/</mml:mo><mml:mi>N</mml:mi></mml:math></inline-formula> = 5 \
            in the <inline-formula><mml:math><mml:msup><mml:mi>H</mml:mi><mml:mn>2</mml:mn></mml:msup></mml:math></inline-formula> line.
            """
        )
        .padding()
    }
}

#Preview("Complex Math") {
    ScrollView {
        AbstractRenderer(
            text: """
            The quadratic formula is $$x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}$$ which gives the roots of any quadratic equation.
            """
        )
        .padding()
    }
}

#Preview("Greek Letters") {
    AbstractRenderer(
        text: "The fine structure constant $\\alpha \\approx 1/137$ determines the strength of electromagnetic interactions."
    )
    .padding()
}
