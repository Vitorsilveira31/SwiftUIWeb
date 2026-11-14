/// A view that skips its content's body when the content is equal to what it rendered last time, as SwiftUI's
/// `EquatableView` does. Typically produced by `.equatable()` on a view that conforms to `Equatable`:
///
///     ForEach(rows) { row in RowView(row: row).equatable() }
///
/// The previous result is reused when, at the same structural position:
/// - the content compares equal (`==`) to the content rendered last time;
/// - every environment value the content read holds the same value (a `Hashable` value is compared by hash; any
///   other value always counts as changed);
/// - the content read no state, observable model or binding: such a body depends on more than its value, so it
///   is rendered every time.
public nonisolated struct EquatableView<Content: View & Equatable>: View {
  public typealias Body = Never
  public var content: Content

  public nonisolated init(content: Content) {
    self.content = content
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    guard _EquatableViewReuse.enabled, !context._speculative, let registry = context._renderOwnerRegistry else {
      return content._render(in: context)
    }
    if let memo = registry._memoized(at: context._fiberPath, content: content, environment: context.environment) {
      // An enclosing EquatableView depends on what this content read, though it was not read again.
      EnvironmentValues._readRecorder?.merge(memo.reads)
      return memo.node
    }
    let recorder = _EnvironmentReadRecorder()
    let enclosing = EnvironmentValues._readRecorder
    EnvironmentValues._readRecorder = recorder
    // The content's deferred parts record into this recorder too (they install it when they run), and the decision
    // waits for them: it is taken when the pass has rendered everything the content queued.
    _RenderStaging.enterStage()
    let node = content._render(in: context)
    _RenderStaging.exitStage()
    EnvironmentValues._readRecorder = enclosing
    let value = content
    let path = context._fiberPath
    _RenderStaging.settled {
      enclosing?.merge(recorder)
      if !recorder.untracked && recorder.stateReads == 0 {
        registry._memoize(at: path, content: value, reads: recorder.reads, node: node)
      }
    }
    return node
  }
}

public extension View where Self: Equatable {
  /// Skips this view's body while it is equal to the value it last rendered (see `EquatableView`).
  nonisolated func equatable() -> EquatableView<Self> {
    EquatableView(content: self)
  }
}

/// Whether `EquatableView` reuses results. In the Embedded browser runtime every state and model read goes
/// through the state store, which is how a render that read none is told apart. A native build observes
/// `@Observable` models through Swift's Observation instead, where such a read is not visible here, so reuse is
/// off unless a test turns it on for content that reads no model.
@MainActor @_spi(Renderer) public enum _EquatableViewReuse {
#if canImport(Observation) && !hasFeature(Embedded)
  public static var enabled = false
#else
  public static var enabled = true
#endif
}
