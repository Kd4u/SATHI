import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct TimetableReviewView: View {
    let report: TimetableReport
    let initialSelection: Set<String>
    var readOnly = false
    var onRequestSchedule: ((String) -> Void)? = nil
    let onSave: (TimetableReport, Set<String>) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var rows: [TimetableSession] = []
    @State private var chosen: Set<String> = []
    @State private var date = Date()
    @State private var week = true
    @State private var programme = "All"
    @State private var section = "All"
    @State private var editing: TimetableSession?
    @State private var slots = false
    @State private var editTeacher = ""
    @State private var editSection = ""
    @State private var promotedEvents: Set<String> = []
    private var scoped: [TimetableSession] {
        rows.filter { (programme == "All" || TimetableIdentity.programme(source: $0.source) == programme) && (section == "All" || $0.section.isEmpty || $0.section == section) }
    }
    private var dates: [String] {
        let calendar = Calendar.current
        let start = week ? calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date : date
        return (0..<(week ? 7 : 1)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map(SATHIDate.key)
    }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(readOnly ? "Browse every imported class, including subjects you do not take." : "Tap a class to choose it. Highlighted classes are in your timetable. Use the pencil to correct names or times.").font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Picker("View", selection: $week) { Text("Day").tag(false); Text("7 days").tag(true) }.pickerStyle(.segmented).frame(maxWidth: 220)
                    DatePicker("Show", selection: $date, displayedComponents: .date).labelsHidden()
                    Spacer()
                    Button("Time slots", systemImage: "clock") { slots = true }.disabled(readOnly)
                }
                HStack {
                    Picker("Course", selection: $programme) { ForEach(["All", "MBA", "DBM", "DBAI", "HHM"], id: \.self) { Text($0).tag($0) } }
                    Picker("Section", selection: $section) { ForEach(["All", "A", "B", "C", "D"], id: \.self) { Text($0).tag($0) } }
                    Spacer()
                    Button { date = Calendar.current.date(byAdding: .day, value: week ? -7 : -1, to: date) ?? date } label: { Image(systemName: "chevron.left") }
                    Button { date = Calendar.current.date(byAdding: .day, value: week ? 7 : 1, to: date) ?? date } label: { Image(systemName: "chevron.right") }
                }
                ScrollView([.horizontal, .vertical]) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(dates, id: \.self) { day in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(day).font(.headline).padding(.vertical, 8)
                                ForEach(scoped.filter { $0.date == day }.sorted { $0.time < $1.time }) { row in
                                    VStack(alignment: .leading, spacing: 7) {
                                        Button {
                                            if !readOnly { if chosen.contains(row.id) { chosen.remove(row.id) } else { chosen.insert(row.id) } }
                                        } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Label(row.subject, systemImage: chosen.contains(row.id) ? "checkmark.circle.fill" : "circle")
                                                Text(row.time).font(.caption)
                                                if !row.section.isEmpty { Text("Section " + row.section).font(.caption2) }
                                                Text(row.teacher).font(.caption2).foregroundStyle(.secondary)
                                            }.frame(maxWidth: .infinity, alignment: .leading)
                                        }.buttonStyle(.plain)
                                        if !readOnly { Button("Correct this class", systemImage: "pencil") { editing = row }.font(.caption) }
                                    }.padding(12).background(chosen.contains(row.id) ? Color.accentColor.opacity(0.17) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
                                }
                                ForEach(Array(report.events.filter { $0.date == day }.enumerated()), id: \.offset) { _, event in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(event.title).font(.caption.bold()); Text(event.time).font(.caption2)
                                        if !readOnly { Button("This is a class I take") {
                                            let row = TimetableSession(id: "manual-" + UUID().uuidString, date: event.date, day: "", time: event.time, subject: event.title, section: "", teacher: "", source: event.source)
                                            rows.append(row); chosen.insert(row.id); promotedEvents.insert(event.source + "|" + event.date + "|" + event.time + "|" + event.title); editing = row
                                        }.font(.caption).disabled(rows.contains(where: { $0.source == event.source && $0.id.hasPrefix("manual-") })) }
                                    }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                                }
                                if scoped.filter({ $0.date == day }).isEmpty { Text("No imported classes").font(.caption).foregroundStyle(.secondary) }
                            }.frame(width: week ? 230 : (sizeClass == .compact ? 310 : 480), alignment: .topLeading)
                        }
                    }.padding(4)
                }
                if scoped.isEmpty, programme != "All", let onRequestSchedule { Button("Upload the " + programme + " schedule", systemImage: "arrow.up.doc") { onRequestSchedule(programme) } }
                if scoped.isEmpty { Text("This course or section is not in the uploaded workbook. Close this view and upload its schedule from Settings; your current semester is preserved in History.").font(.footnote).foregroundStyle(.secondary) }
            }.padding()
            .navigationTitle(readOnly ? "Whole timetable" : "Check my timetable")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(readOnly ? "Done" : "Cancel") { dismiss() } }
                if !readOnly { ToolbarItem(placement: .confirmationAction) { Button("Save my \(chosen.count) classes") {
                    let addedSources = promotedEvents
                    let updated = TimetableReport(workbook: report.workbook, sessions: rows, subjects: TimetableIdentity.subjects(rows), events: report.events.filter { !addedSources.contains($0.source + "|" + $0.date + "|" + $0.time + "|" + $0.title) }, warnings: report.warnings)
                    onSave(updated, chosen)
                }.disabled(chosen.isEmpty) } }
            }
            .onChange(of: programme) { _, course in
                section = "All"
                if readOnly, course != "All", !rows.contains(where: { TimetableIdentity.programme(source: $0.source) == course }) { onRequestSchedule?(course) }
            }
            .onChange(of: section) { _, value in
                if value != "All", programme != "MBA", !rows.contains(where: { TimetableIdentity.programme(source: $0.source) == programme && $0.section == value }) { programme = "MBA" }
            }
            .onAppear { rows = report.sessions; chosen = initialSelection; if let first = rows.map(\.date).min(), let value = SATHIDate.parse(first) { date = value } }
            .sheet(item: $editing) { item in
                ScheduleItemEditor(title: item.subject, date: item.date, time: item.time, additionalFields: AnyView(Group {
                    TextField("Teacher (optional)", text: $editTeacher)
                    TextField("Section (leave blank for common)", text: $editSection)
                })) { title, day, start, end in
                    if let index = rows.firstIndex(where: { $0.id == item.id }) {
                        rows[index] = TimetableSession(id: item.id, date: day, day: item.day, time: start + " – " + end, subject: title, section: editSection.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), teacher: editTeacher, source: item.source)
                    }
                    editing = nil
                }.onAppear { editTeacher = item.teacher; editSection = item.section }
            }
            .sheet(isPresented: $slots) { SlotReviewView(slots: Array(Set(rows.map(\.time))).sorted()) { old, new in
                rows = rows.map { row in TimetableSession(id: row.id, date: row.date, day: row.day, time: row.time == old ? new : row.time, subject: row.subject, section: row.section, teacher: row.teacher, source: row.source) }
            } }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 560)
        #endif
    }
}

struct ScheduleItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var day: Date
    @State private var start: Date
    @State private var end: Date
    let onSave: (String, String, String, String) -> Void
    let additionalFields: AnyView?
    init(title: String, date: String, time: String, additionalFields: AnyView? = nil, onSave: @escaping (String, String, String, String) -> Void) {
        _title = State(initialValue: title)
        let window = ClassWindow.make(id: "edit", subject: title, date: date, time: time)
        _day = State(initialValue: SATHIDate.parse(date) ?? Date())
        _start = State(initialValue: window?.start ?? Date()); _end = State(initialValue: window?.end ?? Date().addingTimeInterval(5400)); self.onSave = onSave; self.additionalFields = additionalFields
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Class or activity name", text: $title)
                DatePicker("New date", selection: $day, displayedComponents: .date)
                DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                if let additionalFields { additionalFields }
                Text("Choose any earlier or later date and time. Overlapping classes and activities stay visible.").font(.caption)
            }.formStyle(.grouped).navigationTitle("Reschedule / correct")
                .toolbar { Button("Cancel") { dismiss() }; Button("Save") {
                    let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
                    onSave(title, SATHIDate.key(day), formatter.string(from: start), formatter.string(from: end)); dismiss()
                }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || Calendar.current.dateComponents([.hour, .minute], from: end).hour! * 60 + Calendar.current.component(.minute, from: end) <= Calendar.current.component(.hour, from: start) * 60 + Calendar.current.component(.minute, from: start)) }
        }.frame(minWidth: 300, minHeight: 320)
    }
}
private struct SlotReviewView: View {
    let slots: [String]
    let onChange: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editing: String?
    var body: some View {
        NavigationStack {
            List(slots, id: \.self) { slot in Button(slot + " · change") { editing = slot } }
                .navigationTitle("When do your slots start and end?").toolbar { Button("Done") { dismiss() } }
                .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                    if let editing { ScheduleItemEditor(title: "Time slot", date: SATHIDate.key(Date()), time: editing) { _, _, start, end in onChange(editing, start + " – " + end); self.editing = nil } }
                }
        }.frame(minWidth: 320, minHeight: 400)
    }
}

struct CampusDocumentView: View {
    @ObservedObject var study: StudyStore
    let kind: String
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var document: URL?
    @State private var preview: URL?
    @State private var error = ""
    private func folder() throws -> URL {
        let value = try study.notebookDirectory().deletingLastPathComponent().appendingPathComponent("LocalCampus", isDirectory: true)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true); return value
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: kind == "menu" ? "fork.knife" : "washer").font(.largeTitle).foregroundStyle(Color.accentColor)
                if let document { Button("Open saved \(kind == "menu" ? "mess menu" : "laundry schedule")") { preview = document }.buttonStyle(.borderedProminent) }
                else { Text("Add a photo or PDF. It opens locally, even offline.").foregroundStyle(.secondary) }
                Button(document == nil ? "Choose photo or PDF" : "Edit / replace document") { importing = true }
                if !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption) }
            }.padding(30).navigationTitle(kind == "menu" ? "Mess menu" : "Laundry")
                .toolbar { Button("Done") { dismiss() } }.quickLookPreview($preview)
                .task { if let root = try? folder(), let name = try? String(contentsOf: root.appendingPathComponent(kind + ".txt"), encoding: .utf8) { document = root.appendingPathComponent(name) } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .pdf]) { result in
                    do {
                        let source = try result.get(); let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
                        let root = try folder(), name = kind + "-" + UUID().uuidString + "." + source.pathExtension
                        let target = root.appendingPathComponent(name)
                        try Data(contentsOf: source).write(to: target, options: .atomic)
                        try name.write(to: root.appendingPathComponent(kind + ".txt"), atomically: true, encoding: .utf8)
                        document = target; preview = target
                    } catch { self.error = error.localizedDescription }
                }
        }.frame(minWidth: 300, minHeight: 280)
    }
}
