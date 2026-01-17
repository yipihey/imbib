//
//  FirstRunManager.swift
//  PublicationManagerCore
//
//  Created by Claude on 2026-01-17.
//

import Foundation
import CoreData
import OSLog

// MARK: - First Run Manager

/// Manages first-run state and provides reset functionality for testing.
///
/// Used by developers and testers to:
/// 1. Check if this is a first run (no libraries exist)
/// 2. Reset the app to first-run state (delete all data except Keychain API keys)
/// 3. Trigger the default library set import
@MainActor
public final class FirstRunManager {

    // MARK: - Shared Instance

    public static let shared = FirstRunManager()

    // MARK: - Dependencies

    private let persistenceController: PersistenceController

    // MARK: - Initialization

    public init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - First Run Detection

    /// Check if this is a first run (no libraries exist).
    ///
    /// Returns `true` if the database has no libraries, indicating either:
    /// - Fresh install
    /// - After a reset to first-run state
    public var isFirstRun: Bool {
        let context = persistenceController.viewContext
        let request = NSFetchRequest<CDLibrary>(entityName: "Library")
        request.fetchLimit = 1

        do {
            let count = try context.count(for: request)
            return count == 0
        } catch {
            Logger.library.errorCapture("Failed to check library count: \(error.localizedDescription)", category: "firstrun")
            return false
        }
    }

    // MARK: - Reset to First Run

    /// Reset the app to first-run state.
    ///
    /// This method:
    /// 1. Deletes all Core Data entities (publications, libraries, collections, etc.)
    /// 2. Clears UserDefaults (AppStateStore, ListViewStateStore, ReadingPositionStore, etc.)
    /// 3. Deletes Papers folder contents
    /// 4. Preserves Keychain API keys (intentionally kept for re-testing with same credentials)
    ///
    /// After calling this, the app will behave as if freshly installed on next launch.
    public func resetToFirstRun() async throws {
        Logger.library.warningCapture("Resetting app to first-run state", category: "firstrun")

        // 1. Delete all Core Data entities
        try await deleteAllCoreDataEntities()

        // 2. Clear all UserDefaults stores
        await clearAllUserDefaultsStores()

        // 3. Delete Papers folder contents
        deletePapersFolderContents()

        Logger.library.infoCapture("Reset to first-run state complete", category: "firstrun")
    }

    // MARK: - Core Data Deletion

    /// Delete all Core Data entities.
    private func deleteAllCoreDataEntities() async throws {
        let context = persistenceController.viewContext

        // Entity names to delete (in dependency order to avoid constraint violations)
        let entityNames = [
            "Annotation",
            "LinkedFile",
            "PublicationAuthor",
            "Publication",
            "SmartSearch",
            "Collection",
            "Library",
            "Author",
            "Tag",
            "AttachmentTag",
            "MutedItem",
            "DismissedPaper",
            "SciXPendingChange",
            "SciXLibrary",
        ]

        for entityName in entityNames {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
            fetchRequest.includesPropertyValues = false

            do {
                let objects = try context.fetch(fetchRequest)
                for object in objects {
                    context.delete(object)
                }
                Logger.library.debugCapture("Deleted \(objects.count) \(entityName) entities", category: "firstrun")
            } catch {
                Logger.library.errorCapture("Failed to delete \(entityName) entities: \(error.localizedDescription)", category: "firstrun")
                // Continue with other entities even if one fails
            }
        }

        // Save the context
        persistenceController.save()
        Logger.library.infoCapture("Deleted all Core Data entities", category: "firstrun")
    }

    // MARK: - UserDefaults Clearing

    /// Clear all UserDefaults stores used by the app.
    private func clearAllUserDefaultsStores() async {
        // Clear actor-based stores
        await AppStateStore.shared.reset()
        await ListViewStateStore.shared.clearAll()
        await ReadingPositionStore.shared.clearAll()
        await AutomationSettingsStore.shared.reset()
        await PDFSettingsStore.shared.reset()

        // Clear inbox settings (not actor-based, but follows similar pattern)
        await InboxSettingsStore.shared.reset()
        await SmartSearchSettingsStore.shared.reset()

        // Clear any remaining app-specific UserDefaults keys
        let keysToRemove = [
            "libraryLocation",
            "openPDFInExternalViewer",
            "autoGenerateCiteKeys",
            "defaultEntryType",
            "exportPreserveRawBibTeX",
        ]

        let defaults = UserDefaults.standard
        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }

        Logger.library.infoCapture("Cleared all UserDefaults stores", category: "firstrun")
    }

    // MARK: - Papers Folder Deletion

    /// Delete all files in the Papers folder.
    private func deletePapersFolderContents() {
        // Get the default Papers directory
        let fileManager = FileManager.default

        // Papers are typically stored in the app's Documents or Library folder
        // For macOS: ~/Library/Containers/com.imbib.app/Data/Documents/Papers
        // For iOS: App sandbox Documents/Papers

        #if os(macOS)
        // Check common locations
        let possiblePaths = [
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Papers"),
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("imbib/Papers"),
        ].compactMap { $0 }
        #else
        let possiblePaths = [
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Papers"),
        ].compactMap { $0 }
        #endif

        for papersURL in possiblePaths {
            guard fileManager.fileExists(atPath: papersURL.path) else {
                continue
            }

            do {
                let contents = try fileManager.contentsOfDirectory(at: papersURL, includingPropertiesForKeys: nil)
                for fileURL in contents {
                    try fileManager.removeItem(at: fileURL)
                }
                Logger.files.infoCapture("Deleted \(contents.count) files from Papers folder: \(papersURL.path)", category: "firstrun")
            } catch {
                Logger.files.errorCapture("Failed to delete Papers folder contents: \(error.localizedDescription)", category: "firstrun")
            }
        }
    }

    // MARK: - Check for Reset Flag

    /// Check if the reset-to-first-run launch argument is present.
    ///
    /// Call this early in app initialization to perform reset before any other setup.
    public static var shouldResetOnLaunch: Bool {
        #if os(macOS)
        return CommandLine.arguments.contains("--reset-to-first-run")
        #else
        return false  // iOS doesn't support launch arguments from command line
        #endif
    }

    /// Perform reset if the launch argument is present.
    ///
    /// This is called from the app's initialization to handle the --reset-to-first-run flag.
    /// After reset, the app will continue normally and load the default library set.
    public func resetIfNeeded() async {
        guard Self.shouldResetOnLaunch else { return }

        Logger.library.infoCapture("--reset-to-first-run flag detected, performing reset", category: "firstrun")

        do {
            try await resetToFirstRun()
        } catch {
            Logger.library.errorCapture("Reset to first-run failed: \(error.localizedDescription)", category: "firstrun")
        }
    }
}

// MARK: - First Run Error

public enum FirstRunError: LocalizedError {
    case resetFailed(Error)
    case coreDataDeletionFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .resetFailed(let error):
            return "Failed to reset to first-run state: \(error.localizedDescription)"
        case .coreDataDeletionFailed(let error):
            return "Failed to delete Core Data entities: \(error.localizedDescription)"
        }
    }
}
