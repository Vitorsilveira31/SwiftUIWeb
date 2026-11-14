import Testing
import Foundation
import SwiftUIWebCore
import SwiftUIWebFeatures
import SwiftUIWebFiber
import SwiftUIWebHTML

@Suite(.processGlobalState)
@MainActor
final class ColorTests {
  @Test
  func testRawCSSColorCannotCloseTheDeclarationOrAddOne() {
    let hostile = Color("red; position: fixed; inset: 0; } body { background: url(\"x")
    _expectTrue(!hostile.cssValue.contains(";"), hostile.cssValue)
    _expectTrue(!hostile.cssValue.contains("}"), hostile.cssValue)
    _expectTrue(!hostile.cssValue.contains("\""), hostile.cssValue)
    _expectEqual(Color("rgba(0, 0, 0, 0.5)").cssValue, "rgba(0, 0, 0, 0.5)")
    _expectEqual(Color("light-dark(#fff, #000)").cssValue, "light-dark(#fff, #000)")
  }

  @Test
  func testColorIsAViewAndKeepsShapeStyleRenderingPath() {
    let html = StaticHTMLFiberRenderer().render(
      VStack {
        Color.red.frame(width: 24, height: 12)
        Rectangle().fill(Color.blue)
      }
    )

    _expectTrue(html.contains("color-well"))
    _expectTrue(html.contains("data-color=\"\(Color.red.cssValue)\""))
    _expectTrue(html.contains("background: \(Color.red.cssValue);"))
    _expectTrue(html.contains("background: \(Color.blue.cssValue);"))
  }

  @Test
  func testRGBGrayscaleAndHSBComponentsAreNormalized() {
    // Preserve the existing deterministic sRGB spelling while clipping
    // invalid/out-of-range components before they reach CSS.
    _expectEqual(Color(red: 0, green: 0, blue: 0.5).cssValue, "rgba(0, 0, 127, 1.0)")
    _expectEqual(Color(red: 2, green: -1, blue: .nan, opacity: 2).cssValue, "rgba(255, 0, 0, 1.0)")
    _expectEqual(Color(white: 0.25, opacity: 0.5).cssValue, "rgba(63, 63, 63, 0.5)")
    _expectEqual(Color(hue: 0, saturation: 1, brightness: 1).cssValue, "rgba(255, 0, 0, 1.0)")
    _expectEqual(Color(hue: 1.0 / 3.0, saturation: 1, brightness: 1).cssValue, "rgba(0, 255, 0, 1.0)")
    let component: Double = 0.5
    _expectEqual(Color(red: component, green: component, blue: component).cssValue, "rgba(127, 127, 127, 1.0)")
  }

  @Test
  func testWideGamutAndOpacityRemainCSSNative() {
    let p3 = Color(.displayP3, red: 0.2, green: 0.4, blue: 0.6, opacity: 0.75)
    let linear = Color(.sRGBLinear, red: 0.2, green: 0.4, blue: 0.6)
    _expectTrue(p3.cssValue.hasPrefix("color(display-p3 0.2 0.4 0.6 / 0.75)"))
    _expectTrue(linear.cssValue.hasPrefix("color(srgb-linear 0.2 0.4 0.6 / 1.0)"))
    _expectEqual(Color.red.opacity(1), .red)
    _expectEqual(Color.red.opacity(0), .clear)
    _expectTrue(Color.red.opacity(0.25).cssValue.contains("color-mix(in srgb"))
  }

  @Test
  func testSemanticSystemColorsFollowColorSchemeAndTintTokens() {
    let previous = ColorSchemeRuntime.current
    defer { ColorSchemeRuntime.install(previous) }

    ColorSchemeRuntime.install(.dark)
    _expectEqual(EnvironmentValues().colorScheme, .dark)
    _expectEqual(Color.accentColor.cssValue, "var(--tint-color, var(--color-swu-primary))")
    _expectEqual(Color.systemBackground.cssValue, "var(--color-swu-background)")

    let html = StaticHTMLFiberRenderer().render(
      Text("semantic")
        .foregroundStyle(Color.primary)
        .background(Color.secondarySystemBackground)
    )
    _expectTrue(html.contains("color: CanvasText;"))
    _expectTrue(html.contains("background-color: var(--color-swu-surface);"))

    let tinted = StaticHTMLFiberRenderer().render(
      Color.accentColor.frame(width: 16, height: 16).tint(Color.pink)
    )
    _expectTrue(tinted.contains("background: var(--tint-color, var(--color-swu-primary));"))
    _expectTrue(tinted.contains("--tint-color: \(Color.pink.cssValue);"))
  }

  @Test
  func testTintWithTheAppAccentDoesNotMakeTheTintPropertyRefertoItself() {
    // `Color.accentColor` is `var(--tint-color, …)`; as the value of `--tint-color` it would be a cycle.
    let html = StaticHTMLFiberRenderer().render(Text("accent").tint(Color.accentColor))
    _expectTrue(!html.contains("--tint-color: var(--tint-color"))
    _expectTrue(html.contains("--tint-color: var(--asset-color-AccentColor, var(--color-swu-primary));"))
    // A real tint is written as before.
    let pink = StaticHTMLFiberRenderer().render(Text("pink").tint(Color.pink))
    _expectTrue(pink.contains("--tint-color: \(Color.pink.cssValue);"))
  }

  @Test
  func testEnvironmentColorSchemeMarksItsSubtreeLikePreferredColorScheme() {
    // A subtree set to dark through the environment gets the CSS color-scheme of dark, so its semantic colors
    // (`.primary`) resolve for dark on a page that is light, as they do on iOS.
    let html = StaticHTMLFiberRenderer().render(
      Text("dark card").foregroundStyle(Color.primary).environment(\.colorScheme, .dark)
    )
    _expectTrue(html.contains("data-color-scheme=\"dark\""))
    // Scoped to the subtree: the host must not lift it to the page as it does for preferredColorScheme.
    _expectTrue(html.contains("data-color-scheme-scope=\"subtree\""))
    _expectTrue(html.contains("dark card"))
  }

  @Test
  func testEnvironmentColorSchemeOfAGroupMarksEachOfItsPublishedRoots() {
    // A Group of several views is flattened into its children when it is published, so the scheme is on each child.
    let html = StaticHTMLFiberRenderer().render(
      Group { Text("first"); Text("second") }.environment(\.colorScheme, .dark)
    )
    #expect(html.components(separatedBy: "data-color-scheme=\"dark\"").count - 1 == 2)
    #expect(html.components(separatedBy: "data-color-scheme-scope=\"subtree\"").count - 1 == 2)
  }

  @Test
  func testTheInnermostEnvironmentColorSchemeWinsOnASharedNode() {
    let html = StaticHTMLFiberRenderer().render(
      Text("light").environment(\.colorScheme, .light).environment(\.colorScheme, .dark)
    )
    #expect(html.contains("data-color-scheme=\"light\""))
    #expect(!html.contains("data-color-scheme=\"dark\""), "the outer override does not overwrite the more local one")
    // And a more local override on one child of a Group stays while its sibling takes the outer scheme.
    let mixed = StaticHTMLFiberRenderer().render(
      Group { Text("a").environment(\.colorScheme, .light); Text("b") }.environment(\.colorScheme, .dark)
    )
    #expect(mixed.components(separatedBy: "data-color-scheme=\"light\"").count - 1 == 1)
    #expect(mixed.components(separatedBy: "data-color-scheme=\"dark\"").count - 1 == 1)
  }

  @Test
  func testResolvedColorPreservesColorSpaceAndInterpolates() {
    let p3 = Color.Resolved(colorSpace: .displayP3, red: 0, green: 0.2, blue: 0.4, opacity: 0.5)
    _expectTrue(p3.color.cssValue.hasPrefix("color(display-p3 0.0 "))
    _expectTrue(p3.color.cssValue.hasSuffix(" / 0.5)"))

    let black = Color.Resolved(red: 0, green: 0, blue: 0)
    let white = Color.Resolved(red: 1, green: 1, blue: 1)
    let midpoint = black.interpolated(to: white, fraction: 0.5)
    _expectEqual(midpoint.red, 0.5, accuracy: 0.0001)
    _expectEqual(midpoint.green, 0.5, accuracy: 0.0001)
    _expectEqual(midpoint.blue, 0.5, accuracy: 0.0001)
    _expectTrue(Color.red.mix(with: Color.blue, by: 0.5).cssValue.contains("color-mix(in srgb"))
  }

  @Test
  func testForegroundAndBackgroundAcceptColorAsShapeStyleAndView() {
    let html = StaticHTMLFiberRenderer().render(
      Color.green
        .foregroundStyle(.primary)
        .background(Color.surface)
    )
    _expectTrue(html.contains("color-well"))
    _expectTrue(html.contains("color: currentColor"))
    _expectTrue(html.contains("background-color: var(--color-swu-surface);"))
  }
}
