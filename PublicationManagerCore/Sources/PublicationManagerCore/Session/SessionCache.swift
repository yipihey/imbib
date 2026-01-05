//
//  SessionCache.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog

// MARK: - Session Cache

/// Session-scoped cache for online search results, PDFs, and temporary metadata.
///
/// This actor manages ephemeral data that should persist during a session
/// but be cleaned up when the app terminates.
public actor SessionCache {

    // MARK: - Singleton

    public static let shared = SessionCache()

    // MARK: - Configuration

    /// Maximum number of cached search results
    public static let maxSearchResults = 50

    /// Maximum total size of cached PDFs (100 MB)
    public static let maxPDFCacheSize: Int64 = 100 * 1024 * 1024

    /// Maximum age for cached results (1 hour)
    public static let maxResultAge: TimeInterval = 3600

    // MARK: - Properties

    private var searchResults: [String: CachedSearchResults] = [:]
    private var bibtexCache: [String: String] = [:]
    private var risCache: [String: String] = [:]
    private var pdfCache: [String: URL] = [:]
    private var pendingMetadata: [String: PendingPaperMetadata] = [:]

    private let tempDirectory: URL
    private let fileManager = FileManager.default

    private let logger = Logger(subsystem: "com.imbib.core", category: "SessionCache")

    // MARK: - Initialization

    private init() {
        // Create temp directory for session cache
        let tempBase = fileManager.temporaryDirectory
        self.tempDirectory = tempBase.appendingPathComponent("imbib-session-\(UUID().uuidString)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            logger.info("Created session cache directory: \(self.tempDirectory.path)")
        } catch {
            logger.error("Failed to create session cache directory: \(error.localizedDescription)")
        }
    }

    // MARK: - Search Results

    /// Cache search results for a query
    public func cacheSearchResults(_ results: [SearchResult], for query: String, sourceIDs: [String]) {
        let key = cacheKey(query: query, sourceIDs: sourceIDs)
        searchResults[key] = CachedSearchResults(
            results: results,
            timestamp: Date()
        )

        // Evict old entries if over limit
        evictOldSearchResults()

        logger.debug("Cached \(results.count) results for query: \(query)")
    }

    /// Get cached search results if still valid
    public func getCachedResults(for query: String, sourceIDs: [String]) -> [SearchResult]? {
        let key = cacheKey(query: query, sourceIDs: sourceIDs)
        guard let cached = searchResults[key] else { return nil }

        // Check if expired
        if Date().timeIntervalSince(cached.timestamp) > Self.maxResultAge {
            searchResults.removeValue(forKey: key)
            return nil
        }

        logger.debug("Cache hit for query: \(query)")
        return cached.results
    }

    /// Clear cached results for a query
    public func clearResults(for query: String, sourceIDs: [String]) {
        let key = cacheKey(query: query, sourceIDs: sourceIDs)
        searchResults.removeValue(forKey: key)
    }

    // MARK: - BibTeX Cache

    /// Cache BibTeX for a paper
    public func cacheBibTeX(_ bibtex: String, for paperID: String) {
        bibtexCache[paperID] = bibtex
    }

    /// Get cached BibTeX
    public func getCachedBibTeX(for paperID: String) -> String? {
        bibtexCache[paperID]
    }

    // MARK: - RIS Cache

    /// Cache RIS for a paper
    public func cacheRIS(_ ris: String, for paperID: String) {
        risCache[paperID] = ris
    }

    /// Get cached RIS
    public func getCachedRIS(for paperID: String) -> String? {
        risCache[paperID]
    }

    // MARK: - PDF Cache

    /// Download and cache a PDF for temporary viewing
    public func cachePDF(from url: URL, for paperID: String) async throws -> URL {
        // Check if already cached
        if let cached = pdfCache[paperID], fileManager.fileExists(atPath: cached.path) {
            return cached
        }

        // Download to temp directory
        let filename = "\(paperID).pdf"
        let localURL = tempDirectory.appendingPathComponent(filename)

        logger.info("Downloading PDF for \(paperID) from \(url)")

        let (tempURL, _) = try await URLSession.shared.download(from: url)

        // Move to our temp directory
        if fileManager.fileExists(atPath: localURL.path) {
            try fileManager.removeItem(at: localURL)
        }
        try fileManager.moveItem(at: tempURL, to: localURL)

        pdfCache[paperID] = localURL

        // Check cache size and evict if needed
        await evictOldPDFs()

        logger.info("Cached PDF for \(paperID) at \(localURL.path)")
        return localURL
    }

    /// Get cached PDF URL if available
    public func getCachedPDF(for paperID: String) -> URL? {
        guard let url = pdfCache[paperID],
              fileManager.fileExists(atPath: url.path) else {
            pdfCache.removeValue(forKey: paperID)
            return nil
        }
        return url
    }

    // MARK: - Pending Metadata

    /// Store temporary metadata for a paper before import
    public func setMetadata(_ metadata: PendingPaperMetadata, for paperID: String) {
        pendingMetadata[paperID] = metadata
    }

    /// Get pending metadata for a paper
    public func getMetadata(for paperID: String) -> PendingPaperMetadata? {
        pendingMetadata[paperID]
    }

    /// Clear pending metadata after import
    public func clearMetadata(for paperID: String) {
        pendingMetadata.removeValue(forKey: paperID)
    }

    /// Update specific metadata fields
    public func updateMetadata(
        for paperID: String,
        tags: Set<String>? = nil,
        notes: String? = nil,
        customCiteKey: String? = nil
    ) {
        var metadata = pendingMetadata[paperID] ?? PendingPaperMetadata()
        if let tags = tags { metadata.tags = tags }
        if let notes = notes { metadata.notes = notes }
        if let key = customCiteKey { metadata.customCiteKey = key }
        pendingMetadata[paperID] = metadata
    }

    // MARK: - Cleanup

    /// Clean up all cached data (call on app termination)
    public func cleanup() {
        logger.info("Cleaning up session cache")

        // Clear in-memory caches
        searchResults.removeAll()
        bibtexCache.removeAll()
        risCache.removeAll()
        pdfCache.removeAll()
        pendingMetadata.removeAll()

        // Remove temp directory
        do {
            if fileManager.fileExists(atPath: tempDirectory.path) {
                try fileManager.removeItem(at: tempDirectory)
                logger.info("Removed session cache directory")
            }
        } catch {
            logger.error("Failed to remove session cache directory: \(error.localizedDescription)")
        }
    }

    /// Clear all caches but keep the temp directory
    public func clearAll() {
        searchResults.removeAll()
        bibtexCache.removeAll()
        risCache.removeAll()
        pendingMetadata.removeAll()

        // Clear PDF files
        for (_, url) in pdfCache {
            try? fileManager.removeItem(at: url)
        }
        pdfCache.removeAll()
    }

    // MARK: - Private Helpers

    private func cacheKey(query: String, sourceIDs: [String]) -> String {
        let sortedSources = sourceIDs.sorted().joined(separator: ",")
        return "\(query.lowercased())|\(sortedSources)"
    }

    private func evictOldSearchResults() {
        // Remove expired entries
        let now = Date()
        searchResults = searchResults.filter { _, cached in
            now.timeIntervalSince(cached.timestamp) < Self.maxResultAge
        }

        // If still over limit, remove oldest
        while searchResults.count > Self.maxSearchResults {
            if let oldest = searchResults.min(by: { $0.value.timestamp < $1.value.timestamp }) {
                searchResults.removeValue(forKey: oldest.key)
            }
        }
    }

    private func evictOldPDFs() async {
        // Calculate total size
        var totalSize: Int64 = 0
        var fileSizes: [(String, URL, Int64)] = []

        for (paperID, url) in pdfCache {
            if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                totalSize += size
                fileSizes.append((paperID, url, size))
            }
        }

        // Evict oldest files until under limit
        if totalSize > Self.maxPDFCacheSize {
            // Sort by modification date (oldest first)
            fileSizes.sort { lhs, rhs in
                let lhsDate = (try? fileManager.attributesOfItem(atPath: lhs.1.path)[.modificationDate] as? Date) ?? .distantPast
                let rhsDate = (try? fileManager.attributesOfItem(atPath: rhs.1.path)[.modificationDate] as? Date) ?? .distantPast
                return lhsDate < rhsDate
            }

            for (paperID, url, size) in fileSizes {
                if totalSize <= Self.maxPDFCacheSize {
                    break
                }
                try? fileManager.removeItem(at: url)
                pdfCache.removeValue(forKey: paperID)
                totalSize -= size
                logger.debug("Evicted cached PDF: \(paperID)")
            }
        }
    }
}

// MARK: - Cached Search Results

private struct CachedSearchResults {
    let results: [SearchResult]
    let timestamp: Date
}

// MARK: - Pending Paper Metadata

/// Temporary metadata that can be attached to a paper before import.
public struct PendingPaperMetadata: Sendable, Equatable {
    public var tags: Set<String>
    public var notes: String
    public var customCiteKey: String?

    public init(
        tags: Set<String> = [],
        notes: String = "",
        customCiteKey: String? = nil
    ) {
        self.tags = tags
        self.notes = notes
        self.customCiteKey = customCiteKey
    }

    public var isEmpty: Bool {
        tags.isEmpty && notes.isEmpty && customCiteKey == nil
    }
}
