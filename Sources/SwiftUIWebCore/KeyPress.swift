/// A key press delivered to `onKeyPress` handlers, matching SwiftUI's value.
@_spi(Renderer) import SwiftUIWebTransferable
public struct KeyPress: Sendable {
  public struct Phases: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let down = Phases(rawValue: 1 << 0)
    public static let `repeat` = Phases(rawValue: 1 << 1)
    public static let up = Phases(rawValue: 1 << 2)
    public static let all: Phases = [.down, .repeat, .up]
  }

  public enum Result: Hashable, Sendable {
    /// Stops propagation to ancestor handlers and suppresses the browser's
    /// default action for the key.
    case handled
    /// Lets the next enclosing handler (and the browser) process the key.
    case ignored
  }

  public let phase: Phases
  public let key: KeyEquivalent
  public let characters: String
  public let modifiers: EventModifiers

  package init(phase: Phases, key: KeyEquivalent, characters: String, modifiers: EventModifiers) {
    self.phase = phase
    self.key = key
    self.characters = characters
    self.modifiers = modifiers
  }

  /// Decodes the browser host payload `phase\tkey\tmodifierBits`, ignoring the enclosing handlers the host may name after
  /// it (see `_KeyPressDispatch._splitEnclosingHandlers`).
  @_spi(Renderer) public init?(_webPayload payload: String) {
    let fields = payload.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
    guard fields.count == 3 || fields.count == 4, let key = KeyEquivalent(_webKey: fields[1]) else { return nil }
    let phase: Phases
    switch fields[0] {
    case "down": phase = .down
    case "repeat": phase = .repeat
    case "up": phase = .up
    default: return nil
    }
    let characters = fields[1].count == 1 ? fields[1] : (key == .return ? "\r" : key == .tab ? "\t" : key == .escape ? "\u{1B}" : "")
    self.init(phase: phase, key: key, characters: characters, modifiers: EventModifiers(rawValue: Int(fields[2]) ?? 0))
  }
}

/// Result channel between a key-press handler and the browser host. The
/// press goes from the focused element outward and stops at the first
/// `.handled` result.
@_spi(Renderer) public enum _KeyPressDispatch {
  private static let handledFlag = _Locked(false)
  static var handled: Bool {
    get { handledFlag.withLock { $0 } }
    set { handledFlag.withLock { $0 = newValue } }
  }
  /// Returns and clears whether the last dispatched event was handled.
  public static func _consumeHandled() -> Bool {
    defer { handled = false }
    return handled
  }

  /// Splits the browser payload `phase\tkey\tmodifierBits\tid,id` into the press and the event ids of the enclosing
  /// handlers the host names after it, innermost first. The host sends one call for the whole walk: a Swift worker cannot
  /// answer which handler took the press in time for the host to stop.
  public static func _splitEnclosingHandlers(_ payload: String) -> (press: String, enclosing: [UInt32]) {
    var tabs = 0
    for index in payload.indices where payload[index] == "\t" {
      tabs += 1
      guard tabs == 3 else { continue }
      let enclosing = payload[payload.index(after: index)...].split(separator: ",").compactMap { UInt32($0) }
      return (String(payload[..<index]), enclosing)
    }
    return (payload, [])
  }
}

package nonisolated struct OnKeyPressModifier: ViewModifier {
  let phases: KeyPress.Phases
  let matches: (KeyPress) -> Bool
  let action: (KeyPress) -> KeyPress.Result

  @_spi(Renderer) public init(
    phases: KeyPress.Phases,
    matches: @escaping (KeyPress) -> Bool,
    action: @escaping (KeyPress) -> KeyPress.Result
  ) {
    self.phases = phases
    self.matches = matches
    self.action = action
  }

  @MainActor public func _apply(to node: _RenderNode, context: inout _RenderContext) {
    // Disabled views do not receive key presses.
    guard context.environment.isEnabled else { return }
    let handler: (KeyPress) -> Bool = { press in
      guard phases.contains(press.phase), matches(press) else { return false }
      return action(press) == .handled
    }
    Self.install(handler, on: node)
  }

  @MainActor private static func install(_ handler: @escaping (KeyPress) -> Bool, on node: _RenderNode) {
    // Fragments have no DOM host; the focused descendant still bubbles to
    // each rendered child that carries the handler.
    if case .fragment = node.kind {
      for child in node.children { install(handler, on: child) }
      return
    }
    // Several `onKeyPress` modifiers can land on one element. The inner
    // (earlier) handler sees the press first, as in SwiftUI.
    let inner = node.events["keyPress"]?.valueAction
    node.events["keyPress"] = _EventHandler(name: "keyPress", action: { raw in
      if let inner {
        inner(raw)
        if _KeyPressDispatch.handled { return }
      }
      guard let press = KeyPress(_webPayload: raw) else { return }
      if handler(press) { _KeyPressDispatch.handled = true }
    })
  }
}

public extension View {
  /// Performs `action` when `key` is pressed (down or repeat) while this view
  /// or one of its descendants has focus.
  nonisolated func onKeyPress(_ key: KeyEquivalent, action: @escaping () -> KeyPress.Result) -> some View {
    modifier(OnKeyPressModifier(phases: [.down, .repeat], matches: { $0.key == key }, action: { _ in action() }))
  }
  nonisolated func onKeyPress(
    _ key: KeyEquivalent,
    phases: KeyPress.Phases,
    action: @escaping (KeyPress) -> KeyPress.Result
  ) -> some View {
    modifier(OnKeyPressModifier(phases: phases, matches: { $0.key == key }, action: action))
  }
  nonisolated func onKeyPress(
    keys: Set<KeyEquivalent>,
    phases: KeyPress.Phases = [.down, .repeat],
    action: @escaping (KeyPress) -> KeyPress.Result
  ) -> some View {
    modifier(OnKeyPressModifier(phases: phases, matches: { keys.contains($0.key) }, action: action))
  }
  nonisolated func onKeyPress(
    phases: KeyPress.Phases = [.down, .repeat],
    action: @escaping (KeyPress) -> KeyPress.Result
  ) -> some View {
    modifier(OnKeyPressModifier(phases: phases, matches: { _ in true }, action: action))
  }
}
