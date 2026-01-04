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
- [x] Session cache for online papers

### Phase 3: Polish
- [x] PDF viewer (basic viewing complete, annotation pending)
- [ ] PDF annotation support
- [x] BibTeX editor with syntax highlighting
- [ ] Smart collections
- [ ] Export templates
- [ ] DBLP source

### Phase 4: Extensibility
- [ ] JSON config bundles for user sources
- [ ] JavaScriptCore for complex transformations
- [ ] Keyboard shortcuts (macOS)
- [ ] Shortcuts/Siri integration (iOS)

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

## Session Continuity

When resuming work, check:
1. `git status` for current branch and changes
2. `docs/adr/` for recent decisions
3. Phase checklist above for priorities

Update the changelog below after significant work:

## Changelog

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
- All 204 tests passing

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
