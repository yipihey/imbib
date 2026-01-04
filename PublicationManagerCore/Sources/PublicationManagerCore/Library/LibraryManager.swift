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

    /// All known libraries
    public private(set) var libraries: [CDLibrary] = []

    /// Currently active library
    public private(set) var activeLibrary: CDLibrary?

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
    }

    // MARK: - Library Loading

    /// Load all libraries from Core Data
    public func loadLibraries() {
        let request = NSFetchRequest<CDLibrary>(entityName: "Library")
        request.sortDescriptors = [
            NSSortDescriptor(key: "dateLastOpened", ascending: false),
            NSSortDescriptor(key: "name", ascending: true)
        ]

        do {
            libraries = try persistenceController.viewContext.fetch(request)

            // Set active to default library if not set
            if activeLibrary == nil {
                activeLibrary = libraries.first { $0.isDefault } ?? libraries.first
            }
        } catch {
            Logger.persistence.error("Failed to load libraries: \(error.localizedDescription)")
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
        let context = persistenceController.viewContext

        let library = CDLibrary(context: context)
        library.id = UUID()
        library.name = name
        library.bibFilePath = bibFileURL?.path
        library.papersDirectoryPath = papersDirectoryURL?.path
        library.dateCreated = Date()
        library.isDefault = libraries.isEmpty  // First library is default

        // Create security-scoped bookmark if URL provided
        if let url = bibFileURL {
            library.bookmarkData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }

        persistenceController.save()
        loadLibraries()

        return library
    }

    /// Open an existing .bib file as a library
    @discardableResult
    public func openLibrary(at url: URL) throws -> CDLibrary {
        // Check if already open
        if let existing = libraries.first(where: { $0.bibFilePath == url.path }) {
            setActive(existing)
            return existing
        }

        // Create security-scoped bookmark
        guard url.startAccessingSecurityScopedResource() else {
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

        persistenceController.save()
        setActive(library)

        return library
    }

    /// Set the active library
    public func setActive(_ library: CDLibrary) {
        library.dateLastOpened = Date()
        activeLibrary = library
        persistenceController.save()

        // Post notification for UI updates
        NotificationCenter.default.post(name: .activeLibraryChanged, object: library)
    }

    /// Close a library (remove from list but don't delete data)
    public func closeLibrary(_ library: CDLibrary) {
        if activeLibrary?.id == library.id {
            // Switch to another library
            activeLibrary = libraries.first { $0.id != library.id }
        }

        persistenceController.viewContext.delete(library)
        persistenceController.save()
        loadLibraries()
    }

    /// Delete a library and optionally its files
    public func deleteLibrary(_ library: CDLibrary, deleteFiles: Bool = false) throws {
        if deleteFiles {
            // Delete .bib file
            if let path = library.bibFilePath {
                try? FileManager.default.removeItem(atPath: path)
            }
            // Delete Papers directory
            if let path = library.papersDirectoryPath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }

        closeLibrary(library)
    }

    /// Set a library as the default
    public func setDefault(_ library: CDLibrary) {
        // Clear existing default
        for lib in libraries {
            lib.isDefault = (lib.id == library.id)
        }
        persistenceController.save()
    }

    /// Rename a library
    public func rename(_ library: CDLibrary, to name: String) {
        library.name = name
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
