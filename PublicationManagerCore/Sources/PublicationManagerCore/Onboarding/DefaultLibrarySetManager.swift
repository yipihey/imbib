//
//  DefaultLibrarySetManager.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-07.
//

import Foundation
import CoreData
import OSLog

// MARK: - Default Library Set Manager

/// Manages loading and exporting default library sets for onboarding.
///
/// On first launch (no existing libraries), the bundled default set is imported
/// to provide example libraries, smart searches, and collections for new users.
///
/// Development mode allows exporting the current state to JSON for version control.
@MainActor
public final class DefaultLibrarySetManager {

    // MARK: - Shared Instance

    public static let shared = DefaultLibrarySetManager()

    // MARK: - Dependencies

    private let persistenceController: PersistenceController

    // MARK: - Initialization

    public init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - First Launch Detection

    /// Check if this is the first launch (no existing libraries).
    public func isFirstLaunch() -> Bool {
        let context = persistenceController.viewContext
        let request = NSFetchRequest<CDLibrary>(entityName: "Library")
        request.fetchLimit = 1

        do {
            let count = try context.count(for: request)
            return count == 0
        } catch {
            Logger.library.errorCapture("Failed to check library count: \(error.localizedDescription)", category: "onboarding")
            return false
        }
    }

    // MARK: - Load Default Set

    /// Load and import the bundled default library set.
    ///
    /// This creates CDLibrary, CDSmartSearch, and CDCollection entities
    /// from the bundled DefaultLibrarySet.json file.
    public func loadDefaultSet() throws {
        Logger.library.infoCapture("Loading default library set from bundle", category: "onboarding")

        // Find the bundled JSON file
        guard let url = Bundle.main.url(forResource: "DefaultLibrarySet", withExtension: "json") else {
            Logger.library.errorCapture("DefaultLibrarySet.json not found in bundle", category: "onboarding")
            throw DefaultLibrarySetError.bundleNotFound
        }

        // Load and decode
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            Logger.library.errorCapture("Failed to read DefaultLibrarySet.json: \(error.localizedDescription)", category: "onboarding")
            throw DefaultLibrarySetError.decodingFailed(error)
        }

        let defaultSet: DefaultLibrarySet
        do {
            let decoder = JSONDecoder()
            defaultSet = try decoder.decode(DefaultLibrarySet.self, from: data)
        } catch {
            Logger.library.errorCapture("Failed to decode DefaultLibrarySet.json: \(error.localizedDescription)", category: "onboarding")
            throw DefaultLibrarySetError.decodingFailed(error)
        }

        Logger.library.infoCapture("Loaded default set v\(defaultSet.version) with \(defaultSet.libraries.count) libraries", category: "onboarding")

        // Import the set
        try importSet(defaultSet)
    }

    /// Import a DefaultLibrarySet into Core Data.
    private func importSet(_ set: DefaultLibrarySet) throws {
        let context = persistenceController.viewContext

        for (index, defaultLibrary) in set.libraries.enumerated() {
            // Create library
            let library = CDLibrary(context: context)
            library.id = UUID()
            library.name = defaultLibrary.name
            library.dateCreated = Date()
            library.isDefault = defaultLibrary.isDefault
            library.sortOrder = Int16(index)

            Logger.library.debugCapture("Creating library: \(defaultLibrary.name)", category: "onboarding")

            // Create smart searches
            if let smartSearches = defaultLibrary.smartSearches {
                for (ssIndex, defaultSS) in smartSearches.enumerated() {
                    let smartSearch = CDSmartSearch(context: context)
                    smartSearch.id = UUID()
                    smartSearch.name = defaultSS.name
                    smartSearch.query = defaultSS.query
                    smartSearch.sources = defaultSS.sourceIDs ?? []
                    smartSearch.dateCreated = Date()
                    smartSearch.library = library
                    smartSearch.order = Int16(ssIndex)
                    smartSearch.feedsToInbox = defaultSS.feedsToInbox ?? false
                    smartSearch.autoRefreshEnabled = defaultSS.autoRefreshEnabled ?? false
                    smartSearch.refreshIntervalSeconds = Int32(defaultSS.refreshIntervalSeconds ?? 21600)

                    // Create result collection for smart search (ADR-016)
                    let resultCollection = CDCollection(context: context)
                    resultCollection.id = UUID()
                    resultCollection.name = defaultSS.name
                    resultCollection.isSmartSearchResults = true
                    resultCollection.isSmartCollection = false
                    resultCollection.smartSearch = smartSearch
                    smartSearch.resultCollection = resultCollection

                    Logger.library.debugCapture("  Created smart search: \(defaultSS.name)", category: "onboarding")
                }
            }

            // Create collections
            if let collections = defaultLibrary.collections {
                for defaultColl in collections {
                    let collection = CDCollection(context: context)
                    collection.id = UUID()
                    collection.name = defaultColl.name
                    collection.isSmartCollection = false
                    collection.isSmartSearchResults = false
                    collection.isSystemCollection = false
                    collection.library = library

                    Logger.library.debugCapture("  Created collection: \(defaultColl.name)", category: "onboarding")
                }
            }
        }

        // Save
        persistenceController.save()
        Logger.library.infoCapture("Successfully imported default library set", category: "onboarding")
    }

    // MARK: - Export Current State (Development Mode)

    /// Export the current libraries, smart searches, and collections to JSON.
    ///
    /// This is used in development mode to update the bundled DefaultLibrarySet.json.
    public func exportCurrentAsDefaultSet(to url: URL) throws {
        Logger.library.infoCapture("Exporting current state to: \(url.lastPathComponent)", category: "onboarding")

        let context = persistenceController.viewContext

        // Fetch all libraries
        let libraryRequest = NSFetchRequest<CDLibrary>(entityName: "Library")
        libraryRequest.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]

        let libraries: [CDLibrary]
        do {
            libraries = try context.fetch(libraryRequest)
        } catch {
            Logger.library.errorCapture("Failed to fetch libraries for export: \(error.localizedDescription)", category: "onboarding")
            throw DefaultLibrarySetError.encodingFailed(error)
        }

        guard !libraries.isEmpty else {
            throw DefaultLibrarySetError.noLibrariesToExport
        }

        // Build the export structure
        var defaultLibraries: [DefaultLibrary] = []

        for library in libraries {
            // Skip inbox and system libraries
            if library.isInbox {
                continue
            }

            // Export smart searches
            let smartSearches = (library.smartSearches ?? [])
                .sorted { $0.order < $1.order }
                .map { ss in
                    DefaultSmartSearch(
                        name: ss.name,
                        query: ss.query,
                        sourceIDs: ss.sources.isEmpty ? nil : ss.sources,
                        feedsToInbox: ss.feedsToInbox ? true : nil,
                        autoRefreshEnabled: ss.autoRefreshEnabled ? true : nil,
                        refreshIntervalSeconds: ss.autoRefreshEnabled ? Int(ss.refreshIntervalSeconds) : nil
                    )
                }

            // Export user-created collections (not smart search results, not system collections)
            let collections = (library.collections ?? [])
                .filter { !$0.isSmartSearchResults && !$0.isSystemCollection }
                .map { DefaultCollection(name: $0.name) }

            let defaultLibrary = DefaultLibrary(
                name: library.displayName,
                isDefault: library.isDefault,
                smartSearches: smartSearches.isEmpty ? nil : smartSearches,
                collections: collections.isEmpty ? nil : collections
            )

            defaultLibraries.append(defaultLibrary)
        }

        let defaultSet = DefaultLibrarySet(
            version: 1,
            libraries: defaultLibraries
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(defaultSet)
        } catch {
            Logger.library.errorCapture("Failed to encode default set: \(error.localizedDescription)", category: "onboarding")
            throw DefaultLibrarySetError.encodingFailed(error)
        }

        // Write to file
        do {
            try data.write(to: url)
            Logger.library.infoCapture("Successfully exported default set with \(defaultLibraries.count) libraries", category: "onboarding")
        } catch {
            Logger.library.errorCapture("Failed to write default set file: \(error.localizedDescription)", category: "onboarding")
            throw DefaultLibrarySetError.writeFailed(error)
        }
    }
}
