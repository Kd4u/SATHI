import SwiftUI
import UniformTypeIdentifiers
import Foundation
#if os(iOS)
import UIKit
#endif

// SATHI's only UI file. TimetableLogic.swift owns all Excel models and parsing.
struct ContentView: View {
    @ObservedObject var cloud: CloudSyncStore
    @StateObject private var study: StudyStore
    @State private var showAppearance = false
    @State private var showHistory = false
    @State private var attendanceWindow: ClassWindow?
    @State private var nextSemesterImport = false
    @State private var surfaceStatus = ""
    @State private var clockNow = Date()
    @State private var cachedWindows: [ClassWindow] = []
    @State private var windowSignature: Int?
    @State private var endDates: [String: Date] = [:]
    @State private var loadedAccountID: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSync = false
    @State private var hasRestored = false
    @State private var observedSnapshot = SyncSnapshot()
    @State private var useCachedCopy = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var report: TimetableReport?
    @State private var semester: Int?
    @State private var selectedKeys: Set<String> = []
    @State private var page: Page = .welcome
    @State private var showImporter = false
    @State private var showManualReview = false
    @State private var showWholeSchedule = false
    @State private var additionalProgramme: String?
    @State private var importing = false
    @State private var notice = ""
    @State private var query = ""
    @State private var showAllDates = false
    @State private var selectedDate = Date()
    @State private var showAddEvent = false
    @State private var attendance: [String: String] = [:]
    @State private var customEvents: [SATHICustomEvent] = []
    @State private var minimumAttendance = 80
    @State private var monthOffset = 0
    @State private var exportFilename = "SATHI_Timetable"
    @State private var showExport = false
    @State private var exportDocument = SATHIJSONDocument()

    init(cloud: CloudSyncStore) {
        self.cloud = cloud
        _study = StateObject(wrappedValue: StudyStoreRegistry.store(for: cloud.accountID))
    }

    private enum Page: String { case welcome, semester, subjects, overview, timetable }
    private var accent: Color { study.workspace.preferences.accentColor }

    private var isSecondYear: Bool { (semester ?? 0) >= 4 }
    private var programmeSessions: [TimetableSession] {
        (report?.sessions ?? []).filter { TimetableIdentity.programme(source: $0.source) == study.workspace.preferences.programme }
    }
    private var subjects: [TimetableSubject] { TimetableIdentity.subjects(programmeSessions) }
    private var manualIDs: Set<String>? { (study.workspace.preferences.manualSelections?[study.workspace.currentSemesterID]).map { Set($0) } }
    private var activeSubjects: [TimetableSubject] {
        if let manualIDs { return TimetableIdentity.subjects((report?.sessions ?? []).filter { manualIDs.contains($0.id) }) }
        if isSecondYear { return subjects.filter { selectedKeys.contains($0.key) } }
        let section = study.workspace.preferences.firstYearSection.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return subjects.filter { item in
            let parts = item.key.components(separatedBy: "|")
            return section.isEmpty || parts.count < 2 || parts.last?.isEmpty == true || parts.last?.uppercased() == section
        }
    }
    private var credits: Double { activeSubjects.reduce(0) { $0 + $1.credits } }
    private var sessions: [TimetableSession] {
        let scoped = (manualIDs == nil ? programmeSessions : (report?.sessions ?? [])).filter { session in
            if let manualIDs { return manualIDs.contains(session.id) }
            if isSecondYear { return selectedKeys.contains(session.subject + "|" + session.section) }
            let section = study.workspace.preferences.firstYearSection.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return section.isEmpty || session.section.isEmpty || session.section.uppercased() == section
        }
            .sorted { ($0.date, $0.time, $0.subject) < ($1.date, $1.time, $1.subject) }
        return ScheduleEdits.apply(scoped, overrides: study.workspace.overrides, semesterID: study.workspace.currentSemesterID)
    }
    private var lectureOrdinals: [String: Int] {
        let chosen = Set(sessions.map(\.id))
        let grouped = Dictionary(grouping: (report?.sessions ?? []).filter { chosen.contains($0.id) }) { $0.subject + "|" + $0.section }
        var result: [String: Int] = [:]
        for values in grouped.values {
            for (index, row) in values.sorted(by: { ($0.date, $0.time, $0.id) < ($1.date, $1.time, $1.id) }).enumerated() { result[row.id] = index + 1 }
        }
        return result
    }
    private var events: [TimetableEvent] {
        (report?.events ?? []).map { event in
            let id = event.id ?? "excel-" + event.source + "-" + event.time
            if let edit = study.workspace.overrides[id], edit.semesterID == study.workspace.currentSemesterID {
                return TimetableEvent(date: edit.date, time: edit.start + " – " + edit.end, title: edit.title, source: event.source, id: id)
            }
            return event
        }.filter { event in
            guard TimetableIdentity.programme(source: event.source) == study.workspace.preferences.programme else { return false }
            let section = TimetableSection.label(in: event.source.components(separatedBy: "!")[0])
            let chosen = study.workspace.preferences.firstYearSection
            return isSecondYear || chosen.isEmpty || section.isEmpty || section == chosen
        }
    }
    private var displayedSessions: [TimetableSession] {
        guard !showAllDates else { return sessions }
        return sessions.filter { $0.date == dateString(selectedDate) }
    }
    private var dailyCustomEvents: [SATHICustomEvent] {
        customEvents.filter { $0.date == dateString(selectedDate) }.sorted { $0.start < $1.start }
    }
    private var displayedEvents: [TimetableEvent] {
        guard !showAllDates else { return events }
        return events.filter { $0.date == dateString(selectedDate) }
    }
    private struct SubjectGroup: Identifiable { let name: String; let variants: [TimetableSubject]; var id: String { name } }
    private var groups: [SubjectGroup] {
        let dictionary = Dictionary(grouping: subjects) { $0.key.components(separatedBy: "|").first ?? $0.name }
        return dictionary.keys.sorted().filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
            .map { SubjectGroup(name: $0, variants: (dictionary[$0] ?? []).sorted { $0.key < $1.key }) }
    }
    private var sectionLabels: [String] {
        Array(Set(programmeSessions.map(\.section).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        GeometryReader { geo in
            Group {
                if !cloud.signedIn {
                    GoogleOnboardingView(store: cloud)
                } else if loadedAccountID != cloud.accountID {
                    VStack { ProgressView("Opening your private account…"); Text(notice).font(.caption) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !cloud.hasCheckedCloud && report == nil {
                    VStack(spacing: 20) {
                        Image(systemName: "icloud.and.arrow.down").font(.largeTitle).foregroundStyle(.tint)
                        Text("Your timetable").font(.title.bold())
                        Text("Restore your saved timetable before importing a new one.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("Restore from cloud", systemImage: "arrow.triangle.2.circlepath") { Task { await syncNow() } }.buttonStyle(.borderedProminent).disabled(cloud.busy)
                        if cloud.busy { ProgressView("Restoring… You can keep using the app.") }
                        Text(cloud.status).font(.caption).foregroundStyle(.secondary)
                        Button("Account settings") { showSync = true }
                    }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if page == .timetable {
                    timetablePage
                } else {
                ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    if cloud.hasUnclaimedLegacy && report == nil && cloud.hasCheckedCloud {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Older SATHI data found on this device").font(.headline)
                            Text("Only import it if it belongs to you. It will be added to \(cloud.email).")
                            Button("Import my older saved data") {
                                do {
                                    try cloud.claimLegacyData()
                                    restore()
                                    observedSnapshot = (try? syncSnapshot()) ?? .init()
                                } catch { notice = error.localizedDescription }
                            }.disabled(cloud.busy)
                        }.padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    VStack(alignment: .leading, spacing: 22) {
                        switch page {
                        case .welcome: welcomePage
                        case .semester: semesterPage
                        case .subjects: selectionPage
                        case .overview: overviewPage
                        case .timetable: timetablePage
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    if !notice.isEmpty {
                        Label(notice, systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: 760, alignment: .leading)
                            .frame(maxWidth: .infinity)
                    }
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, geo.size.width < 550 ? 20 : 36)
                .padding(.top, 24)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
                }
                }
            }
            .background(Color(uiCompatibleBackground: colorScheme))
        }
        .sheet(isPresented: $showSync) {
            VStack {
                CloudSyncPanel(store: cloud) { Task { await syncNow() } }
                Button("Done") { showSync = false }.padding(.bottom)
            }.frame(minWidth: 300, idealWidth: 420)
        }
        .task(id: cloud.accountID) {
            guard let uid = cloud.accountID, cloud.signedIn else { return }
            do { try study.configure(directory: cloud.dataDirectory, uid: uid, journal: cloud.journal) }
            catch { notice = error.localizedDescription; return }
            restore()
            loadedAccountID = uid
            if let report { try? study.ensureSemesterID(seed: report.workbook + (report.sessions.map(\.date).min() ?? "")) }
            observedSnapshot = (try? syncSnapshot()) ?? .init()
            hasRestored = true
            BackgroundSync.liveUID = uid
            BackgroundSync.liveApply = { base, remote in
                guard cloud.accountID == uid, loadedAccountID == uid else { throw SyncFailure.account }
                let current = try syncSnapshot()
                let merged = try SyncSnapshot.merge(base: base, local: current, remote: remote)
                if merged != current { try applySyncSnapshot(merged) }
            }
            if let report { try? study.ensureSemesterID(seed: report.workbook + (report.sessions.map(\.date).min() ?? "")) }
            consumeNotificationAction()
            await refreshSurfaces()
            var nextAutomaticSync = Date().addingTimeInterval(3600)
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { break }
                if scenePhase == .active && cloud.signedIn && loadedAccountID == cloud.accountID {
                    clockNow = Date()
                    await refreshSurfaces()
                }
                // macOS keeps this lightweight timer while the app is running;
                // iOS may suspend it and uses BGAppRefreshTask for background wakes.
                if cloud.signedIn && loadedAccountID == cloud.accountID && Date() >= nextAutomaticSync {
                    nextAutomaticSync = Date().addingTimeInterval(3600)
                    await syncNow(automatic: true)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && cloud.signedIn { clockNow = Date(); Task { await refreshSurfaces() } }
            if phase == .background { BackgroundSync.schedule() }
        }
        .onChange(of: cloud.signedIn) { _, signedIn in
            useCachedCopy = false
            if !signedIn { showSync = false; Task { await ClassReminders.shared.clear() } }
        }
        .sheet(isPresented: $showAppearance) { AppearanceSetupView(store: study) { saveStudy(); showAppearance = false } }
        .sheet(isPresented: $showManualReview) {
            if let report {
                TimetableReviewView(report: report, initialSelection: Set(sessions.map(\.id)), readOnly: false) { updated, chosen in
                    do {
                        let backup = storageDirectory.appendingPathComponent("ManualReview-" + UUID().uuidString, isDirectory: true)
                        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                        try JSONEncoder().encode(report).write(to: backup.appendingPathComponent("timetable.json"), options: .atomic)
                        try JSONEncoder().encode(updated).write(to: storageDirectory.appendingPathComponent("timetable.json"), options: .atomic)
                        let oldByID = Dictionary(report.sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                        for row in updated.sessions {
                            if let old = oldByID[row.id], old.date != row.date || old.time != row.time || old.subject != row.subject { study.workspace.overrides.removeValue(forKey: row.id) }
                        }
                        self.report = updated
                        if study.workspace.preferences.manualSelections == nil { study.workspace.preferences.manualSelections = [:] }
                        study.workspace.preferences.manualSelections?[study.workspace.currentSemesterID] = chosen.sorted()
                        try study.saveWorkspace(); persist(); showManualReview = false
                    } catch { notice = error.localizedDescription }
                }
            }
        }
        .sheet(isPresented: $showWholeSchedule) {
            if let report { TimetableReviewView(report: report, initialSelection: Set(sessions.map(\.id)), readOnly: true, onRequestSchedule: { course in additionalProgramme = course; showWholeSchedule = false; showImporter = true }, onSave: { _, _ in }) }
        }
        .sheet(isPresented: $showHistory) { SemesterHistoryView(store: study) }
        .sheet(isPresented: Binding(get: { attendanceWindow != nil }, set: { if !$0 { attendanceWindow = nil } })) {
            if let window = attendanceWindow {
                ClassAttendanceView(window: window, proof: Binding(get: { study.workspace.proofs[window.id] ?? .init() }, set: { study.workspace.proofs[window.id] = $0 }), penalized: penaltyIDs.contains(window.id)) {
                    saveStudy(); attendanceWindow = nil
                }
            }
        }
        .onChange(of: study.workspace) { _, _ in if hasRestored { saveStudy(); Task { await refreshSurfaces() } } }
        .onReceive(NotificationCenter.default.publisher(for: .sathiClassAction)) { _ in consumeNotificationAction() }
        .onReceive(NotificationCenter.default.publisher(for: .sathiStudyAssetsChanged)) { note in
            guard note.object as? String == cloud.accountID else { return }
            try? study.reloadAssets()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sathiBackgroundSync)) { note in
            guard let update = note.object as? BackgroundSyncUpdate, update.uid == cloud.accountID, loadedAccountID == update.uid else { return }
            do { try applySyncSnapshot(SyncSnapshot.merge(base: update.base, local: syncSnapshot(), remote: update.remote)) }
            catch { notice = "Background changes are saved on disk. Refresh to resolve: " + error.localizedDescription }
        }
        .preferredColorScheme(study.workspace.preferences.colorScheme)
        .dynamicTypeSize(study.workspace.preferences.textSize)
        .environment(\.studyGlassOpacity, study.workspace.preferences.glassOpacity)
        .environment(\.studyGlassStyle, study.workspace.preferences.glassStyle ?? "regular")
        .accentColor(accent)
        .tint(accent)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { importExcel(url) }
            case .failure(let error): additionalProgramme = nil; nextSemesterImport = false; notice = error.localizedDescription
            }
        }
        .fileExporter(isPresented: $showExport, document: exportDocument,
                      contentType: .json, defaultFilename: exportFilename) { result in
            if case .failure(let error) = result { notice = error.localizedDescription }
        }
        .sheet(isPresented: $showAddEvent) {
            SATHIEventEditor(date: selectedDate, subjects: activeSubjects.map(\.name)) { event in
                customEvents.append(event)
                saveExtras()
            }
        }
        .onChange(of: minimumAttendance) { _, _ in
            if hasRestored, cloud.signedIn { persist() }
        }
        .onChange(of: page) { _, value in
            guard hasRestored, cloud.signedIn else { return }
            do { try cloud.journal.record("screen_opened", details: ["screen": value.rawValue]) }
            catch { notice = "Activity log could not be saved: \(error.localizedDescription)" }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(accent.gradient, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text("SATHI").font(.title3.bold())
                Text("Your campus, in sync.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if report != nil {
                Menu {
                    Button("My timetable", systemImage: "calendar") { page = .timetable }
                    Button("My subjects", systemImage: "books.vertical") { page = .overview }
                    if isSecondYear { Button("Edit selection", systemImage: "checklist") { page = .subjects } }
                    Button("Change semester", systemImage: "graduationcap") { page = .semester }
                    Button("Semester history", systemImage: "clock.arrow.circlepath") { showHistory = true }
                    Button("Replace Excel", systemImage: "arrow.triangle.2.circlepath") { showImporter = true }
                    Button("Export JSON", systemImage: "square.and.arrow.up") { prepareExport() }
                    Button("Export activity JSON", systemImage: "clock.arrow.circlepath") { prepareActivityExport() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("More options")
            }
        }
    }

    private var welcomePage: some View {
        onboardingBackdrop {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Your timetable, simplified.")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("A quieter way to stay on top of classes, credits and campus events.")
                    .font(.body).foregroundStyle(.secondary)
            }
            panel {
                VStack(spacing: 18) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(accent)
                    Text("Start with your timetable")
                        .font(.title3.bold())
                    Text("Choose your Excel (.xlsx) file. SATHI will organize the schedule for you.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button { page = .semester } label: {
                        Label(importing ? "Reading timetable…" : "Set up my timetable", systemImage: "arrow.up.doc")
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(importing)
                    if importing { ProgressView() }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
            }
            Label("Upload once. Your saved timetable syncs to your other devices.", systemImage: "icloud")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    }

    private var semesterPage: some View {
        onboardingBackdrop {
        VStack(alignment: .leading, spacing: 20) {
            stepLabel("01 / SETUP")
            Text("Which semester are you in?")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("We'll personalize your setup for your academic year.")
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                ForEach(1...6, id: \.self) { number in
                    Button {
                        semester = number
                        study.workspace.preferences.studentSemester = number
                        persist()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Semester \(number)").font(.headline)
                                Text(number <= 3 ? "First year" : "Second year")
                                    .font(.caption).foregroundStyle(semester == number ? Color.white.opacity(0.85) : .secondary)
                            }
                            Spacer(minLength: 0)
                            if semester == number { Image(systemName: "checkmark.circle.fill") }
                        }
                        .foregroundStyle(semester == number ? Color.white : Color.primary)
                        .padding(16).frame(maxWidth: .infinity, minHeight: 80)
                        .background(semester == number ? accent : accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(semester == number ? 0.8 : 0.18)))
                    }.buttonStyle(.plain)
                }
            }
            Picker("Programme", selection: $study.workspace.preferences.programme) {
                ForEach(["MBA", "DBM", "DBAI", "HHM"], id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: study.workspace.preferences.programme) { _, _ in
                selectedKeys = []
                study.workspace.preferences.firstYearSection = ""
                persist()
            }
            if let semester, semester <= 3 {
                Text("All first-year subjects are included. Choose your section once; it is remembered through semester 3.").font(.subheadline)
                if study.workspace.preferences.programme == "MBA" || !sectionLabels.isEmpty {
                    Picker("Your section", selection: $study.workspace.preferences.firstYearSection) {
                        Text("Choose section").tag("")
                        ForEach(sectionLabels.isEmpty ? ["A", "B", "C", "D"] : sectionLabels, id: \.self) { Text("Section " + $0).tag($0) }
                    }
                }
            }
            Button {
                guard let semester else { return }
                if report == nil { showImporter = true; return }
                if semester <= 3 {
                    page = .overview
                } else {
                    page = .subjects
                }
                persist()
            } label: {
                HStack { Text("Continue"); Spacer(); Image(systemName: "arrow.right") }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(semester == nil || ((semester ?? 0) <= 3 && (sectionLabels.count > 1 || (report == nil && study.workspace.preferences.programme == "MBA")) && study.workspace.preferences.firstYearSection.isEmpty))
            Button("Choose a different Excel file") { showImporter = true }
                .font(.subheadline)
        }
    }

    }

    private var selectionPage: some View {
        onboardingBackdrop {
        VStack(alignment: .leading, spacing: 18) {
            stepLabel("02 / PERSONALIZE")
            Text("Choose your subjects")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Pick your electives and the section you attend. Only one section per subject can be selected.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                statistic("Subjects", "\(selectedKeys.count)")
                statistic("Credits", creditText(credits))
            }
            TextField("Search subjects", text: $query)
                .textFieldStyle(.roundedBorder)
            LazyVStack(spacing: 10) {
                ForEach(groups) { group in
                    panel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.name).font(.headline)
                            ForEach(group.variants, id: \.key) { subject in
                                Button {
                                    if selectedKeys.contains(subject.key) {
                                        selectedKeys.remove(subject.key)
                                    } else {
                                        group.variants.forEach { selectedKeys.remove($0.key) }
                                        selectedKeys.insert(subject.key)
                                    }
                                    persist()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedKeys.contains(subject.key) ? "checkmark.circle.fill" : "circle")
                                            .font(.title3).foregroundStyle(accent)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(sectionName(subject)).font(.subheadline.weight(.medium))
                                            Text("\(subject.count) classes · \(creditText(subject.credits)) credits")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            Button {
                page = .overview
                persist()
            } label: {
                HStack { Text("Review my subjects"); Spacer(); Image(systemName: "arrow.right") }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(selectedKeys.isEmpty)
        }
    }

    }

    private var overviewPage: some View {
        onboardingBackdrop {
        VStack(alignment: .leading, spacing: 18) {
            stepLabel(isSecondYear ? "03 / REVIEW" : "02 / YOUR COURSES")
            Text(isSecondYear ? "Your chosen subjects" : "Your subjects")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Semester \(semester ?? 1) · \(activeSubjects.count) subjects")
                .foregroundStyle(.secondary)
            Button("Check or correct my timetable", systemImage: "tablecells.badge.ellipsis") { showManualReview = true }
            Text("Recommended if a subject, class count or time looks wrong. Your predicted classes start selected.").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                statistic("Total credits", creditText(credits))
                statistic("Classes", "\(sessions.count)")
            }
            if let warnings = report?.warnings, !warnings.isEmpty {
                DisclosureGroup("Import review (\(warnings.count))") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning).font(.caption).textSelection(.enabled)
                        }
                    }
                }
            }
            LazyVStack(spacing: 10) {
                ForEach(activeSubjects, id: \.key) { subject in
                    panel {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "book.closed")
                                .foregroundStyle(accent).frame(width: 24)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(subject.name).font(.headline)
                                Text(professors(for: subject).isEmpty ? "Faculty not listed" : professors(for: subject).joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text("\(subject.count) classes")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 6)
                            Text("\(creditText(subject.credits)) cr")
                                .font(.subheadline.bold()).foregroundStyle(accent)
                        }
                    }
                }
            }
            if activeSubjects.contains(where: { $0.credits == 0 }) {
                Label("Some credits are unverified because their class counts don't match the known credit mapping.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button {
                page = .timetable
                selectedDate = Date()
                monthOffset = 0
                persist()
            } label: {
                HStack { Text("Next · View timetable"); Spacer(); Image(systemName: "arrow.right") }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }.buttonStyle(.borderedProminent).controlSize(.large)
            if isSecondYear { Button("Edit subject selection") { page = .subjects } }
        }
    }

    }

    private var timetablePage: some View {
        let currentSessions = sessions
        let ids = Set(currentSessions.map(\.id))
        return SATHICommandCenter(
            sessions: currentSessions,
            otherSectionSessions: programmeSessions.filter { candidate in
                !ids.contains(candidate.id)
            },
            subjects: activeSubjects,
            events: events,
            custom: customEvents.map {
                SATHICommandEvent(id: "custom-" + $0.id.uuidString, date: $0.date,
                                  title: $0.title, time: "\($0.start) – \($0.end)")
            },
            selectedDate: $selectedDate,
            attendance: effectiveAttendance,
            onAttendanceChange: { id, status in
                if let status { attendance[id] = status }
                if status == "OD" {
                    var proof = study.workspace.proofs[id] ?? .init(); proof.officialDuty = true; study.workspace.proofs[id] = proof
                } else if var proof = study.workspace.proofs[id], proof.officialDuty {
                    proof.officialDuty = false; study.workspace.proofs[id] = proof
                }
                if status == "Attended" || status == "Missed" {
                    var proof = study.workspace.proofs[id] ?? .init(); proof.attended = status == "Attended"; proof.updatedAt = Date(); study.workspace.proofs[id] = proof
                }
                if status == nil { attendance.removeValue(forKey: id); study.workspace.proofs.removeValue(forKey: id) }
                saveExtras()
            },
            onAddEvent: { showAddEvent = true },
            onDeleteCustomEvent: { id in
                customEvents.removeAll { $0.id.uuidString == id }
                saveExtras()
            },
            onSubjects: { page = .overview },
            onEditSelection: { page = .subjects },
            onChangeSemester: { page = .semester },
            onReplaceExcel: { showImporter = true },
            onExport: { prepareExport() },
            onExportActivity: { prepareActivityExport() },
            target: $minimumAttendance,
            study: study,
            windows: classWindows,
            endDates: endDates,
            penaltyIDs: penaltyIDs,
            onProof: { id in attendanceWindow = classWindows.first { $0.id == id } },
            onAppearance: { showAppearance = true },
            onSync: { Task { await syncNow() } }, onAccount: { showSync = true }, syncing: cloud.busy, syncStatus: cloud.status,
            onHistory: { showHistory = true },
            onNextSemester: { nextSemesterImport = true; showImporter = true },
            canStartNextSemester: canStartNextSemester,
            canEditSelection: isSecondYear,
            onManualReview: { showManualReview = true },
            onWholeSchedule: { showWholeSchedule = true },
            customEvents: customEvents,
            onEditCustom: { updated in
                if let index = customEvents.firstIndex(where: { $0.id == updated.id }) { customEvents[index] = updated; saveExtras() }
            },
            lectureOrdinals: lectureOrdinals,
            timetableReport: report,
            onRequestProgramme: { course in additionalProgramme = course; showImporter = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func classCard(_ session: TimetableSession) -> some View {
        let status = attendance[session.id]
        let isFuture = sessionStart(session).map { $0 > Date() } ?? false
        return panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "book.closed.fill").foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.subject).font(.headline)
                        Text(session.time).font(.subheadline).foregroundStyle(.secondary)
                        if !session.teacher.isEmpty {
                            Text(session.teacher).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    if let status {
                        Text(status).font(.caption.weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(status == "Missed" ? Color.red.opacity(0.13) : accent.opacity(0.13),
                                        in: Capsule())
                    }
                }
                Menu {
                    if isFuture {
                        Button("Planning to attend", systemImage: "checkmark.circle") { setAttendance(session.id, "Planning to attend") }
                        Button("Planning to miss", systemImage: "calendar.badge.minus") { setAttendance(session.id, "Planning to miss") }
                        Button("OD", systemImage: "person.crop.rectangle") { setAttendance(session.id, "OD") }
                    } else {
                        Button("Attended", systemImage: "checkmark.circle") { setAttendance(session.id, "Attended") }
                        Button("Missed", systemImage: "xmark.circle") { setAttendance(session.id, "Missed") }
                        Button("OD", systemImage: "person.crop.rectangle") { setAttendance(session.id, "OD") }
                    }
                    Button("Clear status", systemImage: "arrow.uturn.backward") {
                        attendance.removeValue(forKey: session.id); saveExtras()
                    }
                } label: {
                    HStack {
                        Text(status ?? (isFuture ? "Plan attendance" : "Mark attendance"))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                }
                .menuStyle(.borderlessButton)
            }
        }
    }

    private func eventCard(title: String, time: String, type: String) -> some View {
        panel {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text("\(type) · \(time)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var monthCalendar: some View {
        let calendar = Calendar.current
        let currentMonth = calendar.date(byAdding: .month, value: monthOffset, to: calendar.startOfDay(for: Date())) ?? Date()
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let weekdayOffset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
        return panel {
            VStack(spacing: 14) {
                HStack {
                    Text(first.formatted(.dateTime.month(.wide).year())).font(.title3.bold())
                    Spacer()
                    Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }
                    Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }
                }.buttonStyle(.borderless)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(0..<7, id: \.self) { i in
                        let weekday = (calendar.firstWeekday - 1 + i) % 7 + 1
                        Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ForEach(0..<(weekdayOffset + count), id: \.self) { index in
                        if index < weekdayOffset {
                            Color.clear.frame(height: 43)
                        } else {
                            let day = index - weekdayOffset + 1
                            let date = calendar.date(byAdding: .day, value: day - 1, to: first) ?? first
                            let dateKey = dateString(date)
                            let hasClasses = sessions.contains { $0.date == dateKey }
                            let hasEvents = events.contains { $0.date == dateKey } || customEvents.contains { $0.date == dateKey }
                            Button {
                                selectedDate = date
                            } label: {
                                VStack(spacing: 4) {
                                    Text("\(day)").font(.subheadline.weight(calendar.isDate(date, inSameDayAs: selectedDate) ? .bold : .regular))
                                    HStack(spacing: 3) {
                                        if hasClasses { Circle().fill(accent).frame(width: 4, height: 4) }
                                        if hasEvents { Circle().fill(.orange).frame(width: 4, height: 4) }
                                    }.frame(height: 5)
                                }
                                .frame(maxWidth: .infinity).frame(height: 43)
                                .background(calendar.isDate(date, inSameDayAs: selectedDate) ? accent.opacity(0.20) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                        }
                    }
                }
                HStack(spacing: 14) {
                    Label("Classes", systemImage: "circle.fill").foregroundStyle(accent)
                    Label("Events", systemImage: "circle.fill").foregroundStyle(.orange)
                    Spacer()
                }.font(.caption)
            }
        }
    }

    private func shiftDay(_ offset: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) ?? selectedDate
        let current = Calendar.current.dateComponents([.year, .month], from: Date())
        let chosen = Calendar.current.dateComponents([.year, .month], from: selectedDate)
        monthOffset = ((chosen.year ?? 0) - (current.year ?? 0)) * 12 + (chosen.month ?? 1) - (current.month ?? 1)
    }

    private func sessionStart(_ session: TimetableSession) -> Date? {
        let first = session.time.components(separatedBy: "-").first?.trimmingCharacters(in: .whitespaces) ?? ""
        let normalized = first.replacingOccurrences(of: ".", with: ":")
        let formats = ["yyyy-MM-dd HH:mm", "yyyy-MM-dd h:mm a", "yyyy-MM-dd h:mma"]
        for format in formats {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_IN"); f.dateFormat = format
            if let date = f.date(from: "\(session.date) \(normalized)") { return date }
        }
        return nil
    }


    private func syncSnapshot() throws -> SyncSnapshot {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var snapshot = SyncSnapshot()
        if let report {
            snapshot.records["timetable"] = try encoder.encode(report)
            snapshot.records["selection"] = try encoder.encode(SyncSelection(semester: semester, keys: selectedKeys.sorted(), minimumAttendance: minimumAttendance))
        }
        for (id, value) in attendance { snapshot.records["attendance:" + id] = try encoder.encode(value) }
        for event in customEvents { snapshot.records["event:" + event.id.uuidString] = try encoder.encode(event) }
        // An untouched new device has no local study edits. Publishing defaults here
        // would conflict with the existing account's preferences before first download.
        if study.workspace.shouldPublish(hasTimetable: report != nil) {
            for (key, value) in try study.workspaceRecords() { snapshot.records[key] = value }
        }
        return snapshot
    }

    @MainActor private func syncNow(automatic: Bool = false) async {
        if automatic && !SyncCadence.isDue(lastSync: cloud.lastSync, now: Date()) { return }
        guard !cloud.busy, let uid = cloud.accountID, loadedAccountID == uid, hasRestored else { return }
        do {
            let captured = try syncSnapshot()
            await cloud.sync(local: captured) { downloaded in
                guard cloud.accountID == uid, loadedAccountID == uid else { throw SyncFailure.account }
                let current = try syncSnapshot()
                let merged = try SyncSnapshot.merge(base: captured, local: current, remote: downloaded)
                if merged != current { try applySyncSnapshot(merged) }
            }
            await study.sync()
        } catch { notice = "Could not prepare sync: \(error.localizedDescription)" }
    }

    private func applySyncSnapshot(_ snapshot: SyncSnapshot) throws {
        let decoder = JSONDecoder()
        let originalReport = try snapshot.records["timetable"].map { try decoder.decode(TimetableReport.self, from: $0) }
        let repaired = originalReport.map { TimetableIdentity.repair($0) }
        let newReport = repaired?.report
        var selection = try snapshot.records["selection"].map { try decoder.decode(SyncSelection.self, from: $0) }
        if let old = selection, let repaired, repaired.changed {
            selection = SyncSelection(semester: old.semester, keys: Array(Set(old.keys.map { repaired.keys[$0] ?? $0 })).sorted(), minimumAttendance: old.minimumAttendance)
        }
        let incomingWorkspace = try study.decodeWorkspace(snapshot.records)
        var newAttendance: [String: String] = [:]
        var newEvents: [SATHICustomEvent] = []
        for (key, data) in snapshot.records {
            if key.hasPrefix("attendance:") { newAttendance[String(key.dropFirst(11))] = try decoder.decode(String.self, from: data) }
            else if key.hasPrefix("event:") {
                let event = try decoder.decode(SATHICustomEvent.self, from: data)
                guard key == "event:" + event.id.uuidString else { throw SyncFailure.invalidData }
                newEvents.append(event)
            } else if key != "timetable" && key != "selection" && !key.hasPrefix("study:") { throw SyncFailure.invalidData }
        }
        guard (newReport != nil) == (selection != nil) else { throw SyncFailure.invalidData }
        // Retain device files in a timestamped backup before applying any cloud changes.
        let backup = storageDirectory.appendingPathComponent("SyncBackups/" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        let names = ["timetable.json", "preferences.json", "attendance.json", "customEvents.json", "Study/workspace.json"]
        var prior: [String: Data] = [:]
        for name in names {
            let url = storageDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                prior[name] = data
                let destination = backup.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destination, options: .atomic)
            }
        }
        let encoder = JSONEncoder()
        let newPage: Page
        if newReport == nil { newPage = .welcome }
        else if selection?.semester == nil { newPage = .semester }
        else if (selection?.semester ?? 0) >= 4 && (selection?.keys.isEmpty ?? true) { newPage = .subjects }
        else { newPage = page == .welcome ? .timetable : page }
        var files = ["attendance.json": try encoder.encode(newAttendance), "customEvents.json": try encoder.encode(newEvents.sorted { $0.id.uuidString < $1.id.uuidString }), "Study/workspace.json": try encoder.encode(incomingWorkspace)]
        if let newReport, let selection {
            files["timetable.json"] = try encoder.encode(newReport)
            files["preferences.json"] = try encoder.encode(Preferences(semester: selection.semester, keys: selection.keys, page: newPage.rawValue, minimumAttendance: selection.minimumAttendance))
        }
        do {
            for name in names {
                let url = storageDirectory.appendingPathComponent(name)
                if let data = files[name] { try data.write(to: url, options: .atomic) }
                else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
        } catch {
            for name in names {
                let url = storageDirectory.appendingPathComponent(name)
                if let data = prior[name] { try? data.write(to: url, options: .atomic) }
                else { try? FileManager.default.removeItem(at: url) }
            }
            throw error
        }
        report = newReport
        minimumAttendance = selection?.minimumAttendance ?? 80
        semester = selection?.semester
        selectedKeys = Set(selection?.keys ?? [])
        attendance = newAttendance
        customEvents = newEvents
        page = newPage
        study.workspace = incomingWorkspace
        study.workspace.preferences.studentSemester = semester
        observedSnapshot = snapshot
    }

    private func setAttendance(_ id: String, _ value: String) {
        attendance[id] = value
        saveExtras()
    }

    private func recordSavedChanges() throws {
        guard hasRestored, cloud.signedIn, loadedAccountID == cloud.accountID else { return }
        let current = try syncSnapshot()
        for key in Set(observedSnapshot.records.keys).union(current.records.keys).sorted() {
            guard observedSnapshot.records[key] != current.records[key] else { continue }
            var details = ["record": key, "operation": current.records[key] == nil ? "delete" : "save"]
            if key == "timetable" {
                details["workbook"] = report?.workbook ?? ""
                details["classCount"] = String(report?.sessions.count ?? 0)
            } else if let data = current.records[key] {
                details["valueJSON"] = String(data: data, encoding: .utf8)
            }
            try cloud.journal.record("record_changed", details: details)
        }
        observedSnapshot = current
    }

    private func saveExtras() {
        guard cloud.signedIn, loadedAccountID == cloud.accountID else { return }
        do {
            try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(attendance).write(to: storageDirectory.appendingPathComponent("attendance.json"), options: .atomic)
            try JSONEncoder().encode(customEvents).write(to: storageDirectory.appendingPathComponent("customEvents.json"), options: .atomic)
            try recordSavedChanges()
        } catch { notice = "Could not save updates: \(error.localizedDescription)" }
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(accent.opacity(0.15), lineWidth: 1))
            .shadow(color: accent.opacity(0.045), radius: 15, y: 7)
    }
    private func onboardingBackdrop<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                Text("SATHI · ACADEMIC SPACE")
            }
            .font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(accent)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(accent.opacity(0.10), in: Capsule())
            content()
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(accent.opacity(colorScheme == .dark ? 0.055 : 0.035))
        )
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(accent.opacity(0.12)))
    }
    private func statistic(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.title2.bold()).foregroundStyle(accent)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }
    private func stepLabel(_ text: String) -> some View {
        Text(text).font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(accent)
    }
    private func sectionName(_ subject: TimetableSubject) -> String {
        let components = subject.key.components(separatedBy: "|")
        return components.count > 1 && !components[1].isEmpty ? "Section \(components[1])" : "Common subject"
    }
    private func professors(for subject: TimetableSubject) -> [String] {
        Array(Set(programmeSessions
            .filter { $0.subject + "|" + $0.section == subject.key }
            .map(\.teacher).filter { !$0.isEmpty })).sorted()
    }
    private func creditText(_ value: Double) -> String { String(format: "%g", value) }
    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    private func setDate(_ string: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let value = formatter.date(from: string) { selectedDate = value }
    }
    private var storageDirectory: URL {
        cloud.dataDirectory
    }
    private struct Preferences: Codable { let semester: Int?; let keys: [String]; let page: String; var minimumAttendance: Int? = nil }
    private func persist() {
        guard cloud.signedIn, loadedAccountID == cloud.accountID else { return }
        do {
            try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            if let report {
                try JSONEncoder().encode(report).write(to: storageDirectory.appendingPathComponent("timetable.json"), options: .atomic)
            }
            let preferences = Preferences(semester: semester, keys: selectedKeys.sorted(), page: page.rawValue, minimumAttendance: minimumAttendance)
            try JSONEncoder().encode(preferences).write(to: storageDirectory.appendingPathComponent("preferences.json"), options: .atomic)
            try recordSavedChanges()
        } catch { notice = "Could not save: \(error.localizedDescription)" }
    }
    private func restore() {
        guard report == nil else { return }
        guard let data = try? Data(contentsOf: storageDirectory.appendingPathComponent("timetable.json")),
              let saved = try? JSONDecoder().decode(TimetableReport.self, from: data) else { return }
        report = saved
        if let data = try? Data(contentsOf: storageDirectory.appendingPathComponent("attendance.json")),
           let stored = try? JSONDecoder().decode([String: String].self, from: data) { attendance = stored }
        if let data = try? Data(contentsOf: storageDirectory.appendingPathComponent("customEvents.json")),
           let stored = try? JSONDecoder().decode([SATHICustomEvent].self, from: data) { customEvents = stored }
        if let data = try? Data(contentsOf: storageDirectory.appendingPathComponent("preferences.json")),
           let prefs = try? JSONDecoder().decode(Preferences.self, from: data) {
            minimumAttendance = prefs.minimumAttendance ?? 80
            semester = prefs.semester
            study.workspace.preferences.studentSemester = semester
            selectedKeys = Set(prefs.keys).intersection(Set(saved.subjects.map(\.key)))
            page = Page(rawValue: prefs.page) ?? .semester
            if page == .welcome { page = .semester }
            if page == .subjects && !isSecondYear { page = .overview }
            if isSecondYear && selectedKeys.isEmpty && (page == .overview || page == .timetable) { page = .subjects }
        } else { page = .semester }
        let repaired = TimetableIdentity.repair(saved)
        if repaired.changed {
            let preferencesURL = storageDirectory.appendingPathComponent("preferences.json")
            let originalPreferences = try? Data(contentsOf: preferencesURL)
            do {
                let backup = storageDirectory.appendingPathComponent("ImportRepair-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                try data.write(to: backup.appendingPathComponent("timetable.json"), options: .atomic)
                if let oldPreferences = originalPreferences {
                    try oldPreferences.write(to: backup.appendingPathComponent("preferences.json"), options: .atomic)
                }
                let keys = Set(selectedKeys.map { repaired.keys[$0] ?? $0 })
                let preferences = Preferences(semester: semester, keys: keys.sorted(), page: page.rawValue, minimumAttendance: minimumAttendance)
                try JSONEncoder().encode(repaired.report).write(to: storageDirectory.appendingPathComponent("timetable.json"), options: .atomic)
                try JSONEncoder().encode(preferences).write(to: preferencesURL, options: .atomic)
                report = repaired.report
                selectedKeys = keys
                notice = "Imported subject names repaired. Original import backed up; attendance and notes preserved."
            } catch {
                try? data.write(to: storageDirectory.appendingPathComponent("timetable.json"), options: .atomic)
                if let originalPreferences { try? originalPreferences.write(to: preferencesURL, options: .atomic) }
                notice = "Import repair could not be saved: \(error.localizedDescription)"
            }
        }
        selectedDate = Date()
    }
    private func importExcel(_ url: URL) {
        guard let importAccount = cloud.accountID, loadedAccountID == importAccount else { return }
        importing = true
        notice = "Reading \(url.lastPathComponent)…"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let sourceData = try Data(contentsOf: url)
                let parsed = try TimetableLogic().read(url: url)
                DispatchQueue.main.async {
                    guard cloud.accountID == importAccount, loadedAccountID == importAccount else { return }
                    importing = false
                    guard !parsed.sessions.isEmpty else {
                        notice = "No classes detected. Please check the workbook layout."
                        return
                    }
                    // Keep the original workbook privately for later audits/reparsing.
                    do {
                        let sources = storageDirectory.appendingPathComponent("ImportSources", isDirectory: true)
                        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
                        try sourceData.write(to: sources.appendingPathComponent(UUID().uuidString + ".xlsx"), options: .atomic)
                    } catch { notice = "Could not preserve the source workbook: \(error.localizedDescription)"; return }
                    if let existing = report, !nextSemesterImport, semester != nil,
                       TimetableIdentity.canSupplement(existing, with: parsed), selectedKeys.isSubset(of: Set(parsed.subjects.map(\.key))) {
                        do {
                            let backup = storageDirectory.appendingPathComponent("ImportRepair-" + UUID().uuidString, isDirectory: true)
                            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                            try JSONEncoder().encode(existing).write(to: backup.appendingPathComponent("timetable.json"), options: .atomic)
                            try JSONEncoder().encode(parsed).write(to: storageDirectory.appendingPathComponent("timetable.json"), options: .atomic)
                            report = parsed
                            page = .overview
                            notice = "Restored \(parsed.sessions.count - existing.sessions.count) omitted classes. Attendance, notes and selections retained."
                            persist()
                        } catch { notice = "Could not repair the saved import: \(error.localizedDescription)" }
                        return
                    }
                    if let course = additionalProgramme, let existing = report {
                        do {
                            let matching = parsed.sessions.filter { TimetableIdentity.programme(source: $0.source) == course }
                            let incoming = (matching.isEmpty ? parsed.sessions : matching).map { row in
                                TimetableSession(id: course + "-" + row.id, date: row.date, day: row.day, time: row.time, subject: row.subject, section: row.section, teacher: row.teacher, source: course + " / " + row.source)
                            }
                            var identities = Set(existing.sessions.map { $0.date + "|" + $0.time + "|" + $0.subject + "|" + $0.section + "|" + TimetableIdentity.programme(source: $0.source) })
                            let added = incoming.filter { identities.insert($0.date + "|" + $0.time + "|" + $0.subject + "|" + $0.section + "|" + course).inserted }
                            let all = existing.sessions + added
                            let moreEvents = parsed.events.filter { matching.isEmpty || TimetableIdentity.programme(source: $0.source) == course }.map { TimetableEvent(date: $0.date, time: $0.time, title: $0.title, source: course + " / " + $0.source) }
                            let merged = TimetableReport(workbook: existing.workbook, sessions: all, subjects: TimetableIdentity.subjects(all), events: existing.events + moreEvents, warnings: existing.warnings + parsed.warnings)
                            let backup = storageDirectory.appendingPathComponent("AdditionalSchedule-" + UUID().uuidString, isDirectory: true)
                            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                            try JSONEncoder().encode(existing).write(to: backup.appendingPathComponent("timetable.json"), options: .atomic)
                            try JSONEncoder().encode(merged).write(to: storageDirectory.appendingPathComponent("timetable.json"), options: .atomic)
                            report = merged; additionalProgramme = nil; persist(); showWholeSchedule = true
                            notice = "Added the \(course) schedule. Your own timetable and attendance were retained."
                        } catch { notice = error.localizedDescription }
                        return
                    }
                    let firstSetup = report == nil
                    let previousSemester = semester
                    do { try archiveCurrentSemester() }
                    catch { notice = "Could not preserve the previous semester: \(error.localizedDescription)"; return }
                    report = parsed
                    let available = Set(parsed.sessions.map { TimetableIdentity.programme(source: $0.source) })
                    if !available.contains(study.workspace.preferences.programme), let first = available.sorted().first {
                        study.workspace.preferences.programme = first
                    }
                    selectedKeys = []
                    attendance = [:]
                    customEvents = []
                    study.workspace.proofs = [:]
                    study.workspace.overrides = [:]
                    study.workspace.currentSemesterID = UUID().uuidString
                    semester = nextSemesterImport ? (previousSemester ?? 0) + 1 : (firstSetup ? previousSemester : nil)
                    nextSemesterImport = false
                    study.workspace.preferences.studentSemester = semester
                    saveExtras()
                    page = semester == nil ? .semester : ((semester ?? 0) <= 3 ? .overview : .subjects)
                    selectedDate = Date()
                    notice = semester == nil ? "Timetable imported. Choose your semester to continue." : "Next semester imported. Your previous semester is in History."
                    persist()
                    do { try cloud.journal.record("excel_imported", details: ["filename": url.lastPathComponent, "classes": String(parsed.sessions.count), "subjects": String(parsed.subjects.count)]) }
                    catch { notice = "Timetable saved, but activity logging failed: \(error.localizedDescription)" }
                }
            } catch {
                DispatchQueue.main.async {
                    guard cloud.accountID == importAccount, loadedAccountID == importAccount else { return }
                    importing = false
                    notice = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }
    private func refreshSurfaces() async {
        guard let uid = cloud.accountID, loadedAccountID == uid, hasRestored else { return }
        let rows = sessions
        var hash = Hasher()
        for row in rows { hash.combine(row.id); hash.combine(row.date); hash.combine(row.time); hash.combine(row.subject) }
        let signature = hash.finalize()
        if signature != windowSignature {
            let parsed = await Task.detached(priority: .utility) {
                rows.compactMap { ClassWindow.make(id: $0.id, subject: $0.subject, date: $0.date, time: $0.time) }
            }.value
            guard !Task.isCancelled, cloud.accountID == uid else { return }
            cachedWindows = parsed.sorted { $0.start < $1.start }; endDates = Dictionary(parsed.map { ($0.id, $0.end) }, uniquingKeysWith: { _, last in last }); windowSignature = signature
        }
        await ClassReminders.shared.publish(windows: classWindows, preferences: study.workspace.preferences, proofs: study.workspace.proofs, accountID: uid, events: EventPresentation.widgetRows(EventPresentation.applyingOverrides(
            events.map { SATHICommandEvent(id: $0.id ?? "excel-" + $0.source + "-" + $0.time, date: $0.date, title: $0.title, time: $0.time) } + customEvents.map { SATHICommandEvent(id: "custom-" + $0.id.uuidString, date: $0.date, title: $0.title, time: $0.start + " – " + $0.end) }, overrides: study.workspace.overrides, semesterID: study.workspace.currentSemesterID
        )))
        guard !Task.isCancelled, cloud.accountID == uid, loadedAccountID == uid else { return }
        await ClassReminders.shared.schedule(windows: classWindows, preferences: study.workspace.preferences, accountID: uid, proofs: study.workspace.proofs)
        surfaceStatus = ClassReminders.shared.status
    }
    private func consumeNotificationAction() {
        guard let info = UserDefaults.standard.dictionary(forKey: "SATHIPendingAction"),
              info["accountID"] as? String == cloud.accountID, loadedAccountID == cloud.accountID else { return }
        UserDefaults.standard.removeObject(forKey: "SATHIPendingAction")
        page = .timetable
        guard let id = info["classID"] as? String, let window = classWindows.first(where: { $0.id == id }) else { return }
        if info["action"] as? String == "FINGERPRINT_DONE" {
            var proof = study.workspace.proofs[id] ?? .init()
            proof.fingerprint = true; proof.updatedAt = Date(); study.workspace.proofs[id] = proof
            saveStudy()
        }
        selectedDate = window.start
        attendanceWindow = window
        #if os(iOS)
        if study.workspace.preferences.haptics { UISelectionFeedbackGenerator().selectionChanged() }
        #endif
    }

    private var classWindows: [ClassWindow] {
        cachedWindows
    }
    private var penaltyIDs: Set<String> { study.workspace.preferences.proofCrosscheck == true ? AttendanceRules.penaltyIDs(windows: classWindows, proofs: study.workspace.proofs, now: clockNow) : [] }
    private var effectiveAttendance: [String: String] {
        if study.workspace.preferences.proofCrosscheck != true { return AttendanceRules.simple(proofs: study.workspace.proofs, recorded: attendance) }
        return AttendanceRules.effective(windows: classWindows, proofs: study.workspace.proofs, recorded: attendance, now: clockNow)
    }
    private var canStartNextSemester: Bool { !sessions.isEmpty && ((sessions.map(\.date).max() ?? "9999") < dateString(Date())) && ((events.filter { $0.title.lowercased().contains("exam") }.map(\.date).max() ?? "0000") < dateString(Date())) }
    private func saveStudy() {
        guard hasRestored, loadedAccountID == cloud.accountID else { return }
        do { try study.saveWorkspace(); try recordSavedChanges() }
        catch { notice = "Could not save study settings: \(error.localizedDescription)" }
    }
    private func archiveCurrentSemester() throws {
        guard let report else { return }
        let term = study.workspace.currentSemesterID.isEmpty ? UUID().uuidString : study.workspace.currentSemesterID
        let archiveReport = report
        let archive = ArchivedSemester(report: archiveReport, number: semester ?? 0, selectedKeys: selectedKeys.sorted(), attendance: effectiveAttendance, proofRecords: study.workspace.proofs, overrides: study.workspace.overrides, semesterID: term, section: study.workspace.preferences.firstYearSection, customEvents: customEvents, minimumAttendance: minimumAttendance, selectedSessionIDs: sessions.map(\.id))
        try study.saveAsset(id: "semester-" + term, kind: "semester", title: "Semester \(semester ?? 0) · \(report.workbook)", subject: "", semesterID: term, data: JSONEncoder().encode(archive))
    }

    private func prepareActivityExport() {
        do {
            try cloud.journal.record("export_requested", details: ["format": "activity_json"])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            exportDocument = SATHIJSONDocument(data: try encoder.encode(cloud.journal.entries))
            exportFilename = "SATHI_Activity"
            showExport = true
        } catch { notice = "Could not export activity: \(error.localizedDescription)" }
    }

    private func prepareExport() {
        guard let report, let data = try? JSONEncoder().encode(report) else { return }
        exportFilename = "SATHI_Timetable"
        exportDocument = SATHIJSONDocument(data: data)
        do { try cloud.journal.record("export_requested", details: ["format": "timetable_json"]) }
        catch { notice = "Activity log could not be saved: \(error.localizedDescription)" }
        showExport = true
    }
}

private struct SATHIJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data = Data()
    init() {}
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private extension Color {
    init(uiCompatibleBackground scheme: ColorScheme) {
        self = scheme == .dark ? Color(red: 0.075, green: 0.085, blue: 0.12) : Color(red: 0.985, green: 0.988, blue: 0.997)
    }
}

// Student-added events are stored separately from the imported Excel timetable.

private struct SATHIEventEditor: View {
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let subjects: [String]
    let onSave: (SATHICustomEvent) -> Void
    @State private var title = ""
    @State private var type = "Quiz"
    @State private var subject = "None"
    @State private var notes = ""
    @State private var chosenDate = Date()
    @State private var regular = true
    @State private var slot = "08:15 – 09:45"
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(5400)
    private let slots = ["08:15 – 09:45", "10:00 – 11:30", "11:45 – 13:15", "14:15 – 15:45", "16:00 – 17:30", "17:45 – 19:15", "19:30 – 21:00", "21:15 – 22:45"]
    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    Picker("Type", selection: $type) {
                        ForEach(["Quiz", "Guest lecture", "Presentation", "Placement", "Workshop", "Meeting", "Other"], id: \.self) { Text($0) }
                    }
                    TextField("Event title", text: $title)
                    Picker("Subject (optional)", selection: $subject) {
                        Text("None").tag("None")
                        ForEach(Array(Set(subjects)).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("When") {
                    DatePicker("Date", selection: $chosenDate, displayedComponents: .date)
                    Picker("Time", selection: $regular) {
                        Text("Regular slot").tag(true)
                        Text("Custom time").tag(false)
                    }.pickerStyle(.segmented)
                    if regular {
                        Picker("Class slot", selection: $slot) {
                            ForEach(slots, id: \.self) { Text($0) }
                        }
                    } else {
                        DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                        DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
                    }
                }
                Section("Notes") { TextField("Optional details", text: $notes, axis: .vertical) }
            }
            .formStyle(.grouped)
            .navigationTitle("New event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!regular && end <= start))
                }
            }
        }
        .frame(minWidth: 350, idealWidth: 520, minHeight: 450)
        .onAppear { chosenDate = date }
    }
    private func save() {
        let dateFormatter = DateFormatter(); dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter(); timeFormatter.dateFormat = "HH:mm"
        let components = slot.components(separatedBy: " – ")
        let startText = regular ? (components.first ?? "08:15") : timeFormatter.string(from: start)
        let endText = regular ? (components.last ?? "09:45") : timeFormatter.string(from: end)
        onSave(SATHICustomEvent(date: dateFormatter.string(from: chosenDate), start: startText,
                                end: endText, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                type: type, subject: subject, notes: notes))
        dismiss()
    }
}
