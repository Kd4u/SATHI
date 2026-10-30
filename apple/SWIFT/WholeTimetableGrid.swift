import SwiftUI

/// Virtualized subject rows with horizontally scrollable date columns. The
/// source report is retained; browsing never changes a student's selections.
struct WholeTimetableGrid: View {
    let report: TimetableReport
    let onRequestProgramme: (String) -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var programme = "All"
    @State private var section = "All"
    @State private var search = ""
    @State private var weekAnchor: Date?
    private var rows: [TimetableSession] {
        report.sessions.filter { (programme == "All" || TimetableIdentity.programme(source: $0.source) == programme) && (section == "All" || $0.section == section || $0.section.isEmpty) && (search.isEmpty || $0.subject.localizedCaseInsensitiveContains(search)) }
    }
    private var dates: [String] { Array(Set(rows.map(\.date) + report.events.filter { programme == "All" || TimetableIdentity.programme(source: $0.source) == programme }.map(\.date))).sorted() }
    private var subjects: [String] { Array(Set(rows.map { $0.subject + ($0.section.isEmpty ? "" : " · " + $0.section) })).sorted() }
    private var cellWidth: CGFloat { sizeClass == .compact ? 145 : 190 }
    private var labelWidth: CGFloat { sizeClass == .compact ? 170 : 240 }
    var body: some View {
        let values = rows
        let indexed = Dictionary(grouping: values) { $0.date + "|" + $0.subject + ($0.section.isEmpty ? "" : " · " + $0.section) }
        VStack(alignment: .leading, spacing: 12) {
            if sizeClass != .compact { Text("Whole timetable").font(.title2.bold()) }
            Text(sizeClass == .compact ? "All uploaded classes, seven days at a time." : "Subjects run down the rows; dates run across. Scroll both ways to browse the complete uploaded schedule.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("Course", selection: $programme) { ForEach(["All", "MBA", "DBM", "DBAI", "HHM"], id: \.self) { Text($0).tag($0) } }
                Picker("Section", selection: $section) { ForEach(["All", "A", "B", "C", "D"], id: \.self) { Text($0).tag($0) } }
            }
            TextField("Find a subject", text: $search).textFieldStyle(.roundedBorder)
            if rows.isEmpty, programme != "All" {
                ContentUnavailableView("No \(programme) schedule uploaded", systemImage: "tablecells", description: Text("Add its workbook alongside your current timetable."))
                Button("Upload \(programme) schedule") { onRequestProgramme(programme) }.buttonStyle(.borderedProminent)
            } else if sizeClass == .compact {
                compactWeek
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(subjects, id: \.self) { subject in
                                LazyHStack(alignment: .top, spacing: 1) {
                                    Text(subject).font(.subheadline.weight(.semibold)).padding(12).frame(width: labelWidth, alignment: .leading).frame(minHeight: 90, alignment: .leading).background(Color.accentColor.opacity(0.10))
                                    ForEach(dates, id: \.self) { date in
                                        let values = indexed[date + "|" + subject] ?? []
                                        VStack(alignment: .leading, spacing: 8) {
                                            if values.isEmpty { Text("—").foregroundStyle(.tertiary) }
                                            ForEach(values) { row in
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(row.time).font(.caption.bold()).foregroundStyle(Color.accentColor)
                                                    if !row.teacher.isEmpty { Text(row.teacher).font(.caption2).foregroundStyle(.secondary) }
                                                }
                                            }
                                        }.padding(10).frame(width: cellWidth, alignment: .topLeading).frame(minHeight: 90, alignment: .topLeading).background(Color.primary.opacity(values.isEmpty ? 0.015 : 0.04))
                                    }
                                }
                            }
                        } header: {
                            HStack(spacing: 1) {
                                Text("Subject / Date").font(.headline).padding(12).frame(width: labelWidth, height: 55, alignment: .leading)
                                ForEach(dates, id: \.self) { date in Text(date).font(.subheadline.bold()).frame(width: cellWidth, height: 55) }
                            }.background(.regularMaterial)
                        }
                    }
                }.frame(minHeight: sizeClass == .compact ? 520 : 720)
            }
        }
    }
    private var weekStart: Date {
        let first = dates.first.flatMap(SATHIDate.parse) ?? Date()
        let last = dates.last.flatMap(SATHIDate.parse) ?? first
        let chosen = weekAnchor ?? min(max(Date(), first), last)
        return Calendar.current.startOfDay(for: chosen)
    }
    private func shiftWeek(_ amount: Int) {
        weekAnchor = Calendar.current.date(byAdding: .day, value: amount * 7, to: weekStart)
    }
    private var compactWeek: some View {
        let start = weekStart
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let first = dates.first.flatMap(SATHIDate.parse) ?? start
        let last = dates.last.flatMap(SATHIDate.parse) ?? first
        let groups = Dictionary(grouping: rows, by: \.date)
        let events = report.events.filter { programme == "All" || TimetableIdentity.programme(source: $0.source) == programme }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button { shiftWeek(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 38) }
                    .disabled(SATHIDate.key(start) <= (dates.first ?? ""))
                    .accessibilityLabel("Previous seven days")
                VStack(spacing: 2) {
                    Text(start.formatted(.dateTime.day().month(.abbreviated)) + " – " + end.formatted(.dateTime.day().month(.abbreviated))).font(.headline)
                    Text("7 days · all subjects").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
                Button { shiftWeek(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 38) }
                    .disabled(SATHIDate.key(end) >= (dates.last ?? ""))
                    .accessibilityLabel("Next seven days")
            }
            DatePicker("Jump to date", selection: Binding(get: { start }, set: { weekAnchor = $0 }), in: first...last, displayedComponents: .date).font(.subheadline)
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(0..<7, id: \.self) { offset in
                    let day = Calendar.current.date(byAdding: .day, value: offset, to: start) ?? start
                    let key = SATHIDate.key(day)
                    let classes = (groups[key] ?? []).sorted { ($0.time, $0.subject, $0.id) < ($1.time, $1.subject, $1.id) }
                    let dayEvents = Array(Set(events.filter { $0.date == key }.map(\.title))).sorted()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).font(.subheadline.bold())
                            Spacer()
                            Text("\(classes.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ForEach(classes) { row in
                            HStack(alignment: .top, spacing: 10) {
                                Rectangle().fill(Color.accentColor).frame(width: 3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.time).font(.caption.bold()).foregroundStyle(Color.accentColor)
                                    Text(row.subject).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                                    if !row.section.isEmpty { Text("Section " + row.section).font(.caption2).foregroundStyle(.secondary) }
                                    if !row.teacher.isEmpty { Text(row.teacher).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                        }
                        ForEach(dayEvents, id: \.self) { title in Label(title, systemImage: "calendar").font(.caption).foregroundStyle(.secondary) }
                        if classes.isEmpty && dayEvents.isEmpty { Text("No scheduled classes").font(.caption).foregroundStyle(.secondary) }
                    }
                    if offset < 6 { Divider() }
                }
            }
        }
        .onChange(of: programme) { _, _ in weekAnchor = nil }
        .onChange(of: section) { _, _ in weekAnchor = nil }
    }

}
