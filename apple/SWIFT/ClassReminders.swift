import Foundation
import UserNotifications
import WidgetKit
#if os(iOS)
import UIKit
import ActivityKit
#endif

extension Notification.Name { static let sathiClassAction = Notification.Name("SATHIClassAction") }

@MainActor
final class ClassReminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ClassReminders()
    private var previousSignature = ""
    private var currentAccountID: String?
    private var lastWidgetData: Data?
    private(set) var status = ""
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        let fingerprint = UNNotificationAction(identifier: "FINGERPRINT_DONE", title: "Fingerprint done", options: [.foreground])
        let review = UNNotificationAction(identifier: "REVIEW", title: "Review attendance", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([UNNotificationCategory(identifier: "SATHI_CLASS", actions: [fingerprint, review], intentIdentifiers: [], options: [])])
    }

    func schedule(windows: [ClassWindow], preferences: StudyPreferences, accountID: String, proofs: [String: ClassProof]) async {
        guard !Task.isCancelled else { return }
        currentAccountID = accountID
        var signatureHash = Hasher()
        signatureHash.combine(accountID); signatureHash.combine(Int(Date().timeIntervalSince1970 / 1800))
        signatureHash.combine(preferences); signatureHash.combine(windows)
        for id in proofs.keys.sorted() { signatureHash.combine(id); signatureHash.combine(proofs[id]) }
        let signature = String(signatureHash.finalize())
        guard signature != previousSignature else { return }
        previousSignature = signature
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard preferences.reminders else { return }
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else { status = "Notifications are disabled in system settings."; return }
            guard !Task.isCancelled, currentAccountID == accountID else { return }
            var reminders: [(Date, String, String, String)] = []
            for window in windows where window.end > Date() {
                if proofs[window.id]?.fingerprint != true {
                    reminders.append((window.start.addingTimeInterval(-Double(preferences.fingerprintLeadMinutes * 60)), window.id, "Fingerprint before " + window.subject, "Aim to finish by " + window.fingerprintTarget(preferences: preferences).formatted(date: .omitted, time: .shortened)))
                    reminders.append((window.start.addingTimeInterval(Double(preferences.reminderGraceMinutes * 60)), window.id, "Fingerprint check", "Class has started. If you missed the fingerprint, do not sign the attendance sheet; review your record."))
                }
                let sheetTime = window.start.addingTimeInterval(Double(preferences.sheetReminderMinutes * 60))
                if sheetTime < window.end && proofs[window.id]?.signedSheet != true {
                    reminders.append((sheetTime, window.id, "Where is the attendance sheet?", window.subject + " · Review fingerprint and sheet status."))
                }
                reminders.append((window.end.addingTimeInterval(15 * 60), window.id, "Review " + window.subject, "Did you attend, record your fingerprint and sign? You can record missed proofs or OD now."))
            }
            for (index, item) in reminders.filter({ $0.0 > Date() }).sorted(by: { $0.0 < $1.0 }).prefix(60).enumerated() {
                guard !Task.isCancelled, currentAccountID == accountID else { return }
                let content = UNMutableNotificationContent()
                content.title = item.2; content.body = item.3; content.categoryIdentifier = "SATHI_CLASS"
                content.userInfo = ["classID": item.1, "accountID": accountID]
                if preferences.sounds { content.sound = preferences.notificationSound == "chime" ? UNNotificationSound(named: UNNotificationSoundName("sathi-chime.wav")) : .default }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.0.timeIntervalSinceNow), repeats: false)
                let identifier = "SATHI-" + accountID + "-" + String(index)
                try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
                guard !Task.isCancelled, currentAccountID == accountID else {
                    center.removePendingNotificationRequests(withIdentifiers: [identifier]); return
                }
            }
            status = "Class reminders scheduled"
        } catch { status = error.localizedDescription }
    }

    func publish(windows: [ClassWindow], preferences: StudyPreferences, proofs: [String: ClassProof], accountID: String?, events: [WidgetClass] = []) async {
        guard let accountID else { await clear(); return }
        guard !Task.isCancelled else { return }
        currentAccountID = accountID
        let classes = WidgetDates.horizon(windows.map {
            WidgetClass(id: $0.id, subject: $0.subject, start: $0.start, end: $0.end, fingerprintTarget: $0.fingerprintTarget(preferences: preferences), proxyWarning: preferences.proofCrosscheck == true && AttendanceRules.hasLiveProxyWarning(proof: proofs[$0.id], window: $0, now: Date()))
        } + events, from: Date())
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(classes)
            if data != lastWidgetData {
                try SharedClassStorage.save(.init(classes: classes, updatedAt: Date()))
                lastWidgetData = data
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        catch { status = error.localizedDescription }
        #if os(iOS)
        guard preferences.liveActivities, ActivityAuthorizationInfo().areActivitiesEnabled,
              let next = classes.first(where: { $0.end > Date() && $0.eventKind == nil }), next.start.timeIntervalSinceNow < Double(preferences.fingerprintLeadMinutes * 60) else {
            for activity in Activity<SathiClassActivity>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let state = SathiClassActivity.ContentState(proxyWarning: next.proxyWarning, fingerprintDone: proofs[next.id]?.fingerprint == true)
        for activity in Activity<SathiClassActivity>.activities where activity.attributes.classID != next.id { await activity.end(nil, dismissalPolicy: .immediate) }
        guard !Task.isCancelled, currentAccountID == accountID else { return }
        if let activity = Activity<SathiClassActivity>.activities.first(where: { $0.attributes.classID == next.id }) {
            if activity.content.state != state { await activity.update(ActivityContent(state: state, staleDate: next.end)) }
        } else {
            do {
                _ = try Activity.request(attributes: SathiClassActivity(subject: next.subject, start: next.start, end: next.end, fingerprintTarget: next.fingerprintTarget, classID: next.id), content: ActivityContent(state: state, staleDate: next.end), pushType: nil)
            } catch { status = "Live Activity could not start: \(error.localizedDescription)" }
        }
        #endif
    }

    func clear() async {
        previousSignature = ""
        currentAccountID = nil
        lastWidgetData = nil
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        try? SharedClassStorage.save(nil)
        WidgetCenter.shared.reloadAllTimelines()
        UserDefaults.standard.removeObject(forKey: "SATHIPendingAction")
        #if os(iOS)
        for activity in Activity<SathiClassActivity>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        #endif
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let value: [String: String] = ["classID": info["classID"] as? String ?? "", "accountID": info["accountID"] as? String ?? "", "action": response.actionIdentifier]
        await MainActor.run {
            UserDefaults.standard.set(value, forKey: "SATHIPendingAction")
            NotificationCenter.default.post(name: .sathiClassAction, object: nil)
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}
