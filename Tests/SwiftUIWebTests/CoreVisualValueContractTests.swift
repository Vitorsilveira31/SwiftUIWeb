import Testing
import SwiftUIWeb

@Suite
@MainActor
struct CoreVisualValueContractTests {
  private struct PassthroughModifier: ViewModifier {
    func body(content: Content) -> some View { content }
  }

  @Test
  func colorHueSectorsAndNonFiniteInputsResolveToStableCSSColors() {
    #expect(Set([HorizontalAlignment.leading, .center, .trailing]).count == 3)
    #expect(Set([VerticalAlignment.top, .center, .bottom]).count == 3)
    let sectors: [(Double, String)] = [
      (0, "rgba(255, 0, 0, 1.0)"),
      (1.0 / 6.0, "rgba(255, 255, 0, 1.0)"),
      (1.0 / 3.0, "rgba(0, 255, 0, 1.0)"),
      (0.5, "rgba(0, 255, 255, 1.0)"),
      (2.0 / 3.0, "rgba(0, 0, 255, 1.0)"),
      (5.0 / 6.0, "rgba(255, 0, 255, 1.0)"),
      (1, "rgba(255, 0, 0, 1.0)")
    ]
    for (hue, expected) in sectors {
      #expect(Color(hue: hue, saturation: 1, brightness: 1).cssValue == expected)
    }
    #expect(Color(hue: -1.0 / 6.0, saturation: 1, brightness: 1).cssValue == sectors[5].1)
    #expect(Color(hue: .nan, saturation: .infinity, brightness: -1).cssValue == "rgba(0, 0, 0, 1.0)")
    #expect(Color(white: .infinity, opacity: .nan).cssValue == "rgba(0, 0, 0, 0.0)")
    #expect(Color(white: Double(Float(0.5)), opacity: Double(Float(0.25))).cssValue == "rgba(127, 127, 127, 0.25)")
    #expect(Color(hue: Double(Float(1.0 / 3.0)), saturation: Double(Float(1)), brightness: Double(Float(1))).cssValue == "rgba(0, 255, 0, 1.0)")
    #expect(Color(.displayP3, red: Double(Float(0.2)), green: Double(Float(0.4)), blue: Double(Float(0.6))).cssValue ==
      "color(display-p3 0.20000000298023224 0.4000000059604645 0.6000000238418579 / 1.0)")
    #expect(Color("asset-token", bundle: nil).cssValue == "var(--asset-color-asset-token, asset-token)")
    #expect(Color("StudioInk").cssValue == "var(--asset-color-StudioInk, StudioInk)")
    #expect(Color("#112233").cssValue == "#112233", "hex is a CSS value, not an asset name")
    #expect(Color("light-dark(#fff, #000)").cssValue == "light-dark(#fff, #000)")
    #expect(Color("rgba(0, 0, 0, 0.5)").cssValue == "rgba(0, 0, 0, 0.5)")
    #expect(Color(css: "red").cssValue == "red")
    #expect(Color.red.cssValue == "light-dark(#FF3B30, #FF453A)", "system colors are Apple's palette")

    #expect(Color.red.mix(with: .blue, by: -0.5) == .red)
    #expect(Color.red.mix(with: .blue, by: 1.5) == .blue)
    #expect(Color.red.interpolated(to: .blue, fraction: 0.5).cssValue.contains("color-mix(in srgb"))
    let fade = Color.red.gradient
    #expect(fade.startPoint == .top)
    #expect(fade.endPoint == .bottom)
    #expect(fade.gradient.stops.map(\.location) == [0, 1])
    #expect(fade.gradient.stops.first?.color.cssValue.contains("color-mix(in srgb") == true, "lighter at the top")
    #expect(fade.gradient.stops.last?.color.cssValue == Color.red.cssValue, "the color itself at the bottom, opaque")

    let resolvedBlack = Color.Resolved(red: 0, green: 0, blue: 0, opacity: 0)
    let resolvedWhite = Color.Resolved(colorSpace: .displayP3, red: 1, green: 1, blue: 1, opacity: 1)
    let resolvedMidpoint = resolvedBlack.mix(with: resolvedWhite, by: 0.5)
    #expect(resolvedMidpoint.colorSpace == .sRGB)
    #expect(resolvedMidpoint.red == 0.5)
    #expect(resolvedMidpoint.opacity == 0.5)
  }

  @Test
  func gradientsSupportColorStopAndAngleInitializersAcrossRenderers() {
    let stops = [Gradient.Stop(color: .red, location: 0), Gradient.Stop(color: .blue, location: 1)]
    let angularValues = [
      AngularGradient(gradient: Gradient(stops: stops), center: .center, startAngle: .zero, endAngle: .degrees(180)),
      AngularGradient(colors: [.red, .blue], center: .center, startAngle: .zero, endAngle: .degrees(180)),
      AngularGradient(stops: stops, center: .center, startAngle: .zero, endAngle: .degrees(180)),
      AngularGradient(gradient: Gradient(stops: stops), center: .center, angle: .degrees(30)),
      AngularGradient(colors: [.red, .blue], center: .center, angle: .degrees(30)),
      AngularGradient(stops: stops, center: .center, angle: .degrees(30)),
      AngularGradient.angularGradient(Gradient(stops: stops), center: .center, startAngle: .zero, endAngle: .degrees(180)),
      AngularGradient.angularGradient(colors: [.red, .blue], center: .center, startAngle: .zero, endAngle: .degrees(180)),
      AngularGradient.angularGradient(stops: stops, center: .center, startAngle: .zero, endAngle: .degrees(180)),
      AngularGradient(gradient: Gradient(stops: stops), center: .center, angle: .degrees(30)),
      AngularGradient(colors: [.red, .blue], center: .center, angle: .degrees(30)),
      AngularGradient(stops: stops, center: .center, angle: .degrees(30))
    ]
    #expect(angularValues.allSatisfy { $0._swiftUIWebCSSValue.hasPrefix("conic-gradient(") })

    let radial = RadialGradient(colors: [.red, .blue], center: .center, startRadius: 1, endRadius: .infinity)
    #expect(radial._swiftUIWebCSSValue.contains("radial-gradient(circle at 50% 50%"))
    let html = FiberTree(
      VStack {
        Circle().strokeBorder(lineWidth: 2)
        Circle().strokeBorder(Color.blue, style: StrokeStyle(lineWidth: 3, dash: [2, 1]))
        Rectangle().fill(AngularGradient(colors: [.red, .blue], center: .center, angle: .zero))
        Rectangle().fill(RadialGradient(stops: stops, center: .topLeading, startRadius: 0, endRadius: 100))
        Circle().fill(AnyShapeStyle(RadialGradient(colors: [.red, .blue], center: .center, startRadius: 0, endRadius: 20)))
        Circle().stroke(AnyShapeStyle(AngularGradient(colors: [.red, .blue], center: .center, angle: .zero)), lineWidth: 2)
      }
    ).renderNode.htmlDescription
    #expect(html.contains("data-shape-stroke-border=\"true\""))
    #expect(html.contains("conic-gradient("))
    #expect(html.contains("radial-gradient("))

    let transition = AnyTransition.asymmetric(
      insertion: .move(edge: .leading), removal: .offset(x: 3, y: -2)
    ).combined(with: .scale(scale: 0.8, anchor: .bottomTrailing))
    #expect(transition.name.contains("asymmetric(move(2),offset(3,-2))"))
    #expect(transition.name.contains("combined("))
    #expect(AnyTransition.modifier(active: PassthroughModifier(), identity: PassthroughModifier()).name.hasPrefix("modifier("))
    #expect(AnyTransition.symbolEffect.name == "symbol-effect")
    let scaled = FiberTree(Text("Scale").transition(.scale)).renderNode
    // A transition never transitions the view's ordinary changes; it publishes its insertion and removal states.
    #expect(scaled.styles["transition"] == nil)
    #expect(scaled.attributes["data-transition-insert"] == "scale:0.00001;transform-origin:50% 50%")
  }

  @Test
  func fontAndAnimationValuesKeepTheirSwiftUIShapedOptions() {
    let font = Font.system(.headline, design: .rounded, weight: .medium)
      .italic().monospacedDigit().width(.expanded)
    #expect(font.cssStyles["font-family"] == Font.Design.rounded.rawValue)
    #expect(font.cssStyles["font-size"] == "17px")
    #expect(font.cssStyles["font-weight"] == Font.Weight.medium.rawValue)
    #expect(font.cssStyles["font-style"] == "italic")
    #expect(font.cssStyles["font-variant-numeric"] == "tabular-nums")
    #expect(font.cssStyles["font-stretch"] == Font.Width.expanded.rawValue)
    #expect(Font.system(size: 12, design: .serif).cssStyles["font-family"] == Font.Design.serif.rawValue)
    #expect(Font.body.monospaced().cssStyles["font-family"] == Font.Design.monospaced.rawValue)
    // A browser that lacks the system-ui family ignores it, so every design must end in a generic family.
    #expect(Font.Design.monospaced.rawValue.hasSuffix(", monospace"))
    #expect(Font.Design.serif.rawValue.hasSuffix(", serif"))
    #expect(Font.Design.rounded.rawValue.hasSuffix(", sans-serif"))
    #expect(Font.system(size: 16).weight(.semibold).cssStyles["font-weight"] == Font.Weight.semibold.rawValue)
    #expect(Font.system(size: 16).bold().cssStyles["font-weight"] == Font.Weight.bold.rawValue)

    let animations = [
      Animation.linear(duration: 0.2), .easeIn(duration: 0.2), .easeOut(duration: 0.2), .easeInOut(duration: 0.2),
      .spring(response: -1, dampingFraction: 2, blendDuration: 0.1),
      .interactiveSpring(response: 0.2, dampingFraction: 0.4),
      .interpolatingSpring(mass: 0, stiffness: 0, damping: -1, initialVelocity: 2),
      .interpolatingSpring(duration: -1, bounce: 2, initialVelocity: -0.4),
      .interpolatingSpring(duration: 0.4, bounce: 0),
      .timingCurve(0.1, 0.2, 0.3, 0.4, duration: -1),
      .smooth(), .smooth(duration: 0.2, extraBounce: 0.1),
      .snappy(), .snappy(duration: 0.2, extraBounce: 0.1),
      .bouncy(), .bouncy(duration: 0.2, extraBounce: 0.1)
    ]
    #expect(animations.count == 16)
    #expect(animations[4].name == "spring(0.01,2,0.1)")
    // `interactiveSpring` defaults to Apple's 0.25 s blend duration.
    #expect(animations[5].name == "spring(0.2,0.4,0.25)")
    // Bounce is clamped to 1, an undamped spring: it is cut at ten seconds.
    #expect(animations[7].cssValue.hasPrefix("all 10000ms linear("))
    #expect(animations[9].cssValue.contains("cubic-bezier(0.1,0.2,0.3,0.4)"))
    #expect(Animation("unknown").cssValue.contains(" ease-in-out"))
    #expect(Animation.easeOut(duration: 0.4).speed(2).delay(0.1).repeatCount(2, autoreverses: false).cssValue.contains("200ms ease-out 100ms /* repeat 2 */"))
    #expect(Animation.linear.repeatCount(-2).speed(-1).cssValue.contains("repeat 0"))
    #expect(Animation.default.repeatForever(autoreverses: false).cssValue.contains("/* infinite */"))
  }
}
