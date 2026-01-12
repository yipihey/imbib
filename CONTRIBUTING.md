# Contributing to imbib

Thanks for your interest in contributing to imbib! This document will help you get started.

## Getting Started

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later
- Swift 5.9+

### Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/yipihey/imbib.git
   cd imbib
   ```

2. Build the Swift Package (core library):
   ```bash
   cd PublicationManagerCore
   swift build
   ```

3. Run tests:
   ```bash
   swift test
   ```

4. Open in Xcode:
   ```bash
   open imbib/imbib.xcodeproj
   ```

5. Build the macOS app:
   - Select the `imbib` scheme
   - Press Cmd+B to build

### Project Structure

```
imbib/
├── PublicationManagerCore/    # Shared Swift Package (95% of code)
│   └── Sources/
│       └── PublicationManagerCore/
│           ├── Models/        # Core Data + BibTeX models
│           ├── Repositories/  # Data access layer
│           ├── Services/      # Business logic
│           ├── Sources/       # Search source plugins
│           └── SharedViews/   # Cross-platform SwiftUI
├── imbib/                     # macOS app shell
├── imbib-iOS/                 # iOS app shell
├── imbib-cli/                 # Command-line tool
├── imbibBrowserExtension/     # Chrome/Firefox/Edge extension
└── docs/                      # Documentation website
```

## Documentation

| Document | Purpose |
|----------|---------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design and data flow |
| [CONVENTIONS.md](CONVENTIONS.md) | Coding style and patterns |
| [SOURCES.md](SOURCES.md) | How to implement search source plugins |
| [CLAUDE.md](CLAUDE.md) | AI-assisted development context |
| [docs/adr/](docs/adr/) | Architecture Decision Records |

## Architecture Decision Records (ADRs)

We document significant technical decisions as ADRs. Browse them at [docs/adr/](docs/adr/).

Key decisions:
- **ADR-001**: Core Data over SwiftData
- **ADR-002**: BibTeX as source of truth
- **ADR-003**: Plugin architecture for search sources
- **ADR-004**: Human-readable PDF filenames

When making architectural changes, consider adding a new ADR.

## Development Workflow

1. **Create a branch** for your feature or fix
2. **Write tests** for new functionality
3. **Follow conventions** in [CONVENTIONS.md](CONVENTIONS.md)
4. **Run tests** before submitting: `swift test`
5. **Submit a PR** with a clear description

## Adding a New Search Source

See [SOURCES.md](SOURCES.md) for the complete guide. In brief:

1. Create a new file in `PublicationManagerCore/Sources/Sources/`
2. Implement the `SourcePlugin` protocol
3. Register in `SourceManager`
4. Add tests

## AI-Assisted Development

This project is designed to work well with AI coding assistants. See [CLAUDE.md](CLAUDE.md) for:

- Project context and architecture summary
- Key design decisions
- Current development phase
- Session continuity tips

## Reporting Issues

- Use [GitHub Issues](https://github.com/yipihey/imbib/issues)
- Include macOS/iOS version
- Include steps to reproduce
- Attach relevant logs from Console.app if applicable

## Code of Conduct

Be respectful and constructive. We're all here to build a better tool for researchers.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
