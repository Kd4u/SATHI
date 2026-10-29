import Foundation

// Separate from existing JSON models so adding sync does not migrate local data.
struct SyncSnapshot: Codable, Equatable {
    var records: [String: Data] = [:]

    static func merge(base: Self, local: Self, remote: Self) throws -> Self {
        var result = remote
        for key in Set(base.records.keys).union(local.records.keys) {
            let before = base.records[key]
            let after = local.records[key]
            guard before != after else { continue }
            let cloud = remote.records[key]
            guard cloud == before || cloud == after else {
                throw SyncFailure.conflict(key)
            }
            result.records[key] = after
        }
        return result
    }
}

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
