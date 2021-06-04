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

        viewModel.initialize { result in
            expectation.fulfill()

            switch result {
            case .failure(let error):
                XCTFail("Error during VM initialization: \(error)")
            case .success:
                break
            }
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

        let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: idsToDelete)

        var deletedIDs: [CKRecord.ID] = []

        // Track each deletion to ensure all target records are successfully deleted.
        deleteOperation.perRecordDeleteBlock = { id, result in
            guard case .success = result else {
                return
            }

            deletedIDs.append(id)
        }

        deleteOperation.modifyRecordsResultBlock = { result in
            deleteExpectation.fulfill()

            switch result {
            case .failure(let error):
                XCTFail("Error deleting temporary IDs: \(error.localizedDescription)")

            case .success:
                guard deletedIDs == self.idsToDelete else {
                    XCTFail("Deleted IDs in tear down did not match idsToDelete.")
                    return
                }

                self.idsToDelete = []
            }
        }

        database.add(deleteOperation)

        waitForExpectations(timeout: 10, handler: nil)
    }

    // MARK: - CloudKit Readiness

    func test_CloudKitReadiness() throws {
        // Fetch zones from the Private Database of the CKContainer for the current user to test for valid/ready state
        let container = CKContainer(identifier: Config.containerIdentifier)
        let database = container.privateCloudDatabase

        let fetchExpectation = expectation(description: "Expect CloudKit fetch to complete")
        database.fetchAllRecordZones { _, error in
            if let error = error as? CKError {
                switch error.code {
                case .badContainer, .badDatabase:
                    XCTFail("Create or select a CloudKit container in this app target's Signing & Capabilities in Xcode")

                case .permissionFailure, .notAuthenticated:
                    XCTFail("Simulator or device running this app needs a signed-in iCloud account")

                default:
                    XCTFail("CKError: \(error)")
                }
            }
            fetchExpectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    // MARK: - CKShare Creation

    func testCreatingShare() {
        let expectation = self.expectation(description: "Expect sequence of creating CKShare to complete")

        createTestContact {
            self.fetchPrivateContacts { contacts in
                guard let testContact = contacts.first(where: { $0.name == self.testContactName }) else {
                    XCTFail("No matching test Contact found after fetching private contacts")
                    expectation.fulfill()
                    return
                }

                self.idsToDelete.append(testContact.associatedRecord.recordID)

                self.viewModel.createShare(contact: testContact) { result in
                    switch result {
                    case .failure(let error):
                        XCTFail("Failed to create share on test Contact: \(error)")
                    case .success((let share, _)):
                        self.idsToDelete.append(share.recordID)
                    }

                    expectation.fulfill()
                }
            }
        }

        waitForExpectations(timeout: 15)
    }

    // MARK: - Helpers

    /// For testing creating a `CKShare`, we need to create a `Contact` with a name we can reference later.
    private lazy var testContactName: String = {
        "Test\(UUID().uuidString)"
    }()

    /// Simple function to create and save a new `Contact` to test with. Immediately fails on any error.
    /// - Parameter completion: Handler called on completion.
    private func createTestContact(completion: @escaping () -> Void) {
        viewModel.addContact(name: testContactName, phoneNumber: "555-123-4567") { result in
            if case .failure(let error) = result {
                XCTFail("Error creating test contact: \(error)")
            }

            completion()
        }
    }

    /// Uses the ViewModel to fetch only private contacts. Immediately fails on any error.
    /// - Parameter completion: Handler called on completion.
    private func fetchPrivateContacts(completion: @escaping ([Contact]) -> Void) {
        viewModel.fetchPrivateAndSharedContacts { result in
            switch result {
            case .failure(let error):
                XCTFail("Error creating test contact: \(error)")
                completion([])
            case .success((let privateContacts, _)):
                completion(privateContacts)
            }
        }
    }
}
