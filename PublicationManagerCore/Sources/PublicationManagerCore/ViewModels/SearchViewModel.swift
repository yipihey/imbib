//
//  SearchViewModel.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-04.
//

import Foundation
import OSLog
import SwiftUI

// MARK: - Search View Model

/// View model for searching across publication sources.
@MainActor
@Observable
public final class SearchViewModel {

    // MARK: - Published State

    public private(set) var results: [DeduplicatedResult] = []
    public private(set) var isSearching = false
    public private(set) var error: Error?

    public var query = ""
    public var selectedSourceIDs: Set<String> = []
    public var selectedResults: Set<String> = []

    // MARK: - Dependencies

    private let sourceManager: SourceManager
    private let deduplicationService: DeduplicationService
    private let repository: PublicationRepository

    // MARK: - Initialization

    public init(
        sourceManager: SourceManager = SourceManager(),
        deduplicationService: DeduplicationService = DeduplicationService(),
        repository: PublicationRepository = PublicationRepository()
    ) {
        self.sourceManager = sourceManager
        self.deduplicationService = deduplicationService
        self.repository = repository
    }

    // MARK: - Available Sources

    public var availableSources: [SourceMetadata] {
        get async {
            await sourceManager.availableSources
        }
    }

    // MARK: - Search

    public func search() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }

        Logger.viewModels.entering()
        defer { Logger.viewModels.exiting() }

        isSearching = true
        error = nil
        results = []

        do {
            let options = SearchOptions(
                maxResults: 100,
                sortOrder: .relevance,
                sourceIDs: selectedSourceIDs.isEmpty ? nil : Array(selectedSourceIDs)
            )

            let rawResults = try await sourceManager.search(query: query, options: options)
            results = await deduplicationService.deduplicate(rawResults)

            Logger.viewModels.info("Search returned \(self.results.count) deduplicated results")
        } catch {
            self.error = error
            Logger.viewModels.error("Search failed: \(error.localizedDescription)")
        }

        isSearching = false
    }

    // MARK: - Import

    public func importResult(_ result: DeduplicatedResult) async throws {
        Logger.viewModels.info("Importing: \(result.primary.title)")

        let entry = try await sourceManager.fetchBibTeX(for: result.primary)
        await repository.create(from: entry)
    }

    public func importSelected() async throws -> Int {
        Logger.viewModels.info("Importing \(self.selectedResults.count) results")

        var imported = 0

        for resultID in selectedResults {
            guard let result = results.first(where: { $0.id == resultID }) else { continue }

            do {
                try await importResult(result)
                imported += 1
            } catch {
                Logger.viewModels.error("Failed to import \(result.primary.title): \(error.localizedDescription)")
            }
        }

        selectedResults.removeAll()
        return imported
    }

    // MARK: - Selection

    public func toggleSelection(_ result: DeduplicatedResult) {
        if selectedResults.contains(result.id) {
            selectedResults.remove(result.id)
        } else {
            selectedResults.insert(result.id)
        }
    }

    public func selectAll() {
        selectedResults = Set(results.map { $0.id })
    }

    public func clearSelection() {
        selectedResults.removeAll()
    }

    // MARK: - Source Selection

    public func toggleSource(_ sourceID: String) {
        if selectedSourceIDs.contains(sourceID) {
            selectedSourceIDs.remove(sourceID)
        } else {
            selectedSourceIDs.insert(sourceID)
        }
    }

    public func selectAllSources() async {
        selectedSourceIDs = Set(await availableSources.map { $0.id })
    }

    public func clearSourceSelection() {
        selectedSourceIDs.removeAll()
    }
}
