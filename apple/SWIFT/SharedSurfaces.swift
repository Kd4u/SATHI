import Foundation
import Security
import AppIntents
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

nonisolated struct WidgetClass: Codable, Hashable, Identifiable {
    var id: String
    var subject: String
    var start: Date
    var end: Date
    var fingerprintTarget: Date
    var proxyWarning: Bool
    var eventKind: String? = nil
}
nonisolated struct WidgetSchedule: Codable {
    var classes: [WidgetClass]
    var updatedAt: Date
}

nonisolated enum SharedClassStorage {
    private static let service = "SATHI.WidgetSchedule"
    private static var group: String? { Bundle.main.object(forInfoDictionaryKey: "SATHISharedKeychainGroup") as? String }
    private static var query: [String: Any] {
        var value: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "schedule"]
        if let group, !group.contains("$(") { value[kSecAttrAccessGroup as String] = group }
        return value
    }
    static func save(_ schedule: WidgetSchedule?) throws {
        guard let schedule else { SecItemDelete(query as CFDictionary); return }
        let data = try JSONEncoder().encode(schedule)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var value = query
            value[kSecValueData as String] = data
            value[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(value as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Widget sharing could not be configured with this signing profile."]) }
    }
    static func load() -> WidgetSchedule? {
        var value = query; value[kSecReturnData as String] = true; value[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(value as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(WidgetSchedule.self, from: data)
    }
}

struct NextSathiClassIntent: AppIntent {
    static let title: LocalizedStringResource = "Next SATHI class"
    static let description = IntentDescription("Find the next class in your signed-in SATHI timetable.")
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let next = SharedClassStorage.load()?.classes.filter { $0.end > Date() }.sorted { $0.start < $1.start }.first
        let answer = next.map { "\($0.subject), \($0.start.formatted(date: .abbreviated, time: .shortened))" } ?? "Open SATHI and refresh your timetable to make your next class available."
        return .result(value: answer)
    }
}

struct OpenSathiTimetableIntent: AppIntent {
    static let title: LocalizedStringResource = "Open SATHI timetable"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}
struct SathiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NextSathiClassIntent(), phrases: ["Next class in \(.applicationName)", "What's next in \(.applicationName)"], shortTitle: "Next class", systemImageName: "calendar")
        AppShortcut(intent: OpenSathiTimetableIntent(), phrases: ["Open my timetable in \(.applicationName)"], shortTitle: "Timetable", systemImageName: "calendar.day.timeline.left")
    }
}

#if canImport(ActivityKit) && os(iOS)
nonisolated struct SathiClassActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var proxyWarning: Bool
        var fingerprintDone: Bool
    }
    var subject: String
    var start: Date
    var end: Date
    var fingerprintTarget: Date
    var classID: String
}
#endif

nonisolated enum WidgetDates {
    static var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Asia/Kolkata")!; return value }
    static func classes(_ classes: [WidgetClass], on date: Date) -> [WidgetClass] {
        classes.filter { calendar.isDate($0.start, inSameDayAs: date) }.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }
    static func horizon(_ classes: [WidgetClass], from date: Date) -> [WidgetClass] {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        return classes.filter { $0.start >= start && $0.start < end }.sorted { $0.start < $1.start }
    }
}
