import Foundation
import Testing
@testable import SwiftUIWebCoreLocation

@Suite(.processGlobalState)
@MainActor
struct CoreLocationContractsTests {
  @Test
  func coordinatesValidateGeographicLimitsAndDistanceWrapsTheDateline() {
    _expectTrue(CLLocationCoordinate2D.zero.isValid)
    _expectTrue(CLLocationCoordinate2D(latitude: -90, longitude: -180).isValid)
    _expectTrue(CLLocationCoordinate2D(latitude: 90, longitude: 180).isValid)
    _expectFalse(CLLocationCoordinate2D(latitude: 90.001, longitude: 0).isValid)
    _expectFalse(CLLocationCoordinate2D(latitude: 0, longitude: -180.001).isValid)
    _expectFalse(CLLocationCoordinate2D(latitude: .nan, longitude: 0).isValid)
    _expectFalse(CLLocationCoordinate2D(latitude: 0, longitude: .infinity).isValid)
    _expectTrue(CLLocationCoordinate2DIsValid(.zero))

    let west = CLLocationCoordinate2D(latitude: 0, longitude: 179.9)
    let east = CLLocationCoordinate2D(latitude: 0, longitude: -179.9)
    _expectEqual(west.distance(to: east), 22_264, accuracy: 2)
    _expectTrue(west.distance(to: .zero).isFinite)
    _expectTrue(CLLocationCoordinate2D(latitude: .nan, longitude: 0).distance(to: .zero).isNaN)
  }

  @Test
  func locationValuesRetainDefaultsEqualityAndTimestampSemantics() {
    let timestamp = Date(timeIntervalSince1970: 12)
    let location = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 37, longitude: -122),
      altitude: 4,
      horizontalAccuracy: 5,
      verticalAccuracy: 6,
      course: 7,
      speed: 8,
      timestamp: timestamp
    )
    let same = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 37, longitude: -122),
      altitude: 4,
      horizontalAccuracy: 5,
      verticalAccuracy: 6,
      course: 7,
      speed: 8,
      timestamp: timestamp
    )
    _expectEqual(location, same)
    _expectEqual(location.distance(from: same), 0, accuracy: 0.001)
    _expectTrue(location.description.contains("37.0, -122.0"))
    _expectTrue(location.description.contains("±5.0m"))

    let defaults = CLLocation(latitude: 0, longitude: 0)
    _expectEqual(defaults.altitude, 0)
    _expectEqual(defaults.horizontalAccuracy, -1)
    _expectEqual(defaults.verticalAccuracy, -1)
    _expectEqual(defaults.course, -1)
    _expectEqual(defaults.speed, -1)

    let changedTimestamp = CLLocation(
      coordinate: location.coordinate,
      altitude: location.altitude,
      horizontalAccuracy: location.horizontalAccuracy,
      verticalAccuracy: location.verticalAccuracy,
      course: location.course,
      speed: location.speed,
      timestamp: Date(timeIntervalSince1970: 13)
    )
    _expectNotEqual(location, changedTimestamp)
  }

  @Test
  func authorizationAliasesAndAllLocationErrorDescriptionsAreStable() {
    _expectEqual(CLAuthorizationStatus.authorized, .authorizedWhenInUse)
    _expectFalse(CLAuthorizationStatus.notDetermined.isAuthorized)
    _expectFalse(CLAuthorizationStatus.restricted.isAuthorized)
    _expectFalse(CLAuthorizationStatus.denied.isAuthorized)
    _expectTrue(CLAuthorizationStatus.authorizedAlways.isAuthorized)
    _expectTrue(CLAuthorizationStatus.authorizedWhenInUse.isAuthorized)
    _expectEqual(CLAccuracyAuthorization.fullAccuracy.rawValue, 0)
    _expectEqual(CLAccuracyAuthorization.reducedAccuracy.rawValue, 1)

    let cases: [(CLError, String)] = [
      (.locationUnknown, "The location is currently unknown."),
      (.denied, "Location permission was denied."),
      (.network, "The location provider could not reach its network service."),
      (.headingFailure, "The heading could not be determined."),
      (.regionMonitoringDenied, "Region monitoring is denied."),
      (.regionMonitoringFailure, "Region monitoring failed."),
      (.regionMonitoringSetupDelayed, "Region monitoring setup was delayed."),
      (.regionMonitoringResponseDelayed, "The region monitoring response was delayed."),
      (.geocodeFoundNoResult, "No geocoding result was found."),
      (.geocodeFoundPartialResult, "Only a partial geocoding result was found."),
      (.geocodeCanceled, "Geocoding was canceled."),
      (.deferredFailed, "Deferred location updates failed."),
      (.deferredCanceled, "Deferred location updates were canceled."),
      (.deferredAccuracyAuthorizationDenied, "Deferred accuracy authorization was denied."),
      (.rangingUnavailable, "Beacon ranging is unavailable."),
      (.rangingFailure, "Beacon ranging failed."),
      (.promptDeclined, "The location prompt was declined."),
      (.deferredNotUpdatingLocation, "Deferred updates are not active."),
      (.deferredAccuracyTooLow, "The requested deferred accuracy is too low."),
      (.deferredDistanceFiltered, "The deferred update was filtered by distance."),
      (.historicalLocationError, "The historical location request failed."),
      (.timeout, "The location request timed out."),
      (.unavailable, "Location services are unavailable."),
      (.insecureContext, "Browser location requires a secure context (HTTPS or localhost).")
    ]
    for (error, description) in cases {
      _expectEqual(error.description, description)
      _expectEqual(error.localizedDescription, description)
    }
  }

  @Test
  func unavailableDefaultProviderFailsClosedForAuthorizationAndRequests() async {
    let manager = CLLocationManager()
    let delegate = ContractLocationDelegate()
    manager.delegate = delegate
    _expectFalse(CLLocationManager.locationServicesEnabled())

    manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "testing")
    _expectEqual(manager.accuracyAuthorization, .fullAccuracy)
    manager.requestWhenInUseAuthorization()
    _expectEqual(delegate.authorizationChanges, 1)
    _expectEqual(delegate.errors, [.unavailable])

    do {
      _ = try await manager.requestAuthorization()
      _fail("Unavailable hosts must reject async authorization")
    } catch let error as CLError {
      _expectEqual(error, .unavailable)
    } catch {
      _fail("Unexpected error: \(error)")
    }

    do {
      _ = try await manager.location()
      _fail("Unavailable hosts must reject async location requests")
    } catch let error as CLError {
      _expectEqual(error, .unavailable)
    } catch {
      _fail("Unexpected error: \(error)")
    }

    let requestDelegateLocation: () -> Void = manager.requestLocation
    requestDelegateLocation()
    manager.startUpdatingLocation()
    _expectEqual(delegate.errors, [.unavailable, .unavailable, .unavailable, .unavailable])
    _expectFalse(manager.isUpdatingLocation)
  }

  @Test
  func asyncAuthorizationReturnsCachedGrantRejectsDuplicateAndSupportsCancellation() async throws {
    let authorizedProvider = ContractLocationProvider(status: .authorizedAlways)
    let authorizedManager = CLLocationManager(provider: authorizedProvider)
    let authorizedStatus = try await authorizedManager.requestAuthorization()
    _expectEqual(authorizedStatus, .authorizedAlways)
    _expectEqual(authorizedProvider.authorizationRequests, 0)

    let provider = ContractLocationProvider(status: .notDetermined)
    let manager = CLLocationManager(provider: provider)
    let firstRequest = Task { try await manager.requestAuthorization() }
    await waitFor { provider.authorizationRequests == 1 }

    do {
      _ = try await manager.requestAuthorization()
      _fail("Only one authorization continuation may be active")
    } catch let error as CLError {
      _expectEqual(error, .locationUnknown)
    }

    provider.completeAuthorization(.success(.authorizedWhenInUse))
    let firstStatus = try await firstRequest.value
    _expectEqual(firstStatus, .authorizedWhenInUse)

    let cancelledProvider = ContractLocationProvider(status: .notDetermined)
    let cancelledManager = CLLocationManager(provider: cancelledProvider)
    let cancelledRequest = Task { try await cancelledManager.requestAuthorization() }
    await waitFor { cancelledProvider.authorizationRequests == 1 }
    cancelledRequest.cancel()
    do {
      _ = try await cancelledRequest.value
      _fail("Cancellation must resume the authorization continuation")
    } catch is CancellationError {
      // Expected: cancellation is kept distinct from a permission denial.
    }
    cancelledProvider.completeAuthorization(.success(.authorizedWhenInUse))
    _expectEqual(cancelledManager.authorizationStatus, .authorizedWhenInUse)
  }

  @Test
  func alwaysAuthorizationUsesForegroundPermissionAndDefaultDelegateForwardsStatus() {
    let provider = ContractLocationProvider(status: .notDetermined)
    let manager = CLLocationManager(provider: provider)
    let delegate = AuthorizationOnlyLocationDelegate()
    manager.delegate = delegate

    manager.requestAlwaysAuthorization()
    _expectEqual(provider.authorizationRequests, 1)
    provider.completeAuthorization(.success(.authorizedWhenInUse))

    _expectEqual(manager.authorizationStatus, .authorizedWhenInUse)
    _expectEqual(delegate.statuses, [.authorizedWhenInUse])
  }

  @Test
  func oneShotSuccessHonorsProviderOptionsAndDoesNotDisturbAnActiveWatch() {
    let provider = ContractLocationProvider(status: .authorizedWhenInUse)
    let manager = CLLocationManager(provider: provider)
    let delegate = ContractLocationDelegate()
    manager.delegate = delegate
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    manager.distanceFilter = 5_000
    manager.requestTimeout = 3.5
    manager.startUpdatingLocation()
    let previous = CLLocation(latitude: 37, longitude: -122)
    provider.emit(previous)

    manager.requestLocation()
    _expectEqual(provider.oneShotAccuracy, kCLLocationAccuracyHundredMeters)
    _expectEqual(provider.oneShotTimeout, 3.5)
    provider.completeOneShot(.success(CLLocation(latitude: 37.001, longitude: -122)))

    _expectEqual(delegate.locations.count, 2)
    _expectTrue(manager.isUpdatingLocation)
    _expectFalse(provider.watchWasStopped)
    manager.stopUpdatingLocation()
    _expectTrue(provider.watchWasStopped)
  }

  @Test
  func asyncOneShotRejectsDuplicatesCancelsAndIgnoresLateCallbacks() async throws {
    let provider = ContractLocationProvider(status: .authorizedWhenInUse)
    let manager = CLLocationManager(provider: provider)
    let firstRequest = Task { try await manager.location() }
    await waitFor { provider.oneShotRequests == 1 }

    do {
      _ = try await manager.requestLocation()
      _fail("An overlapping async one-shot request must fail deterministically")
    } catch let error as CLError {
      _expectEqual(error, .locationUnknown)
    }

    firstRequest.cancel()
    do {
      _ = try await firstRequest.value
      _fail("A cancelled location request must throw CancellationError")
    } catch is CancellationError {
      // Expected.
    }
    provider.completeOneShot(.success(CLLocation(latitude: 1, longitude: 2)))

    let succeedingRequest = Task { try await manager.requestLocation() }
    await waitFor { provider.oneShotRequests == 2 }
    let expected = CLLocation(latitude: 48, longitude: 2)
    provider.completeOneShot(.success(expected))
    let actual = try await succeedingRequest.value
    _expectEqual(actual, expected)
  }

  @Test
  func transientWatchErrorsKeepUpdatesAliveButTerminalErrorsStopAndRevoke() {
    let provider = ContractLocationProvider(status: .authorizedWhenInUse)
    let manager = CLLocationManager(provider: provider)
    let delegate = ContractLocationDelegate()
    manager.delegate = delegate
    manager.startUpdatingLocation()
    provider.failWatch(.locationUnknown)
    _expectTrue(manager.isUpdatingLocation)
    _expectEqual(delegate.errors, [.locationUnknown])

    provider.emit(CLLocation(latitude: 1, longitude: 1))
    _expectEqual(delegate.locations.count, 1)
    provider.failWatch(.denied)
    _expectFalse(manager.isUpdatingLocation)
    _expectEqual(manager.authorizationStatus, .denied)
    _expectEqual(delegate.authorizationChanges, 1)
    _expectEqual(delegate.errors, [.locationUnknown, .denied])
    _expectTrue(provider.watchWasStopped)
  }

  @Test
  func watchWaitsForAuthorizationFiltersNearbyFixesAndFinishesOnStop() async throws {
    let provider = ContractLocationProvider(status: .notDetermined)
    let manager = CLLocationManager(provider: provider)
    manager.distanceFilter = 500

    let updates = manager.updates
    var iterator = updates.makeAsyncIterator()
    // Starting an already-pending watch must not issue another permission prompt.
    manager.startUpdatingLocation()
    await waitFor { provider.authorizationRequests == 1 }
    _expectFalse(provider.watchWasStarted)

    provider.completeAuthorization(.success(.authorizedWhenInUse))
    await waitFor { provider.watchWasStarted }
    _expectTrue(manager.isUpdatingLocation)

    let first = CLLocation(latitude: 0, longitude: 0)
    let nearby = CLLocation(latitude: 0.001, longitude: 0)
    let distant = CLLocation(latitude: 0.01, longitude: 0)
    provider.emit(first)
    provider.emit(nearby)
    provider.emit(distant)

    let firstUpdate = try await iterator.next()
    let secondUpdate = try await iterator.next()
    _expectEqual(firstUpdate, first)
    _expectEqual(secondUpdate, distant)
    manager.stopUpdatingLocation()
    let finalUpdate = try await iterator.next()
    _expectNil(finalUpdate)
    _expectFalse(manager.isUpdatingLocation)
    _expectTrue(provider.watchWasStopped)
  }

  @Test
  func synchronousOneShotWaitsForPermissionAndTerminatesOnRestrictedStatus() async {
    let provider = ContractLocationProvider(status: .notDetermined)
    let manager = CLLocationManager(provider: provider)
    let delegate = ContractLocationDelegate()
    manager.delegate = delegate

    let requestDelegateLocation: () -> Void = manager.requestLocation
    requestDelegateLocation()
    await waitFor { provider.authorizationRequests == 1 }
    _expectEqual(provider.oneShotRequests, 0)
    provider.completeAuthorization(.success(.authorizedWhenInUse))
    _expectEqual(provider.oneShotRequests, 1)

    let fix = CLLocation(latitude: 47, longitude: 8)
    provider.completeOneShot(.success(fix))
    _expectEqual(delegate.locations, [fix])
    _expectTrue(delegate.errors.isEmpty)

    let restrictedProvider = ContractLocationProvider(status: .notDetermined)
    let restrictedManager = CLLocationManager(provider: restrictedProvider)
    let restrictedDelegate = ContractLocationDelegate()
    restrictedManager.delegate = restrictedDelegate
    let requestRestrictedDelegateLocation: () -> Void = restrictedManager.requestLocation
    requestRestrictedDelegateLocation()
    await waitFor { restrictedProvider.authorizationRequests == 1 }
    restrictedProvider.completeAuthorization(.success(.restricted))

    _expectEqual(restrictedManager.authorizationStatus, .restricted)
    _expectEqual(restrictedDelegate.errors, [.denied])
    _expectEqual(restrictedProvider.oneShotRequests, 0)
  }

  @Test
  func asyncOneShotCanWaitForPermissionAndPropagatesProviderDenial() async throws {
    let provider = ContractLocationProvider(status: .notDetermined)
    let manager = CLLocationManager(provider: provider)
    let request = Task { try await manager.location() }
    await waitFor { provider.authorizationRequests == 1 }
    provider.completeAuthorization(.success(.authorizedWhenInUse))
    await waitFor { provider.oneShotRequests == 1 }

    let expected = CLLocation(latitude: -33, longitude: 151)
    provider.completeOneShot(.success(expected))
    let actual = try await request.value
    _expectEqual(actual, expected)

    let deniedProvider = ContractLocationProvider(status: .authorizedWhenInUse)
    let deniedManager = CLLocationManager(provider: deniedProvider)
    let deniedRequest = Task { try await deniedManager.requestLocation() }
    await waitFor { deniedProvider.oneShotRequests == 1 }
    deniedProvider.completeOneShot(.failure(.denied))

    do {
      _ = try await deniedRequest.value
      _fail("Provider denial must fail the async one-shot request")
    } catch let error as CLError {
      _expectEqual(error, .denied)
    }
    _expectEqual(deniedManager.authorizationStatus, .denied)
  }

  @Test
  func distanceWrapsTheDatelineFromEastToWestAndLocationsHashByValue() {
    let west = CLLocationCoordinate2D(latitude: 0, longitude: 179.9)
    let east = CLLocationCoordinate2D(latitude: 0, longitude: -179.9)
    _expectEqual(east.distance(to: west), 22_264, accuracy: 2)
    _expectEqual(east.distance(to: west), west.distance(to: east), accuracy: 0.001)

    let timestamp = Date(timeIntervalSince1970: 42)
    let first = CLLocation(coordinate: west, horizontalAccuracy: 3, timestamp: timestamp)
    let duplicate = CLLocation(coordinate: west, horizontalAccuracy: 3, timestamp: timestamp)
    let other = CLLocation(coordinate: east, horizontalAccuracy: 3, timestamp: timestamp)
    let unique: Set<CLLocation> = [first, duplicate, other]
    _expectEqual(unique.count, 2)
    _expectTrue(unique.contains(duplicate))
  }

  @Test
  func delegateWithOnlyDefaultCallbacksAcceptsEveryLifecycleEvent() {
    let provider = ContractLocationProvider(status: .notDetermined)
    let manager = CLLocationManager(provider: provider)
    let delegate = SilentLocationDelegate()
    manager.delegate = delegate

    manager.requestWhenInUseAuthorization()
    provider.completeAuthorization(.success(.authorizedWhenInUse))
    manager.startUpdatingLocation()
    provider.emit(CLLocation(latitude: 1, longitude: 2))
    provider.failWatch(.locationUnknown)

    _expectEqual(manager.authorizationStatus, .authorizedWhenInUse)
    _expectTrue(manager.isUpdatingLocation)
  }

  @Test
  func legacyClassAuthorizationStatusReflectsTheLatestManagerDecision() {
    let provider = ContractLocationProvider(status: .notDetermined)
    let manager = CLLocationManager(provider: provider)
    let legacy: any LegacyAuthorizationStatusSource.Type = CLLocationManager.self
    _expectEqual(legacy.authorizationStatus(), .notDetermined)

    manager.requestWhenInUseAuthorization()
    provider.completeAuthorization(.success(.authorizedWhenInUse))
    _expectEqual(legacy.authorizationStatus(), .authorizedWhenInUse)

    manager.startUpdatingLocation()
    provider.failWatch(.denied)
    _expectEqual(legacy.authorizationStatus(), .denied)
  }

  @Test
  func previouslyDeniedPermissionFailsEveryRequestWithoutPrompting() async {
    let provider = ContractLocationProvider(status: .denied)
    let manager = CLLocationManager(provider: provider)
    let delegate = ContractLocationDelegate()
    manager.delegate = delegate

    do {
      _ = try await manager.requestAuthorization()
      _fail("A denied permission must not resolve async authorization")
    } catch let error as CLError {
      _expectEqual(error, .denied)
    } catch {
      _fail("Unexpected error: \(error)")
    }

    manager.requestWhenInUseAuthorization()
    _expectEqual(delegate.authorizationChanges, 1, "A denied request re-announces the current status")

    manager.startUpdatingLocation()
    let requestDelegateLocation: () -> Void = manager.requestLocation
    requestDelegateLocation()
    _expectEqual(delegate.errors, [.denied, .denied])
    _expectFalse(manager.isUpdatingLocation)

    do {
      _ = try await manager.location()
      _fail("A denied permission must reject async location requests")
    } catch let error as CLError {
      _expectEqual(error, .denied)
    } catch {
      _fail("Unexpected error: \(error)")
    }
    _expectEqual(provider.authorizationRequests, 0)
    _expectEqual(provider.oneShotRequests, 0)
    _expectFalse(provider.watchWasStarted)
  }

  @Test
  func promptResolvingToDeniedThrowsFromAsyncAuthorization() async {
    let provider = ContractLocationProvider(status: .notDetermined)
    let manager = CLLocationManager(provider: provider)
    let request = Task { try await manager.requestAuthorization() }
    await waitFor { provider.authorizationRequests == 1 }
    provider.completeAuthorization(.success(.denied))

    do {
      _ = try await request.value
      _fail("A denied prompt must throw")
    } catch let error as CLError {
      _expectEqual(error, .denied)
    } catch {
      _fail("Unexpected error: \(error)")
    }
    _expectEqual(manager.authorizationStatus, .denied)
  }

  @Test
  func pendingPermissionQueuesOneShotAndWatchAndRejectsOverlappingRequests() async {
    let provider = ContractLocationProvider(status: .notDetermined)
    let manager = CLLocationManager(provider: provider)
    let delegate = ContractLocationDelegate()
    manager.delegate = delegate

    let requestDelegateLocation: () -> Void = manager.requestLocation
    requestDelegateLocation()
    requestDelegateLocation()
    _expectEqual(delegate.errors, [.locationUnknown], "Only one one-shot request may wait for permission")

    do {
      _ = try await manager.location()
      _fail("An async request must not overlap a queued one-shot request")
    } catch let error as CLError {
      _expectEqual(error, .locationUnknown)
    } catch {
      _fail("Unexpected error: \(error)")
    }

    manager.startUpdatingLocation()
    _expectEqual(provider.authorizationRequests, 1, "A pending prompt is shared by the queued watch")
    _expectFalse(provider.watchWasStarted)

    provider.completeAuthorization(.success(.authorizedWhenInUse))
    _expectEqual(provider.oneShotRequests, 1)
    _expectTrue(provider.watchWasStarted)
    _expectTrue(manager.isUpdatingLocation)

    manager.startUpdatingLocation()
    _expectEqual(delegate.errors, [.locationUnknown], "Starting an active watch again is a no-op")
  }

  @Test
  func revokedOrFailedReauthorizationStopsAnActiveWatch() {
    let provider = ContractLocationProvider(status: .authorizedWhenInUse)
    let manager = CLLocationManager(provider: provider)
    let delegate = ContractLocationDelegate()
    manager.delegate = delegate
    manager.startUpdatingLocation()
    manager.requestWhenInUseAuthorization()
    provider.completeAuthorization(.success(.restricted))

    _expectFalse(manager.isUpdatingLocation)
    _expectTrue(provider.watchWasStopped)
    _expectEqual(manager.authorizationStatus, .restricted)
    _expectEqual(delegate.errors, [.denied])

    let failingProvider = ContractLocationProvider(status: .authorizedWhenInUse)
    let failingManager = CLLocationManager(provider: failingProvider)
    let failingDelegate = ContractLocationDelegate()
    failingManager.delegate = failingDelegate
    failingManager.startUpdatingLocation()
    failingManager.requestWhenInUseAuthorization()
    failingProvider.completeAuthorization(.failure(.network))

    _expectFalse(failingManager.isUpdatingLocation)
    _expectTrue(failingProvider.watchWasStopped)
    _expectEqual(failingManager.authorizationStatus, .authorizedWhenInUse, "A non-denial failure keeps the grant")
    _expectEqual(failingDelegate.errors, [.network])
  }

  @Test
  func providerAvailabilityErrorsReachEveryEntryPoint() async {
    let insecure = ContractLocationProvider(status: .authorizedWhenInUse)
    insecure.availabilityError = .insecureContext
    let insecureManager = CLLocationManager(provider: insecure)
    let insecureDelegate = ContractLocationDelegate()
    insecureManager.delegate = insecureDelegate
    insecureManager.startUpdatingLocation()
    let requestInsecureLocation: () -> Void = insecureManager.requestLocation
    requestInsecureLocation()
    _expectEqual(insecureDelegate.errors, [.insecureContext, .insecureContext])
    await expectLocationError(.insecureContext, from: insecureManager)

    let disabled = ContractLocationProvider(status: .authorizedWhenInUse)
    disabled.isLocationServicesEnabled = false
    let disabledManager = CLLocationManager(provider: disabled)
    let disabledDelegate = ContractLocationDelegate()
    disabledManager.delegate = disabledDelegate
    disabledManager.startUpdatingLocation()
    let requestDisabledLocation: () -> Void = disabledManager.requestLocation
    requestDisabledLocation()
    _expectEqual(disabledDelegate.errors, [.unavailable, .unavailable], "Disabled services without a reason report unavailable")
    await expectLocationError(.unavailable, from: disabledManager)

    _expectFalse(insecure.watchWasStarted || disabled.watchWasStarted)
    _expectEqual(insecure.oneShotRequests + disabled.oneShotRequests, 0)
  }

  @Test
  func oneShotProviderFailuresReachTheDelegateAndAsyncCallers() async {
    let provider = ContractLocationProvider(status: .authorizedWhenInUse)
    let manager = CLLocationManager(provider: provider)
    let delegate = ContractLocationDelegate()
    manager.delegate = delegate
    let requestDelegateLocation: () -> Void = manager.requestLocation
    requestDelegateLocation()
    provider.completeOneShot(.failure(.timeout))
    _expectEqual(delegate.errors, [.timeout])
    _expectTrue(delegate.locations.isEmpty)

    let waitingProvider = ContractLocationProvider(status: .notDetermined)
    let waitingManager = CLLocationManager(provider: waitingProvider)
    let request = Task { try await waitingManager.location() }
    await waitFor { waitingProvider.authorizationRequests == 1 }
    waitingProvider.completeAuthorization(.success(.authorizedWhenInUse))
    await waitFor { waitingProvider.oneShotRequests == 1 }
    waitingProvider.completeOneShot(.failure(.timeout))
    do {
      _ = try await request.value
      _fail("A provider timeout must fail the queued async request")
    } catch let error as CLError {
      _expectEqual(error, .timeout)
    } catch {
      _fail("Unexpected error: \(error)")
    }
  }

  @Test
  func cancellingARejectedRequestLeavesTheActiveRequestRunning() async throws {
    let provider = ContractLocationProvider(status: .authorizedWhenInUse)
    let manager = CLLocationManager(provider: provider)
    let active = Task { try await manager.location() }
    await waitFor { provider.oneShotRequests == 1 }

    let cancelled = Task { () throws -> CLLocation in
      withUnsafeCurrentTask { $0?.cancel() }
      return try await manager.location()
    }
    do {
      _ = try await cancelled.value
      _fail("An already-cancelled request must throw")
    } catch is CancellationError {
      // Expected: the cancellation handler ignores the other request's id.
    }

    let expected = CLLocation(latitude: 10, longitude: 20)
    provider.completeOneShot(.success(expected))
    let actual = try await active.value
    _expectEqual(actual, expected)
  }

  @Test
  func releasingTheManagerFinishesOutstandingUpdateStreams() async throws {
    let provider = ContractLocationProvider(status: .authorizedWhenInUse)
    var iterator = makeOrphanedUpdates(provider: provider).makeAsyncIterator()
    _expectTrue(provider.watchWasStarted)
    _expectTrue(provider.watchWasStopped, "Releasing the manager stops the provider watch")
    let next = try await iterator.next()
    _expectNil(next)
  }

  private func makeOrphanedUpdates(provider: ContractLocationProvider) -> AsyncThrowingStream<CLLocation, Error> {
    let manager = CLLocationManager(provider: provider)
    return manager.locationUpdates()
  }

  private func expectLocationError(_ expected: CLError, from manager: CLLocationManager) async {
    do {
      _ = try await manager.location()
      _fail("Expected \(expected)")
    } catch let error as CLError {
      _expectEqual(error, expected)
    } catch {
      _fail("Unexpected error: \(error)")
    }
  }
}

/// Reaches the deprecated class-level status through a protocol witness so the
/// test does not opt into deprecation warnings.
private protocol LegacyAuthorizationStatusSource {
  static func authorizationStatus() -> CLAuthorizationStatus
}

extension CLLocationManager: LegacyAuthorizationStatusSource {}

private final class SilentLocationDelegate: CLLocationManagerDelegate {}

private final class ContractLocationDelegate: CLLocationManagerDelegate {
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

private final class AuthorizationOnlyLocationDelegate: CLLocationManagerDelegate {
  var statuses: [CLAuthorizationStatus] = []

  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    statuses.append(status)
  }
}

private final class ContractLocationProvider: _CLLocationProvider {
  var authorizationStatus: CLAuthorizationStatus
  var isLocationServicesEnabled = true
  var availabilityError: CLError?
  var authorizationRequests = 0
  var watchWasStarted = false
  var watchWasStopped = false
  var oneShotRequests = 0
  var oneShotAccuracy: CLLocationAccuracy?
  var oneShotTimeout: Double?

  private var authorizationCompletion: (@Sendable (Result<CLAuthorizationStatus, CLError>) -> Void)?
  private var watchLocation: (@Sendable (CLLocation) -> Void)?
  private var watchError: (@Sendable (CLError) -> Void)?
  private var oneShotLocation: (@Sendable (CLLocation) -> Void)?
  private var oneShotError: (@Sendable (CLError) -> Void)?

  init(status: CLAuthorizationStatus) { authorizationStatus = status }

  func requestAuthorization(
    _ completion: @escaping @Sendable (Result<CLAuthorizationStatus, CLError>) -> Void
  ) {
    authorizationRequests += 1
    authorizationCompletion = completion
  }

  func startUpdatingLocation(
    desiredAccuracy: CLLocationAccuracy,
    distanceFilter: CLLocationDistance,
    onLocation: @escaping @Sendable (CLLocation) -> Void,
    onError: @escaping @Sendable (CLError) -> Void
  ) {
    _ = (desiredAccuracy, distanceFilter)
    watchWasStarted = true
    watchLocation = onLocation
    watchError = onError
  }

  func requestLocation(
    desiredAccuracy: CLLocationAccuracy,
    timeout: Double,
    onLocation: @escaping @Sendable (CLLocation) -> Void,
    onError: @escaping @Sendable (CLError) -> Void
  ) {
    oneShotRequests += 1
    oneShotAccuracy = desiredAccuracy
    oneShotTimeout = timeout
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

@MainActor private func waitFor(_ predicate: () -> Bool) async {
  for _ in 0..<200 {
    if predicate() { return }
    await Task.yield()
    try? await Task.sleep(nanoseconds: 1_000_000)
  }
}
