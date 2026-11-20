/// SwiftUI's geometry proxy. Frames come from the last host measurement of
/// the view (see GeometryMeasurement.swift); native/static rendering keeps
/// the deterministic zero-size fallback until a host reports a measurement.
public struct GeometryProxy: Sendable {
  public let size: CGSize
  public let safeAreaInsets: EdgeInsets
  let _measurement: _GeometryMeasurement
  let _access: _GeometryProxyAccess?

  /// Compatibility initializer. `bounds` is the view's frame in global
  /// coordinates; without it the view is placed at the global origin.
  package init(size: CGSize = _SwiftUIWebGeometryDefaults.zeroSize, safeAreaInsets: EdgeInsets = EdgeInsets(), bounds: CGRect? = nil) {
    let origin = bounds?.origin ?? _SwiftUIWebGeometryDefaults.zeroPoint
    let box = _GeometryBox(x: Double(origin.x), y: Double(origin.y), width: Double(size.width), height: Double(size.height))
    self.init(measurement: _GeometryMeasurement(box: box), safeAreaInsets: safeAreaInsets)
  }

  package init(measurement: _GeometryMeasurement, safeAreaInsets: EdgeInsets = EdgeInsets(), access: _GeometryProxyAccess? = nil) {
    size = measurement.size
    self.safeAreaInsets = safeAreaInsets
    _measurement = measurement
    _access = access
  }

  /// The view's frame in `coordinateSpace`: `.local` has a zero origin,
  /// `.global` is the window frame, and a named or `.scrollView` space is
  /// relative to the nearest matching ancestor (global when none matches).
  @_disfavoredOverload public func frame(in coordinateSpace: CoordinateSpace) -> CGRect {
    let space = coordinateSpace._geometrySpace
    if space != .local { _access?.readsPosition = true }
    return _measurement.frame(in: space)
  }

  public func frame(in coordinateSpace: some CoordinateSpaceProtocol) -> CGRect {
    frame(in: coordinateSpace.coordinateSpace)
  }

  /// The bounds of `coordinateSpace` converted into this view's local
  /// coordinates, or nil when no such ancestor space exists.
  public func bounds(of coordinateSpace: NamedCoordinateSpace) -> CGRect? {
    _access?.readsPosition = true
    return _measurement.bounds(of: coordinateSpace.coordinateSpace._geometrySpace)
  }
}

/// Records whether a proxy consumer depends on the view's position. Hosts
/// only re-measure such views while an ancestor scrolls or the window moves.
final package class _GeometryProxyAccess: @unchecked Sendable {
  package var readsPosition = false
  package init() {}
}

/// Retained per-reader storage: the newest host measurement and the one the
/// content was last evaluated with. Mutating it never invalidates the view.
final class _GeometryReaderStore {
  var latest = _GeometryMeasurement.zero
  var rendered = _GeometryMeasurement.zero
  var readsPosition = false
  /// Set once the host has reported this reader's real box.
  var hasHostMeasurement = false
}

private enum GeometryHintEnvironmentKey: EnvironmentKey {
  static let defaultValue: CGSize? = nil
}

extension EnvironmentValues {
  /// The size of the nearest enclosing `GeometryReader`. A nested reader that
  /// the host has not measured yet is proposed this size, as SwiftUI proposes
  /// its parent's space in the same layout pass; without it the first
  /// evaluation runs at zero and is replaced as soon as the host measures. At
  /// the root, a browser session sets it to the window, which encloses the
  /// application's outermost readers.
  package var _geometryHint: CGSize? {
    get { self[GeometryHintEnvironmentKey.self] }
    set { self[GeometryHintEnvironmentKey.self] = newValue }
  }
}

public nonisolated struct GeometryReader<Content: View>: View, _OwnerBoundaryContent {
  public typealias Body = Never
  public let content: (GeometryProxy) -> Content
  @State(memberID: 196385298) private var store = _GeometryReaderStore()
  public nonisolated init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) { self.content = content }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    // The reader is its own render owner with its own state scope: a new host
    // measurement invalidates only this reader's content, as in SwiftUI, not
    // the view that happens to contain it (or the whole root).
    AnyView(_ownerBoundaryOf: self)._render(in: context)
  }

  @MainActor package func _renderOwnerBoundary(in context: _RenderContext) -> _RenderNode { _renderReader(in: context) }

  @MainActor private func _renderReader(in context: _RenderContext) -> _RenderNode {
    let previousScope = StateRuntime.scope
    StateRuntime.scope = StateScope(context: context, viewTag: "GeometryReader")
    defer { StateRuntime.scope = previousScope }
    let node = _RenderNode.element("div")
    node.classes = ["geometry-reader"]
    // The browser does not assign 100%-of-an-unspecified-height. The layout
    // accepts the proposal and reports the resolved box after placement.
    node.attributes["data-layout-kind"] = "geometry"
    node.attributes["data-geometry-reader"] = "true"
    // A new host measurement invalidates this reader's own render owner
    // directly (the mechanism Observation uses), so the update never depends
    // on a State source that could be shared with, or attributed to, another
    // owner and force a root pass.
    let ownerToken = context._renderOwnerToken
    if let ownerToken { context._renderOwnerRegistry?._markAliasable(ownerToken) }
    let invalidationStore = context.stateStore
    let readerPath = context._fiberPath
    let store = self.store
    let access = _GeometryProxyAccess()
    var measurement = store.latest
    if !store.hasHostMeasurement, measurement == .zero, let hint = context.environment._geometryHint {
      measurement = _GeometryMeasurement(box: _GeometryBox(x: 0, y: 0, width: Double(hint.width), height: Double(hint.height)))
      store.latest = measurement
    }
    var contentContext = context.child(_FiberKey("content"))
    if measurement.size.width > 0 || measurement.size.height > 0 { contentContext.environment._geometryHint = measurement.size }
    let child = content(GeometryProxy(measurement: measurement, access: access))._render(in: contentContext)
    store.rendered = measurement
    // The size this node's content is drawn for: a measurement reaching it while the reader has since been drawn for another
    // size reached a node that is no longer the reader's drawing, though the page still shows it.
    let drawnSize = measurement.size
    // The size the content was drawn for. With Swift in a worker the page shows a reader it has just inserted only once
    // it is drawn for the size the layout gives it (Tools/embedded-dom.js): the first evaluation runs at the enclosing
    // reader's size or the window's, and showed a page at sizes it never has (Food Truck's donuts at 560 points).
    node.attributes["data-geometry-rendered"] = "\(_layoutNumber(CGFloat(measurement.size.width))),\(_layoutNumber(CGFloat(measurement.size.height)))"
    // Sticky: a proxy captured by a child view may be read by a later,
    // independent body evaluation of that child.
    store.readsPosition = store.readsPosition || access.readsPosition
    // Only content that reads a frame or bounds is re-measured while an
    // ancestor scrolls; size-only readers follow ResizeObserver.
    if store.readsPosition { node.attributes["data-geometry-position"] = "true" }
    // The browser host measures this wrapper after each commit, on resize
    // and (for position readers) on ancestor scroll, and reports through the
    // ordinary value-event channel.
    node.events["geometry"] = _EventHandler(name: "geometry", action: { rawValue in
      guard let next = _GeometryMeasurement(decoding: rawValue) else { return }
      store.latest = next
      store.hasHostMeasurement = true
      let rendered = store.rendered
      // Shown although the reader was drawn again since: a remembered render above brought this node back (a custom
      // Layout renders its subviews again to measure them, under other owners), and Food Truck's tiles showed donuts
      // drawn for 23 points in 155-point boxes, which the page measured again and again in vain.
      let stale = drawnSize != rendered.size
      let visible = stale || next.size != rendered.size
        || ((store.readsPosition || access.readsPosition) && next != rendered)
      guard visible else { return }
      store.rendered = next
      // What the views above remembered holds this reader as it was drawn.
      if stale || next.size != rendered.size { invalidationStore._forgetViews(above: readerPath) }
      if let ownerToken { invalidationStore._ownerObservationDidChange(ownerToken) }
    })
    node.children = child.isEmpty ? [] : [child]
    return node
  }
}

/// What the page last measured for a view, kept by the modules above this one (a `visualEffect` makes its effect from it in
/// every render): equal when nothing a proxy can report changed.
package struct _MeasuredGeometry: Equatable, Sendable {
  let measurement: _GeometryMeasurement
  /// A proxy of the measurement.
  package var proxy: GeometryProxy { GeometryProxy(measurement: measurement) }
}

package extension GeometryProxy {
  /// What this proxy reports, to keep.
  var _measured: _MeasuredGeometry { _MeasuredGeometry(measurement: _measurement) }
}
