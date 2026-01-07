//
//  SmartSearchProviderCache.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-07.
//

import Foundation

// MARK: - Smart Search Provider Cache

/// Caches SmartSearchProvider instances to avoid re-fetching when switching between views.
///
/// This cache is actor-isolated for thread safety and stores providers keyed by
/// the smart search UUID. When a smart search is edited, call `invalidate` to
/// clear the cached provider.
public actor SmartSearchProviderCache {
    public static let shared = SmartSearchProviderCache()

    private var providers: [UUID: SmartSearchProvider] = [:]

    public init() {}

    /// Get an existing provider or create a new one for the smart search.
    public func getOrCreate(
        for smartSearch: CDSmartSearch,
        sourceManager: SourceManager,
        repository: PublicationRepository
    ) -> SmartSearchProvider {
        if let existing = providers[smartSearch.id] {
            return existing
        }
        let provider = SmartSearchProvider(
            from: smartSearch,
            sourceManager: sourceManager,
            repository: repository
        )
        providers[smartSearch.id] = provider
        return provider
    }

    /// Invalidate cached provider (call when smart search is edited)
    public func invalidate(_ id: UUID) {
        providers.removeValue(forKey: id)
    }

    /// Invalidate all cached providers
    public func invalidateAll() {
        providers.removeAll()
    }
}
