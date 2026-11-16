import SwiftUIWeb

/// Browser resource categories understood by the private prefetch planner.
/// These values are SPI-only: normal SwiftUI application code never needs to
/// name a browser asset or a JavaScript module.
@_spi(Browser)
public enum _WebPrefetchKind: UInt8, Hashable, Sendable {
  case module = 0
  case script = 1
  case stylesheet = 2
  case image = 3
  case font = 4
  case worker = 5
  case data = 6
  case route = 7
  case media = 8
}

/// A prefetch is deliberately described by intent instead of by an
/// imperative browser operation.  This lets the host choose `<link
/// rel="prefetch">`, `modulepreload`, or another low-priority mechanism while
/// keeping package code independent of JavaScript interop.
@_spi(Browser)
public enum _WebPrefetchTrigger: Hashable, Sendable {
  /// A small, explicitly registered resource may be warmed after first paint
  /// when the browser has idle time.
  case idle
  /// A route/feature resource is eligible only after navigation intent is
  /// observed (pointer hover, keyboard focus, or an equivalent host signal).
  case route(String)
  /// A resource is eligible when a semantic host enters the viewport
  /// proximity window. The optional scope lets a package distinguish map,
  /// video, or another feature family.
  case viewport(String?)
}

@_spi(Browser)
public struct _WebPrefetchResource: Hashable, Sendable {
  public let url: String
  public let kind: _WebPrefetchKind
  public let trigger: _WebPrefetchTrigger
  public let priority: UInt8
  /// Cross-origin hints are opt-in. Image/map providers can explicitly allow
  /// them, while route and package resources default to same-origin behavior.
  public let allowCrossOrigin: Bool

  public init(
    url: String,
    kind: _WebPrefetchKind,
    trigger: _WebPrefetchTrigger = .idle,
    priority: UInt8 = 100,
    allowCrossOrigin: Bool = false
  ) {
    self.url = url
    self.kind = kind
    self.trigger = trigger
    self.priority = priority
    self.allowCrossOrigin = allowCrossOrigin
  }

  /// The browser cache key intentionally excludes the trigger. A resource
  /// registered both for a route and for a viewport is still fetched once.
  @_spi(Browser)
  public var _cacheKey: String { "\(kind.rawValue):" + _framedPrefetchKeyPart(url) }
}

/// A key part framed by its UTF-8 length, so a URL or route that contains `|` cannot alias another key.
private func _framedPrefetchKeyPart(_ value: String) -> String {
  String(value.utf8.count) + ":" + value
}

/// Host policy is intentionally conservative. It is not exposed through the
/// normal SwiftUI API and can be tuned by a browser host or test harness.
@_spi(Browser)
public struct _WebPrefetchPolicy: Hashable, Sendable {
  public var enabled: Bool
  public var maxIdleResourcesPerDrain: Int
  public var maxIntentResourcesPerDrain: Int
  public var maxViewportResourcesPerDrain: Int
  public var maxTotalResources: Int

  public init(
    enabled: Bool = true,
    maxIdleResourcesPerDrain: Int = 2,
    maxIntentResourcesPerDrain: Int = 4,
    maxViewportResourcesPerDrain: Int = 4,
    maxTotalResources: Int = 32
  ) {
    self.enabled = enabled
    self.maxIdleResourcesPerDrain = max(0, maxIdleResourcesPerDrain)
    self.maxIntentResourcesPerDrain = max(0, maxIntentResourcesPerDrain)
    self.maxViewportResourcesPerDrain = max(0, maxViewportResourcesPerDrain)
    self.maxTotalResources = max(0, maxTotalResources)
  }
}

@_spi(Browser)
public struct _WebPrefetchMetrics: Equatable, Sendable {
  public fileprivate(set) var registrations = 0
  public fileprivate(set) var deduplicatedRegistrations = 0
  public fileprivate(set) var idleBatches = 0
  public fileprivate(set) var intentBatches = 0
  public fileprivate(set) var viewportBatches = 0
  public fileprivate(set) var dispatched = 0
  public fileprivate(set) var skippedConstrainedNetwork = 0
  public fileprivate(set) var skippedHiddenPage = 0
  public fileprivate(set) var skippedBudget = 0

  public init() {}
}

/// Lifetime token for a wrapper-owned prefetch registration. This is separate
/// from `WebSubscription` so a package that only imports the Browser SPI does
/// not need to depend on the WebMount SPI merely to remove a manifest entry.
@_spi(Browser)
public final class _WebPrefetchRegistration {
  private var cancellation: (() -> Void)?

  fileprivate init(_ cancellation: @escaping () -> Void) {
    self.cancellation = cancellation
  }

  public func cancel() {
    guard let cancellation else { return }
    self.cancellation = nil
    cancellation()
  }

  deinit { cancel() }
}

/// A compact, browser-neutral planner. Keeping this separate from the DOM
/// coordinator makes policy and deduplication testable on native hosts and
/// avoids pulling JavaScript interop into Core/Fiber or into package wrappers.
@_spi(Browser)
public final class _WebPrefetchPlanner {
  private struct Entry {
    var resource: _WebPrefetchResource
    let order: UInt64
  }

  public private(set) var policy: _WebPrefetchPolicy
  public private(set) var metrics = _WebPrefetchMetrics()
  private var entries: [String: Entry] = .init()
  private var dispatchedKeys: Set<String> = []
  private var nextOrder: UInt64 = 0

  public init(policy: _WebPrefetchPolicy = _WebPrefetchPolicy()) {
    self.policy = policy
  }

  public func update(policy: _WebPrefetchPolicy) {
    self.policy = policy
  }

  /// Registering the same URL/category repeatedly is cheap and does not grow
  /// the queue. A later registration may raise priority (lower numeric value)
  /// or opt into cross-origin loading, but cannot make an idle resource more
  /// eager than the trigger supplied by its owner.
  public func register(_ resource: _WebPrefetchResource) {
    guard !resource.url.isEmpty else { return }
    metrics.registrations += 1
    let key = _framedPrefetchKeyPart(resource._cacheKey) + _framedPrefetchKeyPart(triggerKey(resource.trigger))
    if let existing = entries[key] {
      metrics.deduplicatedRegistrations += 1
      let merged = _WebPrefetchResource(
        url: resource.url,
        kind: resource.kind,
        trigger: resource.trigger,
        priority: min(existing.resource.priority, resource.priority),
        allowCrossOrigin: existing.resource.allowCrossOrigin || resource.allowCrossOrigin
      )
      entries[key] = Entry(resource: merged, order: existing.order)
      return
    }
    nextOrder &+= 1
    entries[key] = Entry(resource: resource, order: nextOrder)
    pruneResolvedEntriesIfNeeded()
  }

  public func register<S: Sequence>(_ resources: S) where S.Element == _WebPrefetchResource {
    for resource in resources { register(resource) }
  }

  public func markDispatched(_ resource: _WebPrefetchResource) {
    dispatchedKeys.insert(resource._cacheKey)
  }

  public func isDispatched(_ resource: _WebPrefetchResource) -> Bool {
    dispatchedKeys.contains(resource._cacheKey)
  }

  public var hasPendingResources: Bool {
    entries.values.contains { !dispatchedKeys.contains($0.resource._cacheKey) }
  }

  /// Pending resources that are safe to drain without an explicit route or
  /// viewport trigger. Hosts use this to avoid spinning an idle callback for
  /// every registered route/viewport entry before its trigger occurs.
  public var hasPendingIdleResources: Bool {
    entries.values.contains {
      if case .idle = $0.resource.trigger {
        return !dispatchedKeys.contains($0.resource._cacheKey)
      }
      return false
    }
  }

  /// Returns the next bounded batch ordered by explicit priority and then by
  /// registration order. The planner never marks entries dispatched itself;
  /// the browser coordinator does so only after a link has been appended.
  public func idleBatch(limit: Int? = nil) -> [_WebPrefetchResource] {
    metrics.idleBatches += 1
    return batch(matching: { trigger in
      if case .idle = trigger { return true }
      return false
    }, limit: limit ?? policy.maxIdleResourcesPerDrain)
  }

  public func intentBatch(route: String, limit: Int? = nil) -> [_WebPrefetchResource] {
    metrics.intentBatches += 1
    let normalized = Self.normalizeRoute(route)
    return batch(matching: { trigger in
      guard case .route(let expected) = trigger else { return false }
      return Self.normalizeRoute(expected) == normalized
    }, limit: limit ?? policy.maxIntentResourcesPerDrain)
  }

  public func viewportBatch(scope: String?, limit: Int? = nil) -> [_WebPrefetchResource] {
    metrics.viewportBatches += 1
    return batch(matching: { trigger in
      guard case .viewport(let expected) = trigger else { return false }
      return expected == nil || expected == scope
    }, limit: limit ?? policy.maxViewportResourcesPerDrain)
  }

  /// Clears only the dispatch history. This is useful for a host that replaces
  /// its document (for example a test harness) while retaining registrations.
  public func resetDispatchHistory() {
    dispatchedKeys.removeAll(keepingCapacity: true)
  }

  private func batch(
    matching predicate: (_WebPrefetchTrigger) -> Bool,
    limit: Int
  ) -> [_WebPrefetchResource] {
    guard policy.enabled, limit > 0 else { return [] }
    let sorted = entries.values
      .filter { predicate($0.resource.trigger) && !dispatchedKeys.contains($0.resource._cacheKey) }
      .sorted {
        if $0.resource.priority != $1.resource.priority {
          return $0.resource.priority < $1.resource.priority
        }
        return $0.order < $1.order
      }
    if sorted.count > limit {
      metrics.skippedBudget += sorted.count - limit
    }
    return sorted.prefix(limit).map { item in item.resource }
  }

  private func triggerKey(_ trigger: _WebPrefetchTrigger) -> String {
    switch trigger {
    case .idle: return "idle"
    case .route(let route): return "route:" + Self.normalizeRoute(route)
    case .viewport(let scope): return "viewport:" + (scope ?? "*")
    }
  }

  private func pruneResolvedEntriesIfNeeded() {
    // Viewport discovery can encounter a fresh image URL on every scroll. Do
    // not retain an unbounded manifest just to remember resources that were
    // already hinted; the compact dispatched-key set is enough for that.
    let cap = max(64, policy.maxTotalResources * 4)
    guard entries.count > cap else { return }
    let resolvedKeys = entries.compactMap { key, entry in
      dispatchedKeys.contains(entry.resource._cacheKey) ? key : nil
    }
    for key in resolvedKeys {
      entries.removeValue(forKey: key)
      if entries.count <= cap { break }
    }
  }

  private static func normalizeRoute(_ value: String) -> String {
    var route = value.split(separator: "#", maxSplits: 1).first.map(String.init) ?? value
    while route.count > 1 && route.hasSuffix("/") { route.removeLast() }
    return route
  }
}

/// Feature wrappers may register a small resource manifest through SPI. The
/// registration is intentionally declarative: package code does not create
/// links, fetch data, or retain DOM objects. A host may consume these entries
/// when a route or feature receives intent.
@_spi(Browser)
@MainActor public enum WebPrefetchRuntime {
  private static var resources: [String: _WebPrefetchResource] = .init()
  private static var registrationIDs: [String: UInt64] = .init()
  private static var generation: UInt64 = 0
  private static var nextRegistrationID: UInt64 = 0
  /// The most manifest entries kept. Past it a new registration is not added (a prefetch is only a hint), so data cannot
  /// grow the table forever and no live route or viewport loses the prefetch it registered.
  private static let maxResources = 512

  @discardableResult
  public static func register(_ resource: _WebPrefetchResource) -> _WebPrefetchRegistration {
    let triggerKey: String
    switch resource.trigger {
    case .idle: triggerKey = "idle"
    case .route(let route): triggerKey = "route:" + route
    case .viewport(let scope): triggerKey = "viewport:" + (scope ?? "*")
    }
    let key = _framedPrefetchKeyPart(resource._cacheKey) + _framedPrefetchKeyPart(triggerKey)
    if resources[key] == nil, resources.count >= maxResources { return _WebPrefetchRegistration {} }
    resources[key] = resource
    nextRegistrationID &+= 1
    let registrationID = nextRegistrationID
    registrationIDs[key] = registrationID
    generation &+= 1
    return _WebPrefetchRegistration {
      // A later registration for the same manifest key supersedes an older
      // token. A stale token must never cancel the newer resource.
      guard registrationIDs[key] == registrationID else { return }
      registrationIDs.removeValue(forKey: key)
      if resources.removeValue(forKey: key) != nil { generation &+= 1 }
    }
  }

  public static func register<S: Sequence>(_ resources: S) -> _WebPrefetchRegistration where S.Element == _WebPrefetchResource {
    let tokens = resources.map(register)
    return _WebPrefetchRegistration { tokens.forEach { $0.cancel() } }
  }

  @_spi(Browser)
  public static func _registeredResources() -> [_WebPrefetchResource] {
    Array(resources.values)
  }

  @_spi(Browser)
  public static var _registrationGeneration: UInt64 { generation }
}

