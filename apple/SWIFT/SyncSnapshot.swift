import Foundation

// Separate from existing JSON models so adding sync does not migrate local data.
struct SyncSnapshot: Codable, Equatable {
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

enum SyncConflictResolution { case local, remote }

enum SyncFailure: LocalizedError {
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

struct SyncSelection: Codable { let semester: Int?; let keys: [String]; var minimumAttendance: Int? = nil }
nonisolated enum SyncCadence {
    static func isDue(lastSync: Date?, now: Date) -> Bool {
        guard let lastSync else { return true }
        return now.timeIntervalSince(lastSync) >= 3600
    }
}
