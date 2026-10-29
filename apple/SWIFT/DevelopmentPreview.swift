#if DEBUG
import SwiftUI

/// Isolated fixture for simulator visual checks. No cloud sync, account adoption or real timetable writes.
struct DevelopmentPreview: View {
    @StateObject private var study = StudyStore()
    @State private var selectedDate = Date()
    @State private var target = 80
    @State private var showAppearance = false
    private var rows: [TimetableSession] {
        let names = ["Operations Management", "Financial Accounting", "Business Analytics"]
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        return (0..<3).flatMap { offset in
            names.enumerated().map { index, name in
                let date = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
                return TimetableSession(id: "preview-\(offset)-\(index)", date: formatter.string(from: date), day: "", time: ["09:00 – 10:30", "11:00 – 12:30", "14:00 – 15:30"][index], subject: name, section: "A", teacher: "Professor", source: "Preview")
            }
        }
    }
    var body: some View {
        let windows = rows.compactMap { ClassWindow.make(id: $0.id, subject: $0.subject, date: $0.date, time: $0.time) }
        SATHICommandCenter(sessions: rows, otherSectionSessions: [], subjects: Array(Set(rows.map(\.subject))).sorted().map { TimetableSubject(key: $0 + "|A", name: $0, count: 20, credits: 3) }, events: [], custom: [], selectedDate: $selectedDate, attendance: [:], onAttendanceChange: { _, _ in }, onAddEvent: {}, onDeleteCustomEvent: { _ in }, onSubjects: {}, onEditSelection: {}, onChangeSemester: {}, onReplaceExcel: {}, onExport: {}, onExportActivity: {}, target: $target, study: study, windows: windows, endDates: Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.end) }), penaltyIDs: [], onProof: { _ in }, onAppearance: { showAppearance = true }, onSync: {}, onAccount: {}, syncing: false, syncStatus: "Preview · saved on this device", onHistory: {}, onNextSemester: {}, canStartNextSemester: false, canEditSelection: false)
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-sathi-dark") ? .dark : .light)
            .sheet(isPresented: $showAppearance) { AppearanceSetupView(store: study) { showAppearance = false } }
            .task {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SATHI-Visual-Preview", isDirectory: true)
                try? study.configure(directory: folder, uid: "visual-preview-only")
            }
    }
}
#endif
