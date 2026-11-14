@_spi(Renderer) import SwiftUIWebLocking
import SwiftUIWebTransferable  // `Date`, the type of `CLLocation.timestamp`.
// CoreLocation-shaped location services for SwiftUIWeb Web/WASM targets.
//
// The public declarations in this file intentionally contain no JavaScript interop
// or DOM types.  The browser implementation lives at the bottom of the file
// and is selected only for the JavaScript WebAssembly runtime.

public typealias CLLocationDegrees = Double
public typealias CLLocationDistance = Double
public typealias CLLocationAccuracy = Double
public typealias CLLocationDirection = Double
public typealias CLLocationSpeed = Double

public let kCLLocationAccuracyBest: CLLocationAccuracy = -1
public let kCLLocationAccuracyBestForNavigation: CLLocationAccuracy = -2
public let kCLLocationAccuracyNearestTenMeters: CLLocationAccuracy = 10
public let kCLLocationAccuracyHundredMeters: CLLocationAccuracy = 100
public let kCLLocationAccuracyKilometer: CLLocationAccuracy = 1_000
public let kCLLocationAccuracyThreeKilometers: CLLocationAccuracy = 3_000
public let kCLLocationAccuracyReduced: CLLocationAccuracy = 6_380_000
public let kCLDistanceFilterNone: CLLocationDistance = -1

/// A latitude/longitude pair that is independent of MapKit and browser types.
/// SwiftUIWebMapKit can use this value directly without depending on the
/// browser adapter or introducing a reverse dependency into CoreLocation.
public struct CLLocationCoordinate2D: Equatable, Hashable, Sendable,
  CustomStringConvertible {
  public var latitude: CLLocationDegrees
  public var longitude: CLLocationDegrees

  public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
    self.latitude = latitude
    self.longitude = longitude
  }

  public static let zero = Self(latitude: 0, longitude: 0)

  public var isValid: Bool {
    latitude.isFinite && longitude.isFinite &&
      (-90...90).contains(latitude) && (-180...180).contains(longitude)
  }

  public var description: String { "(\(latitude), \(longitude))" }

  /// Distance in meters using a WASM-safe local-earth approximation. The
  /// browser uses this for `distanceFilter`; avoiding libc math keeps the
  /// coordinate layer available to Embedded/WASI SDKs as well.
  public func distance(to other: Self) -> CLLocationDistance {
    guard isValid && other.isValid else { return .nan }
    var longitudeDelta = other.longitude - longitude
    if longitudeDelta > 180 { longitudeDelta -= 360 }
    if longitudeDelta < -180 { longitudeDelta += 360 }
    let latitudeMeters = (other.latitude - latitude) * 110_574
    let meanLatitude = (latitude + other.latitude) * 0.5 * 0.0174532925199433
    let latitudeSquared = meanLatitude * meanLatitude
    let cosineLatitude = 1 - latitudeSquared * 0.5 +
      latitudeSquared * latitudeSquared / 24 -
      latitudeSquared * latitudeSquared * latitudeSquared / 720
    let longitudeMeters = longitudeDelta * 111_320 * max(0, cosineLatitude)
    let larger = max(abs(latitudeMeters), abs(longitudeMeters))
    let smaller = min(abs(latitudeMeters), abs(longitudeMeters))
    return larger + smaller * 0.41421356237
  }
}

/// Compatibility spelling used by CoreLocation clients.
public func CLLocationCoordinate2DIsValid(_ coordinate: CLLocationCoordinate2D) -> Bool {
  coordinate.isValid
}

/// A location fix returned by the browser geolocation service.
public final class CLLocation: @unchecked Sendable, Hashable,
  CustomStringConvertible {
  public let coordinate: CLLocationCoordinate2D
  public let altitude: CLLocationDistance
  public let horizontalAccuracy: CLLocationAccuracy
  public let verticalAccuracy: CLLocationAccuracy
  public let course: CLLocationDirection
  public let speed: CLLocationSpeed
  public let timestamp: Date

  public init(
    coordinate: CLLocationCoordinate2D,
    altitude: CLLocationDistance = 0,
    horizontalAccuracy: CLLocationAccuracy = -1,
    verticalAccuracy: CLLocationAccuracy = -1,
    course: CLLocationDirection = -1,
    speed: CLLocationSpeed = -1,
    timestamp: Date = .now
  ) {
    self.coordinate = coordinate
    self.altitude = altitude
    self.horizontalAccuracy = horizontalAccuracy
    self.verticalAccuracy = verticalAccuracy
    self.course = course
    self.speed = speed
    self.timestamp = timestamp
  }

  public convenience init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
    self.init(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
  }

  public func distance(from location: CLLocation) -> CLLocationDistance {
    coordinate.distance(to: location.coordinate)
  }

  public var description: String {
    "<CLLocation \(coordinate), ±\(horizontalAccuracy)m>"
  }

  public static func == (lhs: CLLocation, rhs: CLLocation) -> Bool {
    lhs.coordinate == rhs.coordinate &&
      lhs.altitude == rhs.altitude &&
      lhs.horizontalAccuracy == rhs.horizontalAccuracy &&
      lhs.verticalAccuracy == rhs.verticalAccuracy &&
      lhs.course == rhs.course && lhs.speed == rhs.speed &&
      lhs.timestamp == rhs.timestamp
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(coordinate)
    hasher.combine(altitude)
    hasher.combine(horizontalAccuracy)
    hasher.combine(verticalAccuracy)
    hasher.combine(course)
    hasher.combine(speed)
    hasher.combine(timestamp)
  }
}

public enum CLAuthorizationStatus: Int, Sendable {
  case notDetermined = 0
  case restricted = 1
  case denied = 2
  case authorizedAlways = 3
  case authorizedWhenInUse = 4

  /// The spelling used by older Apple SDKs. Browser geolocation has only a
  /// foreground permission, so `.authorized` maps to `.authorizedWhenInUse`.
  public static var authorized: Self { .authorizedWhenInUse }

  public var isAuthorized: Bool {
    self == .authorizedAlways || self == .authorizedWhenInUse
  }
}

/// Browser geolocation does not expose a separate reduced/full permission
/// prompt, but the type keeps modern CoreLocation call sites source-compatible.
public enum CLAccuracyAuthorization: Int, Sendable {
  case fullAccuracy = 0
  case reducedAccuracy = 1
}

public enum CLError: Int, Error, Equatable, Sendable,
  CustomStringConvertible {
  case locationUnknown = 0
  case denied = 1
  case network = 2
  case headingFailure = 3
  case regionMonitoringDenied = 4
  case regionMonitoringFailure = 5
  case regionMonitoringSetupDelayed = 6
  case regionMonitoringResponseDelayed = 7
  case geocodeFoundNoResult = 8
  case geocodeFoundPartialResult = 9
  case geocodeCanceled = 10
  case deferredFailed = 11
  case deferredCanceled = 12
  case deferredAccuracyAuthorizationDenied = 13
  case rangingUnavailable = 14
  case rangingFailure = 15
  case promptDeclined = 16
  case deferredNotUpdatingLocation = 17
  case deferredAccuracyTooLow = 18
  case deferredDistanceFiltered = 19
  case historicalLocationError = 20
  case timeout = 100
  case unavailable = 101
  case insecureContext = 102

  public var description: String {
    switch self {
    case .locationUnknown: return "The location is currently unknown."
    case .denied: return "Location permission was denied."
    case .network: return "The location provider could not reach its network service."
    case .headingFailure: return "The heading could not be determined."
    case .regionMonitoringDenied: return "Region monitoring is denied."
    case .regionMonitoringFailure: return "Region monitoring failed."
    case .regionMonitoringSetupDelayed: return "Region monitoring setup was delayed."
    case .regionMonitoringResponseDelayed: return "The region monitoring response was delayed."
    case .geocodeFoundNoResult: return "No geocoding result was found."
    case .geocodeFoundPartialResult: return "Only a partial geocoding result was found."
    case .geocodeCanceled: return "Geocoding was canceled."
    case .deferredFailed: return "Deferred location updates failed."
    case .deferredCanceled: return "Deferred location updates were canceled."
    case .deferredAccuracyAuthorizationDenied: return "Deferred accuracy authorization was denied."
    case .rangingUnavailable: return "Beacon ranging is unavailable."
    case .rangingFailure: return "Beacon ranging failed."
    case .promptDeclined: return "The location prompt was declined."
    case .deferredNotUpdatingLocation: return "Deferred updates are not active."
    case .deferredAccuracyTooLow: return "The requested deferred accuracy is too low."
    case .deferredDistanceFiltered: return "The deferred update was filtered by distance."
    case .historicalLocationError: return "The historical location request failed."
    case .timeout: return "The location request timed out."
    case .unavailable: return "Location services are unavailable."
    case .insecureContext: return "Browser location requires a secure context (HTTPS or localhost)."
    }
  }

  public var localizedDescription: String { description }
}

/// Delegate callbacks mirror the useful CLLocationManager lifecycle. Default
/// implementations make the protocol pleasant to adopt in SwiftUI views.
public protocol CLLocationManagerDelegate: AnyObject {
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error)
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager)
  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus)
}

public extension CLLocationManagerDelegate {
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    locationManager(manager, didChangeAuthorization: manager.authorizationStatus)
  }
  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {}
}


#if !hasFeature(Embedded)
extension CLLocationCoordinate2D: Codable {}
extension CLAuthorizationStatus: Codable {}
extension CLAccuracyAuthorization: Codable {}
extension CLError: Codable {}
#endif

// MARK: - Provider boundary

/// Internal browser/native boundary. It is deliberately not public: clients
/// interact with CLLocationManager and never need JavaScript or provider types.
protocol _CLLocationProvider: AnyObject {
  var authorizationStatus: CLAuthorizationStatus { get }
  var isLocationServicesEnabled: Bool { get }
  var availabilityError: CLError? { get }
  func requestAuthorization(_ completion: @escaping @Sendable (Result<CLAuthorizationStatus, CLError>) -> Void)
  func startUpdatingLocation(
    desiredAccuracy: CLLocationAccuracy,
    distanceFilter: CLLocationDistance,
    onLocation: @escaping @Sendable (CLLocation) -> Void,
    onError: @escaping @Sendable (CLError) -> Void
  )
  func requestLocation(
    desiredAccuracy: CLLocationAccuracy,
    timeout: Double,
    onLocation: @escaping @Sendable (CLLocation) -> Void,
    onError: @escaping @Sendable (CLError) -> Void
  )
  func stopUpdatingLocation()
}

private enum _CLLocationProviderRegistry {
  private struct State {
    var cachedAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    var factory: () -> any _CLLocationProvider = { _UnavailableLocationProvider() }
  }
  private static let state = _Locked(State())

  static var cachedAuthorizationStatus: CLAuthorizationStatus {
    get { state.withLock { $0.cachedAuthorizationStatus } }
    set { state.withLock { $0.cachedAuthorizationStatus = newValue } }
  }
  static var factory: () -> any _CLLocationProvider {
    get { state.withLock { $0.factory } }
    set { state.withLock { $0.factory = newValue } }
  }

  static func make() -> any _CLLocationProvider { factory() }
}

private final class _UnavailableLocationProvider: _CLLocationProvider {
  var authorizationStatus: CLAuthorizationStatus { .notDetermined }
  var isLocationServicesEnabled: Bool { false }
  var availabilityError: CLError? { .unavailable }
  func requestAuthorization(_ completion: @escaping @Sendable (Result<CLAuthorizationStatus, CLError>) -> Void) {
    completion(.failure(.unavailable))
  }
  func startUpdatingLocation(desiredAccuracy: Double, distanceFilter: Double,
                             onLocation: @escaping @Sendable (CLLocation) -> Void,
                             onError: @escaping @Sendable (CLError) -> Void) {
    onError(.unavailable)
  }
  func requestLocation(desiredAccuracy: Double, timeout: Double,
                       onLocation: @escaping @Sendable (CLLocation) -> Void,
                       onError: @escaping @Sendable (CLError) -> Void) {
    onError(.unavailable)
  }
  func stopUpdatingLocation() {}
}

/// Whether a manager still exists, for the browser's callbacks that can arrive after it is gone (a permission prompt the
/// visitor answers later, a position that comes late). Embedded Swift has no weak references, so the callbacks hold this
/// and the manager unowned, and look here first.
final class _CLManagerLiveness: @unchecked Sendable {
  var alive = true
}

/// The manager owns a provider and translates its callbacks into Apple-shaped
/// delegate calls, one-shot requests, and async streams.
public final class CLLocationManager: @unchecked Sendable {
  private let liveness = _CLManagerLiveness()
  #if hasFeature(Embedded)
  public unowned(unsafe) var delegate: (any CLLocationManagerDelegate)?
  #else
  public weak var delegate: (any CLLocationManagerDelegate)?
  #endif
  public var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
  public var distanceFilter: CLLocationDistance = kCLDistanceFilterNone
  public var pausesLocationUpdatesAutomatically = true
  public var allowsBackgroundLocationUpdates = false
  public var requestTimeout: Double = 10

  public private(set) var authorizationStatus: CLAuthorizationStatus
  public private(set) var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
  public private(set) var isUpdatingLocation = false

  private let provider: any _CLLocationProvider
  private var pendingOneShot: (@Sendable (Result<CLLocation, CLError>) -> Void)?
  /// Whether `pendingOneShot` was set by the async request in flight (`requestLocationForAsync`).
  private var asyncOwnsPendingOneShot = false
  private var pendingAuthorization = false
  private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Error>?
  private var pendingStart = false
  private var lastLocation: CLLocation?
  private var streamContinuations: [UInt64: AsyncThrowingStream<CLLocation, Error>.Continuation] = [:]
  private var nextStreamID: UInt64 = 1
  private var asyncRequest: (id: UInt64, continuation: CheckedContinuation<CLLocation, Error>)?
  private var nextRequestID: UInt64 = 1

  public init() {
    provider = _CLLocationProviderRegistry.make()
    authorizationStatus = provider.authorizationStatus
    _CLLocationProviderRegistry.cachedAuthorizationStatus = authorizationStatus
  }

  /// Test/runtime-adapter initializer. It is intentionally internal so the
  /// public module cannot acquire a browser-specific provider dependency.
  init(provider: any _CLLocationProvider) {
    self.provider = provider
    authorizationStatus = provider.authorizationStatus
    _CLLocationProviderRegistry.cachedAuthorizationStatus = authorizationStatus
  }

  /// Exposes the runtime-wide service availability using the same spelling as
  /// CoreLocation. It does not leak the provider or browser implementation.
  public static func locationServicesEnabled() -> Bool {
    _CLLocationProviderRegistry.make().isLocationServicesEnabled
  }

  @available(*, deprecated, message: "Use CLLocationManager.authorizationStatus on an instance")
  public static func authorizationStatus() -> CLAuthorizationStatus {
    _CLLocationProviderRegistry.cachedAuthorizationStatus
  }

  public func requestWhenInUseAuthorization() {
    _requestAuthorization()
  }

  public func requestAlwaysAuthorization() {
    // Browser geolocation has no background/always permission. Treat this as
    // a foreground request so Apple-shaped call sites remain portable.
    _requestAuthorization()
  }

  public func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String) {
    _ = purposeKey
    accuracyAuthorization = .fullAccuracy
  }

  /// Async permission request for code that does not use a delegate. A denied
  /// browser prompt throws `CLError.denied`, while an approved prompt returns
  /// `.authorizedWhenInUse`.
  public func requestAuthorization() async throws -> CLAuthorizationStatus {
    #if !hasFeature(Embedded)
    try Task.checkCancellation()
    #endif
    if authorizationStatus.isAuthorized { return authorizationStatus }
    if authorizationStatus == .denied { throw CLError.denied }
    if authorizationContinuation != nil { throw CLError.locationUnknown }
    return try await withTaskCancellationHandler(operation: {
      #if !hasFeature(Embedded)
    try Task.checkCancellation()
    #endif
      return try await withCheckedThrowingContinuation { continuation in
        authorizationContinuation = continuation
        _requestAuthorization()
      }
    }, onCancel: { [unowned(unsafe) self] in
      self.cancelAuthorizationRequest()
    })
  }

  private func _requestAuthorization() {
    guard authorizationStatus != .denied else {
      delegate?.locationManagerDidChangeAuthorization(self)
      return
    }
    guard !pendingAuthorization else { return }
    pendingAuthorization = true
    provider.requestAuthorization { [unowned(unsafe) self, liveness] result in
      guard liveness.alive else { return }
            self.pendingAuthorization = false
      switch result {
      case .success(let status):
        self.authorizationStatus = status
        _CLLocationProviderRegistry.cachedAuthorizationStatus = status
        if let continuation = self.authorizationContinuation {
          self.authorizationContinuation = nil
          if status == .denied { continuation.resume(throwing: CLError.denied) }
          else { continuation.resume(returning: status) }
        }
        self.delegate?.locationManagerDidChangeAuthorization(self)
        if status.isAuthorized, let pending = self.pendingOneShot {
          self.pendingOneShot = nil
          let shouldStartWatch = self.pendingStart
          self.pendingStart = false
          self.startOneShot(completion: pending)
          if shouldStartWatch { self.startUpdatingLocation() }
        } else if status.isAuthorized, self.pendingStart {
          self.pendingStart = false
          self.startUpdatingLocation()
        } else if !status.isAuthorized {
          // Restricted/non-authorized browser states cannot produce a watch.
          // Treat them like CoreLocation's denied error so pending streams and
          // one-shot requests never remain suspended indefinitely.
          let hadPendingRequest = self.pendingOneShot != nil
          self.failPendingOneShot(.denied)
          self.pendingStart = false
          if self.isUpdatingLocation { self.stopProviderOnly() }
          if !hadPendingRequest { self.delegate?.locationManager(self, didFailWithError: CLError.denied) }
          self.finishStreams(throwing: CLError.denied)
        }
      case .failure(let error):
        if error == .denied { self.authorizationStatus = .denied }
        if error == .denied { _CLLocationProviderRegistry.cachedAuthorizationStatus = .denied }
        self.delegate?.locationManagerDidChangeAuthorization(self)
        if let continuation = self.authorizationContinuation {
          self.authorizationContinuation = nil
          continuation.resume(throwing: error)
        }
        let hadPendingRequest = self.pendingOneShot != nil
        self.failPendingOneShot(error)
        self.pendingStart = false
        if self.isUpdatingLocation { self.stopProviderOnly() }
        if !hadPendingRequest { self.delegate?.locationManager(self, didFailWithError: error) }
        self.finishStreams(throwing: error)
      }
    }
  }

  public func startUpdatingLocation() {
    guard !isUpdatingLocation else { return }
    guard provider.isLocationServicesEnabled else {
      report(error: provider.availabilityError ?? .unavailable)
      return
    }
    guard let availabilityError = provider.availabilityError else {
      if authorizationStatus == .denied {
        report(error: .denied)
        return
      }
      if !authorizationStatus.isAuthorized {
        pendingStart = true
        _requestAuthorization()
        return
      }
      isUpdatingLocation = true
      provider.startUpdatingLocation(
        desiredAccuracy: desiredAccuracy,
        distanceFilter: distanceFilter,
        onLocation: { [unowned(unsafe) self, liveness] location in
          guard liveness.alive else { return }
          self.receive(location)
        },
        onError: { [unowned(unsafe) self, liveness] error in
          guard liveness.alive else { return }
          self.handleWatchError(error)
        }
      )
      return
    }
    report(error: availabilityError)
  }

  public func stopUpdatingLocation() {
    pendingStart = false
    stopProviderOnly()
    finishStreams()
  }

  private func stopProviderOnly() {
    isUpdatingLocation = false
    provider.stopUpdatingLocation()
    lastLocation = nil
  }

  /// Requests one location and delivers it through the delegate, matching the
  /// CoreLocation one-shot API. Use `location()` when an async result is more
  /// convenient.
  public func requestLocation() {
    guard provider.isLocationServicesEnabled else {
      // A one-shot failure must not tear down an unrelated continuous watch.
      notify(error: provider.availabilityError ?? .unavailable)
      return
    }
    guard provider.availabilityError == nil else {
      notify(error: provider.availabilityError!)
      return
    }
    guard authorizationStatus != .denied else {
      notify(error: .denied)
      return
    }
    guard pendingOneShot == nil else {
      notify(error: .locationUnknown)
      return
    }
    guard authorizationStatus.isAuthorized else {
      pendingOneShot = { [unowned(unsafe) self] result in
        switch result {
        case .success(let location): self.receive(location, applyDistanceFilter: false)
        case .failure(let error): self.notify(error: error)
        }
      }
      _requestAuthorization()
      return
    }
    startOneShot { [unowned(unsafe) self] result in
      switch result {
      case .success(let location): self.receive(location, applyDistanceFilter: false)
      case .failure(let error): self.notify(error: error)
      }
    }
  }

  /// Async/await-friendly one-shot request. Cancellation stops the pending
  /// request and maps to Swift's standard CancellationError.
  public func location() async throws -> CLLocation {
    let id = nextRequestID
    nextRequestID &+= 1
    return try await withTaskCancellationHandler(operation: {
      #if !hasFeature(Embedded)
    try Task.checkCancellation()
    #endif
      return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
        guard asyncRequest == nil else {
          continuation.resume(throwing: CLError.locationUnknown)
          return
        }
        asyncRequest = (id, continuation)
        requestLocationForAsync()
      }
    }, onCancel: { [unowned(unsafe) self] in
      self.cancelAsyncRequest(id: id)
    })
  }

  /// Async overload retaining the CoreLocation request spelling. Swift can
  /// select this overload from `try await manager.requestLocation()` while
  /// synchronous callers continue to use the delegate-based method above.
  public func requestLocation() async throws -> CLLocation {
    try await location()
  }

  private func requestLocationForAsync() {
    guard provider.isLocationServicesEnabled else {
      resolveAsync(.failure(provider.availabilityError ?? .unavailable)); return
    }
    guard let error = provider.availabilityError else {
      guard authorizationStatus != .denied else {
        resolveAsync(.failure(CLError.denied))
        return
      }
      guard pendingOneShot == nil else {
        resolveAsync(.failure(CLError.locationUnknown))
        return
      }
      asyncOwnsPendingOneShot = true
      guard authorizationStatus.isAuthorized else {
        pendingOneShot = { [unowned(unsafe) self] result in
          self.resolveAsync(result.mapError { $0 as Error })
        }
        _requestAuthorization()
        return
      }
      startOneShot { [unowned(unsafe) self] result in
        self.resolveAsync(result.mapError { $0 as Error })
      }
      return
    }
    resolveAsync(.failure(error))
  }

  private func cancelAsyncRequest(id: UInt64) {
    guard asyncRequest?.id == id else { return }
    let request = asyncRequest
    asyncRequest = nil
    // Clear the one-shot only when this request started it: a delegate-based request may own the shared slot.
    if asyncOwnsPendingOneShot {
      pendingOneShot = nil
      asyncOwnsPendingOneShot = false
    }
    request?.continuation.resume(throwing: CancellationError())
  }

  private func cancelAuthorizationRequest() {
    guard let continuation = authorizationContinuation else { return }
    authorizationContinuation = nil
    continuation.resume(throwing: CancellationError())
  }

  private func resolveAsync(_ result: Result<CLLocation, Error>) {
    guard let request = asyncRequest else { return }
    asyncRequest = nil
    asyncOwnsPendingOneShot = false
    request.continuation.resume(with: result)
  }

  /// Starts continuous updates and yields each accepted fix. Terminating the
  /// stream stops the browser watch, which prevents callbacks after a view's
  /// task/lifecycle has gone away.
  public func locationUpdates() -> AsyncThrowingStream<CLLocation, Error> {
    let id = nextStreamID
    nextStreamID &+= 1
    let stream = AsyncThrowingStream<CLLocation, Error> { [unowned(unsafe) self] continuation in
            self.streamContinuations[id] = continuation
      continuation.onTermination = { [unowned(unsafe) self] _ in
                self.streamContinuations.removeValue(forKey: id)
        if self.streamContinuations.isEmpty { self.stopUpdatingLocation() }
      }
      self.startUpdatingLocation()
    }
    return stream
  }

  public var updates: AsyncThrowingStream<CLLocation, Error> { locationUpdates() }

  private func startOneShot(completion: @escaping @Sendable (Result<CLLocation, CLError>) -> Void) {
    pendingOneShot = completion
    provider.requestLocation(
      desiredAccuracy: desiredAccuracy,
      timeout: requestTimeout,
      onLocation: { [unowned(unsafe) self, liveness] location in
        guard liveness.alive else { return }
                let completion = self.pendingOneShot
        self.pendingOneShot = nil
        completion?(.success(location))
      },
      onError: { [unowned(unsafe) self, liveness] error in
        guard liveness.alive else { return }
                if error == .denied {
          self.authorizationStatus = .denied
          _CLLocationProviderRegistry.cachedAuthorizationStatus = .denied
          self.delegate?.locationManagerDidChangeAuthorization(self)
        }
        let completion = self.pendingOneShot
        self.pendingOneShot = nil
        completion?(.failure(error))
      }
    )
  }

  private func receive(_ location: CLLocation, applyDistanceFilter: Bool = true) {
    if applyDistanceFilter, distanceFilter >= 0, let lastLocation,
       lastLocation.distance(from: location) < distanceFilter {
      return
    }
    lastLocation = location
    delegate?.locationManager(self, didUpdateLocations: [location])
    // A consumer may cancel from inside its iterator while a value is being
    // delivered; iterate over a snapshot so `onTermination` can safely remove
    // its continuation during the callback.
    for continuation in Array(streamContinuations.values) { continuation.yield(location) }
  }

  private func handleWatchError(_ error: CLError) {
    if error == .denied || error == .unavailable || error == .insecureContext {
      if error == .denied {
        authorizationStatus = .denied
        _CLLocationProviderRegistry.cachedAuthorizationStatus = .denied
        delegate?.locationManagerDidChangeAuthorization(self)
      }
      stopProviderOnly()
      report(error: error)
      return
    }
    // locationUnknown is a transient CoreLocation condition. Preserve the
    // watch and its async stream so a later browser fix can still succeed.
    delegate?.locationManager(self, didFailWithError: error)
  }

  private func report(error: CLError) {
    delegate?.locationManager(self, didFailWithError: error)
    finishStreams(throwing: error)
    resolveAsync(.failure(error))
  }

  private func notify(error: CLError) {
    delegate?.locationManager(self, didFailWithError: error)
  }

  private func finishStreams(throwing error: Error? = nil) {
    let continuations = Array(streamContinuations.values)
    streamContinuations.removeAll()
    // `continuations` is a value collection retained above; finish after the
    // dictionary is cleared so onTermination can safely re-enter the manager.
    if !continuations.isEmpty {
      for continuation in continuations {
        if let error { continuation.finish(throwing: error) }
        else { continuation.finish() }
      }
    }
  }

  private func failPendingOneShot(_ error: CLError) {
    guard let completion = pendingOneShot else { return }
    pendingOneShot = nil
    completion(.failure(error))
  }

  deinit {
    liveness.alive = false
    provider.stopUpdatingLocation()
    authorizationContinuation?.resume(throwing: CLError.unavailable)
    asyncRequest?.continuation.resume(throwing: CLError.unavailable)
    for continuation in streamContinuations.values { continuation.finish() }
  }
}

// MARK: - Browser implementation
