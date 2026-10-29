import Foundation

@main struct JournalChecks {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SATHI-Journal-Checks-" + UUID().uuidString)
        let log = ActivityJournal(directory: root)
        try log.record("excel_imported", details: ["filename": "Term.xlsx", "classes": "20"])
        assert(log.entries.count == 1 && log.pending.count == 1)
        let reopened = ActivityJournal(directory: root)
        assert(reopened.pending.first?.id == log.entries.first?.id)
        assert(reopened.deviceID == log.deviceID)
        try reopened.acknowledge(reopened.pending.map(\.id))
        assert(ActivityJournal(directory: root).pending.isEmpty)
        let remote = ActivityEntry(id: "remote-event", timestamp: Date(), device: "another-device", action: "attendance_changed", details: ["value": "Attended"])
        try reopened.receive([remote, remote])
        assert(reopened.entries.count == 2 && reopened.pending.isEmpty)
        try reopened.advanceCursor(Date(timeIntervalSince1970: 1000))
        assert(ActivityJournal(directory: root).cloudCursor == Date(timeIntervalSince1970: 1000))
        let data = try Data(contentsOf: root.appendingPathComponent("activity-log.json"))
        assert(String(data: data, encoding: .utf8)!.contains("excel_imported"))
        print("Activity JSON checks passed: persistence, offline queue, acknowledgement, remote deduplication, cursor persistence.")
    }
}
