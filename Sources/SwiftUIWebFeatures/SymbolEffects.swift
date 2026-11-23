@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

/// The swing angle in thousandths of a radian, as a class name suffix. A non-finite angle is 0 and the magnitude is
/// capped so `Int(_:)` cannot trap on wasm32.
private func _wiggleAngleMillis(_ angle: Double) -> Int {
  guard angle.isFinite else { return 0 }
  return Int(Swift.max(-1e9, Swift.min(1e9, (angle * 1000).rounded())))
}
/// SwiftUI's SF Symbol effects (`.symbolEffect(.bounce, value:)`, `.symbolEffect(.pulse, isActive:)`). Browser symbols are
/// static Lucide glyphs, so an effect moves the whole glyph: indefinite effects run a CSS animation while active
/// (Tools/styles.css), and discrete effects play once (or `options.repeat` times) when `value` changes
/// (Tools/transition-host.js). The effect and its variant stay inspectable as `data-symbol-effect`.
public protocol SymbolEffect { var _swiftUIWebSymbolEffectName: String { get } }

public struct BounceSymbolEffect: SymbolEffect, Hashable, Sendable {
  var direction = "up"
  public var _swiftUIWebSymbolEffectName: String { direction == "down" ? "bounce-down" : "bounce" }
  public var up: BounceSymbolEffect { var effect = self; effect.direction = "up"; return effect }
  public var down: BounceSymbolEffect { var effect = self; effect.direction = "down"; return effect }
  public var byLayer: BounceSymbolEffect { self }
  public var wholeSymbol: BounceSymbolEffect { self }
}
public struct PulseSymbolEffect: SymbolEffect, Hashable, Sendable {
  public var _swiftUIWebSymbolEffectName: String { "pulse" }
  public var byLayer: PulseSymbolEffect { self }
  public var wholeSymbol: PulseSymbolEffect { self }
}
public struct VariableColorSymbolEffect: SymbolEffect, Hashable, Sendable {
  public var _swiftUIWebSymbolEffectName: String { "variable-color" }
  public var iterative: VariableColorSymbolEffect { self }
  public var cumulative: VariableColorSymbolEffect { self }
  public var reversing: VariableColorSymbolEffect { self }
}
public struct ScaleSymbolEffect: SymbolEffect, Hashable, Sendable {
  var direction = "up"
  public var _swiftUIWebSymbolEffectName: String { direction == "down" ? "scale-down" : "scale" }
  public var up: ScaleSymbolEffect { var effect = self; effect.direction = "up"; return effect }
  public var down: ScaleSymbolEffect { var effect = self; effect.direction = "down"; return effect }
}
/// The symbol draws in (as when it is first shown).
public struct AppearSymbolEffect: SymbolEffect, Hashable, Sendable {
  var direction = "up"
  public var _swiftUIWebSymbolEffectName: String { direction == "down" ? "appear-down" : "appear" }
  public var up: AppearSymbolEffect { var effect = self; effect.direction = "up"; return effect }
  public var down: AppearSymbolEffect { var effect = self; effect.direction = "down"; return effect }
  public var byLayer: AppearSymbolEffect { self }
  public var wholeSymbol: AppearSymbolEffect { self }
}
/// The symbol draws out and stays hidden while the effect is active.
public struct DisappearSymbolEffect: SymbolEffect, Hashable, Sendable {
  var direction = "up"
  public var _swiftUIWebSymbolEffectName: String { direction == "down" ? "disappear-down" : "disappear" }
  public var up: DisappearSymbolEffect { var effect = self; effect.direction = "up"; return effect }
  public var down: DisappearSymbolEffect { var effect = self; effect.direction = "down"; return effect }
  public var byLayer: DisappearSymbolEffect { self }
  public var wholeSymbol: DisappearSymbolEffect { self }
}
/// One symbol replaced by another: the old one leaves, the new one arrives.
public struct ReplaceSymbolEffect: SymbolEffect, Hashable, Sendable {
  var style = "down-up"
  public var _swiftUIWebSymbolEffectName: String { "replace-\(style)" }
  public var downUp: ReplaceSymbolEffect { var effect = self; effect.style = "down-up"; return effect }
  public var upUp: ReplaceSymbolEffect { var effect = self; effect.style = "up-up"; return effect }
  public var offUp: ReplaceSymbolEffect { var effect = self; effect.style = "off-up"; return effect }
  public var byLayer: ReplaceSymbolEffect { self }
  public var wholeSymbol: ReplaceSymbolEffect { self }
  public static var downUp: ReplaceSymbolEffect { ReplaceSymbolEffect() }
  public static var upUp: ReplaceSymbolEffect { ReplaceSymbolEffect().upUp }
  public static var offUp: ReplaceSymbolEffect { ReplaceSymbolEffect().offUp }
  /// Replaces matching layers in place where it can; a glyph has one layer, so it is the fallback here.
  public struct MagicReplace: SymbolEffect, Hashable, Sendable {
    let fallback: ReplaceSymbolEffect
    public var _swiftUIWebSymbolEffectName: String { fallback._swiftUIWebSymbolEffectName }
  }
  public func magic(fallback: ReplaceSymbolEffect) -> ReplaceSymbolEffect.MagicReplace { MagicReplace(fallback: fallback) }
}
/// The effect the system picks for the symbol: a bounce here.
public struct AutomaticSymbolEffect: SymbolEffect, Hashable, Sendable {
  public var _swiftUIWebSymbolEffectName: String { "bounce" }
}
/// A short back-and-forth swing.
public struct WiggleSymbolEffect: SymbolEffect, Hashable, Sendable {
  var direction = "clockwise"
  var angle: Double? = nil
  public var _swiftUIWebSymbolEffectName: String {
    if let angle { return "wiggle-angle-\(_wiggleAngleMillis(angle))" }
    return "wiggle-\(direction)"
  }
  private func with(_ direction: String) -> WiggleSymbolEffect { var effect = self; effect.direction = direction; effect.angle = nil; return effect }
  public var clockwise: WiggleSymbolEffect { with("clockwise") }
  public var counterClockwise: WiggleSymbolEffect { with("counter-clockwise") }
  public var left: WiggleSymbolEffect { with("left") }
  public var right: WiggleSymbolEffect { with("right") }
  public var up: WiggleSymbolEffect { with("up") }
  public var down: WiggleSymbolEffect { with("down") }
  public var forward: WiggleSymbolEffect { with("right") }
  public var backward: WiggleSymbolEffect { with("left") }
  /// A swing along `angle` (radians from the horizontal).
  public func custom(angle: Double) -> WiggleSymbolEffect { var effect = self; effect.angle = angle; return effect }
  public var byLayer: WiggleSymbolEffect { self }
  public var wholeSymbol: WiggleSymbolEffect { self }
}
/// A full turn.
public struct RotateSymbolEffect: SymbolEffect, Hashable, Sendable {
  var clockwiseValue = true
  public var _swiftUIWebSymbolEffectName: String { clockwiseValue ? "rotate" : "rotate-counter-clockwise" }
  public var clockwise: RotateSymbolEffect { var effect = self; effect.clockwiseValue = true; return effect }
  public var counterClockwise: RotateSymbolEffect { var effect = self; effect.clockwiseValue = false; return effect }
  public var byLayer: RotateSymbolEffect { self }
  public var wholeSymbol: RotateSymbolEffect { self }
}
/// A slow swell, and with `pulse` a fade as it swells.
public struct BreatheSymbolEffect: SymbolEffect, Hashable, Sendable {
  var pulses = false
  public var _swiftUIWebSymbolEffectName: String { pulses ? "breathe-pulse" : "breathe" }
  public var pulse: BreatheSymbolEffect { var effect = self; effect.pulses = true; return effect }
  public var plain: BreatheSymbolEffect { var effect = self; effect.pulses = false; return effect }
  public var byLayer: BreatheSymbolEffect { self }
  public var wholeSymbol: BreatheSymbolEffect { self }
}

public extension SymbolEffect where Self == BounceSymbolEffect { static var bounce: BounceSymbolEffect { BounceSymbolEffect() } }
public extension SymbolEffect where Self == PulseSymbolEffect { static var pulse: PulseSymbolEffect { PulseSymbolEffect() } }
public extension SymbolEffect where Self == VariableColorSymbolEffect { static var variableColor: VariableColorSymbolEffect { VariableColorSymbolEffect() } }
public extension SymbolEffect where Self == ScaleSymbolEffect { static var scale: ScaleSymbolEffect { ScaleSymbolEffect() } }
public extension SymbolEffect where Self == AppearSymbolEffect { static var appear: AppearSymbolEffect { AppearSymbolEffect() } }
public extension SymbolEffect where Self == DisappearSymbolEffect { static var disappear: DisappearSymbolEffect { DisappearSymbolEffect() } }
public extension SymbolEffect where Self == ReplaceSymbolEffect { static var replace: ReplaceSymbolEffect { ReplaceSymbolEffect() } }
public extension SymbolEffect where Self == AutomaticSymbolEffect { static var automatic: AutomaticSymbolEffect { AutomaticSymbolEffect() } }
public extension SymbolEffect where Self == WiggleSymbolEffect { static var wiggle: WiggleSymbolEffect { WiggleSymbolEffect() } }
public extension SymbolEffect where Self == RotateSymbolEffect { static var rotate: RotateSymbolEffect { RotateSymbolEffect() } }
public extension SymbolEffect where Self == BreatheSymbolEffect { static var breathe: BreatheSymbolEffect { BreatheSymbolEffect() } }


public extension View {
  /// An indefinite symbol effect while `isActive` is true.
  nonisolated func symbolEffect<T: SymbolEffect>(_ effect: T, options: SymbolEffectOptions = .default, isActive: Bool = true) -> some View {
    var attributes = options.attributes
    attributes["data-symbol-effect"] = effect._swiftUIWebSymbolEffectName
    attributes["data-symbol-effect-active"] = isActive ? "true" : "false"
    return _modified(_SymbolEffectModifier(attributes: attributes))
  }

  /// A discrete symbol effect played whenever `value` changes. The value's hash travels with the effect, so the host sees
  /// the attribute change and plays it.
  nonisolated func symbolEffect<T: SymbolEffect, U: Hashable>(_ effect: T, options: SymbolEffectOptions = .default, value: U) -> some View {
    var attributes = options.attributes
    attributes["data-symbol-effect"] = effect._swiftUIWebSymbolEffectName
    attributes["data-symbol-effect-trigger"] = String(value.hashValue)
    return _modified(_SymbolEffectModifier(attributes: attributes))
  }
}
