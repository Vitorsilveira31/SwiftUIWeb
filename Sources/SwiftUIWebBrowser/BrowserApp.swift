import SwiftUIWeb
import CSwiftUIWebBrowserIO
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Browser) @_spi(Generated) import SwiftUIWebCore
@_spi(Browser) @_spi(Generated) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebFiber
#if !SWIFTUIWEB_RELEASE || SWIFTUIWEB_RELEASE_HAS_PHOTOS
@_spi(Browser) import SwiftUIWebPhotosUI
#endif
@_spi(Browser) @_spi(Renderer) import SwiftUIWebTransferable
@_spi(Browser) import SwiftUIWebInternationalization

#if arch(wasm32) && hasFeature(Embedded)
import SwiftUIWebBrowserIO
@_spi(ExperimentalCustomExecutors) import _Concurrency

/// Embedded Swift has the concurrency runtime, but it deliberately does not
/// create a thread-backed global executor. Browser work must therefore run on
/// the browser's event loop. The JavaScript host calls `drain()` after launch
/// and whenever a BrowserIO operation delivers a response.
private final class _EmbeddedBrowserExecutor: @unchecked Sendable, MainExecutor, TaskExecutor {
  static let shared = _EmbeddedBrowserExecutor()

  // The browser runs one thread on one event loop, so whatever code reaches the runtime is on the main actor. The runtime
  // asks the executor itself (these two witnesses) whether the caller is isolated to it, and the default answers "no" and
  // traps; the C hooks installed below are a different path. This is what lets `MainActor.assumeIsolated` work inside
  // the callbacks an app hands to AVFoundation, Foundation and the like, as it does on Apple's platforms.
  func isIsolatingCurrentContext() -> Bool? { true }
  func checkIsolated() {}

  private var jobs: [UnownedJob] = []
  private var draining = false
  private var wakeRequested = false

  /// Embedded Swift omits ExecutorImpl.swift, so ExecutorFactory does not
  /// install the global/main queues. These ABI hooks are the supported bridge
  /// used by the JavaScript host as well; the host only needs to call `drain()`.
  static func installLegacyHooks() {
    typealias GlobalHook = @convention(thin) (UnownedJob, UnsafeMutableRawPointer?) -> Void
    typealias GlobalDelayHook = @convention(thin) (UInt64, UnownedJob, UnsafeMutableRawPointer?) -> Void
    typealias MainHook = @convention(thin) (UnownedJob, UnsafeMutableRawPointer?) -> Void

    let global: GlobalHook = { job, _ in
      _EmbeddedBrowserExecutor.shared.enqueue(job)
    }
    let delayed: GlobalDelayHook = { _, job, _ in
      _EmbeddedBrowserExecutor.shared.enqueue(job)
    }
    let main: MainHook = { job, _ in
      _EmbeddedBrowserExecutor.shared.enqueue(job)
    }

    typealias MainGetter = @convention(thin) (UnsafeMutableRawPointer?) -> UnownedSerialExecutor
    let mainExecutor: MainGetter = { _ in _EmbeddedBrowserExecutor.shared.asUnownedSerialExecutor() }
    // The browser runs one thread on one event loop, so the code that reaches the runtime
    // is always on the main actor: executor checks (MainActor.assumeIsolated) pass.
    typealias CheckIsolated = @convention(thin) (UnownedSerialExecutor, UnsafeMutableRawPointer?) -> Void
    typealias IsIsolating = @convention(thin) (UnownedSerialExecutor, UnsafeMutableRawPointer?) -> Bool
    typealias IsOnExecutor = @convention(thin) (UnsafeMutableRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Bool
    typealias IsMainExecutor = @convention(thin) (UnownedSerialExecutor, UnsafeMutableRawPointer?) -> Bool
    let checkIsolated: CheckIsolated = { _, _ in }
    let isIsolating: IsIsolating = { _, _ in true }
    // `MainActor.assumeIsolated` asks the runtime whether the caller is on the executor, and the runtime answers from the
    // job it is running; an event handler or a callback called from the host runs outside any job, so it said no and
    // trapped. There is one thread and one event loop: every caller is on the main executor.
    let isOnExecutor: IsOnExecutor = { _, _, _, _ in true }
    let isMainExecutor: IsMainExecutor = { _, _ in true }
    _swiftUIWebInstallMainExecutorGetter(
      unsafeBitCast(mainExecutor, to: UnsafeMutableRawPointer?.self),
      checkIsolated: unsafeBitCast(checkIsolated, to: UnsafeMutableRawPointer?.self),
      isIsolating: unsafeBitCast(isIsolating, to: UnsafeMutableRawPointer?.self),
      isOnExecutor: unsafeBitCast(isOnExecutor, to: UnsafeMutableRawPointer?.self),
      isMainExecutor: unsafeBitCast(isMainExecutor, to: UnsafeMutableRawPointer?.self)
    )
    _swiftUIWebInstallConcurrencyHooks(
      unsafeBitCast(global, to: UnsafeMutableRawPointer?.self),
      unsafeBitCast(delayed, to: UnsafeMutableRawPointer?.self),
      unsafeBitCast(main, to: UnsafeMutableRawPointer?.self)
    )
  }

  func enqueue(_ job: UnownedJob) {
    jobs.append(job)
    // A job queued outside a drain (a continuation resumed by a host callback that did not go through
    // BrowserIO) would wait for the host's safety-net timer. Ask the host to drain on its next microtask,
    // once per burst: the drain in progress picks up whatever is queued while it runs.
    if !draining && !wakeRequested {
      wakeRequested = true
      browser_io_wake_executor()
    }
  }

  func run() throws {
    _ = drain()
  }

  func stop() {}

  func drain() -> UInt32 {
    // A job can call into the host, and the host back into `drain()`. The inner call must not walk the
    // queue again: it would rerun the job that is still in progress. The outer loop reaches anything new.
    guard !draining else { return 0 }
    wakeRequested = false
    draining = true
    defer { draining = false }
    var ran: UInt32 = 0
    // Walk the queue by index (removeFirst() moves every remaining job each time) and clear it in one
    // step; jobs queued while one runs are appended and reached by the same loop. A long chain is
    // trimmed now and then so the array does not hold finished jobs.
    var next = 0
    while next < jobs.count {
      let job = jobs[next]
      next += 1
      job.runSynchronously(on: asUnownedSerialExecutor())
      ran &+= 1
      if next >= 4096 {
        jobs.removeFirst(next)
        next = 0
      }
    }
    jobs.removeAll(keepingCapacity: true)
    return ran
  }
}

@MainActor private func _swiftUIWebCreateBrowserExecutors() {
  _EmbeddedBrowserExecutor.installLegacyHooks()
}
#endif


/// An `App` entry point that mounts SwiftUIWeb in a browser when compiled for
/// WebAssembly. On native hosts it keeps the normal Fiber HTML
/// fallback, which makes the same examples useful in smoke tests and scripts.
public protocol BrowserApp: App {}

@MainActor
public enum BrowserAppLauncher {

  @MainActor public static func launch<A: App>(_ app: A, configuration: _AppConfiguration) {
    // Embedded Swift has no JavaScript object model to call into. Render
    // the retained Fiber tree into a compact UTF-8 snapshot. The host patches
    // DOM nodes by Fiber generation; it never replaces the body.
    #if arch(wasm32) && hasFeature(Embedded)
    embeddedBrowserLaunch(app, configuration: configuration)
    #else
    // Native callers keep a deterministic Fiber snapshot; the embedded
    // browser entry points are intentionally unavailable on this target.
    _ = FiberTree(app.body, environment: configuration.rootEnvironment)
    #endif
  }
}


#if arch(wasm32) && hasFeature(Embedded)
private final class _EmbeddedBrowserIOOperationBox: @unchecked Sendable {
  var operation: BrowserIOOperation? { didSet { if cancelled { operation?.cancel() } } }
  var cancelled = false
  func cancel() { cancelled = true; operation?.cancel() }
}

private final class _EmbeddedBrowserTaskBox: @unchecked Sendable {
  var task: Task<Void, Never>? { didSet { if cancelled { task?.cancel() } } }
  private var cancelled = false
  func cancel() { cancelled = true; task?.cancel() }
}

#endif

#if arch(wasm32) && hasFeature(Embedded)
// Snapshot ABI used only by the Embedded browser host. The owned byte buffer
// has an explicit lifetime through the next publication. Byte-wise access is
// retained for compatibility; a borrowed pointer avoids one WASM call per byte.
// BrowserApp entry points are generated transiently by the source lowering.
@MainActor private var _embeddedBrowserHTMLBuffer: UnsafeMutablePointer<UInt8>?
@MainActor private var _embeddedBrowserHTMLCount = 0
@MainActor private var _embeddedBrowserHTMLCapacity = 0
@MainActor private var _embeddedBrowserTree: FiberTree?
#if DEBUG
/// Where a debug page leaves its states for the page that replaces it (`sessionStorage`, the key the development
/// loop's page script waits for: Tools/live-reload.mjs).
private let _embeddedDevelopmentStorage = BrowserWebStorage(.session, namespace: "swiftuiweb.dev")
private let _embeddedStateSnapshotKey = "state"
#endif
/// The viewport the page reported before the tree existed (with the start message). The window encloses the
/// application's outermost geometry readers: they start at its size instead of zero (`_geometryHint`).
@MainActor private var _embeddedInitialViewport: CGSize?
@MainActor private var _embeddedBrowserLazyIDs: [FiberIdentity: (Int, Int, UInt64, _LazyAxis)] = [:]
/// Height of the viewport the host reported, which sizes the first rows of a lazy collection (see below).
@MainActor private var _embeddedViewportHeight: Double = 0
/// Lazy collections whose first rows a publication has materialized (kept while the collection is in the tree).
@MainActor private var _embeddedBrowserMaterializedLazy: Set<FiberIdentity> = []

/// A vertical lazy collection that appears in a publication (a tab built for the first time) has no rows until the host
/// asks for a window, which costs a publication of its own and a frame of empty content. The first rows are materialized
/// here instead: the rows the host keeps around the top of a list (about two and a half viewports, the window it asks
/// for first at the default extent) at the estimated extent. The host's first window then matches them and publishes
/// nothing; a window that differs is served as before. Returns whether rows were added.
/// The rows that 2.5 viewports of `height` hold at `extent` a row. A non-finite quotient (a zero or NaN extent) holds
/// none, and the count is capped, since `Int` of a huge or infinite value traps.
@MainActor private func _embeddedViewportRows(height: Double, extent: Double) -> Int {
  let rows = (2.5 * height / extent).rounded(.up)
  guard rows.isFinite else { return 0 }
  return Int(Swift.min(Swift.max(rows, 0), 1_000_000))
}

@MainActor private func _embeddedMaterializeFreshLazyCollections(_ tree: FiberTree) -> Bool {
  var added = false
  var present: Set<FiberIdentity> = []
  for info in tree._lazyCollections() {
    present.insert(info.ownerIdentity)
    guard info.descriptor.axis == .vertical, _embeddedViewportHeight > 0 else { continue }
    guard _embeddedBrowserMaterializedLazy.insert(info.ownerIdentity).inserted else { continue }
    let lanes = max(1, info.descriptor.laneCount)
    let extent = max(1, info.descriptor.estimatedExtent)
    let rows = _embeddedViewportRows(height: _embeddedViewportHeight, extent: extent)
    let (capacity, overflow) = rows.multipliedReportingOverflow(by: lanes)
    let count = overflow ? info.descriptor.count : min(info.descriptor.count, capacity)
    guard count > 0 else { continue }
    let remainingRows = (info.descriptor.count - count + lanes - 1) / lanes
    _ = tree._materializeLazyCollection(ownerIdentity: info.ownerIdentity, indices: Array(0..<count), beforeExtent: 0, afterExtent: Double(remainingRows) * extent)
    added = true
  }
  _embeddedBrowserMaterializedLazy.formIntersection(present)
  return added
}
@MainActor private var _embeddedBrowserEventNodes: [UInt32: _RenderNode] = [:]
@MainActor private var _embeddedBrowserSecureNodes: [String: _RenderNode] = [:]
// Incremental publication (Documentation/Architecture/BINARY_PATCHES.md). The host acknowledges the publication sequence it
// committed; a publication lists what changed since that acknowledged epoch, as binary records.
@MainActor private var _embeddedPublishAckedEpoch: UInt64 = 0
@MainActor private var _embeddedPublishSequence: UInt32 = 0
@MainActor private var _embeddedPublishPending: [(sequence: UInt32, epoch: UInt64)] = []
@MainActor private var _embeddedPublishCount = 0
/// Flag 32: every publication carries a reference encoding of the whole tree too, for the page to compare the DOM it built with.
@MainActor private var _embeddedBinaryVerify = false
/// What the host holds of the list of the page's own children (the record of the tree), as the fibers' records hold what it
/// holds of their elements.
@MainActor private var _embeddedBinaryRootRecord = BinaryNodeRecord()
/// The shapes the host holds (`BinaryShapeTable`), unless flag 64 turns them off. The table is made with the first publication.
@MainActor private var _embeddedBinaryShapesEnabled = false
@MainActor private var _embeddedBinaryShapes: BinaryShapeTable?
@MainActor private var _embeddedBinaryShapeTuning = (instances: 0, elements: 0)
/// Diagnostics read through `fiber_metric` 40 to 49: bytes published, 41 unused (elements the HTML transport wrote without
/// their attributes), binary publications, publications sent as the whole tree because an element the host held could not
/// stay where it sat, then roots, records, held nodes and shapes.
@MainActor private var _embeddedPublishCounters: [UInt64] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
/// Wall time of each publication phase in microseconds, accumulated until the
/// host reads them through `fiber_metric` (indexes 35...39: reconcile, snapshot walk, annotate and
/// serializer setup, serialization, result bookkeeping and buffer copy).
@MainActor private var _embeddedPublishPhaseMicroseconds: [UInt64] = [0, 0, 0, 0, 0]
@inline(__always) private func _embeddedPhaseNow() -> UInt64 { browser_io_monotonic_nanoseconds() }
@MainActor @inline(__always) private func _embeddedRecordPhase(_ index: Int, since start: UInt64) -> UInt64 {
  let now = _embeddedPhaseNow()
  _embeddedPublishPhaseMicroseconds[index] &+= (now &- start) / 1000
  return now
}
@MainActor private var _embeddedBrowserEventValueBytes: [UInt8] = []
/// Staging buffer the host writes an event value into in one copy
/// (`event_value_alloc` / `event_value_commit`).
@MainActor private var _embeddedBrowserEventValueInput = _EmbeddedByteBuffer()
/// True after `event_value_commit`: the pending value then lives in the staging
/// buffer (read in place), otherwise in `_embeddedBrowserEventValueBytes`
/// (the per-byte fallback path).
@MainActor private var _embeddedBrowserEventValueStaged = false

/// The pending event value decoded as text, `dropFirst` bytes skipped, at most
/// `limit` bytes long. Staged values are decoded straight from the buffer.
@MainActor private func _embeddedEventValueString(dropFirst: Int = 0, limit: Int = Int.max) -> String {
  if _embeddedBrowserEventValueStaged, let pointer = _embeddedBrowserEventValueInput.pointer {
    let total = _embeddedBrowserEventValueInput.count
    let start = min(max(0, dropFirst), total)
    let length = min(limit, total - start)
    return String(decoding: UnsafeBufferPointer(start: pointer + start, count: length), as: UTF8.self)
  }
  let bytes = _embeddedBrowserEventValueBytes
  let start = min(max(0, dropFirst), bytes.count)
  let end = limit >= bytes.count - start ? bytes.count : start + limit
  return String(decoding: bytes[start..<end], as: UTF8.self)
}

@MainActor private func _embeddedEventValueCount() -> Int {
  _embeddedBrowserEventValueStaged ? _embeddedBrowserEventValueInput.count : _embeddedBrowserEventValueBytes.count
}

/// Forgets the pending value: wipes what the host wrote (a password may be in
/// it) and releases staging that a large value grew.
@MainActor private func _embeddedEventValueClear() {
  _embeddedBrowserEventValueBytes.removeAll(keepingCapacity: true)
  _embeddedBrowserEventValueStaged = false
  _embeddedBrowserEventValueInput.wipe()
}
/// Newline-separated ids of the SecureFields in the newest publication.
@MainActor private var _embeddedBrowserSecureIDsOutput = _EmbeddedByteBuffer()
@MainActor private var _embeddedBrowserSecureValueBuffer: UnsafeMutablePointer<UInt8>?
@MainActor private var _embeddedBrowserSecureValueCount = 0
@MainActor private var _embeddedBrowserSecureValueCapacity = 0
@MainActor private var _embeddedBrowserStorageObservation: BrowserIOOperation?
@MainActor private var _embeddedBrowserEnvironment = EnvironmentValues()
@MainActor private var _embeddedBrowserApplyEnvironment: ((EnvironmentValues) -> Void)?
@MainActor private var _embeddedScrollSequence: UInt32 = 0
@MainActor private var _embeddedPendingScroll: (String, UnitPoint?, String?, UInt32)?

/// Breaks the retained browser-session cycle before a host starts a new app
/// session. Embedded Swift cannot depend on weak captures or eventual
/// deinitialization to retire Observation sources, so replacement is explicit.
/// A WASI environment entry supplied by the browser host, or nil.
private func _embeddedEnvironmentValue(_ key: String) -> String? {
  guard let pointer = browser_io_environment_value(key) else { return nil }
  return String(cString: pointer)
}

@MainActor private func _embeddedBrowserDisposeSession() {
  WebEnvironment.install(provider: nil)
  _ImageAssets.install(nil)
  LocalizationTable.preferredLanguage = nil
  _embeddedBrowserStorageObservation?.cancel()
  _embeddedBrowserStorageObservation = nil
  _embeddedBrowserApplyEnvironment = nil
  _embeddedBrowserTree?._dispose()
  _embeddedBrowserTree = nil
  _embeddedBrowserEventNodes.removeAll(keepingCapacity: false)
  _embeddedBrowserSecureNodes.removeAll(keepingCapacity: false)
  _embeddedBrowserEventTokens.removeAll(keepingCapacity: false)
  _embeddedBrowserLazyIDs.removeAll(keepingCapacity: false)
  _embeddedBrowserMaterializedLazy.removeAll(keepingCapacity: false)
  _embeddedPublishAckedEpoch = 0
  _embeddedBinaryRootRecord = BinaryNodeRecord()
  _embeddedBinaryShapes = nil
  _embeddedPublishSequence = 0
  _embeddedPublishPending.removeAll(keepingCapacity: false)
  _embeddedPublishCount = 0
  _embeddedBrowserEventValueBytes.removeAll(keepingCapacity: false)
  _embeddedBrowserEventValueStaged = false
  _embeddedBrowserEventValueInput.release()
  _embeddedBrowserSecureIDsOutput.release()
  if let buffer = _embeddedBrowserSecureValueBuffer {
    for index in 0..<_embeddedBrowserSecureValueCapacity { buffer[index] = 0 }
  }
  _embeddedBrowserSecureValueBuffer?.deallocate()
  _embeddedBrowserSecureValueBuffer = nil
  _embeddedBrowserSecureValueCount = 0
  _embeddedBrowserSecureValueCapacity = 0
  _embeddedPendingScroll = nil
  _embeddedBrowserHTMLBuffer?.deallocate()
  _embeddedBrowserHTMLBuffer = nil
  _embeddedBrowserHTMLCount = 0
  _embeddedBrowserHTMLCapacity = 0
  BrowserHistoryAdapter.embeddedReset()
  _BrowserDateFormatting.install(nil)
  _TextHost.formatNumber = nil
  _TextHost.fold = nil
}

/// A page address that names something other than the app's start page: the root document (`/`, `/index.html`) with
/// any query or fragment is the plain launch.
private func _embeddedIsDeepLink(_ location: String) -> Bool {
  let path = location.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
  let pathOnly = path.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
  return !(pathOnly.isEmpty || pathOnly == "/" || pathOnly == "/index.html")
}

@MainActor private func _embeddedBrowserSetHTML(_ bytes: UnsafeBufferPointer<UInt8>) {
  if bytes.count > _embeddedBrowserHTMLCapacity {
    let capacity = max(bytes.count, max(4096, _embeddedBrowserHTMLCapacity * 2))
    // The previous snapshot is dead once the host has read it; there is nothing
    // to preserve, so skip zero-filling the new allocation.
    let next = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
    _embeddedBrowserHTMLBuffer?.deallocate()
    _embeddedBrowserHTMLBuffer = next
    _embeddedBrowserHTMLCapacity = capacity
  }
  if let buffer = _embeddedBrowserHTMLBuffer, let source = bytes.baseAddress {
    buffer.update(from: source, count: bytes.count)
  }
  _embeddedBrowserHTMLCount = bytes.count
}

/// Copies one SecureField value into a private WASM buffer. This buffer is
/// read by the browser host only long enough to assign `HTMLInputElement.value`;
/// it is never part of the HTML snapshot or a _RenderNode attribute.
@MainActor private func _embeddedBrowserSetSecureValue(_ value: String) {
  let bytes = Array(value.utf8)
  if bytes.count > _embeddedBrowserSecureValueCapacity {
    let capacity = max(bytes.count, max(64, _embeddedBrowserSecureValueCapacity * 2))
    let next = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
    next.initialize(repeating: 0, count: capacity)
    if let old = _embeddedBrowserSecureValueBuffer {
      for index in 0..<_embeddedBrowserSecureValueCapacity { old[index] = 0 }
    }
    _embeddedBrowserSecureValueBuffer?.deallocate()
    _embeddedBrowserSecureValueBuffer = next
    _embeddedBrowserSecureValueCapacity = capacity
  }
  if let buffer = _embeddedBrowserSecureValueBuffer {
    for index in 0..<_embeddedBrowserSecureValueCapacity { buffer[index] = 0 }
    for index in bytes.indices { buffer[index] = bytes[index] }
  }
  _embeddedBrowserSecureValueCount = bytes.count
}

@MainActor private func _embeddedBrowserClearSecureValue() {
  if let buffer = _embeddedBrowserSecureValueBuffer {
    for index in 0..<_embeddedBrowserSecureValueCapacity { buffer[index] = 0 }
  }
  _embeddedBrowserSecureValueCount = 0
}

@MainActor private func _embeddedBrowserSecureNodeID(_ fiber: Fiber) -> String {
  "\(fiber.structuralID.index):\(fiber.structuralID.generation)"
}

// Tokens are never recycled during a session. Fiber generations prevent a
// callback from an unmounted control from targeting its replacement.
@MainActor private var _embeddedBrowserEventTokens: [StructuralNodeID: _EmbeddedEventToken] = [:]
private struct _EmbeddedEventToken { let value: UInt32; let descriptor: String? }
@MainActor private var _embeddedBrowserNextEventToken: UInt32 = 1

/// Everything a snapshot needs to decide what the host already has.
private struct _EmbeddedSnapshotContext {
  /// Epoch the host acknowledged; 0 forces a full publication.
  let acked: UInt64
  /// Fibers copied in full, with the copy that represents them.
  var written: [(fiber: Fiber, copy: _RenderNode, inHostContent: Bool)] = []
  let tree: FiberTree
  /// A placeholder stands for every element the host holds that did not change, whatever its tag and size, and these are
  /// the fibers the placeholders were made for.
  var kept: [(fiber: Fiber, node: _RenderNode)] = []
  /// The fiber of the first element of the tree, which carries the annotations of the publication (`_EmbeddedAnnotations`):
  /// a publication visits it, so that they reach the page.
  var annotationTarget: ObjectIdentifier?
  init(acked: UInt64, tree: FiberTree) { self.acked = acked; self.tree = tree }
}

@MainActor private func _embeddedBrowserNodeID(_ fiber: Fiber, _ node: _RenderNode) -> String {
  "\(fiber.structuralID.index):\(fiber.structuralID.generation):\(node.descriptor ?? "")"
}

/// Whether `fiber` is the content of a tab panel the tab view hides (`TabView` writes each tab's content as the only
/// child of its panel).
@MainActor private func _embeddedBrowserIsHiddenTabContent(_ fiber: Fiber, context: _EmbeddedSnapshotContext) -> Bool {
  guard let parentIdentity = fiber.parentIdentity, let panel = context.tree.fiber(at: parentIdentity) else { return false }
  let attributes = panel.renderNode.attributes
  return attributes["data-tab-panel"] == "true" && attributes["data-tab-hidden"] == "true"
}

/// Whether a placeholder stands for `fiber`: the host holds the element (`Fiber.firstPublishedEpoch`) as it was last
/// published, and nothing below it asks to be visited. There is no size minimum and no tag is excluded: a placeholder is a
/// handle, and the encoder checks that the parser keeps the element where it sits.
@MainActor private func _embeddedBrowserCanKeep(_ fiber: Fiber, root: Fiber, insideText: Bool, context: _EmbeddedSnapshotContext) -> Bool {
  guard fiber !== root, BinaryHeldState.holds(fiber, acked: context.acked), !insideText,
        case .element = fiber.renderNode.kind, ObjectIdentifier(fiber) != context.annotationTarget else { return false }
  // What the host keeps state in is written again with every publication, and a lazy list or a mounted view is analysed
  // again. The content of a tab panel the tab view hides is left as it is: nothing in it is on screen, and a tab view
  // that keeps every visited tab would otherwise send each hidden tab's lazy lists with every publication. The tab is
  // built and written again when it is selected.
  if (fiber.isVolatile || fiber.publishedHostOwned) && !_embeddedBrowserIsHiddenTabContent(fiber, context: context) { return false }
  return true
}

/// The first element of the tree, in the order the annotations look for it (`_embeddedBrowserAnnotate`).
@MainActor private func _embeddedBrowserFirstElementFiber(_ root: Fiber) -> Fiber? {
  var stack = [root]
  while let fiber = stack.popLast() {
    if case .element = fiber.renderNode.kind { return fiber }
    for child in fiber.children.reversed() { stack.append(child) }
  }
  return nil
}

/// One element being copied for publication, between visiting it and finishing its children.
private struct _EmbeddedSnapshotFrame {
  let fiber: Fiber
  let copy: _RenderNode
  var children: [_RenderNode]
  var next = 0
  let nextParent: String
  let insideTextLeaf: Bool
  /// Whether the children sit in content the page replaces or manages (an icon, `data-host-managed="*children"`): the
  /// page may not hold them.
  let insideHostContent: Bool
  let insideButton: Bool
  /// Whether the element sits in content the page replaces or manages (see `insideHostContent`): the page does not keep
  /// the element it would be given.
  let inHostContent: Bool
}

/// Copies the fiber tree for publication. A loop over an explicit stack rather than a recursion: a view hierarchy
/// hundreds of levels deep is a tree as deep, and one WebAssembly frame per level of it is more than a WebKit
/// Worker's stack holds.
@MainActor private func _embeddedBrowserSnapshot(_ rootFiber: Fiber, root: Fiber, context: inout _EmbeddedSnapshotContext) -> _RenderNode {
  var stack: [_EmbeddedSnapshotFrame] = []
  switch _embeddedBrowserSnapshotVisit(rootFiber, root: root, context: &context, parentTag: "", insideTextLeaf: false, insideButton: false, insideHostContent: false) {
  case .finished(let node): return node
  case .descend(let frame): stack.append(frame)
  }
  while let top = stack.last {
    if top.next < top.fiber.children.count {
      let child = top.fiber.children[top.next]
      stack[stack.count - 1].next += 1
      switch _embeddedBrowserSnapshotVisit(child, root: root, context: &context, parentTag: top.nextParent, insideTextLeaf: top.insideTextLeaf, insideButton: top.insideButton, insideHostContent: top.insideHostContent) {
      case .finished(let node): stack[stack.count - 1].children.append(node)
      case .descend(let frame): stack.append(frame)
      }
    } else {
      let done = stack.removeLast()
      done.copy.children = done.children
      context.written.append((done.fiber, done.copy, done.inHostContent))
      if stack.isEmpty { return done.copy }
      stack[stack.count - 1].children.append(done.copy)
    }
  }
  fatalError("the snapshot of a fiber tree always ends with its root")
}

private enum _EmbeddedSnapshotStep {
  case finished(_RenderNode)
  case descend(_EmbeddedSnapshotFrame)
}

@MainActor private func _embeddedBrowserSnapshotVisit(_ fiber: Fiber, root: Fiber, context: inout _EmbeddedSnapshotContext, parentTag: String, insideTextLeaf: Bool, insideButton: Bool, insideHostContent: Bool) -> _EmbeddedSnapshotStep {
  let node = fiber.renderNode
  // The HTML parser never nests a <button> in a <button>: it closes the outer one and lifts everything after it out
  // of its container. A button under a button (a context menu's items inside a row that is itself a button) is
  // published as a div with the button role instead.
  var kind = node.kind
  var nestedButton = false
  if insideButton, case .element("button") = node.kind { kind = .element("div"); nestedButton = true }
  if _embeddedBrowserCanKeep(fiber, root: root, insideText: insideTextLeaf, context: context) {
    // The handle names the element; its tag and namespace say whether it is the one the host holds.
    let keep = _RenderNode.element(StaticHTMLFiberRenderer.keepTag)
    keep.attributes["data-embedded-node-id"] = _embeddedBrowserNodeID(fiber, node)
    if case .element(let tag) = kind { keep.attributes["data-keep-tag"] = tag }
    context.kept.append((fiber, keep))
    return .finished(keep)
  }
  // Copy only serialized presentation fields. Never annotate the retained
  // semantic tree, or the next reconciliation sees the host's own attributes.
  let copy = _RenderNode(kind: kind, text: node.text)
  copy.attributes = node.attributes
  // Swift's own marker of semantic layout attributes (`_semanticWrap`); the page never reads it, and every element of a
  // publication carried it.
  copy.attributes.removeValue(forKey: "data-layout-schema")
  if nestedButton {
    copy.attributes["role"] = copy.attributes["role"] ?? "button"
    copy.attributes["tabindex"] = copy.attributes["tabindex"] ?? "0"
    copy.attributes["data-nested-button"] = "true"
  }
  copy.styles = node.styles
  copy.classes = node.classes
  if let info = _embeddedBrowserLazyIDs[fiber.identity] {
    copy.attributes["data-keep-lazy-index"] = String(info.0)
    copy.attributes["data-keep-lazy-lanes"] = String(info.1)
    copy.attributes["data-keep-lazy-revision"] = String(info.2)
    // The axis the collection is windowed on: its container is not always the lazy stack that sets `data-lazy` (an
    // HStack in a LazyHStack).
    if info.3 == .horizontal { copy.attributes["data-keep-lazy-axis"] = "horizontal" }
  }
  let textOnlyParent = ["option", "textarea", "title", "script", "style", "text", "tspan"].contains(parentTag)
  if node.kind != .text || !textOnlyParent {
    copy.attributes["data-embedded-node-id"] = _embeddedBrowserNodeID(fiber, node)
    // Runs inside a rich Text leaf are inline content of that one leaf; only
    // the outer span participates in semantic layout and measurement.
    if node.kind == .text && !insideTextLeaf {
      copy.attributes["data-layout-kind"] = "intrinsic"
      copy.attributes["data-layout-leaf"] = "text"
    }
  }
  if node.attributes["data-control-kind"] == "secure-field" {
    let secureID = _embeddedBrowserSecureNodeID(fiber)
    copy.attributes["data-keep-secure-id"] = secureID
    _embeddedBrowserSecureNodes[secureID] = node
  }
  if let mountKey = copy.attributes["data-web-mount-key"] {
    let identity = "\(fiber.structuralID.index):\(fiber.structuralID.generation)"
    let token = "\(identity.utf8.count):\(identity)|\(mountKey.utf8.count):\(mountKey)"
    copy.attributes["data-web-mount-token"] = token
    if let descriptor = node._domView {
      _DOMViewRuntime.stage(token: token, descriptor: descriptor)
    }
  }
  // A hover the framework could express as CSS never reaches Swift: drop its
  // enter/leave events from the published node (Swift keeps them as fallback).
  var publishedEvents = node.events
  if node._hoverProbe != nil, context.tree._resolveHover(for: fiber, deferringNew: true) {
    publishedEvents.removeValue(forKey: "mouseenter")
    publishedEvents.removeValue(forKey: "mouseleave")
  }
  if !publishedEvents.isEmpty {
    let token: UInt32
    if let existing = _embeddedBrowserEventTokens[fiber.structuralID], existing.descriptor == node.descriptor { token = existing.value }
    else {
      precondition(_embeddedBrowserNextEventToken < UInt32.max, "Embedded event token space exhausted")
      token = _embeddedBrowserNextEventToken
      _embeddedBrowserNextEventToken += 1
      _embeddedBrowserEventTokens[fiber.structuralID] = _EmbeddedEventToken(value: token, descriptor: node.descriptor)
    }
    copy.attributes["data-embedded-event-id"] = String(token)
    copy.attributes["data-embedded-events"] = publishedEvents.keys.sorted().joined(separator: ",")
    copy.attributes["data-embedded-prevent-events"] = publishedEvents.filter { $0.value.preventsDefault }.map { $0.key }.sorted().joined(separator: ",")
    _embeddedBrowserEventNodes[token] = node
  }
  let nextParent: String
  if case .element(let tag) = kind { nextParent = tag } else { nextParent = parentTag }
  let childInsideButton = insideButton || { if case .element("button") = node.kind { return true } else { return false } }()
  let childInsideTextLeaf = insideTextLeaf || node.attributes["data-layout-leaf"] == "text"
  var children: [_RenderNode] = []
  children.reserveCapacity(fiber.children.count)
  return .descend(_EmbeddedSnapshotFrame(fiber: fiber, copy: copy, children: children, nextParent: nextParent, insideTextLeaf: childInsideTextLeaf, insideHostContent: insideHostContent || node.attributes["data-symbol"] != nil || node.attributes["data-host-managed"]?.hasPrefix("*children") == true, insideButton: childInsideButton, inHostContent: insideHostContent))
}

@MainActor private var _embeddedTransactionSerial: UInt32 = 0

@MainActor private func _embeddedBrowserAnnotateTransaction(_ node: _RenderNode, css: String) -> Bool {
  if case .element = node.kind {
    node.attributes["data-animation-transaction"] = css
    return true
  }
  for child in node.children {
    if _embeddedBrowserAnnotateTransaction(child, css: css) { return true }
  }
  return false
}

/// A commit that carries an animation transaction animates the scroll positions it sets: the host
/// marks each scroll surface, and the coordinator scrolls smoothly when that surface's target changed.
@MainActor private func _embeddedBrowserAnnotateScrollPositionAnimation(_ node: _RenderNode) {
  if node.attributes["data-scroll-position"] == "true" {
    node.attributes["data-scroll-position-animated"] = "true"
  }
  for child in node.children { _embeddedBrowserAnnotateScrollPositionAnimation(child) }
}

@discardableResult
@MainActor private func _embeddedBrowserAnnotate(_ node: _RenderNode, values: _NodeValues) -> Bool {
  if case .element = node.kind {
    for (key, value) in values { node.attributes[key] = value }; return true
  }
  for child in node.children { if _embeddedBrowserAnnotate(child, values: values) { return true } }
  return false
}

// Writes that happen outside a DOM event (a finished request, a timer, a task)
// arrive inside one of the host's entry points. Coalesce them: the invalidation
// handler only records that a publication is owed, and the outermost entry point
// publishes once when it finishes, however many writes it made.
@MainActor private var _embeddedEntryDepth = 0
@MainActor private var _embeddedPublishRequested = false

@MainActor private func _embeddedRequestPublish(_ tree: FiberTree) {
  if _embeddedEntryDepth > 0 { _embeddedPublishRequested = true } else { _embeddedBrowserPublish(tree) }
}

/// Depth of the render that a publication starts with `tree.renderNode`. A render pass is open then, and the runtime refuses
/// a second one in the same state store (`BUSY`, which traps), so a media request raised by that render must wait.
@MainActor private var _embeddedRenderingDepth = 0

/// A player's wish changed. A player created in a `@State` initializer registers itself while the page renders and asks
/// for a publication from inside that render. That request waits, and one more publication serves it when the running one
/// returns (`_embeddedPublishRequested`, as batched writes are). Outside a render it publishes at once, as before.
@MainActor private func _embeddedRequestPublishForMedia(_ tree: FiberTree) {
  if _embeddedRenderingDepth > 0 || _embeddedEntryDepth > 0 { _embeddedPublishRequested = true } else { _embeddedBrowserPublish(tree) }
}

@MainActor private func _embeddedBatchedEntry<Result>(_ body: () -> Result) -> Result {
  _embeddedEntryDepth += 1
  let result = body()
  _embeddedEntryDepth -= 1
  if _embeddedEntryDepth == 0, _embeddedPublishRequested {
    _embeddedPublishRequested = false
    if let tree = _embeddedBrowserTree { _embeddedBrowserPublish(tree) }
  }
  return result
}

/// Elements the published HTML nests before the rest follows as siblings (see `StaticHTMLFiberRenderer.maxElementDepth`).
/// Both parsers stop nesting at 512 elements on their own, so this writes the tree they would build (a shallower tree
/// is unchanged). It stays under that depth, so that no parser sees more, and puts the siblings written past the limit
/// at the depth the parsers did (the host's own `html`, `body` and root, then these 510 levels, then the sibling): WebKit
/// builds no renderer below 512 levels, and a limit lower than that made it lay out and tear down thousands of boxes the
/// parser used to leave without one (a 5000-level mount took 1.5 s longer).
private let _embeddedMaxNestedElements = 510

/// Publishes the tree. A media request that arrived while it rendered is served by a publication of its own, after this one
/// returns to the host (a second publication in the same task would reuse the host's acknowledgement epoch before it applied).
@MainActor private func _embeddedBrowserPublish(_ tree: FiberTree) {
  _embeddedBrowserPublishNow(tree)
  if _embeddedRenderingDepth == 0, _embeddedEntryDepth == 0, _embeddedPublishRequested {
    _embeddedPublishRequested = false
    _ = BrowserTimer.schedule(after: 0) { _assumeMainActor { if let live = _embeddedBrowserTree { _embeddedBrowserPublish(live) } } }
  }
  _embeddedScheduleHoverLearning(tree)
}

/// The hovering views a publication met for the first time are learned by a publication of their own once publications
/// pause for this long (`FiberTree._learnDeferredHover`): not on the path of the input that brought them (a list that
/// filters while typing brings back dozens of cards at every key), and not between two keys of a word.
private let _embeddedHoverLearningDelay = 0.25
@MainActor private var _embeddedHoverLearningTimer: BrowserIOOperation?
/// Set by the timer: the next publication learns what was deferred before its snapshot.
@MainActor private var _embeddedHoverLearningDue = false

@MainActor private func _embeddedScheduleHoverLearning(_ tree: FiberTree) {
  _embeddedHoverLearningTimer?.cancel()
  _embeddedHoverLearningTimer = nil
  guard tree._hasDeferredHover else { return }
  _embeddedHoverLearningTimer = BrowserTimer.schedule(after: _embeddedHoverLearningDelay) {
    _assumeMainActor {
      _embeddedHoverLearningTimer = nil
      guard let live = _embeddedBrowserTree, live._hasDeferredHover else { return }
      _embeddedHoverLearningDue = true
      _embeddedBrowserPublish(live)
    }
  }
}

@MainActor private func _embeddedBrowserPublishNow(_ tree: FiberTree) {
  var phaseStart = _embeddedPhaseNow()
  // This getter flushes all pending structural and leaf invalidations first.
  _embeddedRenderingDepth += 1
  _ = tree.renderNode
  _embeddedRenderingDepth -= 1
  phaseStart = _embeddedRecordPhase(0, since: phaseStart)
  // Event routes persist between publications (subtrees the host keeps are not
  // visited); they are pruned by liveness below. Secure fields and lazy
  // collections are volatile, so they are always visited and rebuilt.
  _embeddedBrowserSecureNodes.removeAll(keepingCapacity: true)
  _embeddedBrowserLazyIDs.removeAll(keepingCapacity: true)
  if _embeddedMaterializeFreshLazyCollections(tree) { _ = tree.renderNode }
  // Rows materialized before the data changed are rendered again here, so the first publication after the change shows
  // the current rows instead of the previous data's until the host asks for the window.
  if tree._refreshStaleLazyWindows(growTo: { descriptor in
    guard descriptor.axis == .vertical, _embeddedViewportHeight > 0 else { return 0 }
    return _embeddedViewportRows(height: _embeddedViewportHeight, extent: max(1, descriptor.estimatedExtent))
  }) { _ = tree.renderNode }
  for (index, info) in tree._lazyCollections().enumerated() {
    _embeddedBrowserLazyIDs[info.containerIdentity] = (index, max(1, info.descriptor.laneCount), info.descriptor.revision, info.descriptor.axis)
  }
  if _embeddedHoverLearningDue {
    _embeddedHoverLearningDue = false
    tree._learnDeferredHover()
  }
  // A publication lists the changes since the epoch the host acknowledged only when the host holds the tree the fibers'
  // records describe; otherwise it is the whole tree, and nothing is replaced by a placeholder.
  let hostHoldsTree = BinaryHeldState.holdsTree(_embeddedBinaryRootRecord, acked: _embeddedPublishAckedEpoch)
  let snapshotAcked = hostHoldsTree ? _embeddedPublishAckedEpoch : 0
  _DOMViewRuntime.beginSnapshot()
  var context = _EmbeddedSnapshotContext(acked: snapshotAcked, tree: tree)
  if snapshotAcked > 0, let target = _embeddedBrowserFirstElementFiber(tree.root) { context.annotationTarget = ObjectIdentifier(target) }
  let root = _embeddedBrowserSnapshot(tree.root, root: tree.root, context: &context)
  _DOMViewRuntime.finishSnapshot()
  phaseStart = _embeddedRecordPhase(1, since: phaseStart)
  var annotations = _EmbeddedAnnotations()
  if let rules = tree._hoverRuleChanges(acked: _embeddedPublishAckedEpoch) {
    annotations.values.append(["data-hover-rules": rules])
  }
  if let request = ScrollViewRuntime._consumeLastRequest() {
    _embeddedScrollSequence = _embeddedScrollSequence == UInt32.max ? 1 : _embeddedScrollSequence + 1
    _embeddedPendingScroll = (request.0, request.1, ScrollViewRuntime._consumeLastScope(), _embeddedScrollSequence)
  }
  if let request = _embeddedPendingScroll {
    var values: _NodeValues = ["data-embedded-scroll-id": request.0,
                  "data-embedded-scroll-sequence": String(request.3)]
    if let scope = request.2 { values["data-embedded-scroll-scope"] = scope }
    if let anchor = request.1 { values["data-embedded-scroll-anchor"] = "\(anchor.x),\(anchor.y)" }
    annotations.values.append(values)
  }
  if _HeadlessMedia.isAvailable {
    // Players without a view: their wishes ride on the root, their reports come back through a reserved route.
    let wishes = _HeadlessMedia.wishes()
    if wishes != "[]" {
      annotations.values.append(["data-headless-media-wishes": wishes, "data-headless-event-id": String(_HeadlessMedia.eventToken)])
      _embeddedBrowserEventNodes[_HeadlessMedia.eventToken] = _HeadlessMedia.node
    } else {
      _embeddedBrowserEventNodes.removeValue(forKey: _HeadlessMedia.eventToken)
    }
  }
  if let operations = BrowserHistoryAdapter.embeddedOperations() {
    annotations.values.append(["data-history-operations": operations])
  }
  // Numbered, so that two animated commits in a row with the same animation still differ: an update sends the root's first
  // element only when its attributes changed, and an unchanged transaction would reach the page as no transaction at all.
  annotations.transaction = tree.root.stateStore._takeAnimationTransactionCSS().map { css in
    _embeddedTransactionSerial = _embeddedTransactionSerial == UInt32.max ? 1 : _embeddedTransactionSerial + 1
    return css + " /* transaction \(_embeddedTransactionSerial) */"
  }
  annotations.apply(to: root)
  phaseStart = _embeddedRecordPhase(2, since: phaseStart)
  _embeddedPublishCount += 1
  if _embeddedPublishCount % 8 == 0 { _embeddedBrowserPruneEventRoutes(tree) }

  let covered = tree._advanceEpoch()
  tree._hoverRulesPublished(epoch: covered)
  let published = _embeddedBrowserPublishBinary(tree, root: root, context: context, annotations: annotations, covered: covered)
  _embeddedPublishCounters[0] += UInt64(published)
  phaseStart = _embeddedRecordPhase(3, since: phaseStart)
  _embeddedPublishSequence = _embeddedPublishSequence == UInt32.max ? 1 : _embeddedPublishSequence + 1
  _embeddedPublishPending.append((_embeddedPublishSequence, covered))
  if _embeddedPublishPending.count > 32 { _embeddedPublishPending.removeFirst(_embeddedPublishPending.count - 32) }
  _ = _embeddedRecordPhase(4, since: phaseStart)
}

/// What a publication adds to the root's first element: the requests, rules and transactions the page reads there. They are
/// worked out once, so that the tree a binary publication is checked against (or falls back to) carries the same ones.
private struct _EmbeddedAnnotations {
  var values: [_NodeValues] = []
  var transaction: String?

  @MainActor func apply(to root: _RenderNode) {
    for entry in values { _ = _embeddedBrowserAnnotate(root, values: entry) }
    if let transaction {
      _ = _embeddedBrowserAnnotateTransaction(root, css: transaction)
      _embeddedBrowserAnnotateScrollPositionAnimation(root)
    }
  }
}

private typealias _EmbeddedWrittenFibers = [(fiber: Fiber, copy: _RenderNode, inHostContent: Bool)]

/// Publishes the snapshot `root` as a binary stream (Documentation/Architecture/BINARY_PATCHES.md): the whole tree when the
/// host holds nothing, otherwise records of what changed since the epoch it acknowledged, or the whole tree again when an
/// element the host holds cannot stay where it now sits (see `BinaryFiberEncoder`). In the verification mode
/// (`_embeddedBinaryVerify`) the publication also carries a reference: the whole tree encoded again by a fresh encoder, which
/// the page builds and compares its DOM with. Returns the bytes published.
@MainActor private func _embeddedBrowserPublishBinary(_ tree: FiberTree, root: _RenderNode, context: _EmbeddedSnapshotContext, annotations: _EmbeddedAnnotations, covered: UInt64) -> Int {
  var byCopy: [ObjectIdentifier: Fiber] = [:]
  byCopy.reserveCapacity(context.written.count + context.kept.count)
  for entry in context.written { byCopy[ObjectIdentifier(entry.copy)] = entry.fiber }
  for entry in context.kept { byCopy[ObjectIdentifier(entry.node)] = entry.fiber }
  if _embeddedBinaryShapesEnabled && _embeddedBinaryShapes == nil { _embeddedBinaryShapes = BinaryShapeTable(minimumElements: _embeddedBinaryShapeTuning.elements == 0 ? 3 : _embeddedBinaryShapeTuning.elements, instancesBeforeDefinition: _embeddedBinaryShapeTuning.instances == 0 ? 3 : _embeddedBinaryShapeTuning.instances) }
  let encoder = BinaryFiberEncoder(maxElementDepth: _embeddedMaxNestedElements, acked: context.acked, covered: covered, rootRecord: _embeddedBinaryRootRecord, shapes: _embeddedBinaryShapes, lookup: { node in
    _assumeMainActor { byCopy[ObjectIdentifier(node)].map { BinaryHeldState.record(of: $0) } }
  })
  // The tree with nothing replaced by a placeholder: the snapshot itself when the host held nothing, otherwise another.
  var full: (root: _RenderNode, written: _EmbeddedWrittenFibers)?
  func fullSnapshot() -> (root: _RenderNode, written: _EmbeddedWrittenFibers) {
    if let full { return full }
    if context.acked == 0 {
      full = (root, context.written)
    } else {
      _DOMViewRuntime.beginSnapshot()
      var fullContext = _EmbeddedSnapshotContext(acked: 0, tree: tree)
      let fullRoot = _embeddedBrowserSnapshot(tree.root, root: tree.root, context: &fullContext)
      _DOMViewRuntime.finishSnapshot()
      annotations.apply(to: fullRoot)
      full = (fullRoot, fullContext.written)
    }
    return full!
  }
  // The verification mode's reference: the whole tree encoded again by an encoder that holds nothing and shares no state with
  // the publication (no shapes, no held state, no root record).
  let reference = _embeddedBinaryVerify
    ? BinaryFiberEncoder(maxElementDepth: _embeddedMaxNestedElements, acked: 0, covered: covered, rootRecord: BinaryNodeRecord(), lookup: { _ in nil }).encode(fullSnapshot().root)?.bytes
    : nil
  func encode(_ encoder: BinaryFiberEncoder, _ tree: _RenderNode) -> BinaryFiberEncoder.Output? {
    guard let reference else { return encoder.encode(tree) }
    return reference.withUnsafeBufferPointer { encoder.encode(tree, reference: $0) }
  }
  var visited = context.written
  var kept = context.kept
  let output: BinaryFiberEncoder.Output
  if let incremental = encode(encoder, root) {
    output = incremental
  } else {
    // The whole tree, which holds no placeholder: the page reconciles it with the DOM it has, and what it held before is no
    // longer what the records describe.
    let everything = fullSnapshot()
    var fullByCopy: [ObjectIdentifier: Fiber] = [:]
    fullByCopy.reserveCapacity(everything.written.count)
    for entry in everything.written { fullByCopy[ObjectIdentifier(entry.copy)] = entry.fiber }
    let whole = BinaryFiberEncoder(maxElementDepth: _embeddedMaxNestedElements, acked: context.acked, covered: covered, rootRecord: BinaryNodeRecord(), shapes: _embeddedBinaryShapes, lookup: { node in
      _assumeMainActor { fullByCopy[ObjectIdentifier(node)].map { BinaryHeldState.record(of: $0) } }
    })
    guard let encoded = encode(whole, everything.root) else { fatalError("a tree without placeholders is always encoded") }
    _embeddedPublishCounters[3] += 1
    output = encoded
    visited = everything.written
    kept = []
  }
  output.bytes.withUnsafeBufferPointer { _embeddedBrowserSetHTML($0) }
  _embeddedPublishCounters[2] += 1
  if output.isRoot { _embeddedPublishCounters[4] += 1 }
  _embeddedPublishCounters[5] += UInt64(output.attrsRecords)
  _embeddedPublishCounters[6] += UInt64(output.childrenRecords)
  _embeddedPublishCounters[7] += UInt64(output.heldNodes)
  _embeddedPublishCounters[8] += UInt64(output.shapeDefinitions)
  _embeddedPublishCounters[9] += UInt64(output.shapeInstances)
  BinaryHeldState.published(output, visited: visited.map { ($0.fiber, $0.copy, $0.inHostContent) }, kept: kept, covered: covered)
  _embeddedBinaryRootRecord = output.rootRecord
  return output.bytes.count
}

/// Drops event routes of fibers that no longer exist. Routes of kept subtrees
/// stay valid because their fibers (and nodes) are unchanged.
@MainActor private func _embeddedBrowserPruneEventRoutes(_ tree: FiberTree) {
  var liveTokens = Set<UInt32>()
  var dead: [StructuralNodeID] = []
  for (id, token) in _embeddedBrowserEventTokens {
    if tree._isStructuralNodeLive(id) { liveTokens.insert(token.value) } else { dead.append(id) }
  }
  for id in dead { _embeddedBrowserEventTokens.removeValue(forKey: id) }
  liveTokens.insert(_HeadlessMedia.eventToken)
  _embeddedBrowserEventNodes = _embeddedBrowserEventNodes.filter { liveTokens.contains($0.key) }
}

public extension BrowserAppLauncher {

  @MainActor private static func _embeddedInstallStorage() {
    let app = BrowserWebStorage(.local, namespace: "swiftuiweb")
    let scene = BrowserWebStorage(.session, namespace: "swiftuiweb")
    @MainActor func storageError(_ error: BrowserIOError, expected: UInt64? = nil, actual: UInt64? = nil) -> StorageError {
      switch error.code {
      case -3: return .quotaExceeded
      case -2, -7: return .unavailable
      case -9: return .transactionConflict(expected: expected ?? 0, actual: actual ?? 0)
      case -1: return .invalidKey
      default: return .host(error.message)
      }
    }
    @MainActor func transaction(_ storage: BrowserWebStorage, _ mutations: [StorageMutation], _ expected: UInt64?) throws -> UInt64 {
      let hostMutations = mutations.map { mutation -> BrowserWebStorage.Mutation in
        switch mutation {
        case .set(let key, let value): return .set(key: key, value: value)
        case .remove(let key): return .remove(key: key)
        }
      }
      do { return try storage.transaction(hostMutations, expectedRevision: expected) }
      catch {
        let actual = (try? storage.revision()) ?? 0
        throw storageError(error, expected: expected, actual: actual)
      }
    }
    StorageRuntime.install(
      appAdapter: StorageAdapter(
        read: { key in try? app.get(key) },
        write: { key, value in try? app.set(value, forKey: key) },
        throwingWrite: { key, value in
          do { try app.set(value, forKey: key) }
          catch let error as BrowserIOError { throw storageError(error) }
          catch { throw StorageError.host("Storage host operation failed") }
        },
        remove: { key in try? app.remove(key) },
        transaction: { mutations, expected in try transaction(app, mutations, expected) },
        revision: { (try? app.revision()) ?? 0 }
      ),
      sceneAdapter: StorageAdapter(
        read: { key in try? scene.get(key) },
        write: { key, value in try? scene.set(value, forKey: key) },
        throwingWrite: { key, value in
          do { try scene.set(value, forKey: key) }
          catch let error as BrowserIOError { throw storageError(error) }
          catch { throw StorageError.host("Storage host operation failed") }
        },
        remove: { key in try? scene.remove(key) },
        transaction: { mutations, expected in try transaction(scene, mutations, expected) },
        revision: { (try? scene.revision()) ?? 0 }
      )
    )
  }

  nonisolated private static func _embeddedRequest(
    _ request: URLRequest,
    configuration: URLSessionConfiguration
  ) -> BrowserHTTPRequest {
    var headers = configuration.httpAdditionalHeaders ?? [:]
    for (key, value) in request.allHTTPHeaderFields ?? [:] { headers[key] = value }
    let requestTimeout = request.explicitTimeout ?? configuration.timeoutIntervalForRequest
    let resourceTimeout = configuration.timeoutIntervalForResource > 0 ? configuration.timeoutIntervalForResource : requestTimeout
    let timeoutSeconds = min(requestTimeout, resourceTimeout)
    let timeoutMilliseconds: UInt32
    if timeoutSeconds <= 0 { timeoutMilliseconds = 0 }
    else { timeoutMilliseconds = UInt32(min(timeoutSeconds * 1000, Double(UInt32.max))) }
    let credentials: BrowserHTTPRequest.Credentials
    switch configuration.credentialsPolicy(for: request) {
    case .omit: credentials = .omit
    case .sameOrigin: credentials = .sameOrigin
    case .include: credentials = .include
    }
    let redirect: BrowserHTTPRequest.Redirect
    switch configuration.redirectPolicy {
    case .follow: redirect = .follow
    case .manual: redirect = .manual
    case .error: redirect = .error
    }
    return BrowserHTTPRequest(
      url: request.url?.absoluteString ?? "",
      method: request.effectiveHTTPMethod,
      headers: headers,
      body: request.httpBody?.toArray(),
      timeoutMilliseconds: timeoutMilliseconds,
      maximumResponseBytes: 64 * 1024 * 1024 - 65536,
      credentials: credentials,
      redirect: redirect,
      // The request's cache policy (`reloadIgnoringLocalCacheData` is fetch's `no-store`).
      cache: BrowserHTTPRequest.Cache(rawValue: request.browserCacheMode) ?? .default
    )
  }

  nonisolated private static func _embeddedResponse(_ response: BrowserHTTPResponse) -> (Data, HTTPURLResponse) {
    let url = URL(string: response.url) ?? URL(response.url)
    // Foundation's rule: an absent or encoded body has no expected length (the response is decoded by fetch).
    let length = _expectedContentLength(headers: response.headers)
    let mime = response.headers.first { $0.key.lowercased() == "content-type" }?.value
    return (
      Data(response.body),
      HTTPURLResponse(url: url, statusCode: response.statusCode, headerFields: response.headers, expectedContentLength: length, mimeType: mime)
    )
  }

  /// Maps the host's failure codes (see `Tools/BrowserIO/browser-io.mjs`) to the
  /// package networking vocabulary; URLSession then exposes them as `URLError` codes.
  nonisolated private static func _embeddedNetworkError(_ error: BrowserIOError) -> NetworkError {
    switch error.code {
    case -1: return .invalidRequest(error.message)
    case -2: return .insecureRequest(error.message)
    case -3: return .transport("Browser storage or response quota exceeded")
    case -4: return .cancelled
    case -5: return .timedOut
    case -7: return .unavailable
    case -9: return .connectionFailed(error.message)
    case -12: return .offline(error.message)
    case -13: return .connectionLost(error.message)
    case -14: return .responseTooLarge(error.message)
    case -15: return .unsupported(error.message)
    case -16: return .badURL(error.message)
    default: return .transport(error.message)
    }
  }

  /// Adapts a transfer's upload report to BrowserIO's unsigned counts.
  nonisolated private static func _embeddedUploadReport(
    _ report: @escaping @Sendable (Int64, Int64) -> Void
  ) -> @Sendable (UInt64, UInt64) -> Void {
    { sent, total in report(Int64(clamping: sent), Int64(clamping: total)) }
  }

  /// Adapts the host's download report to a transfer's cumulative count, with Foundation's expected length.
  nonisolated private static func _embeddedDownloadReport(
    _ report: @escaping @Sendable (Int64, Int64) -> Void
  ) -> @Sendable (BrowserHTTPDownloadProgress) -> Void {
    { event in
      var headers: [String: String] = [:]
      if let length = event.contentLength { headers["content-length"] = length }
      if let encoding = event.contentEncoding { headers["content-encoding"] = encoding }
      report(Int64(clamping: event.received), _expectedContentLength(headers: headers))
    }
  }

  /// `withAnimation(_:completionCriteria:_:completion:)` completes on the page's timer.
  @MainActor private static func _embeddedInstallAnimationCompletions() {
    _animationCompletionScheduler = { seconds, completion in
      nonisolated(unsafe) let completion = completion
      _ = BrowserTimer.schedule(after: seconds) { _assumeMainActor { completion() } }
    }
  }

  @MainActor private static func _embeddedInstallNetworking() {
    // The page's own cookie jar: `HTTPCookieStorage` reads and writes `document.cookie` through BrowserIO.
    CookieJarRuntime.install(
      read: {
        guard let snapshot = try? BrowserCookieJar().snapshot() else { return nil }
        return (snapshot.cookieString, snapshot.host, snapshot.isSecurePage)
      },
      write: { line in (try? BrowserCookieJar().write(line)) != nil }
    )
    NetworkRuntime.installTimeoutScheduler { seconds, callback in
      let box = _EmbeddedBrowserIOOperationBox()
      box.operation = BrowserTimer.schedule(after: seconds, callback)
      return { box.cancel() }
    }
    NetworkRuntime.installConfigured { request, configuration in
      do {
        let response = try await BrowserHTTPClient.send(_embeddedRequest(request, configuration: configuration))
        return _embeddedResponse(response)
      } catch let error as BrowserIOError {
        throw _embeddedNetworkError(error)
      }
    }
    NetworkRuntime.installConnectivityProvider {
      guard let online = BrowserConnectivity.isOnline() else { return NetworkConnectivityState(status: .unknown) }
      return NetworkConnectivityState(status: online ? .online : .offline)
    }
    NetworkRuntime.installConnectivitySubscription { callback in
      // The subscription cancellation token is @Sendable. Keep the non-Sendable
      // browser operation behind the same explicitly synchronized wrapper used
      // by fetch cancellation instead of capturing it directly.
      let box = _EmbeddedBrowserIOOperationBox()
      box.operation = BrowserConnectivity.observe { online in
        callback(NetworkConnectivityState(status: online ? .online : .offline))
      }
      return { box.cancel() }
    }
    NetworkRuntime.installTransferProgress { request, configuration, progress in
      do {
        let response = try await BrowserHTTPClient.send(
          _embeddedRequest(request, configuration: configuration),
          uploadProgress: progress.upload.map(_embeddedUploadReport),
          downloadProgress: progress.download.map(_embeddedDownloadReport)
        )
        return _embeddedResponse(response)
      } catch let error as BrowserIOError {
        throw _embeddedNetworkError(error)
      }
    }
    NetworkRuntime.installStreaming { request, configuration in
      let hostRequest = _embeddedRequest(request, configuration: configuration)
      do {
        let (response, source) = try await BrowserHTTPClient.stream(hostRequest)
        let (_, http) = _embeddedResponse(response)
        let bridge = _EmbeddedBrowserTaskBox()
        let stream = AsyncThrowingStream<Data, Error> { continuation in
          continuation.onTermination = { _ in bridge.cancel() }
          bridge.task = Task {
            do {
              for try await chunk in source { continuation.yield(Data(chunk)) }
              continuation.finish()
            } catch let error as BrowserIOError {
              continuation.finish(throwing: _embeddedNetworkError(error))
            } catch { continuation.finish(throwing: error) }
          }
        }
        return (http, stream)
      } catch let error as BrowserIOError {
        throw _embeddedNetworkError(error)
      }
    }
  }

  @MainActor static func embeddedBrowserLaunch<A: App>(_ app: A, configuration: _AppConfiguration) {
    _embeddedBrowserDisposeSession()
    _HeadlessMedia.isAvailable = true
    SwiftUIWebDateRuntime.install(now: { browser_io_wall_time_seconds() })
    // `<meta name="runtime-environment" content="KEY=VALUE">` entries reach
    // the wasm as its WASI environment (main thread and worker alike), which
    // makes `WebEnvironment` real in the browser and carries the generated
    // asset-catalog image manifest.
    WebEnvironment.install(provider: { key in _embeddedEnvironmentValue(key) })
    _ImageAssets.install(manifest: _embeddedEnvironmentValue("SWIFTUIWEB_IMAGE_ASSETS") ?? "")
    // The host passes navigator.language unless the application pinned a
    // language meta; nil keeps the development language of the strings table.
    LocalizationTable.preferredLanguage = _embeddedEnvironmentValue("SWIFTUIWEB_LANGUAGE")
    // `?stack-depth=1` measures the render recursion: depth and the call-stack headroom the host sees at each level.
    if _embeddedEnvironmentValue("SWIFTUIWEB_STACK_DIAGNOSTICS") != nil {
      _RenderDepthMeter.observer = { depth in browser_io_stack_headroom(UInt32(truncatingIfNeeded: depth)) }
      _RenderDepthMeter.enabled = true
    }
    // `?render-stage=N` overrides how many view levels a render descends before it stages the rest (0 turns it off).
    if let stage = _embeddedEnvironmentValue("SWIFTUIWEB_RENDER_STAGE"), let budget = Int(stage) {
      _RenderStaging.budget = budget
    }
    // Install browser capabilities before evaluating app.body. SwiftUI lifecycle
    // tasks and @AppStorage may run during the first Fiber evaluation.
    _swiftUIWebCreateBrowserExecutors()
    _embeddedInstallStorage()
    _embeddedInstallNetworking()
    _embeddedInstallAnimationCompletions()
    _DOMViewRuntime.install()
    _BrowserDateFormatting.install { request in
      BrowserIntl.format(
        epochSeconds: request.epochSeconds,
        style: request.style.rawValue,
        locale: request.locale,
        calendar: request.calendar,
        offsetSeconds: request.offsetSeconds,
        options: request.options
      )
    }
    // `Calendar.current` and `TimeZone.current` read the browser's zone through the same host as the date formatting.
    _LocalTimeZoneHost.install { BrowserIntl.localOffsetSeconds(epochSeconds: $0) }
    _LocalTimeZoneHost.installZoneAndWeek(
      identifier: { BrowserIntl.localTimeZoneIdentifier() },
      week: { BrowserIntl.localWeekInfo(locale: $0) }
    )
    _TextHost.formatNumber = { BrowserText.formatNumber($0, options: $1) }
    _TextHost.fold = { BrowserText.fold($0, diacritics: $1, case: $2) }
    var environment = configuration.rootEnvironment
    if environment.navigationHistory == nil { environment.navigationHistory = BrowserHistoryAdapter() }
    if environment._geometryHint == nil, let viewport = _embeddedInitialViewport { environment._geometryHint = viewport }
    #if DEBUG
    // Development loop: the page this one replaces may have left the values of its states (StateSnapshot.swift). They are
    // taken once, so a reload the developer asks for starts from the initial values.
    _StateSnapshots.enabled = true
    if let saved = try? _embeddedDevelopmentStorage.get(_embeddedStateSnapshotKey) {
      _StateSnapshots.load(saved)
      try? _embeddedDevelopmentStorage.remove(_embeddedStateSnapshotKey)
    }
    #endif
    // The scene is built once and kept: a live literal written in it cannot be replaced by rendering again.
    _LiveLiterals._startApplication()
    _LiveLiterals.launching = true
    let scene = app.body
    _LiveLiterals.launching = false
    let tree = FiberTree(scene, environment: environment, deferLazyCollections: true, startLifecycle: false)
    _embeddedBrowserTree = tree
    // The host patches the DOM from the published HTML; nothing reads the packed mutations.
    tree._setRecordsPackedMutations(false)
    tree.setExternalInvalidationHandler({
      _embeddedRequestPublish(tree)
    }, deferUpdates: true)
    // Lifecycle tasks and onAppear callbacks must run only after the browser
    // host has installed its scheduler and external commit callback.
    tree._startLifecycle()
    _embeddedBrowserEnvironment = environment
    _embeddedBrowserApplyEnvironment = { environment in
      // Update the retained root instead of evaluating `app.body` again.
      // View values rebuilt outside the active render pass can recreate
      // @State with its defaults and turn a resize/tab switch into a logout.
      _ = tree._updateEnvironmentForRenderer(environment)
    }
    _embeddedBrowserStorageObservation = BrowserWebStorage.observeChanges(namespace: "swiftuiweb") { change in
      let scope: StorageScope = change.scope == .local ? .app : .scene
      StorageRuntime.invalidateCache(scope: scope, key: change.key)
      if let liveTree = _embeddedBrowserTree { _embeddedBrowserPublish(liveTree) }
    }
    // The page was opened at an address: apply it before the first publication and before the lazy collections are sized (the route can replace them), so the first frame already shows the
    // requested screen instead of the declared default followed by a switch. A TabView selection comes from `?tab-selection=`;
    // a deep link reaches `onOpenURL`, as a URL launch does on Apple platforms. A history entry that carries a typed
    // NavigationStack snapshot owns the route, so the path is not replayed over it.
    if let location = _embeddedEnvironmentValue("SWIFTUIWEB_INITIAL_LOCATION") {
      BrowserHistoryAdapter.embeddedLocation(location)
      if _embeddedEnvironmentValue("SWIFTUIWEB_INITIAL_NAVIGATION_STATE") == nil, _embeddedIsDeepLink(location) {
        tree.dispatch(event: "openURL", value: location)
      }
    }
    for info in tree._lazyCollections() {
      let initialCount = min(info.descriptor.count, max(1, info.descriptor.laneCount) * 32)
      if initialCount > 0 {
        _ = tree._materializeLazyCollection(ownerIdentity: info.ownerIdentity, indices: Array(0..<initialCount), beforeExtent: 0, afterExtent: Double((max(0, info.descriptor.count - initialCount) + max(1, info.descriptor.laneCount) - 1) / max(1, info.descriptor.laneCount)) * info.descriptor.estimatedExtent)
      }
    }
    _HeadlessMedia.requestPublish = { if let live = _embeddedBrowserTree { _embeddedRequestPublishForMedia(live) } }
    // The system action of `OpenURLAction` opens the URL in a new window, as the browser does for a link.
    _OpenURLSystem.open = { url in BrowserWindow.open(url.absoluteString) }
    _embeddedBrowserPublish(tree)
  }

  /// Advances the browser-owned Swift Concurrency executor. The generated
  /// application entry point exports this as a small host callback; apps do
  /// not need to know that Embedded Swift uses an event-loop executor.
  static func embeddedBrowserDrainTasks() -> UInt32 {
    _embeddedBatchedEntry { _EmbeddedBrowserExecutor.shared.drain() }
  }

  /// C/WASM response trampoline retained by the generated application entry
  /// point. BrowserIO owns the pending-operation table; the app never calls
  /// this method directly.
  static func embeddedBrowserIOReceive(_ id: UInt32, status: Int32, _ pointer: UnsafePointer<UInt8>?, count: UInt32) {
    _embeddedBatchedEntry { _swiftUIWebReceiveIO(id, status, pointer, count) }
  }

  static func embeddedBrowserDispatch(_ id: UInt32, eventCode: UInt32) {
    defer { _embeddedEventValueClear() }
    guard let tree = _embeddedBrowserTree, let node = _embeddedBrowserEventNodes[id] else { return }
    let event: String
    switch eventCode {
    case 1: event = "click"
    case 2: event = "submit"
    case 3: event = "change"
    case 4: event = "input"
    case 5: event = "focus"
    case 6: event = "blur"
    default: return
    }
    if node.events[event]?.valueAction != nil {
      let value = _embeddedEventValueString()
      tree.dispatch(event: event, value: value, on: node)
    } else {
      tree.dispatch(event: event, on: node)
    }
    _embeddedEventValueClear()
    _embeddedRequestPublish(tree)
  }

  /// Returns 1 when a handler reported the event as handled (currently
  /// `onKeyPress` returning `.handled`), so the host can stop propagation and
  /// suppress the browser default synchronously; 0 otherwise.
  @discardableResult
  static func embeddedBrowserDispatchNamed(_ id: UInt32, nameLength: UInt32) -> UInt32 {
    defer { _embeddedEventValueClear() }
    guard let tree = _embeddedBrowserTree, let node = _embeddedBrowserEventNodes[id] else { return 0 }
    let count = min(Int(nameLength), _embeddedEventValueCount())
    let event = _embeddedEventValueString(limit: count)
    let value = _embeddedEventValueString(dropFirst: count)
    guard !event.isEmpty, node.events[event] != nil else { return 0 }
    let handled: Bool
    if event == "keyPress" {
      let (press, enclosing) = _KeyPressDispatch._splitEnclosingHandlers(value)
      handled = tree.dispatchKeyPress(press, on: node, enclosing: enclosing.compactMap { _embeddedBrowserEventNodes[$0] })
    } else {
      _ = _KeyPressDispatch._consumeHandled()
      if node.events[event]?.valueAction != nil { tree.dispatch(event: event, value: value, on: node) }
      else { tree.dispatch(event: event, on: node) }
      handled = _KeyPressDispatch._consumeHandled()
    }
    // A handler that wrote nothing (a key press every handler ignored, a report equal to the last one) leaves nothing
    // to render: publishing anyway rendered and sent the whole page again, once per key down and once per key up.
    if tree._hasPendingInvalidation || ScrollViewRuntime.lastRequest != nil { _embeddedRequestPublish(tree) }
    return handled ? 1 : 0
  }

  /// Events sent between `begin` and `end` update the tree one by one and publish once, when the last batch ends.
  /// The host brackets its post-commit measurement reports (geometry, layout proposals) this way.
  static func embeddedBrowserBatchBegin() { _embeddedEntryDepth += 1 }
  static func embeddedBrowserBatchEnd() {
    guard _embeddedEntryDepth > 0 else { return }
    _embeddedEntryDepth -= 1
    if _embeddedEntryDepth == 0, _embeddedPublishRequested {
      _embeddedPublishRequested = false
      if let tree = _embeddedBrowserTree { _embeddedBrowserPublish(tree) }
    }
  }

  static func embeddedBrowserTimelineTick() {
    guard let tree = _embeddedBrowserTree else { return }; _ = tree._hostTimelineTick(); _embeddedBrowserPublish(tree)
  }

  static func embeddedBrowserLazyCollectionCount() -> UInt32 { UInt32(_embeddedBrowserTree?._lazyCollections().count ?? 0) }
  static func embeddedBrowserLazyItemCount(_ collection: UInt32) -> UInt32 {
    guard let tree = _embeddedBrowserTree else { return 0 }; let infos = tree._lazyCollections(); let index = Int(collection)
    guard infos.indices.contains(index) else { return 0 }; return UInt32(infos[index].descriptor.count)
  }
  static func embeddedBrowserLazyEstimatedExtent(_ collection: UInt32) -> Double {
    guard let tree = _embeddedBrowserTree else { return 44 }; let infos = tree._lazyCollections(); let index = Int(collection)
    guard infos.indices.contains(index) else { return 44 }; return infos[index].descriptor.estimatedExtent
  }
  static func embeddedBrowserLazyWindow(_ collection: UInt32, start: UInt32, count: UInt32, before: Double, after: Double) {
    guard let tree = _embeddedBrowserTree else { return }; let infos = tree._lazyCollections(); let ci = Int(collection)
    guard infos.indices.contains(ci) else { return }; let info = infos[ci], lower = min(Int(start), info.descriptor.count), upper = min(info.descriptor.count, lower + Int(count))
    _ = tree._materializeLazyCollection(ownerIdentity: info.ownerIdentity, indices: Array(lower..<upper), beforeExtent: max(0, before), afterExtent: max(0, after))
    // The host asks for the window again after every commit that touches the collection. When the rows it
    // materializes are the ones already published, nothing in the tree changed in this epoch; publishing anyway
    // only re-sent the same tree in its other form (kept subtrees as placeholders), a commit that changed no DOM.
    // Flush first: a row that writes state while it materializes only marks the tree once pending invalidations run.
    // Materialization reconciles from the collection's owner, whose version does not reach the root, so both count.
    _ = tree.renderNode
    let ownerChanged = (tree.fiber(at: info.ownerIdentity)?.version ?? tree._epoch) >= tree._epoch
    guard ownerChanged || tree.root.version >= tree._epoch || ScrollViewRuntime.lastRequest != nil else { return }
    _embeddedBrowserPublish(tree)
  }

  /// The worker's cookie mirror was replaced (another tab or a response changed the jar): tell observers, then let the
  /// view tree re-render from whatever they read back through `HTTPCookieStorage`.
  /// Live literals: the pending event value holds the replacements (`_LiveLiterals._apply`). Returns how
  /// many were taken.
  static func embeddedBrowserLiveLiterals() -> UInt32 {
    let taken = _LiveLiterals._apply(_embeddedEventValueString())
    _embeddedEventValueClear()
    if taken > 0, let tree = _embeddedBrowserTree {
      _ = tree._liveLiteralsChanged()
      _embeddedBrowserPublish(tree)
    }
    // A replacement the page could not use (a literal of a type without a live form): the page script reads this key when
    // the build ends and reloads (Tools/live-reload.mjs). Storage, because the worker cannot answer the call.
    if _LiveLiterals._takeUnapplied() {
      try? BrowserWebStorage(.session, namespace: "swiftuiweb.dev").set("1", forKey: "literals-stale")
    }
    return UInt32(taken)
  }

  /// Development loop: writes the states of the page that can be kept across a reload to the session's storage, where
  /// the module that replaces this one reads them when it starts. Returns how many characters it wrote; 0 in a release
  /// build, which has none of this.
  static func embeddedBrowserStateSave() -> UInt32 {
    #if DEBUG
    guard let tree = _embeddedBrowserTree else { return 0 }
    let text = tree._stateSnapshotText()
    do { try _embeddedDevelopmentStorage.set(text, forKey: _embeddedStateSnapshotKey) } catch { return 0 }
    return UInt32(truncatingIfNeeded: text.utf8.count) &+ 1
    #else
    return 0
    #endif
  }

  static func embeddedBrowserCookiesChanged() {
    NotificationCenter.default._post(name: .NSHTTPCookieManagerCookiesChanged, sender: HTTPCookieStorage.shared)
    CookieJarRuntime.notifyChanged()
    if let tree = _embeddedBrowserTree {
      _ = tree._hostTimelineTick()
      _embeddedBrowserPublish(tree)
    }
  }

  static func embeddedBrowserHistoryAcknowledge(_ sequence: UInt32) { BrowserHistoryAdapter.embeddedAcknowledge(sequence) }
  static func embeddedBrowserHistoryLocation() {
    let url = _embeddedEventValueString()
    _embeddedEventValueClear()
    // A location notification can update a typed TabView selection through
    // its history observer. History is a structural boundary, so force one
    // retained-root reconciliation even when the source graph coalesced the
    // binding write with the preceding click commit. The page reports the
    // location after every tab URL Swift pushed, which names the tab already
    // shown: that report selects nothing, and the root pass reconciled the
    // whole tree (about a third of a section change in a large app) for nothing.
    guard BrowserHistoryAdapter.embeddedLocation(url), let tree = _embeddedBrowserTree else { return }
    _ = tree._hostTimelineTick()
    _embeddedBrowserPublish(tree)
  }
  static func embeddedBrowserHistoryRestore() {
    let key = _embeddedEventValueString()
    _embeddedEventValueClear()
    BrowserHistoryAdapter.embeddedRestore(key)
    if let tree = _embeddedBrowserTree {
      _ = tree._hostTimelineTick()
      _embeddedBrowserPublish(tree)
    }
  }

  static func embeddedBrowserViewport(_ width: Double, height: Double, dark: UInt32, reducedMotion: UInt32) {
    // Kept before the tree exists too: the page reports its viewport once at start, and the first rows of a lazy
    // collection are sized from it.
    if height.isFinite, height > 0 { _embeddedViewportHeight = height }
    guard width.isFinite, height.isFinite, width > 0, height > 0 else { return }
    guard let tree = _embeddedBrowserTree else {
      _embeddedInitialViewport = CGSize(width: width, height: height)
      return
    }
    tree._setRootLayoutProposal(ProposedViewSize(width: width, height: height))
    let colorScheme = dark == 1 ? ColorScheme.dark : ColorScheme.light
    let reduceMotion = reducedMotion == 1
    let preferencesChanged = ColorSchemeRuntime.current != colorScheme || AccessibilityRuntime.reduceMotion != reduceMotion
    ColorSchemeRuntime.install(colorScheme)
    AccessibilityRuntime.install(reduceMotion: reduceMotion)
    // ResizeObserver fires for ordinary geometry changes. Only reevaluate
    // environment readers when a media preference really changed; never write
    // those values into the typed dictionary during a resize callback.
    if preferencesChanged { _ = tree._hostTimelineTick() }
    _embeddedBrowserPublish(tree)
  }

  /// `flags`: 1 reduced motion, 32 publications with a reference
  /// encoding of the same tree attached (see `_embeddedBinaryVerify`), 64 no shapes. 8 and 16 are retired (they chose the HTML transport), and so is 2 (CSS layout worked out by Swift).
  static func embeddedBrowserSetInitialPreferences(dark: UInt32, reducedMotion flags: UInt32) {
    ColorSchemeRuntime.install(dark == 1 ? .dark : .light)
    AccessibilityRuntime.install(reduceMotion: flags & 1 == 1)
    _embeddedBinaryVerify = flags & 32 == 32
    _embeddedBinaryShapesEnabled = flags & 64 == 0
    // Tuning, from the page (window.__binaryShapeInstances, window.__binaryShapeElements): bits 8 to 11 and 12 to 15, 0 for the default.
    _embeddedBinaryShapeTuning = (Int(flags >> 8 & 15), Int(flags >> 12 & 15))
  }

  static func embeddedBrowserAcknowledgeScroll(_ sequence: UInt32) {
    if _embeddedPendingScroll?.3 == sequence { _embeddedPendingScroll = nil }
  }

  /// Materialize a virtual target by semantic ID, rather than guessing that
  /// the requested ID is an array index. The following DOM commit performs
  /// the scroll inside the actual owning ScrollView.
  static func embeddedBrowserPrepareScrollTarget() -> UInt32 {
    defer { _embeddedEventValueClear() }
    guard let tree = _embeddedBrowserTree else { return 0 }
    let requested = _embeddedEventValueString()
    for info in tree._lazyCollections() {
      for index in 0..<info.descriptor.count {
        if fiberKeyDescription(info.descriptor.keyAt(index)) != requested { continue }
        let lanes = max(1, info.descriptor.laneCount)
        let lower = max(0, index / lanes - 8) * lanes
        let upper = min(info.descriptor.count, lower + 32 * lanes)
        let extent = info.descriptor.estimatedExtent
        _ = tree._materializeLazyCollection(ownerIdentity: info.ownerIdentity, indices: Array(lower..<upper), beforeExtent: Double(lower / lanes) * extent, afterExtent: Double((max(0, info.descriptor.count - upper) + lanes - 1) / lanes) * extent)
        _embeddedBrowserPublish(tree)
        return 1
      }
    }
    return 0
  }

  static func embeddedBrowserEventValueReset() { _embeddedEventValueClear() }
  static func embeddedBrowserEventValuePush(_ byte: UInt32) { _embeddedBrowserEventValueBytes.append(UInt8(truncatingIfNeeded: byte)) }

  /// Bulk replacement for `event_value_reset` + `event_value_push` per byte:
  /// the host asks for room, writes its bytes there, then commits the length.
  /// Returns the borrowed address (valid until the next alloc), or 0 when the
  /// request is refused, in which case the host falls back to the byte path.
  static func embeddedBrowserEventValueAlloc(_ length: UInt32) -> UInt32 {
    guard _embeddedBrowserEventValueInput.reserve(Int(length)) != nil else { return 0 }
    return _embeddedBrowserEventValueInput.address
  }

  /// Makes the first `length` bytes written after `event_value_alloc` the
  /// pending event value. The staging area is wiped (it may hold a password)
  /// and shrunk when the event that consumes the value finishes.
  static func embeddedBrowserEventValueCommit(_ length: UInt32) {
    _embeddedBrowserEventValueBytes.removeAll(keepingCapacity: true)
    _embeddedBrowserEventValueInput.commit(Int(length))
    // The value is read in place from the staging buffer (one copy, into the
    // String); the buffer is wiped and shrunk when the event finishes.
    _embeddedBrowserEventValueStaged = _embeddedBrowserEventValueInput.count > 0
  }

  /// Resolve a non-sensitive structural SecureField identifier into its live
  /// value. The host clears the returned buffer immediately after assigning
  /// the DOM property, so credentials never enter HTML or _RenderNode markup.
  static func embeddedBrowserSecureValue() -> UInt32 {
    let id = _embeddedEventValueString()
    defer { _embeddedEventValueClear() }
    guard let node = _embeddedBrowserSecureNodes[id], node.attributes["data-control-kind"] == "secure-field" else {
      _embeddedBrowserClearSecureValue()
      return 0
    }
    if let secureValue = node._secureValue {
      _embeddedBrowserSetSecureValue(secureValue())
    } else if let binding = node.leafBindings.first(where: { $0.operation == .property("value") }) {
      _embeddedBrowserSetSecureValue(binding.value())
    } else {
      _embeddedBrowserClearSecureValue()
    }
    return UInt32(_embeddedBrowserSecureValueCount)
  }

  /// Borrowed address of the value `secure_value` just resolved (its length is
  /// the return value of that call); valid until `secure_value_reset` or the
  /// next `secure_value`. The host copies it out and then resets.
  static func embeddedBrowserSecureValuePointer() -> UInt32 {
    guard let buffer = _embeddedBrowserSecureValueBuffer else { return 0 }
    return UInt32(truncatingIfNeeded: UInt(bitPattern: buffer))
  }

  /// Writes the ids of the SecureFields in the newest publication, newline
  /// separated, and returns the byte count; `secure_ids_pointer` is its address.
  /// Lets the worker host skip decoding the whole HTML snapshot to find them.
  static func embeddedBrowserSecureIDsLength() -> UInt32 {
    var bytes: [UInt8] = []
    for id in _embeddedBrowserSecureNodes.keys.sorted() {
      if !bytes.isEmpty { bytes.append(10) }
      bytes.append(contentsOf: id.utf8)
    }
    _embeddedBrowserSecureIDsOutput.store(bytes)
    return UInt32(_embeddedBrowserSecureIDsOutput.count)
  }

  static func embeddedBrowserSecureIDsPointer() -> UInt32 { _embeddedBrowserSecureIDsOutput.address }

  static func embeddedBrowserSecureValueReset() { _embeddedBrowserClearSecureValue() }
  static func embeddedBrowserSecureValueByte(_ index: UInt32) -> UInt32 {
    let offset = Int(index)
    guard offset >= 0, offset < _embeddedBrowserSecureValueCount, let buffer = _embeddedBrowserSecureValueBuffer else { return 0 }
    return UInt32(buffer[offset])
  }


  static func embeddedBrowserWebMountReconcile() { WebMountRegistry.shared.reconcileEmbedded() }

  /// Sequence number of the newest publication (the one in the HTML buffer).
  static func embeddedBrowserPublishSequence() -> UInt32 { _embeddedPublishSequence }

  /// The host committed the publication `sequence`: everything it covered is
  /// now in the DOM and may be replaced by placeholders from here on.
  static func embeddedBrowserPublishAcknowledge(_ sequence: UInt32) {
    guard let index = _embeddedPublishPending.firstIndex(where: { $0.sequence == sequence }) else { return }
    _embeddedPublishAckedEpoch = max(_embeddedPublishAckedEpoch, _embeddedPublishPending[index].epoch)
    _embeddedPublishPending.removeFirst(index + 1)
  }

  /// The host found a placeholder it could not honor: forget what it holds and
  /// publish everything again.
  static func embeddedBrowserPublishFull() {
    _embeddedPublishAckedEpoch = 0
    _embeddedBinaryShapes?.reset()
    _embeddedPublishPending.removeAll(keepingCapacity: true)
    if let tree = _embeddedBrowserTree { _embeddedBrowserPublish(tree) }
  }
  static func embeddedBrowserHTMLLength() -> UInt32 { UInt32(_embeddedBrowserHTMLCount) }

  /// Borrowed output pointer, stable until the next dispatch/publish. The host
  /// copies UTF-8 synchronously and refreshes memory.buffer after WASM calls.
  static func embeddedBrowserHTMLPointer() -> UInt32 {
    guard let buffer = _embeddedBrowserHTMLBuffer else { return 0 }
    return UInt32(truncatingIfNeeded: UInt(bitPattern: buffer))
  }

  static func embeddedBrowserHTMLByte(_ index: UInt32) -> UInt32 {
    let offset = Int(index)
    guard offset < _embeddedBrowserHTMLCount, let buffer = _embeddedBrowserHTMLBuffer else { return 0 }
    return UInt32(buffer[offset])
  }

  /// Read-only Fiber counters for browser benchmarks. Values are indexed so
  /// the Embedded ABI stays scalar and does not serialize a second UI model.
  static func embeddedBrowserFiberMetric(_ index: UInt32) -> UInt32 {
    guard let metrics = _embeddedBrowserTree?.metrics else { return 0 }
    let value: Int
    switch index {
    case 0: value = metrics.bodyEvaluations
    case 1: value = metrics.renderNodeAllocations
    case 2: value = metrics.structuralNodeVisits
    case 3: value = metrics.reconciliationOperations
    case 4: value = metrics.invalidatedOwners
    case 5: value = metrics.invalidatedNodes
    case 6: value = metrics.reconciledNodes
    case 7: value = metrics.schedulerInvalidations
    case 8: value = metrics.schedulerLeafFlushes
    case 9: value = metrics.schedulerStructuralFlushes
    case 10: value = metrics.schedulerSubtreeFlushes
    case 11: value = metrics.domOperations
    case 12: value = metrics.bridgeBatches
    case 13: value = metrics.bridgeCommands
    case 14: value = metrics.publishedObservationTargets
    case 15: value = metrics.publishedObservationRouteMisses
    case 16: value = metrics.stateOwnerRouteMisses
    case 17: value = metrics.deferredRootPasses
    case 18: value = metrics.leafRootPasses
    case 19: value = metrics.observationRootPasses
    case 20: value = metrics.externalRootPasses
    case 21: value = metrics.nestedChangeRootFallbacks
    case 22: value = metrics.ownerRouteRootFallbacks
    case 23: value = metrics.subtreeOwnerInvalidations
    case 24: value = metrics.subtreeTargetPathDepthTotal
    case 25: value = metrics.subtreeTargetRenderNodeCount
    case 26: value = metrics.staleSubtreeRendererFallbacks
    case 27: value = metrics.staleSubtreeOwnerTokens
    case 28: value = metrics.publishedObservationGroupsUnavailable
    case 29: value = metrics.publishedObservationSourceCountMismatches
    case 30: value = metrics.publishedObservationGroupsWithoutActiveOwners
    case 31: value = metrics.publishedObservationUnresolvedOwnerTokens
    case 32: value = metrics.publishedObservationOwnerPathsUnavailable
    case 33: value = metrics.publishedObservationOwnerPathsNotMounted
    case 34: value = metrics.publishedObservationOwnerPathRemaps
    case 35...39: value = Int(_embeddedPublishPhaseMicroseconds[Int(index) - 35])
    case 40...49: value = Int(clamping: _embeddedPublishCounters[Int(index) - 40])
    default: value = 0
    }
    return UInt32(clamping: value)
  }
}
#endif

public extension BrowserApp {
  static func _launch(_ app: Self, with configuration: _AppConfiguration) {
    BrowserAppLauncher.launch(app, configuration: configuration)
  }

  /// Browser applications can use the same internal App title hook as other
  /// SwiftUIWeb hosts. The JavaScript/DOM detail stays in this adapter.
  static func _setTitle(_ title: String) {
    AppTitleRuntime.set(title)
    _ = title
  }
}
