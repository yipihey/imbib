//
//  ManagedObjects.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import CoreData

// MARK: - Publication

@objc(CDPublication)
public class CDPublication: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var citeKey: String
    @NSManaged public var entryType: String
    @NSManaged public var title: String?
    @NSManaged public var year: Int16
    @NSManaged public var abstract: String?
    @NSManaged public var doi: String?
    @NSManaged public var url: String?
    @NSManaged public var rawBibTeX: String?
    @NSManaged public var rawFields: String?
    @NSManaged public var fieldTimestamps: String?
    @NSManaged public var dateAdded: Date
    @NSManaged public var dateModified: Date

    // Relationships
    @NSManaged public var publicationAuthors: Set<CDPublicationAuthor>?
    @NSManaged public var linkedFiles: Set<CDLinkedFile>?
    @NSManaged public var tags: Set<CDTag>?
    @NSManaged public var collections: Set<CDCollection>?
}

// MARK: - Publication Helpers

public extension CDPublication {

    /// Get all fields as dictionary (decoded from rawFields JSON)
    var fields: [String: String] {
        get {
            guard let json = rawFields,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return dict
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                rawFields = json
            }
        }
    }

    /// Get authors sorted by order
    var sortedAuthors: [CDAuthor] {
        (publicationAuthors ?? [])
            .sorted { $0.order < $1.order }
            .compactMap { $0.author }
    }

    /// Author string for display
    var authorString: String {
        // Prefer CDAuthor entities if they exist
        let fromEntities = sortedAuthors.map { $0.displayName }.joined(separator: ", ")
        if !fromEntities.isEmpty {
            return fromEntities
        }

        // Fall back to parsed author field with braces stripped
        guard let rawAuthor = fields["author"] else { return "" }

        // Parse and clean author names (same logic as BibTeXEntry.authorList)
        return rawAuthor
            .components(separatedBy: " and ")
            .map { BibTeXFieldCleaner.cleanAuthorName($0) }
            .joined(separator: ", ")
    }

    /// Convert to BibTeXEntry
    func toBibTeXEntry() -> BibTeXEntry {
        var entryFields = fields

        // Add core fields
        if let title = title { entryFields["title"] = title }
        if year > 0 { entryFields["year"] = String(year) }
        if let abstract = abstract { entryFields["abstract"] = abstract }
        if let doi = doi { entryFields["doi"] = doi }
        if let url = url { entryFields["url"] = url }

        // Add author field
        if !sortedAuthors.isEmpty {
            entryFields["author"] = sortedAuthors.map { $0.bibtexName }.joined(separator: " and ")
        }

        // Add file references
        let files = (linkedFiles ?? []).map { $0.relativePath }
        if !files.isEmpty {
            BdskFileCodec.addFiles(Array(files), to: &entryFields)
        }

        return BibTeXEntry(
            citeKey: citeKey,
            entryType: entryType,
            fields: entryFields,
            rawBibTeX: rawBibTeX
        )
    }

    /// Update from BibTeXEntry
    func update(from entry: BibTeXEntry, context: NSManagedObjectContext) {
        citeKey = entry.citeKey
        entryType = entry.entryType
        rawBibTeX = entry.rawBibTeX

        // Extract and set core fields (use cleaned properties, not raw fields)
        title = entry.title
        if let yearStr = entry.fields["year"], let yearInt = Int16(yearStr) {
            year = yearInt
        }
        abstract = entry.fields["abstract"]
        doi = entry.fields["doi"]
        url = entry.fields["url"]

        // Store all fields
        fields = entry.fields

        dateModified = Date()
    }
}

// MARK: - Author

@objc(CDAuthor)
public class CDAuthor: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var familyName: String
    @NSManaged public var givenName: String?
    @NSManaged public var nameSuffix: String?

    // Relationships
    @NSManaged public var publicationAuthors: Set<CDPublicationAuthor>?
}

// MARK: - Author Helpers

public extension CDAuthor {

    /// Display name (e.g., "Albert Einstein")
    var displayName: String {
        if let given = givenName {
            var name = "\(given) \(familyName)"
            if let suffix = nameSuffix {
                name += ", \(suffix)"
            }
            return name
        }
        return familyName
    }

    /// BibTeX format (e.g., "Einstein, Albert")
    var bibtexName: String {
        if let given = givenName {
            var name = "\(familyName), \(given)"
            if let suffix = nameSuffix {
                name += ", \(suffix)"
            }
            return name
        }
        return familyName
    }

    /// Parse author string from BibTeX format
    static func parse(_ string: String) -> (familyName: String, givenName: String?, suffix: String?) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)

        if trimmed.contains(",") {
            // "Last, First" or "Last, First, Jr."
            let parts = trimmed.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }

            let familyName = parts[0]
            let givenName = parts.count > 1 ? parts[1] : nil
            let suffix = parts.count > 2 ? parts[2] : nil

            return (familyName, givenName, suffix)
        } else {
            // "First Last"
            let parts = trimmed.components(separatedBy: " ")
            if parts.count > 1 {
                let familyName = parts.last ?? trimmed
                let givenName = parts.dropLast().joined(separator: " ")
                return (familyName, givenName, nil)
            }
            return (trimmed, nil, nil)
        }
    }
}

// MARK: - Publication Author (Join Table)

@objc(CDPublicationAuthor)
public class CDPublicationAuthor: NSManagedObject {
    @NSManaged public var order: Int16

    // Relationships
    @NSManaged public var publication: CDPublication?
    @NSManaged public var author: CDAuthor?
}

// MARK: - Linked File

@objc(CDLinkedFile)
public class CDLinkedFile: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var relativePath: String
    @NSManaged public var filename: String
    @NSManaged public var fileType: String?
    @NSManaged public var sha256: String?
    @NSManaged public var dateAdded: Date

    // Relationships
    @NSManaged public var publication: CDPublication?
}

// MARK: - Linked File Helpers

public extension CDLinkedFile {

    /// File extension
    var fileExtension: String {
        URL(fileURLWithPath: filename).pathExtension.lowercased()
    }

    /// Whether this is a PDF
    var isPDF: Bool {
        fileExtension == "pdf" || fileType == "pdf"
    }
}

// MARK: - Tag

@objc(CDTag)
public class CDTag: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var color: String?

    // Relationships
    @NSManaged public var publications: Set<CDPublication>?
}

// MARK: - Collection

@objc(CDCollection)
public class CDCollection: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var isSmartCollection: Bool
    @NSManaged public var predicate: String?

    // Relationships
    @NSManaged public var publications: Set<CDPublication>?
}

// MARK: - Collection Helpers

public extension CDCollection {

    /// Parse predicate string to NSPredicate
    var nsPredicate: NSPredicate? {
        guard isSmartCollection, let predicateString = predicate else {
            return nil
        }
        return NSPredicate(format: predicateString)
    }
}

// MARK: - Library

@objc(CDLibrary)
public class CDLibrary: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var bibFilePath: String?         // Path to .bib file (may be nil for new libraries)
    @NSManaged public var papersDirectoryPath: String? // Path to Papers folder
    @NSManaged public var bookmarkData: Data?          // Security-scoped bookmark for file access
    @NSManaged public var dateCreated: Date
    @NSManaged public var dateLastOpened: Date?
    @NSManaged public var isDefault: Bool              // Is this the default library?

    // Relationships
    @NSManaged public var smartSearches: Set<CDSmartSearch>?
}

// MARK: - Library Helpers

public extension CDLibrary {

    /// Display name (uses .bib filename if name is empty)
    var displayName: String {
        if !name.isEmpty {
            return name
        }
        if let path = bibFilePath {
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
        return "Untitled Library"
    }

    /// Resolve the .bib file URL using the security-scoped bookmark
    func resolveURL() -> URL? {
        guard let bookmarkData else {
            // Fall back to path if no bookmark
            if let path = bibFilePath {
                return URL(fileURLWithPath: path)
            }
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        // If bookmark is stale, we should refresh it (handled elsewhere)
        return url
    }
}

// MARK: - Smart Search

@objc(CDSmartSearch)
public class CDSmartSearch: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var query: String
    @NSManaged public var sourceIDs: String?           // JSON array of source IDs
    @NSManaged public var dateCreated: Date
    @NSManaged public var dateLastExecuted: Date?
    @NSManaged public var order: Int16                  // For sidebar ordering

    // Relationships
    @NSManaged public var library: CDLibrary?
}

// MARK: - Smart Search Helpers

public extension CDSmartSearch {

    /// Get source IDs as array
    var sources: [String] {
        get {
            guard let json = sourceIDs,
                  let data = json.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return array
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                sourceIDs = json
            }
        }
    }

    /// Whether this search uses all available sources
    var usesAllSources: Bool {
        sources.isEmpty
    }
}
