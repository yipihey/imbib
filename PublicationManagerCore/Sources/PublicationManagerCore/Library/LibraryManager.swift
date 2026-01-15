//
//  LibraryManager.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import CoreData
import OSLog

// MARK: - Library Manager

/// Manages multiple publication libraries.
///
/// Each library represents a separate .bib file and associated PDF collection.
/// Libraries can be opened, closed, and switched between. The active library
/// determines which publications and smart searches are shown.
@MainActor
@Observable
public final class LibraryManager {

    // MARK: - Published State

    /// All known libraries (excludes system libraries like Exploration)
    public private(set) var libraries: [CDLibrary] = []

    /// Currently active library
    public private(set) var activeLibrary: CDLibrary?

    /// The Exploration system library (for references/citations exploration)
    public private(set) var explorationLibrary: CDLibrary?

    /// Recently opened libraries (for menu)
    public var recentLibraries: [CDLibrary] {
        libraries
            .filter { $0.dateLastOpened != nil }
            .sorted { ($0.dateLastOpened ?? .distantPast) > ($1.dateLastOpened ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Dependencies

    private let persistenceController: PersistenceController

    // MARK: - Initialization

    public init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
        loadLibraries()

        // Load default library set if none exist (first run)
        if libraries.isEmpty {
            Logger.library.infoCapture("No libraries found, loading default set", category: "library")
            do {
                try DefaultLibrarySetManager.shared.loadDefaultSet()
                loadLibraries()  // Reload after import
            } catch {
                // Fallback: create empty library if default set fails
                Logger.library.warningCapture("Failed to load default set, creating fallback library: \(error.localizedDescription)", category: "library")
                _ = createLibrary(name: "My Library")
            }
        }
    }

    // MARK: - Library Loading

    /// Load all libraries from Core Data
    public func loadLibraries() {
        Logger.library.debugCapture("Loading libraries from Core Data", category: "library")

        let request = NSFetchRequest<CDLibrary>(entityName: "Library")
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]

        do {
            let allLibraries = try persistenceController.viewContext.fetch(request)

            // Separate system libraries from user libraries
            libraries = allLibraries.filter { !$0.isSystemLibrary }
            explorationLibrary = allLibraries.first { $0.isSystemLibrary && $0.name == "Exploration" }

            Logger.library.infoCapture("Loaded \(libraries.count) libraries + \(explorationLibrary != nil ? "1" : "0") system library", category: "library")

            // Set active to default library if not set
            if activeLibrary == nil {
                activeLibrary = libraries.first { $0.isDefault } ?? libraries.first
                if let active = activeLibrary {
                    Logger.library.infoCapture("Set active library: \(active.displayName)", category: "library")
                }
            }
        } catch {
            Logger.library.errorCapture("Failed to load libraries: \(error.localizedDescription)", category: "library")
            libraries = []
        }
    }

    // MARK: - Library Management

    /// Create a new library
    @discardableResult
    public func createLibrary(
        name: String,
        bibFileURL: URL? = nil,
        papersDirectoryURL: URL? = nil
    ) -> CDLibrary {
        Logger.library.infoCapture("Creating library: \(name)", category: "library")

        let context = persistenceController.viewContext

        let library = CDLibrary(context: context)
        library.id = UUID()
        library.name = name
        library.bibFilePath = bibFileURL?.path
        library.papersDirectoryPath = papersDirectoryURL?.path
        library.dateCreated = Date()
        library.isDefault = libraries.isEmpty  // First library is default

        // Create security-scoped bookmark if URL provided (macOS only)
        #if os(macOS)
        if let url = bibFileURL {
            library.bookmarkData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            Logger.library.debugCapture("Created security-scoped bookmark for: \(url.lastPathComponent)", category: "library")
        }
        #endif

        persistenceController.save()
        loadLibraries()

        Logger.library.infoCapture("Created library '\(name)' with ID: \(library.id)", category: "library")
        return library
    }

    /// Open an existing .bib file as a library
    @discardableResult
    public func openLibrary(at url: URL) throws -> CDLibrary {
        Logger.library.infoCapture("Opening library at: \(url.lastPathComponent)", category: "library")

        // Check if already open
        if let existing = libraries.first(where: { $0.bibFilePath == url.path }) {
            Logger.library.debugCapture("Library already open, switching to: \(existing.displayName)", category: "library")
            setActive(existing)
            return existing
        }

        #if os(macOS)
        // Create security-scoped bookmark (macOS only)
        guard url.startAccessingSecurityScopedResource() else {
            Logger.library.errorCapture("Access denied to: \(url.lastPathComponent)", category: "library")
            throw LibraryError.accessDenied(url)
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let library = createLibrary(
            name: url.deletingPathExtension().lastPathComponent,
            bibFileURL: url
        )
        library.bookmarkData = bookmarkData
        #else
        // iOS: Files are accessed via document picker, no security scoping needed
        let library = createLibrary(
            name: url.deletingPathExtension().lastPathComponent,
            bibFileURL: url
        )
        #endif

        persistenceController.save()
        setActive(library)

        Logger.library.infoCapture("Opened library: \(library.displayName)", category: "library")
        return library
    }

    /// Set the active library
    public func setActive(_ library: CDLibrary) {
        Logger.library.infoCapture("Switching to library: \(library.displayName)", category: "library")

        library.dateLastOpened = Date()
        activeLibrary = library
        persistenceController.save()

        // Post notification for UI updates
        NotificationCenter.default.post(name: .activeLibraryChanged, object: library)
    }

    /// Close a library (remove from list but don't delete data)
    public func closeLibrary(_ library: CDLibrary) {
        Logger.library.infoCapture("Closing library: \(library.displayName)", category: "library")

        if activeLibrary?.id == library.id {
            // Switch to another library
            activeLibrary = libraries.first { $0.id != library.id }
            if let newActive = activeLibrary {
                Logger.library.debugCapture("Switched to library: \(newActive.displayName)", category: "library")
            }
        }

        persistenceController.viewContext.delete(library)
        persistenceController.save()
        loadLibraries()
    }

    /// Delete a library and optionally its files
    public func deleteLibrary(_ library: CDLibrary, deleteFiles: Bool = false) throws {
        Logger.library.warningCapture("Deleting library: \(library.displayName), deleteFiles: \(deleteFiles)", category: "library")

        if deleteFiles {
            // Delete .bib file
            if let path = library.bibFilePath {
                try? FileManager.default.removeItem(atPath: path)
                Logger.library.debugCapture("Deleted .bib file: \(path)", category: "library")
            }
            // Delete Papers directory
            if let path = library.papersDirectoryPath {
                try? FileManager.default.removeItem(atPath: path)
                Logger.library.debugCapture("Deleted Papers directory: \(path)", category: "library")
            }
        }

        closeLibrary(library)
    }

    /// Set a library as the default
    public func setDefault(_ library: CDLibrary) {
        Logger.library.infoCapture("Setting default library: \(library.displayName)", category: "library")

        // Clear existing default
        for lib in libraries {
            lib.isDefault = (lib.id == library.id)
        }
        persistenceController.save()
    }

    /// Rename a library
    public func rename(_ library: CDLibrary, to name: String) {
        Logger.library.infoCapture("Renaming library '\(library.displayName)' to '\(name)'", category: "library")
        library.name = name
        persistenceController.save()
    }

    /// Reorder libraries (for drag-and-drop in sidebar)
    public func moveLibraries(from indices: IndexSet, to destination: Int) {
        Logger.library.infoCapture("Moving libraries from \(indices) to \(destination)", category: "library")

        var reordered = libraries
        reordered.move(fromOffsets: indices, toOffset: destination)

        // Update sortOrder for all libraries
        for (index, library) in reordered.enumerated() {
            library.sortOrder = Int16(index)
        }

        libraries = reordered
        persistenceController.save()
    }

    // MARK: - Library Lookup

    /// Find a library by ID
    public func find(id: UUID) -> CDLibrary? {
        libraries.first { $0.id == id }
    }

    /// Get the default library, creating one if needed
    public func getOrCreateDefaultLibrary() -> CDLibrary {
        if let defaultLib = libraries.first(where: { $0.isDefault }) {
            return defaultLib
        }

        if let firstLib = libraries.first {
            firstLib.isDefault = true
            persistenceController.save()
            return firstLib
        }

        // Create a default library
        return createLibrary(name: "My Library")
    }

    // MARK: - Last Search Collection (ADR-016)

    /// Get or create the "Last Search" collection for the active library.
    ///
    /// This is a system collection that holds ad-hoc search results. Each library
    /// has its own "Last Search" collection. Results are replaced on each new search.
    public func getOrCreateLastSearchCollection() -> CDCollection? {
        guard let library = activeLibrary else {
            Logger.library.warningCapture("No active library for Last Search collection", category: "library")
            return nil
        }

        // Return existing collection if available
        if let collection = library.lastSearchCollection {
            return collection
        }

        // Create new Last Search collection
        Logger.library.infoCapture("Creating Last Search collection for: \(library.displayName)", category: "library")

        let context = persistenceController.viewContext
        let collection = CDCollection(context: context)
        collection.id = UUID()
        collection.name = "Last Search"
        collection.isSystemCollection = true
        collection.isSmartSearchResults = false
        collection.isSmartCollection = false
        collection.owningLibrary = library
        library.lastSearchCollection = collection

        persistenceController.save()

        return collection
    }

    /// Clear the Last Search collection (remove papers only in this collection)
    public func clearLastSearchCollection() {
        guard let collection = activeLibrary?.lastSearchCollection else { return }

        Logger.library.debugCapture("Clearing Last Search collection", category: "library")

        let context = persistenceController.viewContext

        // Get publications only in this collection
        guard let publications = collection.publications else { return }

        for pub in publications {
            // Check if this paper is ONLY in Last Search (not in other collections/smart searches)
            let otherCollections = (pub.collections ?? []).filter { $0.id != collection.id }
            if otherCollections.isEmpty {
                // Paper is only in Last Search - delete it
                context.delete(pub)
            }
        }

        // Clear the collection's publication set
        collection.publications = []
        persistenceController.save()
    }

    // MARK: - Exploration Library

    /// Get or create the Exploration system library.
    ///
    /// This is a system library that holds exploration results (references/citations).
    /// Collections in this library are created when exploring a paper's references or citations.
    @discardableResult
    public func getOrCreateExplorationLibrary() -> CDLibrary {
        // Return existing if available
        if let lib = explorationLibrary {
            return lib
        }

        // Create new Exploration library
        Logger.library.infoCapture("Creating Exploration system library", category: "library")

        let context = persistenceController.viewContext
        let library = CDLibrary(context: context)
        library.id = UUID()
        library.name = "Exploration"
        library.isSystemLibrary = true
        library.isDefault = false
        library.dateCreated = Date()
        library.sortOrder = Int16.max  // Always at the end

        persistenceController.save()

        explorationLibrary = library
        return library
    }

    /// Delete all collections in the Exploration library
    public func clearExplorationLibrary() {
        guard let library = explorationLibrary else { return }

        Logger.library.infoCapture("Clearing Exploration library", category: "library")

        let context = persistenceController.viewContext

        // Delete all collections and their papers
        if let collections = library.collections {
            for collection in collections {
                // Delete papers that are only in exploration collections
                if let publications = collection.publications {
                    for pub in publications {
                        let otherCollections = (pub.collections ?? []).filter {
                            $0.library?.isSystemLibrary != true
                        }
                        if otherCollections.isEmpty {
                            context.delete(pub)
                        }
                    }
                }
                context.delete(collection)
            }
        }

        persistenceController.save()
    }

    /// Delete a specific exploration collection
    public func deleteExplorationCollection(_ collection: CDCollection) {
        guard collection.library?.isSystemLibrary == true else {
            Logger.library.warningCapture("Attempted to delete non-exploration collection", category: "library")
            return
        }

        Logger.library.infoCapture("Deleting exploration collection: \(collection.name)", category: "library")

        let context = persistenceController.viewContext

        // Delete papers that are only in this exploration collection
        if let publications = collection.publications {
            for pub in publications {
                let otherCollections = (pub.collections ?? []).filter { $0.id != collection.id }
                if otherCollections.isEmpty {
                    context.delete(pub)
                }
            }
        }

        // Delete child collections recursively
        if let children = collection.childCollections {
            for child in children {
                deleteExplorationCollection(child)
            }
        }

        context.delete(collection)
        persistenceController.save()
    }
}

// MARK: - Library Error

public enum LibraryError: LocalizedError {
    case accessDenied(URL)
    case notFound(UUID)
    case invalidBibFile(URL)

    public var errorDescription: String? {
        switch self {
        case .accessDenied(let url):
            return "Access denied to \(url.lastPathComponent)"
        case .notFound(let id):
            return "Library not found: \(id)"
        case .invalidBibFile(let url):
            return "Invalid BibTeX file: \(url.lastPathComponent)"
        }
    }
}

// MARK: - Notifications

public extension Notification.Name {
    static let activeLibraryChanged = Notification.Name("activeLibraryChanged")
}

// MARK: - Library Definition (Sendable snapshot)

/// A Sendable snapshot of a library for use in async contexts
public struct LibraryDefinition: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let bibFilePath: String?
    public let papersDirectoryPath: String?
    public let dateCreated: Date
    public let dateLastOpened: Date?
    public let isDefault: Bool

    public init(from entity: CDLibrary) {
        self.id = entity.id
        self.name = entity.displayName
        self.bibFilePath = entity.bibFilePath
        self.papersDirectoryPath = entity.papersDirectoryPath
        self.dateCreated = entity.dateCreated
        self.dateLastOpened = entity.dateLastOpened
        self.isDefault = entity.isDefault
    }
}
