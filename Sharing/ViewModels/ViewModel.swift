//
//  ViewModel.swift
//  (cloudkit-samples) Sharing
//

import Foundation
import CloudKit
import OSLog

final class ViewModel: ObservableObject {

    // MARK: - Error

    enum ViewModelError: Error {
        case unknown
    }

    // MARK: - State

    enum State {
        case loading
        case loaded(private: [Contact], shared: [Contact])
        case error(Error)
    }

    // MARK: - Properties

    /// State directly observable by our view.
    @Published private(set) var state: State
    /// Use the specified iCloud container ID, which should also be present in the entitlements file.
    lazy var container = CKContainer(identifier: Config.containerIdentifier)
    /// This project uses the user's private database.
    private lazy var database = container.privateCloudDatabase
    /// Sharing requires using a custom record zone.
    let recordZone = CKRecordZone(zoneName: "Contacts")

    // MARK: - Init

    /// Initializer to provide explicit state (e.g. for previews).
    init(state: State = .loading) {
        self.state = state
    }

    // MARK: - API

    /// Creates custom zone if needed and performs initial fetch afterwards.
    func initialize(completionHandler: ((Result<Void, Error>) -> Void)? = nil) {
        createZoneIfNeeded { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    self.state = .error(error)
                    completionHandler?(.failure(error))

                case .success:
                    self.refresh()
                    completionHandler?(.success(()))
                }
            }
        }
    }

    /// Fetches contacts from the remote databases and updates local state.
    func refresh() {
        state = .loading

        fetchPrivateAndSharedContacts { result in
            switch result {
            case let .success((privateContacts, sharedContacts)):
                self.state = .loaded(private: privateContacts, shared: sharedContacts)
            case let .failure(error):
                self.state = .error(error)
            }
        }
    }

    /// Fetch private and shared Contacts from iCloud databases.
    /// - Parameter completionHandler: Handler to process Contact results or error.
    func fetchPrivateAndSharedContacts(
        completionHandler: @escaping (Result<([Contact], [Contact]), Error>) -> Void
    ) {
        // Multiple operations are run asynchronously, storing results as they complete.
        var privateContacts: [Contact]?
        var sharedContacts: [Contact]?
        var lastError: Error?

        let group = DispatchGroup()

        group.enter()
        fetchContacts(scope: .private, in: [recordZone]) { result in
            switch result {
            case .success(let contacts):
                privateContacts = contacts
            case .failure(let error):
                lastError = error
            }

            group.leave()
        }

        group.enter()
        fetchSharedContacts { result in
            switch result {
            case .success(let contacts):
                sharedContacts = contacts
            case .failure(let error):
                lastError = error
            }

            group.leave()
        }

        // When all asynchronous operations have completed, inform the completionHandler of the result.
        group.notify(queue: .main) {
            if let error = lastError {
                completionHandler(.failure(error))
            } else {
                let privateContacts = privateContacts ?? []
                let sharedContacts = sharedContacts ?? []
                completionHandler(.success((privateContacts, sharedContacts)))
            }
        }
    }

    /// Adds a new Contact to the database.
    /// - Parameters:
    ///   - name: Name of the Contact.
    ///   - phoneNumber: Phone number of the contact.
    ///   - completionHandler: Handler to process success or error of the operation.
    func addContact(
        name: String,
        phoneNumber: String,
        completionHandler: @escaping (Result<Void, Error>) -> Void
    ) {
        let id = CKRecord.ID(zoneID: recordZone.zoneID)
        let contactRecord = CKRecord(recordType: "Contact", recordID: id)
        contactRecord["name"] = name
        contactRecord["phoneNumber"] = phoneNumber

        let saveOperation = CKModifyRecordsOperation(recordsToSave: [contactRecord])
        saveOperation.savePolicy = .allKeys

        saveOperation.modifyRecordsCompletionBlock = { recordsSaved, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    completionHandler(.failure(error))
                    debugPrint("Error adding contact: \(error)")
                } else {
                    completionHandler(.success(()))
                }
            }
        }

        database.add(saveOperation)
    }

    /// Fetches an existing `CKShare` on a Contact record, or creates a new one in preparation to share a Contact with another user.
    /// - Parameters:
    ///   - contact: Contact to share.
    ///   - completionHandler: Handler to process a `success` or `failure` result.
    func fetchOrCreateShare(contact: Contact, completionHandler: @escaping (Result<(CKShare, CKContainer), Error>) -> Void) {
        guard let existingShare = contact.associatedRecord.share else {
            let share = CKShare(rootRecord: contact.associatedRecord)
            share[CKShare.SystemFieldKey.title] = "Contact: \(contact.name)"

            let operation = CKModifyRecordsOperation(recordsToSave: [contact.associatedRecord, share])
            operation.modifyRecordsCompletionBlock = { (savedRecords, deletedRecordIDs, error) in
                if let error = error {
                    completionHandler(.failure(error))
                    debugPrint("Error saving CKShare: \(error)")
                } else {
                    completionHandler(.success((share, self.container)))
                }
            }

            database.add(operation)
            return
        }

        database.fetch(withRecordID: existingShare.recordID) { (share, error) in
            if let error = error {
                completionHandler(.failure(error))
            } else if let share = share as? CKShare {
                completionHandler(.success((share, self.container)))
            } else {
                completionHandler(.failure(ViewModelError.unknown))
            }
        }
    }

    // MARK: - Private

    /// Asynchronously fetches contacts for a given set of zones in a given database scope.
    /// - Parameters:
    ///   - scope: Database scope to fetch from.
    ///   - zones: Record zones to fetch contacts from.
    ///   - completionHandler: Handler to process success or failure of operation.
    private func fetchContacts(
        scope: CKDatabase.Scope,
        in zones: [CKRecordZone],
        completionHandler: @escaping (Result<[Contact], Error>) -> Void
    ) {
        let database = container.database(with: scope)
        let zoneIDs = zones.map { $0.zoneID }
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs,
                                                          configurationsByRecordZoneID: [:])
        var contacts: [Contact] = []

        operation.recordChangedBlock = { record in
            if record.recordType == "Contact", let contact = Contact(record: record) {
                contacts.append(contact)
            }
        }

        operation.fetchRecordZoneChangesCompletionBlock = { error in
            if let error = error {
                completionHandler(.failure(error))
            } else {
                completionHandler(.success(contacts))
            }
        }

        database.add(operation)
    }

    /// Fetches all shared Contacts from all available record zones.
    /// - Parameter completionHandler: Handler to process success or failure.
    private func fetchSharedContacts(completionHandler: @escaping (Result<[Contact], Error>) -> Void) {
        // The first step is to fetch all available record zones in user's shared database.
        container.sharedCloudDatabase.fetchAllRecordZones { zones, error in
            if let error = error {
                completionHandler(.failure(error))
            } else if let zones = zones, !zones.isEmpty {
                // Fetch all Contacts in the set of zones in the shared database.
                self.fetchContacts(scope: .shared, in: zones, completionHandler: completionHandler)
            } else {
                // Zones nil or empty so no shared contacts.
                completionHandler(.success([]))
            }
        }
    }

    /// Creates the custom zone in use if needed.
    /// - Parameter completionHandler: An optional completion handler to track operation completion or errors.
    private func createZoneIfNeeded(completionHandler: ((Result<Void, Error>) -> Void)? = nil) {
        // Avoid the operation if this has already been done.
        guard !UserDefaults.standard.bool(forKey: "isZoneCreated") else {
            completionHandler?(.success(()))
            return
        }

        let createZoneOperation = CKModifyRecordZonesOperation(recordZonesToSave: [recordZone])
        createZoneOperation.modifyRecordZonesCompletionBlock = { _, _, error in
            if let error = error {
                debugPrint("Error: Failed to create custom zone: \(error)")
                completionHandler?(.failure(error))
            } else {
                DispatchQueue.main.async {
                    UserDefaults.standard.setValue(true, forKey: "isZoneCreated")
                    completionHandler?(.success(()))
                }
            }
        }

        database.add(createZoneOperation)
    }
}
