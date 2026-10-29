import Foundation
import WidgetKit
#if os(iOS)
import BackgroundTasks
#endif

extension Notification.Name { static let sathiStudyAssetsChanged = Notification.Name("SATHIStudyAssetsChanged"); static let sathiBackgroundSync = Notification.Name("SATHIBackgroundSync") }
struct BackgroundSyncUpdate { let uid: String; let base: SyncSnapshot; let remote: SyncSnapshot }

@MainActor enum BackgroundSync {
    static var liveUID: String?
    static var liveApply: ((SyncSnapshot, SyncSnapshot) throws -> Void)?
    static let identifier = "com.karandeepsinghpersonalteam.SWIFT.refresh"
    static func register(cloud: CloudSyncStore) {
        #if os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            let operation = Task { @MainActor in
                schedule()
                let success = await run(cloud: cloud)
                task.setTaskCompleted(success: success)
            }
            task.expirationHandler = { operation.cancel() }
        }
        #endif
    }
    static func schedule() {
        #if os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }
    private struct Preferences: Codable {
        var semester: Int?; var keys: [String]; var page: String; var minimumAttendance: Int?
    }
    static func run(cloud: CloudSyncStore) async -> Bool {
        guard let uid = cloud.accountID, cloud.signedIn, !cloud.busy else { return false }
        guard SyncCadence.isDue(lastSync: cloud.lastSync, now: Date()) else { return true }
        let folder = cloud.dataDirectory
        let study = StudyStoreRegistry.store(for: uid)
        do {
            try study.configure(directory: folder, uid: uid, journal: cloud.journal)
            func snapshot() throws -> SyncSnapshot {
                var result = SyncSnapshot(); let encoder = JSONEncoder()
                if let data = try? Data(contentsOf: folder.appendingPathComponent("timetable.json")) {
                    let report = try JSONDecoder().decode(TimetableReport.self, from: data)
                    result.records["timetable"] = try encoder.encode(report)
                    let prefs = try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: folder.appendingPathComponent("preferences.json")))
                    result.records["selection"] = try encoder.encode(SyncSelection(semester: prefs.semester, keys: prefs.keys, minimumAttendance: prefs.minimumAttendance ?? 80))
                }
                if let data = try? Data(contentsOf: folder.appendingPathComponent("attendance.json")) {
                    for (id, value) in try JSONDecoder().decode([String: String].self, from: data) { result.records["attendance:" + id] = try encoder.encode(value) }
                }
                if let data = try? Data(contentsOf: folder.appendingPathComponent("customEvents.json")) {
                    for event in try JSONDecoder().decode([SATHICustomEvent].self, from: data) { result.records["event:" + event.id.uuidString] = try encoder.encode(event) }
                }
                if study.workspace.shouldPublish(hasTimetable: result.records["timetable"] != nil) {
                    for (key, data) in try study.workspaceRecords() { result.records[key] = data }
                }
                return result
            }
            let captured = try snapshot()
            await cloud.sync(local: captured) { downloaded in
                guard !Task.isCancelled, cloud.accountID == uid else { throw SyncFailure.account }
                // Re-read locally saved edits before applying an in-flight cloud response.
                try study.configure(directory: folder, uid: uid, journal: cloud.journal)
                let merged = try SyncSnapshot.merge(base: captured, local: snapshot(), remote: downloaded)
                if liveUID == uid, let liveApply {
                    try liveApply(captured, merged)
                    try study.configure(directory: folder, uid: uid, journal: cloud.journal)
                    return
                }
                let decoder = JSONDecoder(); let encoder = JSONEncoder()
                let report = try merged.records["timetable"].map { try decoder.decode(TimetableReport.self, from: $0) }
                let selection = try merged.records["selection"].map { try decoder.decode(SyncSelection.self, from: $0) }
                guard (report == nil) == (selection == nil) else { throw SyncFailure.invalidData }
                var attendance: [String: String] = [:]; var events: [SATHICustomEvent] = []
                for (key, data) in merged.records {
                    if key.hasPrefix("attendance:") { attendance[String(key.dropFirst(11))] = try decoder.decode(String.self, from: data) }
                    else if key.hasPrefix("event:") {
                        let event = try decoder.decode(SATHICustomEvent.self, from: data)
                        guard key == "event:" + event.id.uuidString else { throw SyncFailure.invalidData }
                        events.append(event)
                    }
                    else if key != "timetable" && key != "selection" && !key.hasPrefix("study:") { throw SyncFailure.invalidData }
                }
                let workspace = try study.decodeWorkspace(merged.records)
                var files = ["attendance.json": try encoder.encode(attendance), "customEvents.json": try encoder.encode(events), "Study/workspace.json": try encoder.encode(workspace)]
                if let report, let selection {
                    files["timetable.json"] = try encoder.encode(report)
                    files["preferences.json"] = try encoder.encode(Preferences(semester: selection.semester, keys: selection.keys, page: "timetable", minimumAttendance: selection.minimumAttendance))
                }
                let names = ["attendance.json", "customEvents.json", "Study/workspace.json", "timetable.json", "preferences.json"]
                let backup = folder.appendingPathComponent("SyncBackups/" + UUID().uuidString)
                var prior: [String: Data] = [:]
                for name in names {
                    if let data = try? Data(contentsOf: folder.appendingPathComponent(name)) {
                        prior[name] = data
                        let destination = backup.appendingPathComponent(name)
                        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: destination, options: .atomic)
                    }
                }
                do {
                    for name in names {
                        let destination = folder.appendingPathComponent(name)
                        if let data = files[name] {
                            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try data.write(to: destination, options: .atomic)
                        } else if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                    }
                } catch {
                    for name in names {
                        if let data = prior[name] { try? data.write(to: folder.appendingPathComponent(name), options: .atomic) }
                        else { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
                    }
                    throw error
                }
                study.workspace = workspace
                NotificationCenter.default.post(name: .sathiBackgroundSync, object: BackgroundSyncUpdate(uid: uid, base: captured, remote: merged))
            }
            guard !Task.isCancelled, cloud.accountID == uid else { return false }
            await study.sync()
            guard !Task.isCancelled, cloud.accountID == uid else { return false }
            if let data = try? Data(contentsOf: folder.appendingPathComponent("timetable.json")), let report = try? JSONDecoder().decode(TimetableReport.self, from: data),
               let prefsData = try? Data(contentsOf: folder.appendingPathComponent("preferences.json")), let prefs = try? JSONDecoder().decode(Preferences.self, from: prefsData) {
                let section = study.workspace.preferences.firstYearSection.uppercased()
                let rows = report.sessions.filter { row in
                    if (prefs.semester ?? 0) >= 4 { return prefs.keys.contains(row.subject + "|" + row.section) }
                    return section.isEmpty || row.section.isEmpty || row.section.uppercased() == section
                }
                let effective = ScheduleEdits.apply(rows, overrides: study.workspace.overrides, semesterID: study.workspace.currentSemesterID)
                let widgets = effective.compactMap { row -> WidgetClass? in
                    guard let window = ClassWindow.make(id: row.id, subject: row.subject, date: row.date, time: row.time) else { return nil }
                    return WidgetClass(id: row.id, subject: row.subject, start: window.start, end: window.end, fingerprintTarget: window.fingerprintTarget(preferences: study.workspace.preferences), proxyWarning: AttendanceRules.hasLiveProxyWarning(proof: study.workspace.proofs[row.id], window: window, now: Date()))
                }
                try SharedClassStorage.save(WidgetSchedule(classes: WidgetDates.horizon(widgets + EventPresentation.widgetRows(report.events.map { SATHICommandEvent(id: "excel-" + $0.source + "-" + $0.time, date: $0.date, title: $0.title, time: $0.time) } + ((try? JSONDecoder().decode([SATHICustomEvent].self, from: Data(contentsOf: folder.appendingPathComponent("customEvents.json")))) ?? []).map { SATHICommandEvent(id: "custom-" + $0.id.uuidString, date: $0.date, title: $0.title, time: $0.start + " – " + $0.end) }), from: Date()), updatedAt: Date()))
                WidgetCenter.shared.reloadAllTimelines()
            }
            NotificationCenter.default.post(name: .sathiStudyAssetsChanged, object: uid)
            return cloud.status == "Up to date"
        } catch { return false }
    }
}
