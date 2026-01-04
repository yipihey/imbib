//
//  SidebarView.swift
//  imbib
//
//  Created by Claude on 2026-01-04.
//

import SwiftUI
import PublicationManagerCore

struct SidebarView: View {

    // MARK: - Properties

    @Binding var selection: SidebarSection?

    // MARK: - State

    @State private var collections: [CDCollection] = []
    @State private var tags: [CDTag] = []

    // MARK: - Body

    var body: some View {
        List(selection: $selection) {
            // Library Section
            Section("Library") {
                Label("All Publications", systemImage: "books.vertical")
                    .tag(SidebarSection.library)

                Label("Recently Added", systemImage: "clock")
                    .tag(SidebarSection.recentlyAdded)

                Label("Recently Read", systemImage: "book")
                    .tag(SidebarSection.recentlyRead)
            }

            // Search Section
            Section("Search") {
                Label("Search Sources", systemImage: "magnifyingglass")
                    .tag(SidebarSection.search)
            }

            // Collections Section
            if !collections.isEmpty {
                Section("Collections") {
                    ForEach(collections, id: \.id) { collection in
                        CollectionRow(collection: collection)
                            .tag(SidebarSection.collection(collection))
                    }
                }
            }

            // Tags Section
            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags, id: \.id) { tag in
                        TagRow(tag: tag)
                            .tag(SidebarSection.tag(tag))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("imbib")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 300)
        #endif
        .task {
            await loadCollectionsAndTags()
        }
    }

    // MARK: - Data Loading

    private func loadCollectionsAndTags() async {
        let collectionRepo = CollectionRepository()
        let tagRepo = TagRepository()

        collections = await collectionRepo.fetchAll()
        tags = await tagRepo.fetchAll()
    }
}

// MARK: - Collection Row

struct CollectionRow: View {
    let collection: CDCollection

    var body: some View {
        Label {
            Text(collection.name)
        } icon: {
            Image(systemName: collection.isSmartCollection ? "folder.badge.gearshape" : "folder")
        }
    }
}

// MARK: - Tag Row

struct TagRow: View {
    let tag: CDTag

    var body: some View {
        Label {
            HStack {
                Text(tag.name)
                Spacer()
                Text("\(tag.publications?.count ?? 0)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } icon: {
            Image(systemName: "tag")
        }
    }
}

#Preview {
    SidebarView(selection: .constant(.library))
}
