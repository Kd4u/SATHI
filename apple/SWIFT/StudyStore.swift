import Foundation
import Combine
import CryptoKit
import FirebaseFirestore

@MainActor
final class StudyStore: ObservableObject {
    @Published var workspace = StudyWorkspace()
    @Published private(set) var assets: [StudyAsset] = []
    @Published private(set) var status = "Saved on this device"
    private var folder: URL?
    private var uid: String?
    private var cursor: Date?
    private var configured = false
    private var syncing = false
    @Published private(set) var conflictNotice = ""
    private var activity: ActivityJournal?

    func configure(directory: URL, uid: String, journal: ActivityJournal? = nil) throws {
        activity = journal
        let requestedFolder = directory.appendingPathComponent("Study", isDirectory: true)
        if configured && self.uid == uid && folder == requestedFolder { return }
        configured = false
        conflictNotice = ""
        self.uid = uid
        folder = directory.appendingPathComponent("Study", isDirectory: true)
        try FileManager.default.createDirectory(at: folder!, withIntermediateDirectories: true)
        workspace = FileManager.default.fileExists(atPath: folder!.appendingPathComponent("workspace.json").path) ? try read(StudyWorkspace.self, "workspace.json") : .init()
        assets = FileManager.default.fileExists(atPath: folder!.appendingPathComponent("assets.json").path) ? try read([StudyAsset].self, "assets.json") : []
        cursor = try? read(Date.self, "cursor.json")
        configured = true
    }

    func reloadAssets() throws { assets = try read([StudyAsset].self, "assets.json") }

    func notebookDirectory() throws -> URL {
        guard configured, let folder else { throw SyncFailure.account }
        return folder.appendingPathComponent("Notebooks", isDirectory: true)
    }

    func recordAction(_ name: String) { try? activity?.record(name) }

    func ensureSemesterID(seed: String) throws {
        if workspace.currentSemesterID.isEmpty {
            workspace.currentSemesterID = SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
            try saveWorkspace()
        }
    }

    func saveWorkspace() throws { try write(workspace, "workspace.json") }

    func workspaceRecords() throws -> [String: Data] {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var result = ["study:preferences": try encoder.encode(workspace.preferences)]
        struct Index: Codable { var current: String; var semesters: [SemesterSummary] }
        result["study:semesters"] = try encoder.encode(Index(current: workspace.currentSemesterID, semesters: workspace.semesters))
        for (id, proof) in workspace.proofs { result["study:proof:" + id] = try encoder.encode(proof) }
        for (id, value) in workspace.overrides { result["study:override:" + id] = try encoder.encode(value) }
        return result
    }

    func decodeWorkspace(_ records: [String: Data]) throws -> StudyWorkspace {
        var next = StudyWorkspace(); let decoder = JSONDecoder()
        struct Index: Codable { var current: String; var semesters: [SemesterSummary] }
        for (key, data) in records where key.hasPrefix("study:") {
            switch key {
            case "study:preferences": next.preferences = try decoder.decode(StudyPreferences.self, from: data)
            case "study:semesters":
                let index = try decoder.decode(Index.self, from: data)
                next.currentSemesterID = index.current; next.semesters = index.semesters
            default:
                if key.hasPrefix("study:proof:") { next.proofs[String(key.dropFirst(12))] = try decoder.decode(ClassProof.self, from: data) }
                else if key.hasPrefix("study:override:") { next.overrides[String(key.dropFirst(15))] = try decoder.decode(ScheduleOverride.self, from: data) }
                else { throw SyncFailure.invalidData }
            }
        }
        return next
    }

    func createNotebook(subject: String, semesterID: String) throws -> String {
        let id = UUID().uuidString
        try saveAsset(id: id, kind: "note", title: subject.isEmpty ? "Quick notes" : subject, subject: subject, semesterID: semesterID, data: JSONEncoder().encode(NotebookPage()))
        return id
    }

    func note(_ id: String) throws -> NotebookPage { try JSONDecoder().decode(NotebookPage.self, from: assetData(id)) }

    func saveNote(_ id: String, page: NotebookPage) throws {
        guard let item = assets.first(where: { $0.id == id }) else { throw SyncFailure.invalidData }
        try saveAsset(id: id, kind: item.kind, title: item.title, subject: item.subject, semesterID: item.semesterID, data: JSONEncoder().encode(page))
    }

    func assetURL(_ id: String) throws -> URL {
        guard let folder, !id.contains("/"), !id.contains("\\"), !id.isEmpty else { throw SyncFailure.invalidData }
        return folder.appendingPathComponent(id + ".json")
    }

    func assetData(_ id: String) throws -> Data {
        guard let folder else { throw SyncFailure.account }
        return try Data(contentsOf: folder.appendingPathComponent(id + ".json"))
    }

    func saveAsset(id: String, kind: String, title: String, subject: String, semesterID: String, data: Data) throws {
        guard let folder else { throw SyncFailure.account }
        let existing = assets.first(where: { $0.id == id })
        let old = try? Data(contentsOf: folder.appendingPathComponent(id + ".json"))
        if old == data { return }
        try data.write(to: folder.appendingPathComponent(id + ".json"), options: .atomic)
        let next = StudyAsset(id: id, kind: kind, title: title, subject: subject, semesterID: semesterID, revision: UUID().uuidString, baseRevision: existing?.baseRevision, modifiedAt: Date(), pending: true)
        assets.removeAll { $0.id == id }; assets.append(next)
        try write(assets, "assets.json")
        try activity?.record(["note", "notebook", "notebookPage"].contains(kind) ? "note_saved" : "semester_archived", details: ["id": id, "title": title, "semester": semesterID])
        status = "Saved locally · waiting to sync"
    }

    func sync() async {
        guard !Task.isCancelled, !syncing, let uid, let folder else { return }
        syncing = true; defer { syncing = false }
        let collection = Firestore.firestore().collection("users").document(uid).collection("studyAssets")
        do {
            for item in assets.filter(\.pending) {
                try Task.checkCancellation()
                let reference = collection.document(item.id)
                let head = try await reference.getDocument(source: .server)
                guard !Task.isCancelled, self.uid == uid else { return }
                if let remoteRevision = head.data()?["revision"] as? String,
                   remoteRevision != item.baseRevision && remoteRevision != item.revision {
                    try preserveConflict(item.id)
                    continue
                }
                let data = try Data(contentsOf: folder.appendingPathComponent(item.id + ".json"))
                let count = max(1, Int(ceil(Double(data.count) / 700_000)))
                guard count < 200 else { throw SyncFailure.oversized }
                for chunk in 0..<count {
                    try Task.checkCancellation()
                    let lower = min(chunk * 700_000, data.count); let upper = min(lower + 700_000, data.count)
                    try await reference.collection("versions").document(item.revision).collection("chunks").document(String(chunk)).setData(["bytes": Data(data[lower..<upper])])
                }
                try Task.checkCancellation()
                let encoded = try JSONEncoder().encode(item)
                _ = try await Firestore.firestore().runTransaction { transaction, pointer in
                    do {
                        let remote = try transaction.getDocument(reference)
                        let revision = remote.data()?["revision"] as? String
                        guard revision == item.baseRevision || revision == item.revision else { throw SyncFailure.conflict(item.title) }
                        transaction.setData(["revision": item.revision, "metadata": encoded, "chunks": count, "committedAt": FieldValue.serverTimestamp()], forDocument: reference)
                        return true
                    } catch { pointer?.pointee = error as NSError; return nil }
                }
                guard !Task.isCancelled, self.uid == uid else { return }
                if let index = assets.firstIndex(where: { $0.id == item.id }) {
                    assets[index].baseRevision = item.revision
                    if assets[index].revision == item.revision { assets[index].pending = false }
                }
                try write(assets, "assets.json")
            }
            var query: Query = collection.order(by: "committedAt").limit(to: 100)
            if let cursor { query = query.whereField("committedAt", isGreaterThanOrEqualTo: Timestamp(date: cursor.addingTimeInterval(-1))) }
            var latest = cursor
            while true {
                let page = try await query.getDocuments(source: .server)
                for doc in page.documents {
                    guard let encoded = doc.data()["metadata"] as? Data,
                          let revision = doc.data()["revision"] as? String,
                          let chunks = doc.data()["chunks"] as? Int, chunks > 0, chunks < 200 else { throw SyncFailure.invalidData }
                    var incoming = try JSONDecoder().decode(StudyAsset.self, from: encoded)
                    guard incoming.id == doc.documentID, !incoming.id.contains("/"), incoming.id.count < 150 else { throw SyncFailure.invalidData }
                    if let local = assets.first(where: { $0.id == incoming.id }) {
                        if local.revision == revision { continue }
                        if local.pending {
                            if local.baseRevision == revision { continue }
                            try preserveConflict(local.id)
                        }
                    }
                    var content = Data()
                    for index in 0..<chunks {
                        let chunk = try await doc.reference.collection("versions").document(revision).collection("chunks").document(String(index)).getDocument(source: .server)
                        guard let bytes = chunk.data()?["bytes"] as? Data else { throw SyncFailure.invalidData }
                        content.append(bytes)
                    }
                    guard !Task.isCancelled, self.uid == uid else { return }
                    // Edits may have been saved while the page chunks were downloading.
                    if let current = assets.first(where: { $0.id == incoming.id }) {
                        if current.revision == revision { continue }
                        if current.pending {
                            if current.baseRevision == revision { continue }
                            try preserveConflict(current.id)
                        }
                    }
                    try content.write(to: folder.appendingPathComponent(incoming.id + ".json"), options: .atomic)
                    incoming.pending = false; incoming.baseRevision = revision
                    assets.removeAll { $0.id == incoming.id }; assets.append(incoming)
                    try write(assets, "assets.json")
                }
                if let stamp = page.documents.last?.data()["committedAt"] as? Timestamp { latest = stamp.dateValue() }
                guard page.documents.count == 100, let last = page.documents.last else { break }
                query = query.start(afterDocument: last)
            }
            if let latest { cursor = latest; try write(latest, "cursor.json") }
            status = conflictNotice.isEmpty ? "Notes and semester history are up to date" : conflictNotice
        } catch { status = "Saved locally. Sync needs attention: \(error.localizedDescription)" }
    }

    private func preserveConflict(_ id: String) throws {
        guard let item = assets.first(where: { $0.id == id }), item.pending else { return }
        let copyID = UUID().uuidString
        try saveAsset(id: copyID, kind: item.kind, title: item.title + " · local conflict copy", subject: item.subject, semesterID: item.semesterID, data: assetData(id))
        if let index = assets.firstIndex(where: { $0.id == id }) { assets[index].pending = false }
        try write(assets, "assets.json")
        conflictNotice = "Concurrent edits preserved as a separate local copy. The original follows the cloud version; refresh again to upload the copy."
    }

    private func read<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        guard let folder else { throw SyncFailure.account }
        return try JSONDecoder().decode(type, from: Data(contentsOf: folder.appendingPathComponent(name)))
    }
    private func write<T: Encodable>(_ value: T, _ name: String) throws {
        guard let folder else { throw SyncFailure.account }
        try JSONEncoder().encode(value).write(to: folder.appendingPathComponent(name), options: .atomic)
    }
}

@MainActor enum StudyStoreRegistry {
    private static var currentUID: String?
    private static var current = StudyStore()
    static func store(for uid: String?) -> StudyStore {
        if currentUID != uid { currentUID = uid; current = StudyStore() }
        return current
    }
}
