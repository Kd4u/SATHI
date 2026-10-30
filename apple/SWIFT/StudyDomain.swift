import Foundation

nonisolated struct StudyPreferences: Codable, Equatable, Hashable, Sendable {
    var didCustomizeAppearance = false
    var appearanceMode: String? = nil
    var glassStyle: String? = nil
    var accent = "blue"
    var glassOpacity = 0.75
    var fontScale = 1.0
    var sounds = true
    var notificationSound = "default"
    var haptics = true
    var reminders = false
    var classCountdown = true
    var liveActivities = false
    var fingerprintLeadMinutes = 15
    var fingerprintTargetMinutes = 1
    var reminderGraceMinutes = 5
    var sheetReminderMinutes = 40
    var firstYearSection = ""
    var programme = "MBA"
    var studentName: String? = nil
    var studentSemester: Int? = nil
    var proofCrosscheck: Bool? = nil
    var campusShortcuts: Bool? = nil
    var manualSelections: [String: [String]]? = nil
}

nonisolated struct ClassProof: Codable, Equatable, Hashable, Sendable {
    var attended: Bool?
    var fingerprint: Bool?
    var signedSheet: Bool?
    var officialDuty = false
    var updatedAt = Date()
}

struct SemesterSummary: Codable, Equatable, Identifiable {
    var id: String
    var number: Int
    var title: String
    var start: String
    var end: String
}

struct ScheduleOverride: Codable, Equatable, Identifiable {
    var id: String
    var date: String
    var start: String
    var end: String
    var title: String
    var cancelled = false
    var added = false
    var semesterID: String? = nil
}

struct StudyWorkspace: Codable, Equatable {
    var preferences = StudyPreferences()
    var proofs: [String: ClassProof] = [:]
    var semesters: [SemesterSummary] = []
    var currentSemesterID = ""
    var overrides: [String: ScheduleOverride] = [:]
    func shouldPublish(hasTimetable: Bool) -> Bool {
        hasTimetable || preferences.didCustomizeAppearance || !proofs.isEmpty || !overrides.isEmpty || !semesters.isEmpty
    }
}

nonisolated struct ClassWindow: Equatable, Hashable, Sendable {
    var id: String
    var subject: String
    var start: Date
    var end: Date

    static func make(id: String, subject: String, date: String, time: String) -> Self? {
        let pattern = try? NSRegularExpression(pattern: #"(\d{1,2})[:.](\d{2})\s*(AM|PM)?"#, options: .caseInsensitive)
        let range = NSRange(time.startIndex..<time.endIndex, in: time)
        let matches = pattern?.matches(in: time, range: range) ?? []
        guard matches.count >= 2 else { return nil }
        func clock(_ match: NSTextCheckingResult) -> String? {
            guard let hr = Range(match.range(at: 1), in: time), let min = Range(match.range(at: 2), in: time), var hour = Int(time[hr]), let minute = Int(time[min]), hour < 24, minute < 60 else { return nil }
            if let ampm = Range(match.range(at: 3), in: time) {
                guard hour >= 1 && hour <= 12 else { return nil }
                hour = hour % 12 + (time[ampm].uppercased() == "PM" ? 12 : 0)
            }
            return String(format: "%02d:%02d", hour, minute)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.isLenient = false
        guard let first = clock(matches[0]), let second = clock(matches[1]),
              let start = formatter.date(from: date + " " + first),
              let end = formatter.date(from: date + " " + second), end > start else { return nil }
        return .init(id: id, subject: subject, start: start, end: end)
    }

    func fingerprintTarget(preferences: StudyPreferences) -> Date {
        start.addingTimeInterval(-Double(preferences.fingerprintTargetMinutes * 60))
    }
    func fingerprintMinutesLeft(at now: Date, preferences: StudyPreferences) -> Int {
        max(0, Int(ceil(fingerprintTarget(preferences: preferences).timeIntervalSince(now) / 60)))
    }
}

nonisolated enum AttendanceRules {
    static func effective(windows: [ClassWindow], proofs: [String: ClassProof], recorded: [String: String], now: Date) -> [String: String] {
        let penalties = penaltyIDs(windows: windows, proofs: proofs, now: now)
        var result = recorded
        for window in windows {
            result[window.id] = status(proof: proofs[window.id], recorded: recorded[window.id], penalized: penalties.contains(window.id), classEnded: window.end <= now)
        }
        return result
    }
    static func penaltyIDs(windows: [ClassWindow], proofs: [String: ClassProof], now: Date) -> Set<String> {
        let ordered = windows.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        var result = Set<String>()
        for (index, window) in ordered.enumerated() {
            guard window.end <= now, let proof = proofs[window.id], !proof.officialDuty,
                  let fingerprint = proof.fingerprint, let sheet = proof.signedSheet,
                  fingerprint != sheet else { continue }
            for later in ordered.dropFirst(index + 1).prefix(3) { result.insert(later.id) }
        }
        return result
    }

    static func status(proof: ClassProof?, recorded: String?, penalized: Bool, classEnded: Bool) -> String? {
        if proof?.officialDuty == true || recorded == "OD" { return "OD" }
        if penalized { return "Missed" }
        guard let proof else { return recorded }
        if proof.attended == false { return "Missed" }
        if proof.attended == true && proof.fingerprint == true && proof.signedSheet == true { return "Attended" }
        if classEnded, proof.fingerprint != nil, proof.signedSheet != nil,
           proof.fingerprint != true || proof.signedSheet != true { return "Missed" }
        return recorded
    }

    static func simple(proofs: [String: ClassProof], recorded: [String: String]) -> [String: String] {
        var result = recorded
        for (id, proof) in proofs {
            if proof.officialDuty { result[id] = "OD" }
            else if let attended = proof.attended { result[id] = attended ? "Attended" : "Missed" }
        }
        return result
    }
    static func hasLiveProxyWarning(proof: ClassProof?, window: ClassWindow, now: Date) -> Bool {
        guard let proof, !proof.officialDuty else { return false }
        return now >= window.start && now < window.end && proof.fingerprint == false
    }
}

struct ArchivedSemester: Codable {
    var report: TimetableReport
    var number: Int
    var selectedKeys: [String]
    var attendance: [String: String]
    var proofRecords: [String: ClassProof]
    var overrides: [String: ScheduleOverride]? = nil
    var semesterID: String
    var section: String? = nil
    var customEvents: [SATHICustomEvent]? = nil
    var minimumAttendance: Int? = nil
    var selectedSessionIDs: [String]? = nil
}


enum ScheduleEdits {
    static func apply(_ sessions: [TimetableSession], overrides: [String: ScheduleOverride], semesterID: String) -> [TimetableSession] {
        var result: [TimetableSession] = []
        for session in sessions {
            guard let edit = overrides[session.id], edit.semesterID == nil || edit.semesterID == semesterID else { result.append(session); continue }
            guard !edit.cancelled else { continue }
            result.append(TimetableSession(id: session.id, date: edit.date, day: session.day, time: edit.start + " – " + edit.end, subject: edit.title.isEmpty ? session.subject : edit.title, section: session.section, teacher: session.teacher, source: session.source))
        }
        for edit in overrides.values where edit.added && !edit.cancelled && edit.semesterID == semesterID && !sessions.contains(where: { $0.id == edit.id }) {
            result.append(TimetableSession(id: edit.id, date: edit.date, day: "", time: edit.start + " – " + edit.end, subject: edit.title, section: "", teacher: "", source: "Added in SATHI"))
        }
        return result.sorted { ($0.date, $0.time, $0.id) < ($1.date, $1.time, $1.id) }
    }
}

struct StudyAsset: Codable, Identifiable, Equatable {
    var id: String
    var kind: String
    var title: String
    var subject: String
    var semesterID: String
    var revision: String
    var baseRevision: String?
    var modifiedAt: Date
    var pending: Bool
}

struct NotebookPage: Codable, Equatable {
    var text = ""
    var drawing = Data()
    var drawingPreview: Data? = nil
}

