
/// Whether a view that compares its inputs reuses what it rendered (`AnyView._renderReusing`). As for
/// `_EquatableViewReuse`: in the Embedded browser runtime every state and model read goes through the state store, so a
/// reused render is told apart from one that read something that changed; a native build observes `@Observable` models
/// through Swift's Observation, where it is not, so reuse is off there unless a test turns it on.
@MainActor @_spi(Renderer) public enum _ViewReuse {
#if canImport(Observation) && !hasFeature(Embedded)
  public static var enabled = false
#else
  public static var enabled = true
#endif
}
