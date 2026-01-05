//
//  UnifiedPaperRow.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI

// MARK: - Unified Paper Row

/// A row view that works with any PaperRepresentable, providing consistent
/// display for both local library papers and online search results.
public struct UnifiedPaperRow<Paper: PaperRepresentable>: View {

    // MARK: - Properties

    public let paper: Paper

    /// Whether to show the library state indicator
    public var showLibraryIndicator: Bool = true

    /// Whether to show source badges
    public var showSourceBadges: Bool = true

    /// Whether to show citation metrics badge
    public var showCitationBadge: Bool = true

    /// Citation count for the paper (nil if not enriched)
    public var citationCount: Int?

    /// When the enrichment data was last updated
    public var enrichmentDate: Date?

    /// Action when import button is tapped (nil to hide button)
    public var onImport: (() -> Void)?

    /// Action when citation badge is tapped to refresh enrichment
    public var onRefreshEnrichment: (() async -> Void)?

    // MARK: - State

    @State private var libraryState: LibraryState = .checking
    @State private var isRefreshingEnrichment: Bool = false

    // MARK: - Initialization

    public init(
        paper: Paper,
        showLibraryIndicator: Bool = true,
        showSourceBadges: Bool = true,
        showCitationBadge: Bool = true,
        citationCount: Int? = nil,
        enrichmentDate: Date? = nil,
        onImport: (() -> Void)? = nil,
        onRefreshEnrichment: (() async -> Void)? = nil
    ) {
        self.paper = paper
        self.showLibraryIndicator = showLibraryIndicator
        self.showSourceBadges = showSourceBadges
        self.showCitationBadge = showCitationBadge
        self.citationCount = citationCount
        self.enrichmentDate = enrichmentDate
        self.onImport = onImport
        self.onRefreshEnrichment = onRefreshEnrichment
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title row with library indicator
            HStack {
                Text(paper.title)
                    .font(.headline)
                    .lineLimit(2)

                Spacer()

                if showLibraryIndicator {
                    LibraryStateIndicator(state: libraryState)
                }
            }

            // Authors
            Text(paper.authorDisplayString)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Metadata row
            HStack(spacing: 8) {
                // Source badges (for online results)
                if showSourceBadges {
                    sourceBadge
                }

                // Year
                if let year = paper.year {
                    Text(String(year))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Venue
                if let venue = paper.venue {
                    Text(venue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Citation metrics badge
                if showCitationBadge {
                    CitationMetricsBadge(
                        citationCount: citationCount,
                        enrichmentDate: enrichmentDate,
                        isRefreshing: $isRefreshingEnrichment,
                        onRefresh: onRefreshEnrichment != nil ? {
                            isRefreshingEnrichment = true
                            await onRefreshEnrichment?()
                            isRefreshingEnrichment = false
                        } : nil
                    )
                }

                // Import button (for online results)
                if let onImport = onImport, !paper.sourceType.isPersistent {
                    Button {
                        onImport()
                    } label: {
                        Label("Import", systemImage: "plus.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .disabled(libraryState == .inLibrary)
                }
            }

            // Abstract preview (if available)
            if let abstract = paper.abstract, !abstract.isEmpty {
                Text(abstract)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 4)
        .task {
            await checkLibraryState()
        }
    }

    // MARK: - Source Badge

    @ViewBuilder
    private var sourceBadge: some View {
        switch paper.sourceType {
        case .local:
            EmptyView() // No badge for local papers

        case .smartSearch:
            Text("Smart Search")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.2))
                .clipShape(Capsule())

        case .adHocSearch(let sourceID):
            Text(formatSourceID(sourceID))
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.2))
                .clipShape(Capsule())
        }
    }

    // MARK: - Helpers

    private func checkLibraryState() async {
        // Skip checking for local papers (they're always in library)
        if paper.sourceType.isPersistent {
            libraryState = .inLibrary
            return
        }

        libraryState = await paper.checkLibraryState()
    }

    private func formatSourceID(_ id: String) -> String {
        // Capitalize and format source IDs nicely
        switch id.lowercased() {
        case "arxiv": return "arXiv"
        case "ads": return "ADS"
        case "crossref": return "Crossref"
        case "pubmed": return "PubMed"
        case "dblp": return "DBLP"
        case "semantic-scholar": return "Semantic Scholar"
        case "openalex": return "OpenAlex"
        default: return id.capitalized
        }
    }
}

// MARK: - Library State Indicator

/// Shows whether a paper is already in the library
public struct LibraryStateIndicator: View {

    public let state: LibraryState

    public init(state: LibraryState) {
        self.state = state
    }

    public var body: some View {
        switch state {
        case .inLibrary:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("In Library")

        case .notInLibrary:
            EmptyView()

        case .checking:
            ProgressView()
                .scaleEffect(0.6)

        case .unknown:
            EmptyView()
        }
    }
}

// MARK: - Preview

#Preview {
    // Create a sample OnlinePaper for preview
    let result = SearchResult(
        id: "preview-1",
        sourceID: "arxiv",
        title: "On the Electrodynamics of Moving Bodies",
        authors: ["Albert Einstein"],
        year: 1905,
        venue: "Annalen der Physik",
        abstract: "A theory of special relativity demonstrating the relationship between space and time.",
        doi: "10.1002/andp.19053221004"
    )
    let paper = OnlinePaper(result: result)

    return List {
        UnifiedPaperRow(paper: paper) {
            print("Import tapped")
        }
    }
}
