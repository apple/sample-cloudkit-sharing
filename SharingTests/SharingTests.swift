//
//  SharingTests.swift
//  SharingTests
//

import XCTest
import CloudKit
@testable import Sharing

class SharingTests: XCTestCase {

    let viewModel = ViewModel()
    var idsToDelete: [CKRecord.ID] = []

    // MARK: - Setup & Tear Down

    override func setUp() {
        let expectation = self.expectation(description: "Expect ViewModel initizliation completed")

        async {
            try await viewModel.initialize()
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    override func tearDownWithError() throws {
        guard !idsToDelete.isEmpty else {
            return
        }

        let container = CKContainer(identifier: Config.containerIdentifier)
        let database = container.privateCloudDatabase
        let deleteExpectation = expectation(description: "Expect CloudKit to delete testing records")

        async {
            _ = try await database.modifyRecords(deleting: idsToDelete)
            idsToDelete = []
            deleteExpectation.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
    }

    // MARK: - CloudKit Readiness

    func test_CloudKitReadiness() async throws {
        // Fetch zones from the Private Database of the CKContainer for the current user to test for valid/ready state
        let container = CKContainer(identifier: Config.containerIdentifier)
        let database = container.privateCloudDatabase

        do {
            _ = try await database.allRecordZones()
        } catch let error as CKError {
            switch error.code {
            case .badContainer, .badDatabase:
                XCTFail("Create or select a CloudKit container in this app target's Signing & Capabilities in Xcode")

            case .permissionFailure, .notAuthenticated:
                XCTFail("Simulator or device running this app needs a signed-in iCloud account")

            default:
                XCTFail("CKError: \(error)")
            }
        }
    }

    // MARK: - CKShare Creation

    func testCreatingShare() async throws {
        // Create a temporary contact to create the share on.
        try await createTestContact()
        // Fetch private contacts, which should now contain the temporary contact.
        let privateContacts = try await fetchPrivateContacts()

        guard let testContact = privateContacts.first(where: { $0.name == self.testContactName }) else {
            XCTFail("No matching test Contact found after fetching private contacts")
            return
        }

        idsToDelete.append(testContact.associatedRecord.recordID)

        let (share, _) = try await viewModel.createShare(contact: testContact)

        idsToDelete.append(share.recordID)
    }

    // MARK: - Helpers

    /// For testing creating a `CKShare`, we need to create a `Contact` with a name we can reference later.
    private lazy var testContactName: String = {
        "Test\(UUID().uuidString)"
    }()

    /// Simple function to create and save a new `Contact` to test with. Immediately fails on any error.
    private func createTestContact() async throws {
        try await viewModel.addContact(name: testContactName, phoneNumber: "555-123-4567")
    }

    /// Uses the ViewModel to fetch only private contacts. Immediately fails on any error.
    /// - Parameter completion: Handler called on completion.
    private func fetchPrivateContacts() async throws -> [Contact] {
        try await viewModel.fetchPrivateAndSharedContacts().private
    }
}
