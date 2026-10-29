import SwiftUI
import Combine
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import GoogleSignInSwift
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
final class CloudSyncStore: ObservableObject {
    @Published var email = ""
    @Published private(set) var displayName = ""
    @Published private(set) var hasCheckedCloud = false
    @Published private(set) var signedIn = false
    @Published private(set) var busy = false
    @Published private(set) var status = "Cloud sync not connected"
    @Published private(set) var lastSync: Date?
    @Published private(set) var accountID: String?
    @Published private(set) var hasUnclaimedLegacy = false
    private var baseline = SyncSnapshot()
    private let rootDirectory: URL
    var dataDirectory: URL {
        guard let uid = accountID else { return rootDirectory.appendingPathComponent("SignedOut", isDirectory: true) }
        return AccountStorage(root: rootDirectory).directory(for: uid)
    }
    private var directory: URL { dataDirectory }
    private var configured = false
    private(set) var journal: ActivityJournal

    init(directory: URL) {
        rootDirectory = directory
        journal = ActivityJournal(directory: directory.appendingPathComponent("SignedOut", isDirectory: true))
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else {
            status = SyncFailure.configuration.localizedDescription
            return
        }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        configured = true
        if let user = Auth.auth().currentUser, user.providerData.contains(where: { $0.providerID == "google.com" }) {
            do {
                try activate(user)
                status = "Loading your saved timetable…"
            } catch { status = "Could not open account data: \(error.localizedDescription)" }
        } else { status = "Sign in with your personal Google account" }
    }

    private func activate(_ user: User) throws {
        let storage = AccountStorage(root: rootDirectory)
        let folder = try storage.prepare(for: user.uid)
        // Change the complete session together; no prior account's baseline or queue survives.
        baseline = .init()
        lastSync = nil
        hasCheckedCloud = false
        journal = ActivityJournal(directory: folder)
        email = user.email ?? ""
        displayName = user.displayName ?? ""
        accountID = user.uid
        hasUnclaimedLegacy = storage.hasUnclaimedLegacy
        loadBaseline()
        signedIn = true
    }

    func claimLegacyData() throws {
        guard let uid = accountID, signedIn, hasCheckedCloud, !busy else { throw SyncFailure.account }
        try AccountStorage(root: rootDirectory).claimLegacy(for: uid)
        hasUnclaimedLegacy = false
        try journal.record("legacy_data_imported")
    }

    func signInWithGoogle() async {
        guard configured else { status = SyncFailure.configuration.localizedDescription; return }
        guard !busy else { return }
        guard let clientID = FirebaseApp.app()?.options.clientID,
              let configURL = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let config = NSDictionary(contentsOf: configURL),
              let callback = config["REVERSED_CLIENT_ID"] as? String,
              let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]],
              types.contains(where: { ($0["CFBundleURLSchemes"] as? [String] ?? []).contains(callback) }) else {
            status = "Google sign-in setup is pending. Your existing saved data is safe."
            return
        }
        busy = true
        defer { busy = false }
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            let result: GIDSignInResult
            #if os(macOS)
            guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else { throw SyncFailure.account }
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
            #elseif canImport(UIKit)
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                  var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { throw SyncFailure.account }
            while let presented = presenter.presentedViewController { presenter = presented }
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            #else
            throw SyncFailure.account
            #endif
            guard let idToken = result.user.idToken?.tokenString else { throw SyncFailure.account }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            let authResult: AuthDataResult
            if let current = Auth.auth().currentUser,
               !current.providerData.contains(where: { $0.providerID == "google.com" }),
               current.email?.lowercased() == result.user.profile?.email.lowercased() {
                authResult = try await current.link(with: credential)
            } else {
                authResult = try await Auth.auth().signIn(with: credential)
            }
            try activate(authResult.user)
            try journal.record("google_sign_in")
            status = "Signed in. Loading your saved timetable…"
        } catch { status = error.localizedDescription }
    }

    func signOut() {
        guard !busy else { return }
        do {
            try journal.record("sign_out")
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            signedIn = false
            accountID = nil
            email = ""
            displayName = ""
            baseline = .init()
            lastSync = nil
            hasCheckedCloud = false
            hasUnclaimedLegacy = false
            journal = ActivityJournal(directory: rootDirectory.appendingPathComponent("SignedOut", isDirectory: true))
            status = "Signed out. Your saved copy remains on this device."
        } catch { status = error.localizedDescription }
    }

    private func syncActivity(uid: String) async throws {
        let collection = Firestore.firestore().collection("users").document(uid).collection("activity")
        let pending = journal.pending
        // Deterministic document IDs make retries safe after interrupted requests.
        for offset in stride(from: 0, to: pending.count, by: 200) {
            let entries = Array(pending[offset..<min(offset + 200, pending.count)])
            let batch = Firestore.firestore().batch()
            for entry in entries {
                let payload = try JSONEncoder().encode(entry)
                batch.setData(["payload": payload, "committedAt": FieldValue.serverTimestamp()], forDocument: collection.document(entry.id))
            }
            try await batch.commit()
            try journal.acknowledge(entries.map(\.id))
        }
        // Fetch the history on first sign-in; subsequent requests overlap the last sync
        // to include delayed writes without duplicating entries.
        var query: Query = collection.order(by: "committedAt").limit(to: 200)
        if let cursor = journal.cloudCursor { query = query.whereField("committedAt", isGreaterThanOrEqualTo: Timestamp(date: cursor.addingTimeInterval(-1))) }
        var newest = journal.cloudCursor
        while true {
            let page = try await query.getDocuments(source: .server)
            let entries = try page.documents.map { doc -> ActivityEntry in
                guard let payload = doc.data()["payload"] as? Data else { throw SyncFailure.invalidData }
                return try JSONDecoder().decode(ActivityEntry.self, from: payload)
            }
            try journal.receive(entries)
            if let timestamp = page.documents.last?.data()["committedAt"] as? Timestamp { newest = timestamp.dateValue() }
            guard page.documents.count == 200, let last = page.documents.last else { break }
            query = query.start(afterDocument: last)
        }
        if let newest { try journal.advanceCursor(newest) }
    }

    // apply must validate and durably save local data before advancing the baseline.
    func sync(local: SyncSnapshot, apply: (SyncSnapshot) throws -> Void) async {
        guard configured else { status = SyncFailure.configuration.localizedDescription; return }
        guard signedIn, let uid = accountID, Auth.auth().currentUser?.uid == uid else { status = SyncFailure.account.localizedDescription; return }
        guard !busy else { return }
        busy = true
        status = "Syncing…"
        defer { busy = false }
        do {
            let base = baseline
            // An unexpectedly empty local store must never erase an existing cloud snapshot.
            guard base.records.isEmpty || !local.records.isEmpty else { throw SyncFailure.invalidData }
            let ref = Firestore.firestore().collection("users").document(uid).collection("sathi").document("snapshot")
            let result: Data = try await withCheckedThrowingContinuation { continuation in
                Firestore.firestore().runTransaction({ transaction, errorPointer -> Any? in
                    do {
                        let doc = try transaction.getDocument(ref)
                        let remote: SyncSnapshot
                        if doc.exists {
                            guard doc.data()?["schema"] as? Int == 1, let payload = doc.data()?["payload"] as? Data else { throw SyncFailure.invalidData }
                            remote = try JSONDecoder().decode(SyncSnapshot.self, from: payload)
                        } else {
                            guard base.records.isEmpty else { throw SyncFailure.invalidData }
                            remote = .init()
                        }
                        let merged = try SyncSnapshot.merge(base: base, local: local, remote: remote)
                        let payload = try JSONEncoder().encode(merged)
                        guard payload.count < 900_000 else { throw SyncFailure.oversized }
                        if merged != remote || !doc.exists {
                            transaction.setData(["schema": 1, "payload": payload, "updatedAt": FieldValue.serverTimestamp()], forDocument: ref)
                        }
                        return payload
                    } catch {
                        errorPointer?.pointee = error as NSError
                        return nil
                    }
                }, completion: { result, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let payload = result as? Data { continuation.resume(returning: payload) }
                    else { continuation.resume(throwing: SyncFailure.invalidData) }
                })
            }
            let merged = try JSONDecoder().decode(SyncSnapshot.self, from: result)
            guard !Task.isCancelled, accountID == uid, Auth.auth().currentUser?.uid == uid else { throw SyncFailure.account }
            try apply(merged)
            let checkpoint = Baseline(owner: uid, snapshot: merged, lastSync: Date())
            try JSONEncoder().encode(checkpoint).write(to: directory.appendingPathComponent("sync-baseline.json"), options: .atomic)
            baseline = merged
            lastSync = checkpoint.lastSync
            hasCheckedCloud = true
            do {
                try await syncActivity(uid: uid)
            } catch {
                status = "Timetable synced. Activity history will retry: \(error.localizedDescription)"
                return
            }
            status = "Up to date"
        } catch { status = "Sync not completed: \(error.localizedDescription)" }
    }

    private struct Baseline: Codable { let owner: String; let snapshot: SyncSnapshot; let lastSync: Date }
    private func loadBaseline() {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("sync-baseline.json")),
              let saved = try? JSONDecoder().decode(Baseline.self, from: data), saved.owner == accountID else { return }
        baseline = saved.snapshot
        lastSync = saved.lastSync
    }
}

struct GoogleOnboardingView: View {
    @ObservedObject var store: CloudSyncStore
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 48)).foregroundStyle(.tint)
            Text("Welcome to SATHI").font(.largeTitle.bold())
            Text("Sign in once. Your timetable, attendance and events follow you.")
                .multilineTextAlignment(.center)
            Text("Use your personal Google account, rather than a college or work account. Use the same account on your Mac, iPad and iPhone.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            GoogleSignInButton { Task { await store.signInWithGoogle() } }
                .frame(maxWidth: 320).disabled(store.busy)
            if store.busy { ProgressView() }
            Text(store.status).font(.footnote).multilineTextAlignment(.center).textSelection(.enabled)
            Text("SATHI remembers your sign-in on this device. Google handles your password; SATHI never records it.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(30).frame(maxWidth: 540).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CloudSyncPanel: View {
    @ObservedObject var store: CloudSyncStore
    let saveAndSync: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your SATHI account").font(.headline)
            Text(store.displayName).font(.title3)
            Text(store.email).foregroundStyle(.secondary)
            Text("Use this personal Google account on all your devices.").font(.caption)
            Button(action: saveAndSync) { Label(store.busy ? "Syncing…" : "Save & Refresh", systemImage: "arrow.triangle.2.circlepath") }.disabled(store.busy)
            Text(store.status).font(.footnote).textSelection(.enabled)
            if let date = store.lastSync { Text("Last synced: \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            Text("Saved locally immediately. Syncs every 2 minutes while open and when you return to the app.").font(.caption).foregroundStyle(.secondary)
            Button("Sign out") { store.signOut() }.disabled(store.busy)
        }.padding()
    }
}
