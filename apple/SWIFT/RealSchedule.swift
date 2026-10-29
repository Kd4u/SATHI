
import Foundation

enum ScheduleItemType: String, Codable {
    case lecture
    case event
    case quiz
    case exam
    case holiday
    case other
}

enum ScheduleSource: String, Codable {
    case excel
    case xml
    case csv
    case manual
    case announcement
    case other
}

struct TimeBlock: Identifiable, Codable {
    var id: UUID = UUID()
    var type: ScheduleItemType
    var subject: String
    var teacher: String?
    var section: String?
    var startDateTime: Date
    var endDateTime: Date
    var venue: String?
    var source: ScheduleSource
    var notes: String?
}

struct RealSchedule: Codable {
    var version: Int = 1
    var semester: String = ""
    var importedAt: Date = Date()
    var items: [TimeBlock] = []

    func saveLocally() throws -> URL {
        let directory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let url = directory.appendingPathComponent(
            "RealSchedule.json"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)

        return url
    }

    static func loadLocally() throws -> RealSchedule {
        let directory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let url = directory.appendingPathComponent(
            "RealSchedule.json"
        )

        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(
            RealSchedule.self,
            from: data
        )
    }
}
