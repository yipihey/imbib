//
//  ADSClassicSearchView.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-14.
//

import SwiftUI
import OSLog

// MARK: - ADS Search Field

/// All available ADS search fields with their syntax and descriptions
public enum ADSSearchField: String, CaseIterable, Identifiable {
    // Bibliographic fields
    case author
    case firstAuthor
    case title
    case abstract
    case abstractTitleKeywords
    case acknowledgements
    case fullText
    case body

    // Identifiers
    case bibcode
    case alternateBibcode
    case bibstem
    case doi
    case arxivID
    case arxivClass
    case identifier

    // Author & Affiliation
    case authorCount
    case affiliation
    case affiliationID
    case institution
    case orcid
    case orcidPub
    case orcidUser
    case orcidOther

    // Date & Publication
    case year
    case pubdate
    case volume
    case issue
    case page
    case copyright

    // Content & Metadata
    case keyword
    case language
    case vizierKeywords
    case alternateTitle

    // Metrics
    case citationCount
    case readCount

    // Classification
    case doctype
    case database
    case bibgroup
    case grant
    case property

    // Specialized
    case object
    case facility

    public var id: String { rawValue }

    /// The field syntax to use in queries
    public var syntax: String {
        switch self {
        case .author: return "author:"
        case .firstAuthor: return "author:\"^"
        case .title: return "title:"
        case .abstract: return "abstract:"
        case .abstractTitleKeywords: return "abs:"
        case .acknowledgements: return "ack:"
        case .fullText: return "full:"
        case .body: return "body:"
        case .bibcode: return "bibcode:"
        case .alternateBibcode: return "alternate_bibcode:"
        case .bibstem: return "bibstem:"
        case .doi: return "doi:"
        case .arxivID: return "arXiv:"
        case .arxivClass: return "arxiv_class:"
        case .identifier: return "identifier:"
        case .authorCount: return "author_count:"
        case .affiliation: return "aff:"
        case .affiliationID: return "aff_id:"
        case .institution: return "inst:"
        case .orcid: return "orcid:"
        case .orcidPub: return "orcid_pub:"
        case .orcidUser: return "orcid_user:"
        case .orcidOther: return "orcid_other:"
        case .year: return "year:"
        case .pubdate: return "pubdate:"
        case .volume: return "volume:"
        case .issue: return "issue:"
        case .page: return "page:"
        case .copyright: return "copyright:"
        case .keyword: return "keyword:"
        case .language: return "lang:"
        case .vizierKeywords: return "vizier:"
        case .alternateTitle: return "alternate_title:"
        case .citationCount: return "citation_count:"
        case .readCount: return "read_count:"
        case .doctype: return "doctype:"
        case .database: return "database:"
        case .bibgroup: return "bibgroup:"
        case .grant: return "grant:"
        case .property: return "property:"
        case .object: return "object:"
        case .facility: return "facility:"
        }
    }

    /// Display name for the field
    public var displayName: String {
        switch self {
        case .author: return "Author"
        case .firstAuthor: return "First Author"
        case .title: return "Title"
        case .abstract: return "Abstract"
        case .abstractTitleKeywords: return "Abstract/Title/Keywords"
        case .acknowledgements: return "Acknowledgements"
        case .fullText: return "Full Text"
        case .body: return "Body"
        case .bibcode: return "Bibcode"
        case .alternateBibcode: return "Alternate Bibcode"
        case .bibstem: return "Bibliographic Stem"
        case .doi: return "DOI"
        case .arxivID: return "arXiv ID"
        case .arxivClass: return "arXiv Class"
        case .identifier: return "Any Identifier"
        case .authorCount: return "Author Count"
        case .affiliation: return "Affiliation"
        case .affiliationID: return "Affiliation ID"
        case .institution: return "Institution"
        case .orcid: return "ORCID"
        case .orcidPub: return "ORCID (Publisher)"
        case .orcidUser: return "ORCID (ADS User)"
        case .orcidOther: return "ORCID (Other)"
        case .year: return "Year"
        case .pubdate: return "Publication Date"
        case .volume: return "Volume"
        case .issue: return "Issue"
        case .page: return "Page"
        case .copyright: return "Copyright"
        case .keyword: return "Keyword"
        case .language: return "Language"
        case .vizierKeywords: return "VizieR Keywords"
        case .alternateTitle: return "Alternate Title"
        case .citationCount: return "Citation Count"
        case .readCount: return "Read Count"
        case .doctype: return "Document Type"
        case .database: return "Database"
        case .bibgroup: return "Bibliographic Group"
        case .grant: return "Grant"
        case .property: return "Property"
        case .object: return "Astronomical Object"
        case .facility: return "Facility"
        }
    }

    /// Description of what the field searches
    public var description: String {
        switch self {
        case .author:
            return "Search for papers by author name. Use \"Last, First M\" format."
        case .firstAuthor:
            return "Limit to papers where the person is the first/primary author. Use ^ prefix."
        case .title:
            return "Search for words or phrases in the title field only."
        case .abstract:
            return "Search for words or phrases in the abstract only."
        case .abstractTitleKeywords:
            return "Search abstract, title, and keywords simultaneously. Broader than title or abstract alone."
        case .acknowledgements:
            return "Search the acknowledgements section of papers."
        case .fullText:
            return "Search the full text including abstract, title, keywords, and acknowledgements."
        case .body:
            return "Search the main body text of articles (requires full-text access)."
        case .bibcode:
            return "Find a specific paper using its 19-character ADS bibcode (e.g., 2019ApJ...882L..12A)."
        case .alternateBibcode:
            return "Find papers that previously had or still have this bibcode."
        case .bibstem:
            return "Search by journal abbreviation (e.g., ApJ, MNRAS, A&A)."
        case .doi:
            return "Find a paper by its Digital Object Identifier."
        case .arxivID:
            return "Find a paper by its arXiv identifier (e.g., 2301.12345 or astro-ph/0702089)."
        case .arxivClass:
            return "Find all arXiv preprints in a specific category (e.g., astro-ph.GA, hep-th)."
        case .identifier:
            return "Search using any identifier: bibcode, DOI, arXiv ID, etc."
        case .authorCount:
            return "Find papers with a specific number of authors. Use ranges like [10 TO 50]."
        case .affiliation:
            return "Search the raw affiliation field as provided by authors."
        case .affiliationID:
            return "Search by canonical affiliation ID from the ADS affiliations list."
        case .institution:
            return "Search the curated institution abbreviations (e.g., CfA, STScI, ESO)."
        case .orcid:
            return "Find papers associated with a specific ORCID iD."
        case .orcidPub:
            return "Find papers with ORCID iD specified by the publisher."
        case .orcidUser:
            return "Find papers claimed by known ADS users via ORCID."
        case .orcidOther:
            return "Find papers claimed via ORCID by users not in ADS."
        case .year:
            return "Filter by publication year. Use YYYY or YYYY-YYYY for ranges."
        case .pubdate:
            return "Filter by precise publication date. Use [YYYY-MM TO YYYY-MM] format."
        case .volume:
            return "Search for papers in a specific journal volume."
        case .issue:
            return "Search for papers in a specific journal issue."
        case .page:
            return "Search for papers starting on a specific page number."
        case .copyright:
            return "Search for papers with specific copyright holders."
        case .keyword:
            return "Search publisher or author-supplied keywords."
        case .language:
            return "Filter papers by language (e.g., english, german, french)."
        case .vizierKeywords:
            return "Search VizieR astronomical keywords."
        case .alternateTitle:
            return "Search alternate/translated titles when available."
        case .citationCount:
            return "Filter by number of citations. Use ranges like [100 TO *]."
        case .readCount:
            return "Filter by ADS read count (measure of recent interest)."
        case .doctype:
            return "Filter by document type: article, eprint, inproceedings, book, etc."
        case .database:
            return "Limit to astronomy, physics, or general collection."
        case .bibgroup:
            return "Search papers in curated bibliographies (e.g., HST, Chandra, JWST)."
        case .grant:
            return "Find papers acknowledging specific grants or funding."
        case .property:
            return "Filter by properties: refereed, eprint, openaccess, data, software, etc."
        case .object:
            return "Find papers about specific astronomical objects (uses SIMBAD/NED)."
        case .facility:
            return "Search for papers using specific telescopes or facilities."
        }
    }

    /// Example usage of the field
    public var example: String {
        switch self {
        case .author: return "author:\"Einstein, Albert\""
        case .firstAuthor: return "author:\"^Hawking, S\""
        case .title: return "title:\"dark matter\""
        case .abstract: return "abstract:gravitational"
        case .abstractTitleKeywords: return "abs:\"black hole\""
        case .acknowledgements: return "ack:NASA"
        case .fullText: return "full:\"machine learning\""
        case .body: return "body:methodology"
        case .bibcode: return "bibcode:2019ApJ...882L..12A"
        case .alternateBibcode: return "alternate_bibcode:2019arXiv190102345"
        case .bibstem: return "bibstem:ApJ"
        case .doi: return "doi:10.3847/1538-4357/ab1234"
        case .arxivID: return "arXiv:2301.12345"
        case .arxivClass: return "arxiv_class:astro-ph.GA"
        case .identifier: return "identifier:2019ApJ...882L..12A"
        case .authorCount: return "author_count:[10 TO 50]"
        case .affiliation: return "aff:\"Harvard\""
        case .affiliationID: return "aff_id:A12345"
        case .institution: return "inst:CfA"
        case .orcid: return "orcid:0000-0001-2345-6789"
        case .orcidPub: return "orcid_pub:0000-0001-2345-6789"
        case .orcidUser: return "orcid_user:0000-0001-2345-6789"
        case .orcidOther: return "orcid_other:0000-0001-2345-6789"
        case .year: return "year:2020-2024"
        case .pubdate: return "pubdate:[2023-01 TO 2024-06]"
        case .volume: return "volume:882"
        case .issue: return "issue:12"
        case .page: return "page:456"
        case .copyright: return "copyright:AAS"
        case .keyword: return "keyword:\"gravitational waves\""
        case .language: return "lang:english"
        case .vizierKeywords: return "vizier:photometry"
        case .alternateTitle: return "alternate_title:relativité"
        case .citationCount: return "citation_count:[100 TO *]"
        case .readCount: return "read_count:[50 TO *]"
        case .doctype: return "doctype:article"
        case .database: return "database:astronomy"
        case .bibgroup: return "bibgroup:HST"
        case .grant: return "grant:\"NASA NNX\""
        case .property: return "property:refereed"
        case .object: return "object:\"M31\""
        case .facility: return "facility:HST"
        }
    }

    /// Category grouping for menu organization
    public var category: ADSSearchFieldCategory {
        switch self {
        case .author, .firstAuthor, .title, .abstract, .abstractTitleKeywords, .acknowledgements, .fullText, .body:
            return .bibliographic
        case .bibcode, .alternateBibcode, .bibstem, .doi, .arxivID, .arxivClass, .identifier:
            return .identifiers
        case .authorCount, .affiliation, .affiliationID, .institution, .orcid, .orcidPub, .orcidUser, .orcidOther:
            return .authorAffiliation
        case .year, .pubdate, .volume, .issue, .page, .copyright:
            return .datePublication
        case .keyword, .language, .vizierKeywords, .alternateTitle:
            return .contentMetadata
        case .citationCount, .readCount:
            return .metrics
        case .doctype, .database, .bibgroup, .grant, .property:
            return .classification
        case .object, .facility:
            return .specialized
        }
    }
}

/// Categories for grouping search fields in the menu
public enum ADSSearchFieldCategory: String, CaseIterable {
    case bibliographic = "Bibliographic"
    case identifiers = "Identifiers"
    case authorAffiliation = "Author & Affiliation"
    case datePublication = "Date & Publication"
    case contentMetadata = "Content & Metadata"
    case metrics = "Metrics"
    case classification = "Classification"
    case specialized = "Specialized"

    public var fields: [ADSSearchField] {
        ADSSearchField.allCases.filter { $0.category == self }
    }

    public var icon: String {
        switch self {
        case .bibliographic: return "doc.text"
        case .identifiers: return "number"
        case .authorAffiliation: return "person.2"
        case .datePublication: return "calendar"
        case .contentMetadata: return "tag"
        case .metrics: return "chart.bar"
        case .classification: return "folder"
        case .specialized: return "star"
        }
    }
}

#if os(macOS)

// MARK: - ADS Search Field Picker

/// A dropdown menu for selecting ADS search fields with descriptions
public struct ADSSearchFieldPicker: View {
    @Binding var queryText: String
    @State private var selectedField: ADSSearchField?
    @State private var showingFieldInfo = false

    public init(queryText: Binding<String>) {
        self._queryText = queryText
    }

    public var body: some View {
        Menu {
            ForEach(ADSSearchFieldCategory.allCases, id: \.self) { category in
                Section(category.rawValue) {
                    ForEach(category.fields) { field in
                        Button {
                            selectedField = field
                            showingFieldInfo = true
                        } label: {
                            Label(field.displayName, systemImage: category.icon)
                        }
                    }
                }
            }
        } label: {
            Label("All Search Terms", systemImage: "list.bullet.rectangle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .popover(isPresented: $showingFieldInfo, arrowEdge: .bottom) {
            if let field = selectedField {
                ADSSearchFieldInfoView(
                    field: field,
                    onInsert: { syntax in
                        insertFieldSyntax(syntax)
                        showingFieldInfo = false
                    },
                    onDismiss: {
                        showingFieldInfo = false
                    }
                )
            }
        }
    }

    private func insertFieldSyntax(_ syntax: String) {
        if queryText.isEmpty {
            queryText = syntax
        } else if queryText.hasSuffix(" ") {
            queryText += syntax
        } else {
            queryText += " " + syntax
        }
    }
}

/// Popover view showing field information and allowing insertion
struct ADSSearchFieldInfoView: View {
    let field: ADSSearchField
    let onInsert: (String) -> Void
    let onDismiss: () -> Void

    @State private var valueText: String = ""
    @FocusState private var isValueFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label(field.displayName, systemImage: field.category.icon)
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Description
            Text(field.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Syntax
            VStack(alignment: .leading, spacing: 4) {
                Text("Syntax")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(field.syntax)
                    .font(.system(.body, design: .monospaced))
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Example
            VStack(alignment: .leading, spacing: 4) {
                Text("Example")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(field.example)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.blue)
                    .padding(6)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Divider()

            // Value input
            VStack(alignment: .leading, spacing: 4) {
                Text("Enter value:")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                HStack {
                    TextField(placeholderText, text: $valueText)
                        .textFieldStyle(.roundedBorder)
                        .focused($isValueFocused)
                        .onSubmit {
                            insertWithValue()
                        }
                    Button("Insert") {
                        insertWithValue()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(valueText.isEmpty)
                }
            }

            // Quick insert (syntax only)
            Button {
                onInsert(field.syntax)
            } label: {
                Label("Insert syntax only", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            isValueFocused = true
        }
    }

    private var placeholderText: String {
        switch field {
        case .author, .firstAuthor: return "Last, First M"
        case .year: return "2024 or 2020-2024"
        case .pubdate: return "[2023-01 TO 2024-06]"
        case .citationCount, .readCount, .authorCount: return "[min TO max]"
        case .orcid, .orcidPub, .orcidUser, .orcidOther: return "0000-0001-2345-6789"
        case .bibcode: return "2019ApJ...882L..12A"
        case .doi: return "10.3847/..."
        case .arxivID: return "2301.12345"
        default: return "search value"
        }
    }

    private func insertWithValue() {
        let trimmed = valueText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let needsQuotes = trimmed.contains(" ") && !trimmed.hasPrefix("\"") && !trimmed.hasPrefix("[")
        let formattedValue = needsQuotes ? "\"\(trimmed)\"" : trimmed

        // Special handling for first author (needs closing quote)
        if field == .firstAuthor {
            onInsert("author:\"^\(trimmed)\"")
        } else {
            onInsert("\(field.syntax)\(formattedValue)")
        }
    }
}

// MARK: - Year Picker

/// A picker for selecting a year with optional "Any" value
public struct YearPicker: View {
    let label: String
    @Binding var selection: Int?

    private let currentYear = Calendar.current.component(.year, from: Date())
    private let startYear = 1800

    public init(_ label: String, selection: Binding<Int?>) {
        self.label = label
        self._selection = selection
    }

    public var body: some View {
        Picker(label, selection: $selection) {
            Text("Any").tag(nil as Int?)
            ForEach((startYear...currentYear).reversed(), id: \.self) { year in
                Text(String(year)).tag(year as Int?)
            }
        }
        #if os(macOS)
        .pickerStyle(.menu)
        #endif
    }
}

// MARK: - ADS Classic Search View

/// Multi-field search form matching the classic ADS interface
public struct ADSClassicSearchView: View {

    // MARK: - Environment

    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(LibraryViewModel.self) private var libraryViewModel

    // MARK: - Bindings

    @Binding var selectedPublication: CDPublication?

    // MARK: - Form State

    @State private var authors: String = ""
    @State private var isAddingToInbox: Bool = false
    @State private var objects: String = ""
    @State private var titleWords: String = ""
    @State private var titleLogic: QueryLogic = .and
    @State private var abstractWords: String = ""
    @State private var abstractLogic: QueryLogic = .and
    @State private var yearFrom: Int? = nil
    @State private var yearTo: Int? = nil
    @State private var database: ADSDatabase = .all
    @State private var refereedOnly: Bool = false
    @State private var articlesOnly: Bool = false

    // MARK: - Initialization

    public init(selectedPublication: Binding<CDPublication?>) {
        self._selectedPublication = selectedPublication
    }

    // MARK: - State for Layout

    @State private var isFormExpanded: Bool = true

    // MARK: - Body

    public var body: some View {
        @Bindable var viewModel = searchViewModel

        VStack(spacing: 0) {
            // Collapsible form section
            DisclosureGroup(isExpanded: $isFormExpanded) {
                formContent
            } label: {
                HStack {
                    Label("Search Criteria", systemImage: "list.bullet.rectangle")
                        .font(.headline)
                    Spacer()
                    if !isFormEmpty {
                        Text("Fields filled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()

            Divider()

            // Results section
            resultsContent
        }
    }

    // MARK: - Form Content

    @ViewBuilder
    private var formContent: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Authors")
                        .font(.headline)
                    TextEditor(text: $authors)
                        .font(.body)
                        .frame(minHeight: 60, maxHeight: 100)
                        .border(Color.secondary.opacity(0.3), width: 1)
                    Text("One author per line (Last, First M)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Objects")
                        .font(.headline)
                    TextField("SIMBAD/NED object names", text: $objects)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title")
                        .font(.headline)
                    HStack {
                        TextField("Title words", text: $titleWords)
                            .textFieldStyle(.roundedBorder)
                        logicPicker(selection: $titleLogic)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Abstract / Keywords")
                        .font(.headline)
                    HStack {
                        TextField("Abstract words", text: $abstractWords)
                            .textFieldStyle(.roundedBorder)
                        logicPicker(selection: $abstractLogic)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Publication Date")
                        .font(.headline)
                    HStack {
                        YearPicker("From", selection: $yearFrom)
                        Text("to")
                            .foregroundStyle(.secondary)
                        YearPicker("To", selection: $yearTo)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Database")
                        .font(.headline)
                    Picker("Collection", selection: $database) {
                        ForEach(ADSDatabase.allCases, id: \.self) { db in
                            Text(db.displayName).tag(db)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Filters")
                        .font(.headline)
                    HStack(spacing: 20) {
                        Toggle("Refereed only", isOn: $refereedOnly)
                        Toggle("Articles only", isOn: $articlesOnly)
                    }
                    .toggleStyle(.checkbox)
                }
            }

            // Action buttons
            Section {
                HStack {
                    Button("Clear") {
                        clearForm()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        addToInbox()
                    } label: {
                        if isAddingToInbox {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Add to Inbox")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isFormEmpty || isAddingToInbox)

                    Button("Search") {
                        performSearch()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isFormEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Results Content

    @ViewBuilder
    private var resultsContent: some View {
        @Bindable var viewModel = searchViewModel

        if viewModel.isSearching {
            ProgressView("Searching...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.publications.isEmpty && viewModel.query.isEmpty {
            ContentUnavailableView {
                Label("ADS Classic Search", systemImage: "list.bullet.rectangle")
            } description: {
                Text("Fill in the form and click Search to find publications.")
            }
        } else if viewModel.publications.isEmpty {
            ContentUnavailableView {
                Label("No Results", systemImage: "magnifyingglass")
            } description: {
                Text("No publications found matching your criteria.")
            }
        } else {
            PublicationListView(
                publications: viewModel.publications,
                selection: $viewModel.selectedPublicationIDs,
                selectedPublication: $selectedPublication,
                library: libraryManager.activeLibrary,
                allLibraries: libraryManager.libraries,
                showImportButton: false,
                showSortMenu: true,
                emptyStateMessage: "No Results",
                emptyStateDescription: "Fill in the form and click Search.",
                listID: libraryManager.activeLibrary?.lastSearchCollection.map { .lastSearch($0.id) },
                filterScope: .constant(.current),
                onDelete: { ids in
                    await libraryViewModel.delete(ids: ids)
                },
                onToggleRead: { publication in
                    await libraryViewModel.toggleReadStatus(publication)
                },
                onCopy: { ids in
                    await libraryViewModel.copyToClipboard(ids)
                },
                onCut: { ids in
                    await libraryViewModel.cutToClipboard(ids)
                },
                onPaste: {
                    try? await libraryViewModel.pasteFromClipboard()
                },
                onAddToLibrary: { ids, targetLibrary in
                    await libraryViewModel.addToLibrary(ids, library: targetLibrary)
                },
                onAddToCollection: { ids, collection in
                    await libraryViewModel.addToCollection(ids, collection: collection)
                },
                onRemoveFromAllCollections: { ids in
                    await libraryViewModel.removeFromAllCollections(ids)
                },
                onOpenPDF: { _ in }
            )
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func logicPicker(selection: Binding<QueryLogic>) -> some View {
        Picker("", selection: selection) {
            Text("AND").tag(QueryLogic.and)
            Text("OR").tag(QueryLogic.or)
        }
        .pickerStyle(.segmented)
        .frame(width: 100)
    }

    // MARK: - Computed Properties

    private var isFormEmpty: Bool {
        SearchFormQueryBuilder.isClassicFormEmpty(
            authors: authors,
            objects: objects,
            titleWords: titleWords,
            abstractWords: abstractWords,
            yearFrom: yearFrom,
            yearTo: yearTo
        )
    }

    // MARK: - Actions

    private func performSearch() {
        let query = SearchFormQueryBuilder.buildClassicQuery(
            authors: authors,
            objects: objects,
            titleWords: titleWords,
            titleLogic: titleLogic,
            abstractWords: abstractWords,
            abstractLogic: abstractLogic,
            yearFrom: yearFrom,
            yearTo: yearTo,
            database: database,
            refereedOnly: refereedOnly,
            articlesOnly: articlesOnly
        )

        searchViewModel.query = query
        searchViewModel.selectedSourceIDs = Set(database.sourceIDs)

        Task {
            await searchViewModel.search()
        }
    }

    private func addToInbox() {
        let query = SearchFormQueryBuilder.buildClassicQuery(
            authors: authors,
            objects: objects,
            titleWords: titleWords,
            titleLogic: titleLogic,
            abstractWords: abstractWords,
            abstractLogic: abstractLogic,
            yearFrom: yearFrom,
            yearTo: yearTo,
            database: database,
            refereedOnly: refereedOnly,
            articlesOnly: articlesOnly
        )

        // Generate a descriptive feed name
        let feedName = generateFeedName()

        isAddingToInbox = true

        Task {
            guard let library = libraryManager.activeLibrary else {
                Logger.viewModels.errorCapture("No active library for ADS feed", category: "feed")
                isAddingToInbox = false
                return
            }

            let context = PersistenceController.shared.viewContext

            // Create SmartSearch (feed definition)
            let smartSearch = CDSmartSearch(context: context)
            smartSearch.id = UUID()
            smartSearch.name = feedName
            smartSearch.query = query
            smartSearch.sources = database.sourceIDs
            smartSearch.dateCreated = Date()
            smartSearch.dateLastExecuted = nil
            smartSearch.library = library
            smartSearch.maxResults = 500

            // KEY: These flags make it an Inbox feed
            smartSearch.feedsToInbox = true
            smartSearch.autoRefreshEnabled = true
            smartSearch.refreshIntervalSeconds = 3600  // 1 hour

            // Set order based on existing searches
            let existingCount = library.smartSearches?.count ?? 0
            smartSearch.order = Int16(existingCount)

            // Create associated result collection
            let collection = CDCollection(context: context)
            collection.id = UUID()
            collection.name = feedName
            collection.isSmartSearchResults = true
            collection.isSmartCollection = false
            collection.smartSearch = smartSearch
            collection.library = library
            smartSearch.resultCollection = collection

            PersistenceController.shared.save()

            Logger.viewModels.infoCapture("Created ADS inbox feed: '\(feedName)'", category: "feed")

            // Execute initial fetch through proper pipeline
            await executeInitialFetch(smartSearch)

            isAddingToInbox = false
        }
    }

    /// Generate a descriptive feed name from form fields
    private func generateFeedName() -> String {
        var parts: [String] = []
        if !authors.isEmpty {
            let firstAuthor = authors.split(separator: "\n").first.map(String.init) ?? authors
            parts.append(firstAuthor)
        }
        if !objects.isEmpty { parts.append(objects) }
        if !titleWords.isEmpty { parts.append("\"\(titleWords)\"") }

        let baseName = parts.isEmpty ? "ADS Search" : parts.joined(separator: " ")
        return "\(database.displayName): \(baseName)"
    }

    /// Execute initial feed fetch
    private func executeInitialFetch(_ smartSearch: CDSmartSearch) async {
        guard let fetchService = await InboxCoordinator.shared.paperFetchService else {
            Logger.viewModels.warningCapture(
                "InboxCoordinator not started, skipping initial feed fetch",
                category: "feed"
            )
            return
        }

        do {
            let fetchedCount = try await fetchService.fetchForInbox(smartSearch: smartSearch)
            Logger.viewModels.infoCapture(
                "Initial ADS feed fetch complete: \(fetchedCount) papers added to Inbox",
                category: "feed"
            )
        } catch {
            Logger.viewModels.errorCapture(
                "Initial ADS feed fetch failed: \(error.localizedDescription)",
                category: "feed"
            )
        }
    }

    private func clearForm() {
        authors = ""
        objects = ""
        titleWords = ""
        titleLogic = .and
        abstractWords = ""
        abstractLogic = .and
        yearFrom = nil
        yearTo = nil
        database = .all
        refereedOnly = false
        articlesOnly = false
    }
}

// MARK: - ADS Classic Search Form View (Detail Pane)

/// Form-only view for the detail pane (right side)
/// Results are shown in the middle pane via SearchResultsListView
public struct ADSClassicSearchFormView: View {

    // MARK: - Environment

    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - Local State (not persisted)

    @State private var isAddingToInbox: Bool = false

    // MARK: - Initialization

    public init() {}

    // MARK: - Body

    public var body: some View {
        @Bindable var viewModel = searchViewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Label("ADS Search", systemImage: "magnifyingglass")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Build queries using search terms or classic form fields")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                // Modern Query Builder
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Query")
                            .font(.headline)
                        Spacer()
                        ADSSearchFieldPicker(queryText: $viewModel.classicFormState.rawQuery)
                    }

                    TextEditor(text: $viewModel.classicFormState.rawQuery)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60, maxHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )

                    Text("Use \"All Search Terms\" to build queries, or type ADS syntax directly")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .padding(.vertical, 4)

                // Classic form fields header
                Text("Classic Form Fields")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                // Authors
                VStack(alignment: .leading, spacing: 4) {
                    Text("Authors")
                        .font(.headline)
                    TextEditor(text: $viewModel.classicFormState.authors)
                        .font(.body)
                        .frame(minHeight: 60, maxHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    Text("One author per line (Last, First M)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Objects
                VStack(alignment: .leading, spacing: 4) {
                    Text("Objects")
                        .font(.headline)
                    TextField("SIMBAD/NED object names", text: $viewModel.classicFormState.objects)
                        .textFieldStyle(.roundedBorder)
                }

                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title")
                        .font(.headline)
                    HStack {
                        TextField("Title words", text: $viewModel.classicFormState.titleWords)
                            .textFieldStyle(.roundedBorder)
                        logicPicker(selection: $viewModel.classicFormState.titleLogic)
                    }
                }

                // Abstract
                VStack(alignment: .leading, spacing: 4) {
                    Text("Abstract / Keywords")
                        .font(.headline)
                    HStack {
                        TextField("Abstract words", text: $viewModel.classicFormState.abstractWords)
                            .textFieldStyle(.roundedBorder)
                        logicPicker(selection: $viewModel.classicFormState.abstractLogic)
                    }
                }

                // Publication Date
                VStack(alignment: .leading, spacing: 4) {
                    Text("Publication Date")
                        .font(.headline)
                    HStack {
                        YearPicker("From", selection: $viewModel.classicFormState.yearFrom)
                        Text("to")
                            .foregroundStyle(.secondary)
                        YearPicker("To", selection: $viewModel.classicFormState.yearTo)
                    }
                }

                // Database
                VStack(alignment: .leading, spacing: 4) {
                    Text("Database")
                        .font(.headline)
                    Picker("Collection", selection: $viewModel.classicFormState.database) {
                        ForEach(ADSDatabase.allCases, id: \.self) { db in
                            Text(db.displayName).tag(db)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Filters
                VStack(alignment: .leading, spacing: 8) {
                    Text("Filters")
                        .font(.headline)
                    HStack(spacing: 20) {
                        Toggle("Refereed only", isOn: $viewModel.classicFormState.refereedOnly)
                        Toggle("Articles only", isOn: $viewModel.classicFormState.articlesOnly)
                    }
                    .toggleStyle(.checkbox)
                }

                Divider()
                    .padding(.vertical, 8)

                // Edit mode header
                if searchViewModel.isEditMode, let smartSearch = searchViewModel.editingSmartSearch {
                    HStack {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Editing: \(smartSearch.name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") {
                            searchViewModel.exitEditMode()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Action buttons
                HStack {
                    Button("Clear") {
                        clearForm()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if searchViewModel.isEditMode {
                        // Edit mode: Save button
                        Button("Save") {
                            searchViewModel.saveToSmartSearch()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isFormEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                    } else {
                        // Normal mode: Add to Inbox and Search buttons
                        Button {
                            addToInbox()
                        } label: {
                            if isAddingToInbox {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Add to Inbox")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isFormEmpty || isAddingToInbox)

                        Button("Search") {
                            performSearch()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isFormEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .task {
            // Ensure SearchViewModel has access to LibraryManager
            searchViewModel.setLibraryManager(libraryManager)
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func logicPicker(selection: Binding<QueryLogic>) -> some View {
        Picker("", selection: selection) {
            Text("AND").tag(QueryLogic.and)
            Text("OR").tag(QueryLogic.or)
        }
        .pickerStyle(.segmented)
        .frame(width: 100)
    }

    // MARK: - Computed Properties

    private var isFormEmpty: Bool {
        searchViewModel.classicFormState.isEmpty
    }

    // MARK: - Actions

    private func performSearch() {
        let state = searchViewModel.classicFormState
        let classicQuery = SearchFormQueryBuilder.buildClassicQuery(
            authors: state.authors,
            objects: state.objects,
            titleWords: state.titleWords,
            titleLogic: state.titleLogic,
            abstractWords: state.abstractWords,
            abstractLogic: state.abstractLogic,
            yearFrom: state.yearFrom,
            yearTo: state.yearTo,
            database: state.database,
            refereedOnly: state.refereedOnly,
            articlesOnly: state.articlesOnly
        )

        // Combine raw query (from "All Search Terms") with classic form query
        let rawQuery = state.rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let combinedQuery: String
        if !rawQuery.isEmpty && !classicQuery.isEmpty {
            combinedQuery = "\(rawQuery) \(classicQuery)"
        } else if !rawQuery.isEmpty {
            combinedQuery = rawQuery
        } else {
            combinedQuery = classicQuery
        }

        searchViewModel.query = combinedQuery
        searchViewModel.selectedSourceIDs = Set(state.database.sourceIDs)

        Task {
            await searchViewModel.search()
        }
    }

    private func addToInbox() {
        let state = searchViewModel.classicFormState
        let classicQuery = SearchFormQueryBuilder.buildClassicQuery(
            authors: state.authors,
            objects: state.objects,
            titleWords: state.titleWords,
            titleLogic: state.titleLogic,
            abstractWords: state.abstractWords,
            abstractLogic: state.abstractLogic,
            yearFrom: state.yearFrom,
            yearTo: state.yearTo,
            database: state.database,
            refereedOnly: state.refereedOnly,
            articlesOnly: state.articlesOnly
        )

        // Combine raw query (from "All Search Terms") with classic form query
        let rawQuery = state.rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let combinedQuery: String
        if !rawQuery.isEmpty && !classicQuery.isEmpty {
            combinedQuery = "\(rawQuery) \(classicQuery)"
        } else if !rawQuery.isEmpty {
            combinedQuery = rawQuery
        } else {
            combinedQuery = classicQuery
        }

        // Generate a descriptive feed name
        let feedName = generateFeedName()

        isAddingToInbox = true

        Task {
            guard let library = libraryManager.activeLibrary else {
                Logger.viewModels.errorCapture("No active library for ADS feed", category: "feed")
                isAddingToInbox = false
                return
            }

            let context = PersistenceController.shared.viewContext

            // Create SmartSearch (feed definition)
            let smartSearch = CDSmartSearch(context: context)
            smartSearch.id = UUID()
            smartSearch.name = feedName
            smartSearch.query = combinedQuery
            smartSearch.sources = state.database.sourceIDs
            smartSearch.dateCreated = Date()
            smartSearch.dateLastExecuted = nil
            smartSearch.library = library
            smartSearch.maxResults = 500

            // KEY: These flags make it an Inbox feed
            smartSearch.feedsToInbox = true
            smartSearch.autoRefreshEnabled = true
            smartSearch.refreshIntervalSeconds = 3600  // 1 hour

            // Set order based on existing searches
            let existingCount = library.smartSearches?.count ?? 0
            smartSearch.order = Int16(existingCount)

            // Create associated result collection
            let collection = CDCollection(context: context)
            collection.id = UUID()
            collection.name = feedName
            collection.isSmartSearchResults = true
            collection.isSmartCollection = false
            collection.smartSearch = smartSearch
            collection.library = library
            smartSearch.resultCollection = collection

            PersistenceController.shared.save()

            Logger.viewModels.infoCapture("Created ADS inbox feed: '\(feedName)'", category: "feed")

            // Execute initial fetch through proper pipeline
            await executeInitialFetch(smartSearch)

            isAddingToInbox = false
        }
    }

    /// Generate a descriptive feed name from form fields
    private func generateFeedName() -> String {
        let state = searchViewModel.classicFormState
        var parts: [String] = []

        // Include truncated rawQuery if present
        let rawQuery = state.rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawQuery.isEmpty {
            let truncated = String(rawQuery.prefix(30)) + (rawQuery.count > 30 ? "..." : "")
            parts.append(truncated)
        }

        // Include classic form fields
        if !state.authors.isEmpty {
            let firstAuthor = state.authors.split(separator: "\n").first.map(String.init) ?? state.authors
            parts.append(firstAuthor)
        }
        if !state.objects.isEmpty { parts.append(state.objects) }
        if !state.titleWords.isEmpty { parts.append("\"\(state.titleWords)\"") }

        let baseName = parts.isEmpty ? "ADS Search" : parts.joined(separator: " ")
        return "\(state.database.displayName): \(baseName)"
    }

    /// Execute initial feed fetch
    private func executeInitialFetch(_ smartSearch: CDSmartSearch) async {
        guard let fetchService = await InboxCoordinator.shared.paperFetchService else {
            Logger.viewModels.warningCapture(
                "InboxCoordinator not started, skipping initial feed fetch",
                category: "feed"
            )
            return
        }

        do {
            let fetchedCount = try await fetchService.fetchForInbox(smartSearch: smartSearch)
            Logger.viewModels.infoCapture(
                "Initial ADS feed fetch complete: \(fetchedCount) papers added to Inbox",
                category: "feed"
            )
        } catch {
            Logger.viewModels.errorCapture(
                "Initial ADS feed fetch failed: \(error.localizedDescription)",
                category: "feed"
            )
        }
    }

    private func clearForm() {
        searchViewModel.classicFormState.clear()
    }
}

#endif  // os(macOS)
