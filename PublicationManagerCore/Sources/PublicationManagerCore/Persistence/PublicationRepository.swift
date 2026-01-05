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
    ///
    /// - Parameters:
    ///   - entry: The BibTeX entry to create from
    ///   - library: Optional library for resolving file paths
    ///   - processLinkedFiles: If true, process Bdsk-File-* fields to create linked file records
    @discardableResult
    public func create(
        from entry: BibTeXEntry,
        in library: CDLibrary? = nil,
        processLinkedFiles: Bool = true
    ) async -> CDPublication {
        Logger.persistence.info("Creating publication: \(entry.citeKey)")
        let context = persistenceController.viewContext

        let publication = await context.perform {
            let publication = CDPublication(context: context)
            publication.id = UUID()
            publication.dateAdded = Date()
            publication.update(from: entry, context: context)

            self.persistenceController.save()
            return publication
        }

        // Process linked files on MainActor
        if processLinkedFiles {
            await MainActor.run {
                PDFManager.shared.processBdskFiles(from: entry, for: publication, in: library)
            }
        }

        return publication
    }

    /// Import multiple entries
    ///
    /// - Parameters:
    ///   - entries: BibTeX entries to import
    ///   - library: Optional library for resolving file paths (for Bdsk-File-* fields)
    public func importEntries(_ entries: [BibTeXEntry], in library: CDLibrary? = nil) async -> Int {
        Logger.persistence.info("Importing \(entries.count) entries")

        var imported = 0
        for entry in entries {
            // Check for duplicate
            if await fetch(byCiteKey: entry.citeKey) == nil {
                await create(from: entry, in: library)
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

    /// Update a single field in a publication
    public func updateField(_ publication: CDPublication, field: String, value: String?) async {
        Logger.persistence.info("Updating field '\(field)' for: \(publication.citeKey)")
        let context = persistenceController.viewContext

        await context.perform {
            var currentFields = publication.fields
            if let value = value, !value.isEmpty {
                currentFields[field] = value
            } else {
                currentFields.removeValue(forKey: field)
            }
            publication.fields = currentFields
            publication.dateModified = Date()
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

    // MARK: - RIS Import Operations

    /// Create a new publication from RIS entry
    ///
    /// Converts the RIS entry to BibTeX internally for storage.
    ///
    /// - Parameters:
    ///   - entry: The RIS entry to create from
    ///   - library: Optional library for resolving file paths
    @discardableResult
    public func create(from entry: RISEntry, in library: CDLibrary? = nil) async -> CDPublication {
        // Convert RIS to BibTeX for storage
        let bibtexEntry = RISBibTeXConverter.toBibTeX(entry)
        Logger.persistence.info("Creating publication from RIS: \(bibtexEntry.citeKey)")
        return await create(from: bibtexEntry, in: library, processLinkedFiles: false)
    }

    /// Import multiple RIS entries
    ///
    /// - Parameters:
    ///   - entries: RIS entries to import
    ///   - library: Optional library for resolving file paths
    public func importRISEntries(_ entries: [RISEntry], in library: CDLibrary? = nil) async -> Int {
        Logger.persistence.info("Importing \(entries.count) RIS entries")

        var imported = 0
        for entry in entries {
            // Convert to BibTeX to get cite key
            let bibtexEntry = RISBibTeXConverter.toBibTeX(entry)

            // Check for duplicate
            if await fetch(byCiteKey: bibtexEntry.citeKey) == nil {
                await create(from: entry, in: library)
                imported += 1
            } else {
                Logger.persistence.debug("Skipping duplicate: \(bibtexEntry.citeKey)")
            }
        }

        Logger.persistence.info("Imported \(imported) new RIS entries")
        return imported
    }

    /// Import RIS content from string
    ///
    /// - Parameters:
    ///   - content: RIS formatted string
    ///   - library: Optional library for resolving file paths
    /// - Returns: Number of entries imported
    public func importRIS(_ content: String, in library: CDLibrary? = nil) async throws -> Int {
        let parser = RISParser()
        let entries = try parser.parse(content)
        return await importRISEntries(entries, in: library)
    }

    /// Import RIS file from URL
    ///
    /// - Parameters:
    ///   - url: URL to the .ris file
    ///   - library: Optional library for resolving file paths
    /// - Returns: Number of entries imported
    public func importRISFile(at url: URL, in library: CDLibrary? = nil) async throws -> Int {
        Logger.persistence.info("Importing RIS file: \(url.lastPathComponent)")
        let content = try String(contentsOf: url, encoding: .utf8)
        return try await importRIS(content, in: library)
    }

    // MARK: - RIS Export Operations

    /// Export all publications to RIS string
    public func exportAllToRIS() async -> String {
        let publications = await fetchAll(sortedBy: "citeKey", ascending: true)
        return exportToRIS(publications)
    }

    /// Export selected publications to RIS string
    public func exportToRIS(_ publications: [CDPublication]) -> String {
        let bibtexEntries = publications.map { $0.toBibTeXEntry() }
        let risEntries = RISBibTeXConverter.toRIS(bibtexEntries)
        return RISExporter().export(risEntries)
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

    /// Fetch only smart collections
    public func fetchSmartCollections() async -> [CDCollection] {
        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDCollection>(entityName: "Collection")
            request.predicate = NSPredicate(format: "isSmartCollection == YES")
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

            return (try? context.fetch(request)) ?? []
        }
    }

    /// Fetch only static collections
    public func fetchStaticCollections() async -> [CDCollection] {
        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDCollection>(entityName: "Collection")
            request.predicate = NSPredicate(format: "isSmartCollection == NO")
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

            return (try? context.fetch(request)) ?? []
        }
    }

    /// Create a new collection
    @discardableResult
    public func create(name: String, isSmartCollection: Bool = false, predicate: String? = nil) async -> CDCollection {
        Logger.persistence.info("Creating collection: \(name) (smart: \(isSmartCollection))")
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

    /// Update a collection
    public func update(_ collection: CDCollection, name: String? = nil, predicate: String? = nil) async {
        Logger.persistence.info("Updating collection: \(collection.name)")
        let context = persistenceController.viewContext

        await context.perform {
            if let name = name {
                collection.name = name
            }
            if collection.isSmartCollection {
                collection.predicate = predicate
            }
            self.persistenceController.save()
        }
    }

    /// Delete a collection
    public func delete(_ collection: CDCollection) async {
        Logger.persistence.info("Deleting collection: \(collection.name)")
        let context = persistenceController.viewContext

        await context.perform {
            context.delete(collection)
            self.persistenceController.save()
        }
    }

    /// Execute a smart collection query
    public func executeSmartCollection(_ collection: CDCollection) async -> [CDPublication] {
        guard collection.isSmartCollection, let predicateString = collection.predicate else {
            // For static collections, return the assigned publications
            return Array(collection.publications ?? [])
        }

        Logger.persistence.debug("Executing smart collection: \(collection.name)")
        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDPublication>(entityName: "Publication")

            // Parse and apply the predicate
            do {
                request.predicate = NSPredicate(format: predicateString)
            } catch {
                Logger.persistence.error("Invalid predicate: \(predicateString)")
                return []
            }

            request.sortDescriptors = [NSSortDescriptor(key: "dateModified", ascending: false)]

            do {
                return try context.fetch(request)
            } catch {
                Logger.persistence.error("Smart collection query failed: \(error.localizedDescription)")
                return []
            }
        }
    }

    /// Add publications to a static collection
    public func addPublications(_ publications: [CDPublication], to collection: CDCollection) async {
        guard !collection.isSmartCollection else { return }
        let context = persistenceController.viewContext

        await context.perform {
            var current = collection.publications ?? []
            for pub in publications {
                current.insert(pub)
            }
            collection.publications = current
            self.persistenceController.save()
        }
    }

    /// Remove publications from a static collection
    public func removePublications(_ publications: [CDPublication], from collection: CDCollection) async {
        guard !collection.isSmartCollection else { return }
        let context = persistenceController.viewContext

        await context.perform {
            var current = collection.publications ?? []
            for pub in publications {
                current.remove(pub)
            }
            collection.publications = current
            self.persistenceController.save()
        }
    }
}
