# CloudKit Samples: Sharing

⚠️ For the new Swift 5.5 concurrency APIs, see the `swift-concurrency` branch ⚠️

### Goals

This project demonstrates sharing CloudKit records across user accounts. It shows how to initiate a share from one user account, and accept the share and subsequently view shared data on another account.

### Prerequisites

* A Mac with [Xcode 12](https://developer.apple.com/xcode/) (or later) installed is required to build and test this project.
* An active [Apple Developer Program membership](https://developer.apple.com/support/compare-memberships/) is needed to create a CloudKit container.

### Setup Instructions

* Ensure the simulator or device you run the project on is signed in to an Apple ID account with iCloud enabled. This can be done in the Settings app.
* If you wish to run the app on a device, ensure the correct developer team is selected in the “Signing & Capabilities” tab of the Sharing app target, and a valid iCloud container is selected under the “iCloud” section.

#### Using Your Own iCloud Container

* Create a new iCloud container through Xcode’s “Signing & Capabilities” tab of the Sharing app target.
* Update the `containerIdentifier` property in [Config.swift](Sharing/App/Config.swift) with your new iCloud container ID.

### How it Works

#### User One: Initiating the Share

* On either a device or simulator with a signed-in iCloud account, User One creates a new Contact record through the UI with a name and phone number. The Contact is saved to the user’s private iCloud database with the `addContact(name:phoneNumber:completionHandler)` function in ViewModel.swift.

* After the Contacts list is refreshed, the newly added Contact will appear under the “Private” section of the UI.

* Tapping the share button on the Contact list entry creates a `CKShare` object and writes it to the database with the `createShare(contact:completionHandler)` function in ViewModel.swift. After the share is created, the `CloudSharingView` is displayed which wraps [UICloudSharingController](https://developer.apple.com/documentation/uikit/uicloudsharingcontroller) in a SwiftUI compatible view. This view allows the user to configure share options and send or copy the share link to share with User Two.

#### User Two: Accepting the Share Invitation

* On a separate device with a different signed-in iCloud account, User Two accepts the share by following the link provided by User One.

* The link initiates a prompt on the user’s device to accept the share, which launches the Sharing app and accepts the share through a database operation defined in SceneDelegate’s `userDidAcceptCloudKitShareWith` delegate callback.

* After the share is accepted and the UI is refreshed, the shared Contact will display in User Two’s Contacts list in the “Shared” section. `fetchSharedContacts(completionHandler:)` in ViewModel.swift shows how Contacts in shared database zones are fetched.

### Further Reading

* [Sharing CloudKit Data with Other iCloud Users](https://developer.apple.com/documentation/cloudkit/shared_records/sharing_cloudkit_data_with_other_icloud_users)
