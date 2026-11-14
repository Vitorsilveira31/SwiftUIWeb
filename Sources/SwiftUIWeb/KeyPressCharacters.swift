@_spi(Renderer) import SwiftUIWebCore

// `CharacterSet` is Foundation's type natively and WebFoundation's
// Foundation-free subset on Embedded/WASI, so this SwiftUI overload lives in
// the façade that sees both.
public extension View {
  /// Performs `action` when a key producing characters in `characters` is
  /// pressed while this view or a descendant has focus.
  nonisolated func onKeyPress(
    characters: CharacterSet,
    phases: KeyPress.Phases = [.down, .repeat],
    action: @escaping (KeyPress) -> KeyPress.Result
  ) -> some View {
    modifier(OnKeyPressModifier(phases: phases, matches: { press in
      !press.characters.isEmpty && press.characters.unicodeScalars.allSatisfy { characters.contains($0) }
    }, action: action))
  }
}
