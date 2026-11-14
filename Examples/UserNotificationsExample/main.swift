import SwiftUIWeb
import SwiftUIWebBrowser
import SwiftUIWebUserNotifications

@main
private struct UserNotificationsExample: BrowserApp {
  var body: some Scene {
    WindowGroup { NotificationDemo() }
  }
}

private struct NotificationDemo: View {
  @State private var permission = NotificationAuthorizationStatus.notDetermined
  @State private var message = "Checking notification permission…"
  @State private var permissionRequest = 0
  @State private var notificationRequest = 0

  var body: some View {
    VStack {
      Text("Browser notifications")
        .font(.title)
      Text(message)
      Button("Request permission") {
        permissionRequest += 1
      }
      .disabled(permission == .authorized)
      Button("Show local notification") {
        notificationRequest += 1
      }
      .disabled(permission != .authorized)
      Text("Web Push is a separate opt-in extension. It needs a service worker and an application backend.")
        .font(.caption)
    }
    .padding()
    .task(id: permissionRequest) {
      guard permissionRequest > 0 else { return }
      do {
        _ = try await UserNotificationCenter.current.requestAuthorization(options: [.alert])
        permission = await UserNotificationCenter.current.authorizationStatus()
        message = "Permission: \(permission.rawValue)"
      } catch {
        message = "Notifications are not available here"
      }
    }
    .task(id: notificationRequest) {
      guard notificationRequest > 0 else { return }
      do {
        try await UserNotificationCenter.current.add(NotificationRequest(
          identifier: "swiftuiweb-example",
          content: NotificationContent(
            title: "SwiftUIWeb",
            body: "This is a local browser notification.",
            userInfo: ["source": "example"]
          )
        ))
        message = "Notification shown"
      } catch {
        message = "The notification could not be shown"
      }
    }
    .task {
      permission = await UserNotificationCenter.current.authorizationStatus()
      message = "Permission: \(permission.rawValue)"
    }
  }
}
