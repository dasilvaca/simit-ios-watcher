import SwiftUI
import UserNotifications

@main
struct SappaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(.sAccentGreen)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.appBecameActive() }
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Must happen before launch finishes.
        BackgroundScheduler.register(service: .shared)
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let fineId = response.notification.request.content.userInfo["fineId"] as? Int64 else { return }
        await MainActor.run { AppModel.shared.openFine(fineId) }
    }
}
