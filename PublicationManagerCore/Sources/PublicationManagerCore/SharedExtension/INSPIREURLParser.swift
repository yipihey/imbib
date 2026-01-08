//
//  INSPIREURLParser.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-08.
//

import Foundation

// MARK: - INSPIRE URL Parser

/// Parser for INSPIRE HEP URLs to extract record identifiers.
///
/// Supports various INSPIRE URL formats:
/// - `https://inspirehep.net/literature/12345`
/// - `https://labs.inspirehep.net/literature/12345`
/// - `https://inspirehep.net/api/literature/12345`
/// - `https://old.inspirehep.net/record/12345`
///
/// Used by the share extension to import papers from INSPIRE URLs.
public struct INSPIREURLParser {

    // MARK: - URL Patterns

    /// Supported INSPIRE hostnames
    private static let validHosts = [
        "inspirehep.net",
        "labs.inspirehep.net",
        "old.inspirehep.net",
        "www.inspirehep.net"
    ]

    // MARK: - Public Interface

    /// Parse an INSPIRE URL and extract the identifier.
    ///
    /// - Parameter url: The URL to parse
    /// - Returns: An `INSPIREIdentifier` if the URL is a valid INSPIRE URL, nil otherwise
    public static func parse(_ url: URL) -> INSPIREIdentifier? {
        guard let host = url.host?.lowercased(),
              validHosts.contains(where: { host.hasSuffix($0) }) else {
            return nil
        }

        // Try different URL patterns
        if let recid = parseModernLiteratureURL(url) {
            return .recordID(recid)
        }

        if let recid = parseAPILiteratureURL(url) {
            return .recordID(recid)
        }

        if let recid = parseLegacyRecordURL(url) {
            return .recordID(recid)
        }

        if let arxivID = parseArXivSearchURL(url) {
            return .arXivID(arxivID)
        }

        if let doi = parseDOISearchURL(url) {
            return .doi(doi)
        }

        return nil
    }

    /// Check if a URL is an INSPIRE URL (without parsing the identifier).
    ///
    /// - Parameter url: The URL to check
    /// - Returns: true if the URL is from an INSPIRE domain
    public static func isINSPIREURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }
        return validHosts.contains(where: { host.hasSuffix($0) })
    }

    // MARK: - URL Pattern Parsers

    /// Parse modern INSPIRE literature URL: /literature/12345
    private static func parseModernLiteratureURL(_ url: URL) -> Int? {
        let components = url.pathComponents
        guard let literatureIndex = components.firstIndex(of: "literature"),
              literatureIndex + 1 < components.count else {
            return nil
        }

        let recidString = components[literatureIndex + 1]
        return Int(recidString)
    }

    /// Parse API literature URL: /api/literature/12345
    private static func parseAPILiteratureURL(_ url: URL) -> Int? {
        let components = url.pathComponents
        guard let apiIndex = components.firstIndex(of: "api"),
              apiIndex + 2 < components.count,
              components[apiIndex + 1] == "literature" else {
            return nil
        }

        let recidString = components[apiIndex + 2]
        return Int(recidString)
    }

    /// Parse legacy INSPIRE record URL: /record/12345
    private static func parseLegacyRecordURL(_ url: URL) -> Int? {
        let components = url.pathComponents
        guard let recordIndex = components.firstIndex(of: "record"),
              recordIndex + 1 < components.count else {
            return nil
        }

        let recidString = components[recordIndex + 1]
        return Int(recidString)
    }

    /// Parse arXiv search URL: /literature?q=arxiv:2401.12345
    private static func parseArXivSearchURL(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let qItem = queryItems.first(where: { $0.name == "q" }),
              let query = qItem.value else {
            return nil
        }

        // Pattern: arxiv:XXXX.XXXXX
        let pattern = #"arxiv:(\d{4}\.\d{4,5}(?:v\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let range = Range(match.range(at: 1), in: query) else {
            return nil
        }

        return String(query[range])
    }

    /// Parse DOI search URL: /literature?q=doi:10.1234/...
    private static func parseDOISearchURL(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let qItem = queryItems.first(where: { $0.name == "q" }),
              let query = qItem.value else {
            return nil
        }

        // Pattern: doi:10.XXXX/...
        let pattern = #"doi:(10\.\d{4,}/[^\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let range = Range(match.range(at: 1), in: query) else {
            return nil
        }

        return String(query[range])
    }
}

// MARK: - INSPIRE Identifier

/// An identifier extracted from an INSPIRE URL.
public enum INSPIREIdentifier: Sendable, Equatable, Hashable {
    /// INSPIRE record ID (numeric)
    case recordID(Int)

    /// arXiv ID extracted from search URL
    case arXivID(String)

    /// DOI extracted from search URL
    case doi(String)

    /// The string representation of this identifier
    public var stringValue: String {
        switch self {
        case .recordID(let id):
            return String(id)
        case .arXivID(let id):
            return id
        case .doi(let doi):
            return doi
        }
    }

    /// Build an INSPIRE API query for this identifier
    public var apiQuery: String {
        switch self {
        case .recordID(let id):
            return "recid:\(id)"
        case .arXivID(let id):
            return "arxiv:\(id)"
        case .doi(let doi):
            return "doi:\(doi)"
        }
    }

    /// Build an INSPIRE literature page URL for this identifier
    public var webURL: URL? {
        switch self {
        case .recordID(let id):
            return URL(string: "https://inspirehep.net/literature/\(id)")
        case .arXivID(let id):
            return URL(string: "https://inspirehep.net/literature?q=arxiv:\(id)")
        case .doi(let doi):
            // URL encode the DOI
            let encodedDOI = doi.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? doi
            return URL(string: "https://inspirehep.net/literature?q=doi:\(encodedDOI)")
        }
    }
}
