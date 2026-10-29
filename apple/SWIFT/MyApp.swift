import SwiftUI
import GoogleSignIn

@main struct MyApp: App {
    @StateObject private var cloud: CloudSyncStore

    init() {
        let store = CloudSyncStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("IIMBGSATHI", isDirectory: true))
        _cloud = StateObject(wrappedValue: store)
        BackgroundSync.register(cloud: store)
    }

    private var accountView: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-sathi-ui-preview") { DevelopmentPreview() }
            else { ContentView(cloud: cloud) }
            #else
            ContentView(cloud: cloud)
            #endif
        }
            .id(cloud.accountID ?? "signed-out")
            .task(id: cloud.accountID) {
                if cloud.accountID == nil {
                    BackgroundSync.liveUID = nil; BackgroundSync.liveApply = nil
                    await ClassReminders.shared.clear()
                }
            }
            .onOpenURL { url in
                if GIDSignIn.sharedInstance.handle(url) { return }
                guard url.scheme == "sathi", let uid = cloud.accountID else { return }
                let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value ?? ""
                UserDefaults.standard.set(["accountID": uid, "classID": id, "action": "REVIEW"], forKey: "SATHIPendingAction")
                NotificationCenter.default.post(name: .sathiClassAction, object: nil)
            }
    }

    var body: some Scene {
        #if os(macOS)
        // One editing window prevents two independent view snapshots sharing one disk cache.
        Window("SATHI", id: "sathi") { accountView }
        #else
        WindowGroup { accountView }
        #endif
    }
}
