// A small, Swift-only UserNotifications-shaped API for browser WebAssembly.
//
// The public types in this file intentionally do not mention DOM, JavaScript interop,
// Notification, PushManager, or service-worker objects.  The browser provider at
// the bottom of the file is an implementation detail of this optional module.

public enum NotificationAuthorizationStatus: String, Hashable, Sendable {
  case notDetermined
  case denied
  case authorized
  case provisional
  case ephemeral

  public var isAuthorized: Bool {
    self == .authorized || self == .provisional || self == .ephemeral
  }
}

// Apple-platform spellings are aliases, not a second implementation. They
// make small shared models easier to port while retaining the descriptive
// SwiftUIWeb names above.
public typealias UNAuthorizationStatus = NotificationAuthorizationStatus

/// Options accepted by ``UserNotificationCenter``.  Browsers currently map
/// these to their single visible-alert permission; the extra cases make code
/// shared with Apple-platform UserNotifications easier to port without making
/// unsupported browser features look available.
public struct NotificationAuthorizationOptions: OptionSet, Hashable, Sendable {
  public let rawValue: UInt64

  public init(rawValue: UInt64) { self.rawValue = rawValue }

  public static let alert = Self(rawValue: 1 << 0)
  public static let badge = Self(rawValue: 1 << 1)
  public static let sound = Self(rawValue: 1 << 2)
  public static let provisional = Self(rawValue: 1 << 3)
  public static let criticalAlert = Self(rawValue: 1 << 4)
  public static let carPlay = Self(rawValue: 1 << 5)
  public static let providesAppNotificationSettings = Self(rawValue: 1 << 6)
  public static let announcement = Self(rawValue: 1 << 7)
  public static let timeSensitive = Self(rawValue: 1 << 8)

  public static let all: Self = [
    .alert, .badge, .sound, .provisional, .criticalAlert, .carPlay,
    .providesAppNotificationSettings, .announcement, .timeSensitive
  ]
}

public typealias UNAuthorizationOptions = NotificationAuthorizationOptions

public enum NotificationPermissionError: Error, Equatable, Sendable, CustomStringConvertible {
  case notSupported
  case permissionDenied
  case restricted
  case invalidRequest(String)
  case invalidContent(String)
  case requestFailed(String)

  public var description: String {
    switch self {
    case .notSupported:
      return "Browser notifications are not supported by this host"
    case .permissionDenied:
      return "Notification permission was denied"
    case .restricted:
      return "Notification permission is restricted by the host"
    case .invalidRequest(let message):
      return message
    case .invalidContent(let message):
      return message
    case .requestFailed(let message):
      return message
    }
  }
}

public enum NotificationSound: Hashable, Sendable {
  case `default`
  case named(String)
}

public typealias UNNotificationSound = NotificationSound

/// Values understood by both a local browser notification and a native-style
/// notification model.  Browser-only options such as a DOM object or a
/// JavaScript callback are deliberately absent.
public struct NotificationContent: Hashable, Sendable {
  public var title: String
  public var subtitle: String?
  public var body: String
  public var badge: String?
  public var iconURL: String?
  public var tag: String?
  public var sound: NotificationSound?
  public var threadIdentifier: String?
  public var categoryIdentifier: String?
  public var userInfo: [String: String]
  public var requireInteraction: Bool
  public var silent: Bool

  public init(
    title: String,
    body: String = "",
    subtitle: String? = nil,
    badge: String? = nil,
    iconURL: String? = nil,
    tag: String? = nil,
    sound: NotificationSound? = nil,
    threadIdentifier: String? = nil,
    categoryIdentifier: String? = nil,
    userInfo: [String: String] = .init(),
    requireInteraction: Bool = false,
    silent: Bool = false
  ) {
    self.title = title
    self.body = body
    self.subtitle = subtitle
    self.badge = badge
    self.iconURL = iconURL
    self.tag = tag
    self.sound = sound
    self.threadIdentifier = threadIdentifier
    self.categoryIdentifier = categoryIdentifier
    self.userInfo = userInfo
    self.requireInteraction = requireInteraction
    self.silent = silent
  }
}

public typealias UNNotificationContent = NotificationContent
public typealias UNMutableNotificationContent = NotificationContent

/// Browser notifications are immediate.  A time interval is represented so
/// shared application code can describe a local request, but the browser
/// provider rejects it rather than silently pretending to schedule work.
public enum NotificationTrigger: Hashable, Sendable {
  case immediate
  case timeInterval(seconds: Double, repeats: Bool = false)
}

public typealias UNNotificationTrigger = NotificationTrigger

public struct NotificationRequest: Hashable, Sendable {
  public var identifier: String
  public var content: NotificationContent
  public var trigger: NotificationTrigger

  public init(
    identifier: String,
    content: NotificationContent,
    trigger: NotificationTrigger? = .immediate
  ) {
    self.identifier = identifier
    self.content = content
    self.trigger = trigger ?? .immediate
  }
}

public typealias UNNotificationRequest = NotificationRequest

public struct NotificationResponse: Hashable, Sendable {
  public static let defaultActionIdentifier = "default"

  public let requestIdentifier: String
  public let actionIdentifier: String
  public let content: NotificationContent
  public let userInfo: [String: String]

  /// The neutral request that produced this response. This mirrors the
  /// commonly used `response.notification.request` access pattern without
  /// exposing a browser notification object.
  public var request: NotificationRequest {
    NotificationRequest(identifier: requestIdentifier, content: content)
  }

  public init(
    requestIdentifier: String,
    actionIdentifier: String = NotificationResponse.defaultActionIdentifier,
    content: NotificationContent,
    userInfo: [String: String]? = nil
  ) {
    self.requestIdentifier = requestIdentifier
    self.actionIdentifier = actionIdentifier
    self.content = content
    self.userInfo = userInfo ?? content.userInfo
  }

  public init(
    request: NotificationRequest,
    actionIdentifier: String = NotificationResponse.defaultActionIdentifier,
    userInfo: [String: String]? = nil
  ) {
    self.init(
      requestIdentifier: request.identifier,
      actionIdentifier: actionIdentifier,
      content: request.content,
      userInfo: userInfo
    )
  }
}

public typealias UNNotificationResponse = NotificationResponse

/// A cancellable response observer.  It is intentionally a plain Swift token;
/// applications never need to retain a JavaScript event-listener object.
public final class NotificationSubscription: @unchecked Sendable {
  private var cancellation: (() -> Void)?

  public init(_ cancellation: @escaping () -> Void) {
    self.cancellation = cancellation
  }

  public func cancel() {
    guard let cancellation else { return }
    self.cancellation = nil
    cancellation()
  }

  deinit { cancel() }
}

/// The injectable runtime boundary.  Tests and non-browser hosts can provide
/// a deterministic implementation; the default provider is selected at
/// compile time and is not visible as a JavaScript type.
public protocol UserNotificationProvider: AnyObject {
  func authorizationStatus() async -> NotificationAuthorizationStatus
  func requestAuthorization(options: NotificationAuthorizationOptions) async throws -> Bool
  func present(_ request: NotificationRequest) async throws
  func removeDeliveredNotifications(withIdentifiers identifiers: [String])
  func removePendingNotificationRequests(withIdentifiers identifiers: [String])
  func deliveredRequests() async -> [NotificationRequest]
  func pendingRequests() async -> [NotificationRequest]
  func setResponseHandler(_ handler: ((NotificationResponse) -> Void)?)
}

public extension UserNotificationProvider {
  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) { _ = identifiers }
  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) { _ = identifiers }
  func deliveredRequests() async -> [NotificationRequest] { [] }
  func pendingRequests() async -> [NotificationRequest] { [] }
  func setResponseHandler(_ handler: ((NotificationResponse) -> Void)?) { _ = handler }
}

/// The local notification center.  It owns only the neutral value model and
/// delegates browser work to a private provider.
public final class UserNotificationCenter: @unchecked Sendable {
  public static let current = UserNotificationCenter()

  private let provider: any UserNotificationProvider
  private var observerID = 0

  public init() {
    self.provider = Self.makeDefaultProvider()
  }

  public init(provider: any UserNotificationProvider) {
    self.provider = provider
  }

  public func authorizationStatus() async -> NotificationAuthorizationStatus {
    await provider.authorizationStatus()
  }

  /// Requests the browser permission and returns true only for an authorized
  /// result. A denied or unavailable request is surfaced as a typed error.
  @discardableResult
  public func requestAuthorization(
    options: NotificationAuthorizationOptions = [.alert]
  ) async throws -> Bool {
    try await provider.requestAuthorization(options: options)
  }

  public func add(_ request: NotificationRequest) async throws {
    guard !request.identifier.isEmpty else {
      throw NotificationPermissionError.invalidRequest("A notification request needs an identifier")
    }
    guard !request.content.title.isEmpty || !request.content.body.isEmpty else {
      throw NotificationPermissionError.invalidContent("A notification needs a title or body")
    }
    try await provider.present(request)
  }

  public func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
    provider.removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  public func removeAllDeliveredNotifications() {
    provider.removeDeliveredNotifications(withIdentifiers: [])
  }

  public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
    provider.removePendingNotificationRequests(withIdentifiers: identifiers)
  }

  public func removeAllPendingNotificationRequests() {
    provider.removePendingNotificationRequests(withIdentifiers: [])
  }

  public func deliveredRequests() async -> [NotificationRequest] {
    await provider.deliveredRequests()
  }

  public func pendingRequests() async -> [NotificationRequest] {
    await provider.pendingRequests()
  }

  @discardableResult
  public func observeResponses(
    _ handler: @escaping (NotificationResponse) -> Void
  ) -> NotificationSubscription {
    observerID += 1
    let id = observerID
    #if hasFeature(Embedded)
    // Embedded Swift has no weak references: the handlers keep the center, which lives as long as the page does.
    provider.setResponseHandler { [self] response in
      guard self.observerID == id else { return }
      handler(response)
    }
    return NotificationSubscription { [self] in
      guard self.observerID == id else { return }
      self.observerID += 1
      self.provider.setResponseHandler(nil)
    }
    #else
    provider.setResponseHandler { [weak self] response in
      guard let self, self.observerID == id else { return }
      handler(response)
    }
    return NotificationSubscription { [weak self] in
      guard let self, self.observerID == id else { return }
      self.observerID += 1
      self.provider.setResponseHandler(nil)
    }
    #endif
  }

  private static func makeDefaultProvider() -> any UserNotificationProvider {
    return UnavailableNotificationProvider()
  }
}

public typealias UNUserNotificationCenter = UserNotificationCenter

private final class UnavailableNotificationProvider: UserNotificationProvider {
  func authorizationStatus() async -> NotificationAuthorizationStatus { .notDetermined }

  func requestAuthorization(options: NotificationAuthorizationOptions) async throws -> Bool {
    _ = options
    throw NotificationPermissionError.notSupported
  }

  func present(_ request: NotificationRequest) async throws {
    _ = request
    throw NotificationPermissionError.notSupported
  }
}

// MARK: - Optional Web Push extension

public struct WebPushConfiguration: Hashable, Sendable {
  /// A URL served by the application. Registration is mandatory for Web Push;
  /// an empty value is rejected before any browser API is touched.
  public var serviceWorkerURL: String
  /// A base64url VAPID application-server key, when the backend uses VAPID.
  public var applicationServerKey: String?

  public init(serviceWorkerURL: String, applicationServerKey: String? = nil) {
    self.serviceWorkerURL = serviceWorkerURL
    self.applicationServerKey = applicationServerKey
  }
}

public struct WebPushSubscription: Hashable, Sendable {
  public let endpoint: String
  public let expirationTime: Double?
  /// Key material is represented as encoded strings, never as a browser
  /// ArrayBuffer or JavaScript value.
  public let keys: [String: String]

  public init(endpoint: String, expirationTime: Double? = nil, keys: [String: String] = .init()) {
    self.endpoint = endpoint
    self.expirationTime = expirationTime
    self.keys = keys
  }
}

public enum WebPushError: Error, Equatable, Sendable, CustomStringConvertible {
  case notSupported
  case serviceWorkerRequired
  case backendRequired
  case notSubscribed
  case permissionDenied
  case subscriptionFailed(String)
  case backendFailed(String)

  public var description: String {
    switch self {
    case .notSupported: return "Web Push is not supported by this host"
    case .serviceWorkerRequired: return "Web Push requires a service worker URL"
    case .backendRequired: return "Web Push requires a backend to register subscriptions"
    case .notSubscribed: return "There is no active Web Push subscription"
    case .permissionDenied: return "Notification permission is required for Web Push"
    case .subscriptionFailed(let message): return message
    case .backendFailed(let message): return message
    }
  }
}

public protocol WebPushRuntime {
  var isSupported: Bool { get }
  func subscribe(configuration: WebPushConfiguration) async throws -> WebPushSubscription
  func unsubscribe(_ subscription: WebPushSubscription) async throws
}

/// The backend is deliberately explicit. Obtaining a browser subscription is
/// not enough to deliver pushes: an application server must retain it and send
/// messages through a push service.
public protocol WebPushBackend {
  func register(_ subscription: WebPushSubscription) async throws
  func unregister(_ subscription: WebPushSubscription) async throws
}

public final class WebPushClient {
  public let configuration: WebPushConfiguration
  public let backend: (any WebPushBackend)?
  private let runtime: any WebPushRuntime
  private var activeSubscription: WebPushSubscription?

  public init(
    configuration: WebPushConfiguration,
    backend: (any WebPushBackend)? = nil,
    runtime: (any WebPushRuntime)? = nil
  ) {
    self.configuration = configuration
    self.backend = backend
    self.runtime = runtime ?? Self.makeDefaultRuntime()
  }

  public var isSupported: Bool {
    !configuration.serviceWorkerURL.isEmpty && runtime.isSupported
  }

  public var subscription: WebPushSubscription? { activeSubscription }

  public func subscribe() async throws -> WebPushSubscription {
    guard !configuration.serviceWorkerURL.isEmpty else {
      throw WebPushError.serviceWorkerRequired
    }
    guard let backend else { throw WebPushError.backendRequired }
    guard runtime.isSupported else { throw WebPushError.notSupported }

    let subscription: WebPushSubscription
    do {
      subscription = try await runtime.subscribe(configuration: configuration)
    } catch let error as WebPushError {
      throw error
    } catch {
      throw WebPushError.subscriptionFailed(_describe(error))
    }

    do {
      try await backend.register(subscription)
    } catch {
      // Best-effort cleanup avoids leaving a browser subscription that the
      // application server never learned about.
      try? await runtime.unsubscribe(subscription)
      throw WebPushError.backendFailed(_describe(error))
    }
    activeSubscription = subscription
    return subscription
  }

  public func unsubscribe() async throws {
    guard let subscription = activeSubscription else { throw WebPushError.notSubscribed }
    guard let backend else { throw WebPushError.backendRequired }
    do {
      try await backend.unregister(subscription)
      try await runtime.unsubscribe(subscription)
    } catch let error as WebPushError {
      throw error
    } catch {
      throw WebPushError.backendFailed(_describe(error))
    }
    activeSubscription = nil
  }

  private static func makeDefaultRuntime() -> any WebPushRuntime {
    return UnavailableWebPushRuntime()
  }
}

private struct UnavailableWebPushRuntime: WebPushRuntime {
  var isSupported: Bool { false }
  func subscribe(configuration: WebPushConfiguration) async throws -> WebPushSubscription {
    _ = configuration
    throw WebPushError.notSupported
  }
  func unsubscribe(_ subscription: WebPushSubscription) async throws { _ = subscription }
}

// The values are `Codable` where there is a `Codable`: Embedded Swift has none, and nothing in this module encodes or decodes them.
#if !hasFeature(Embedded)
extension NotificationAuthorizationStatus: Codable {}
extension NotificationSound: Codable {}
extension NotificationContent: Codable {}
extension NotificationTrigger: Codable {}
extension NotificationRequest: Codable {}
extension NotificationResponse: Codable {}
extension WebPushConfiguration: Codable {}
extension WebPushSubscription: Codable {}
#endif

#if hasFeature(Embedded)
// Embedded Swift cannot describe an error it only knows as `any Error`.
private func _describe(_ error: any Error) -> String { "The operation couldn’t be completed." }
#else
private func _describe(_ error: any Error) -> String { String(describing: error) }
#endif
