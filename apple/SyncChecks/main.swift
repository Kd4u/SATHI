import Foundation
func snapshot(_ values: [String: String]) -> SyncSnapshot { SyncSnapshot(records: values.mapValues { Data($0.utf8) }) }
let base = snapshot(["a":"old", "b":"old"])
let merged = try SyncSnapshot.merge(base: base, local: snapshot(["a":"new", "b":"old"]), remote: snapshot(["a":"old", "b":"remote"]))
assert(merged == snapshot(["a":"new", "b":"remote"]))
assert(try! SyncSnapshot.merge(base: base, local: snapshot(["b":"old"]), remote: base) == snapshot(["b":"old"]))
do { _ = try SyncSnapshot.merge(base: base, local: snapshot(["a":"local", "b":"old"]), remote: snapshot(["a":"remote", "b":"old"])); fatalError("Conflict was overwritten") } catch SyncFailure.conflict { }
do { _ = try SyncSnapshot.merge(base: base, local: snapshot(["b":"old"]), remote: snapshot(["a":"remote", "b":"old"])); fatalError("Delete conflict was overwritten") } catch SyncFailure.conflict { }
assert(try! SyncSnapshot.merge(base: .init(), local: .init(), remote: base) == base)
assert(try! SyncSnapshot.merge(base: base, local: base, remote: .init()) == .init())
print("Sync merge checks passed: independent edits, deletions, conflicts, empty device, remote deletion.")
