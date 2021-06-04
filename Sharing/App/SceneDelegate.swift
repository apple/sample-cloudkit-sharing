//
//  SceneDelegate.swift
//  (cloudkit-samples) Sharing
//

import UIKit
import SwiftUI
import CloudKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        let contentView = ContentView().environmentObject(ViewModel())

        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = UIHostingController(rootView: contentView)
            self.window = window
            window.makeKeyAndVisible()
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        guard cloudKitShareMetadata.containerIdentifier == Config.containerIdentifier else {
            print("Shared container identifier \(cloudKitShareMetadata.containerIdentifier) did not match known identifier.")
            return
        }

        // Create an operation to accept the share, running in the app's CKContainer.
        let container = CKContainer(identifier: Config.containerIdentifier)
        let operation = CKAcceptSharesOperation(shareMetadatas: [cloudKitShareMetadata])

        debugPrint("Accepting CloudKit Share with metadata: \(cloudKitShareMetadata)")

        operation.perShareCompletionBlock = { metadata, share, error in
            let rootRecordID = metadata.rootRecordID

            if let error = error {
                debugPrint("Error accepting share with root record ID: \(rootRecordID), \(error)")
            } else {
                debugPrint("Accepted CloudKit share for root record ID: \(rootRecordID)")
            }
        }

        operation.acceptSharesCompletionBlock = { error in
            if let error = error {
                debugPrint("Error accepting CloudKit Share: \(error)")
            }
        }

        operation.qualityOfService = .utility
        container.add(operation)
    }
}
