import SwiftUI
import WidgetKit
#if os(iOS)
import ActivityKit
#endif

private func attendanceURL(_ id: String) -> URL? {
    var parts = URLComponents(); parts.scheme = "sathi"; parts.host = "attendance"
    parts.queryItems = [URLQueryItem(name: "id", value: id)]
    return parts.url
}

struct ClassWidgetEntry: TimelineEntry {
    var date: Date
    var classes: [WidgetClass]
    var hasCache = true
    var relevance: TimelineEntryRelevance? {
        guard let next, next.start.timeIntervalSince(date) < 3600 else { return nil }
        return TimelineEntryRelevance(score: 80, duration: max(60, next.end.timeIntervalSince(date)))
    }
    var next: WidgetClass? { classes.filter { $0.end > date }.sorted { $0.start < $1.start }.first }
}
struct ClassWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClassWidgetEntry { .init(date: .now, classes: []) }
    func getSnapshot(in context: Context, completion: @escaping (ClassWidgetEntry) -> Void) {
        completion(.init(date: .now, classes: SharedClassStorage.load()?.classes ?? [], hasCache: SharedClassStorage.load() != nil))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ClassWidgetEntry>) -> Void) {
        let now = Date(); let saved = SharedClassStorage.load(); let classes = saved?.classes ?? []
        var dates = [now]
        for offset in 1...7 { dates.append(WidgetDates.calendar.date(byAdding: .day, value: offset, to: WidgetDates.calendar.startOfDay(for: now))!) }
        for value in classes where value.end > now { dates += [value.start, value.end].filter { $0 > now } }
        let entries = Set(dates).sorted().prefix(80).map { ClassWidgetEntry(date: $0, classes: classes, hasCache: saved != nil) }
        let relevance = classes.contains { $0.start > now && $0.start.timeIntervalSince(now) < 3600 }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(relevance ? 1800 : 3600))))
    }
}

struct NextClassWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClassWidgetEntry
    var threeDays = false
    var body: some View {
        Group {
            #if os(iOS)
            if family == .accessoryInline { Label(entry.next?.subject ?? "No more classes today", systemImage: "calendar") }
            else if family == .accessoryCircular {
                VStack { Image(systemName: "calendar"); if let next = entry.next { Text(next.start, style: .time).font(.caption2) } else { Text("Free").font(.caption2) } }
            } else if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SATHI · Today").font(.caption2.bold())
                    Text(WidgetDates.classes(entry.classes, on: entry.date).first?.subject ?? (entry.hasCache ? "No events today" : "Open SATHI to refresh")).font(.headline).lineLimit(2).privacySensitive()
                }
            } else { schedule }
            #else
            schedule
            #endif
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "sathi://timetable"))
    }
    private var schedule: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Label((family == .systemLarge || threeDays) ? "Next three days" : "Today", systemImage: "calendar").font(.caption.bold()); Spacer(); Text("SATHI").font(.caption2).foregroundStyle(.secondary) }
            if !entry.hasCache {
                Text("Open SATHI to load your timetable").font(.callout)
                Text("Widgets use your saved schedule, even offline.").font(.caption2).foregroundStyle(.secondary)
            } else if family == .systemLarge || threeDays {
                ForEach(0..<3, id: \.self) { offset in
                    let date = WidgetDates.calendar.date(byAdding: .day, value: offset, to: entry.date)!
                    let rows = WidgetDates.classes(entry.classes, on: date)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)).font(.caption.bold()).foregroundStyle(.secondary)
                            if family == .systemMedium { Spacer(); Text("\(rows.count) scheduled").font(.caption2).foregroundStyle(.secondary) }
                        }
                        if rows.isEmpty { Text("Free day").font(.caption) }
                        ForEach(rows.prefix(family == .systemMedium ? 1 : 4)) { row in classRow(row) }
                        if family != .systemMedium && rows.count > 4 { Text("+\(rows.count - 4) more · open timetable").font(.caption2).foregroundStyle(.secondary) }
                    }
                    if offset < 2 { Divider() }
                }
            } else {
                let rows = WidgetDates.classes(entry.classes, on: entry.date)
                if rows.isEmpty { Text("No events today").font(.headline) }
                ForEach(rows.prefix(family == .systemSmall ? 2 : 4)) { row in classRow(row) }
                if rows.count > (family == .systemSmall ? 2 : 4) { Text("+ more in SATHI").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
    }
    private func classRow(_ row: WidgetClass) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Group { if row.eventKind == "day" { Text("All day") } else { Text(row.start, style: .time) } }.font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 57, alignment: .leading)
            Text(row.subject).font(.caption.weight(.medium)).lineLimit(1).privacySensitive()
            Spacer(minLength: 0)
            if entry.date >= row.start && entry.date < row.end { Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.tint) }
        }
    }
}
struct NextClassWidget: Widget {
    let kind = "SATHINextClass"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClassWidgetProvider()) { NextClassWidgetView(entry: $0) }
            .configurationDisplayName("SATHI schedule")
            .description("Today's classes, or a three-day agenda in the large widget. Add to a same-size Smart Stack.")
            #if os(iOS)
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular])
            #else
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
            #endif
    }
}

struct ThreeDayScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SATHIThreeDayAgenda", provider: ClassWidgetProvider()) {
            NextClassWidgetView(entry: $0, threeDays: true)
        }
        .configurationDisplayName("SATHI three-day agenda")
        .description("The next three days. Stack with Today's widget using the same size.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

#if os(iOS)
struct SathiLiveClassWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SathiClassActivity.self) { context in
            VStack(alignment: .leading, spacing: 7) {
                HStack { Text("SATHI").font(.caption.bold()); Spacer(); Text(context.attributes.subject).bold().lineLimit(1) }
                if context.state.proxyWarning { Label("Do not sign · fingerprint missed", systemImage: "exclamationmark.octagon.fill").foregroundStyle(.red).font(.caption.bold()) }
                HStack {
                    VStack(alignment: .leading) { Text("Fingerprint target").font(.caption); Text(timerInterval: context.attributes.fingerprintTarget.addingTimeInterval(-15 * 60)...context.attributes.fingerprintTarget, countsDown: true).monospacedDigit() }
                    Spacer()
                    VStack(alignment: .trailing) { Text("Class remaining").font(.caption); Text(timerInterval: context.attributes.start...context.attributes.end, countsDown: true).monospacedDigit() }
                }
                Text(context.state.fingerprintDone ? "Fingerprint recorded · remember the attendance sheet" : "Record fingerprint and sheet status in SATHI").font(.caption2)
            }.padding(15)
            .activityBackgroundTint(context.state.proxyWarning ? .red.opacity(0.15) : .blue.opacity(0.10))
            .widgetURL(attendanceURL(context.attributes.classID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: context.state.proxyWarning ? "exclamationmark.octagon.fill" : "calendar").foregroundStyle(context.state.proxyWarning ? .red : .blue) }
                DynamicIslandExpandedRegion(.trailing) { Text(timerInterval: context.attributes.start...context.attributes.end, countsDown: true).monospacedDigit().frame(width: 90) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack { Text(context.attributes.subject).font(.headline); Text(context.state.proxyWarning ? "Do not sign: fingerprint missed" : "Fingerprint and sheet check").font(.caption).foregroundStyle(context.state.proxyWarning ? .red : .secondary) }
                }
            } compactLeading: { Image(systemName: context.state.proxyWarning ? "exclamationmark.triangle.fill" : "calendar").foregroundStyle(context.state.proxyWarning ? .red : .blue) }
            compactTrailing: { Text(timerInterval: context.attributes.start...context.attributes.end, countsDown: true).monospacedDigit().frame(width: 52) }
            minimal: { Image(systemName: context.state.proxyWarning ? "exclamationmark.octagon.fill" : "calendar").foregroundStyle(context.state.proxyWarning ? .red : .blue) }
            .widgetURL(URL(string: "sathi://timetable"))
        }
    }
}
#endif

@main struct SATHIWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextClassWidget()
        ThreeDayScheduleWidget()
        #if os(iOS)
        SathiLiveClassWidget()
        #endif
    }
}
