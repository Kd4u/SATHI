import Foundation

nonisolated struct NotebookColor: Codable, Equatable, Hashable, Sendable {
    var red: Double; var green: Double; var blue: Double
    static let white = Self(red: 1, green: 1, blue: 1)
    static let ink = Self(red: 0.12, green: 0.16, blue: 0.21)
    static let blue = Self(red: 0.18, green: 0.42, blue: 0.72)
}
nonisolated enum NotebookPaper: String, Codable, CaseIterable, Sendable {
    case ruled, blank, grid, dotted, cornell, checklist, custom
    var title: String { rawValue.capitalized }
}
nonisolated struct PaperConfiguration: Codable, Equatable, Sendable {
    var template: NotebookPaper = .ruled
    var size = "A4"
    var landscape = false
    var customWidth = 595.0
    var customHeight = 842.0
    var background = NotebookColor.white
    var ruleColor = NotebookColor(red: 0.65, green: 0.75, blue: 0.85)
    var backgroundOpacity = 1.0
    var spacing = 28.0
    var gridSpacing = 24.0
    var dotSpacing = 20.0
    var margin = 42.0
    var width: Double { landscape ? baseHeight : baseWidth }
    var height: Double { landscape ? baseWidth : baseHeight }
    private var baseWidth: Double { switch size { case "A5": 420; case "Letter": 612; case "Custom": min(2400, max(200, customWidth)); default: 595 } }
    private var baseHeight: Double { switch size { case "A5": 595; case "Letter": 792; case "Custom": min(3200, max(200, customHeight)); default: 842 } }
    var safeSpacing: Double { min(100, max(8, spacing)) }
    var safeMargin: Double { min(min(width, height) / 3, max(10, margin)) }
}
nonisolated struct NotebookTextObject: Codable, Equatable, Identifiable, Sendable {
    var id = UUID().uuidString
    var text = ""
    var x = 48.0; var y = 70.0
    var width = 340.0; var height = 160.0
    var fontSize = 18.0
    var bold = false; var italic = false; var underline = false
    var alignment = "left"
    var color = NotebookColor.ink
}
nonisolated struct NotebookPageDocument: Codable, Equatable, Sendable {
    var version = 1
    var id: String
    var notebookID: String
    var paper = PaperConfiguration()
    var drawing = Data()
    var textObjects: [NotebookTextObject] = []
    var modifiedAt = Date()
    var hasContent: Bool { !drawing.isEmpty || textObjects.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}
nonisolated struct NotebookPageSize: Codable, Equatable, Sendable { var width: Double; var height: Double }

nonisolated struct NotebookManifest: Codable, Equatable, Identifiable, Sendable {
    var version = 1
    var id = UUID().uuidString
    var title = "Quick book"
    var subject = ""
    var semesterID = ""
    var folder = ""
    var coverStyle = "linen"
    var coverColor = NotebookColor.blue
    var paper = PaperConfiguration()
    var pageIDs: [String] = []
    var pageSizes: [String: NotebookPageSize] = [:]
    var importedLegacyIDs: [String] = []
    var removedPageIDs: [String] = []
    var modifiedAt = Date()
    var deletedAt: Date?
}
nonisolated enum NotebookPageOrder {
    static func moving(_ ids: [String], from: Int, to: Int) -> [String] {
        guard ids.indices.contains(from), ids.indices.contains(to), from != to else { return ids }
        var copy = ids; let value = copy.remove(at: from); copy.insert(value, at: to); return copy
    }
    static func selection(_ value: String, count: Int) throws -> [Int] {
        var result = Set<Int>()
        for part in value.split(separator: ",") {
            let range = part.trimmingCharacters(in: .whitespaces).split(separator: "-")
            guard let first = range.first.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }), first > 0 else { throw NotebookFailure.invalidRange }
            let last = range.count == 2 ? Int(range[1].trimmingCharacters(in: .whitespaces)) : first
            guard range.count <= 2, let last, last >= first, last <= count else { throw NotebookFailure.invalidRange }
            for number in first...last { result.insert(number - 1) }
        }
        guard !result.isEmpty else { throw NotebookFailure.invalidRange }
        return result.sorted()
    }
}
nonisolated enum NotebookFailure: LocalizedError {
    case invalidRange, missingPage, changedPage
    var errorDescription: String? {
        switch self {
        case .invalidRange: "Enter existing page numbers, such as 1–3, 5."
        case .missingPage: "This page is not downloaded yet. Use Sync to retrieve it."
        case .changedPage: "This page changed elsewhere. Your version was kept as a separate page."
        }
    }
}
