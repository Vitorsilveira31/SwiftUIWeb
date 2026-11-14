/// Lightweight, opt-in allocation telemetry for the SwiftUIWeb runtime.
///
/// Swift does not expose a portable way to ask the WASM allocator how many
/// bytes a class instance or ARC retain costs.  Interposing malloc would also
/// make the browser, WASI and Embedded builds disagree.  The renderer therefore
/// records object lifetimes and *estimated* payload bytes at the framework
/// ownership boundaries.  This is intentionally SPI-only and disabled by
/// default, so production applications pay one predictable branch per
/// instrumented object rather than carrying a tracing allocator.
@_spi(Renderer) public struct _RuntimeMemorySnapshot: Equatable, Sendable {
  public let enabled: Bool

  public let renderNodeAllocations: Int
  public let renderNodeDeallocations: Int
  public let renderNodeLive: Int
  public let peakRenderNodeLive: Int
  public let estimatedRenderNodeBytes: Int
  /// A shape-based lower-bound sample of the currently retained tree. It is
  /// separate from allocation bytes because old mutation snapshots may remain
  /// alive for one commit while the browser consumes them.
  public let retainedRenderNodeBytes: Int
  public let peakRetainedRenderNodeBytes: Int

  public let fiberAllocations: Int
  public let fiberDeallocations: Int
  public let fiberLive: Int
  public let peakFiberLive: Int

  public let bindingCellAllocations: Int
  public let bindingCellReleases: Int
  public let bindingCellLive: Int
  public let peakBindingCellLive: Int

  public let stateStoreAllocations: Int
  public let stateStoreDeallocations: Int
  public let stateBoxAllocations: Int
  public let stateBoxDeallocations: Int
  public let stateStorageAllocations: Int
  public let stateStorageDeallocations: Int
  public let stateSubscriptionAllocations: Int
  public let stateSubscriptionDeallocations: Int
  public let stateStoreEntries: Int
  public let stateStoreSubscribers: Int
  public let stateStoreObservedKeys: Int
  public let stateStoreObservedObjects: Int
  public let dependencyOwnerEdges: Int
  public let environmentEntries: Int
  public let peakEnvironmentEntries: Int

  /// _EventHandler is a value type, but each handler normally owns one or more
  /// escaping closures.  These counters are logical closure registrations,
  /// not a claim about the allocator's closure object size.
  public let eventHandlerRegistrations: Int
  public let taskRegistrations: Int
  public let webSubscriptionAllocations: Int
  public let webSubscriptionDeallocations: Int
  public let webMountsLive: Int

  public let browserHandleSlots: Int
  public let peakBrowserHandleSlots: Int
  public let browserIndexEntries: Int
  public let peakBrowserIndexEntries: Int
  public let scratchBufferBytes: Int
  public let peakScratchBufferBytes: Int

  public let stringValuesObserved: Int
  public let stringBytesObserved: Int

  public init(
    enabled: Bool = false,
    renderNodeAllocations: Int = 0,
    renderNodeDeallocations: Int = 0,
    renderNodeLive: Int = 0,
    peakRenderNodeLive: Int = 0,
    estimatedRenderNodeBytes: Int = 0,
    retainedRenderNodeBytes: Int = 0,
    peakRetainedRenderNodeBytes: Int = 0,
    fiberAllocations: Int = 0,
    fiberDeallocations: Int = 0,
    fiberLive: Int = 0,
    peakFiberLive: Int = 0,
    bindingCellAllocations: Int = 0,
    bindingCellReleases: Int = 0,
    bindingCellLive: Int = 0,
    peakBindingCellLive: Int = 0,
    stateStoreAllocations: Int = 0,
    stateStoreDeallocations: Int = 0,
    stateBoxAllocations: Int = 0,
    stateBoxDeallocations: Int = 0,
    stateStorageAllocations: Int = 0,
    stateStorageDeallocations: Int = 0,
    stateSubscriptionAllocations: Int = 0,
    stateSubscriptionDeallocations: Int = 0,
    stateStoreEntries: Int = 0,
    stateStoreSubscribers: Int = 0,
    stateStoreObservedKeys: Int = 0,
    stateStoreObservedObjects: Int = 0,
    dependencyOwnerEdges: Int = 0,
    environmentEntries: Int = 0,
    peakEnvironmentEntries: Int = 0,
    eventHandlerRegistrations: Int = 0,
    taskRegistrations: Int = 0,
    webSubscriptionAllocations: Int = 0,
    webSubscriptionDeallocations: Int = 0,
    webMountsLive: Int = 0,
    browserHandleSlots: Int = 0,
    peakBrowserHandleSlots: Int = 0,
    browserIndexEntries: Int = 0,
    peakBrowserIndexEntries: Int = 0,
    scratchBufferBytes: Int = 0,
    peakScratchBufferBytes: Int = 0,
    stringValuesObserved: Int = 0,
    stringBytesObserved: Int = 0
  ) {
    self.enabled = enabled
    self.renderNodeAllocations = renderNodeAllocations
    self.renderNodeDeallocations = renderNodeDeallocations
    self.renderNodeLive = renderNodeLive
    self.peakRenderNodeLive = peakRenderNodeLive
    self.estimatedRenderNodeBytes = estimatedRenderNodeBytes
    self.retainedRenderNodeBytes = retainedRenderNodeBytes
    self.peakRetainedRenderNodeBytes = peakRetainedRenderNodeBytes
    self.fiberAllocations = fiberAllocations
    self.fiberDeallocations = fiberDeallocations
    self.fiberLive = fiberLive
    self.peakFiberLive = peakFiberLive
    self.bindingCellAllocations = bindingCellAllocations
    self.bindingCellReleases = bindingCellReleases
    self.bindingCellLive = bindingCellLive
    self.peakBindingCellLive = peakBindingCellLive
    self.stateStoreAllocations = stateStoreAllocations
    self.stateStoreDeallocations = stateStoreDeallocations
    self.stateBoxAllocations = stateBoxAllocations
    self.stateBoxDeallocations = stateBoxDeallocations
    self.stateStorageAllocations = stateStorageAllocations
    self.stateStorageDeallocations = stateStorageDeallocations
    self.stateSubscriptionAllocations = stateSubscriptionAllocations
    self.stateSubscriptionDeallocations = stateSubscriptionDeallocations
    self.stateStoreEntries = stateStoreEntries
    self.stateStoreSubscribers = stateStoreSubscribers
    self.stateStoreObservedKeys = stateStoreObservedKeys
    self.stateStoreObservedObjects = stateStoreObservedObjects
    self.dependencyOwnerEdges = dependencyOwnerEdges
    self.environmentEntries = environmentEntries
    self.peakEnvironmentEntries = peakEnvironmentEntries
    self.eventHandlerRegistrations = eventHandlerRegistrations
    self.taskRegistrations = taskRegistrations
    self.webSubscriptionAllocations = webSubscriptionAllocations
    self.webSubscriptionDeallocations = webSubscriptionDeallocations
    self.webMountsLive = webMountsLive
    self.browserHandleSlots = browserHandleSlots
    self.peakBrowserHandleSlots = peakBrowserHandleSlots
    self.browserIndexEntries = browserIndexEntries
    self.peakBrowserIndexEntries = peakBrowserIndexEntries
    self.scratchBufferBytes = scratchBufferBytes
    self.peakScratchBufferBytes = peakScratchBufferBytes
    self.stringValuesObserved = stringValuesObserved
    self.stringBytesObserved = stringBytesObserved
  }

  public var liveObjectCount: Int {
    renderNodeLive + fiberLive + bindingCellLive
      + max(0, stateStoreAllocations - stateStoreDeallocations)
      + max(0, stateBoxAllocations - stateBoxDeallocations)
      + max(0, stateStorageAllocations - stateStorageDeallocations)
      + max(0, stateSubscriptionAllocations - stateSubscriptionDeallocations)
      + max(0, webSubscriptionAllocations - webSubscriptionDeallocations)
      + webMountsLive
  }

  /// Lower-bound ARC traffic proxy: framework-owned class initialization and
  /// destruction events. Swift's retain/release operations themselves are not
  /// observable portably, so this must not be read as a literal retain count.
  public var estimatedARCEvents: Int {
    renderNodeAllocations + renderNodeDeallocations
      + fiberAllocations + fiberDeallocations
      + bindingCellAllocations + bindingCellReleases
      + stateStoreAllocations + stateStoreDeallocations
      + stateBoxAllocations + stateBoxDeallocations
      + stateStorageAllocations + stateStorageDeallocations
      + stateSubscriptionAllocations + stateSubscriptionDeallocations
      + webSubscriptionAllocations + webSubscriptionDeallocations
  }

  /// A lower-bound estimate for retained framework payload. Dynamic values
  /// (for example a user's string contents or Foundation objects) are not
  /// included unless a host explicitly reports them through the string hooks.
  public var estimatedLiveBytes: Int {
    retainedRenderNodeBytes + browserHandleSlots * MemoryLayout<UInt32>.stride * 2
      + browserIndexEntries * 32
      + scratchBufferBytes + stateStoreEntries * 32 + dependencyOwnerEdges * 16
      + environmentEntries * 24
  }
}

@_spi(Renderer) public enum _RuntimeMemoryMetrics {
  static var counters: _RuntimeMemoryCounters { _RenderThreadState.current.memoryCounters }

  public static var isEnabled: Bool { counters.isEnabled }

  public static func start() { counters.start() }
  public static func stop() { counters.stop() }
  public static func reset() { counters.reset() }
  public static func snapshot() -> _RuntimeMemorySnapshot { counters.snapshot() }
  public static func recordRenderNodeInit(estimatedBytes: Int = 192) { counters.recordRenderNodeInit(estimatedBytes: estimatedBytes) }
  public static func recordRenderNodeDeinit(estimatedBytes: Int = 192) { counters.recordRenderNodeDeinit(estimatedBytes: estimatedBytes) }
  public static func recordFiberInit() { counters.recordFiberInit() }
  public static func recordFiberDeinit() { counters.recordFiberDeinit() }
  public static func recordRetainedRenderNodeBytes(_ bytes: Int) { counters.recordRetainedRenderNodeBytes(bytes) }
  public static func recordBindingCellInit() { counters.recordBindingCellInit() }
  public static func recordBindingCellRelease() { counters.recordBindingCellRelease() }
  public static func recordStateStoreInit() { counters.recordStateStoreInit() }
  public static func recordStateStoreDeinit() { counters.recordStateStoreDeinit() }
  public static func recordStateBoxInit() { counters.recordStateBoxInit() }
  public static func recordStateBoxDeinit() { counters.recordStateBoxDeinit() }
  public static func recordStateStorageInit() { counters.recordStateStorageInit() }
  public static func recordStateStorageDeinit() { counters.recordStateStorageDeinit() }
  public static func recordStateSubscriptionInit() { counters.recordStateSubscriptionInit() }
  public static func recordStateSubscriptionDeinit() { counters.recordStateSubscriptionDeinit() }
  public static func recordStateStoreShape(entries: Int, subscribers: Int, observedKeys: Int, observedObjects: Int, dependencyOwnerEdges: Int) { counters.recordStateStoreShape(entries: entries, subscribers: subscribers, observedKeys: observedKeys, observedObjects: observedObjects, dependencyOwnerEdges: dependencyOwnerEdges) }
  public static func clearStateStoreShape() { counters.clearStateStoreShape() }
  public static func recordEnvironmentEntries(_ count: Int) { counters.recordEnvironmentEntries(count) }
  public static func recordEventHandler() { counters.recordEventHandler() }
  public static func recordTaskRegistration() { counters.recordTaskRegistration() }
  public static func recordWebSubscriptionInit() { counters.recordWebSubscriptionInit() }
  public static func recordWebSubscriptionDeinit() { counters.recordWebSubscriptionDeinit() }
  public static func recordWebMounts(_ count: Int) { counters.recordWebMounts(count) }
  public static func recordBrowserHandleSlots(_ count: Int) { counters.recordBrowserHandleSlots(count) }
  public static func clearBrowserHandleSlots() { counters.clearBrowserHandleSlots() }
  public static func recordBrowserIndexEntries(_ count: Int) { counters.recordBrowserIndexEntries(count) }
  public static func clearBrowserIndexEntries() { counters.clearBrowserIndexEntries() }
  public static func recordScratchBuffer(bytes: Int) { counters.recordScratchBuffer(bytes: bytes) }
  public static func clearScratchBuffer() { counters.clearScratchBuffer() }
  public static func observeString(_ value: String) { counters.observeString(value) }
}

/// Counter storage for `_RuntimeMemoryMetrics`. The browser runtime is
/// single-threaded and uses one instance; native hosts keep one instance per
/// thread (see `_RenderThreadState`) so concurrently evaluated view graphs,
/// for example parallel tests, never pollute each other's measurements.
final class _RuntimeMemoryCounters {
  var isEnabled = false

  var renderNodeAllocations = 0
  var renderNodeDeallocations = 0
  var renderNodeLive = 0
  var peakRenderNodeLive = 0
  var estimatedRenderNodeBytes = 0
  var retainedRenderNodeBytes = 0
  var peakRetainedRenderNodeBytes = 0

  var fiberAllocations = 0
  var fiberDeallocations = 0
  var fiberLive = 0
  var peakFiberLive = 0

  var bindingCellAllocations = 0
  var bindingCellReleases = 0
  var bindingCellLive = 0
  var peakBindingCellLive = 0

  var stateStoreAllocations = 0
  var stateStoreDeallocations = 0
  var stateBoxAllocations = 0
  var stateBoxDeallocations = 0
  var stateStorageAllocations = 0
  var stateStorageDeallocations = 0
  var stateSubscriptionAllocations = 0
  var stateSubscriptionDeallocations = 0
  var stateStoreEntries = 0
  var stateStoreSubscribers = 0
  var stateStoreObservedKeys = 0
  var stateStoreObservedObjects = 0
  var dependencyOwnerEdges = 0
  var environmentEntries = 0
  var peakEnvironmentEntries = 0

  var eventHandlerRegistrations = 0
  var taskRegistrations = 0
  var webSubscriptionAllocations = 0
  var webSubscriptionDeallocations = 0
  var webMountsLive = 0

  var browserHandleSlots = 0
  var peakBrowserHandleSlots = 0
  var browserIndexEntries = 0
  var peakBrowserIndexEntries = 0
  var scratchBufferBytes = 0
  var peakScratchBufferBytes = 0
  var stringValuesObserved = 0
  var stringBytesObserved = 0

  func start() {
    reset()
    isEnabled = true
  }

  func stop() {
    isEnabled = false
  }

  func reset() {
    renderNodeAllocations = 0; renderNodeDeallocations = 0; renderNodeLive = 0
    peakRenderNodeLive = 0; estimatedRenderNodeBytes = 0
    retainedRenderNodeBytes = 0; peakRetainedRenderNodeBytes = 0
    fiberAllocations = 0; fiberDeallocations = 0; fiberLive = 0; peakFiberLive = 0
    bindingCellAllocations = 0; bindingCellReleases = 0; bindingCellLive = 0; peakBindingCellLive = 0
    stateStoreAllocations = 0; stateStoreDeallocations = 0
    stateBoxAllocations = 0; stateBoxDeallocations = 0
    stateStorageAllocations = 0; stateStorageDeallocations = 0
    stateSubscriptionAllocations = 0; stateSubscriptionDeallocations = 0
    stateStoreEntries = 0; stateStoreSubscribers = 0
    stateStoreObservedKeys = 0; stateStoreObservedObjects = 0; dependencyOwnerEdges = 0
    environmentEntries = 0; peakEnvironmentEntries = 0
    eventHandlerRegistrations = 0; taskRegistrations = 0
    webSubscriptionAllocations = 0; webSubscriptionDeallocations = 0; webMountsLive = 0
    browserHandleSlots = 0; peakBrowserHandleSlots = 0
    browserIndexEntries = 0; peakBrowserIndexEntries = 0
    scratchBufferBytes = 0; peakScratchBufferBytes = 0
    stringValuesObserved = 0; stringBytesObserved = 0
  }

  func snapshot() -> _RuntimeMemorySnapshot {
    _RuntimeMemorySnapshot(
      enabled: isEnabled,
      renderNodeAllocations: renderNodeAllocations,
      renderNodeDeallocations: renderNodeDeallocations,
      renderNodeLive: renderNodeLive,
      peakRenderNodeLive: peakRenderNodeLive,
      estimatedRenderNodeBytes: estimatedRenderNodeBytes,
      retainedRenderNodeBytes: retainedRenderNodeBytes,
      peakRetainedRenderNodeBytes: peakRetainedRenderNodeBytes,
      fiberAllocations: fiberAllocations,
      fiberDeallocations: fiberDeallocations,
      fiberLive: fiberLive,
      peakFiberLive: peakFiberLive,
      bindingCellAllocations: bindingCellAllocations,
      bindingCellReleases: bindingCellReleases,
      bindingCellLive: bindingCellLive,
      peakBindingCellLive: peakBindingCellLive,
      stateStoreAllocations: stateStoreAllocations,
      stateStoreDeallocations: stateStoreDeallocations,
      stateBoxAllocations: stateBoxAllocations,
      stateBoxDeallocations: stateBoxDeallocations,
      stateStorageAllocations: stateStorageAllocations,
      stateStorageDeallocations: stateStorageDeallocations,
      stateSubscriptionAllocations: stateSubscriptionAllocations,
      stateSubscriptionDeallocations: stateSubscriptionDeallocations,
      stateStoreEntries: stateStoreEntries,
      stateStoreSubscribers: stateStoreSubscribers,
      stateStoreObservedKeys: stateStoreObservedKeys,
      stateStoreObservedObjects: stateStoreObservedObjects,
      dependencyOwnerEdges: dependencyOwnerEdges,
      environmentEntries: environmentEntries,
      peakEnvironmentEntries: peakEnvironmentEntries,
      eventHandlerRegistrations: eventHandlerRegistrations,
      taskRegistrations: taskRegistrations,
      webSubscriptionAllocations: webSubscriptionAllocations,
      webSubscriptionDeallocations: webSubscriptionDeallocations,
      webMountsLive: webMountsLive,
      browserHandleSlots: browserHandleSlots,
      peakBrowserHandleSlots: peakBrowserHandleSlots,
      browserIndexEntries: browserIndexEntries,
      peakBrowserIndexEntries: peakBrowserIndexEntries,
      scratchBufferBytes: scratchBufferBytes,
      peakScratchBufferBytes: peakScratchBufferBytes,
      stringValuesObserved: stringValuesObserved,
      stringBytesObserved: stringBytesObserved
    )
  }

  @inline(__always) func recordRenderNodeInit(estimatedBytes: Int = 192) {
    guard isEnabled else { return }
    renderNodeAllocations += 1; renderNodeLive += 1
    estimatedRenderNodeBytes += max(0, estimatedBytes)
    peakRenderNodeLive = max(peakRenderNodeLive, renderNodeLive)
  }

  @inline(__always) func recordRenderNodeDeinit(estimatedBytes: Int = 192) {
    guard isEnabled else { return }
    renderNodeDeallocations += 1; renderNodeLive = max(0, renderNodeLive - 1)
    estimatedRenderNodeBytes = max(0, estimatedRenderNodeBytes - max(0, estimatedBytes))
  }

  @inline(__always) func recordFiberInit() {
    guard isEnabled else { return }
    fiberAllocations += 1; fiberLive += 1; peakFiberLive = max(peakFiberLive, fiberLive)
  }

  @inline(__always) func recordFiberDeinit() {
    guard isEnabled else { return }
    fiberDeallocations += 1; fiberLive = max(0, fiberLive - 1)
  }

  /// Records a shape-based retained-tree estimate supplied by FiberTree. This
  /// is intentionally called only when instrumentation is enabled because it
  /// walks the retained graph and is diagnostic work, not a production path.
  func recordRetainedRenderNodeBytes(_ bytes: Int) {
    guard isEnabled else { return }
    retainedRenderNodeBytes = max(0, bytes)
    peakRetainedRenderNodeBytes = max(peakRetainedRenderNodeBytes, retainedRenderNodeBytes)
  }

  @inline(__always) func recordBindingCellInit() {
    guard isEnabled else { return }
    bindingCellAllocations += 1; bindingCellLive += 1; peakBindingCellLive = max(peakBindingCellLive, bindingCellLive)
  }

  @inline(__always) func recordBindingCellRelease() {
    guard isEnabled else { return }
    bindingCellReleases += 1; bindingCellLive = max(0, bindingCellLive - 1)
  }

  @inline(__always) func recordStateStoreInit() { if isEnabled { stateStoreAllocations += 1 } }
  @inline(__always) func recordStateStoreDeinit() { if isEnabled { stateStoreDeallocations += 1 } }
  @inline(__always) func recordStateBoxInit() { if isEnabled { stateBoxAllocations += 1 } }
  @inline(__always) func recordStateBoxDeinit() { if isEnabled { stateBoxDeallocations += 1 } }
  @inline(__always) func recordStateStorageInit() { if isEnabled { stateStorageAllocations += 1 } }
  @inline(__always) func recordStateStorageDeinit() { if isEnabled { stateStorageDeallocations += 1 } }
  @inline(__always) func recordStateSubscriptionInit() { if isEnabled { stateSubscriptionAllocations += 1 } }
  @inline(__always) func recordStateSubscriptionDeinit() { if isEnabled { stateSubscriptionDeallocations += 1 } }
  @inline(__always) func recordStateStoreShape(entries: Int, subscribers: Int, observedKeys: Int, observedObjects: Int, dependencyOwnerEdges: Int) {
    guard isEnabled else { return }
    stateStoreEntries = max(0, entries)
    stateStoreSubscribers = max(0, subscribers)
    stateStoreObservedKeys = max(0, observedKeys)
    stateStoreObservedObjects = max(0, observedObjects)
    self.dependencyOwnerEdges = max(0, dependencyOwnerEdges)
  }
  @inline(__always) func clearStateStoreShape() {
    if isEnabled {
      stateStoreEntries = 0; stateStoreSubscribers = 0
      stateStoreObservedKeys = 0; stateStoreObservedObjects = 0; dependencyOwnerEdges = 0
    }
  }
  @inline(__always) func recordEnvironmentEntries(_ count: Int) {
    guard isEnabled else { return }
    environmentEntries = max(0, count)
    peakEnvironmentEntries = max(peakEnvironmentEntries, environmentEntries)
  }
  @inline(__always) func recordEventHandler() { if isEnabled { eventHandlerRegistrations += 1 } }
  @inline(__always) func recordTaskRegistration() { if isEnabled { taskRegistrations += 1 } }

  @inline(__always) func recordWebSubscriptionInit() { if isEnabled { webSubscriptionAllocations += 1 } }
  @inline(__always) func recordWebSubscriptionDeinit() { if isEnabled { webSubscriptionDeallocations += 1 } }
  @inline(__always) func recordWebMounts(_ count: Int) { if isEnabled { webMountsLive = max(0, count) } }
  @inline(__always) func recordBrowserHandleSlots(_ count: Int) {
    guard isEnabled else { return }
    browserHandleSlots = max(0, count); peakBrowserHandleSlots = max(peakBrowserHandleSlots, browserHandleSlots)
  }
  @inline(__always) func clearBrowserHandleSlots() {
    if isEnabled { browserHandleSlots = 0 }
  }
  @inline(__always) func recordBrowserIndexEntries(_ count: Int) {
    guard isEnabled else { return }
    browserIndexEntries = max(0, count)
    peakBrowserIndexEntries = max(peakBrowserIndexEntries, browserIndexEntries)
  }
  @inline(__always) func clearBrowserIndexEntries() {
    if isEnabled { browserIndexEntries = 0 }
  }
  @inline(__always) func recordScratchBuffer(bytes: Int) {
    guard isEnabled else { return }
    scratchBufferBytes = max(0, bytes)
    peakScratchBufferBytes = max(peakScratchBufferBytes, scratchBufferBytes)
  }
  @inline(__always) func clearScratchBuffer() {
    if isEnabled { scratchBufferBytes = 0 }
  }
  @inline(__always) func observeString(_ value: String) {
    guard isEnabled else { return }
    // Wrapping: these only count, and Int is 32 bits in the browser build.
    stringValuesObserved &+= 1; stringBytesObserved &+= value.utf8.count
  }
}
