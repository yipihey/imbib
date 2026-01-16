//
//  ArXivFeedFormView.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-15.
//

import SwiftUI
import CoreData
import OSLog

#if os(macOS)

// MARK: - arXiv Feed Form View

/// Simplified form for creating arXiv category feeds.
///
/// This is the preferred way to create feeds that automatically populate the Inbox
/// with new papers from selected arXiv categories.
public struct ArXivFeedFormView: View {

    // MARK: - Environment

    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - Local State

    @State private var feedName: String = ""
    @State private var selectedCategories: Set<String> = []
    @State private var includeCrossListed: Bool = true
    @State private var expandedGroups: Set<String> = []
    @State private var isCreating: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    // MARK: - Edit Mode State

    @State private var editingFeed: CDSmartSearch?

    var isEditMode: Bool {
        editingFeed != nil
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Body

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        isEditMode ? "Edit arXiv Feed" : "Create arXiv Feed",
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                    .font(.title2)
                    .fontWeight(.semibold)
                    Text("Subscribe to categories for automatic Inbox updates")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                // Feed Name Section
                feedNameSection

                // Categories Section
                categoriesSection

                // Cross-listing toggle
                Toggle("Include cross-listed papers", isOn: $includeCrossListed)
                    .toggleStyle(.checkbox)
                    .font(.subheadline)

                Divider()
                    .padding(.vertical, 8)

                // Edit mode header
                if let feed = editingFeed {
                    HStack {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Editing: \(feed.name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") {
                            exitEditMode()
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
                    Button("Clear All") {
                        clearForm()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if isEditMode {
                        Button("Save") {
                            saveToFeed()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedCategories.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                    } else {
                        Button {
                            createFeed()
                        } label: {
                            if isCreating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Create Feed")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedCategories.isEmpty || isCreating)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }

                // Error message
                if showError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .editArXivFeed)) { notification in
            if let feed = notification.object as? CDSmartSearch {
                loadFeedForEditing(feed)
            }
        }
    }

    // MARK: - Feed Name Section

    @ViewBuilder
    private var feedNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Feed Name")
                .font(.headline)

            TextField("Auto-generated from categories", text: $feedName)
                .textFieldStyle(.roundedBorder)

            Text("Leave blank to auto-generate from selected categories")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Categories Section

    @ViewBuilder
    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subject Categories")
                .font(.headline)

            ArXivCategoryPickerView(
                selectedCategories: $selectedCategories,
                expandedGroups: $expandedGroups
            )

            if !selectedCategories.isEmpty {
                HStack {
                    Text("\(selectedCategories.count) selected:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(selectedCategories.sorted().joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var autoGeneratedName: String {
        if selectedCategories.isEmpty {
            return ""
        }
        return selectedCategories.sorted().joined(separator: ", ")
    }

    private var effectiveFeedName: String {
        let trimmed = feedName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? autoGeneratedName : trimmed
    }

    // MARK: - Actions

    private func createFeed() {
        guard !selectedCategories.isEmpty else { return }

        isCreating = true
        showError = false

        Task {
            do {
                // Build the query from categories
                let query = SearchFormQueryBuilder.buildArXivAdvancedQuery(
                    searchTerms: [],  // No search terms for feed
                    categories: selectedCategories,
                    includeCrossListed: includeCrossListed,
                    dateFilter: .allDates,
                    sortBy: .submittedDateDesc
                )

                // Get the active library (or exploration library as fallback)
                guard let library = libraryManager.activeLibrary ?? libraryManager.explorationLibrary else {
                    throw FeedCreationError.noLibrary
                }

                // Create the smart search with feed properties
                let context = PersistenceController.shared.viewContext
                let smartSearch = CDSmartSearch(context: context)
                smartSearch.id = UUID()
                smartSearch.name = effectiveFeedName
                smartSearch.query = query
                smartSearch.sources = ["arxiv"]
                smartSearch.dateCreated = Date()
                smartSearch.dateLastExecuted = nil  // Will be set after first fetch
                smartSearch.library = library
                smartSearch.maxResults = 500  // Fetch up to 500 most recent papers
                smartSearch.feedsToInbox = true
                smartSearch.autoRefreshEnabled = true
                smartSearch.refreshIntervalSeconds = 3600  // 1 hour refresh interval

                // Set order based on existing searches
                let existingCount = library.smartSearches?.count ?? 0
                smartSearch.order = Int16(existingCount)

                // Create associated result collection
                let collection = CDCollection(context: context)
                collection.id = UUID()
                collection.name = effectiveFeedName
                collection.isSmartSearchResults = true
                collection.isSmartCollection = false
                collection.smartSearch = smartSearch
                collection.library = library
                smartSearch.resultCollection = collection

                // Save to Core Data
                try context.save()

                Logger.viewModels.infoCapture(
                    "Created arXiv feed '\(smartSearch.name)' with \(selectedCategories.count) categories",
                    category: "feed"
                )

                // Execute initial fetch to populate Inbox
                await executeInitialFetch(smartSearch)

                // Notify sidebar to refresh
                await MainActor.run {
                    NotificationCenter.default.post(name: .explorationLibraryDidChange, object: nil)
                    NotificationCenter.default.post(name: .navigateToSmartSearch, object: smartSearch.id)
                }

                // Clear the form
                clearForm()

            } catch {
                Logger.viewModels.errorCapture("Failed to create feed: \(error.localizedDescription)", category: "feed")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }

            await MainActor.run {
                isCreating = false
            }
        }
    }

    private func executeInitialFetch(_ smartSearch: CDSmartSearch) async {
        // Use InboxCoordinator's PaperFetchService to execute the search and add to Inbox
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
                "Initial feed fetch complete: \(fetchedCount) papers added to Inbox",
                category: "feed"
            )
        } catch {
            Logger.viewModels.errorCapture(
                "Initial feed fetch failed: \(error.localizedDescription)",
                category: "feed"
            )
        }
    }

    private func saveToFeed() {
        guard let feed = editingFeed else { return }
        guard !selectedCategories.isEmpty else { return }

        // Build the query from categories
        let query = SearchFormQueryBuilder.buildArXivAdvancedQuery(
            searchTerms: [],
            categories: selectedCategories,
            includeCrossListed: includeCrossListed,
            dateFilter: .allDates,
            sortBy: .submittedDateDesc
        )

        // Update the feed
        feed.name = effectiveFeedName
        feed.query = query

        // Update the result collection name too
        feed.resultCollection?.name = effectiveFeedName

        // Save
        do {
            try PersistenceController.shared.viewContext.save()
            Logger.viewModels.infoCapture("Updated arXiv feed '\(feed.name)'", category: "feed")

            // Notify sidebar
            NotificationCenter.default.post(name: .explorationLibraryDidChange, object: nil)

            // Exit edit mode
            exitEditMode()
        } catch {
            Logger.viewModels.errorCapture("Failed to save feed: \(error.localizedDescription)", category: "feed")
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func loadFeedForEditing(_ feed: CDSmartSearch) {
        editingFeed = feed
        feedName = feed.name

        // Parse the query to extract categories
        selectedCategories = parseCategoriesFromQuery(feed.query)

        // Default include cross-listed to true (we don't store this separately)
        includeCrossListed = !feed.query.contains("ANDNOT cross:")

        Logger.viewModels.infoCapture(
            "Loaded feed '\(feed.name)' for editing with \(selectedCategories.count) categories",
            category: "feed"
        )
    }

    private func parseCategoriesFromQuery(_ query: String) -> Set<String> {
        var categories: Set<String> = []

        // Extract cat:xxx patterns from the query
        let pattern = #"cat:([^\s()]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: query, options: [], range: NSRange(query.startIndex..., in: query))
            for match in matches {
                if let range = Range(match.range(at: 1), in: query) {
                    categories.insert(String(query[range]))
                }
            }
        }

        return categories
    }

    private func exitEditMode() {
        editingFeed = nil
        clearForm()
    }

    private func clearForm() {
        feedName = ""
        selectedCategories = []
        includeCrossListed = true
        showError = false
        errorMessage = ""
    }
}

// MARK: - Feed Creation Error

enum FeedCreationError: LocalizedError {
    case noLibrary

    var errorDescription: String? {
        switch self {
        case .noLibrary:
            return "No library available. Please create a library first."
        }
    }
}

// MARK: - Notifications

public extension Notification.Name {
    /// Posted when a feed should be edited (object is CDSmartSearch)
    static let editArXivFeed = Notification.Name("editArXivFeed")
}

#endif  // os(macOS)
