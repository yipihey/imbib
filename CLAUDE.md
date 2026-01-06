# PublicationManager - Claude Code Briefing

## Project Overview

A cross-platform (macOS/iOS) scientific publication manager with:
- BibTeX database management (BibDesk-compatible)
- PDF library with human-readable filenames
- Multi-source search (arXiv, PubMed, Crossref, ADS, etc.)
- CloudKit sync between devices

Target users: Academics, researchers, and students who use LaTeX/BibTeX workflows.

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────┐
│  macOS App              │           iOS App                 │
│  └─ Platform UI         │           └─ Platform UI          │
├─────────────────────────┴───────────────────────────────────┤
│                    Shared SwiftUI Views                     │
├─────────────────────────────────────────────────────────────┤
│                    Platform Abstraction                     │
│              (PDFViewer, FileImporter, Sharing)             │
├─────────────────────────────────────────────────────────────┤
│                 PublicationManagerCore                      │
│    Models │ Repositories │ Services │ Plugins │ ViewModels │
├─────────────────────────────────────────────────────────────┤
│                    Core Data + CloudKit                     │
└─────────────────────────────────────────────────────────────┘
```

### Package Structure
- **PublicationManagerCore**: Swift Package containing 95% of code
- **PublicationManager-macOS**: Thin shell, platform-specific UI only  
- **PublicationManager-iOS**: Thin shell, platform-specific UI only

All business logic, models, view models, and shared views live in Core.

## Key Design Decisions

### Data Layer
- **Core Data + CloudKit** (not SwiftData—broader training corpus)
- Repository pattern: `PublicationRepository` abstracts Core Data
- See `001-core-data-over-swiftdata.md`

### BibTeX Compatibility
- `.bib` files are the portable format; Core Data is the working store
- Preserve unknown fields verbatim for round-trip fidelity
- Support `Bdsk-File-*` fields (base64-encoded plist with relativePath)
- Generate cite keys: `{LastName}{Year}{TitleWord}`
- See `002-bibtex-source-of-truth.md`

### File Management
- PDFs stored with human-readable names: `Author_Year_Title.pdf`
- Reference by UUID internally; path is derived
- No content-addressed storage (breaks annotation, BibDesk compat)
- Relative paths from `.bib` file location
- **macOS**: User-selected library folder with security-scoped bookmarks
- **iOS**: App container with CloudKit sync, export to Files.app on demand
- See `004-human-readable-pdf-names.md`, `006-ios-file-handling.md`

### Plugin System
- Protocol: `SourcePlugin` (see `PublicationManagerCore/Sources/Sources/`)
- Built-in: ArXiv, Crossref, PubMed, ADS, Semantic Scholar, OpenAlex, DBLP
- User-extensible via JSON config bundles (phase 2)
- All plugins use `actor` for thread safety + rate limiting
- See `003-plugin-architecture.md`

### Cross-Platform Strategy
- Use `#if os(macOS)` / `#if os(iOS)` sparingly
- Prefer `ViewModifier` for platform differences
- Abstract platform APIs behind protocols (e.g., `PDFViewing`)
- Typealiases: `PlatformImage`, `PlatformColor`
- See `005-swiftui-frontend.md`, `006-ios-file-handling.md`

### Sync & Conflict Resolution
- CloudKit for cross-device sync
- Field-level timestamps for scalar merge (last-writer-wins per field)
- Union merge for relationships (tags, collections)
- User prompt for cite key collisions and PDF conflicts
- See `007-conflict-resolution.md`

### API Keys & Authentication
- Store API keys in Keychain (not UserDefaults)
- Each source declares credential requirements
- Graceful degradation when credentials missing
- Settings UI for key management
- See `008-api-key-management.md`

### Search Deduplication
- Identifier graph links DOI ↔ arXiv ID ↔ PMID ↔ bibcode
- Fuzzy matching (title + first author) for entries without shared IDs
- Unified results with multiple source options
- See `009-deduplication-service.md`

### BibTeX Parser
- Custom Swift parser using [swift-parsing](https://github.com/pointfreeco/swift-parsing)
- NOT btparse (thread-safety issues incompatible with Swift concurrency)
- Handles: nested braces, string macros, concatenation, crossref inheritance
- Extensive test fixtures from BibDesk and real-world files
- See `010-bibtex-parser-strategy.md`

### RIS Format Support
- First-class RIS (Research Information Systems) format support
- `RISParser`: Parse `.ris` files from EndNote, Zotero, Mendeley
- `RISExporter`: Export to RIS with proper tag formatting
- `RISBibTeXConverter`: Bidirectional RIS ↔ BibTeX conversion
- 50+ reference types (JOUR, BOOK, CONF, THES, etc.)
- 65+ tags with metadata (AU, TI, PY, DO, etc.)
- See `013-ris-format-support.md` (ADR-013)

## Coding Conventions

### Swift Style
- Swift 5.9+, strict concurrency checking enabled
- `actor` for stateful services with async methods
- `struct` for data transfer objects and BibTeX entries
- `final class` for view models with `@Observable` or `ObservableObject`
- Prefer `async/await` over Combine for new code

### Naming
| Type | Convention | Example |
|------|------------|---------|
| Protocols | `*ing` or `*able` | `BibTeXParsing`, `SourceManaging` |
| Implementations | No suffix | `BibTeXParser`, `SourceManager` |
| View models | `*ViewModel` | `LibraryViewModel` |
| Platform-specific | `+platform.swift` | `PDFViewer+macOS.swift` |

### File Organization
```swift
// MARK: - Public Interface
// MARK: - Private Implementation  
// MARK: - Protocol Conformance
```

### Error Handling
- Domain-specific errors: `BibTeXError`, `SourceError`, `FileError`
- Conform to `LocalizedError` with `errorDescription`
- Never force-unwrap; use `guard let` with meaningful errors

### Testing
- Unit tests for Core package (parsers, plugins, repositories)
- Mock all protocols for isolation
- Use `async` test methods
- Test file: `*Tests.swift` in `PublicationManagerTests/`

## Key Types

```swift
// Core Data model
Publication: NSManagedObject {
    citeKey: String
    entryType: String           // article, book, inproceedings...
    rawBibTeX: String?          // Original for round-trip
    // Relationships: authors, linkedFiles, tags, collections
}

// Plugin protocol
protocol SourcePlugin: Sendable {
    var metadata: SourceMetadata { get }
    func search(query: String) async throws -> [SearchResult]
    func fetchBibTeX(for result: SearchResult) async throws -> BibTeXEntry
    func normalize(_ entry: BibTeXEntry) -> BibTeXEntry
}

// Search result (cross-source)
struct SearchResult: Identifiable, Sendable {
    let id: String              // Source-specific (DOI, arXiv ID)
    let title: String
    let authors: [String]
    let year: Int?
    let venue: String?
    let sourceID: String        // Which plugin produced this
    let pdfURL: URL?
}

// BibTeX interchange format
struct BibTeXEntry: Sendable {
    var citeKey: String
    var entryType: String
    var fields: [String: String]
    var rawBibTeX: String?      // Preserve for round-trip
}

// RIS interchange format
struct RISEntry: Sendable {
    var type: RISReferenceType  // JOUR, BOOK, CONF, etc.
    var tags: [RISTagValue]     // Ordered list of tag-value pairs
    var rawRIS: String?         // Preserve for round-trip
    // Convenience: authors, title, year, doi, etc.
}
```

## Project Phases

### Phase 1: Foundation (Complete)
- [x] Project structure and Swift Package
- [x] Architecture decisions documented (ADR-001 through ADR-012)
- [x] Core Data model + PersistenceController
- [x] BibTeXParser (import)
- [x] BibTeXExporter (export with Bdsk-File-*)
- [x] SourcePlugin protocol
- [x] ArXivSource implementation
- [x] CredentialManager + Keychain storage
- [x] Basic SwiftUI: LibraryView, PublicationDetailView
- [x] All built-in sources: Crossref, ADS, Semantic Scholar, OpenAlex, DBLP
- [x] Search deduplication service
- [x] Console window for debugging (ADR-011)
- [x] Unified paper abstraction (ADR-012)

### Phase 2: Core Features (Current)
- [x] PDF import and auto-filing (PDFManager with BibDesk compatibility)
- [ ] CloudKit sync with conflict resolution
- [x] Multiple library support (LibraryManager)
- [x] Smart searches (stored queries)
- [x] Unified Paper Model (ADR-016: all papers are CDPublication)
- [x] RIS format core module (ADR-013 Phase 1)

### Phase 3: Polish
- [x] PDF viewer (basic viewing complete, annotation pending)
- [ ] PDF annotation support
- [x] BibTeX editor with syntax highlighting
- [x] Smart collections
- [x] Export templates
- [x] DBLP source (implemented + tests)

### Phase 4: Extensibility
- [ ] JSON config bundles for user sources
- [ ] JavaScriptCore for complex transformations
- [ ] Keyboard shortcuts (macOS)
- [ ] Shortcuts/Siri integration (iOS)

### ADR-013: RIS Integration ✅ COMPLETE
All phases complete: Core Module, Integration, Online Source Integration, and UI Polish.

**Phase 2: Integration** ✅ COMPLETE
- [x] Update `PublicationRepository` to import `.ris` files
- [x] Replace template-based RIS export with `RISExporter`
- [x] Add RIS import to file picker / drag-drop handlers
- [x] Wire up RIS ↔ BibTeX conversion in import flow

**Phase 3: Online Source Integration** ✅ COMPLETE
- [x] Audit which sources return RIS data (Crossref, ADS)
- [x] Add `fetchRIS`/`supportsRIS` to SourcePlugin protocol
- [x] Implement fetchRIS in CrossrefSource (DOI content negotiation)
- [x] Implement fetchRIS in ADSSource (/export/ris endpoint)
- [x] RIS converted to BibTeX at import (no RIS caching needed after ADR-016)

**Phase 4: UI Polish** ✅ COMPLETE
- [x] RIS preview in import dialog (ImportPreviewView)
- [x] Format selection (BibTeX vs RIS) in export (ExportView already supports)

## DO NOT Implement Yet
- CloudKit sync (phase 2)
- PDF annotation (phase 3)  
- JavaScript plugin runtime (phase 4)
- CSL citation formatting

## Commands

```bash
# Build the Swift Package
cd PublicationManagerCore
swift build

# Run tests
swift test

# Build macOS app
xcodebuild -scheme PublicationManager-macOS -configuration Debug build

# Build iOS app (simulator)
xcodebuild -scheme PublicationManager-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 15' \
    -configuration Debug build

# Generate Xcode project for Core package (if needed)
swift package generate-xcodeproj
```

## Reference Documents

| Document | Purpose |
|----------|---------|
| `ARCHITECTURE.md` | Detailed system design |
| `CONVENTIONS.md` | Extended coding style guide |
| `SOURCES.md` | Plugin implementation guide |
| `001-009-*.md` | Architecture decision records |

### ADR Quick Reference

| ADR | Summary |
|-----|---------|
| 001 | Core Data over SwiftData |
| 002 | BibTeX as portable format, Core Data as working store |
| 003 | Hybrid plugin architecture (Swift built-in + JSON config) |
| 004 | Human-readable PDF filenames (`Author_Year_Title.pdf`) |
| 005 | SwiftUI with NavigationSplitView |
| 006 | iOS file handling (app container + CloudKit, not folder access) |
| 007 | Conflict resolution (field-level merge, user prompt for collisions) |
| 008 | API key management (Keychain storage, graceful degradation) |
| 009 | Cross-source deduplication (identifier graph + fuzzy matching) |
| 010 | Custom Swift BibTeX parser using swift-parsing (not btparse) |
| 011 | Console window for debugging (LogStore + dual logging) |
| 012 | Unified library/online experience (PaperRepresentable, SessionCache) |
| 013 | First-class RIS format (RISParser, RISExporter, RISBibTeXConverter) |
| 015 | PDF settings (source priority, library proxy, ADSSource pdfURL fix) |
| 016 | Unified Paper Model: All papers are CDPublication (auto-import, no OnlinePaper) |

## Session Continuity

When resuming work, check:
1. `git status` for current branch and changes
2. `docs/adr/` for recent decisions
3. Phase checklist above for priorities

Update the changelog below after significant work:

## Changelog

### 2026-01-05 (Session 10)
- Unified publication list views for feature parity
  - Created PublicationListView shared component in SharedViews
  - All three list views now use identical code: Library, Smart Search, Ad-hoc Search
- PublicationListView features:
  - Inline toolbar (search field, unread filter, import button, sort menu)
  - MailStylePublicationRow for consistent paper display
  - Full context menu (Open PDF, Copy/Cut, Copy Cite Key, Move To Library, Add To Collection, Delete)
  - Keyboard delete support
  - Multi-selection with UUID-based selection binding
  - Configurable callbacks for all operations
  - **State persistence** via ListViewStateStore (selection, sort order, filters)
- ListViewStateStore (new)
  - Actor-based with UserDefaults + in-memory cache (same pattern as ReadingPositionStore)
  - Persists per library/collection/smart search/last search
  - Stores: selectedPublicationID, sortOrder, showUnreadOnly, lastVisitedDate
  - ListViewID enum: .library(UUID), .collection(UUID), .smartSearch(UUID), .lastSearch(UUID)
- LibraryListView simplified (~380 → ~175 lines)
  - Now wraps PublicationListView with library-specific callbacks
  - Maintains notification handlers for keyboard shortcuts
  - Passes listID: .library(library.id) for state persistence
- SmartSearchResultsView gains full library features
  - Context menu, keyboard shortcuts, sorting, filtering
  - Keeps refresh toolbar button for re-executing search
  - Passes listID: .smartSearch(smartSearch.id) for state persistence
- SearchResultsListView unified
  - Replaced PublicationSearchRow with MailStylePublicationRow
  - Keeps search header with source filter chips
  - Gains all library features (context menu, shortcuts, sorting)
  - Passes listID: .lastSearch(collection.id) for state persistence
- Per ADR-016: No material difference between library and search views
- Fixed ADS year extraction bug causing "Author_NoYear_Title.pdf" filenames
  - Bug: `doc["year"] as? Int` failed when ADS returned year as String
  - Fix: `(doc["year"] as? Int) ?? (doc["year"] as? String).flatMap { Int($0) }`
  - File: `ADSSource.swift:239`
  - Added 2 new tests: `testParseDoc_yearAsInt_parsesCorrectly`, `testParseDoc_yearAsString_parsesCorrectly`
- Fixed deletion crash when deleting selected smart search, collection, or library
  - Root cause: Selection binding retained reference to deleted Core Data object
  - Fix: Clear `selection` BEFORE deletion in `deleteSmartSearch()`, `deleteCollection()`, `deleteLibrary()`
  - Also handles cascade: deleting library now clears selection if any nested item is selected
  - File: `SidebarView.swift` (lines 412-423, 455-464, 468-484)
- All 743 tests passing

### 2026-01-05 (Session 9)
- Multi-library sidebar with disclosure groups
  - Each library displayed as disclosure group with own publications, smart searches, collections
  - Per-library navigation: All Publications, Unread, Smart Searches, Collections
  - "Add..." menu for creating smart searches/collections within library
  - Bottom toolbar with +/- for library management
  - NewLibrarySheet with folder picker (macOS)
- Core Data relationship updates
  - Added owningLibrary relationship to CDPublication (many-to-one)
  - Added library relationship to CDCollection (many-to-one)
  - Added publications and collections relationships to CDLibrary (one-to-many)
  - Cascade delete for publications/collections when library deleted
- SidebarSection enum refactored
  - .library(CDLibrary), .unread(CDLibrary) for library-specific views
  - Smart searches and collections now library-scoped via relationships
- LibraryListView now takes CDLibrary parameter
- Fixed sort order to match LibrarySortOrder enum cases
- Added ReadingPositionStore for PDF reading position tracking (page, zoom, date)
- All 741 tests passing

### 2026-01-05 (Session 8)
- Implemented ADR-016: Unified Paper Model
  - All papers are now CDPublication entities (no more OnlinePaper)
  - Search results auto-import to Last Search collection or smart search collections
  - Deduplication via DOI, arXiv ID, bibcode, Semantic Scholar ID, OpenAlex ID
- Deleted OnlinePaper.swift (replaced by CDPublication)
- Simplified SessionCache to only cache search API responses
  - Removed: bibtexCache, risCache, pdfCache, pendingMetadata, enrichmentCache
  - Kept: searchResults (for API response caching)
- Updated PDFURLResolver to work with CDPublication
- Simplified UnifiedDetailView to single CDPublication path
  - Removed OnlinePaper initializer and casts
  - Unified PDF download flow via PDFManager
- Updated UnifiedPDFTab to use PDFManager for all PDF downloads
- Fixed Core Data entity conflicts in tests (cached NSManagedObjectModel)
- Removed OnlinePaperPDFViewer
- All 741 tests passing

### 2026-01-04 (Session 7)
- Unified PaperDetailView and PublicationDetailView into single UnifiedDetailView
- Created UnifiedDetailView.swift with protocol-based approach:
  - Works with any PaperRepresentable (OnlinePaper, LocalPaper)
  - Conditional editing for persistent papers (library items)
  - Four tabs: Metadata, BibTeX, PDF, Notes
  - Notes tab only shown for library papers
- Implemented full Add PDF functionality:
  - fileImporter for PDF selection
  - PDFManager integration for file import
  - Proper UI refresh after import
- Updated BibTeXExporter.generateEntry to accept any PaperRepresentable
- Fixed PDF viewing for library papers using linkedFile initializer
- Removed deprecated PaperDetailView.swift and PublicationDetailView.swift
- All 756 tests passing

### 2026-01-04 (Session 6)
- Implemented ADR-015: PDF Settings and URL Resolution
- Created PDFSettingsStore (actor-based settings with UserDefaults)
  - PDFSourcePriority enum (.preprint, .publisher)
  - PDFSettings struct (priority, proxy URL, proxy enabled)
  - Common proxy presets (Stanford, Harvard, MIT, Berkeley)
- Created PDFURLResolver for resolving PDF URLs based on settings
  - Preprint priority: arXiv → publisher fallback
  - Publisher priority: publisher → arXiv fallback
  - Library proxy support (URL prefix approach)
  - ADS gateway URLs for non-arXiv papers
- Fixed ADSSource to populate pdfURL in search results
  - Papers with arXiv ID get arXiv PDF URL
  - Papers without arXiv get ADS link gateway URL
- Created PDFSettingsTab UI with source priority and proxy config
- Added PDF tab to SettingsView
- Updated PaperPDFTabView to use PDFURLResolver
- Added comprehensive tests (53 new tests)
  - PDFSettingsStoreTests (18 tests)
  - PDFURLResolverTests (25 tests)
  - ADSSourceTests (10 tests)
- ADR-015 written to project root

### 2026-01-04 (Session 5)
- Completed ADR-013 Phase 2: RIS integration into main application
- Fixed build: Added `ImportError.unsupportedFormat(String)` case
- Added `LibraryViewModel` RIS methods:
  - `importFile(from:)` - Dispatcher for .bib and .ris files
  - `importRIS(from:)` - Parse and import RIS files with logging
- Added `PublicationRepository` RIS methods:
  - `create(from: RISEntry)` - Create publication from RIS entry
  - `importRISEntries()`, `importRIS()`, `importRISFile()` - Batch import
  - `exportAllToRIS()`, `exportToRIS()` - Export to RIS format
- Updated `ExportTemplates` to use proper BibTeX/RIS exporters instead of templates
- Added RIS to file import dialog (ContentView.swift):
  - Accept both .bib and .ris file types
  - Uses `importFile()` dispatcher for format-based routing
- Fixed Xcode build issues:
  - Added missing files to Xcode project (SmartSearchResultsView, SmartSearchEditorView, LibraryPickerView)
  - Added `Identifiable` conformance to `CDCollection` for SwiftUI sheet binding
  - Fixed `BibTeXParser` usage: extract `BibTeXEntry` from `BibTeXItem` enum
- Completed ADR-013 Phase 3: Online Source Integration
  - Added `fetchRIS`/`supportsRIS` to SourcePlugin protocol
  - Added `SourceError.unsupportedFormat` for unsupported format errors
  - Implemented fetchRIS in CrossrefSource (DOI content negotiation)
  - Implemented fetchRIS in ADSSource (/export/ris endpoint)
  - Added RIS caching to SessionCache (risCache, cacheRIS, getCachedRIS)
- Completed ADR-013 Phase 4: UI Polish
  - Created ImportPreviewView for BibTeX/RIS file preview
  - Parse file and show entries before import
  - Toggle entries for selective import
  - Detail panel with raw BibTeX/RIS content
  - Updated ContentView to use preview sheet before import
  - Added ImportError.parseError and ImportError.cancelled cases
  - Note: ExportView already had format selection including RIS
- All 370 tests passing
- Xcode build succeeds
- ADR-013 complete (all 4 phases)

### 2026-01-04 (Session 4)
- Implemented ADR-013: First-class RIS format support
- Created RIS module (`PublicationManagerCore/Sources/PublicationManagerCore/RIS/`)
  - RISTypes.swift: RISEntry, RISTag (65+ tags), RISReferenceType (50+ types)
  - RISParser.swift: Parse RIS content with multi-line value support
  - RISExporter.swift: Export entries with builder API
  - RISBibTeXConverter.swift: Bidirectional RIS ↔ BibTeX conversion
- RIS features:
  - Full RIS specification support (TY/ER tags, repeatable AU/KW/UR)
  - Type mapping (JOUR↔article, BOOK↔book, CONF↔inproceedings, etc.)
  - Field mapping (authors, pages, keywords, DOI, abstract)
  - Cite key generation from RIS entries
  - Round-trip preservation with rawRIS field
  - Convenience extensions on RISEntry and BibTeXEntry
- Added comprehensive RIS tests (103 new tests)
  - RISParserTests.swift (49 tests)
  - RISExporterTests.swift (32 tests)
  - RISBibTeXConverterTests.swift (42 tests)
- Added RIS fixture files (sample.ris, multiple_authors.ris, all_types.ris)
- All 370 tests passing

### 2026-01-04 (Session 3)
- Added LibraryManager for multiple library support
- Added CDLibrary entity with security-scoped bookmarks
- Added CDSmartSearch entity with library relationship
- Implemented SmartSearchProvider and SmartSearchRepository
- Added comprehensive logging for library and smart search features
- Created PDFManager for PDF import and auto-filing (ADR-004)
- BibDesk compatibility: processBdskFiles() preserves existing PDF links
- Human-readable filenames: {Author}_{Year}_{Title}.pdf
- linkExistingPDF() for non-copying imports from BibDesk
- Download PDFs from online sources with importOnlinePaper()
- Added comprehensive tests for Phase 2 features (38 new tests)
  - PDFManagerTests (11 tests)
  - LibraryManagerTests (8 tests)
  - SmartSearchRepositoryTests (6 tests)
  - SessionCacheTests (13 tests)
- Created cross-platform PDFViewer using PDFKit
  - PDFKitViewer: Basic viewer for local files
  - PDFViewerWithControls: Toolbar with page navigation/zoom
  - OnlinePaperPDFViewer: Downloads from SessionCache
  - NSViewRepresentable (macOS) / UIViewRepresentable (iOS)
- Added bidirectional toolbar sync for PDF viewer
  - ControlledPDFKitView with coordinator for two-way binding
  - Uses PDFViewPageChanged and PDFViewScaleChanged notifications
- Created BibTeXEditor with syntax highlighting
  - BibTeXHighlighter: Colors for entry types, cite keys, fields, values
  - BibTeXValidator: Real-time validation with error bar
  - Edit/view modes with save functionality
- Implemented smart collections with predicate builder
  - SmartCollectionEditor: Rule-based UI for building predicates
  - SmartCollectionRule: field + comparison + value → NSPredicate
  - RuleField/RuleComparison enums for type-safe rule building
  - CollectionViewModel for managing collections
  - Sidebar integration with create/edit/delete
- Added export templates with multiple formats (BibTeX, RIS, Plain Text, Markdown, HTML, CSV)
  - ExportFormat enum with file extensions and MIME types
  - ExportTemplate struct for custom templates
  - TemplateEngine with placeholder substitution
  - ExportView with format picker and preview
  - ExportTemplateEditor for custom templates
  - ExportTemplateTests (19 tests)
- Added comprehensive DBLPSourceTests (25 tests)
  - Metadata tests (ID, name, credential requirements)
  - Response parsing tests (title, authors, year, venue, DOI, URLs)
  - Error handling tests (network errors, server errors, malformed JSON)
  - BibTeX fetch tests
  - URL query parameter tests
- All 267 tests passing

### 2026-01-04 (Session 2)
- ADR-012: Unified library and online search experience
- Implemented PaperRepresentable protocol for unified paper abstraction
- Implemented PaperProvider protocol for paper collections
- Created LocalPaper wrapper for CDPublication
- Created OnlinePaper wrapper for SearchResult
- Implemented SessionCache actor for temp PDFs and metadata
- Fixed BibTeX parser for `\\{` escape sequences
- Fixed delete crash when deleting multiple publications
- Fixed BibTeX view not updating on selection change
- Added notes persistence
- Added console window for debugging (ADR-011)
- Fixed year formatting (removed thousands separator)
- All 147 tests passing

### 2026-01-04 (Session 1)
- Initial documentation structure
- Architecture decisions documented (ADR-001 through ADR-010)
- SourcePlugin protocol designed
- All built-in sources implemented
- Core Data model and repository pattern
- Basic SwiftUI views
