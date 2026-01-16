//
//  SearchIntents.swift
//  PublicationManagerCore
//
//  Search-related Siri Shortcuts intents.
//

import AppIntents
import Foundation

// MARK: - Search Source Enum

/// Available search sources for the SearchPapersIntent.
@available(iOS 16.0, macOS 13.0, *)
public enum SearchSourceOption: String, AppEnum {
    case all = "all"
    case arxiv = "arxiv"
    case ads = "ads"
    case crossref = "crossref"
    case pubmed = "pubmed"
    case semanticScholar = "semantic_scholar"
    case openAlex = "openalex"
    case dblp = "dblp"

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Search Source"
    }

    public static var caseDisplayRepresentations: [SearchSourceOption: DisplayRepresentation] {
        [
            .all: DisplayRepresentation(title: "All Sources"),
            .arxiv: DisplayRepresentation(title: "arXiv"),
            .ads: DisplayRepresentation(title: "NASA ADS"),
            .crossref: DisplayRepresentation(title: "Crossref"),
            .pubmed: DisplayRepresentation(title: "PubMed"),
            .semanticScholar: DisplayRepresentation(title: "Semantic Scholar"),
            .openAlex: DisplayRepresentation(title: "OpenAlex"),
            .dblp: DisplayRepresentation(title: "DBLP")
        ]
    }

    /// Convert to source ID used by the automation system.
    var sourceID: String? {
        switch self {
        case .all: return nil
        case .arxiv: return "arxiv"
        case .ads: return "ads"
        case .crossref: return "crossref"
        case .pubmed: return "pubmed"
        case .semanticScholar: return "semantic_scholar"
        case .openAlex: return "openalex"
        case .dblp: return "dblp"
        }
    }
}

// MARK: - Search Papers Intent

/// Search for papers across scientific databases.
@available(iOS 16.0, macOS 13.0, *)
public struct SearchPapersIntent: AppIntent, AutomationIntent {

    public static var title: LocalizedStringResource = "Search Papers"

    public static var description = IntentDescription(
        "Search for scientific papers across multiple databases.",
        categoryName: "Search"
    )

    public static var parameterSummary: some ParameterSummary {
        Summary("Search for \(\.$query)") {
            \.$source
            \.$maxResults
        }
    }

    @Parameter(title: "Query", description: "The search query (title, author, keywords)")
    public var query: String

    @Parameter(title: "Source", description: "Which database to search", default: .all)
    public var source: SearchSourceOption

    @Parameter(title: "Max Results", description: "Maximum number of results to return", default: 50)
    public var maxResults: Int

    public var automationCommand: AutomationCommand {
        .search(query: query, source: source.sourceID, maxResults: maxResults)
    }

    public init() {}

    public init(query: String, source: SearchSourceOption = .all, maxResults: Int = 50) {
        self.query = query
        self.source = source
        self.maxResults = maxResults
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Check if automation is enabled
        let isEnabled = await AutomationSettingsStore.shared.isEnabled
        guard isEnabled else {
            throw IntentError.automationDisabled
        }

        // Execute the search
        let result = await URLSchemeHandler.shared.execute(automationCommand)

        if result.success {
            return .result(value: "Searching for '\(query)'")
        } else {
            throw IntentError.executionFailed(result.error ?? "Search failed")
        }
    }
}

// MARK: - Search Category Intent

/// Search within a specific arXiv category.
@available(iOS 16.0, macOS 13.0, *)
public struct SearchCategoryIntent: AppIntent, AutomationIntent {

    public static var title: LocalizedStringResource = "Search arXiv Category"

    public static var description = IntentDescription(
        "Search for recent papers in an arXiv category.",
        categoryName: "Search"
    )

    @Parameter(title: "Category", description: "The arXiv category (e.g., astro-ph.CO, hep-th)")
    public var category: String

    public var automationCommand: AutomationCommand {
        .searchCategory(category: category)
    }

    public init() {}

    public init(category: String) {
        self.category = category
    }

    public func perform() async throws -> some IntentResult {
        try await performAutomation()
    }
}

// MARK: - Show Search Intent

/// Navigate to the search view.
@available(iOS 16.0, macOS 13.0, *)
public struct ShowSearchIntent: AppIntent, AutomationIntent {

    public static var title: LocalizedStringResource = "Show Search"

    public static var description = IntentDescription(
        "Open the search view in imbib.",
        categoryName: "Navigation"
    )

    public var automationCommand: AutomationCommand {
        .navigate(target: .search)
    }

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await performAutomation()
    }
}
