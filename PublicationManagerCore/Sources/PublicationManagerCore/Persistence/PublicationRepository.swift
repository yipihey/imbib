//
//  PublicationRepository.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import CoreData
import OSLog

// MARK: - Publication Repository

/// Data access layer for publications.
/// Abstracts Core Data operations for the rest of the app.
public actor PublicationRepository {

    // MARK: - Properties

    private let persistenceController: PersistenceController

    // MARK: - Initialization

    public init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - Fetch Operations

    /// Fetch all publications
    public func fetchAll(sortedBy sortKey: String = "dateAdded", ascending: Bool = false) async -> [CDPublication] {
        Logger.persistence.entering()
        defer { Logger.persistence.exiting() }

        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDPublication>(entityName: "Publication")
            request.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: ascending)]

            do {
                return try context.fetch(request)
            } catch {
                Logger.persistence.error("Failed to fetch publications: \(error.localizedDescription)")
                return []
            }
        }
    }

    /// Fetch publication by cite key
    public func fetch(byCiteKey citeKey: String) async -> CDPublication? {
        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDPublication>(entityName: "Publication")
            request.predicate = NSPredicate(format: "citeKey == %@", citeKey)
            request.fetchLimit = 1

            return try? context.fetch(request).first
        }
    }

    /// Fetch publication by ID
    public func fetch(byID id: UUID) async -> CDPublication? {
        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDPublication>(entityName: "Publication")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1

            return try? context.fetch(request).first
        }
    }

    /// Search publications by title or author
    public func search(query: String) async -> [CDPublication] {
        guard !query.isEmpty else { return await fetchAll() }

        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDPublication>(entityName: "Publication")
            request.predicate = NSPredicate(
                format: "title CONTAINS[cd] %@ OR citeKey CONTAINS[cd] %@",
                query, query
            )
            request.sortDescriptors = [NSSortDescriptor(key: "dateModified", ascending: false)]

            do {
                return try context.fetch(request)
            } catch {
                Logger.persistence.error("Search failed: \(error.localizedDescription)")
                return []
            }
        }
    }

    /// Get all existing cite keys
    public func allCiteKeys() async -> Set<String> {
        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDPublication>(entityName: "Publication")
            request.propertiesToFetch = ["citeKey"]

            do {
                let pubs = try context.fetch(request)
                return Set(pubs.map { $0.citeKey })
            } catch {
                Logger.persistence.error("Failed to fetch cite keys: \(error.localizedDescription)")
                return []
            }
        }
    }

    // MARK: - Create Operations

    /// Create a new publication from BibTeX entry
    @discardableResult
    public func create(from entry: BibTeXEntry) async -> CDPublication {
        Logger.persistence.info("Creating publication: \(entry.citeKey)")
        let context = persistenceController.viewContext

        return await context.perform {
            let publication = CDPublication(context: context)
            publication.id = UUID()
            publication.dateAdded = Date()
            publication.update(from: entry, context: context)

            self.persistenceController.save()
            return publication
        }
    }

    /// Import multiple entries
    public func importEntries(_ entries: [BibTeXEntry]) async -> Int {
        Logger.persistence.info("Importing \(entries.count) entries")

        var imported = 0
        for entry in entries {
            // Check for duplicate
            if await fetch(byCiteKey: entry.citeKey) == nil {
                await create(from: entry)
                imported += 1
            } else {
                Logger.persistence.debug("Skipping duplicate: \(entry.citeKey)")
            }
        }

        Logger.persistence.info("Imported \(imported) new entries")
        return imported
    }

    // MARK: - Update Operations

    /// Update an existing publication
    public func update(_ publication: CDPublication, with entry: BibTeXEntry) async {
        Logger.persistence.info("Updating publication: \(publication.citeKey)")
        let context = persistenceController.viewContext

        await context.perform {
            publication.update(from: entry, context: context)
            self.persistenceController.save()
        }
    }

    // MARK: - Delete Operations

    /// Delete a publication
    public func delete(_ publication: CDPublication) async {
        Logger.persistence.info("Deleting publication: \(publication.citeKey)")
        let context = persistenceController.viewContext

        await context.perform {
            context.delete(publication)
            self.persistenceController.save()
        }
    }

    /// Delete multiple publications
    public func delete(_ publications: [CDPublication]) async {
        guard !publications.isEmpty else { return }
        Logger.persistence.info("Deleting \(publications.count) publications")

        let context = persistenceController.viewContext

        await context.perform {
            for publication in publications {
                context.delete(publication)
            }
            self.persistenceController.save()
        }
    }

    // MARK: - Export Operations

    /// Export all publications to BibTeX string
    public func exportAll() async -> String {
        let publications = await fetchAll(sortedBy: "citeKey", ascending: true)
        let entries = publications.map { $0.toBibTeXEntry() }
        return BibTeXExporter().export(entries)
    }

    /// Export selected publications to BibTeX string
    public func export(_ publications: [CDPublication]) -> String {
        let entries = publications.map { $0.toBibTeXEntry() }
        return BibTeXExporter().export(entries)
    }
}

// MARK: - Tag Repository

public actor TagRepository {

    private let persistenceController: PersistenceController

    public init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    /// Fetch all tags
    public func fetchAll() async -> [CDTag] {
        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDTag>(entityName: "Tag")
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

            return (try? context.fetch(request)) ?? []
        }
    }

    /// Create or find tag by name
    public func findOrCreate(name: String) async -> CDTag {
        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDTag>(entityName: "Tag")
            request.predicate = NSPredicate(format: "name ==[cd] %@", name)
            request.fetchLimit = 1

            if let existing = try? context.fetch(request).first {
                return existing
            }

            let tag = CDTag(context: context)
            tag.id = UUID()
            tag.name = name
            self.persistenceController.save()
            return tag
        }
    }
}

// MARK: - Collection Repository

public actor CollectionRepository {

    private let persistenceController: PersistenceController

    public init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    /// Fetch all collections
    public func fetchAll() async -> [CDCollection] {
        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDCollection>(entityName: "Collection")
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

            return (try? context.fetch(request)) ?? []
        }
    }

    /// Create a new collection
    @discardableResult
    public func create(name: String, isSmartCollection: Bool = false, predicate: String? = nil) async -> CDCollection {
        let context = persistenceController.viewContext

        return await context.perform {
            let collection = CDCollection(context: context)
            collection.id = UUID()
            collection.name = name
            collection.isSmartCollection = isSmartCollection
            collection.predicate = predicate
            self.persistenceController.save()
            return collection
        }
    }
}
