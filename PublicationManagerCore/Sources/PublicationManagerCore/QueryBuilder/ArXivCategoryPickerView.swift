//
//  ArXivCategoryPickerView.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-07.
//

import SwiftUI

// MARK: - ArXiv Category Picker View

/// A searchable picker for selecting arXiv categories
public struct ArXivCategoryPickerView: View {
    @Binding var selectedCategory: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    public init(selectedCategory: Binding<String>) {
        self._selectedCategory = selectedCategory
    }

    /// Filtered groups based on search text
    private var filteredGroups: [ArXivCategoryGroup] {
        if searchText.isEmpty {
            return ArXivCategories.groups
        }

        let lowercased = searchText.lowercased()
        return ArXivCategories.groups.compactMap { group in
            let filteredCategories = group.categories.filter { category in
                category.id.lowercased().contains(lowercased) ||
                category.name.lowercased().contains(lowercased) ||
                (category.description?.lowercased().contains(lowercased) ?? false)
            }

            if filteredCategories.isEmpty {
                return nil
            }

            return ArXivCategoryGroup(
                id: group.id,
                name: group.name,
                iconName: group.iconName,
                categories: filteredCategories
            )
        }
    }

    public var body: some View {
        NavigationStack {
            List {
                // Quick picks section
                if searchText.isEmpty {
                    Section("Suggested") {
                        suggestedSection
                    }
                }

                // All categories grouped
                ForEach(filteredGroups) { group in
                    Section {
                        ForEach(group.categories) { category in
                            CategoryRow(
                                category: category,
                                isSelected: selectedCategory == category.id
                            ) {
                                selectedCategory = category.id
                                dismiss()
                            }
                        }
                    } header: {
                        Label(group.name, systemImage: group.iconName)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search categories")
            .navigationTitle("Select Category")
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 500)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var suggestedSection: some View {
        // Astronomy suggestions
        HStack {
            Text("Astrophysics")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }

        FlowLayout(spacing: 6) {
            ForEach(ArXivCategories.suggestedAstro) { category in
                ArXivCategoryChip(
                    category: category,
                    isSelected: selectedCategory == category.id
                ) {
                    selectedCategory = category.id
                    dismiss()
                }
            }
        }

        // ML suggestions
        HStack {
            Text("Machine Learning")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 8)

        FlowLayout(spacing: 6) {
            ForEach(ArXivCategories.suggestedML) { category in
                ArXivCategoryChip(
                    category: category,
                    isSelected: selectedCategory == category.id
                ) {
                    selectedCategory = category.id
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Category Row

/// A single row in the category list
private struct CategoryRow: View {
    let category: ArXivCategory
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(category.id)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)

                        Text(category.name)
                            .foregroundStyle(.secondary)
                    }

                    if let description = category.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Chip

/// A compact chip for displaying a category in the suggested section
private struct ArXivCategoryChip: View {
    let category: ArXivCategory
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(category.id)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: isSelected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
        .help(category.name)
    }
}

// MARK: - Flow Layout

/// A layout that wraps items horizontally
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Preview

#if DEBUG
struct ArXivCategoryPickerView_Previews: PreviewProvider {
    static var previews: some View {
        ArXivCategoryPickerPreview()
    }
}

struct ArXivCategoryPickerPreview: View {
    @State private var selected = "cs.LG"

    var body: some View {
        ArXivCategoryPickerView(selectedCategory: $selected)
    }
}
#endif
