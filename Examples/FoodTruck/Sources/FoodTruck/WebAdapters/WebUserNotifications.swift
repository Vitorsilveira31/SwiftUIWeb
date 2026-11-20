// Web adapter, not part of Apple's sample.
//
// The iPad version of Food Truck schedules a local notification when donuts go in the oven (OrderDetailView). A browser
// build has no notification service for it, so the request is refused with a message the order screen prints.
import Foundation

final class UNMutableNotificationContent {
    var title = ""
    var body = ""
}

struct UNTimeIntervalNotificationTrigger {
    let timeInterval: TimeInterval
    let repeats: Bool
    init(timeInterval: TimeInterval, repeats: Bool) {
        self.timeInterval = timeInterval
        self.repeats = repeats
    }
}

struct UNNotificationRequest {
    let identifier: String
    let content: UNMutableNotificationContent
    let trigger: UNTimeIntervalNotificationTrigger?
    init(identifier: String, content: UNMutableNotificationContent, trigger: UNTimeIntervalNotificationTrigger?) {
        self.identifier = identifier
        self.content = content
        self.trigger = trigger
    }
}

struct UNNotificationUnavailable: LocalizedError {
    var errorDescription: String? { "Local notifications are not available in the browser" }
}

final class UNUserNotificationCenter {
    private static let shared = UNUserNotificationCenter()
    static func current() -> UNUserNotificationCenter { shared }
    func add(_ request: UNNotificationRequest, withCompletionHandler completion: ((Error?) -> Void)? = nil) {
        completion?(UNNotificationUnavailable())
    }
}
