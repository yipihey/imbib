//
//  SciXLibraryRepository.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-09.
//

import Foundation
import CoreData
import OSLog

/// Repository for managing SciX library entities in Core Data.
/// Provides local cache operations and queues changes for sync.
@MainActor
public final class SciXLibraryRepository: ObservableObject {

    // MARK: - Singleton

    public static let shared = SciXLibraryRepository()

    // MARK: - Properties

    private let context: NSManagedObjectContext

    @Published public private(set) var libraries: [CDSciXLibrary] = []

    // MARK: - Initialization

    public init(context: NSManagedObjectContext? = nil) {
        self.context = context ?? PersistenceController.shared.viewContext
        loadLibraries()
    }

    // MARK: - Loading

    /// Load all cached SciX libraries from Core Data
    public func loadLibraries() {
        let request = NSFetchRequest<CDSciXLibrary>(entityName: "SciXLibrary")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDSciXLibrary.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \CDSciXLibrary.name, ascending: true)
        ]

        do {
            libraries = try context.fetch(request)
            Logger.scix.debug("Loaded \(self.libraries.count) SciX libraries from cache")
        } catch {
            Logger.scix.error("Failed to load SciX libraries: \(error)")
            libraries = []
        }
    }

    /// Find a library by remote ID
    public func findLibrary(remoteID: String) -> CDSciXLibrary? {
        libraries.first { $0.remoteID == remoteID }
    }

    /// Find a library by UUID
    public func findLibrary(id: UUID) -> CDSciXLibrary? {
        libraries.first { $0.id == id }
    }

    // MARK: - Cache Operations

    /// Update or create a library from remote metadata
    public func upsertFromRemote(_ metadata: SciXLibraryMetadata) -> CDSciXLibrary {
        let library = findLibrary(remoteID: metadata.id) ?? createLibrary(remoteID: metadata.id)

        library.name = metadata.name
        library.descriptionText = metadata.description
        library.isPublic = metadata.public
        library.permissionLevel = metadata.permission
        library.ownerEmail = metadata.owner
        library.documentCount = Int32(metadata.num_documents)
        library.lastSyncDate = Date()

        // Only set to synced if no pending changes
        if library.pendingChanges?.isEmpty ?? true {
            library.syncState = CDSciXLibrary.SyncState.synced.rawValue
        }

        save()
        loadLibraries()
        return library
    }

    /// Create a new library entity (before syncing to remote)
    public func createLibrary(remoteID: String) -> CDSciXLibrary {
        let library = CDSciXLibrary(context: context)
        library.id = UUID()
        library.remoteID = remoteID
        library.name = ""
        library.dateCreated = Date()
        library.syncState = CDSciXLibrary.SyncState.synced.rawValue
        library.permissionLevel = CDSciXLibrary.PermissionLevel.owner.rawValue
        library.sortOrder = Int16(libraries.count)
        return library
    }

    /// Cache publications for a library
    public func cachePapers(_ publications: [CDPublication], forLibrary library: CDSciXLibrary) {
        // Clear existing publications from this library
        library.publications = []

        // Add publications to library
        for publication in publications {
            var scixLibs = publication.scixLibraries ?? []
            scixLibs.insert(library)
            publication.scixLibraries = scixLibs
        }

        library.documentCount = Int32(publications.count)
        library.lastSyncDate = Date()
        library.syncState = CDSciXLibrary.SyncState.synced.rawValue

        save()
    }

    /// Delete a library from local cache
    public func deleteLibrary(_ library: CDSciXLibrary) {
        // Remove library association from publications (don't delete the publications)
        if let publications = library.publications {
            for publication in publications {
                publication.scixLibraries?.remove(library)
            }
        }

        context.delete(library)
        save()
        loadLibraries()
    }

    // MARK: - Pending Changes Queue

    /// Queue adding documents to a library (for later sync)
    public func queueAddDocuments(library: CDSciXLibrary, bibcodes: [String]) {
        guard library.canEdit else {
            Logger.scix.warning("Cannot add to read-only library")
            return
        }

        let change = CDSciXPendingChange(context: context)
        change.id = UUID()
        change.action = CDSciXPendingChange.Action.add.rawValue
        change.bibcodes = bibcodes
        change.dateCreated = Date()
        change.library = library

        library.syncState = CDSciXLibrary.SyncState.pending.rawValue

        save()
        objectWillChange.send()
    }

    /// Queue removing documents from a library (for later sync)
    public func queueRemoveDocuments(library: CDSciXLibrary, bibcodes: [String]) {
        guard library.canEdit else {
            Logger.scix.warning("Cannot remove from read-only library")
            return
        }

        let change = CDSciXPendingChange(context: context)
        change.id = UUID()
        change.action = CDSciXPendingChange.Action.remove.rawValue
        change.bibcodes = bibcodes
        change.dateCreated = Date()
        change.library = library

        library.syncState = CDSciXLibrary.SyncState.pending.rawValue

        save()
        objectWillChange.send()
    }

    /// Queue metadata update for a library (for later sync)
    public func queueMetadataUpdate(
        library: CDSciXLibrary,
        name: String? = nil,
        description: String? = nil,
        isPublic: Bool? = nil
    ) {
        guard library.canEdit else {
            Logger.scix.warning("Cannot update read-only library")
            return
        }

        let change = CDSciXPendingChange(context: context)
        change.id = UUID()
        change.action = CDSciXPendingChange.Action.updateMeta.rawValue
        change.metadata = CDSciXPendingChange.MetadataUpdate(
            name: name,
            description: description,
            isPublic: isPublic
        )
        change.dateCreated = Date()
        change.library = library

        library.syncState = CDSciXLibrary.SyncState.pending.rawValue

        // Apply changes locally immediately (optimistic update)
        if let name = name {
            library.name = name
        }
        if let description = description {
            library.descriptionText = description
        }
        if let isPublic = isPublic {
            library.isPublic = isPublic
        }

        save()
        loadLibraries()
    }

    /// Get all pending changes for a library
    public func getPendingChanges(for library: CDSciXLibrary) -> [CDSciXPendingChange] {
        Array(library.pendingChanges ?? [])
            .sorted { $0.dateCreated < $1.dateCreated }
    }

    /// Clear pending changes after successful sync
    public func clearPendingChanges(for library: CDSciXLibrary) {
        guard let changes = library.pendingChanges else { return }

        for change in changes {
            context.delete(change)
        }

        library.syncState = CDSciXLibrary.SyncState.synced.rawValue
        save()
        objectWillChange.send()
    }

    /// Discard a specific pending change (revert local change)
    public func discardChange(_ change: CDSciXPendingChange) {
        guard let library = change.library else {
            context.delete(change)
            save()
            return
        }

        // Revert local changes if it was a metadata update
        if change.actionEnum == .updateMeta {
            // We'd need to reload from server to fully revert
            // For now just mark as needing sync
            library.syncState = CDSciXLibrary.SyncState.pending.rawValue
        }

        context.delete(change)

        // If no more pending changes, mark as synced
        if library.pendingChanges?.isEmpty ?? true {
            library.syncState = CDSciXLibrary.SyncState.synced.rawValue
        }

        save()
        objectWillChange.send()
    }

    // MARK: - Library Operations

    /// Add publications to a SciX library (queues for sync)
    public func addPublications(_ publications: [CDPublication], to library: CDSciXLibrary) {
        let bibcodes = publications.compactMap { $0.bibcode }
        guard !bibcodes.isEmpty else { return }

        // Add locally
        for publication in publications {
            var scixLibs = publication.scixLibraries ?? []
            scixLibs.insert(library)
            publication.scixLibraries = scixLibs
        }

        // Queue for sync
        queueAddDocuments(library: library, bibcodes: bibcodes)
    }

    /// Remove publications from a SciX library (queues for sync)
    public func removePublications(_ publications: [CDPublication], from library: CDSciXLibrary) {
        let bibcodes = publications.compactMap { $0.bibcode }
        guard !bibcodes.isEmpty else { return }

        // Remove locally
        for publication in publications {
            publication.scixLibraries?.remove(library)
        }

        // Queue for sync
        queueRemoveDocuments(library: library, bibcodes: bibcodes)
    }

    /// Update library sort order
    public func updateSortOrder(_ orderedLibraries: [CDSciXLibrary]) {
        for (index, library) in orderedLibraries.enumerated() {
            library.sortOrder = Int16(index)
        }
        save()
        loadLibraries()
    }

    // MARK: - Save

    private func save() {
        guard context.hasChanges else { return }

        do {
            try context.save()
        } catch {
            Logger.scix.error("Failed to save SciX library changes: \(error)")
        }
    }
}
