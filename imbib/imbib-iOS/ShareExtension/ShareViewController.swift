//
//  ShareViewController.swift
//  imbib-iOS-ShareExtension
//
//  Created by Claude on 2026-01-07.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import PublicationManagerCore

/// iOS share extension view controller.
///
/// Hosts the SwiftUI ShareExtensionView and handles NSExtensionItem processing.
class ShareViewController: UIViewController {

    // MARK: - Properties

    private var sharedURL: URL?
    private var hostingController: UIHostingController<AnyView>?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        // Extract the shared URL from the extension context
        extractSharedURL { [weak self] url in
            DispatchQueue.main.async {
                if let url = url {
                    self?.showShareUI(for: url)
                } else {
                    self?.showError("No URL found in shared content")
                }
            }
        }
    }

    // MARK: - URL Extraction

    private func extractSharedURL(completion: @escaping (URL?) -> Void) {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            completion(nil)
            return
        }

        // Look for URL attachment
        let urlType = UTType.url.identifier

        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(urlType) {
                attachment.loadItem(forTypeIdentifier: urlType, options: nil) { item, error in
                    if let url = item as? URL {
                        completion(url)
                    } else if let urlData = item as? Data,
                              let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                        completion(url)
                    } else {
                        completion(nil)
                    }
                }
                return
            }
        }

        // Try plain text that might be a URL
        let textType = UTType.plainText.identifier
        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(textType) {
                attachment.loadItem(forTypeIdentifier: textType, options: nil) { item, error in
                    if let urlString = item as? String,
                       let url = URL(string: urlString) {
                        completion(url)
                    } else {
                        completion(nil)
                    }
                }
                return
            }
        }

        completion(nil)
    }

    // MARK: - UI

    private func showShareUI(for url: URL) {
        sharedURL = url

        let shareView = ShareExtensionView(
            sharedURL: url,
            onConfirm: { [weak self] item in
                self?.handleConfirm(item)
            },
            onCancel: { [weak self] in
                self?.handleCancel()
            }
        )

        let hostingController = UIHostingController(rootView: AnyView(
            NavigationStack {
                shareView
                    .navigationBarTitleDisplayMode(.inline)
            }
        ))

        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        self.hostingController = hostingController
    }

    private func showError(_ message: String) {
        let errorView = VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Error")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Close") { [weak self] in
                self?.handleCancel()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()

        let hostingController = UIHostingController(rootView: AnyView(errorView))

        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        self.hostingController = hostingController
    }

    // MARK: - Actions

    private func handleConfirm(_ item: ShareExtensionService.SharedItem) {
        // Queue the item for the main app
        switch item.type {
        case .smartSearch:
            ShareExtensionService.shared.queueSmartSearch(
                url: item.url,
                name: item.name ?? "Shared Search",
                libraryID: item.libraryID
            )
        case .paper:
            ShareExtensionService.shared.queuePaperImport(
                url: item.url,
                libraryID: item.libraryID
            )
        }

        // Complete the extension
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func handleCancel() {
        let error = NSError(
            domain: "com.imbib.ShareExtension",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "User cancelled"]
        )
        extensionContext?.cancelRequest(withError: error)
    }
}
