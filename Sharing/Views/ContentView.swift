//
//  ContentView.swift
//  (cloudkit-samples) Sharing
//

import SwiftUI
import CloudKit

struct ContentView: View {

    // MARK: - Properties & State

    @EnvironmentObject private var vm: ViewModel

    @State private var isAddingContact = false
    @State private var isSharing = false
    @State private var isProcessingShare = false

    @State private var activeShare: CKShare?
    @State private var activeContainer: CKContainer?

    // MARK: - Views

    var body: some View {
        NavigationView {
            contentView
                .navigationTitle("Contacts")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { async { try await vm.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        progressView
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { isAddingContact = true }) { Image(systemName: "plus") }
                    }
                }
        }
        .onAppear {
            async {
                try await vm.initialize()
                try await vm.refresh()
            }
        }
        .sheet(isPresented: $isAddingContact, content: {
            AddContactView(onAdd: addContact, onCancel: { isAddingContact = false })
        })
    }

    /// This progress view will display when either the ViewModel is loading, or a share is processing.
    var progressView: some View {
        let showProgress: Bool = {
            if case .loading = vm.state {
                return true
            } else if isProcessingShare {
                return true
            }

            return false
        }()

        return Group {
            if showProgress {
                ProgressView()
            }
        }
    }

    /// Dynamic view built from ViewModel state.
    private var contentView: some View {
        Group {
            switch vm.state {
            case let .loaded(privateContacts, sharedContacts):
                List {
                    Section(header: Text("Private")) {
                        ForEach(privateContacts) { contactRowView(for: $0) }
                    }
                    Section(header: Text("Shared")) {
                        ForEach(sharedContacts) { contactRowView(for: $0, shareable: false) }
                    }
                }.listStyle(GroupedListStyle())

            case .error(let error):
                VStack {
                    Text("An error occurred: \(error.localizedDescription)").padding()
                    Spacer()
                }

            case .loading:
                VStack { EmptyView() }
            }
        }
    }

    /// Builds a `CloudSharingView` with state after processing a share.
    private func shareView() -> CloudSharingView? {
        guard let share = activeShare, let container = activeContainer else {
            return nil
        }

        return CloudSharingView(container: container, share: share)
    }

    /// Builds a Contact row view for display contact information in a List.
    private func contactRowView(for contact: Contact, shareable: Bool = true) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(contact.name)
                Text(contact.phoneNumber)
                    .textContentType(.telephoneNumber)
                    .font(.footnote)
            }
            if shareable {
                Spacer()
                Button(action: { async { try? await shareContact(contact) } }, label: { Image(systemName: "square.and.arrow.up") }).buttonStyle(BorderlessButtonStyle())
                    .sheet(isPresented: $isSharing, content: { shareView() })
            }
        }
    }

    // MARK: - Actions

    private func addContact(name: String, phoneNumber: String) async throws {
        try await vm.addContact(name: name, phoneNumber: phoneNumber)
        try await vm.refresh()
        isAddingContact = false
    }

    private func shareContact(_ contact: Contact) async throws {
        isProcessingShare = true

        do {
            let (share, container) = try await vm.fetchOrCreateShare(contact: contact)
            isProcessingShare = false
            activeShare = share
            activeContainer = container
            isSharing = true
        } catch {
            debugPrint("Error sharing contact record: \(error)")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    private static let previewContacts: [Contact] = [
        Contact(
            id: UUID().uuidString,
            name: "John Appleseed",
            phoneNumber: "(888) 555-5512",
            associatedRecord: CKRecord(recordType: "Contact")
        )
    ]

    static var previews: some View {
        ContentView()
            .environmentObject(ViewModel(state: .loaded(private: previewContacts, shared: previewContacts)))
    }
}
