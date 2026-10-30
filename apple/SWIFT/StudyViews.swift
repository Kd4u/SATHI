import SwiftUI
#if canImport(UIKit)
import UIKit
import PencilKit
#elseif os(macOS)
import AppKit
#endif

extension StudyPreferences {
    var colorScheme: ColorScheme? {
        switch appearanceMode { case "dark": .dark; case "light": .light; default: nil }
    }
    var accentColor: Color {
        switch accent { case "teal": .teal; case "indigo": .indigo; case "purple": .purple; case "green": .green; case "pink": .pink; case "orange": .orange; case "mint": .mint; case "cyan": .cyan; case "red": .red; case "brown": .brown; case "yellow": .yellow; default: .blue }
    }
    var textSize: DynamicTypeSize {
        switch fontScale { case ..<0.95: .medium; case ..<1.05: .large; case ..<1.15: .xLarge; case ..<1.25: .xxLarge; default: .xxxLarge }
    }
}

struct AppearanceSetupView: View {
    @ObservedObject var store: StudyStore
    var onboarding = false
    let onDone: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(onboarding ? "Make SATHI yours" : "Appearance & reminders").font(.largeTitle.bold())
            Text("A calm study space, on all your devices.").foregroundStyle(.secondary)
            Form {
                Section("Themes") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 95))], spacing: 10) {
                        ForEach(["Ocean", "Forest", "Lavender", "Sunset", "Graphite"], id: \.self) { theme in
                            Button(theme) {
                                let accents = ["Ocean": "blue", "Forest": "green", "Lavender": "purple", "Sunset": "orange", "Graphite": "indigo"]
                                store.workspace.preferences.accent = accents[theme] ?? "blue"
                                store.workspace.preferences.appearanceMode = theme == "Graphite" ? "dark" : "system"
                                store.workspace.preferences.glassStyle = theme == "Graphite" ? "solid" : "regular"
                                store.workspace.preferences.glassOpacity = 0.75
                            }.buttonStyle(.bordered)
                        }
                    }
                }
                Section("Appearance") {
                    Picker("Display", selection: Binding(get: { store.workspace.preferences.appearanceMode ?? "system" }, set: { store.workspace.preferences.appearanceMode = $0 })) {
                        Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                    Picker("Material", selection: Binding(get: { store.workspace.preferences.glassStyle ?? "regular" }, set: { store.workspace.preferences.glassStyle = $0 })) {
                        Text("Glass").tag("regular"); Text("Clear glass").tag("clear"); Text("Frosted").tag("frosted"); Text("Ultra-thin").tag("ultraThin"); Text("Solid").tag("solid")
                    }
                    Picker("Accent colour", selection: $store.workspace.preferences.accent) {
                        ForEach(["blue", "teal", "indigo", "purple", "green", "pink", "orange", "mint", "cyan", "red", "brown", "yellow"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Slider(value: $store.workspace.preferences.glassOpacity, in: 0.25...1) { Text("Glass opacity") }
                    Picker("Text size", selection: $store.workspace.preferences.fontScale) {
                        Text("Small").tag(0.9); Text("Standard").tag(1.0); Text("Large").tag(1.1); Text("Larger").tag(1.2); Text("Largest").tag(1.3)
                    }
                }
                Section("Class reminders") {
                    Toggle("Enable class reminders", isOn: $store.workspace.preferences.reminders)
                    Toggle("Notification sounds", isOn: $store.workspace.preferences.sounds)
                    Picker("Sound", selection: $store.workspace.preferences.notificationSound) { Text("System default").tag("default"); Text("Gentle chime").tag("chime") }
                    Toggle("App haptics", isOn: $store.workspace.preferences.haptics)
                    Text("System notification vibration follows your device's notification and haptic settings.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Class countdown", isOn: $store.workspace.preferences.classCountdown)
                    Toggle("Live Activities", isOn: $store.workspace.preferences.liveActivities)
                    Text("Live Activities start while SATHI is open. Their timers can continue when it closes; background updates follow system limits.").font(.caption).foregroundStyle(.secondary)
                    Stepper("Fingerprint reminder: \(store.workspace.preferences.fingerprintLeadMinutes) min before", value: $store.workspace.preferences.fingerprintLeadMinutes, in: 1...60)
                    Stepper("Fingerprint target: \(store.workspace.preferences.fingerprintTargetMinutes) min before", value: $store.workspace.preferences.fingerprintTargetMinutes, in: 0...10)
                    Stepper("Reminder grace: \(store.workspace.preferences.reminderGraceMinutes) min after", value: $store.workspace.preferences.reminderGraceMinutes, in: 0...20)
                    Stepper("Sheet reminder: \(store.workspace.preferences.sheetReminderMinutes) min into class", value: $store.workspace.preferences.sheetReminderMinutes, in: 5...120, step: 5)
                }
                Section("Student profile") {
                    TextField("Your name", text: Binding(get: { store.workspace.preferences.studentName ?? "" }, set: { store.workspace.preferences.studentName = $0 }))
                    Picker("Course", selection: $store.workspace.preferences.programme) {
                        ForEach(["MBA", "DBM", "DBAI", "HHM"], id: \.self) { Text($0).tag($0) }
                    }
                    if (store.workspace.preferences.studentSemester ?? 4) <= 3 {
                        Picker("Section", selection: $store.workspace.preferences.firstYearSection) {
                            Text("Choose section").tag("")
                            ForEach(["A", "B", "C", "D"], id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Text("Year is determined by your semester. Course and section are remembered.").font(.caption)
                }
                Section("Everyday tools") {
                    Toggle("Fingerprint and attendance-sheet crosscheck", isOn: Binding(get: { store.workspace.preferences.proofCrosscheck ?? false }, set: { store.workspace.preferences.proofCrosscheck = $0 }))
                    Toggle("Show mess menu and laundry buttons", isOn: Binding(get: { store.workspace.preferences.campusShortcuts ?? false }, set: { store.workspace.preferences.campusShortcuts = $0 }))
                    Text("Menu and laundry documents stay on this device. Add a photo or PDF and replace it whenever needed.").font(.caption)
                }
            }.formStyle(.grouped)
            Button(onboarding ? "Continue" : "Save changes") {
                store.workspace.preferences.didCustomizeAppearance = true
                onDone()
            }.buttonStyle(.borderedProminent)
        }.padding(22).tint(store.workspace.preferences.accentColor)
    }
}

struct ClassAttendanceView: View {
    let window: ClassWindow
    @Binding var proof: ClassProof
    let penalized: Bool
    let onSave: () -> Void
    var body: some View {
        Form {
            Section(window.subject) {
                HStack { Text(window.start, style: .time); Text("–"); Text(window.end, style: .time) }.font(.headline)
                if AttendanceRules.hasLiveProxyWarning(proof: proof, window: window, now: Date()) {
                    Label("Do not sign the sheet if you missed the fingerprint. A single completed proof can be treated as proxy attendance.", systemImage: "exclamationmark.octagon.fill").foregroundStyle(.red)
                }
                if penalized { Label("Attendance credit is blocked for this class by a three-class proxy penalty. You must still attend; this class stays in your schedule.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                Toggle("Official duty (OD) · counts as present", isOn: $proof.officialDuty)
                proofPicker("Attended class", value: $proof.attended)
                proofPicker("Fingerprint recorded", value: $proof.fingerprint)
                proofPicker("Attendance sheet signed", value: $proof.signedSheet)
                Text("These are your own records, not a connection to the institute's attendance system. You can correct them later. An unanswered proof stays unresolved.").font(.caption).foregroundStyle(.secondary)
                Text("After class, exactly one completed proof means the next three scheduled classes receive no attendance credit. OD still counts as present.").font(.caption)
                Button("Save attendance") { proof.updatedAt = Date(); onSave() }.buttonStyle(.borderedProminent)
            }
        }.formStyle(.grouped).frame(minWidth: 300)
    }
    private func proofPicker(_ title: String, value: Binding<Bool?>) -> some View {
        Picker(title, selection: value) {
            Text("Unanswered").tag(Optional<Bool>.none)
            Text("Yes").tag(Optional(true))
            Text("No / missed").tag(Optional(false))
        }
    }
}

struct ClassCountdownView: View {
    let windows: [ClassWindow]
    let preferences: StudyPreferences
    var body: some View {
        if preferences.classCountdown {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let window = windows.first(where: { $0.end > context.date }) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(window.subject).font(.headline)
                        if context.date < window.start {
                            if window.start.timeIntervalSince(context.date) <= Double(preferences.fingerprintLeadMinutes * 60) {
                                Text("Fingerprint target in \(window.fingerprintMinutesLeft(at: context.date, preferences: preferences)) min").foregroundStyle(.secondary)
                                Text("Class starts \(window.start, style: .relative)")
                            } else {
                                Text(window.start, format: .dateTime.weekday(.wide).hour().minute()).foregroundStyle(.secondary)
                            }
                        } else {
                            HStack { Text("Class time remaining"); Text(timerInterval: window.start...window.end, countsDown: true).monospacedDigit() }
                        }
                    }.padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
    }
}

struct NotesHubView: View {
    @ObservedObject var store: StudyStore
    let subjects: [String]
    var semesterID: String?
    var body: some View { NotebookLibraryView(study: store, subjects: subjects, semesterID: semesterID) }
}

struct SemesterHistoryView: View {
    @ObservedObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.assets.filter { $0.kind == "semester" }.sorted { $0.modifiedAt > $1.modifiedAt }) { item in
                    NavigationLink(item.title) {
                        if let data = try? store.assetData(item.id), let archive = try? JSONDecoder().decode(ArchivedSemester.self, from: data) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 18) {
                                    Text(item.title).font(.largeTitle.bold())
                                    let present = archive.attendance.values.filter { $0 == "Attended" || $0 == "OD" }.count
                                    let missed = archive.attendance.values.filter { $0 == "Missed" }.count
                                    Text("\(present) present / OD · \(missed) missed")
                                    ForEach(ScheduleEdits.apply(archive.report.sessions.filter { session in
                                        if let ids = archive.selectedSessionIDs { return ids.contains(session.id) }
                                        if archive.number >= 4 { return archive.selectedKeys.contains(session.subject + "|" + session.section) }
                                        return (archive.section ?? "").isEmpty || session.section.isEmpty || session.section.uppercased() == archive.section?.uppercased()
                                    }, overrides: archive.overrides ?? [:], semesterID: archive.semesterID)) { session in
                                        HStack {
                                            VStack(alignment: .leading) { Text(session.subject).bold(); Text(session.date + " · " + session.time).font(.caption) }
                                            Spacer(); Text(archive.attendance[session.id] ?? "Unmarked").font(.caption)
                                        }
                                    }
                                    ForEach(archive.customEvents ?? []) { event in
                                        VStack(alignment: .leading) { Text(event.title).bold(); Text(event.date + " · " + event.start + " – " + event.end).font(.caption); Text(event.notes).font(.caption) }
                                    }
                                    Divider()
                                    NotesHubView(store: store, subjects: archive.report.sessions.filter { session in
                                        if let ids = archive.selectedSessionIDs { return ids.contains(session.id) }
                                        if archive.number >= 4 { return archive.selectedKeys.contains(session.subject + "|" + session.section) }
                                        return (archive.section ?? "").isEmpty || session.section.isEmpty || session.section.uppercased() == archive.section?.uppercased()
                                    }.map(\.subject), semesterID: archive.semesterID)
                                }.padding()
                            }
                        } else { Text("This semester is waiting to download. Use Save & Refresh.") }
                    }
                }
                if store.assets.filter({ $0.kind == "semester" }).isEmpty { Text("Past semesters will appear here when you import your next timetable.") }
            }.navigationTitle("Semester history")
            .toolbar { Button("Done") { dismiss() } }
        }.frame(minWidth: 320, minHeight: 450)
    }
}

private struct StudyGlassOpacityKey: EnvironmentKey { static let defaultValue = 0.75 }
extension EnvironmentValues {
    var studyGlassOpacity: Double {
        get { self[StudyGlassOpacityKey.self] }
        set { self[StudyGlassOpacityKey.self] = newValue }
    }
}

private struct StudyGlassStyleKey: EnvironmentKey { static let defaultValue = "regular" }
extension EnvironmentValues {
    var studyGlassStyle: String { get { self[StudyGlassStyleKey.self] } set { self[StudyGlassStyleKey.self] = newValue } }
}
