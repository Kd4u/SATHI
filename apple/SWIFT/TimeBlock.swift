
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
