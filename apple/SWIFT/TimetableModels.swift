import Foundation

nonisolated struct TimetableSession: Codable, Identifiable, Sendable {
    let id: String
    let date: String
    let day: String
    let time: String
    let subject: String
    let section: String
    let teacher: String
    let source: String
}

nonisolated struct TimetableSubject: Codable, Sendable {
    let key: String
    let name: String
    let count: Int
    let credits: Double
}

nonisolated struct TimetableEvent: Codable, Sendable {
    let date: String
    let time: String
    let title: String
    let source: String
    var id: String? = nil
}

nonisolated struct TimetableReport: Codable, Sendable {
    var importRevision: Int? = nil
    let workbook: String
    let sessions: [TimetableSession]
    let subjects: [TimetableSubject]
    let events: [TimetableEvent]
    let warnings: [String]
}


struct SATHICustomEvent: Identifiable, Codable {
    var id = UUID()
    var date: String
    var start: String
    var end: String
    var title: String
    var type: String
    var subject: String
    var notes: String
}


// Infer a section only from explicit labels, never from an arbitrary subject suffix.
nonisolated enum TimetableSection {
    static func label(in text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.count == 1, cleaned.range(of: "^[A-Z]$", options: .regularExpression) != nil { return cleaned }
        let regex = try? NSRegularExpression(pattern: #"(?i)(?:\b|_)sec(?:tion)?\.?\s*[-:]?\s*([A-Z])\b"#)
        guard let match = regex?.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)), let range = Range(match.range(at: 1), in: text) else { return "" }
        return String(text[range]).uppercased()
    }
}

// Import-only normalization: never rewrite saved class IDs or historic attendance.
nonisolated enum TimetableIdentity {
    static func course(_ raw: String) -> (String, String) {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Explicit hyphenated lecture counters; keep meaningful names such as Industry 4.0 and Accounting II.
        name = name.replacingOccurrences(of: #"\s+[-–—]\s*\d{1,3}\s*$"#, with: "", options: .regularExpression)
        let pattern = #"(?i)\(?\s*\bsec(?:tion)?\.?\s*[-:]?\s*([A-Z])\b\s*\)?"#
        var section = ""
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..<name.endIndex, in: name)),
           let letter = Range(match.range(at: 1), in: name), let whole = Range(match.range, in: name) {
            section = String(name[letter]).uppercased()
            name.removeSubrange(whole)
        }
        name = name.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return (name, section)
    }
    static func programme(source: String) -> String {
        let sheet = source.components(separatedBy: "!")[0].uppercased()
        if sheet.contains("HHM") { return "HHM" }
        if sheet.contains("DBAI") { return "DBAI" }
        if sheet.contains("DBM") { return "DBM" }
        return "MBA"
    }
    // Return repaired identities alongside an exact old-to-new selection map.
    // Dates, cell IDs, instructor names and attendance references remain untouched.
    static func repair(_ report: TimetableReport) -> (report: TimetableReport, keys: [String: String], changed: Bool) {
        let inlineSheets = Set(report.sessions.filter { !course($0.subject).1.isEmpty }.map { $0.source.components(separatedBy: "!")[0] })
        var keys: [String: String] = [:]
        var changed = false
        let rows = report.sessions.map { row in
            let (name, inline) = course(row.subject)
            let sheet = row.source.components(separatedBy: "!")[0]
            let section = !inline.isEmpty ? inline : (inlineSheets.contains(sheet) ? "" : row.section)
            keys[row.subject + "|" + row.section] = name + "|" + section
            changed = changed || row.subject != name || row.section != section
            return TimetableSession(id: row.id, date: row.date, day: row.day, time: row.time, subject: name, section: section, teacher: row.teacher, source: row.source)
        }
        guard changed else { return (report, keys, false) }
        var result = TimetableReport(workbook: report.workbook, sessions: rows, subjects: subjects(rows), events: report.events, warnings: report.warnings)
        result.importRevision = report.importRevision
        return (result, keys, true)
    }
    /// A same-timetable supplement may add missing cells, but cannot remove or
    /// reinterpret existing classes. It must retain every attendance identifier.
    static func canSupplement(_ existing: TimetableReport, with incoming: TimetableReport) -> Bool {
        guard !existing.sessions.isEmpty, incoming.sessions.count > existing.sessions.count else { return false }
        let rows = Dictionary(incoming.sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard rows.count == incoming.sessions.count else { return false }
        return existing.sessions.allSatisfy { old in
            guard let new = rows[old.id] else { return false }
            return old.date == new.date && old.source == new.source && old.time == new.time &&
                old.subject == new.subject && old.section == new.section
        }
    }
    static func subjects(_ sessions: [TimetableSession]) -> [TimetableSubject] {
        Dictionary(grouping: sessions, by: { $0.subject + "|" + $0.section }).map { key, rows in
            let first = rows[0], count = rows.count
            let credits: Double = count == 20 ? 3 : count == 15 ? 2.25 : count == 10 ? 1.5 : count == 7 ? 1 : 0
            return TimetableSubject(key: key, name: first.subject + (first.section.isEmpty ? "" : " (Sec \(first.section))"), count: count, credits: credits)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
