import Foundation
import Testing
@testable import SwiftUIWebCoreLocation

@Suite(.processGlobalState)
@MainActor
final class BrowserLocationTests {
  @Test
  func testBrowserPermissionDeniedStopsPendingWatch() {
    let provider = TestLocationProvider(status: .notDetermined)
    let manager = CLLocationManager(provider: provider)
    let delegate = TestLocationDelegate()
    manager.delegate = delegate

    manager.startUpdatingLocation()
    _expectTrue(provider.authorizationWasRequested)
    provider.completeAuthorization(.success(.authorizedWhenInUse))
    _expectTrue(manager.isUpdatingLocation)
    _expectTrue(provider.watchWasStarted)
    manager.stopUpdatingLocation()

    let deniedProvider = TestLocationProvider(status: .notDetermined)
    let deniedManager = CLLocationManager(provider: deniedProvider)
    let deniedDelegate = TestLocationDelegate()
    deniedManager.delegate = deniedDelegate
    deniedManager.startUpdatingLocation()
    deniedProvider.completeAuthorization(.failure(.denied))

    _expectEqual(deniedManager.authorizationStatus, .denied)
    _expectFalse(deniedManager.isUpdatingLocation)
    _expectEqual(deniedDelegate.authorizationChanges, 1)
    _expectEqual(deniedDelegate.errors, [.denied])
  }

  @Test
  func testBrowserAsyncPermissionRequestReturnsAuthorizedState() async throws {
    let provider = TestLocationProvider(status: .notDetermined)
    let manager = CLLocationManager(provider: provider)
    let request = Task { try await manager.requestAuthorization() }
    // Async Swift Testing cases can share the executor with the child Task under the
    // full package suite. A bounded sleep gives the request task a real
    // scheduling opportunity instead of relying on a small number of yields.
    for _ in 0..<200 {
      if provider.authorizationWasRequested { break }
      await Task.yield()
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    guard provider.authorizationWasRequested else {
      request.cancel()
      return _fail("The manager did not start the browser permission request")
    }
    provider.completeAuthorization(.success(.authorizedWhenInUse))
    let status = try await request.value
    _expectEqual(status, .authorizedWhenInUse)
  }

  @Test
  func testBrowserContinuousWatchHonorsAccuracyAndStopsAtLifecycleEnd() {
    let provider = TestLocationProvider(status: .authorizedWhenInUse)
    let manager = CLLocationManager(provider: provider)
    let delegate = TestLocationDelegate()
    manager.delegate = delegate
    manager.distanceFilter = 100
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters

    manager.startUpdatingLocation()
    _expectTrue(manager.isUpdatingLocation)
    _expectTrue(provider.watchWasStarted)
    _expectEqual(provider.watchDesiredAccuracy, kCLLocationAccuracyHundredMeters)

    provider.emit(CLLocation(latitude: 37.3317, longitude: -122.0307))
    // Roughly 11m away: less than the requested 100m filter.
    provider.emit(CLLocation(latitude: 37.3318, longitude: -122.0307))
    _expectEqual(delegate.locations.count, 1)

    manager.stopUpdatingLocation()
    _expectTrue(provider.watchWasStopped)
    provider.emit(CLLocation(latitude: 37.3337, longitude: -122.0307))
    _expectEqual(delegate.locations.count, 1)
  }

  @Test
  func testBrowserInsecureContextFailsBeforePermissionPrompt() {
    let provider = TestLocationProvider(status: .notDetermined)
    provider.availabilityError = .insecureContext
    let manager = CLLocationManager(provider: provider)
    let delegate = TestLocationDelegate()
    manager.delegate = delegate

    manager.startUpdatingLocation()

    _expectFalse(provider.authorizationWasRequested)
    _expectEqual(delegate.errors, [.insecureContext])
    _expectFalse(manager.isUpdatingLocation)
  }

  @Test
  func testBrowserUnavailableLocationIsReportedWithoutStartingAWatch() {
    let provider = TestLocationProvider(status: .authorizedWhenInUse)
    provider.isLocationServicesEnabled = false
    provider.availabilityError = .unavailable
    let manager = CLLocationManager(provider: provider)
    let delegate = TestLocationDelegate()
    manager.delegate = delegate

    manager.requestLocation()

    _expectEqual(delegate.errors, [.unavailable])
    _expectFalse(provider.watchWasStarted)
    _expectFalse(manager.isUpdatingLocation)
  }

  @Test
  func testBrowserOneShotAsyncRequestPropagatesTimeout() async {
    let provider = TestLocationProvider(status: .authorizedWhenInUse)
    let manager = CLLocationManager(provider: provider)
    let request = Task { () -> Result<CLLocation, Error> in
      do { return .success(try await manager.location()) }
      catch { return .failure(error) }
    }
    for _ in 0..<200 {
      if provider.oneShotWasRequested { break }
      await Task.yield()
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    _expectTrue(provider.oneShotWasRequested)
    guard provider.oneShotWasRequested else {
      request.cancel()
      return
    }
    provider.completeOneShot(.failure(.timeout))

    let result = await request.value
    guard case .failure(let error) = result else {
      return _fail("Expected a timeout")
    }
    _expectEqual(error as? CLError, .timeout)
  }

  @Test
  func testBrowserAsyncUpdatesFinishWhenPermissionIsRevoked() async {
    let provider = TestLocationProvider(status: .authorizedWhenInUse)
    let manager = CLLocationManager(provider: provider)
    let stream = manager.locationUpdates()
    await Task.yield()
    provider.emit(CLLocation(latitude: 48.8566, longitude: 2.3522))
    provider.failWatch(.denied)

    var values: [CLLocation] = []
    do {
      for try await location in stream {
        values.append(location)
      }
    } catch {
      _expectEqual(error as? CLError, .denied)
    }
    _expectEqual(values.count, 1)
    _expectTrue(provider.watchWasStopped)
  }
}

private final class TestLocationDelegate: CLLocationManagerDelegate {
  var locations: [CLLocation] = []
  var errors: [CLError] = []
  var authorizationChanges = 0

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    self.locations.append(contentsOf: locations)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    if let error = error as? CLError { errors.append(error) }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    authorizationChanges += 1
  }
}

private final class TestLocationProvider: _CLLocationProvider {
  var authorizationStatus: CLAuthorizationStatus
  var isLocationServicesEnabled = true
  var availabilityError: CLError?
  var authorizationWasRequested = false
  var watchWasStarted = false
  var watchWasStopped = false
  var oneShotWasRequested = false
  var watchDesiredAccuracy: CLLocationAccuracy?

  private var authorizationCompletion: (@Sendable (Result<CLAuthorizationStatus, CLError>) -> Void)?
  private var watchLocation: (@Sendable (CLLocation) -> Void)?
  private var watchError: (@Sendable (CLError) -> Void)?
  private var oneShotLocation: (@Sendable (CLLocation) -> Void)?
  private var oneShotError: (@Sendable (CLError) -> Void)?

  init(status: CLAuthorizationStatus) {
    authorizationStatus = status
  }

  func requestAuthorization(_ completion: @escaping @Sendable (Result<CLAuthorizationStatus, CLError>) -> Void) {
    authorizationWasRequested = true
    authorizationCompletion = completion
  }

  func startUpdatingLocation(desiredAccuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance,
                             onLocation: @escaping @Sendable (CLLocation) -> Void,
                             onError: @escaping @Sendable (CLError) -> Void) {
    watchWasStarted = true
    watchDesiredAccuracy = desiredAccuracy
    watchLocation = onLocation
    watchError = onError
  }

  func requestLocation(desiredAccuracy: CLLocationAccuracy, timeout: Double,
                       onLocation: @escaping @Sendable (CLLocation) -> Void,
                       onError: @escaping @Sendable (CLError) -> Void) {
    oneShotWasRequested = true
    oneShotLocation = onLocation
    oneShotError = onError
  }

  func stopUpdatingLocation() {
    watchWasStopped = true
    watchLocation = nil
    watchError = nil
  }

  func completeAuthorization(_ result: Result<CLAuthorizationStatus, CLError>) {
    if case .success(let status) = result { authorizationStatus = status }
    authorizationCompletion?(result)
    authorizationCompletion = nil
  }

  func emit(_ location: CLLocation) { watchLocation?(location) }
  func failWatch(_ error: CLError) { watchError?(error) }

  func completeOneShot(_ result: Result<CLLocation, CLError>) {
    switch result {
    case .success(let location): oneShotLocation?(location)
    case .failure(let error): oneShotError?(error)
    }
    oneShotLocation = nil
    oneShotError = nil
  }
}
