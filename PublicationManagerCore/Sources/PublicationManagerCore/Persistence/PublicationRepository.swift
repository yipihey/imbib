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

    // MARK: - Read Status (Apple Mail Styling)

    /// Mark a publication as read
    public func markAsRead(_ publication: CDPublication) async {
        guard !publication.isRead else { return }
        let context = persistenceController.viewContext

        await context.perform {
            publication.isRead = true
            publication.dateRead = Date()
            self.persistenceController.save()
        }
    }

    /// Mark a publication as unread
    public func markAsUnread(_ publication: CDPublication) async {
        guard publication.isRead else { return }
        let context = persistenceController.viewContext

        await context.perform {
            publication.isRead = false
            publication.dateRead = nil
            self.persistenceController.save()
        }
    }

    /// Toggle read/unread status
    public func toggleReadStatus(_ publication: CDPublication) async {
        if publication.isRead {
            await markAsUnread(publication)
        } else {
            await markAsRead(publication)
        }
    }

    /// Mark multiple publications as read
    public func markAllAsRead(_ publications: [CDPublication]) async {
        let unread = publications.filter { !$0.isRead }
        guard !unread.isEmpty else { return }

        let context = persistenceController.viewContext
        let now = Date()

        await context.perform {
            for publication in unread {
                publication.isRead = true
                publication.dateRead = now
            }
            self.persistenceController.save()
        }
    }

    /// Fetch count of unread publications
    public func unreadCount() async -> Int {
        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDPublication>(entityName: "Publication")
            request.predicate = NSPredicate(format: "isRead == NO")

            return (try? context.count(for: request)) ?? 0
        }
    }

    /// Fetch all unread publications
    public func fetchUnread(sortedBy sortKey: String = "dateAdded", ascending: Bool = false) async -> [CDPublication] {
        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDPublication>(entityName: "Publication")
            request.predicate = NSPredicate(format: "isRead == NO")
            request.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: ascending)]

            return (try? context.fetch(request)) ?? []
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

    // MARK: - Deduplication (ADR-016)

    /// Find publication by DOI (normalized to lowercase)
    public func findByDOI(_ doi: String) async -> CDPublication? {
        let normalized = doi.lowercased().trimmingCharacters(in: .whitespaces)
        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDPublication>(entityName: "Publication")
            request.predicate = NSPredicate(format: "doi ==[c] %@", normalized)
            request.fetchLimit = 1

            return try? context.fetch(request).first
        }
    }

    /// Find publication by arXiv ID (strips version suffix like "v1", "v2")
    public func findByArXiv(_ arxivID: String) async -> CDPublication? {
        // Strip version suffix (e.g., "2301.12345v2" -> "2301.12345")
        let baseID = arxivID.replacingOccurrences(
            of: #"v\d+$"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)

        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDPublication>(entityName: "Publication")
            // Check fields.eprint or fields.arxiv (both are used)
            request.predicate = NSPredicate(
                format: "rawFields CONTAINS[c] %@",
                baseID
            )

            do {
                let results = try context.fetch(request)
                // Verify the match in the fields
                return results.first { pub in
                    let fields = pub.fields
                    let eprint = fields["eprint"]?.replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
                    let arxiv = fields["arxiv"]?.replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
                    return eprint?.lowercased() == baseID.lowercased() ||
                           arxiv?.lowercased() == baseID.lowercased()
                }
            } catch {
                return nil
            }
        }
    }

    /// Find publication by ADS bibcode
    public func findByBibcode(_ bibcode: String) async -> CDPublication? {
        let normalized = bibcode.trimmingCharacters(in: .whitespaces)
        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDPublication>(entityName: "Publication")
            // Bibcode is typically stored in fields.bibcode or fields.adsurl
            request.predicate = NSPredicate(
                format: "rawFields CONTAINS[c] %@",
                normalized
            )

            do {
                let results = try context.fetch(request)
                return results.first { pub in
                    let fields = pub.fields
                    return fields["bibcode"]?.lowercased() == normalized.lowercased()
                }
            } catch {
                return nil
            }
        }
    }

    /// Find publication by Semantic Scholar ID
    public func findBySemanticScholarID(_ id: String) async -> CDPublication? {
        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDPublication>(entityName: "Publication")
            request.predicate = NSPredicate(format: "semanticScholarID == %@", id)
            request.fetchLimit = 1

            return try? context.fetch(request).first
        }
    }

    /// Find publication by OpenAlex ID
    public func findByOpenAlexID(_ id: String) async -> CDPublication? {
        let context = persistenceController.viewContext

        return await context.perform {
            let request = NSFetchRequest<CDPublication>(entityName: "Publication")
            request.predicate = NSPredicate(format: "openAlexID == %@", id)
            request.fetchLimit = 1

            return try? context.fetch(request).first
        }
    }

    /// Find publication by any identifier from a SearchResult
    /// Checks DOI, arXiv ID, and bibcode in priority order
    public func findByIdentifiers(_ result: SearchResult) async -> CDPublication? {
        // Check DOI first (most reliable)
        if let doi = result.doi {
            if let pub = await findByDOI(doi) {
                return pub
            }
        }

        // Check arXiv ID
        if let arxivID = result.arxivID {
            if let pub = await findByArXiv(arxivID) {
                return pub
            }
        }

        // Check bibcode
        if let bibcode = result.bibcode {
            if let pub = await findByBibcode(bibcode) {
                return pub
            }
        }

        // Check Semantic Scholar ID
        if let ssID = result.semanticScholarID {
            if let pub = await findBySemanticScholarID(ssID) {
                return pub
            }
        }

        // Check OpenAlex ID
        if let oaID = result.openAlexID {
            if let pub = await findByOpenAlexID(oaID) {
                return pub
            }
        }

        return nil
    }

    // MARK: - Create from Search Result (ADR-016)

    /// Create a new publication from a SearchResult with online source metadata
    ///
    /// This method creates a CDPublication directly from search result metadata,
    /// without requiring a network fetch for BibTeX. The BibTeX is generated locally.
    ///
    /// - Parameters:
    ///   - result: The search result to create from
    ///   - library: Optional library for file paths
    ///   - abstractOverride: Optional abstract to use instead of result.abstract (for merging from alternates)
    /// - Returns: The created CDPublication
    @discardableResult
    public func createFromSearchResult(_ result: SearchResult, in library: CDLibrary? = nil, abstractOverride: String? = nil) async -> CDPublication {
        Logger.persistence.info("Creating publication from search result: \(result.title)")
        let context = persistenceController.viewContext

        return await context.perform {
            let publication = CDPublication(context: context)
            publication.id = UUID()
            publication.dateAdded = Date()
            publication.dateModified = Date()

            // Generate cite key
            let existingKeys = self.fetchCiteKeysSync(context: context)
            publication.citeKey = self.generateCiteKey(for: result, existingKeys: existingKeys)

            // Set entry type (default to article)
            publication.entryType = "article"

            // Core fields
            publication.title = result.title
            if let year = result.year {
                publication.year = Int16(year)
            }
            // Use abstract override if provided (for merged abstracts from deduplication)
            publication.abstract = abstractOverride ?? result.abstract
            publication.doi = result.doi

            // Build fields dictionary
            var fields: [String: String] = [:]
            if !result.authors.isEmpty {
                fields["author"] = result.authors.joined(separator: " and ")
            }
            if let venue = result.venue {
                fields["journal"] = venue
            }
            if let doi = result.doi {
                fields["doi"] = doi
            }
            if let arxivID = result.arxivID {
                fields["eprint"] = arxivID
                fields["archiveprefix"] = "arXiv"
            }
            if let bibcode = result.bibcode {
                fields["bibcode"] = bibcode
            }
            if let pmid = result.pmid {
                fields["pmid"] = pmid
            }
            publication.fields = fields

            // ADR-016: Online source metadata
            publication.originalSourceID = result.sourceID
            publication.webURL = result.webURL?.absoluteString
            publication.semanticScholarID = result.semanticScholarID
            publication.openAlexID = result.openAlexID

            // Store PDF links as JSON
            if !result.pdfLinks.isEmpty {
                publication.pdfLinks = result.pdfLinks
            }

            // Generate and store BibTeX
            let entry = publication.toBibTeXEntry()
            publication.rawBibTeX = BibTeXExporter().export([entry])

            self.persistenceController.save()
            return publication
        }
    }

    /// Synchronous helper to fetch existing cite keys (must be called from context.perform)
    private func fetchCiteKeysSync(context: NSManagedObjectContext) -> Set<String> {
        let request = NSFetchRequest<CDPublication>(entityName: "Publication")
        request.propertiesToFetch = ["citeKey"]

        do {
            let pubs = try context.fetch(request)
            return Set(pubs.map { $0.citeKey })
        } catch {
            return []
        }
    }

    /// Generate a unique cite key for a search result
    private func generateCiteKey(for result: SearchResult, existingKeys: Set<String>) -> String {
        let lastName = result.firstAuthorLastName ?? "Unknown"
        let yearStr = result.year.map { String($0) } ?? ""

        // Get first significant word from title (>3 chars)
        let titleWord = result.title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .first { $0.count > 3 } ?? "Paper"

        var candidate = "\(lastName)\(yearStr)\(titleWord)"
        var counter = 0

        while existingKeys.contains(candidate) {
            counter += 1
            candidate = "\(lastName)\(yearStr)\(titleWord)\(counter)"
        }

        return candidate
    }

    /// Add a publication to a collection
    public func addToCollection(_ publication: CDPublication, collection: CDCollection) async {
        let context = persistenceController.viewContext

        await context.perform {
            var pubs = collection.publications ?? []
            pubs.insert(publication)
            collection.publications = pubs
            self.persistenceController.save()
        }
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

    // MARK: - Move and Collection Operations

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

    /// Move publications to a different library
    public func moveToLibrary(_ publications: [CDPublication], library: CDLibrary) async {
        let context = persistenceController.viewContext

        await context.perform {
            for publication in publications {
                publication.owningLibrary = library
            }
            self.persistenceController.save()
        }
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
