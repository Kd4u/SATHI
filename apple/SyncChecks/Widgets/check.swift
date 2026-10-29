import Foundation
@main struct WidgetChecks {
    static func main() throws {
        let formatter = ISO8601DateFormatter()
        func date(_ value: String) -> Date { formatter.date(from: value)! }
        func row(_ id: String, _ start: String) -> WidgetClass {
            let start = date(start)
            return WidgetClass(id: id, subject: id, start: start, end: start.addingTimeInterval(3600), fingerprintTarget: start.addingTimeInterval(-60), proxyWarning: false)
        }
        let now = date("2026-10-27T18:00:00+05:30")
        let rows = [row("tomorrow", "2026-10-28T09:00:00+05:30"), row("ended-today", "2026-10-27T09:00:00+05:30"), row("midnight", "2026-10-27T00:05:00+05:30"), row("past", "2026-10-26T09:00:00+05:30"), row("too-far", "2026-11-03T09:00:00+05:30")]
        let horizon = WidgetDates.horizon(rows, from: now)
        assert(Set(horizon.map(\.id)) == ["midnight", "ended-today", "tomorrow"])
        assert(WidgetDates.classes(horizon, on: now).map(\.id) == ["midnight", "ended-today"])
        assert(WidgetDates.classes(horizon, on: WidgetDates.calendar.date(byAdding: .day, value: 1, to: now)!).map(\.id) == ["tomorrow"])
        assert(!SyncCadence.isDue(lastSync: now.addingTimeInterval(-3599), now: now))
        assert(SyncCadence.isDue(lastSync: now.addingTimeInterval(-3600), now: now))
        assert(SyncCadence.isDue(lastSync: nil, now: now))
        print("Widget and cadence checks passed: IST midnight, ended-today classes retained, next days, seven-day cache horizon, hourly threshold.")
    }
}
