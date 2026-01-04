//
//  PublicationRow.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI

// MARK: - Publication Row

/// A row view for displaying a publication in a list.
public struct PublicationRow: View {

    let publication: CDPublication
    let isSelected: Bool
    let onTap: () -> Void

    public init(
        publication: CDPublication,
        isSelected: Bool = false,
        onTap: @escaping () -> Void = {}
    ) {
        self.publication = publication
        self.isSelected = isSelected
        self.onTap = onTap
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(publication.title ?? "Untitled")
                    .font(.headline)
                    .lineLimit(2)

                // Authors
                if !publication.authorString.isEmpty {
                    Text(publication.authorString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Metadata row
                HStack(spacing: 8) {
                    // Year
                    if publication.year > 0 {
                        Text(String(publication.year))
                            .font(.caption)
                    }

                    // Entry type
                    Text(publication.entryType.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Capsule())

                    // Cite key
                    Text(publication.citeKey)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Spacer()

                    // PDF indicator
                    if let files = publication.linkedFiles, !files.isEmpty {
                        Image(systemName: "doc.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Search Result Row

/// A row view for displaying a search result.
public struct SearchResultRow: View {

    let result: DeduplicatedResult
    let isSelected: Bool
    let onTap: () -> Void

    public init(
        result: DeduplicatedResult,
        isSelected: Bool = false,
        onTap: @escaping () -> Void = {}
    ) {
        self.result = result
        self.isSelected = isSelected
        self.onTap = onTap
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(result.primary.title)
                    .font(.headline)
                    .lineLimit(2)

                // Authors
                if !result.primary.authors.isEmpty {
                    Text(result.primary.authors.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Metadata row
                HStack(spacing: 8) {
                    // Year
                    if let year = result.primary.year {
                        Text(String(year))
                            .font(.caption)
                    }

                    // Venue
                    if let venue = result.primary.venue {
                        Text(venue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Source badges
                    ForEach(result.sourceIDs, id: \.self) { sourceID in
                        SourceBadge(sourceID: sourceID)
                    }
                }

                // Identifiers
                if !result.identifiers.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(result.identifiers.keys), id: \.self) { type in
                            if let value = result.identifiers[type] {
                                IdentifierBadge(type: type, value: value)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Source Badge

public struct SourceBadge: View {
    let sourceID: String

    public init(sourceID: String) {
        self.sourceID = sourceID
    }

    public var body: some View {
        Text(sourceID)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color(for: sourceID).opacity(0.2))
            .foregroundStyle(color(for: sourceID))
            .clipShape(Capsule())
    }

    private func color(for sourceID: String) -> Color {
        switch sourceID {
        case "arxiv": return .orange
        case "crossref": return .blue
        case "pubmed": return .green
        case "ads": return .purple
        case "semanticscholar": return .indigo
        case "openalex": return .teal
        case "dblp": return .brown
        default: return .gray
        }
    }
}

// MARK: - Identifier Badge

public struct IdentifierBadge: View {
    let type: IdentifierType
    let value: String

    public init(type: IdentifierType, value: String) {
        self.type = type
        self.value = value
    }

    public var body: some View {
        HStack(spacing: 2) {
            Text(type.displayName)
                .font(.caption2.bold())
            Text(truncatedValue)
                .font(.caption2)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var truncatedValue: String {
        if value.count > 20 {
            return String(value.prefix(17)) + "..."
        }
        return value
    }
}
