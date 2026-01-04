//
//  SmartSearchProvider.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import CoreData

// MARK: - Smart Search Provider

/// A paper provider backed by a saved search query.
///
/// Smart searches store the query definition and execute on demand,
/// caching results for the session.
public actor SmartSearchProvider: PaperProvider {
    public typealias Paper = OnlinePaper

    // MARK: - Properties

    public nonisolated let id: UUID
    public nonisolated let name: String
    public nonisolated let providerType: PaperProviderType = .smartSearch

    private let query: String
    private let sourceIDs: [String]
    private let sourceManager: SourceManager

    private var cachedPapers: [OnlinePaper] = []
    private var lastFetched: Date?
    private var _isLoading = false

    // MARK: - Initialization

    public init(
        id: UUID,
        name: String,
        query: String,
        sourceIDs: [String],
        sourceManager: SourceManager
    ) {
        self.id = id
        self.name = name
        self.query = query
        self.sourceIDs = sourceIDs
        self.sourceManager = sourceManager
    }

    /// Create from a Core Data smart search entity
    public init(from entity: CDSmartSearch, sourceManager: SourceManager) {
        self.id = entity.id
        self.name = entity.name
        self.query = entity.query
        self.sourceIDs = entity.sources
        self.sourceManager = sourceManager
    }

    // MARK: - PaperProvider

    public var isLoading: Bool {
        _isLoading
    }

    public var papers: [OnlinePaper] {
        cachedPapers
    }

    public var count: Int {
        cachedPapers.count
    }

    public func refresh() async throws {
        _isLoading = true
        defer { _isLoading = false }

        // Build search options
        let options = SearchOptions(
            sourceIDs: sourceIDs.isEmpty ? nil : sourceIDs
        )

        // Execute the search
        let results = try await sourceManager.search(
            query: query,
            options: options
        )

        // Convert to OnlinePaper
        cachedPapers = results.map { result in
            OnlinePaper(result: result, smartSearchID: id)
        }

        lastFetched = Date()

        // Cache in SessionCache for PDF/BibTeX access
        await SessionCache.shared.cacheSearchResults(
            results,
            for: query,
            sourceIDs: sourceIDs
        )
    }

    // MARK: - Cache State

    /// Time since last fetch, or nil if never fetched
    public var timeSinceLastFetch: TimeInterval? {
        guard let lastFetched else { return nil }
        return Date().timeIntervalSince(lastFetched)
    }

    /// Whether cached results are stale (>1 hour old)
    public var isStale: Bool {
        guard let elapsed = timeSinceLastFetch else { return true }
        return elapsed > 3600  // 1 hour
    }

    /// Clear cached results
    public func clearCache() {
        cachedPapers = []
        lastFetched = nil
    }
}

// MARK: - Smart Search Repository

/// Repository for managing smart search definitions in Core Data.
///
/// Smart searches are library-specific - each library has its own set of smart searches.
@MainActor
public final class SmartSearchRepository: ObservableObject {

    // MARK: - Properties

    @Published public private(set) var smartSearches: [CDSmartSearch] = []

    /// Current library being filtered (nil = show all)
    public private(set) var currentLibrary: CDLibrary?

    private let persistenceController: PersistenceController

    // MARK: - Shared Instance

    public static let shared = SmartSearchRepository()

    // MARK: - Initialization

    public init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - Load

    /// Load all smart searches (unfiltered)
    public func loadSmartSearches() {
        loadSmartSearches(for: currentLibrary)
    }

    /// Load smart searches for a specific library
    public func loadSmartSearches(for library: CDLibrary?) {
        currentLibrary = library

        let request = NSFetchRequest<CDSmartSearch>(entityName: "SmartSearch")
        request.sortDescriptors = [
            NSSortDescriptor(key: "order", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]

        // Filter by library if provided
        if let library {
            request.predicate = NSPredicate(format: "library == %@", library)
        }

        do {
            smartSearches = try persistenceController.viewContext.fetch(request)
        } catch {
            smartSearches = []
        }
    }

    // MARK: - CRUD

    /// Create a new smart search for the specified library
    @discardableResult
    public func create(
        name: String,
        query: String,
        sourceIDs: [String] = [],
        library: CDLibrary? = nil
    ) -> CDSmartSearch {
        let context = persistenceController.viewContext

        let smartSearch = CDSmartSearch(context: context)
        smartSearch.id = UUID()
        smartSearch.name = name
        smartSearch.query = query
        smartSearch.sources = sourceIDs
        smartSearch.dateCreated = Date()
        smartSearch.library = library ?? currentLibrary

        // Set order based on existing searches in this library
        let existingCount = (library ?? currentLibrary)?.smartSearches?.count ?? smartSearches.count
        smartSearch.order = Int16(existingCount)

        persistenceController.save()
        loadSmartSearches(for: currentLibrary)

        return smartSearch
    }

    /// Update an existing smart search
    public func update(
        _ smartSearch: CDSmartSearch,
        name: String? = nil,
        query: String? = nil,
        sourceIDs: [String]? = nil
    ) {
        if let name { smartSearch.name = name }
        if let query { smartSearch.query = query }
        if let sourceIDs { smartSearch.sources = sourceIDs }

        persistenceController.save()
        loadSmartSearches(for: currentLibrary)
    }

    /// Delete a smart search
    public func delete(_ smartSearch: CDSmartSearch) {
        persistenceController.viewContext.delete(smartSearch)
        persistenceController.save()
        loadSmartSearches(for: currentLibrary)
    }

    /// Reorder smart searches
    public func reorder(_ searches: [CDSmartSearch]) {
        for (index, search) in searches.enumerated() {
            search.order = Int16(index)
        }
        persistenceController.save()
        loadSmartSearches(for: currentLibrary)
    }

    /// Mark a smart search as recently executed
    public func markExecuted(_ smartSearch: CDSmartSearch) {
        smartSearch.dateLastExecuted = Date()
        persistenceController.save()
    }

    /// Move a smart search to a different library
    public func move(_ smartSearch: CDSmartSearch, to library: CDLibrary) {
        smartSearch.library = library
        persistenceController.save()
        loadSmartSearches(for: currentLibrary)
    }

    // MARK: - Lookup

    /// Find a smart search by ID
    public func find(id: UUID) -> CDSmartSearch? {
        smartSearches.first { $0.id == id }
    }

    /// Create providers for all smart searches in current library
    public func createProviders(sourceManager: SourceManager) -> [SmartSearchProvider] {
        smartSearches.map { SmartSearchProvider(from: $0, sourceManager: sourceManager) }
    }

    /// Get all smart searches for a specific library
    public func smartSearches(for library: CDLibrary) -> [CDSmartSearch] {
        Array(library.smartSearches ?? []).sorted { $0.order < $1.order }
    }
}

// MARK: - Smart Search Definition

/// A Sendable snapshot of a smart search definition
public struct SmartSearchDefinition: Sendable, Identifiable, Codable, Hashable {
    public let id: UUID
    public let name: String
    public let query: String
    public let sourceIDs: [String]
    public let dateCreated: Date
    public let dateLastExecuted: Date?
    public let order: Int

    public init(
        id: UUID = UUID(),
        name: String,
        query: String,
        sourceIDs: [String] = [],
        dateCreated: Date = Date(),
        dateLastExecuted: Date? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.query = query
        self.sourceIDs = sourceIDs
        self.dateCreated = dateCreated
        self.dateLastExecuted = dateLastExecuted
        self.order = order
    }

    public init(from entity: CDSmartSearch) {
        self.id = entity.id
        self.name = entity.name
        self.query = entity.query
        self.sourceIDs = entity.sources
        self.dateCreated = entity.dateCreated
        self.dateLastExecuted = entity.dateLastExecuted
        self.order = Int(entity.order)
    }
}
