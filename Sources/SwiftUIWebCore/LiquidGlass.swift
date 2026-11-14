

/// The shape `glassEffect(_:in:)` uses when none is given: a capsule, drawn by the renderer's capsule fast path.
public struct DefaultGlassEffectShape: Shape {
  public typealias Body = Never
  public init() {}
  public nonisolated func path(in rect: CGRect) -> Path { Capsule().path(in: rect) }
}

