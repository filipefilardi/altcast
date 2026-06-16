import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    UNUserNotificationCenter.current().delegate = MacNotificationBridge.shared
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

class MacNotificationBridge: NSObject, UNUserNotificationCenterDelegate {
  static let shared = MacNotificationBridge()

  private var channel: FlutterMethodChannel?

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "altcast/notifications",
      binaryMessenger: binaryMessenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "requestPermission":
        self?.requestPermission(result: result)
      case "showNotification":
        self?.showNotification(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestPermission(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound]
    ) { granted, _ in
      DispatchQueue.main.async {
        result(granted)
      }
    }
  }

  private func showNotification(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let title = args["title"] as? String,
          let body = args["body"] as? String else {
      result(FlutterError(
        code: "invalid_arguments",
        message: "Notification title and body are required.",
        details: nil
      ))
      return
    }

    let id = args["id"] as? Int ?? Int(Date().timeIntervalSince1970)
    let payload = args["payload"] as? String ?? ""
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.userInfo = ["payload": payload]

    let request = UNNotificationRequest(
      identifier: "altcast-download-\(id)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(
            code: "notification_error",
            message: error.localizedDescription,
            details: nil
          ))
        } else {
          result(nil)
        }
      }
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(macOS 11.0, *) {
      completionHandler([.banner, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let payload = response.notification.request.content.userInfo["payload"] as? String
    channel?.invokeMethod("notificationTapped", arguments: payload)
    completionHandler()
  }
}
