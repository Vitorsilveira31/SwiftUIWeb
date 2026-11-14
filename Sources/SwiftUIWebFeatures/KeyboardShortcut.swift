@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

public extension View {
  nonisolated func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
    modifier(KeyboardShortcutModifier(shortcut: KeyboardShortcut(key, modifiers: modifiers)))
  }

  nonisolated func keyboardShortcut(
    _ key: KeyEquivalent,
    modifiers: EventModifiers = .command,
    localization: KeyboardShortcut.Localization
  ) -> some View {
    modifier(KeyboardShortcutModifier(shortcut: KeyboardShortcut(key, modifiers: modifiers, localization: localization)))
  }

  /// A nil shortcut removes an inherited one, as in SwiftUI.
  nonisolated func keyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
    modifier(KeyboardShortcutModifier(shortcut: shortcut))
  }
}
