//
//  ExplorationService.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-13.
//

import Foundation
import CoreData
import OSLog

// MARK: - Exploration Service

/// Service for exploring paper references and citations.
///
/// Creates collections in the Exploration library when exploring a paper's
/// references or citations. Papers are imported as CDPublication entities,
/// enabling full list view, info tab, and PDF download functionality.
///
/// ## Usage
///
/// ```swift
/// let collection = try await ExplorationService.shared.exploreReferences(
///     of: publication,
///     parentCollection: existingCollection
/// )
/// ```
@MainActor
public final class ExplorationService {

    // MARK: - Shared Instance

    public static let shared = ExplorationService()

    // MARK: - Dependencies

    private let persistenceController: PersistenceController
    private var libraryManager: LibraryManager
    private var enrichmentService: EnrichmentService?

    // MARK: - State

    /// Whether an exploration is in progress
    public private(set) var isExploring = false

    /// Current error if exploration failed
    public private(set) var error: Error?

    // MARK: - Initialization

    public init(
        persistenceController: PersistenceController = .shared,
        libraryManager: LibraryManager? = nil
    ) {
        self.persistenceController = persistenceController
        // LibraryManager needs to be injected later via setLibraryManager
        // since it may not be available during initialization
        self.libraryManager = libraryManager ?? LibraryManager(persistenceController: persistenceController)
    }

    /// Set the enrichment service (called from coordinator after environment setup)
    public func setEnrichmentService(_ service: EnrichmentService) {
        self.enrichmentService = service
    }

    /// Set the library manager (must be called with the environment's LibraryManager)
    public func setLibraryManager(_ manager: LibraryManager) {
        self.libraryManager = manager
    }

    // MARK: - Exploration

    /// Explore references of a publication.
    ///
    /// Fetches the papers that this publication cites and creates a collection
    /// in the Exploration library containing them.
    ///
    /// - Parameters:
    ///   - publication: The publication to explore references for
    ///   - parentCollection: Optional parent collection for drill-down hierarchy
    /// - Returns: The created collection containing referenced papers
    /// - Throws: ExplorationError if exploration fails
    public func exploreReferences(
        of publication: CDPublication,
        parentCollection: CDCollection? = nil
    ) async throws -> CDCollection {
        Logger.viewModels.info("ExplorationService: exploring references of \(publication.citeKey)")

        isExploring = true
        error = nil

        defer { isExploring = false }

        guard let service = enrichmentService else {
            let err = ExplorationError.notConfigured
            error = err
            throw err
        }

        // Get identifiers for enrichment
        let identifiers = publication.allIdentifiers
        guard !identifiers.isEmpty else {
            let err = ExplorationError.noIdentifiers
            error = err
            throw err
        }

        // Fetch enrichment data (which includes references)
        let result = try await service.enrichNow(identifiers: identifiers)

        guard let references = result.data.references, !references.isEmpty else {
            let err = ExplorationError.noReferences
            error = err
            throw err
        }

        // Create collection name
        let collectionName = formatCollectionName("Refs", publication: publication)

        // Create collection and import papers
        let collection = try await createExplorationCollection(
            name: collectionName,
            papers: references,
            parentCollection: parentCollection
        )

        Logger.viewModels.info("ExplorationService: created collection '\(collectionName)' with \(references.count) papers")

        // Post notification for sidebar navigation with first publication for auto-selection
        let firstPubID = collection.publications?.first(where: { !$0.isDeleted })?.id
        NotificationCenter.default.post(
            name: .navigateToCollection,
            object: nil,
            userInfo: [
                "collection": collection,
                "firstPublicationID": firstPubID as Any
            ]
        )

        NotificationCenter.default.post(name: .explorationLibraryDidChange, object: nil)

        return collection
    }

    /// Explore citations of a publication.
    ///
    /// Fetches the papers that cite this publication and creates a collection
    /// in the Exploration library containing them.
    ///
    /// - Parameters:
    ///   - publication: The publication to explore citations for
    ///   - parentCollection: Optional parent collection for drill-down hierarchy
    /// - Returns: The created collection containing citing papers
    /// - Throws: ExplorationError if exploration fails
    public func exploreCitations(
        of publication: CDPublication,
        parentCollection: CDCollection? = nil
    ) async throws -> CDCollection {
        Logger.viewModels.info("ExplorationService: exploring citations of \(publication.citeKey)")

        isExploring = true
        error = nil

        defer { isExploring = false }

        guard let service = enrichmentService else {
            let err = ExplorationError.notConfigured
            error = err
            throw err
        }

        // Get identifiers for enrichment
        let identifiers = publication.allIdentifiers
        guard !identifiers.isEmpty else {
            let err = ExplorationError.noIdentifiers
            error = err
            throw err
        }

        // Fetch enrichment data (which includes citations)
        let result = try await service.enrichNow(identifiers: identifiers)

        guard let citations = result.data.citations, !citations.isEmpty else {
            let err = ExplorationError.noCitations
            error = err
            throw err
        }

        // Create collection name
        let collectionName = formatCollectionName("Cites", publication: publication)

        // Create collection and import papers
        let collection = try await createExplorationCollection(
            name: collectionName,
            papers: citations,
            parentCollection: parentCollection
        )

        Logger.viewModels.info("ExplorationService: created collection '\(collectionName)' with \(citations.count) papers")

        // Post notification for sidebar navigation with first publication for auto-selection
        let firstPubID = collection.publications?.first(where: { !$0.isDeleted })?.id
        NotificationCenter.default.post(
            name: .navigateToCollection,
            object: nil,
            userInfo: [
                "collection": collection,
                "firstPublicationID": firstPubID as Any
            ]
        )

        NotificationCenter.default.post(name: .explorationLibraryDidChange, object: nil)

        return collection
    }

    /// Explore papers similar to a publication (by content).
    ///
    /// Fetches papers with similar content using ADS `similar()` operator
    /// and creates a collection in the Exploration library containing them.
    ///
    /// - Parameters:
    ///   - publication: The publication to find similar papers for
    ///   - parentCollection: Optional parent collection for drill-down hierarchy
    /// - Returns: The created collection containing similar papers
    /// - Throws: ExplorationError if exploration fails
    public func exploreSimilar(
        of publication: CDPublication,
        parentCollection: CDCollection? = nil
    ) async throws -> CDCollection {
        Logger.viewModels.info("ExplorationService: exploring similar papers for \(publication.citeKey)")

        isExploring = true
        error = nil

        defer { isExploring = false }

        // Use enrichment service to resolve bibcode (same as references/citations)
        guard let service = enrichmentService else {
            let err = ExplorationError.notConfigured
            error = err
            throw err
        }

        // Get identifiers for enrichment
        let identifiers = publication.allIdentifiers
        guard !identifiers.isEmpty else {
            let err = ExplorationError.noIdentifiers
            error = err
            throw err
        }

        // Enrich to get resolved bibcode
        let result = try await service.enrichNow(identifiers: identifiers)

        // Get bibcode from enrichment result or publication
        guard let bibcode = result.resolvedIdentifiers[.bibcode]
                ?? publication.bibcode
                ?? publication.fields["bibcode"],
              !bibcode.isEmpty else {
            let err = ExplorationError.noIdentifiers
            error = err
            throw err
        }

        // Fetch similar papers via ADS
        let adsSource = ADSSource()
        let similar = try await adsSource.fetchSimilar(bibcode: bibcode)
        guard !similar.isEmpty else {
            let err = ExplorationError.noSimilar
            error = err
            throw err
        }

        let collectionName = formatCollectionName("Similar", publication: publication)
        let collection = try await createExplorationCollection(
            name: collectionName,
            papers: similar,
            parentCollection: parentCollection
        )

        Logger.viewModels.info("ExplorationService: created collection '\(collectionName)' with \(similar.count) papers")

        // Post notification for sidebar navigation with first publication for auto-selection
        let firstPubID = collection.publications?.first(where: { !$0.isDeleted })?.id
        NotificationCenter.default.post(
            name: .navigateToCollection,
            object: nil,
            userInfo: [
                "collection": collection,
                "firstPublicationID": firstPubID as Any
            ]
        )
        NotificationCenter.default.post(name: .explorationLibraryDidChange, object: nil)

        return collection
    }

    /// Explore papers frequently co-read with this publication.
    ///
    /// Fetches papers that readers commonly view together using ADS `trending()` operator
    /// and creates a collection in the Exploration library containing them.
    ///
    /// - Parameters:
    ///   - publication: The publication to find co-reads for
    ///   - parentCollection: Optional parent collection for drill-down hierarchy
    /// - Returns: The created collection containing co-read papers
    /// - Throws: ExplorationError if exploration fails
    public func exploreCoReads(
        of publication: CDPublication,
        parentCollection: CDCollection? = nil
    ) async throws -> CDCollection {
        Logger.viewModels.info("ExplorationService: exploring co-reads for \(publication.citeKey)")

        isExploring = true
        error = nil

        defer { isExploring = false }

        // Use enrichment service to resolve bibcode (same as references/citations)
        guard let service = enrichmentService else {
            let err = ExplorationError.notConfigured
            error = err
            throw err
        }

        // Get identifiers for enrichment
        let identifiers = publication.allIdentifiers
        guard !identifiers.isEmpty else {
            let err = ExplorationError.noIdentifiers
            error = err
            throw err
        }

        // Enrich to get resolved bibcode
        let result = try await service.enrichNow(identifiers: identifiers)

        // Get bibcode from enrichment result or publication
        guard let bibcode = result.resolvedIdentifiers[.bibcode]
                ?? publication.bibcode
                ?? publication.fields["bibcode"],
              !bibcode.isEmpty else {
            let err = ExplorationError.noIdentifiers
            error = err
            throw err
        }

        // Fetch co-reads via ADS
        let adsSource = ADSSource()
        let coReads = try await adsSource.fetchCoReads(bibcode: bibcode)
        guard !coReads.isEmpty else {
            let err = ExplorationError.noCoReads
            error = err
            throw err
        }

        let collectionName = formatCollectionName("Co-Reads", publication: publication)
        let collection = try await createExplorationCollection(
            name: collectionName,
            papers: coReads,
            parentCollection: parentCollection
        )

        Logger.viewModels.info("ExplorationService: created collection '\(collectionName)' with \(coReads.count) papers")

        // Post notification for sidebar navigation with first publication for auto-selection
        let firstPubID = collection.publications?.first(where: { !$0.isDeleted })?.id
        NotificationCenter.default.post(
            name: .navigateToCollection,
            object: nil,
            userInfo: [
                "collection": collection,
                "firstPublicationID": firstPubID as Any
            ]
        )
        NotificationCenter.default.post(name: .explorationLibraryDidChange, object: nil)

        return collection
    }

    // MARK: - Private Helpers

    /// Fetch similar papers via ADS, resolving bibcode first if needed
    private func fetchSimilarViaADS(identifiers: [IdentifierType: String]) async throws -> [PaperStub] {
        let adsSource = ADSSource()
        // First resolve bibcode
        let resolved = try await adsSource.resolveIdentifier(from: identifiers)
        guard let bibcodeQuery = resolved[IdentifierType.bibcode] else {
            throw ExplorationError.noIdentifiers
        }

        // Fetch similar using resolved bibcode query
        return try await adsSource.fetchSimilar(bibcode: bibcodeQuery)
    }

    /// Fetch co-reads via ADS, resolving bibcode first if needed
    private func fetchCoReadsViaADS(identifiers: [IdentifierType: String]) async throws -> [PaperStub] {
        let adsSource = ADSSource()
        // First resolve bibcode
        let resolved = try await adsSource.resolveIdentifier(from: identifiers)
        guard let bibcodeQuery = resolved[IdentifierType.bibcode] else {
            throw ExplorationError.noIdentifiers
        }

        // Fetch co-reads using resolved bibcode query
        return try await adsSource.fetchCoReads(bibcode: bibcodeQuery)
    }

    /// Format a collection name from a publication
    private func formatCollectionName(_ prefix: String, publication: CDPublication) -> String {
        let firstAuthor = publication.sortedAuthors.first?.familyName
            ?? publication.authorString.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
            ?? "Unknown"

        if publication.year > 0 {
            return "\(prefix): \(firstAuthor) (\(publication.year))"
        } else {
            return "\(prefix): \(firstAuthor)"
        }
    }

    /// Create an exploration collection and import papers into it
    private func createExplorationCollection(
        name: String,
        papers: [PaperStub],
        parentCollection: CDCollection?
    ) async throws -> CDCollection {
        let context = persistenceController.viewContext

        // Get or create exploration library
        let library = libraryManager.getOrCreateExplorationLibrary()

        // Create collection
        let collection = CDCollection(context: context)
        collection.id = UUID()
        collection.name = name
        collection.isSystemCollection = false
        collection.isSmartCollection = false
        collection.isSmartSearchResults = false
        collection.library = library
        collection.parentCollection = parentCollection

        // Import papers - they already have citation/reference counts from ADS
        for stub in papers {
            let publication = createPublication(from: stub, context: context)
            publication.addToCollection(collection)
            publication.addToLibrary(library)
        }

        persistenceController.save()

        // Note: No enrichment queueing needed - papers from exploration already have
        // citation counts and reference counts from the ADS refs/cites query

        return collection
    }

    /// Create a CDPublication from a PaperStub
    private func createPublication(from stub: PaperStub, context: NSManagedObjectContext) -> CDPublication {
        let pub = CDPublication(context: context)
        pub.id = UUID()
        pub.citeKey = generateCiteKey(from: stub)
        pub.entryType = "article"
        pub.title = stub.title
        pub.year = Int16(stub.year ?? 0)
        pub.dateAdded = Date()
        pub.dateModified = Date()

        // Store abstract if available
        if let abstract = stub.abstract {
            pub.abstract = abstract
        }

        // Store identifiers in fields
        var fields: [String: String] = [:]

        // Store authors only if non-empty
        if !stub.authors.isEmpty {
            fields["author"] = stub.authors.joined(separator: " and ")
        }

        if let venue = stub.venue {
            fields["journal"] = venue
        }
        if let doi = stub.doi {
            pub.doi = doi
            fields["doi"] = doi
        }
        if let arxiv = stub.arxivID {
            fields["eprint"] = arxiv
        }

        // Store bibcode (stub.id is the ADS bibcode)
        // This enables further enrichment and ADS lookups
        fields["bibcode"] = stub.id

        pub.fields = fields

        // Store citation count if available
        if let count = stub.citationCount {
            pub.citationCount = Int32(count)
        }

        // Store reference count if available
        if let count = stub.referenceCount {
            pub.referenceCount = Int32(count)
        }

        // Mark as enriched since we have counts from the ADS refs/cites query
        // This prevents unnecessary re-enrichment
        if stub.citationCount != nil || stub.referenceCount != nil {
            pub.enrichmentDate = Date()
            pub.enrichmentSource = "ads"
        }

        return pub
    }

    /// Generate a cite key from a PaperStub
    private func generateCiteKey(from stub: PaperStub) -> String {
        let firstAuthor = stub.authors.first?
            .components(separatedBy: ",").first?
            .components(separatedBy: " ").last?
            .trimmingCharacters(in: .whitespaces)
            ?? "Unknown"

        let year = stub.year.map { String($0) } ?? ""

        let titleWord = stub.title
            .components(separatedBy: .whitespaces)
            .first { $0.count > 3 }?
            .capitalized
            ?? ""

        return "\(firstAuthor)\(year)\(titleWord)"
    }
}

// MARK: - Exploration Error

public enum ExplorationError: LocalizedError {
    case notConfigured
    case noIdentifiers
    case noReferences
    case noCitations
    case noSimilar
    case noCoReads
    case enrichmentFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Exploration service is not configured"
        case .noIdentifiers:
            return "Publication has no identifiers (DOI, arXiv, bibcode)"
        case .noReferences:
            return "No references found for this publication"
        case .noCitations:
            return "No citations found for this publication"
        case .noSimilar:
            return "No similar papers found for this publication"
        case .noCoReads:
            return "No co-read papers found for this publication"
        case .enrichmentFailed(let error):
            return "Failed to fetch data: \(error.localizedDescription)"
        }
    }
}

// MARK: - CDPublication Extension

extension CDPublication {
    /// Get all identifiers for this publication
    public var allIdentifiers: [IdentifierType: String] {
        var identifiers: [IdentifierType: String] = [:]

        if let doi = doi, !doi.isEmpty {
            identifiers[.doi] = doi
        }
        if let arxiv = arxivID, !arxiv.isEmpty {
            identifiers[.arxiv] = arxiv
        }
        if let bibcode = bibcode, !bibcode.isEmpty {
            identifiers[.bibcode] = bibcode
        }
        if let pmid = pmid, !pmid.isEmpty {
            identifiers[.pmid] = pmid
        }

        return identifiers
    }
}
