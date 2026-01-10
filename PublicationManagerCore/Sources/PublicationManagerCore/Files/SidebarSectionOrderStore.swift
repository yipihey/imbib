//
//  SidebarSectionOrderStore.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-09.
//

import Foundation

// MARK: - Sidebar Section Type

/// Represents the reorderable sections in the sidebar (Inbox is always first, not included)
public enum SidebarSectionType: String, CaseIterable, Codable, Identifiable, Equatable {
    case libraries
    case scixLibraries
    case search

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .libraries: return "Libraries"
        case .scixLibraries: return "SciX Libraries"
        case .search: return "Search"
        }
    }
}

// MARK: - Sidebar Section Order Store

/// Persists the user's preferred order of sidebar sections
public actor SidebarSectionOrderStore {

    // MARK: - Singleton

    public static let shared = SidebarSectionOrderStore()

    // MARK: - Properties

    private let key = "sidebarSectionOrder"
    private var cachedOrder: [SidebarSectionType]?

    // MARK: - Default Order

    public static let defaultOrder: [SidebarSectionType] = [
        .libraries,
        .scixLibraries,
        .search
    ]

    // MARK: - Public API

    /// Get the current section order
    public func order() -> [SidebarSectionType] {
        if let cached = cachedOrder {
            return cached
        }

        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SidebarSectionType].self, from: data) else {
            cachedOrder = Self.defaultOrder
            return Self.defaultOrder
        }

        // Ensure all sections are present (in case new sections were added)
        var result = decoded.filter { Self.defaultOrder.contains($0) }
        for section in Self.defaultOrder where !result.contains(section) {
            result.append(section)
        }

        cachedOrder = result
        return result
    }

    /// Save a new section order
    public func save(_ order: [SidebarSectionType]) {
        cachedOrder = order
        if let data = try? JSONEncoder().encode(order) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Reset to default order
    public func reset() {
        cachedOrder = Self.defaultOrder
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Synchronous Load (for SwiftUI @State init)

    /// Load order synchronously (for initial SwiftUI state)
    public nonisolated static func loadOrderSync() -> [SidebarSectionType] {
        guard let data = UserDefaults.standard.data(forKey: "sidebarSectionOrder"),
              let decoded = try? JSONDecoder().decode([SidebarSectionType].self, from: data) else {
            return defaultOrder
        }

        // Ensure all sections are present
        var result = decoded.filter { defaultOrder.contains($0) }
        for section in defaultOrder where !result.contains(section) {
            result.append(section)
        }
        return result
    }
}

// MARK: - Notification

public extension Notification.Name {
    static let sidebarSectionOrderDidChange = Notification.Name("sidebarSectionOrderDidChange")
}
