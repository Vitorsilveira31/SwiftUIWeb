/// SwiftUI keyboard shortcut. Controls in the modified subtree (Button,
/// Toggle) expose it to the browser host, which triggers the control when the
/// key combination is pressed anywhere in the window.
///
/// Web mapping: `.command` is the Meta (⌘) key on Apple platforms and Ctrl
/// elsewhere; `.control` is Ctrl, `.option` is Alt, `.shift` is Shift. The
/// pressed modifier set must match exactly. Only shortcuts in the topmost
/// presentation (or in the window when nothing is presented) are active, and
/// disabled or hidden controls never fire. While a text-editing control has
/// focus, shortcuts without Command/Control/Option only fire for Escape and
/// for Return from a single-line field; Space/Return on a focused button keep
/// their native activation.
public struct KeyboardShortcut: Hashable, Sendable {
  public struct Localization: Hashable, Sendable {
    let rawValue: String
    public static let automatic = Localization(rawValue: "automatic")
    public static let withoutMirroring = Localization(rawValue: "withoutMirroring")
    public static let custom = Localization(rawValue: "custom")
  }

  public var key: KeyEquivalent
  public var modifiers: EventModifiers
  public var localization: Localization

  public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) {
    self.init(key, modifiers: modifiers, localization: .automatic)
  }

  public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command, localization: KeyboardShortcut.Localization) {
    self.key = key
    self.modifiers = modifiers
    self.localization = localization
  }

  /// Return with no modifiers: the default button of a window or dialog.
  public static let defaultAction = KeyboardShortcut(.return, modifiers: [])
  /// Escape with no modifiers: the cancel button of a window or dialog.
  public static let cancelAction = KeyboardShortcut(.escape, modifiers: [])

  /// `key|modifiers` token read by the browser host.
  @_spi(Renderer) public var _webDescriptor: String { key._webKeyToken + "|" + modifiers._webTokens }

  /// WAI-ARIA `aria-keyshortcuts` spelling.
  var _ariaKeyShortcuts: String {
    var parts: [String] = []
    if modifiers.contains(.command) { parts.append("Meta") }
    if modifiers.contains(.control) { parts.append("Control") }
    if modifiers.contains(.option) { parts.append("Alt") }
    if modifiers.contains(.shift) { parts.append("Shift") }
    let token = key._webKeyToken
    parts.append(token.count == 1 ? token.uppercased() : token)
    return parts.joined(separator: "+")
  }
}

private struct _KeyboardShortcutValue { let shortcut: KeyboardShortcut? }
private enum KeyboardShortcutEnvironmentKey: EnvironmentKey {
  static let defaultValue = _KeyboardShortcutValue(shortcut: nil)
}

extension EnvironmentValues {
  /// The shortcut assigned to controls in this subtree. SwiftUI keeps the
  /// value private; the renderer reads it through SPI.
  @_spi(Renderer) public var _keyboardShortcut: KeyboardShortcut? {
    get { self[KeyboardShortcutEnvironmentKey.self].shortcut }
    set { self[KeyboardShortcutEnvironmentKey.self] = _KeyboardShortcutValue(shortcut: newValue) }
  }
}

nonisolated package struct KeyboardShortcutModifier: ViewModifier {
  public let shortcut: KeyboardShortcut?
  public init(shortcut: KeyboardShortcut?) { self.shortcut = shortcut }
  @MainActor public func _modifyContext(_ context: inout _RenderContext) {
    context.environment._keyboardShortcut = shortcut
  }
}

public extension View {
  nonisolated func keyboardShortcut(_ shortcut: KeyboardShortcut) -> some View {
    _modified(KeyboardShortcutModifier(shortcut: shortcut))
  }
}

/// Publishes the inherited shortcut on a control's activation element.
@MainActor func _applyKeyboardShortcut(_ context: _RenderContext, to node: _RenderNode) {
  guard let shortcut = context.environment._keyboardShortcut else { return }
  node.attributes["data-keyboard-shortcut"] = shortcut._webDescriptor
  node.attributes["aria-keyshortcuts"] = shortcut._ariaKeyShortcuts
}
