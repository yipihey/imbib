//
//  DefaultLibrarySetEditor.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-17.
//

import SwiftUI
import OSLog

#if os(macOS)

// MARK: - Default Library Set Editor

/// Editor view for modifying the default library set configuration.
///
/// This view is used by developers/testers to:
/// 1. View the current default library set
/// 2. Modify library names, smart searches, and collections
/// 3. Export the configuration as JSON
///
/// Access methods:
/// - macOS: Settings > Advanced > hold Option > "Edit Default Library Set"
/// - macOS: Launch with `--edit-default-set` argument
/// - iOS: Settings > tap logo 5 times
public struct DefaultLibrarySetEditor: View {

    // MARK: - State

    @State private var librarySet: DefaultLibrarySet?
    @State private var libraries: [EditableLibrary] = []
    @State private var selectedLibraryIndex: Int = 0
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingExportSheet = false
    @State private var jsonPreview: String = ""
    @State private var showingCopiedToast = false

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Initialization

    public init() {}

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                editorContent
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .task {
            await loadCurrentSet()
        }
        .sheet(isPresented: $showingExportSheet) {
            exportSheet
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Default Library Set Editor")
                    .font(.headline)
                Text("Configure what new users see on first launch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Export JSON...") {
                prepareExport()
            }
            .buttonStyle(.bordered)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading current configuration...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Error")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await loadCurrentSet() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Editor Content

    private var editorContent: some View {
        HSplitView {
            // Library list (left sidebar)
            libraryList
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 300)

            // Selected library editor (right panel)
            if !libraries.isEmpty && selectedLibraryIndex < libraries.count {
                libraryEditor(for: $libraries[selectedLibraryIndex])
            } else {
                emptySelection
            }
        }
    }

    // MARK: - Library List

    private var libraryList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Libraries")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)

            List(selection: Binding(
                get: { selectedLibraryIndex },
                set: { selectedLibraryIndex = $0 }
            )) {
                ForEach(Array(libraries.enumerated()), id: \.element.id) { index, library in
                    HStack {
                        Image(systemName: library.isDefault ? "star.fill" : "folder")
                            .foregroundStyle(library.isDefault ? .yellow : .secondary)
                        Text(library.name)
                        Spacer()
                        Text("\(library.smartSearches.count) searches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(index)
                }
                .onMove(perform: moveLibraries)
                .onDelete(perform: deleteLibraries)
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Button {
                    addLibrary()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add library")

                Spacer()
            }
            .padding(8)
        }
    }

    // MARK: - Library Editor

    private func libraryEditor(for library: Binding<EditableLibrary>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Library name
                Section {
                    HStack {
                        TextField("Library Name", text: library.name)
                            .textFieldStyle(.roundedBorder)

                        Toggle("Default", isOn: library.isDefault)
                            .toggleStyle(.checkbox)
                            .onChange(of: library.wrappedValue.isDefault) { _, newValue in
                                if newValue {
                                    // Ensure only one library is default
                                    for i in libraries.indices where i != selectedLibraryIndex {
                                        libraries[i].isDefault = false
                                    }
                                }
                            }
                    }
                } header: {
                    Text("Library")
                        .font(.headline)
                }

                Divider()

                // Smart searches
                Section {
                    ForEach(library.smartSearches.indices, id: \.self) { index in
                        smartSearchRow(library.smartSearches[index], onDelete: {
                            library.wrappedValue.smartSearches.remove(at: index)
                        })
                    }

                    Button {
                        library.wrappedValue.smartSearches.append(EditableSmartSearch())
                    } label: {
                        Label("Add Smart Search", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    HStack {
                        Text("Smart Searches")
                            .font(.headline)
                        Spacer()
                        Text("\(library.smartSearches.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Collections
                Section {
                    ForEach(library.collections.indices, id: \.self) { index in
                        collectionRow(library.collections[index], onDelete: {
                            library.wrappedValue.collections.remove(at: index)
                        })
                    }

                    Button {
                        library.wrappedValue.collections.append(EditableCollection())
                    } label: {
                        Label("Add Collection", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    HStack {
                        Text("Collections")
                            .font(.headline)
                        Spacer()
                        Text("\(library.collections.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Smart Search Row

    private func smartSearchRow(_ search: Binding<EditableSmartSearch>, onDelete: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: search.name)
                    .textFieldStyle(.roundedBorder)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            TextField("Query", text: search.query)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            HStack {
                TextField("Sources (comma-separated)", text: search.sourceIDsString)
                    .textFieldStyle(.roundedBorder)
                    .help("e.g., arxiv, ads, crossref")

                Toggle("Feeds to Inbox", isOn: search.feedsToInbox)
                    .toggleStyle(.checkbox)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    // MARK: - Collection Row

    private func collectionRow(_ collection: Binding<EditableCollection>, onDelete: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)

            TextField("Collection Name", text: collection.name)
                .textFieldStyle(.roundedBorder)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(6)
    }

    // MARK: - Empty Selection

    private var emptySelection: some View {
        ContentUnavailableView {
            Label("No Library Selected", systemImage: "folder")
        } description: {
            Text("Select a library from the list or add a new one")
        }
    }

    // MARK: - Export Sheet

    private var exportSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export JSON")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    showingExportSheet = false
                }
            }
            .padding()

            Divider()

            ScrollView {
                Text(jsonPreview)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack {
                if showingCopiedToast {
                    Label("Copied!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }

                Spacer()

                Button("Copy to Clipboard") {
                    copyToClipboard()
                }
                .buttonStyle(.bordered)

                Button("Save to File...") {
                    saveToFile()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .animation(.easeInOut, value: showingCopiedToast)
        }
        .frame(width: 600, height: 500)
    }

    // MARK: - Actions

    private func loadCurrentSet() async {
        isLoading = true
        errorMessage = nil

        do {
            let set = try await MainActor.run {
                try DefaultLibrarySetManager.shared.getCurrentAsDefaultSet()
            }
            libraries = set.libraries.map { EditableLibrary(from: $0) }
            librarySet = set
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func addLibrary() {
        let newLibrary = EditableLibrary()
        newLibrary.name = "New Library"
        libraries.append(newLibrary)
        selectedLibraryIndex = libraries.count - 1
    }

    private func moveLibraries(from source: IndexSet, to destination: Int) {
        libraries.move(fromOffsets: source, toOffset: destination)
    }

    private func deleteLibraries(at offsets: IndexSet) {
        libraries.remove(atOffsets: offsets)
        if selectedLibraryIndex >= libraries.count {
            selectedLibraryIndex = max(0, libraries.count - 1)
        }
    }

    private func prepareExport() {
        let editedSet = buildDefaultLibrarySet()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(editedSet),
           let json = String(data: data, encoding: .utf8) {
            jsonPreview = json
            showingExportSheet = true
        }
    }

    private func copyToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(jsonPreview, forType: .string)
        showingCopiedToast = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showingCopiedToast = false
        }
        #endif
    }

    private func saveToFile() {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "DefaultLibrarySet.json"
        panel.message = "Export the default library set configuration"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try jsonPreview.write(to: url, atomically: true, encoding: .utf8)
                showingExportSheet = false
            } catch {
                Logger.library.errorCapture("Failed to save JSON: \(error.localizedDescription)", category: "onboarding")
            }
        }
        #endif
    }

    private func buildDefaultLibrarySet() -> DefaultLibrarySet {
        let defaultLibraries = libraries.map { editable in
            DefaultLibrary(
                name: editable.name,
                isDefault: editable.isDefault,
                smartSearches: editable.smartSearches.isEmpty ? nil : editable.smartSearches.map { ss in
                    DefaultSmartSearch(
                        name: ss.name,
                        query: ss.query,
                        sourceIDs: ss.sourceIDs.isEmpty ? nil : ss.sourceIDs,
                        feedsToInbox: ss.feedsToInbox ? true : nil,
                        autoRefreshEnabled: ss.autoRefreshEnabled ? true : nil,
                        refreshIntervalSeconds: ss.autoRefreshEnabled ? ss.refreshIntervalSeconds : nil
                    )
                },
                collections: editable.collections.isEmpty ? nil : editable.collections.map { c in
                    DefaultCollection(name: c.name)
                }
            )
        }

        return DefaultLibrarySet(version: 1, libraries: defaultLibraries)
    }
}

// MARK: - Editable Models

/// Editable wrapper for DefaultLibrary
@Observable
private class EditableLibrary: Identifiable {
    let id = UUID()
    var name: String = ""
    var isDefault: Bool = false
    var smartSearches: [EditableSmartSearch] = []
    var collections: [EditableCollection] = []

    init() {}

    init(from defaultLibrary: DefaultLibrary) {
        self.name = defaultLibrary.name
        self.isDefault = defaultLibrary.isDefault
        self.smartSearches = (defaultLibrary.smartSearches ?? []).map { EditableSmartSearch(from: $0) }
        self.collections = (defaultLibrary.collections ?? []).map { EditableCollection(from: $0) }
    }
}

/// Editable wrapper for DefaultSmartSearch
@Observable
private class EditableSmartSearch: Identifiable {
    let id = UUID()
    var name: String = "New Search"
    var query: String = ""
    var sourceIDs: [String] = []
    var feedsToInbox: Bool = false
    var autoRefreshEnabled: Bool = false
    var refreshIntervalSeconds: Int = 21600

    /// String representation of source IDs for text field binding
    var sourceIDsString: String {
        get { sourceIDs.joined(separator: ", ") }
        set { sourceIDs = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    init() {}

    init(from defaultSearch: DefaultSmartSearch) {
        self.name = defaultSearch.name
        self.query = defaultSearch.query
        self.sourceIDs = defaultSearch.sourceIDs ?? []
        self.feedsToInbox = defaultSearch.feedsToInbox ?? false
        self.autoRefreshEnabled = defaultSearch.autoRefreshEnabled ?? false
        self.refreshIntervalSeconds = defaultSearch.refreshIntervalSeconds ?? 21600
    }
}

/// Editable wrapper for DefaultCollection
@Observable
private class EditableCollection: Identifiable {
    let id = UUID()
    var name: String = "New Collection"

    init() {}

    init(from defaultCollection: DefaultCollection) {
        self.name = defaultCollection.name
    }
}

// MARK: - Preview

#Preview {
    DefaultLibrarySetEditor()
}

#else

// iOS placeholder - this editor is macOS-only for now
public struct DefaultLibrarySetEditor: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView(
            "macOS Only",
            systemImage: "desktopcomputer",
            description: Text("The Default Library Set Editor is only available on macOS.")
        )
    }
}

#endif
