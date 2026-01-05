//
//  EnrichmentService.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog

// MARK: - Enrichment Service

/// Central service for coordinating publication enrichment across multiple sources.
///
/// The EnrichmentService manages:
/// - On-demand enrichment for user-triggered requests
/// - Background enrichment queue with priority ordering
/// - Source selection based on user preferences
/// - Caching and staleness tracking
///
/// ## Usage
///
/// ```swift
/// let service = EnrichmentService(plugins: [semanticScholar, openAlex])
///
/// // On-demand enrichment
/// let data = try await service.enrichNow(identifiers: [.doi: "10.1234/test"])
///
/// // Queue for background enrichment
/// await service.queueForEnrichment(publicationID: id, priority: .libraryPaper)
/// ```
///
/// ## Thread Safety
///
/// EnrichmentService is an actor, ensuring thread-safe access to all state.
public actor EnrichmentService {

    // MARK: - Dependencies

    private let plugins: [any EnrichmentPlugin]
    private let settingsProvider: EnrichmentSettingsProvider
    private let queue: EnrichmentQueue

    // MARK: - State

    private var isBackgroundSyncRunning = false
    private var backgroundTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Create an enrichment service with the given plugins.
    ///
    /// - Parameters:
    ///   - plugins: Available enrichment plugins (sources)
    ///   - settingsProvider: Provider for user enrichment preferences
    ///   - queue: Queue for managing enrichment requests (injected for testing)
    public init(
        plugins: [any EnrichmentPlugin],
        settingsProvider: EnrichmentSettingsProvider = DefaultEnrichmentSettingsProvider(),
        queue: EnrichmentQueue? = nil
    ) {
        self.plugins = plugins
        self.settingsProvider = settingsProvider
        self.queue = queue ?? EnrichmentQueue()
    }

    // MARK: - On-Demand Enrichment

    /// Immediately enrich a paper using available identifiers.
    ///
    /// Tries plugins in priority order until one succeeds.
    ///
    /// - Parameters:
    ///   - identifiers: Available identifiers for the paper
    ///   - existingData: Previously fetched enrichment data (for merging)
    /// - Returns: Enrichment result with data and resolved identifiers
    /// - Throws: `EnrichmentError` if all plugins fail
    public func enrichNow(
        identifiers: [IdentifierType: String],
        existingData: EnrichmentData? = nil
    ) async throws -> EnrichmentResult {
        let idDesc = identifiers.map { "\($0.key.rawValue): \($0.value)" }.joined(separator: ", ")
        Logger.enrichment.infoCapture("Enriching: \(idDesc)", category: "enrichment")

        guard !identifiers.isEmpty else {
            throw EnrichmentError.noIdentifier
        }

        let priority = await settingsProvider.sourcePriority
        let sortedPlugins = sortPlugins(by: priority)

        var lastError: Error?

        for plugin in sortedPlugins {
            let canEnrich = await plugin.canEnrich(identifiers: identifiers)
            guard canEnrich else {
                Logger.enrichment.debug("\(plugin.metadata.name) cannot enrich these identifiers")
                continue
            }

            do {
                Logger.enrichment.infoCapture("Trying source: \(plugin.metadata.name)", category: "enrichment")
                let result = try await plugin.enrich(identifiers: identifiers, existingData: existingData)
                Logger.enrichment.infoCapture(
                    "\(plugin.metadata.name) succeeded - citations: \(result.data.citationCount ?? 0)",
                    category: "enrichment"
                )
                return result
            } catch {
                Logger.enrichment.warningCapture(
                    "\(plugin.metadata.name) failed: \(error.localizedDescription)",
                    category: "enrichment"
                )
                lastError = error

                // Don't try other sources for rate limiting - wait and retry same source
                if case EnrichmentError.rateLimited = error {
                    throw error
                }
            }
        }

        // All plugins failed
        if let error = lastError {
            throw error
        }
        throw EnrichmentError.noSourceAvailable
    }

    /// Enrich a search result from an online source.
    ///
    /// - Parameter result: The search result to enrich
    /// - Returns: Enrichment data
    /// - Throws: `EnrichmentError` if enrichment fails
    public func enrichSearchResult(_ result: SearchResult) async throws -> EnrichmentResult {
        try await enrichNow(identifiers: result.allIdentifiers, existingData: nil)
    }

    // MARK: - Queue Management

    /// Queue a publication for background enrichment.
    ///
    /// - Parameters:
    ///   - publicationID: UUID of the publication to enrich
    ///   - identifiers: Available identifiers for the paper
    ///   - priority: Priority level for the request
    public func queueForEnrichment(
        publicationID: UUID,
        identifiers: [IdentifierType: String],
        priority: EnrichmentPriority = .libraryPaper
    ) async {
        let request = EnrichmentRequest(
            publicationID: publicationID,
            identifiers: identifiers,
            priority: priority
        )
        await queue.enqueue(request)
        let depth = await queue.count
        Logger.enrichment.infoCapture(
            "Queued \(publicationID.uuidString.prefix(8))... (priority: \(priority.description), depth: \(depth))",
            category: "enrichment"
        )
    }

    /// Get the current queue depth.
    public func queueDepth() async -> Int {
        await queue.count
    }

    /// Process the next item in the queue.
    ///
    /// - Returns: Result if an item was processed, nil if queue is empty
    public func processNextQueued() async -> (UUID, Result<EnrichmentResult, Error>)? {
        guard let request = await queue.dequeue() else {
            return nil
        }

        do {
            let result = try await enrichNow(identifiers: request.identifiers, existingData: nil)
            return (request.publicationID, .success(result))
        } catch {
            return (request.publicationID, .failure(error))
        }
    }

    // MARK: - Background Sync

    /// Start background synchronization.
    ///
    /// Processes queued enrichment requests continuously until stopped.
    public func startBackgroundSync() async {
        guard !isBackgroundSyncRunning else {
            Logger.enrichment.debug("Background sync already running")
            return
        }

        isBackgroundSyncRunning = true
        Logger.enrichment.infoCapture("Background sync started", category: "enrichment")

        backgroundTask = Task {
            await runBackgroundLoop()
        }
    }

    /// Stop background synchronization.
    public func stopBackgroundSync() async {
        guard isBackgroundSyncRunning else { return }

        isBackgroundSyncRunning = false
        backgroundTask?.cancel()
        backgroundTask = nil
        Logger.enrichment.infoCapture("Background sync stopped", category: "enrichment")
    }

    /// Check if background sync is running.
    public var isRunning: Bool {
        isBackgroundSyncRunning
    }

    // MARK: - Plugin Access

    /// Get all registered plugins.
    public var registeredPlugins: [any EnrichmentPlugin] {
        plugins
    }

    /// Get plugin by source ID.
    public func plugin(for sourceID: String) -> (any EnrichmentPlugin)? {
        plugins.first { $0.metadata.id == sourceID }
    }

    /// Get plugins that support a specific capability.
    public func plugins(supporting capability: EnrichmentCapabilities) async -> [any EnrichmentPlugin] {
        var result: [any EnrichmentPlugin] = []
        for plugin in plugins {
            let supports = await plugin.supports(capability)
            if supports {
                result.append(plugin)
            }
        }
        return result
    }

    // MARK: - Private Helpers

    /// Sort plugins by user priority preference.
    private func sortPlugins(by priority: [EnrichmentSource]) -> [any EnrichmentPlugin] {
        plugins.sorted { a, b in
            let aIndex = priority.firstIndex { $0.sourceID == a.metadata.id } ?? Int.max
            let bIndex = priority.firstIndex { $0.sourceID == b.metadata.id } ?? Int.max
            return aIndex < bIndex
        }
    }

    /// Background processing loop.
    private func runBackgroundLoop() async {
        var processedCount = 0
        while isBackgroundSyncRunning && !Task.isCancelled {
            if let (publicationID, result) = await processNextQueued() {
                processedCount += 1
                switch result {
                case .success(let data):
                    Logger.enrichment.infoCapture(
                        "Background enriched \(publicationID.uuidString.prefix(8))... - citations: \(data.data.citationCount ?? 0)",
                        category: "enrichment"
                    )
                case .failure(let error):
                    Logger.enrichment.warningCapture(
                        "Background enrichment failed \(publicationID.uuidString.prefix(8))...: \(error.localizedDescription)",
                        category: "enrichment"
                    )
                }

                // Small delay between requests to avoid hammering APIs
                try? await Task.sleep(for: .milliseconds(100))
            } else {
                // Queue empty, wait before checking again
                if processedCount > 0 {
                    Logger.enrichment.infoCapture(
                        "Background queue empty (processed \(processedCount) items)",
                        category: "enrichment"
                    )
                    processedCount = 0
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

// MARK: - Enrichment Request

/// A request to enrich a publication.
public struct EnrichmentRequest: Sendable, Identifiable {
    public let id: UUID
    public let publicationID: UUID
    public let identifiers: [IdentifierType: String]
    public let priority: EnrichmentPriority
    public let createdAt: Date

    public init(
        publicationID: UUID,
        identifiers: [IdentifierType: String],
        priority: EnrichmentPriority = .libraryPaper
    ) {
        self.id = UUID()
        self.publicationID = publicationID
        self.identifiers = identifiers
        self.priority = priority
        self.createdAt = Date()
    }
}

// MARK: - Default Settings Provider

/// Default implementation of EnrichmentSettingsProvider using stored settings.
public actor DefaultEnrichmentSettingsProvider: EnrichmentSettingsProvider {
    private var settings: EnrichmentSettings

    public init(settings: EnrichmentSettings = .default) {
        self.settings = settings
    }

    public var preferredSource: EnrichmentSource {
        settings.preferredSource
    }

    public var sourcePriority: [EnrichmentSource] {
        settings.sourcePriority
    }

    public var autoSyncEnabled: Bool {
        settings.autoSyncEnabled
    }

    public var refreshIntervalDays: Int {
        settings.refreshIntervalDays
    }

    /// Update settings.
    public func update(_ newSettings: EnrichmentSettings) {
        settings = newSettings
    }
}

