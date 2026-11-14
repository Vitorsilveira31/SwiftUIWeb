import Testing
@testable import SwiftUIWebUserNotifications

@Suite
@MainActor
final class UserNotificationsTests {
  private final class Provider: UserNotificationProvider {
    var status: NotificationAuthorizationStatus = .notDetermined
    var grant = true
    var presented: [NotificationRequest] = []
    var removedDelivered: [[String]] = []
    var removedPending: [[String]] = []
    var delivered: [NotificationRequest] = []
    var pending: [NotificationRequest] = []
    var responseHandler: ((NotificationResponse) -> Void)?
    var retiredResponseHandlers: [(NotificationResponse) -> Void] = []

    func authorizationStatus() async -> NotificationAuthorizationStatus { status }

    func requestAuthorization(options: NotificationAuthorizationOptions) async throws -> Bool {
      _expectTrue(options.contains(.alert))
      if grant {
        status = .authorized
        return true
      }
      status = .denied
      return false
    }

    func present(_ request: NotificationRequest) async throws {
      guard status == .authorized else { throw NotificationPermissionError.permissionDenied }
      presented.append(request)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
      removedDelivered.append(identifiers)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
      removedPending.append(identifiers)
    }

    func deliveredRequests() async -> [NotificationRequest] { delivered }
    func pendingRequests() async -> [NotificationRequest] { pending }

    func setResponseHandler(_ handler: ((NotificationResponse) -> Void)?) {
      if let responseHandler { retiredResponseHandlers.append(responseHandler) }
      responseHandler = handler
    }

    func emit(_ response: NotificationResponse) { responseHandler?(response) }
    func emitRetired(_ response: NotificationResponse) {
      retiredResponseHandlers.forEach { $0(response) }
    }
  }

  private final class MinimalProvider: UserNotificationProvider {
    func authorizationStatus() async -> NotificationAuthorizationStatus { .provisional }
    func requestAuthorization(options: NotificationAuthorizationOptions) async throws -> Bool {
      !options.isEmpty
    }
    func present(_ request: NotificationRequest) async throws { _ = request }
  }

  private struct PushRuntime: WebPushRuntime {
    var supported = true
    var isSupported: Bool { supported }

    func subscribe(configuration: WebPushConfiguration) async throws -> WebPushSubscription {
      WebPushSubscription(endpoint: "https://push.invalid/subscription")
    }

    func unsubscribe(_ subscription: WebPushSubscription) async throws {}
  }

  private final class Backend: WebPushBackend {
    var registered: [WebPushSubscription] = []
    var unregistered: [WebPushSubscription] = []
    var failRegistration = false
    var failUnregistration = false

    func register(_ subscription: WebPushSubscription) async throws {
      guard !failRegistration else { throw PushFailure.register }
      registered.append(subscription)
    }

    func unregister(_ subscription: WebPushSubscription) async throws {
      guard !failUnregistration else { throw PushFailure.unregister }
      unregistered.append(subscription)
    }
  }

  private enum PushFailure: Error, CustomStringConvertible {
    case subscribe
    case unsubscribe
    case register
    case unregister

    var description: String {
      switch self {
      case .subscribe: "browser subscribe failed"
      case .unsubscribe: "browser unsubscribe failed"
      case .register: "backend register failed"
      case .unregister: "backend unregister failed"
      }
    }
  }

  private final class ControlledPushRuntime: WebPushRuntime {
    var supported = true
    var subscribeFailure: WebPushError?
    var genericSubscribeFailure: PushFailure?
    var typedUnsubscribeFailure: WebPushError?
    var unsubscribeFailure: PushFailure?
    var subscription = WebPushSubscription(
      endpoint: "https://push.invalid/subscription",
      expirationTime: 123,
      keys: ["p256dh": "public", "auth": "secret"]
    )
    var subscribedConfigurations: [WebPushConfiguration] = []
    var unsubscribeAttempts: [WebPushSubscription] = []
    var unsubscribed: [WebPushSubscription] = []

    var isSupported: Bool { supported }

    func subscribe(configuration: WebPushConfiguration) async throws -> WebPushSubscription {
      subscribedConfigurations.append(configuration)
      if let subscribeFailure { throw subscribeFailure }
      if let genericSubscribeFailure { throw genericSubscribeFailure }
      return subscription
    }

    func unsubscribe(_ subscription: WebPushSubscription) async throws {
      unsubscribeAttempts.append(subscription)
      if let typedUnsubscribeFailure { throw typedUnsubscribeFailure }
      if let unsubscribeFailure { throw unsubscribeFailure }
      unsubscribed.append(subscription)
    }
  }

  @Test
  func testPermissionStateTransitionsAreObservable() async throws {
    let provider = Provider()
    let center = UserNotificationCenter(provider: provider)

    let initialStatus = await center.authorizationStatus()
    _expectEqual(initialStatus, .notDetermined)
    let granted = try await center.requestAuthorization(options: [.alert, .sound])
    _expectTrue(granted)
    let authorizedStatus = await center.authorizationStatus()
    _expectEqual(authorizedStatus, .authorized)

    provider.grant = false
    provider.status = .notDetermined
    let denied = try await center.requestAuthorization()
    _expectFalse(denied)
    let deniedStatus = await center.authorizationStatus()
    _expectEqual(deniedStatus, .denied)
  }

  @Test
  func testDeniedPermissionCanBeRepresentedAsATypedError() async {
    let provider = Provider()
    provider.grant = false
    let center = UserNotificationCenter(provider: provider)
    provider.status = .denied

    do {
      try await center.add(NotificationRequest(
        identifier: "denied",
        content: NotificationContent(title: "Blocked")
      ))
      _fail("Expected the provider to reject the request")
    } catch let error as NotificationPermissionError {
      _expectEqual(error, .permissionDenied)
    } catch {
      _fail("Unexpected error: \(error)")
    }
  }

  @Test
  func testRequestsAndResponsesRemainSwiftValues() async throws {
    let provider = Provider()
    provider.status = .authorized
    let center = UserNotificationCenter(provider: provider)
    let request = NotificationRequest(
      identifier: "welcome",
      content: NotificationContent(title: "Welcome", body: "Hello", userInfo: ["kind": "welcome"])
    )
    try await center.add(request)
    _expectEqual(provider.presented, [request])

    var responses: [NotificationResponse] = []
    let token = center.observeResponses { responses.append($0) }
    provider.emit(NotificationResponse(requestIdentifier: "welcome", content: request.content))
    token.cancel()
    provider.emit(NotificationResponse(requestIdentifier: "ignored", content: request.content))
    _expectEqual(responses.count, 1)
    _expectEqual(responses.first?.requestIdentifier, "welcome")
  }

  @Test
  func testWebPushRequiresServiceWorkerAndBackend() async throws {
    let runtime = PushRuntime()
    let noWorker = WebPushClient(configuration: WebPushConfiguration(serviceWorkerURL: ""), runtime: runtime)
    do {
      _ = try await noWorker.subscribe()
      _fail("Expected a service-worker requirement")
    } catch let error as WebPushError {
      _expectEqual(error, .serviceWorkerRequired)
    }

    let noBackend = WebPushClient(
      configuration: WebPushConfiguration(serviceWorkerURL: "/worker.js"),
      runtime: runtime
    )
    do {
      _ = try await noBackend.subscribe()
      _fail("Expected a backend requirement")
    } catch let error as WebPushError {
      _expectEqual(error, .backendRequired)
    }
  }

  @Test
  func testWebPushRegistersAndUnregistersThroughExplicitBackend() async throws {
    let backend = Backend()
    let client = WebPushClient(
      configuration: WebPushConfiguration(serviceWorkerURL: "/worker.js"),
      backend: backend,
      runtime: PushRuntime()
    )
    let subscription = try await client.subscribe()
    _expectEqual(backend.registered, [subscription])
    try await client.unsubscribe()
    _expectEqual(backend.unregistered, [subscription])
  }

  @Test
  func testDefaultProviderMakesUnsupportedHostsExplicit() async {
    let center = UserNotificationCenter()
    let status = await center.authorizationStatus()
    _expectEqual(status, .notDetermined)
    do {
      _ = try await center.requestAuthorization()
      _fail("Native test hosts do not provide the browser Notifications API")
    } catch let error as NotificationPermissionError {
      _expectEqual(error, .notSupported)
    } catch {
      _fail("Unexpected error: \(error)")
    }

    do {
      try await center.add(NotificationRequest(
        identifier: "unsupported-host",
        content: NotificationContent(title: "Should not present")
      ))
      _fail("The unavailable provider must reject presentation too")
    } catch let error as NotificationPermissionError {
      _expectEqual(error, .notSupported)
    } catch {
      _fail("Unexpected error: \(error)")
    }
  }

  @Test
  func testAuthorizationStatusesOptionsAliasesAndTypedErrorDescriptions() {
    _expectFalse(NotificationAuthorizationStatus.notDetermined.isAuthorized)
    _expectFalse(NotificationAuthorizationStatus.denied.isAuthorized)
    _expectTrue(NotificationAuthorizationStatus.authorized.isAuthorized)
    _expectTrue(NotificationAuthorizationStatus.provisional.isAuthorized)
    _expectTrue(NotificationAuthorizationStatus.ephemeral.isAuthorized)
    _expectEqual(UNAuthorizationStatus.authorized, .authorized)
    _expectEqual(UNAuthorizationOptions.alert, .alert)

    let options = NotificationAuthorizationOptions.all
    let everyOption: [NotificationAuthorizationOptions] = [
      .alert, .badge, .sound, .provisional, .criticalAlert, .carPlay,
      .providesAppNotificationSettings, .announcement, .timeSensitive
    ]
    for option in everyOption {
      _expectTrue(options.contains(option))
    }

    _expectEqual(NotificationPermissionError.notSupported.description, "Browser notifications are not supported by this host")
    _expectEqual(NotificationPermissionError.permissionDenied.description, "Notification permission was denied")
    _expectEqual(NotificationPermissionError.restricted.description, "Notification permission is restricted by the host")
    _expectEqual(NotificationPermissionError.invalidRequest("bad request").description, "bad request")
    _expectEqual(NotificationPermissionError.invalidContent("bad content").description, "bad content")
    _expectEqual(NotificationPermissionError.requestFailed("request failed").description, "request failed")

    _expectEqual(WebPushError.notSupported.description, "Web Push is not supported by this host")
    _expectEqual(WebPushError.serviceWorkerRequired.description, "Web Push requires a service worker URL")
    _expectEqual(WebPushError.backendRequired.description, "Web Push requires a backend to register subscriptions")
    _expectEqual(WebPushError.notSubscribed.description, "There is no active Web Push subscription")
    _expectEqual(WebPushError.permissionDenied.description, "Notification permission is required for Web Push")
    _expectEqual(WebPushError.subscriptionFailed("subscription failed").description, "subscription failed")
    _expectEqual(WebPushError.backendFailed("backend failed").description, "backend failed")
  }

  @Test
  func testCenterRejectsInvalidRequestsBeforeCallingProviderAndAcceptsEitherTextField() async throws {
    let provider = Provider()
    provider.status = .authorized
    let center = UserNotificationCenter(provider: provider)

    do {
      try await center.add(NotificationRequest(identifier: "", content: NotificationContent(title: "Title")))
      _fail("An identifier is required")
    } catch let error as NotificationPermissionError {
      _expectEqual(error, .invalidRequest("A notification request needs an identifier"))
    }

    do {
      try await center.add(NotificationRequest(identifier: "empty", content: NotificationContent(title: "", body: "")))
      _fail("A title or body is required")
    } catch let error as NotificationPermissionError {
      _expectEqual(error, .invalidContent("A notification needs a title or body"))
    }
    _expectTrue(provider.presented.isEmpty)

    let bodyOnly = NotificationRequest(identifier: "body", content: NotificationContent(title: "", body: "Details"))
    let titleOnly = NotificationRequest(identifier: "title", content: NotificationContent(title: "Headline"))
    try await center.add(bodyOnly)
    try await center.add(titleOnly)
    _expectEqual(provider.presented, [bodyOnly, titleOnly])
  }

  @Test
  func testCenterForwardsRemovalQueriesAndAllRemovalSentinels() async {
    let provider = Provider()
    let delivered = NotificationRequest(identifier: "delivered", content: NotificationContent(title: "Done"))
    let pending = NotificationRequest(identifier: "pending", content: NotificationContent(title: "Later"))
    provider.delivered = [delivered]
    provider.pending = [pending]
    let center = UserNotificationCenter(provider: provider)

    center.removeDeliveredNotifications(withIdentifiers: ["a", "b"])
    center.removeAllDeliveredNotifications()
    center.removePendingNotificationRequests(withIdentifiers: ["c"])
    center.removeAllPendingNotificationRequests()

    _expectEqual(provider.removedDelivered, [["a", "b"], []])
    _expectEqual(provider.removedPending, [["c"], []])
    let deliveredRequests = await center.deliveredRequests()
    let pendingRequests = await center.pendingRequests()
    _expectEqual(deliveredRequests, [delivered])
    _expectEqual(pendingRequests, [pending])
  }

  @Test
  func testDefaultProviderExtensionMethodsAreSafeNoOps() async throws {
    let center = UserNotificationCenter(provider: MinimalProvider())
    let status = await center.authorizationStatus()
    let isAuthorized = try await center.requestAuthorization(options: [.badge])
    _expectEqual(status, .provisional)
    _expectTrue(isAuthorized)
    center.removeDeliveredNotifications(withIdentifiers: ["ignored"])
    center.removeAllDeliveredNotifications()
    center.removePendingNotificationRequests(withIdentifiers: ["ignored"])
    center.removeAllPendingNotificationRequests()
    let delivered = await center.deliveredRequests()
    let pending = await center.pendingRequests()
    _expectTrue(delivered.isEmpty)
    _expectTrue(pending.isEmpty)
    let token = center.observeResponses { _ in }
    token.cancel()
  }

  @Test
  func testResponseObserverReplacementStaleCancellationAndDeinitCleanup() {
    let provider = Provider()
    let center = UserNotificationCenter(provider: provider)
    let content = NotificationContent(title: "Tapped")
    var firstCount = 0
    var secondCount = 0
    let first = center.observeResponses { _ in firstCount += 1 }
    let second = center.observeResponses { _ in secondCount += 1 }
    let response = NotificationResponse(requestIdentifier: "n", content: content)

    provider.emitRetired(response)
    _expectEqual(firstCount, 0, "a replaced provider callback must be ignored")
    _expectEqual(secondCount, 0)
    provider.emit(response)
    first.cancel()
    provider.emit(response)
    _expectEqual(firstCount, 0)
    _expectEqual(secondCount, 2)

    second.cancel()
    second.cancel()
    provider.emit(response)
    _expectEqual(secondCount, 2)
    _expectNil(provider.responseHandler)

    var thirdCount = 0
    do {
      _ = center.observeResponses { _ in thirdCount += 1 }
    }
    provider.emit(response)
    _expectEqual(thirdCount, 0)
    _expectNil(provider.responseHandler)
  }

  @Test
  func testResponseValuesUseContentUserInfoAndImmediateRequestDefaults() {
    let content = NotificationContent(title: "Open", userInfo: ["route": "home"])
    let request = NotificationRequest(identifier: "open", content: content, trigger: nil)
    _expectEqual(request.trigger, .immediate)

    let inherited = NotificationResponse(request: request)
    _expectEqual(inherited.requestIdentifier, "open")
    _expectEqual(inherited.actionIdentifier, NotificationResponse.defaultActionIdentifier)
    _expectEqual(inherited.userInfo, ["route": "home"])
    _expectEqual(inherited.request.identifier, "open")
    _expectEqual(inherited.request.trigger, .immediate)

    let overridden = NotificationResponse(
      requestIdentifier: "open",
      actionIdentifier: "reply",
      content: content,
      userInfo: ["route": "settings"]
    )
    _expectEqual(overridden.userInfo, ["route": "settings"])
    _expectEqual(overridden.actionIdentifier, "reply")
  }

  @Test
  func testResponseCallbackAndTokenDoNotRetainCenter() {
    let provider = Provider()
    let response = NotificationResponse(
      requestIdentifier: "released",
      content: NotificationContent(title: "Released")
    )
    var callbackCount = 0
    weak var weakCenter: UserNotificationCenter?
    var token: NotificationSubscription?
    var callback: ((NotificationResponse) -> Void)?

    do {
      var center: UserNotificationCenter? = UserNotificationCenter(provider: provider)
      weakCenter = center
      token = center?.observeResponses { _ in callbackCount += 1 }
      callback = provider.responseHandler
      center = nil
    }

    _expectNil(weakCenter, "the provider callback and cancellation token must not retain the center")
    callback?(response)
    _expectEqual(callbackCount, 0)
    token?.cancel()
    _expectEqual(callbackCount, 0)
  }

  @Test
  func testWebPushSupportReflectsRuntimeAndServiceWorkerConfiguration() async {
    let runtime = ControlledPushRuntime()
    let validConfiguration = WebPushConfiguration(serviceWorkerURL: "/worker.js")
    let client = WebPushClient(configuration: validConfiguration, backend: Backend(), runtime: runtime)
    _expectTrue(client.isSupported)

    runtime.supported = false
    _expectFalse(client.isSupported)
    do {
      _ = try await client.subscribe()
      _fail("An unsupported runtime must not subscribe")
    } catch let error as WebPushError {
      _expectEqual(error, .notSupported)
    } catch {
      _fail("Unexpected error: \(error)")
    }
    _expectTrue(runtime.subscribedConfigurations.isEmpty)

    let noWorker = WebPushClient(
      configuration: WebPushConfiguration(serviceWorkerURL: ""),
      backend: Backend(),
      runtime: runtime
    )
    _expectFalse(noWorker.isSupported)
  }

  @Test
  func testDefaultWebPushRuntimeReportsUnsupportedHostBeforeSubscription() async {
    let client = WebPushClient(
      configuration: WebPushConfiguration(serviceWorkerURL: "/worker.js"),
      backend: Backend()
    )

    _expectFalse(client.isSupported)
    _expectNil(client.subscription)
    do {
      _ = try await client.subscribe()
      _fail("The default runtime must not claim browser push support")
    } catch let error as WebPushError {
      _expectEqual(error, .notSupported)
    } catch {
      _fail("Unexpected error: \(error)")
    }
    _expectNil(client.subscription)
  }

  @Test
  func testWebPushPreservesRuntimeErrorsAndWrapsUnexpectedSubscribeFailures() async {
    let backend = Backend()
    let runtime = ControlledPushRuntime()
    let configuration = WebPushConfiguration(serviceWorkerURL: "/worker.js", applicationServerKey: "vapid")
    let client = WebPushClient(configuration: configuration, backend: backend, runtime: runtime)

    runtime.subscribeFailure = .permissionDenied
    do {
      _ = try await client.subscribe()
      _fail("The runtime permission error should be preserved")
    } catch let error as WebPushError {
      _expectEqual(error, .permissionDenied)
    } catch {
      _fail("Unexpected error: \(error)")
    }

    runtime.subscribeFailure = .subscriptionFailed("browser denied request")
    do {
      _ = try await client.subscribe()
      _fail("Typed runtime errors should pass through")
    } catch let error as WebPushError {
      _expectEqual(error, .subscriptionFailed("browser denied request"))
    } catch {
      _fail("Unexpected error: \(error)")
    }

    runtime.subscribeFailure = nil
    runtime.genericSubscribeFailure = .subscribe
    do {
      _ = try await client.subscribe()
      _fail("Untyped runtime errors should be wrapped")
    } catch let error as WebPushError {
      _expectEqual(error, .subscriptionFailed("browser subscribe failed"))
    } catch {
      _fail("Unexpected error: \(error)")
    }
    _expectTrue(client.subscription == nil)
    _expectTrue(backend.registered.isEmpty)
  }

  @Test
  func testWebPushRegistrationFailureBestEffortCleansUnregisteredSubscription() async {
    let backend = Backend()
    backend.failRegistration = true
    let runtime = ControlledPushRuntime()
    runtime.unsubscribeFailure = .unsubscribe
    let client = WebPushClient(
      configuration: WebPushConfiguration(serviceWorkerURL: "/worker.js"),
      backend: backend,
      runtime: runtime
    )

    do {
      _ = try await client.subscribe()
      _fail("Registration failure must fail subscription")
    } catch let error as WebPushError {
      _expectEqual(error, .backendFailed("backend register failed"))
    } catch {
      _fail("Unexpected error: \(error)")
    }

    _expectEqual(runtime.unsubscribeAttempts, [runtime.subscription])
    _expectTrue(runtime.unsubscribed.isEmpty)
    _expectTrue(client.subscription == nil)
  }

  @Test
  func testWebPushUnsubscribeFailureRetainsActiveSubscriptionUntilCleanupSucceeds() async throws {
    let backend = Backend()
    let runtime = ControlledPushRuntime()
    let client = WebPushClient(
      configuration: WebPushConfiguration(serviceWorkerURL: "/worker.js"),
      backend: backend,
      runtime: runtime
    )
    let subscription = try await client.subscribe()
    _expectEqual(client.subscription, subscription)

    runtime.typedUnsubscribeFailure = .permissionDenied
    do {
      try await client.unsubscribe()
      _fail("Typed runtime errors should be preserved during unsubscribe")
    } catch let error as WebPushError {
      _expectEqual(error, .permissionDenied)
    } catch {
      _fail("Unexpected error: \(error)")
    }
    _expectEqual(client.subscription, subscription)
    _expectEqual(backend.unregistered, [subscription])
    _expectEqual(runtime.unsubscribeAttempts, [subscription])

    runtime.typedUnsubscribeFailure = nil

    backend.failUnregistration = true
    do {
      try await client.unsubscribe()
      _fail("Backend removal failure must be reported")
    } catch let error as WebPushError {
      _expectEqual(error, .backendFailed("backend unregister failed"))
    } catch {
      _fail("Unexpected error: \(error)")
    }
    _expectEqual(client.subscription, subscription)
    _expectEqual(backend.unregistered, [subscription])
    _expectEqual(runtime.unsubscribeAttempts, [subscription])

    backend.failUnregistration = false
    runtime.unsubscribeFailure = .unsubscribe
    do {
      try await client.unsubscribe()
      _fail("Browser removal failure must be reported")
    } catch let error as WebPushError {
      _expectEqual(error, .backendFailed("browser unsubscribe failed"))
    } catch {
      _fail("Unexpected error: \(error)")
    }
    _expectEqual(client.subscription, subscription)
    _expectEqual(backend.unregistered, [subscription, subscription])
    _expectEqual(runtime.unsubscribeAttempts, [subscription, subscription])

    runtime.unsubscribeFailure = nil
    try await client.unsubscribe()
    _expectNil(client.subscription)
    _expectEqual(runtime.unsubscribed, [subscription])
    _expectEqual(backend.unregistered, [subscription, subscription, subscription])
    _expectEqual(runtime.unsubscribeAttempts, [subscription, subscription, subscription])

    do {
      try await client.unsubscribe()
      _fail("A second unsubscribe must report no subscription")
    } catch let error as WebPushError {
      _expectEqual(error, .notSubscribed)
    }
  }
}
