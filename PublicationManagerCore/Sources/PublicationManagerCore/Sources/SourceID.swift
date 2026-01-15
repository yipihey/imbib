//
//  SourceID.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-06.
//

import Foundation

// MARK: - Source ID

/// Type-safe identifier for data sources (API providers).
///
/// This enum replaces unvalidated `sourceID: String` throughout the codebase,
/// providing compile-time safety for source comparisons and eliminating typos.
///
/// ## Usage
///
/// ```swift
/// // Instead of: result.sourceID == "ads"
/// result.sourceID == .ads
///
/// // Switch exhaustively
/// switch result.sourceID {
/// case .ads: handleADS()
/// case .arxiv: handleArXiv()
/// // ... all cases covered
/// }
/// ```
///
/// ## Adding New Sources
///
/// When adding a new source plugin:
/// 1. Add a new case to this enum
/// 2. The compiler will flag all switch statements that need updating
public enum SourceID: String, Sendable, Codable, CaseIterable, Hashable {
    /// arXiv preprint repository
    case arxiv

    /// NASA Astrophysics Data System
    case ads

    /// NASA Science Explorer (Earth/planetary science)
    case scix

    // MARK: - Display Name

    /// Human-readable name for UI display
    public var displayName: String {
        switch self {
        case .arxiv: return "arXiv"
        case .ads: return "NASA ADS"
        case .scix: return "NASA SciX"
        }
    }

    // MARK: - String Conversion

    /// Initialize from a raw string value (case-insensitive).
    ///
    /// This is useful for backward compatibility with existing string-based code
    /// and for parsing source IDs from external data.
    ///
    /// - Parameter string: The source ID string (e.g., "ads", "ADS", "Ads")
    /// - Returns: The matching SourceID, or nil if not recognized
    public init?(string: String) {
        switch string.lowercased() {
        case "arxiv": self = .arxiv
        case "ads": self = .ads
        case "scix": self = .scix
        default: return nil
        }
    }

    // MARK: - Icon

    /// SF Symbol name for this source
    public var iconName: String {
        switch self {
        case .arxiv: return "doc.text"
        case .ads: return "sparkles"
        case .scix: return "globe.americas"
        }
    }
}
