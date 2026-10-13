import SwiftUI
import UIKit
import FirebaseCore
import FirebaseMessaging
import AppTrackingTransparency
import UserNotifications
import AppsFlyerLib

@main
struct BuildLayerApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
 
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {

    private var base: [AnyHashable: Any] = [:]
    private var trim: [AnyHashable: Any] = [:]
    private var cure: Task<Void, Never>?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()

        let sdk = AppsFlyerLib.shared()
        sdk.appsFlyerDevKey = Blueprint.relayKey
        sdk.appleAppID = Blueprint.appCode
        sdk.delegate = self
        sdk.deepLinkDelegate = self
        sdk.isDebug = false

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()

        if let cold = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            scout(cold)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(sited), name: UIApplication.didBecomeActiveNotification, object: nil)
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    @objc private func sited() {
        guard #available(iOS 14, *) else { return AppsFlyerLib.shared().start() }
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
        ATTrackingManager.requestTrackingAuthorization { status in
            DispatchQueue.main.async {
                AppsFlyerLib.shared().start()
                UserDefaults.standard.set(status.rawValue, forKey: Rebar.attStatus)
            }
        }
    }

    private func level() {
        cure?.cancel()
        cure = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard Task.isCancelled == false else { return }
            await MainActor.run { self?.stack() }
        }
    }

    private func stack() {
        cure?.cancel()
        cure = nil
        var frame = base
        for (key, value) in trim {
            let tag = "\(key)".starts(with: "deep") ? "\(key)" : "deep_\(key)"
            if frame[tag] == nil { frame[tag] = value }
        }
        NotificationCenter.default.post(name: .poured, object: nil, userInfo: ["conversionData": frame])
    }

    private func scout(_ payload: [AnyHashable: Any]) {
        plumb(payload)

        var spied: String?
        if let direct = payload["url"] as? String, direct.isEmpty == false {
            spied = direct
        } else if let data = payload["data"] as? [AnyHashable: Any], let url = data["url"] as? String, url.isEmpty == false {
            spied = url
        } else if let aps = payload["aps"] as? [AnyHashable: Any],
                  let data = aps["data"] as? [AnyHashable: Any],
                  let url = data["url"] as? String, url.isEmpty == false {
            spied = url
        } else if let custom = payload["custom"] as? [AnyHashable: Any], let url = custom["url"] as? String, url.isEmpty == false {
            spied = url
        }
        guard let link = spied else { return }

        UserDefaults.standard.set(link, forKey: Rebar.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NotificationCenter.default.post(name: .lit, object: nil, userInfo: ["temp_url": link])
        }
    }

    private func plumb(_ payload: [AnyHashable: Any]) {
        var raw: Any?
        if let data = payload["data"] as? [AnyHashable: Any], let value = data["message_id"] {
            raw = value
        } else if let value = payload["message_id"] {
            raw = value
        }
        guard let raw = raw else { return }
        let message = "\(raw)"
        guard message.isEmpty == false, message.count <= 128 else { return }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard message.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return }

        let af = AppsFlyerLib.shared().getAppsFlyerUID()
        guard af.isEmpty == false else { return }
        guard var comps = URLComponents(string: Blueprint.interaction) else { return }
        comps.queryItems = [URLQueryItem(name: "message_id", value: message)]
        guard let url = comps.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["af_id": af])
        URLSession.shared.dataTask(with: request).resume()
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        messaging.token { token, error in
            guard error == nil, let token = token else { return }
            UserDefaults.standard.set(token, forKey: Rebar.fcm)
            UserDefaults.standard.set(token, forKey: Rebar.push)
            UserDefaults(suiteName: Blueprint.suite)?.set(token, forKey: Rebar.sharedFcm)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        scout(notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        scout(response.notification.request.content.userInfo)
        completionHandler()
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        scout(userInfo)
        completionHandler(.newData)
    }
}

extension AppDelegate: AppsFlyerLibDelegate, DeepLinkDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        base = conversionInfo
        level()
        if trim.isEmpty == false { stack() }
    }

    func onConversionDataFail(_ error: Error) {
    }

    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard case .found = result.status, let deepLink = result.deepLink else { return }
        guard UserDefaults.standard.bool(forKey: Rebar.primed) == false else { return }
        trim = deepLink.clickEvent
        NotificationCenter.default.post(name: .wired, object: nil, userInfo: ["deeplinksData": deepLink.clickEvent])
        cure?.cancel()
        cure = nil
        if base.isEmpty == false { stack() }
    }
}
