//
//  GroupArXivFeedFormView.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-15.
//

import SwiftUI
import CoreData
import OSLog

#if os(macOS)

// MARK: - Group arXiv Feed Form View

/// Form for creating group arXiv feeds that monitor multiple authors.
///
/// This form allows users to specify multiple author names (comma or newline separated)
/// and selected arXiv categories. Searches for each author are staggered 20 seconds apart
/// to avoid rate limiting.
public struct GroupArXivFeedFormView: View {

    // MARK: - Environment

    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - Local State

    @State private var feedName: String = ""
    @State private var authorsText: String = ""
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
                        isEditMode ? "Edit Group Feed" : "Create Group arXiv Feed",
                        systemImage: "person.3.fill"
                    )
                    .font(.title2)
                    .fontWeight(.semibold)
                    Text("Monitor multiple authors in selected arXiv categories")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                // Feed Name Section
                feedNameSection

                // Authors Section
                authorsSection

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
                        .disabled(!isFormValid)
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
                        .disabled(!isFormValid || isCreating)
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
        .onReceive(NotificationCenter.default.publisher(for: .editGroupArXivFeed)) { notification in
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

            TextField("Friends", text: $feedName)
                .textFieldStyle(.roundedBorder)

            Text("Leave blank to use \"Friends\" as the default name")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Authors Section

    @ViewBuilder
    private var authorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Authors")
                .font(.headline)

            TextEditor(text: $authorsText)
                .font(.body)
                .frame(minHeight: 100, maxHeight: 150)
                .border(Color.gray.opacity(0.3), width: 1)
                .cornerRadius(4)

            Text("Enter author names separated by commas or one per line")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !parsedAuthors.isEmpty {
                HStack {
                    Text("\(parsedAuthors.count) authors:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(parsedAuthors.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    // MARK: - Categories Section

    @ViewBuilder
    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Subject Categories")
                    .font(.headline)
                Text("(required)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

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

    /// Parse authors from the text input (comma or newline separated)
    private var parsedAuthors: [String] {
        authorsText
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var effectiveFeedName: String {
        let trimmed = feedName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Friends" : trimmed
    }

    private var isFormValid: Bool {
        !parsedAuthors.isEmpty && !selectedCategories.isEmpty
    }

    // MARK: - Actions

    private func createFeed() {
        guard isFormValid else { return }

        isCreating = true
        showError = false

        Task {
            do {
                // Build the group feed query string
                let query = buildGroupFeedQuery()

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
                smartSearch.dateLastExecuted = nil
                smartSearch.library = library
                smartSearch.maxResults = 500
                smartSearch.feedsToInbox = true
                smartSearch.autoRefreshEnabled = true
                smartSearch.refreshIntervalSeconds = 86400  // 24 hours (daily refresh)
                smartSearch.isGroupFeed = true  // Mark as group feed

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
                    "Created group arXiv feed '\(smartSearch.name)' with \(parsedAuthors.count) authors and \(selectedCategories.count) categories",
                    category: "feed"
                )

                // Execute initial fetch (will use staggered searches)
                await executeInitialFetch(smartSearch)

                // Notify sidebar to refresh
                await MainActor.run {
                    NotificationCenter.default.post(name: .explorationLibraryDidChange, object: nil)
                    NotificationCenter.default.post(name: .navigateToSmartSearch, object: smartSearch.id)
                }

                // Clear the form
                clearForm()

            } catch {
                Logger.viewModels.errorCapture("Failed to create group feed: \(error.localizedDescription)", category: "feed")
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
        // Use GroupFeedRefreshService for staggered searches
        do {
            let fetchedCount = try await GroupFeedRefreshService.shared.refreshGroupFeed(smartSearch)
            Logger.viewModels.infoCapture(
                "Initial group feed fetch complete: \(fetchedCount) papers added to Inbox",
                category: "feed"
            )
        } catch {
            Logger.viewModels.errorCapture(
                "Initial group feed fetch failed: \(error.localizedDescription)",
                category: "feed"
            )
        }
    }

    private func saveToFeed() {
        guard let feed = editingFeed else { return }
        guard isFormValid else { return }

        // Build the group feed query
        let query = buildGroupFeedQuery()

        // Update the feed
        feed.name = effectiveFeedName
        feed.query = query
        feed.isGroupFeed = true

        // Update the result collection name too
        feed.resultCollection?.name = effectiveFeedName

        // Save
        do {
            try PersistenceController.shared.viewContext.save()
            Logger.viewModels.infoCapture("Updated group arXiv feed '\(feed.name)'", category: "feed")

            // Notify sidebar
            NotificationCenter.default.post(name: .explorationLibraryDidChange, object: nil)

            // Exit edit mode
            exitEditMode()
        } catch {
            Logger.viewModels.errorCapture("Failed to save group feed: \(error.localizedDescription)", category: "feed")
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func loadFeedForEditing(_ feed: CDSmartSearch) {
        editingFeed = feed
        feedName = feed.name

        // Parse the query to extract authors and categories
        let (authors, categories) = parseGroupFeedQuery(feed.query)
        authorsText = authors.joined(separator: "\n")
        selectedCategories = categories

        // Default include cross-listed to true
        includeCrossListed = !feed.query.contains("crosslist:false")

        Logger.viewModels.infoCapture(
            "Loaded group feed '\(feed.name)' for editing with \(authors.count) authors and \(categories.count) categories",
            category: "feed"
        )
    }

    /// Build the query string for a group feed
    private func buildGroupFeedQuery() -> String {
        // Format: GROUP_FEED|authors:Author1,Author2,Author3|categories:cat1,cat2|crosslist:true
        let authorsString = parsedAuthors.joined(separator: ",")
        let categoriesString = selectedCategories.sorted().joined(separator: ",")
        let crosslistString = includeCrossListed ? "true" : "false"
        return "GROUP_FEED|authors:\(authorsString)|categories:\(categoriesString)|crosslist:\(crosslistString)"
    }

    /// Parse a group feed query string to extract authors and categories
    private func parseGroupFeedQuery(_ query: String) -> ([String], Set<String>) {
        var authors: [String] = []
        var categories: Set<String> = []

        guard query.hasPrefix("GROUP_FEED|") else {
            return (authors, categories)
        }

        let parts = query.dropFirst("GROUP_FEED|".count).components(separatedBy: "|")
        for part in parts {
            if part.hasPrefix("authors:") {
                let authorsString = String(part.dropFirst("authors:".count))
                authors = authorsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } else if part.hasPrefix("categories:") {
                let categoriesString = String(part.dropFirst("categories:".count))
                categories = Set(categoriesString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            }
        }

        return (authors, categories)
    }

    private func exitEditMode() {
        editingFeed = nil
        clearForm()
    }

    private func clearForm() {
        feedName = ""
        authorsText = ""
        selectedCategories = []
        includeCrossListed = true
        showError = false
        errorMessage = ""
    }
}

// MARK: - Notifications

public extension Notification.Name {
    /// Posted when a group feed should be edited (object is CDSmartSearch)
    static let editGroupArXivFeed = Notification.Name("editGroupArXivFeed")
}

#endif  // os(macOS)
