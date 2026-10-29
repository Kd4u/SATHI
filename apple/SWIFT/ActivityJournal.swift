import Foundation

struct ActivityEntry: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let device: String
    let action: String
    let details: [String: String]
}

@MainActor
final class ActivityJournal {
    private let directory: URL
    private(set) var entries: [ActivityEntry]
    private var uploaded: Set<String>
    let deviceID: String
    private(set) var cloudCursor: Date?

    init(directory: URL) {
        self.directory = directory
        func read<T: Decodable>(_ name: String, as: T.Type) -> T? {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        cloudCursor = read("activity-cursor.json", as: Date.self)
        entries = read("activity-log.json", as: [ActivityEntry].self) ?? []
        uploaded = Set(read("activity-uploaded.json", as: [String].self) ?? [])
        if let data = try? Data(contentsOf: directory.appendingPathComponent("sync-device.txt")), let id = String(data: data, encoding: .utf8) { deviceID = id }
        else {
            deviceID = UUID().uuidString
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? deviceID.write(to: directory.appendingPathComponent("sync-device.txt"), atomically: true, encoding: .utf8)
        }
    }

    var pending: [ActivityEntry] { entries.filter { !uploaded.contains($0.id) } }

    func record(_ action: String, details: [String: String] = [:]) throws {
        let entry = ActivityEntry(id: UUID().uuidString, timestamp: Date(), device: deviceID, action: action, details: details)
        let next = entries + [entry]
        try save(next, name: "activity-log.json")
        entries = next
    }

    func advanceCursor(_ date: Date) throws {
        try save(date, name: "activity-cursor.json")
        cloudCursor = date
    }

    func acknowledge(_ ids: [String]) throws {
        let next = uploaded.union(ids)
        try save(next.sorted(), name: "activity-uploaded.json")
        uploaded = next
    }

    func receive(_ incoming: [ActivityEntry]) throws {
        var byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        for entry in incoming { byID[entry.id] = entry }
        let next = byID.values.sorted { ($0.timestamp, $0.id) < ($1.timestamp, $1.id) }
        try save(next, name: "activity-log.json")
        entries = next
        try acknowledge(incoming.map(\.id))
    }

    private func save<T: Encodable>(_ value: T, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
