//
//  PaperFetchService.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-06.
//

import Foundation
import CoreData
import OSLog

// MARK: - Paper Fetch Service

/// Unified pipeline for fetching papers from any source and routing to Inbox.
///
/// This service provides a single entry point for all paper fetching that feeds the Inbox:
/// - Smart searches with `feedsToInbox: true`
/// - Ad-hoc searches via "Send to Inbox" action
/// - Future: Recommender systems, author following
///
/// The pipeline:
/// 1. Execute search query (via SourceManager)
/// 2. Apply mute filters (via InboxManager)
/// 3. Deduplicate against ALL libraries
/// 4. Route new papers to Inbox
public actor PaperFetchService {

    // MARK: - Dependencies

    private let sourceManager: SourceManager
    private let repository: PublicationRepository
    private let persistenceController: PersistenceController

    // MARK: - State

    private var _isLoading = false
    private var lastFetchDate: Date?
    private var lastFetchCount: Int = 0

    // MARK: - Initialization

    public init(
        sourceManager: SourceManager,
        repository: PublicationRepository,
        persistenceController: PersistenceController = .shared
    ) {
        self.sourceManager = sourceManager
        self.repository = repository
        self.persistenceController = persistenceController
    }

    // MARK: - State Access

    public var isLoading: Bool { _isLoading }

    public var lastFetch: (date: Date, count: Int)? {
        guard let date = lastFetchDate else { return nil }
        return (date, lastFetchCount)
    }

    // MARK: - Fetch for Inbox

    /// Fetch papers from a smart search and add them to the Inbox.
    ///
    /// This is the main entry point for Inbox-feeding smart searches.
    /// - Returns: Number of new papers added to Inbox
    @discardableResult
    public func fetchForInbox(smartSearch: CDSmartSearch) async throws -> Int {
        guard smartSearch.feedsToInbox else {
            Logger.smartSearch.warningCapture(
                "Smart search '\(smartSearch.name)' does not feed to Inbox",
                category: "inbox"
            )
            return 0
        }

        Logger.smartSearch.infoCapture(
            "Fetching for Inbox: '\(smartSearch.name)' query: \(smartSearch.query)",
            category: "inbox"
        )

        _isLoading = true
        defer { _isLoading = false }

        // Build search options
        let options = SearchOptions(
            maxResults: Int(smartSearch.maxResults),
            sourceIDs: smartSearch.sources.isEmpty ? nil : smartSearch.sources
        )

        // Execute search
        let results = try await sourceManager.search(query: smartSearch.query, options: options)
        Logger.smartSearch.debugCapture("Search returned \(results.count) results", category: "inbox")

        // Process results through pipeline
        let newCount = await processResultsForInbox(results)

        // Update smart search metadata
        await MainActor.run {
            smartSearch.dateLastExecuted = Date()
            smartSearch.lastFetchCount = Int16(newCount)
            persistenceController.save()
        }

        lastFetchDate = Date()
        lastFetchCount = newCount

        Logger.smartSearch.infoCapture(
            "Inbox fetch complete: \(newCount) new papers from '\(smartSearch.name)'",
            category: "inbox"
        )

        return newCount
    }

    /// Fetch papers from an ad-hoc search and add them to the Inbox.
    ///
    /// Used for the "Send to Inbox" action in search results.
    /// - Returns: Number of new papers added to Inbox
    @discardableResult
    public func fetchForInbox(
        query: String,
        sourceIDs: [String]? = nil,
        maxResults: Int = 50
    ) async throws -> Int {
        Logger.smartSearch.infoCapture("Ad-hoc Inbox fetch: '\(query)'", category: "inbox")

        _isLoading = true
        defer { _isLoading = false }

        let options = SearchOptions(maxResults: maxResults, sourceIDs: sourceIDs)
        let results = try await sourceManager.search(query: query, options: options)

        let newCount = await processResultsForInbox(results)

        lastFetchDate = Date()
        lastFetchCount = newCount

        Logger.smartSearch.infoCapture(
            "Ad-hoc Inbox fetch complete: \(newCount) new papers",
            category: "inbox"
        )

        return newCount
    }

    /// Send specific search results to the Inbox.
    ///
    /// Used when user selects papers from search results and clicks "Send to Inbox".
    /// - Returns: Number of new papers added to Inbox
    @discardableResult
    public func sendToInbox(results: [SearchResult]) async -> Int {
        Logger.smartSearch.infoCapture("Sending \(results.count) results to Inbox", category: "inbox")
        return await processResultsForInbox(results)
    }

    // MARK: - Refresh All Inbox Feeds

    /// Refresh all smart searches that feed to the Inbox.
    ///
    /// - Returns: Total number of new papers added
    @discardableResult
    public func refreshAllInboxFeeds() async throws -> Int {
        Logger.smartSearch.infoCapture("Refreshing all Inbox feeds", category: "inbox")

        _isLoading = true
        defer { _isLoading = false }

        // Fetch all smart searches with feedsToInbox enabled
        let request = NSFetchRequest<CDSmartSearch>(entityName: "SmartSearch")
        request.predicate = NSPredicate(format: "feedsToInbox == YES")

        let smartSearches: [CDSmartSearch]
        do {
            smartSearches = try await MainActor.run {
                try persistenceController.viewContext.fetch(request)
            }
        } catch {
            Logger.smartSearch.errorCapture("Failed to fetch Inbox feeds: \(error)", category: "inbox")
            throw error
        }

        Logger.smartSearch.debugCapture("Found \(smartSearches.count) Inbox feeds to refresh", category: "inbox")

        var totalNew = 0
        for smartSearch in smartSearches {
            do {
                let count = try await fetchForInbox(smartSearch: smartSearch)
                totalNew += count
            } catch {
                Logger.smartSearch.errorCapture(
                    "Failed to refresh feed '\(smartSearch.name)': \(error)",
                    category: "inbox"
                )
                // Continue with other feeds
            }
        }

        Logger.smartSearch.infoCapture("Inbox refresh complete: \(totalNew) total new papers", category: "inbox")
        return totalNew
    }

    // MARK: - Pipeline

    /// Process search results through the Inbox pipeline.
    ///
    /// Pipeline:
    /// 1. Apply mute filters
    /// 2. Deduplicate against ALL libraries
    /// 3. Create new papers and add to Inbox
    private func processResultsForInbox(_ results: [SearchResult]) async -> Int {
        guard !results.isEmpty else { return 0 }

        // Get InboxManager on main actor
        let inboxManager = await MainActor.run { InboxManager.shared }

        // Filter results
        var filteredResults: [SearchResult] = []
        for result in results {
            // Check mute filter using SearchResult overload
            let shouldFilter = await MainActor.run {
                inboxManager.shouldFilter(result: result)
            }

            if shouldFilter {
                Logger.smartSearch.debugCapture("Filtered out muted paper: \(result.title)", category: "inbox")
                continue
            }

            filteredResults.append(result)
        }

        Logger.smartSearch.debugCapture(
            "After mute filter: \(filteredResults.count) of \(results.count) papers remain",
            category: "inbox"
        )

        // Deduplicate against ALL libraries
        var newPapers: [CDPublication] = []

        for result in filteredResults {
            // Check if paper exists anywhere (cross-library dedup)
            if let _ = await repository.findByIdentifiers(result) {
                Logger.smartSearch.debugCapture("Paper already exists: \(result.title)", category: "inbox")
                continue
            }

            // Create new publication
            let publication = await repository.createFromSearchResult(result)
            newPapers.append(publication)
        }

        Logger.smartSearch.debugCapture("Created \(newPapers.count) new papers for Inbox", category: "inbox")

        // Add all new papers to Inbox
        if !newPapers.isEmpty {
            await MainActor.run {
                for paper in newPapers {
                    inboxManager.addToInbox(paper)
                }
            }
        }

        return newPapers.count
    }
}

// MARK: - Fetch Status

/// Status of a paper fetch operation.
public enum FetchStatus: Sendable {
    case idle
    case loading
    case completed(count: Int, date: Date)
    case failed(Error)
}
