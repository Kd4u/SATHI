import Foundation

@main struct AccountChecks {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SATHI-Accounts-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = Data("{\"saved\":\"original\"}".utf8)
        try data.write(to: root.appendingPathComponent("timetable.json"))
        try "alice".write(to: root.appendingPathComponent("sync-owner.txt"), atomically: true, encoding: .utf8)
        let storage = AccountStorage(root: root)
        let bob = try storage.prepare(for: "bob")
        assert(!FileManager.default.fileExists(atPath: bob.appendingPathComponent("timetable.json").path))
        let alice = try storage.prepare(for: "alice")
        assert(try! Data(contentsOf: alice.appendingPathComponent("timetable.json")) == data)
        assert(try! Data(contentsOf: root.appendingPathComponent("timetable.json")) == data)
        assert(alice != bob)
        let aliceLog = ActivityJournal(directory: alice)
        try aliceLog.record("alice-only")
        assert(ActivityJournal(directory: bob).entries.isEmpty)
        let changed = Data("updated".utf8)
        try changed.write(to: alice.appendingPathComponent("timetable.json"))
        let preparedAgain = try storage.prepare(for: "alice")
        assert(try! Data(contentsOf: preparedAgain.appendingPathComponent("timetable.json")) == changed)
        assert(storage.directory(for: "../bob").deletingLastPathComponent().lastPathComponent == "Accounts")

        let unowned = root.appendingPathComponent("unowned")
        try FileManager.default.createDirectory(at: unowned, withIntermediateDirectories: true)
        try data.write(to: unowned.appendingPathComponent("timetable.json"))
        let old = AccountStorage(root: unowned)
        let carol = try old.prepare(for: "carol")
        assert(old.hasUnclaimedLegacy)
        assert(!FileManager.default.fileExists(atPath: carol.appendingPathComponent("timetable.json").path))
        try old.claimLegacy(for: "carol")
        assert(try! Data(contentsOf: carol.appendingPathComponent("timetable.json")) == data)
        assert(!old.hasUnclaimedLegacy)
        let dave = try old.prepare(for: "dave")
        assert(!FileManager.default.fileExists(atPath: dave.appendingPathComponent("timetable.json").path))
        do { try old.claimLegacy(for: "dave"); fatalError("A second user claimed another account's legacy data") } catch SyncFailure.invalidData { }
        print("Account isolation checks passed: owned migration, unowned opt-in, separate logs, return to existing account, no second claim, safe paths, original data retained.")
    }
}
