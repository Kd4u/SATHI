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
    @Published private(set) var hasConflict = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var accountID: String?
    @Published private(set) var hasUnclaimedLegacy = false
    @Published private(set) var remoteChange = 0
    private var liveListener: ListenerRegistration?
    private var listenerUID: String?
    private var lastServerSnapshot: SyncSnapshot?
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
        stopLiveUpdates()
        let storage = AccountStorage(root: rootDirectory)
        let folder = try storage.prepare(for: user.uid)
        // Change the complete session together; no prior account's baseline or queue survives.
        baseline = .init()
        hasConflict = false
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
            stopLiveUpdates()
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

    func stopLiveUpdates() {
        liveListener?.remove()
        liveListener = nil; listenerUID = nil; lastServerSnapshot = nil
    }

    func startLiveUpdates() {
        guard configured, signedIn, let uid = accountID else { return }
        guard listenerUID != uid else { return }
        stopLiveUpdates(); listenerUID = uid
        liveListener = Firestore.firestore().collection("users").document(uid)
            .collection("sathi").document("snapshot").addSnapshotListener { [weak self] doc, error in
                Task { @MainActor [weak self] in
                    guard let self, self.accountID == uid, self.listenerUID == uid else { return }
                    if let error {
                        if !self.busy { self.status = "Live sync unavailable: " + error.localizedDescription }
                        return
                    }
                    guard let doc, !doc.metadata.hasPendingWrites, !doc.metadata.isFromCache,
                          let data = doc.data()?["payload"] as? Data,
                          let snapshot = try? JSONDecoder().decode(SyncSnapshot.self, from: data) else { return }
                    if let previous = self.lastServerSnapshot, Self.sameRecords(previous, snapshot) { return }
                    self.lastServerSnapshot = snapshot
                    // Own commits and equivalent JSON must not cause listener/write loops.
                    if !Self.sameRecords(self.baseline, snapshot) { self.remoteChange += 1 }
                }
            }
    }

    nonisolated private static func sameRecords(_ a: SyncSnapshot, _ b: SyncSnapshot) -> Bool {
        Set(a.records.keys) == Set(b.records.keys) && a.records.keys.allSatisfy {
            SyncSnapshot.equivalent(a.records[$0], b.records[$0])
        }
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
    func sync(local: SyncSnapshot, resolving: SyncConflictResolution? = nil, apply: (SyncSnapshot) throws -> Void) async {
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
            let backupFolder = directory.appendingPathComponent("SyncConflictBackups/" + UUID().uuidString, isDirectory: true)
            if resolving != nil {
                try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
                try JSONEncoder().encode(local).write(to: backupFolder.appendingPathComponent("local.json"), options: .atomic)
                try JSONEncoder().encode(base).write(to: backupFolder.appendingPathComponent("baseline.json"), options: .atomic)
            }
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
                        if resolving != nil {
                            // Retain every transaction revision before an explicit conflict choice.
                            try JSONEncoder().encode(remote).write(to: backupFolder.appendingPathComponent("remote-" + UUID().uuidString + ".json"), options: .atomic)
                        }
                        let exchange = try SyncExchange.prepare(base: base, local: local, remote: remote, resolving: resolving)
                        let payload = try JSONEncoder().encode(exchange.cloud)
                        guard payload.count < 900_000 else { throw SyncFailure.oversized }
                        if !Self.sameRecords(exchange.cloud, remote) || !doc.exists {
                            transaction.setData(["schema": 1, "payload": payload, "updatedAt": FieldValue.serverTimestamp()], forDocument: ref)
                        }
                        return try JSONEncoder().encode(exchange)
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
            let exchange = try JSONDecoder().decode(SyncExchange.self, from: result)
            guard !Task.isCancelled, accountID == uid, Auth.auth().currentUser?.uid == uid else { throw SyncFailure.account }
            try apply(exchange.local)
            let checkpoint = Baseline(owner: uid, snapshot: exchange.checkpoint, lastSync: Date())
            try JSONEncoder().encode(checkpoint).write(to: directory.appendingPathComponent("sync-baseline.json"), options: .atomic)
            baseline = exchange.checkpoint
            lastSync = checkpoint.lastSync
            hasCheckedCloud = true
            hasConflict = !exchange.conflicts.isEmpty
            do {
                try await syncActivity(uid: uid)
            } catch {
                status = "Timetable synced. Activity history will retry: \(error.localizedDescription)"
                return
            }
            status = hasConflict ? "Other changes synced. Conflicting records still need a version choice: " + exchange.conflicts.joined(separator: ", ") : "Up to date"
        } catch {
            if error.localizedDescription.contains("Both devices changed") { hasConflict = true }
            status = "Sync not completed: \(error.localizedDescription)"
        }
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
    let resolveConflict: (SyncConflictResolution) -> Void
    @State private var proposedResolution: SyncConflictResolution?
    @State private var confirmingResolution = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your SATHI account").font(.headline)
            Text(store.displayName).font(.title3)
            Text(store.email).foregroundStyle(.secondary)
            Text("Use this personal Google account on all your devices.").font(.caption)
            Button(action: saveAndSync) { Label(store.busy ? "Syncing…" : "Save & Refresh", systemImage: "arrow.triangle.2.circlepath") }.disabled(store.busy)
            Text(store.status).font(.footnote).textSelection(.enabled)
            if store.hasConflict {
                Text("Choose which version to use for conflicting records. Both versions are backed up on this device. A timetable conflict also uses that version’s semester, subjects and study preferences. Other independent edits are kept.").font(.caption)
                Button("Use this device’s version") { proposedResolution = .local; confirmingResolution = true }.disabled(store.busy)
                Button("Use cloud version") { proposedResolution = .remote; confirmingResolution = true }.disabled(store.busy)
            }
            if let date = store.lastSync { Text("Last synced: \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            Text("Saved locally immediately. Sync sends your changes to cloud. Other open devices receive committed changes automatically. Sleeping devices refresh when reopened; hourly background refresh remains available.").font(.caption).foregroundStyle(.secondary)
            Button("Sign out") { store.signOut() }.disabled(store.busy)
        }.padding()
        .confirmationDialog("Resolve conflicting changes?", isPresented: $confirmingResolution, titleVisibility: .visible) {
            Button(proposedResolution == .local ? "Use this device’s version" : "Use cloud version") {
                if let proposedResolution { resolveConflict(proposedResolution) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected version replaces conflicts and related timetable selections. Both snapshots are saved in this device’s private conflict backups first.")
        }
    }
}
