//
//  ArXivAdvancedSearchView.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-15.
//

import SwiftUI

#if os(macOS)

// MARK: - arXiv Advanced Search Form View

/// Form-only view for the detail pane (right side)
/// Results are shown in the middle pane via SearchResultsListView
public struct ArXivAdvancedSearchFormView: View {

    // MARK: - Environment

    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LibraryManager.self) private var libraryManager

    // MARK: - Local State (not persisted)

    @State private var isAddingToInbox: Bool = false
    @State private var expandedGroups: Set<String> = []

    // MARK: - Initialization

    public init() {}

    // MARK: - Body

    public var body: some View {
        @Bindable var viewModel = searchViewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Label("arXiv Advanced Search", systemImage: "text.magnifyingglass")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Multi-field search with category filters")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                // Search Terms Section
                searchTermsSection

                // Categories Section
                categoriesSection

                // Date Filter Section
                dateFilterSection

                // Options Section
                optionsSection

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
            searchViewModel.setLibraryManager(libraryManager)
        }
    }

    // MARK: - Search Terms Section

    @ViewBuilder
    private var searchTermsSection: some View {
        @Bindable var viewModel = searchViewModel

        VStack(alignment: .leading, spacing: 8) {
            Text("Search Terms")
                .font(.headline)

            ForEach(viewModel.arxivFormState.searchTerms.indices, id: \.self) { index in
                ArXivSearchTermRow(
                    term: $viewModel.arxivFormState.searchTerms[index],
                    isFirst: index == 0,
                    onDelete: {
                        if viewModel.arxivFormState.searchTerms.count > 1 {
                            viewModel.arxivFormState.searchTerms.remove(at: index)
                        }
                    }
                )
            }

            Button {
                viewModel.arxivFormState.searchTerms.append(ArXivSearchTerm())
            } label: {
                Label("Add another term", systemImage: "plus.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    // MARK: - Categories Section

    @ViewBuilder
    private var categoriesSection: some View {
        @Bindable var viewModel = searchViewModel

        VStack(alignment: .leading, spacing: 8) {
            Text("Subject Categories")
                .font(.headline)

            ArXivCategoryPickerView(
                selectedCategories: $viewModel.arxivFormState.selectedCategories,
                expandedGroups: $expandedGroups
            )

            Toggle("Include cross-listed papers", isOn: $viewModel.arxivFormState.includeCrossListed)
                .toggleStyle(.checkbox)
                .font(.subheadline)

            // Quick actions for categories
            HStack {
                Button("Clear All") {
                    viewModel.arxivFormState.selectedCategories.removeAll()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Date Filter Section

    @ViewBuilder
    private var dateFilterSection: some View {
        @Bindable var viewModel = searchViewModel

        VStack(alignment: .leading, spacing: 8) {
            Text("Date Filter")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                // All dates
                RadioButton(
                    isSelected: isAllDates,
                    label: "All dates"
                ) {
                    viewModel.arxivFormState.dateFilter = .allDates
                }

                // Past 12 months
                RadioButton(
                    isSelected: isPastMonths,
                    label: "Past 12 months"
                ) {
                    viewModel.arxivFormState.dateFilter = .pastMonths(12)
                }

                // Specific year
                HStack {
                    RadioButton(
                        isSelected: isSpecificYear,
                        label: "Specific year:"
                    ) {
                        viewModel.arxivFormState.dateFilter = .specificYear(Calendar.current.component(.year, from: Date()))
                    }

                    if case .specificYear(let year) = viewModel.arxivFormState.dateFilter {
                        TextField("", value: Binding(
                            get: { year },
                            set: { viewModel.arxivFormState.dateFilter = .specificYear($0) }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    }
                }

                // Date range
                HStack {
                    RadioButton(
                        isSelected: isDateRange,
                        label: "Date range:"
                    ) {
                        viewModel.arxivFormState.dateFilter = .dateRange(from: nil, to: nil)
                    }

                    if case .dateRange(let from, let to) = viewModel.arxivFormState.dateFilter {
                        DatePicker(
                            "From",
                            selection: Binding(
                                get: { from ?? Date() },
                                set: { viewModel.arxivFormState.dateFilter = .dateRange(from: $0, to: to) }
                            ),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .frame(width: 100)

                        Text("to")
                            .foregroundStyle(.secondary)

                        DatePicker(
                            "To",
                            selection: Binding(
                                get: { to ?? Date() },
                                set: { viewModel.arxivFormState.dateFilter = .dateRange(from: from, to: $0) }
                            ),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .frame(width: 100)
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Options Section

    @ViewBuilder
    private var optionsSection: some View {
        @Bindable var viewModel = searchViewModel

        VStack(alignment: .leading, spacing: 8) {
            Text("Options")
                .font(.headline)

            HStack(spacing: 20) {
                HStack {
                    Text("Sort by:")
                        .foregroundStyle(.secondary)
                    Picker("", selection: $viewModel.arxivFormState.sortBy) {
                        ForEach(ArXivSortBy.allCases, id: \.self) { sort in
                            Text(sort.displayName).tag(sort)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }

                HStack {
                    Text("Results:")
                        .foregroundStyle(.secondary)
                    Picker("", selection: $viewModel.arxivFormState.resultsPerPage) {
                        Text("25").tag(25)
                        Text("50").tag(50)
                        Text("100").tag(100)
                        Text("200").tag(200)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }
            }
        }
    }

    // MARK: - Helper Properties

    private var isFormEmpty: Bool {
        searchViewModel.arxivFormState.isEmpty
    }

    private var isAllDates: Bool {
        if case .allDates = searchViewModel.arxivFormState.dateFilter {
            return true
        }
        return false
    }

    private var isPastMonths: Bool {
        if case .pastMonths = searchViewModel.arxivFormState.dateFilter {
            return true
        }
        return false
    }

    private var isSpecificYear: Bool {
        if case .specificYear = searchViewModel.arxivFormState.dateFilter {
            return true
        }
        return false
    }

    private var isDateRange: Bool {
        if case .dateRange = searchViewModel.arxivFormState.dateFilter {
            return true
        }
        return false
    }

    // MARK: - Actions

    private func performSearch() {
        guard !isFormEmpty else { return }

        let state = searchViewModel.arxivFormState
        let query = SearchFormQueryBuilder.buildArXivAdvancedQuery(
            searchTerms: state.searchTerms,
            categories: state.selectedCategories,
            includeCrossListed: state.includeCrossListed,
            dateFilter: state.dateFilter,
            sortBy: state.sortBy
        )

        searchViewModel.query = query
        // Use arXiv source for this search
        searchViewModel.selectedSourceIDs = ["arxiv"]

        Task {
            await searchViewModel.search()
        }
    }

    private func addToInbox() {
        guard !isFormEmpty else { return }

        let state = searchViewModel.arxivFormState
        let query = SearchFormQueryBuilder.buildArXivAdvancedQuery(
            searchTerms: state.searchTerms,
            categories: state.selectedCategories,
            includeCrossListed: state.includeCrossListed,
            dateFilter: state.dateFilter,
            sortBy: state.sortBy
        )

        searchViewModel.query = query
        searchViewModel.selectedSourceIDs = ["arxiv"]

        isAddingToInbox = true

        Task {
            await searchViewModel.search()

            let inboxManager = InboxManager.shared
            for publication in searchViewModel.publications {
                inboxManager.addToInbox(publication)
            }

            isAddingToInbox = false
        }
    }

    private func clearForm() {
        searchViewModel.arxivFormState.clear()
    }
}

// MARK: - Category Picker View

struct ArXivCategoryPickerView: View {
    @Binding var selectedCategories: Set<String>
    @Binding var expandedGroups: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ArXivCategories.groups) { group in
                categoryGroupView(for: group)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func categoryGroupView(for group: ArXivCategoryGroup) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedGroups.contains(group.id) },
                set: { isExpanded in
                    if isExpanded {
                        expandedGroups.insert(group.id)
                    } else {
                        expandedGroups.remove(group.id)
                    }
                }
            )
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 4) {
                ForEach(group.categories) { category in
                    categoryToggle(for: category)
                }
            }
            .padding(.leading, 16)
            .padding(.vertical, 4)
        } label: {
            HStack {
                Text(group.name)
                    .font(.subheadline)
                let count = selectedCount(in: group)
                if count > 0 {
                    Text("(\(count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func categoryToggle(for category: ArXivCategory) -> some View {
        Toggle(isOn: Binding(
            get: { selectedCategories.contains(category.id) },
            set: { isSelected in
                if isSelected {
                    selectedCategories.insert(category.id)
                } else {
                    selectedCategories.remove(category.id)
                }
            }
        )) {
            Text(category.id)
                .font(.caption)
        }
        .toggleStyle(.checkbox)
        .help(category.name)
    }

    private func selectedCount(in group: ArXivCategoryGroup) -> Int {
        group.categories.filter { selectedCategories.contains($0.id) }.count
    }
}

// MARK: - Search Term Row

struct ArXivSearchTermRow: View {
    @Binding var term: ArXivSearchTerm
    let isFirst: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Logic operator (hidden for first term)
            if !isFirst {
                Picker("", selection: $term.logicOperator) {
                    ForEach(ArXivLogicOperator.allCases, id: \.self) { op in
                        Text(op.displayName).tag(op)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            } else {
                // Placeholder to maintain alignment
                Color.clear
                    .frame(width: 100)
            }

            // Field selector
            Picker("", selection: $term.field) {
                ForEach(ArXivSearchField.allCases, id: \.self) { field in
                    Text(field.displayName).tag(field)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            // Search term text
            TextField("Search term", text: $term.term)
                .textFieldStyle(.roundedBorder)

            // Delete button (disabled if only one term)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isFirst)
            .opacity(isFirst ? 0.3 : 1)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Radio Button

struct RadioButton: View {
    let isSelected: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? Color.accentColor : Color.secondary)
                Text(label)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

#endif  // os(macOS)
