import Foundation

// Separate from existing JSON models so adding sync does not migrate local data.
nonisolated struct SyncSnapshot: Codable, Equatable {
    var records: [String: Data] = [:]

    static func equivalent(_ lhs: Data?, _ rhs: Data?) -> Bool {
        if lhs == rhs { return true }
        guard let lhs, let rhs,
              let left = try? JSONSerialization.jsonObject(with: lhs, options: [.fragmentsAllowed]),
              let right = try? JSONSerialization.jsonObject(with: rhs, options: [.fragmentsAllowed]),
              let a = try? JSONSerialization.data(withJSONObject: left, options: [.sortedKeys, .fragmentsAllowed]),
              let b = try? JSONSerialization.data(withJSONObject: right, options: [.sortedKeys, .fragmentsAllowed]) else { return false }
        return a == b
    }

    /// Only repair a verified strict subset; a different semester or edited class is never auto-replaced.
    static func completeTimetable(_ lhs: Data?, _ rhs: Data?) -> Data? {
        guard let lhs, let rhs,
              let a = try? JSONSerialization.jsonObject(with: lhs) as? [String: Any],
              let b = try? JSONSerialization.jsonObject(with: rhs) as? [String: Any],
              let ar = a["sessions"] as? [[String: Any]], let br = b["sessions"] as? [[String: Any]],
              !ar.isEmpty, !br.isEmpty, ar.count != br.count else { return nil }
        let newer = ar.count > br.count ? a : b, older = ar.count > br.count ? b : a
        guard (newer["importRevision"] as? Int ?? 0) >= 2, (older["importRevision"] as? Int ?? 0) < 2 else { return nil }
        let more = ar.count > br.count ? ar : br, less = ar.count > br.count ? br : ar
        var index: [String: [String: Any]] = [:]
        for row in more {
            guard let id = row["id"] as? String, index[id] == nil else { return nil }
            index[id] = row
        }
        let fields = ["id", "date", "time", "subject", "section", "source"]
        guard less.allSatisfy({ old in
            guard let id = old["id"] as? String, let new = index[id] else { return false }
            return fields.allSatisfy { (old[$0] as? String) != nil && (old[$0] as? String) == (new[$0] as? String) }
        }) else { return nil }
        return ar.count > br.count ? lhs : rhs
    }

    static func merge(base: Self, local: Self, remote: Self, resolving: SyncConflictResolution? = nil) throws -> Self {
        var result = remote
        for key in Set(base.records.keys).union(local.records.keys).sorted() {
            let before = base.records[key]
            let after = local.records[key]
            guard !equivalent(before, after) else { continue }
            let cloud = remote.records[key]
            guard equivalent(cloud, before) || equivalent(cloud, after) else {
                switch resolving {
                case .local: result.records[key] = after; continue
                case .remote: continue
                case nil: throw SyncFailure.conflict(key)
                }
            }
            result.records[key] = after
        }
        // A timetable and its selected subjects/semester must travel together.
        let key = "timetable"
        if let resolving, !equivalent(base.records[key], local.records[key]),
           !equivalent(remote.records[key], base.records[key]),
           !equivalent(remote.records[key], local.records[key]) {
            let source = resolving == .local ? local : remote
            for related in ["timetable", "selection", "study:semesters", "study:preferences"] {
                result.records[related] = source.records[related]
            }
        }
        return result
    }
}

/// A conflict in one record must not prevent independent attendance from syncing.
nonisolated struct SyncExchange: Codable {
    var cloud: SyncSnapshot
    var local: SyncSnapshot
    var checkpoint: SyncSnapshot
    var conflicts: [String]

    static func prepare(base: SyncSnapshot, local: SyncSnapshot, remote: SyncSnapshot,
                        resolving: SyncConflictResolution? = nil) throws -> Self {
        var local = local, remote = remote
        if let complete = SyncSnapshot.completeTimetable(local.records["timetable"], remote.records["timetable"]) {
            local.records["timetable"] = complete; remote.records["timetable"] = complete
        }
        if let resolving {
            let merged = try SyncSnapshot.merge(base: base, local: local, remote: remote, resolving: resolving)
            return Self(cloud: merged, local: merged, checkpoint: merged, conflicts: [])
        }
        let changed = Set(base.records.keys).union(local.records.keys).filter {
            !SyncSnapshot.equivalent(base.records[$0], local.records[$0])
        }
        var blocked = Set(changed.filter {
            !SyncSnapshot.equivalent(remote.records[$0], base.records[$0]) &&
            !SyncSnapshot.equivalent(remote.records[$0], local.records[$0])
        })
        if blocked.contains("timetable") {
            blocked.formUnion(["timetable", "selection", "study:semesters", "study:preferences"])
        }
        var cloud = remote
        for key in changed where !blocked.contains(key) { cloud.records[key] = local.records[key] }
        var applied = cloud, checkpoint = cloud
        for key in blocked {
            applied.records[key] = local.records[key]
            checkpoint.records[key] = base.records[key]
        }
        return Self(cloud: cloud, local: applied, checkpoint: checkpoint, conflicts: blocked.sorted())
    }
}

nonisolated enum SyncConflictResolution { case local, remote }

nonisolated enum SyncFailure: LocalizedError {
    case conflict(String), configuration, account, oversized, invalidData
    var errorDescription: String? {
        switch self {
        case .conflict(let key): return "Both devices changed \(key). Your local data is safe. Resolve the conflicting change before retrying."
        case .configuration: return "Cloud sync needs the Firebase app configuration. Changes remain saved on this device."
        case .account: return "Sign in with the same SATHI account on each device."
        case .oversized: return "This timetable exceeds the sync size limit. Your local copy is safe."
        case .invalidData: return "Cloud data could not be read. Your local copy has not been replaced."
        }
    }
}

nonisolated struct SyncSelection: Codable { let semester: Int?; let keys: [String]; var minimumAttendance: Int? = nil }
nonisolated enum SyncCadence {
    static func isDue(lastSync: Date?, now: Date) -> Bool {
        guard let lastSync else { return true }
        return now.timeIntervalSince(lastSync) >= 3600
    }
}
