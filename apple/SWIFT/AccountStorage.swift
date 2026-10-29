import Foundation
import CryptoKit

/// Separate account caches while leaving the original SATHI data untouched.
struct AccountStorage {
    let root: URL
    private let dataFiles = ["timetable.json", "preferences.json", "attendance.json", "customEvents.json"]
    private let ownedFiles = ["timetable.json", "preferences.json", "attendance.json", "customEvents.json", "sync-baseline.json", "activity-log.json", "activity-uploaded.json", "activity-cursor.json", "sync-device.txt"]

    func directory(for uid: String) -> URL {
        let key = SHA256.hash(data: Data(uid.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("Accounts", isDirectory: true).appendingPathComponent(key, isDirectory: true)
    }

    var legacyOwner: String? {
        for name in ["legacy-claimed-by.txt", "sync-owner.txt"] {
            if let value = try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8), !value.isEmpty { return value }
        }
        if let data = try? Data(contentsOf: root.appendingPathComponent("sync-baseline.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return json["owner"] as? String }
        return nil
    }

    var hasUnclaimedLegacy: Bool {
        legacyOwner == nil && FileManager.default.fileExists(atPath: root.appendingPathComponent("timetable.json").path)
    }

    func prepare(for uid: String) throws -> URL {
        guard !uid.isEmpty else { throw SyncFailure.account }
        let target = directory(for: uid)
        let manager = FileManager.default
        guard !manager.fileExists(atPath: target.path) else { return target }
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = target.deletingLastPathComponent().appendingPathComponent(".migration-" + UUID().uuidString)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        if legacyOwner == uid {
            for name in ownedFiles {
                let source = root.appendingPathComponent(name)
                if manager.fileExists(atPath: source.path) { try manager.copyItem(at: source, to: staging.appendingPathComponent(name)) }
            }
        }
        try uid.write(to: staging.appendingPathComponent("account-owner.txt"), atomically: true, encoding: .utf8)
        try manager.moveItem(at: staging, to: target)
        return target
    }

    /// Unowned legacy data is adopted only after the user explicitly chooses to.
    func claimLegacy(for uid: String) throws {
        guard hasUnclaimedLegacy else { throw SyncFailure.invalidData }
        let target = try prepare(for: uid)
        let manager = FileManager.default
        guard dataFiles.allSatisfy({ !manager.fileExists(atPath: target.appendingPathComponent($0).path) }) else {
            throw NSError(domain: "SATHI", code: 10, userInfo: [NSLocalizedDescriptionKey: "This account already has saved data. The older files were kept separately to avoid replacing it."])
        }
        var copied: [URL] = []
        do {
            for name in dataFiles {
                let source = root.appendingPathComponent(name)
                if manager.fileExists(atPath: source.path) {
                    let destination = target.appendingPathComponent(name)
                    try manager.copyItem(at: source, to: destination)
                    copied.append(destination)
                }
            }
            try uid.write(to: root.appendingPathComponent("legacy-claimed-by.txt"), atomically: true, encoding: .utf8)
        } catch {
            for file in copied { try? manager.removeItem(at: file) }
            throw error
        }
    }
}
