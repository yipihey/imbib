//
//  PersistenceController.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import CoreData
import OSLog

// MARK: - Persistence Controller

/// Manages the Core Data stack for the publication database.
public final class PersistenceController: @unchecked Sendable {

    // MARK: - Shared Instance

    public static let shared = PersistenceController()

    // MARK: - Preview Instance

    public static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        // Add sample data for previews
        controller.addSampleData()
        return controller
    }()

    // MARK: - Properties

    public let container: NSPersistentContainer

    public var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    // MARK: - Initialization

    public init(inMemory: Bool = false) {
        Logger.persistence.entering()

        // Create the managed object model programmatically
        let model = Self.createManagedObjectModel()

        container = NSPersistentContainer(name: "PublicationManager", managedObjectModel: model)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                Logger.persistence.error("Failed to load persistent stores: \(error), \(error.userInfo)")
                fatalError("Failed to load persistent stores: \(error)")
            }
            Logger.persistence.info("Loaded persistent store: \(description.url?.absoluteString ?? "unknown")")
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        Logger.persistence.exiting()
    }

    // MARK: - Core Data Model Creation

    private static func createManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // Create entities
        let publicationEntity = createPublicationEntity()
        let authorEntity = createAuthorEntity()
        let publicationAuthorEntity = createPublicationAuthorEntity()
        let linkedFileEntity = createLinkedFileEntity()
        let tagEntity = createTagEntity()
        let collectionEntity = createCollectionEntity()
        let libraryEntity = createLibraryEntity()
        let smartSearchEntity = createSmartSearchEntity()

        // Set up relationships
        setupRelationships(
            publication: publicationEntity,
            author: authorEntity,
            publicationAuthor: publicationAuthorEntity,
            linkedFile: linkedFileEntity,
            tag: tagEntity,
            collection: collectionEntity
        )

        // Set up library-smart search relationship
        setupLibrarySmartSearchRelationship(
            library: libraryEntity,
            smartSearch: smartSearchEntity
        )

        model.entities = [
            publicationEntity,
            authorEntity,
            publicationAuthorEntity,
            linkedFileEntity,
            tagEntity,
            collectionEntity,
            libraryEntity,
            smartSearchEntity,
        ]

        return model
    }

    // MARK: - Entity Creation

    private static func createPublicationEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "Publication"
        entity.managedObjectClassName = "PublicationManagerCore.CDPublication"

        var properties: [NSPropertyDescription] = []

        // Primary key
        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType
        id.isOptional = false
        properties.append(id)

        // Core fields
        let citeKey = NSAttributeDescription()
        citeKey.name = "citeKey"
        citeKey.attributeType = .stringAttributeType
        citeKey.isOptional = false
        properties.append(citeKey)

        let entryType = NSAttributeDescription()
        entryType.name = "entryType"
        entryType.attributeType = .stringAttributeType
        entryType.isOptional = false
        entryType.defaultValue = "article"
        properties.append(entryType)

        let title = NSAttributeDescription()
        title.name = "title"
        title.attributeType = .stringAttributeType
        title.isOptional = true
        properties.append(title)

        let year = NSAttributeDescription()
        year.name = "year"
        year.attributeType = .integer16AttributeType
        year.isOptional = true
        properties.append(year)

        let abstract = NSAttributeDescription()
        abstract.name = "abstract"
        abstract.attributeType = .stringAttributeType
        abstract.isOptional = true
        properties.append(abstract)

        let doi = NSAttributeDescription()
        doi.name = "doi"
        doi.attributeType = .stringAttributeType
        doi.isOptional = true
        properties.append(doi)

        let url = NSAttributeDescription()
        url.name = "url"
        url.attributeType = .stringAttributeType
        url.isOptional = true
        properties.append(url)

        // Raw BibTeX for round-trip
        let rawBibTeX = NSAttributeDescription()
        rawBibTeX.name = "rawBibTeX"
        rawBibTeX.attributeType = .stringAttributeType
        rawBibTeX.isOptional = true
        properties.append(rawBibTeX)

        // JSON storage for all fields
        let rawFields = NSAttributeDescription()
        rawFields.name = "rawFields"
        rawFields.attributeType = .stringAttributeType
        rawFields.isOptional = true
        properties.append(rawFields)

        // Field timestamps for conflict resolution
        let fieldTimestamps = NSAttributeDescription()
        fieldTimestamps.name = "fieldTimestamps"
        fieldTimestamps.attributeType = .stringAttributeType
        fieldTimestamps.isOptional = true
        properties.append(fieldTimestamps)

        // Metadata
        let dateAdded = NSAttributeDescription()
        dateAdded.name = "dateAdded"
        dateAdded.attributeType = .dateAttributeType
        dateAdded.isOptional = false
        dateAdded.defaultValue = Date()
        properties.append(dateAdded)

        let dateModified = NSAttributeDescription()
        dateModified.name = "dateModified"
        dateModified.attributeType = .dateAttributeType
        dateModified.isOptional = false
        dateModified.defaultValue = Date()
        properties.append(dateModified)

        entity.properties = properties
        return entity
    }

    private static func createAuthorEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "Author"
        entity.managedObjectClassName = "PublicationManagerCore.CDAuthor"

        var properties: [NSPropertyDescription] = []

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType
        id.isOptional = false
        properties.append(id)

        let familyName = NSAttributeDescription()
        familyName.name = "familyName"
        familyName.attributeType = .stringAttributeType
        familyName.isOptional = false
        properties.append(familyName)

        let givenName = NSAttributeDescription()
        givenName.name = "givenName"
        givenName.attributeType = .stringAttributeType
        givenName.isOptional = true
        properties.append(givenName)

        let nameSuffix = NSAttributeDescription()
        nameSuffix.name = "nameSuffix"
        nameSuffix.attributeType = .stringAttributeType
        nameSuffix.isOptional = true
        properties.append(nameSuffix)

        entity.properties = properties
        return entity
    }

    private static func createPublicationAuthorEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "PublicationAuthor"
        entity.managedObjectClassName = "PublicationManagerCore.CDPublicationAuthor"

        var properties: [NSPropertyDescription] = []

        let order = NSAttributeDescription()
        order.name = "order"
        order.attributeType = .integer16AttributeType
        order.isOptional = false
        order.defaultValue = 0
        properties.append(order)

        entity.properties = properties
        return entity
    }

    private static func createLinkedFileEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "LinkedFile"
        entity.managedObjectClassName = "PublicationManagerCore.CDLinkedFile"

        var properties: [NSPropertyDescription] = []

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType
        id.isOptional = false
        properties.append(id)

        let relativePath = NSAttributeDescription()
        relativePath.name = "relativePath"
        relativePath.attributeType = .stringAttributeType
        relativePath.isOptional = false
        properties.append(relativePath)

        let filename = NSAttributeDescription()
        filename.name = "filename"
        filename.attributeType = .stringAttributeType
        filename.isOptional = false
        properties.append(filename)

        let fileType = NSAttributeDescription()
        fileType.name = "fileType"
        fileType.attributeType = .stringAttributeType
        fileType.isOptional = true
        fileType.defaultValue = "pdf"
        properties.append(fileType)

        let sha256 = NSAttributeDescription()
        sha256.name = "sha256"
        sha256.attributeType = .stringAttributeType
        sha256.isOptional = true
        properties.append(sha256)

        let dateAdded = NSAttributeDescription()
        dateAdded.name = "dateAdded"
        dateAdded.attributeType = .dateAttributeType
        dateAdded.isOptional = false
        dateAdded.defaultValue = Date()
        properties.append(dateAdded)

        entity.properties = properties
        return entity
    }

    private static func createTagEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "Tag"
        entity.managedObjectClassName = "PublicationManagerCore.CDTag"

        var properties: [NSPropertyDescription] = []

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType
        id.isOptional = false
        properties.append(id)

        let name = NSAttributeDescription()
        name.name = "name"
        name.attributeType = .stringAttributeType
        name.isOptional = false
        properties.append(name)

        let color = NSAttributeDescription()
        color.name = "color"
        color.attributeType = .stringAttributeType
        color.isOptional = true
        properties.append(color)

        entity.properties = properties
        return entity
    }

    private static func createCollectionEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "Collection"
        entity.managedObjectClassName = "PublicationManagerCore.CDCollection"

        var properties: [NSPropertyDescription] = []

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType
        id.isOptional = false
        properties.append(id)

        let name = NSAttributeDescription()
        name.name = "name"
        name.attributeType = .stringAttributeType
        name.isOptional = false
        properties.append(name)

        let isSmartCollection = NSAttributeDescription()
        isSmartCollection.name = "isSmartCollection"
        isSmartCollection.attributeType = .booleanAttributeType
        isSmartCollection.isOptional = false
        isSmartCollection.defaultValue = false
        properties.append(isSmartCollection)

        let predicate = NSAttributeDescription()
        predicate.name = "predicate"
        predicate.attributeType = .stringAttributeType
        predicate.isOptional = true
        properties.append(predicate)

        entity.properties = properties
        return entity
    }

    private static func createLibraryEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "Library"
        entity.managedObjectClassName = "PublicationManagerCore.CDLibrary"

        var properties: [NSPropertyDescription] = []

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType
        id.isOptional = false
        properties.append(id)

        let name = NSAttributeDescription()
        name.name = "name"
        name.attributeType = .stringAttributeType
        name.isOptional = false
        name.defaultValue = ""
        properties.append(name)

        let bibFilePath = NSAttributeDescription()
        bibFilePath.name = "bibFilePath"
        bibFilePath.attributeType = .stringAttributeType
        bibFilePath.isOptional = true
        properties.append(bibFilePath)

        let papersDirectoryPath = NSAttributeDescription()
        papersDirectoryPath.name = "papersDirectoryPath"
        papersDirectoryPath.attributeType = .stringAttributeType
        papersDirectoryPath.isOptional = true
        properties.append(papersDirectoryPath)

        let bookmarkData = NSAttributeDescription()
        bookmarkData.name = "bookmarkData"
        bookmarkData.attributeType = .binaryDataAttributeType
        bookmarkData.isOptional = true
        properties.append(bookmarkData)

        let dateCreated = NSAttributeDescription()
        dateCreated.name = "dateCreated"
        dateCreated.attributeType = .dateAttributeType
        dateCreated.isOptional = false
        dateCreated.defaultValue = Date()
        properties.append(dateCreated)

        let dateLastOpened = NSAttributeDescription()
        dateLastOpened.name = "dateLastOpened"
        dateLastOpened.attributeType = .dateAttributeType
        dateLastOpened.isOptional = true
        properties.append(dateLastOpened)

        let isDefault = NSAttributeDescription()
        isDefault.name = "isDefault"
        isDefault.attributeType = .booleanAttributeType
        isDefault.isOptional = false
        isDefault.defaultValue = false
        properties.append(isDefault)

        entity.properties = properties
        return entity
    }

    private static func createSmartSearchEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "SmartSearch"
        entity.managedObjectClassName = "PublicationManagerCore.CDSmartSearch"

        var properties: [NSPropertyDescription] = []

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType
        id.isOptional = false
        properties.append(id)

        let name = NSAttributeDescription()
        name.name = "name"
        name.attributeType = .stringAttributeType
        name.isOptional = false
        properties.append(name)

        let query = NSAttributeDescription()
        query.name = "query"
        query.attributeType = .stringAttributeType
        query.isOptional = false
        properties.append(query)

        let sourceIDs = NSAttributeDescription()
        sourceIDs.name = "sourceIDs"
        sourceIDs.attributeType = .stringAttributeType
        sourceIDs.isOptional = true
        properties.append(sourceIDs)

        let dateCreated = NSAttributeDescription()
        dateCreated.name = "dateCreated"
        dateCreated.attributeType = .dateAttributeType
        dateCreated.isOptional = false
        dateCreated.defaultValue = Date()
        properties.append(dateCreated)

        let dateLastExecuted = NSAttributeDescription()
        dateLastExecuted.name = "dateLastExecuted"
        dateLastExecuted.attributeType = .dateAttributeType
        dateLastExecuted.isOptional = true
        properties.append(dateLastExecuted)

        let order = NSAttributeDescription()
        order.name = "order"
        order.attributeType = .integer16AttributeType
        order.isOptional = false
        order.defaultValue = 0
        properties.append(order)

        entity.properties = properties
        return entity
    }

    // MARK: - Relationship Setup

    private static func setupLibrarySmartSearchRelationship(
        library: NSEntityDescription,
        smartSearch: NSEntityDescription
    ) {
        // Library -> SmartSearches (one-to-many)
        let libraryToSmartSearches = NSRelationshipDescription()
        libraryToSmartSearches.name = "smartSearches"
        libraryToSmartSearches.destinationEntity = smartSearch
        libraryToSmartSearches.isOptional = true
        libraryToSmartSearches.deleteRule = .cascadeDeleteRule

        // SmartSearch -> Library (many-to-one)
        let smartSearchToLibrary = NSRelationshipDescription()
        smartSearchToLibrary.name = "library"
        smartSearchToLibrary.destinationEntity = library
        smartSearchToLibrary.maxCount = 1
        smartSearchToLibrary.isOptional = true
        smartSearchToLibrary.deleteRule = .nullifyDeleteRule

        // Set inverse relationships
        libraryToSmartSearches.inverseRelationship = smartSearchToLibrary
        smartSearchToLibrary.inverseRelationship = libraryToSmartSearches

        // Add to entities
        library.properties.append(libraryToSmartSearches)
        smartSearch.properties.append(smartSearchToLibrary)
    }

    private static func setupRelationships(
        publication: NSEntityDescription,
        author: NSEntityDescription,
        publicationAuthor: NSEntityDescription,
        linkedFile: NSEntityDescription,
        tag: NSEntityDescription,
        collection: NSEntityDescription
    ) {
        // Publication <-> PublicationAuthor
        let pubToAuthors = NSRelationshipDescription()
        pubToAuthors.name = "publicationAuthors"
        pubToAuthors.destinationEntity = publicationAuthor
        pubToAuthors.isOptional = true
        pubToAuthors.deleteRule = .cascadeDeleteRule

        let authorToPub = NSRelationshipDescription()
        authorToPub.name = "publication"
        authorToPub.destinationEntity = publication
        authorToPub.maxCount = 1
        authorToPub.isOptional = false
        authorToPub.deleteRule = .nullifyDeleteRule

        pubToAuthors.inverseRelationship = authorToPub
        authorToPub.inverseRelationship = pubToAuthors

        // PublicationAuthor <-> Author
        let paToAuthor = NSRelationshipDescription()
        paToAuthor.name = "author"
        paToAuthor.destinationEntity = author
        paToAuthor.maxCount = 1
        paToAuthor.isOptional = false
        paToAuthor.deleteRule = .nullifyDeleteRule

        let authorToPAs = NSRelationshipDescription()
        authorToPAs.name = "publicationAuthors"
        authorToPAs.destinationEntity = publicationAuthor
        authorToPAs.isOptional = true
        authorToPAs.deleteRule = .cascadeDeleteRule

        paToAuthor.inverseRelationship = authorToPAs
        authorToPAs.inverseRelationship = paToAuthor

        // Publication <-> LinkedFile
        let pubToFiles = NSRelationshipDescription()
        pubToFiles.name = "linkedFiles"
        pubToFiles.destinationEntity = linkedFile
        pubToFiles.isOptional = true
        pubToFiles.deleteRule = .cascadeDeleteRule

        let fileToPub = NSRelationshipDescription()
        fileToPub.name = "publication"
        fileToPub.destinationEntity = publication
        fileToPub.maxCount = 1
        fileToPub.isOptional = false
        fileToPub.deleteRule = .nullifyDeleteRule

        pubToFiles.inverseRelationship = fileToPub
        fileToPub.inverseRelationship = pubToFiles

        // Publication <-> Tag (many-to-many)
        let pubToTags = NSRelationshipDescription()
        pubToTags.name = "tags"
        pubToTags.destinationEntity = tag
        pubToTags.isOptional = true
        pubToTags.deleteRule = .nullifyDeleteRule

        let tagToPubs = NSRelationshipDescription()
        tagToPubs.name = "publications"
        tagToPubs.destinationEntity = publication
        tagToPubs.isOptional = true
        tagToPubs.deleteRule = .nullifyDeleteRule

        pubToTags.inverseRelationship = tagToPubs
        tagToPubs.inverseRelationship = pubToTags

        // Publication <-> Collection (many-to-many)
        let pubToCollections = NSRelationshipDescription()
        pubToCollections.name = "collections"
        pubToCollections.destinationEntity = collection
        pubToCollections.isOptional = true
        pubToCollections.deleteRule = .nullifyDeleteRule

        let collectionToPubs = NSRelationshipDescription()
        collectionToPubs.name = "publications"
        collectionToPubs.destinationEntity = publication
        collectionToPubs.isOptional = true
        collectionToPubs.deleteRule = .nullifyDeleteRule

        pubToCollections.inverseRelationship = collectionToPubs
        collectionToPubs.inverseRelationship = pubToCollections

        // Add relationships to entities
        publication.properties.append(contentsOf: [pubToAuthors, pubToFiles, pubToTags, pubToCollections])
        author.properties.append(authorToPAs)
        publicationAuthor.properties.append(contentsOf: [authorToPub, paToAuthor])
        linkedFile.properties.append(fileToPub)
        tag.properties.append(tagToPubs)
        collection.properties.append(collectionToPubs)
    }

    // MARK: - Save

    public func save() {
        guard viewContext.hasChanges else { return }

        do {
            try viewContext.save()
            Logger.persistence.debug("Context saved")
        } catch {
            Logger.persistence.error("Failed to save context: \(error.localizedDescription)")
        }
    }

    // MARK: - Background Context

    public func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }

    public func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask(block)
    }

    // MARK: - Sample Data

    private func addSampleData() {
        let context = viewContext

        // Create sample publications
        let pub1 = CDPublication(context: context)
        pub1.id = UUID()
        pub1.citeKey = "Einstein1905"
        pub1.entryType = "article"
        pub1.title = "On the Electrodynamics of Moving Bodies"
        pub1.year = 1905
        pub1.dateAdded = Date()
        pub1.dateModified = Date()

        let pub2 = CDPublication(context: context)
        pub2.id = UUID()
        pub2.citeKey = "Hawking1974"
        pub2.entryType = "article"
        pub2.title = "Black hole explosions?"
        pub2.year = 1974
        pub2.dateAdded = Date()
        pub2.dateModified = Date()

        try? context.save()
    }
}
