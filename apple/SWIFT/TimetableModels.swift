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

struct TimetableSubject: Codable {
    let key: String
    let name: String
    let count: Int
    let credits: Double
}

struct TimetableEvent: Codable {
    let date: String
    let time: String
    let title: String
    let source: String
}

struct TimetableReport: Codable {
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
        let regex = try? NSRegularExpression(pattern: #"(?i)\bsec(?:tion)?\.?\s*[-:]?\s*([A-Z])\b"#)
        guard let match = regex?.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)), let range = Range(match.range(at: 1), in: text) else { return "" }
        return String(text[range]).uppercased()
    }
}
