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
            Text("Whole timetable").font(.title2.bold())
            Text("Subjects run down the rows; dates run across. Scroll both ways to browse the complete uploaded schedule.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("Course", selection: $programme) { ForEach(["All", "MBA", "DBM", "DBAI", "HHM"], id: \.self) { Text($0).tag($0) } }
                Picker("Section", selection: $section) { ForEach(["All", "A", "B", "C", "D"], id: \.self) { Text($0).tag($0) } }
            }
            TextField("Find a subject", text: $search).textFieldStyle(.roundedBorder)
            if rows.isEmpty, programme != "All" {
                ContentUnavailableView("No \(programme) schedule uploaded", systemImage: "tablecells", description: Text("Add its workbook alongside your current timetable."))
                Button("Upload \(programme) schedule") { onRequestProgramme(programme) }.buttonStyle(.borderedProminent)
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
}
