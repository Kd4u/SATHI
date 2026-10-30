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

let jsonBase = snapshot(["timetable": "{\"a\":1,\"b\":2}"])
let reordered = snapshot(["timetable": "{\"b\":2,\"a\":1}"])
let jsonRemote = snapshot(["timetable": "{\"a\":1,\"b\":3}"])
assert(try! SyncSnapshot.merge(base: jsonBase, local: reordered, remote: jsonRemote) == jsonRemote)
assert(try! SyncSnapshot.merge(base: .init(), local: jsonBase, remote: reordered) == jsonBase)
print("Cross-client JSON order checks passed; real conflicts remain protected.")

let conflictsBase = snapshot(["a":"old", "b":"old", "c":"old"])
let conflictsLocal = snapshot(["a":"mine", "b":"old", "c":"local"])
let conflictsRemote = snapshot(["a":"cloud", "b":"remote", "c":"old"])
assert(try! SyncSnapshot.merge(base: conflictsBase, local: conflictsLocal, remote: conflictsRemote, resolving: .local) == snapshot(["a":"mine", "b":"remote", "c":"local"]))
assert(try! SyncSnapshot.merge(base: conflictsBase, local: conflictsLocal, remote: conflictsRemote, resolving: .remote) == snapshot(["a":"cloud", "b":"remote", "c":"local"]))
print("Explicit conflict choice preserves independent edits on both devices.")

let bundledBase = snapshot(["timetable":"old", "selection":"old subjects", "attendance:1":"old"])
let bundledLocal = snapshot(["timetable":"mine", "selection":"my subjects", "attendance:1":"old"])
let bundledRemote = snapshot(["timetable":"cloud", "selection":"old subjects", "attendance:1":"remote mark"])
let bundleChoice = try SyncSnapshot.merge(base: bundledBase, local: bundledLocal, remote: bundledRemote, resolving: .remote)
assert(bundleChoice == bundledRemote)
print("Timetable conflict selection stays aligned with its semester/subjects.")
