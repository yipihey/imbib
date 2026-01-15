//
//  EnrichmentCoordinator.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-05.
//

import Foundation
import OSLog

// MARK: - Enrichment Coordinator

/// Coordinates enrichment services, connecting the EnrichmentService to Core Data persistence.
///
/// The EnrichmentCoordinator handles:
/// - Creating and configuring the EnrichmentService with plugins
/// - Wiring the persistence callback to save enrichment results
/// - Queueing publications for background enrichment
/// - Starting/stopping background sync
///
/// ## Usage
///
/// ```swift
/// // At app startup
/// let coordinator = EnrichmentCoordinator.shared
/// await coordinator.start()
///
/// // Queue a paper for enrichment
/// await coordinator.queueForEnrichment(publication)
/// ```
public actor EnrichmentCoordinator {

    // MARK: - Shared Instance

    /// Shared coordinator instance
    public static let shared = EnrichmentCoordinator()

    // MARK: - Properties

    private let service: EnrichmentService
    private let repository: PublicationRepository
    private var isStarted = false

    /// Public access to the enrichment service for citation explorer and other features
    public var enrichmentService: EnrichmentService {
        service
    }

    // MARK: - Initialization

    public init(
        repository: PublicationRepository = PublicationRepository(),
        credentialManager: CredentialManager = .shared
    ) {
        self.repository = repository

        // Create enrichment plugins
        let openAlex = OpenAlexSource(credentialManager: credentialManager)
        let semanticScholar = SemanticScholarSource(credentialManager: credentialManager)
        let ads = ADSSource(credentialManager: credentialManager)

        // Create service with plugins - ADS for references/citations, OpenAlex for PDF URLs
        self.service = EnrichmentService(
            plugins: [ads, openAlex, semanticScholar],
            settingsProvider: DefaultEnrichmentSettingsProvider(settings: EnrichmentSettings(
                preferredSource: .ads,
                sourcePriority: [.ads, .openAlex, .semanticScholar],
                autoSyncEnabled: true,
                refreshIntervalDays: 7
            ))
        )
    }

    // MARK: - Lifecycle

    /// Start the enrichment coordinator.
    ///
    /// This wires up the persistence callback and starts background sync.
    public func start() async {
        guard !isStarted else {
            Logger.enrichment.debug("EnrichmentCoordinator already started")
            return
        }

        Logger.enrichment.infoCapture("Starting EnrichmentCoordinator", category: "enrichment")

        // Wire up the persistence callback
        await service.setOnEnrichmentComplete { [repository] publicationID, result in
            await repository.saveEnrichmentResult(publicationID: publicationID, result: result)
        }

        // Start background sync
        await service.startBackgroundSync()
        isStarted = true

        Logger.enrichment.infoCapture("EnrichmentCoordinator started", category: "enrichment")
    }

    /// Stop the enrichment coordinator.
    public func stop() async {
        guard isStarted else { return }

        Logger.enrichment.infoCapture("Stopping EnrichmentCoordinator", category: "enrichment")
        await service.stopBackgroundSync()
        isStarted = false
    }

    // MARK: - Queue Operations

    /// Queue a publication for background enrichment.
    ///
    /// - Parameters:
    ///   - publication: The publication to enrich
    ///   - priority: Priority level (default: libraryPaper)
    public func queueForEnrichment(
        _ publication: CDPublication,
        priority: EnrichmentPriority = .libraryPaper
    ) async {
        let identifiers = publication.enrichmentIdentifiers

        guard !identifiers.isEmpty else {
            Logger.enrichment.debug("Skipping enrichment - no identifiers: \(publication.citeKey)")
            return
        }

        // Skip if recently enriched
        if !publication.isEnrichmentStale(thresholdDays: 1) {
            Logger.enrichment.debug("Skipping enrichment - recently enriched: \(publication.citeKey)")
            return
        }

        await service.queueForEnrichment(
            publicationID: publication.id,
            identifiers: identifiers,
            priority: priority
        )
    }

    /// Queue multiple publications for enrichment.
    public func queueForEnrichment(
        _ publications: [CDPublication],
        priority: EnrichmentPriority = .backgroundSync
    ) async {
        for publication in publications {
            await queueForEnrichment(publication, priority: priority)
        }
    }

    /// Queue all unenriched publications in a library.
    public func queueUnenrichedPublications(in library: CDLibrary) async {
        guard let publications = library.publications else { return }

        let unenriched = publications.filter { !$0.hasBeenEnriched || $0.isEnrichmentStale(thresholdDays: 7) }

        Logger.enrichment.infoCapture(
            "Queueing \(unenriched.count) unenriched publications from \(library.displayName)",
            category: "enrichment"
        )

        for publication in unenriched {
            await queueForEnrichment(publication, priority: .backgroundSync)
        }
    }

    // MARK: - Status

    /// Get current queue depth.
    public func queueDepth() async -> Int {
        await service.queueDepth()
    }

    /// Check if background sync is running.
    public var isRunning: Bool {
        get async { await service.isRunning }
    }
}

// MARK: - EnrichmentService Extension

extension EnrichmentService {

    /// Set the enrichment completion callback.
    ///
    /// This method allows setting the callback from outside the actor.
    public func setOnEnrichmentComplete(_ callback: @escaping (UUID, EnrichmentResult) async -> Void) {
        self.onEnrichmentComplete = callback
    }
}
