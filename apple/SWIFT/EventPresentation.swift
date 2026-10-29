import Foundation

nonisolated struct SATHICommandEvent: Identifiable, Sendable {
    let id: String
    let date: String
    let title: String
    let time: String
}

nonisolated enum EventPresentation {
    static func key(_ title: String) -> String {
        title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func isDayLabel(_ title: String) -> Bool {
        let value = key(title)
        return value.contains("end term") || value.contains("endsem") || value.contains("mid term") || value.contains("midsem") || value.contains("holiday") || value.contains("vacation") || value == "diwali" || value == "term break"
    }
    static func display(_ title: String) -> String {
        let value = key(title)
        if value == "end term examinations" || value == "end term examination" { return "End-term examinations" }
        if value == "mid term examinations" || value == "mid term examination" { return "Mid-term examinations" }
        return title == title.uppercased() ? title.localizedCapitalized : title
    }
    static func consolidate(_ events: [SATHICommandEvent]) -> [SATHICommandEvent] {
        var result: [SATHICommandEvent] = []
        let groups = Dictionary(grouping: events) { event in
            if !event.id.hasPrefix("custom-") && isDayLabel(event.title) { return event.date + "|" + key(event.title) }
            return event.id
        }
        for rows in groups.values {
            guard let first = rows.first else { continue }
            if rows.count > 1 && isDayLabel(first.title) {
                result.append(.init(id: "day-marker-" + first.date + "-" + key(first.title), date: first.date, title: display(first.title), time: "All day"))
            } else {
                result.append(.init(id: first.id, date: first.date, title: display(first.title), time: first.time))
            }
        }
        return result.sorted { ($0.date, $0.time, $0.title) < ($1.date, $1.time, $1.title) }
    }
    static func widgetRows(_ events: [SATHICommandEvent]) -> [WidgetClass] {
        consolidate(events).compactMap { event in
            let allDay = event.time == "All day"
            guard let window = ClassWindow.make(id: event.id, subject: event.title, date: event.date, time: allDay ? "00:00 – 23:59" : event.time) else { return nil }
            return WidgetClass(id: event.id, subject: event.title, start: window.start, end: window.end, fingerprintTarget: window.start, proxyWarning: false, eventKind: allDay ? "day" : "event")
        }
    }
}
