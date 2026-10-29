import SwiftUI
import Foundation

// SATHI v1.2: All new screens live in this file. Existing parsing and storage stay in ContentView.
struct SATHICommandCenter: View {
    let sessions: [TimetableSession]
    let otherSectionSessions: [TimetableSession]
    let subjects: [TimetableSubject]
    let events: [TimetableEvent]
    let custom: [SATHICommandEvent]
    @Binding var selectedDate: Date
    let attendance: [String: String]
    let onAttendanceChange: (String, String?) -> Void
    let onAddEvent: () -> Void
    let onDeleteCustomEvent: (String) -> Void
    let onSubjects: () -> Void
    let onEditSelection: () -> Void
    let onChangeSemester: () -> Void
    let onReplaceExcel: () -> Void
    let onExport: () -> Void
    let onExportActivity: () -> Void
    @Binding var target: Int
    @ObservedObject var study: StudyStore
    let windows: [ClassWindow]
    let endDates: [String: Date]
    let penaltyIDs: Set<String>
    let onProof: (String) -> Void
    let onAppearance: () -> Void
    let onSync: () -> Void
    let onAccount: () -> Void
    let syncing: Bool
    let syncStatus: String
    let onHistory: () -> Void
    let onNextSemester: () -> Void
    let canStartNextSemester: Bool
    let canEditSelection: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: SATHIPage = .today
    @State private var month = Date()
    @State private var search = ""
    @State private var daysToShow = 7
    @State private var showUpcoming = false
    @State private var showAttendanceReview = false

    private var accent: Color { .accentColor }
    private var isCompact: Bool { sizeClass == .compact }
    private var todayKey: String { SATHIDate.key(Date()) }
    private var sortedSessions: [TimetableSession] {
        sessions
    }

    var body: some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone { phoneBody }
        else { wideBody }
        #else
        wideBody
        #endif
    }

    #if os(iOS)
    private var phoneBody: some View {
        TabView(selection: $page) {
            ForEach([SATHIPage.today, .calendar, .notes, .dashboard, .settings]) { item in
                NavigationStack {
                    ScrollView {
                        pageContent(item).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                    .navigationTitle(item.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: onSync) { Image(systemName: "arrow.triangle.2.circlepath") }
                                .disabled(syncing).accessibilityLabel(syncing ? "Sync in progress" : "Sync now")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { if item == .notes { NotificationCenter.default.post(name: .sathiNewNotebook, object: nil) } else { onAddEvent() } } label: { Image(systemName: "plus") }.accessibilityLabel(item == .notes ? "New notebook" : "Add event")
                        }
                    }
                }.tabItem { Label(item.title, systemImage: item.symbol) }.tag(item)
            }
        }
        .background(AccentTabBar(color: accent).frame(width: 0, height: 0))
        .onChange(of: page) { _, next in if next == .notes { NotificationCenter.default.post(name: .sathiOpenNotebook, object: nil) } }
        .sheet(isPresented: $showUpcoming) {
            NavigationStack { ScrollView { glimpsePage(all: true).padding() }.navigationTitle("Upcoming classes").toolbar { Button("Done") { showUpcoming = false } } }
        }
    }
    #endif

    @ViewBuilder private func pageContent(_ item: SATHIPage) -> some View {
        switch item {
        case .today: VStack(alignment: .leading, spacing: 20) { ClassCountdownView(windows: windows, preferences: study.workspace.preferences); todayPage }
        case .calendar: calendarPage
        case .glimpses: glimpsePage(all: false)
        case .allGlimpses: glimpsePage(all: true)
        case .dashboard: dashboardPage
        case .notes: NotesHubView(store: study, subjects: sessions.map(\.subject))
        case .settings: settingsPage
        }
    }

    private var wideBody: some View {
        NavigationSplitView {
            List {
                ForEach(SATHIPage.allCases) { item in
                    Button { animate { page = item } } label: {
                        Label(item.title, systemImage: item.symbol).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(page == item ? accent.opacity(0.12) : Color.clear)
                    .accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("SATHI")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            NavigationStack {
                ScrollView {
                    pageContent(page).frame(maxWidth: 1050, alignment: .leading).frame(maxWidth: .infinity).padding(24)
                }
                .navigationTitle(page.title)
                .toolbar {
                    ToolbarItemGroup {
                        Button { selectedDate = Date(); page = .today } label: { Label("Today", systemImage: "calendar.badge.clock") }
                        Button(action: onSync) { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }.disabled(syncing)
                        Button(action: onAddEvent) { Label("Add event", systemImage: "plus") }
                    }
                }
            }
        }
    }

    private func animate(_ action: () -> Void) {
        if reduceMotion { action() } else { withAnimation(.spring(response: 0.35, dampingFraction: 0.78), action) }
    }

    private var todayPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            dateNavigation
            todayHero
            if !isMarkerOnlyDay {
            HStack {
                sectionHeading("Day schedule", detail: "Classes and campus events")
                Spacer()
                Text("\(sessionsOn(selectedDate).count) classes").font(.caption).foregroundStyle(.secondary)
            }
            let todaySessions = sessionsOn(selectedDate)
            let todayEvents = eventsOn(selectedDate)
            if todaySessions.isEmpty && todayEvents.isEmpty {
                emptyCard("No sessions on this date", symbol: "calendar.badge.checkmark")
            } else {
                ForEach(todaySessions) { session in classRow(session, planning: false) }
                ForEach(todayEvents, id: \.id) { item in eventRow(item) }
            }
            }
            Button {
                #if os(iOS)
                if UIDevice.current.userInterfaceIdiom == .phone { showUpcoming = true }
                else { animate { page = .glimpses } }
                #else
                animate { page = .glimpses }
                #endif
            } label: {
                Label("Explore upcoming days", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }.buttonStyle(SATHIPressStyle())
        }
    }

    private var isMarkerOnlyDay: Bool {
        let values = eventsOn(selectedDate)
        return sessionsOn(selectedDate).isEmpty && !values.isEmpty && values.allSatisfy { $0.time == "All day" }
    }

    private var dateNavigation: some View {
        HStack(spacing: 12) {
            Button { changeDay(-1) } label: { Image(systemName: "chevron.left").foregroundStyle(accent) }
                .accessibilityLabel("Previous day")
            Spacer()
            VStack(spacing: 3) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide))).font(.caption).foregroundStyle(.secondary)
                Text(selectedDate.formatted(.dateTime.day().month(.wide).year()))
                    .font(.system(.title2, design: .rounded, weight: .bold)).minimumScaleFactor(0.75)
            }
            Spacer()
            Button { changeDay(1) } label: { Image(systemName: "chevron.right").foregroundStyle(accent) }
                .accessibilityLabel("Next day")
        }.buttonStyle(SATHIPressStyle())
    }

    private func changeDay(_ n: Int) {
        animate { selectedDate = Calendar.current.date(byAdding: .day, value: n, to: selectedDate) ?? selectedDate; month = selectedDate }
    }

    private var todayHero: some View {
        let todays = sessionsOn(selectedDate)
        let todaysEvents = eventsOn(selectedDate)
        let text = todaysEvents.map(\.title).joined(separator: " ").lowercased()
        let exam = text.contains("exam") || text.contains("quiz") || text.contains("mid term") || text.contains("end term")
        let holiday = text.contains("holiday") || text.contains("vacation") || text.contains("break") || text.contains("diwali")
        let weekend = Calendar.current.isDateInWeekend(selectedDate)
        let next = nextInstructionalDay(after: selectedDate)
        let otherSectionHasClass = otherSectionSessions.contains { $0.date == SATHIDate.key(selectedDate) }
        let free = todays.isEmpty && todaysEvents.isEmpty
        let color = accent
        let title = exam ? "All the best!" : holiday ? "Enjoy the holiday" : weekend && free ? "Weekend mode" : free && otherSectionHasClass ? "Lucky free day" : free ? "A little breathing room" : "Make today count"
        let symbol = exam ? "pencil.and.list.clipboard" : holiday ? "party.popper.fill" : weekend && free ? "sun.max.fill" : free ? "leaf.fill" : "sparkles"
        return ZStack {
            RoundedRectangle(cornerRadius: 25).fill(color.opacity(0.11))
            VStack(spacing: 13) {
                Image(systemName: symbol).font(.system(size: 33, weight: .light)).foregroundStyle(color)
                Text(title).font(.system(.title, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
                if free {
                    if let next {
                        Text("Your next scheduled day has \(next.count) \(next.count == 1 ? "class" : "classes") on \(next.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    } else { Text("No more classes found in your imported timetable.").multilineTextAlignment(.center).foregroundStyle(.secondary) }
                } else {
                    Text(exam ? "You've got this. Check the schedule below." : "\(todays.count) scheduled \(todays.count == 1 ? "class" : "classes") today")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                if holiday || exam {
                    Text(Array(Set(todaysEvents.map(\.title))).sorted().joined(separator: " · "))
                        .font(.caption).multilineTextAlignment(.center).foregroundStyle(color)
                }
            }.padding(.horizontal, 18).padding(.vertical, isCompact ? 20 : 38).frame(maxWidth: .infinity)
        }
        .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(color.opacity(0.20)))
    }

    private var calendarPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeading("Calendar", detail: "Designed for every screen size")
            calendarCard
            sectionHeading("Selected day", detail: selectedDate.formatted(date: .complete, time: .omitted))
            if sessionsOn(selectedDate).isEmpty && eventsOn(selectedDate).isEmpty { todayHero }
            ForEach(sessionsOn(selectedDate)) { classRow($0, planning: false) }
            ForEach(eventsOn(selectedDate), id: \.id) { eventRow($0) }
        }
    }

    private var calendarCard: some View {
        let calendar = Calendar.current
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let days = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let total = ((offset + days + 6) / 7) * 7
        return VStack(spacing: 16) {
            HStack {
                Text(first.formatted(.dateTime.month(.wide).year())).font(.title3.bold())
                Spacer()
                Button { animate { month = calendar.date(byAdding: .month, value: -1, to: first) ?? first } } label: { Image(systemName: "chevron.left").foregroundStyle(accent) }
                Button { animate { month = calendar.date(byAdding: .month, value: 1, to: first) ?? first } } label: { Image(systemName: "chevron.right").foregroundStyle(accent) }
            }.buttonStyle(SATHIPressStyle())
            GeometryReader { geometry in
                let gap: CGFloat = geometry.size.width < 400 ? 3 : 8
                let width = max(24, (geometry.size.width - gap * 6) / 7)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: gap), count: 7), spacing: gap) {
                    ForEach(0..<7, id: \.self) { index in
                        let weekday = (calendar.firstWeekday - 1 + index) % 7
                        Text(calendar.veryShortWeekdaySymbols[weekday])
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).frame(height: 24)
                    }
                    ForEach(0..<total, id: \.self) { index in
                        if index < offset || index >= offset + days {
                            Color.clear.frame(height: width < 43 ? 39 : 49)
                        } else {
                            let day = index - offset + 1
                            let date = calendar.date(byAdding: .day, value: day - 1, to: first) ?? first
                            let count = sessionsOn(date).count
                            let hasEvent = !eventsOn(date).isEmpty
                            let chosen = calendar.isDate(date, inSameDayAs: selectedDate)
                            Button {
                                animate { selectedDate = date }
                            } label: {
                                VStack(spacing: 5) {
                                    Text("\(day)").font(.system(size: width < 38 ? 12 : 14, weight: chosen ? .bold : .medium))
                                    HStack(spacing: 3) {
                                        if count > 0 { Circle().fill(accent).frame(width: 5, height: 5) }
                                        if hasEvent { Circle().fill(.orange).frame(width: 5, height: 5) }
                                    }.frame(height: 5)
                                }
                                .frame(maxWidth: .infinity).frame(height: width < 43 ? 39 : 49)
                                .background(chosen ? accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(chosen ? accent.opacity(0.55) : .clear))
                            }.buttonStyle(SATHIPressStyle())
                                .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(count) classes")
                        }
                    }
                }
            }
            .frame(height: CGFloat(24 + ((total / 7) * (49 + 8))))
            HStack(spacing: 16) {
                Label("Classes", systemImage: "circle.fill").foregroundStyle(accent)
                Label("Events", systemImage: "circle.fill").foregroundStyle(accent)
            }.font(.caption)
        }.padding(16).sathiCard()
    }

    private func glimpsePage(all: Bool) -> some View {
        let now = Calendar.current.startOfDay(for: Date())
        let future = sortedSessions.filter { $0.date >= SATHIDate.key(now) && (search.isEmpty || $0.subject.localizedCaseInsensitiveContains(search)) }
        let end = Calendar.current.date(byAdding: .day, value: daysToShow, to: now) ?? now
        let visible = all ? future : future.filter { $0.date < SATHIDate.key(end) }
        let grouped = Dictionary(grouping: visible, by: \.date)
        let dates = grouped.keys.sorted()
        return VStack(alignment: .leading, spacing: 18) {
            sectionHeading(all ? "All Glimpses" : "Glimpses", detail: all ? "Every remaining scheduled class" : "Your next \(daysToShow) days, at a glance")
            Text("Plan attendance ahead. Future choices are forecasts, not recorded absences.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter subjects", text: $search).textFieldStyle(.plain)
            }.padding(13).sathiCard()
            if !all {
                Picker("Days", selection: $daysToShow) {
                    Text("7 days").tag(7); Text("14 days").tag(14); Text("30 days").tag(30)
                }.pickerStyle(.segmented)
            }
            if dates.isEmpty { emptyCard("No upcoming classes in this range", symbol: "calendar.badge.checkmark") }
            ForEach(dates, id: \.self) { key in
                if let date = SATHIDate.parse(key) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).font(.headline)
                                Text("\(grouped[key]?.count ?? 0) scheduled classes").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if Calendar.current.isDateInWeekend(date) { Label("Weekend", systemImage: "sun.max").font(.caption).foregroundStyle(accent) }
                        }
                        ForEach(grouped[key] ?? []) { classRow($0, planning: true) }
                    }.padding(14).sathiCard()
                }
            }
            if !all {
                Button { animate { page = .allGlimpses } } label: { Label("See all upcoming classes", systemImage: "arrow.right") }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func classRow(_ session: TimetableSession, planning: Bool) -> some View {
        let status = attendance[session.id]
        let future = session.date >= todayKey
        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(accent).frame(width: 4)
            VStack(alignment: .leading, spacing: 7) {
                Text(session.subject).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Label(session.time, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                if !session.teacher.isEmpty { Label(session.teacher, systemImage: "person").font(.caption).foregroundStyle(.secondary) }
                if !session.section.isEmpty { Text("Section \(session.section)").font(.caption2).foregroundStyle(.secondary) }
                if penaltyIDs.contains(session.id) { Label("No attendance credit · must attend", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red) }
                if let window = windows.first(where: { $0.id == session.id }), AttendanceRules.hasLiveProxyWarning(proof: study.workspace.proofs[session.id], window: window, now: Date()) {
                    Text("Do not sign: fingerprint was missed").font(.caption.bold()).foregroundStyle(.red)
                }
                Button("Fingerprint & sheet", systemImage: "checklist") { onProof(session.id) }.font(.caption)
            }
            Spacer(minLength: 4)
            Menu {
                Button("Fingerprint & sheet") { onProof(session.id) }
                if future {
                    Button("Planning to attend", systemImage: "checkmark.circle") { onAttendanceChange(session.id, "Planning to attend") }
                    Button("Planning to miss", systemImage: "calendar.badge.minus") { onAttendanceChange(session.id, "Planning to miss") }
                } else {
                    Button("Attended", systemImage: "checkmark.circle") { onAttendanceChange(session.id, "Attended") }
                    Button("Missed", systemImage: "xmark.circle") { onAttendanceChange(session.id, "Missed") }
                }
                Button("OD", systemImage: "person.crop.rectangle") { onAttendanceChange(session.id, "OD") }
                Button("Clear status", systemImage: "arrow.uturn.backward") { onAttendanceChange(session.id, nil) }
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: status == "Missed" || status == "Planning to miss" ? "xmark.circle.fill" : status == nil ? "ellipsis.circle" : "checkmark.circle.fill")
                    Text(status ?? (planning ? "Plan" : "Mark")).font(.system(size: 10)).multilineTextAlignment(.center)
                }
                .foregroundStyle(status == "Missed" || status == "Planning to miss" ? .red : accent)
                .frame(minWidth: 68).padding(.vertical, 8).padding(.horizontal, 6)
                .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(SATHIPressStyle())
        }
        .padding(13)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private func eventRow(_ event: SATHICommandEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.subheadline.bold())
                Text(event.time).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(14).sathiCard()
            .contextMenu {
                if event.id.hasPrefix("custom-") {
                    Button("Delete event", role: .destructive) {
                        onDeleteCustomEvent(String(event.id.dropFirst("custom-".count)))
                    }
                }
            }
    }

    private func classHasEnded(_ session: TimetableSession) -> Bool {
        endDates[session.id].map { $0 <= Date() } ?? (session.date < todayKey)
    }

    private var dashboardPage: some View {
        let total = sessions.count
        let conducted = sessions.filter(classHasEnded)
        let attended = conducted.filter { attendance[$0.id] == "Attended" || attendance[$0.id] == "OD" }.count
        let missed = conducted.filter { attendance[$0.id] == "Missed" }.count
        let unmarked = conducted.count - attended - missed
        let credits = subjects.reduce(0.0) { $0 + $1.credits }
        return VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Semester overview").font(.title2.bold())
                Spacer()
                Button(action: onHistory) { Image(systemName: "clock.arrow.circlepath") }.accessibilityLabel("Semester history")
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("Recorded attendance", systemImage: "checkmark.seal").font(.subheadline).foregroundStyle(accent)
                if attended + missed > 0 {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(Double(attended) / Double(attended + missed) * 100))%").font(.system(size: 42, weight: .semibold, design: .rounded))
                        Spacer(); Text("Target \(target)%").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Start your attendance record").font(.title3.bold())
                }
                ProgressView(value: Double(attended + missed), total: Double(max(1, conducted.count))).tint(accent)
                Text("\(attended + missed) of \(conducted.count) elapsed classes reviewed").font(.caption).foregroundStyle(.secondary)
                if unmarked > 0 {
                    Button("Review \(unmarked) unmarked classes", systemImage: "checklist") { showAttendanceReview = true }.buttonStyle(.bordered)
                }
            }.padding(18).sathiCard()
            HStack(spacing: 0) {
                compactStat("Scheduled", "\(total)", "calendar")
                Divider().frame(height: 36)
                compactStat("Credits", String(format: "%g", credits), "graduationcap")
                Divider().frame(height: 36)
                compactStat("Missed", "\(missed)", "calendar.badge.minus")
            }.padding(.vertical, 14).sathiCard()
            HStack {
                Text("Attendance target").font(.subheadline.weight(.medium))
                Spacer()
                Picker("Attendance target", selection: $target) { Text("75%").tag(75); Text("80%").tag(80); Text("85%").tag(85) }
                    .labelsHidden().pickerStyle(.menu)
            }.padding(.horizontal, 4)
            Text("Your subjects").font(.headline)
            LazyVStack(spacing: 12) { ForEach(subjects, id: \.key) { subject in subjectCard(subject) } }
            Text("Elapsed schedule is separate from confirmed attendance. Unmarked classes do not count as present.").font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showAttendanceReview) {
            NavigationStack {
                ScrollView { LazyVStack(spacing: 12) { ForEach(conducted.filter { attendance[$0.id] == nil }) { classRow($0, planning: false) } }.padding() }
                    .navigationTitle("Review attendance")
                    .toolbar { Button("Done") { showAttendanceReview = false } }
            }
        }
    }

    private func compactStat(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(accent)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func subjectCard(_ subject: TimetableSubject) -> some View {
        let relevant = sessions.filter { $0.subject + "|" + $0.section == subject.key }
        let elapsed = relevant.filter(classHasEnded)
        let attended = elapsed.filter { attendance[$0.id] == "Attended" || attendance[$0.id] == "OD" }.count
        let missed = elapsed.filter { attendance[$0.id] == "Missed" }.count
        let recorded = attended + missed
        let plannedMisses = relevant.filter { $0.date >= todayKey && attendance[$0.id] == "Planning to miss" }.count
        let plannedAttends = relevant.filter { $0.date >= todayKey && attendance[$0.id] == "Planning to attend" }.count
        let safeNow = max(0, Int(floor(Double(attended) / (Double(target) / 100.0) - Double(recorded) + 1e-9)))
        let maxTotalMiss = max(0, relevant.count - Int(ceil(Double(relevant.count) * Double(target) / 100.0)))
        let reservedPenalty = relevant.filter { penaltyIDs.contains($0.id) && attendance[$0.id] == "Missed" && !classHasEnded($0) }.count
        let remainingBudget = max(0, maxTotalMiss - missed - reservedPenalty)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(subject.name).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Text(recorded > 0 ? "\(Int(Double(attended) / Double(recorded) * 100))%" : "Unmarked")
                    .font(.caption.weight(.medium)).foregroundStyle(recorded > 0 ? accent : .secondary)
            }
            ProgressView(value: Double(recorded), total: Double(max(1, relevant.count))).tint(accent)
            HStack {
                Text("\(recorded) / \(relevant.count) recorded")
                Spacer()
                Text("\(String(format: "%g", subject.credits)) credits")
            }.font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Attendance details") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(attended) present / OD · \(missed) missed · \(max(0, elapsed.count - recorded)) unmarked")
                    Text("Safe misses now: \(safeNow) · Remaining end-term budget: \(remainingBudget)")
                    if plannedMisses > 0 || plannedAttends > 0 { Text("Planned: \(plannedAttends) attend · \(plannedMisses) miss") }
                    Text("Budgets are provisional until past attendance is reviewed.").foregroundStyle(.secondary)
                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }.font(.caption).tint(accent)
        }.padding(16).sathiCard()
    }

    private func metric(_ title: String, _ value: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(accent)
            Text(value).font(.system(.title, design: .rounded, weight: .bold))
            Text(title).font(.subheadline.weight(.medium))
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).sathiCard()
    }

    private func smallMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeading("Settings", detail: "Your existing semester and timetable tools")
            if syncing { ProgressView("Syncing in background…") }
            Text(syncStatus).font(.caption).foregroundStyle(.secondary)
            settingsButton("Sync now", symbol: "arrow.triangle.2.circlepath", action: onSync).disabled(syncing)
            settingsButton("Google account", symbol: "person.crop.circle", action: onAccount)
            settingsButton("Appearance & reminders", symbol: "slider.horizontal.3", action: onAppearance)
            settingsButton("Semester history", symbol: "clock.arrow.circlepath", action: onHistory)
            if canStartNextSemester { settingsButton("Import next semester", symbol: "calendar.badge.plus", action: onNextSemester) }
            settingsButton("My subjects", symbol: "books.vertical", action: onSubjects)
            if canEditSelection { settingsButton("Edit subject selection", symbol: "checklist", action: onEditSelection) }
            settingsButton("Change semester", symbol: "graduationcap", action: onChangeSemester)
            settingsButton("Replace Excel timetable", symbol: "arrow.triangle.2.circlepath", action: onReplaceExcel)
            settingsButton("Export timetable JSON", symbol: "square.and.arrow.up", action: onExport)
            settingsButton("Export activity JSON", symbol: "clock.arrow.circlepath", action: onExportActivity)
            Text("Your changes are saved on this device. Sync runs hourly when the system permits, or when you tap Sync.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func settingsButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Label(title, systemImage: symbol); Spacer(); Image(systemName: "chevron.right").foregroundStyle(accent) }
                .padding(15)
        }.buttonStyle(SATHIPressStyle()).sathiCard()
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(.title2, design: .rounded, weight: .bold))
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func emptyCard(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).padding(24).sathiCard()
    }

    private func sessionsOn(_ date: Date) -> [TimetableSession] { sortedSessions.filter { $0.date == SATHIDate.key(date) } }
    private func eventsOn(_ date: Date) -> [SATHICommandEvent] {
        let key = SATHIDate.key(date)
        return EventPresentation.consolidate(events.filter { $0.date == key }.map { SATHICommandEvent(id: "excel-\($0.source)-\($0.time)", date: $0.date, title: $0.title, time: $0.time) }
            + custom.filter { $0.date == key })
    }
    private func nextInstructionalDay(after date: Date) -> (date: Date, count: Int)? {
        let key = SATHIDate.key(date)
        guard let next = sortedSessions.first(where: { $0.date > key }), let nextDate = SATHIDate.parse(next.date) else { return nil }
        return (nextDate, sessionsOn(nextDate).count)
    }
}

private enum SATHIPage: String, CaseIterable, Identifiable {
    case today, calendar, glimpses, allGlimpses, dashboard, notes, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        case .calendar: "Calendar"
        case .glimpses: "Glimpses"
        case .allGlimpses: "All Glimpses"
        case .dashboard: "Dashboard"
        case .notes: "Notebooks"
        case .settings: "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .today: "house.fill"
        case .calendar: "calendar"
        case .glimpses: "calendar.badge.clock"
        case .allGlimpses: "list.bullet.rectangle"
        case .dashboard: "chart.bar.xaxis"
        case .notes: "book.closed"
        case .settings: "gearshape"
        }
    }
}

private enum SATHIDate {
    static let formatter: DateFormatter = {
        let value = DateFormatter(); value.locale = Locale(identifier: "en_US_POSIX"); value.timeZone = .autoupdatingCurrent; value.dateFormat = "yyyy-MM-dd"; return value
    }()
    static func key(_ date: Date) -> String { formatter.string(from: date) }
    static func parse(_ key: String) -> Date? { formatter.date(from: key) }
}

private struct SATHIPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.58), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

private struct StudyGlassCard: ViewModifier {
    @Environment(\.studyGlassOpacity) private var opacity
    @Environment(\.studyGlassStyle) private var glassStyle
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.background {
            if glassStyle == "solid" || reduceTransparency { RoundedRectangle(cornerRadius: 18).fill(.background) }
            else { RoundedRectangle(cornerRadius: 18).fill(.thinMaterial).opacity(glassStyle == "clear" ? 0.45 : opacity) }
        }
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.08)))
    }
}
private extension View {
    func sathiCard() -> some View { modifier(StudyGlassCard()) }
}
