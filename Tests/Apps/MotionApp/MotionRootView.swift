import SwiftUIWeb

/// The fixture of the motion browser test (`Tools/test-motion-browser.mjs`). Each section exercises one piece of
/// SwiftUI's animation system with a long, linear animation (one second) so the test can sample it half way:
/// insertion and removal transitions, the default fade, the siblings that move around them, a numeric content
/// transition, a spring, and a custom `Transition`.
struct MotionRootView: View {
  @State private var items = [1, 2, 3]
  @State private var snapExtra = false
  @State private var next = 4
  @State private var kind = 0
  @State private var showsTilt = true
  @State private var nests = false
  @State private var overridden = false
  @State private var fade = 1.0
  @State private var slide = 0.0
  @State private var effectDimmed = false
  @State private var showsAsymmetric = true
  @State private var snapAngle = 0.0
  @State private var tint = false
  @State private var cardOpacity = 0.4
  @State private var dotSize = 8.0
  @State private var showsKind = true
  @State private var showsPlain = true
  @State private var count = 8
  @State private var moved = false
  @State private var showsCustom = true
  @State private var showsAttached = true
  @State private var rings = 0
  @State private var completions = 0
  @State private var pulsed = false
  @State private var level = 0.0
  @State private var shaken = 0.0
  @State private var stepped = false
  @State private var quiet = false
  @State private var presenting = false
  @State private var pushed = false
  @State private var alerting = false
  @State private var bar = 0.0
  @State private var typed = 0.0
  @State private var swapped = false
  @State private var selected = 0
  @Namespace private var tabs

  private static let kinds: [(String, AnyTransition)] = [
    ("opacity", .opacity), ("scale", .scale), ("slide", .slide), ("move", .move(edge: .bottom)),
    ("offset", .offset(x: 40, y: 0)), ("push", .push(from: .trailing)),
    ("asymmetric", .asymmetric(insertion: .scale(scale: 0.5, anchor: .topLeading), removal: .opacity)),
    ("combined", AnyTransition.move(edge: .leading).combined(with: .opacity)),
    ("blur", AnyTransition(.blurReplace)),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Button("Add") { withAnimation(.linear(duration: 1)) { items.insert(next, at: 0); next += 1 } }.accessibilityIdentifier("add")
        Button("Remove") { withAnimation(.linear(duration: 1)) { _ = items.isEmpty ? nil : items.removeFirst() } }.accessibilityIdentifier("remove")
      }
      VStack(spacing: 4) {
        ForEach(items, id: \.self) { item in
          Text("Row \(item)").frame(width: 120, height: 24).background(Color.blue.opacity(0.2))
            .transition(.move(edge: .leading).combined(with: .opacity))
            .accessibilityIdentifier("row-\(item)")
        }
      }
      .accessibilityIdentifier("rows")

      HStack {
        Button("Kind") { kind = (kind + 1) % Self.kinds.count }.accessibilityIdentifier("kind")
        Text(Self.kinds[kind].0).accessibilityIdentifier("kind-name")
        Button("Toggle kind") { withAnimation(.linear(duration: 1)) { showsKind.toggle() } }.accessibilityIdentifier("toggle-kind")
      }
      ZStack {
        if showsKind {
          Text("Box").frame(width: 80, height: 40).background(Color.green.opacity(0.3))
            .transition(Self.kinds[kind].1)
            .accessibilityIdentifier("kind-box")
        }
      }
      .frame(width: 200, height: 60)

      Button("Toggle plain") { withAnimation(.linear(duration: 1)) { showsPlain.toggle() } }.accessibilityIdentifier("toggle-plain")
      if showsPlain { Text("Plain").accessibilityIdentifier("plain") }
      Button("Toggle snap") { showsPlain.toggle() }.accessibilityIdentifier("toggle-snap")

      HStack {
        Button("Up") { count += 1 }.accessibilityIdentifier("up")
        Button("Up 100") { count += 100 }.accessibilityIdentifier("up-100")
        Button("Down") { count -= 1 }.accessibilityIdentifier("down")
        Text("\(count)")
          .font(.title)
          .contentTransition(.numericText(value: Double(count)))
          .animation(.linear(duration: 4), value: count)
          .accessibilityIdentifier("count")
      }

      Button("Move") { withAnimation(.bouncy(duration: 1)) { moved.toggle() } }.accessibilityIdentifier("move")
      Text("Spring").offset(x: moved ? 200 : 0).accessibilityIdentifier("spring")

      Button("Toggle custom") { withAnimation(.linear(duration: 1)) { showsCustom.toggle() } }.accessibilityIdentifier("toggle-custom")
      if showsCustom { Text("Custom").opacity(0.4).transition(Twist()).accessibilityIdentifier("custom") }

      Button("Toggle attached") { showsAttached.toggle() }.accessibilityIdentifier("toggle-attached")
      // Two value-scoped animations armed in the same commit: the inner one is the nearer.
      VStack {
        VStack {
          if nests { Text("Nested").transition(.opacity).accessibilityIdentifier("nested") }
        }
        .animation(.linear(duration: 1), value: nests)
      }
      .animation(.linear(duration: 10), value: nests)
      Button("Nest") { nests.toggle() }.accessibilityIdentifier("nest")
      // A value-scoped animation whose value changes inside `withAnimation`: the modifier nearest the views times what enters
      // and what changes below it, not the ten seconds of the transaction.
      VStack {
        if overridden { Text("Overridden").transition(.opacity).accessibilityIdentifier("overridden") }
        Text("Dimmed").opacity(overridden ? 0.5 : 1).accessibilityIdentifier("dimmed")
      }
      .animation(.linear(duration: 1), value: overridden)
      Button("Override") { withAnimation(.linear(duration: 10)) { overridden.toggle() } }.accessibilityIdentifier("override")
      // A transition whose identity phase is not neutral: the view rests half transparent.
      Text("Resting").transition(HalfRest()).accessibilityIdentifier("resting")
      // An identity phase with a transform of its own: the active phase goes over the view's, not over the identity's.
      Button("Toggle tilt") { withAnimation(.linear(duration: 1)) { showsTilt.toggle() } }.accessibilityIdentifier("toggle-tilt")
      if showsTilt { Text("Tilted").transition(Tilt()).accessibilityIdentifier("tilted") }
      Button("Toggle asymmetric") { showsAsymmetric.toggle() }.accessibilityIdentifier("toggle-asymmetric")
      if showsAsymmetric {
        Text("Asymmetric")
          .transition(.asymmetric(insertion: AnyTransition.opacity.animation(.linear(duration: 1)), removal: AnyTransition.opacity.animation(.linear(duration: 3))))
          .accessibilityIdentifier("asymmetric")
      }
      if showsAttached { Text("Attached").transition(AnyTransition.opacity.animation(.linear(duration: 1))).accessibilityIdentifier("attached") }

      HStack {
        Button("Ring") { rings += 1 }.accessibilityIdentifier("ring")
        Image(systemName: "bell").symbolEffect(.wiggle, options: .repeat(2), value: rings).accessibilityIdentifier("bell")
        Image(systemName: "arrow.clockwise").symbolEffect(.rotate, isActive: rings % 2 == 1).accessibilityIdentifier("spinner")
      }

      HStack {
        Button("Complete") { withAnimation(.linear(duration: 0.4), { pulsed.toggle() }, completion: { completions += 1 }) }.accessibilityIdentifier("complete")
        Text("completed \(completions)").accessibilityIdentifier("completed")
      }

      // A geometry effect that moves its content by the content's own width: the size is the one the page measures.
      Text("Measured shift").modifier(WidthShift()).accessibilityIdentifier("measured-shift")

      HStack {
        Button("Fill") { withAnimation(.linear(duration: 1)) { level = level == 0 ? 100 : 0 } }.accessibilityIdentifier("fill")
        Meter(level: level).accessibilityIdentifier("meter")
        Button("Shake") { withAnimation(.linear(duration: 1)) { shaken = shaken == 0 ? 40 : 0 } }.accessibilityIdentifier("shake")
        Text("Shaken").modifier(Shake(amount: shaken)).opacity(shaken == 0 ? 1 : 0.2).accessibilityIdentifier("shaken")
      }

      HStack {
        Button("Step") { withAnimation(Animation(Steps(duration: 1))) { stepped.toggle() } }.accessibilityIdentifier("step")
        Text("Stepped").offset(x: stepped ? 100 : 0).accessibilityIdentifier("stepped")
        Button("Quiet") { withAnimation(.linear(duration: 1)) { quiet.toggle() } }.accessibilityIdentifier("quiet")
        Text("Quiet").offset(x: quiet ? 100 : 0).transaction { $0.animation = nil }.accessibilityIdentifier("quiet-text")
      }

      HStack {
        Button("Grow") { withAnimation(.linear(duration: 1)) { bar = bar == 0 ? 1 : 0 } }.accessibilityIdentifier("grow")
        Bar(fraction: bar).fill(Color.purple).frame(width: 100, height: 10).accessibilityIdentifier("bar")
        Button("Present") { presenting = true }.accessibilityIdentifier("present")
      }

      HStack {
        Button("Type") { withAnimation(.linear(duration: 1)) { typed = typed == 0 ? 1 : 0 } }.accessibilityIdentifier("type")
        (Text("Hello ") + Text("renderer").bold().customAttribute(Emphasis()))
          .textRenderer(Typewriter(progress: typed))
          .accessibilityIdentifier("typed")
      }
      .sheet(isPresented: $presenting) {
        VStack {
          Text("Sheet").accessibilityIdentifier("sheet-text")
          Button("Dismiss") { presenting = false }.accessibilityIdentifier("dismiss")
        }
      }

      HStack(alignment: .top) {
        NavigationStack {
          VStack {
            Text("Root screen").accessibilityIdentifier("nav-root-text")
            Button("Push") { pushed = true }.accessibilityIdentifier("push")
          }
          .navigationDestination(isPresented: $pushed) {
            VStack {
              Text("Pushed screen").accessibilityIdentifier("pushed-text")
              Button("Pop") { pushed = false }.accessibilityIdentifier("pop")
            }
          }
        }
        .frame(width: 300, height: 140)
        .accessibilityIdentifier("nav")
        Button("Alert") { alerting = true }.accessibilityIdentifier("alert")
      }
      .alert("Motion alert", isPresented: $alerting) {
        Button("OK") { alerting = false }.accessibilityIdentifier("alert-ok")
      }

      ScrollView {
        VStack(spacing: 8) {
          ForEach(0..<20, id: \.self) { index in
            Text("Card \(index)").frame(width: 160, height: 40).background(Color.orange.opacity(0.3))
              .opacity(index == 1 ? cardOpacity : 1)
              .scrollTransition { content, phase in
                content.opacity(phase.isIdentity ? 1 : 0.3).scaleEffect(phase.isIdentity ? 1 : 0.8)
              }
              .accessibilityIdentifier("card-\(index)")
          }
        }
      }
      .frame(width: 200, height: 160)
      .accessibilityIdentifier("cards")

      // Each edge with its own configuration: past the top nothing changes, past the bottom it animates.
      ScrollView {
        VStack(spacing: 8) {
          ForEach(0..<20, id: \.self) { index in
            Text("Edge \(index)").frame(width: 160, height: 40).background(Color.teal.opacity(0.3))
              .scrollTransition(topLeading: .identity, bottomTrailing: .animated(.linear(duration: 0.2))) { content, phase in
                content.opacity(phase.isIdentity ? 1 : 0.3)
              }
              .accessibilityIdentifier("edge-\(index)")
          }
        }
      }
      .frame(width: 200, height: 160)
      .accessibilityIdentifier("edges")

      // Snap targets keep their boxes under an animated scroll transition too: the offset moves their content.
      ScrollView {
        VStack(spacing: 8) {
          ForEach(0..<20, id: \.self) { index in
            VStack(spacing: 0) {
              if index == 10 && snapExtra { Text("Extra").frame(width: 160, height: 10) }
              Text("Snap \(index)").frame(width: 160, height: 40).background(Color.purple.opacity(0.3))
                .rotationEffect(.degrees(index == 10 ? snapAngle : 0))
            }
              .id(index)
              .scrollTransition(topLeading: .identity, bottomTrailing: .animated(.linear(duration: 0.2))) { content, phase in
                content.scaleEffect(phase.isIdentity ? 1 : 0.5)
              }
              .accessibilityIdentifier("snap-\(index)")
          }
        }
        .scrollTargetLayout()
      }
      .scrollTargetBehavior(.viewAligned)
      .frame(width: 200, height: 160)
      .accessibilityIdentifier("snaps")
      Button("Extra") { snapExtra.toggle() }.accessibilityIdentifier("snap-extra")
      Button("Rotate") { snapAngle = 30 }.accessibilityIdentifier("snap-rotate")
      Button("Card opacity") { cardOpacity = 0.8 }.accessibilityIdentifier("card-opacity")
      Button("Dot size") { dotSize = 16 }.accessibilityIdentifier("dot-size")

      // A shape's fill under an armed ancestor animation, with a transaction below that turns animations off.
      VStack {
        Circle().trim(from: 0, to: tint ? 1 : 0.5).stroke(tint ? Color.red : Color.blue, lineWidth: 4).frame(width: 40, height: 40)
          .transaction { $0.animation = nil }
          .accessibilityIdentifier("tinted")
      }
      .animation(.linear(duration: 3), value: tint)
      Button("Tint") { tint.toggle() }.accessibilityIdentifier("tint")

      HStack {
        Button("Swap") { withAnimation(.linear(duration: 1)) { swapped.toggle() } }.accessibilityIdentifier("swap")
        Image(systemName: swapped ? "star.fill" : "star").contentTransition(.symbolEffect(.replace)).accessibilityIdentifier("star")
      }

      // A pill that follows the selected tab, and a dot under it that matches only its position.
      HStack(spacing: 12) {
        ForEach(0..<3, id: \.self) { index in
          Button("Tab \(index)") { withAnimation(.linear(duration: 1)) { selected = index } }
            .padding(6)
            .matchedGeometryEffect(id: index, in: tabs)
            .accessibilityIdentifier("tab-\(index)")
        }
      }
      .background(alignment: .center) {
        Capsule().fill(Color.blue.opacity(0.25))
          .matchedGeometryEffect(id: selected, in: tabs, isSource: false)
          .accessibilityIdentifier("pill")
      }
      .overlay(alignment: .topLeading) {
        Circle().fill(Color.blue).frame(width: dotSize, height: dotSize)
          .matchedGeometryEffect(id: selected, in: tabs, properties: .position, anchor: .bottom, isSource: false)
          .accessibilityIdentifier("dot")
      }

      // A source inside a scroll view, and a target outside it: scrolling moves the source without a commit.
      HStack(alignment: .top) {
        ScrollView {
          VStack(spacing: 0) {
            Color.clear.frame(width: 30, height: 20)
            Rectangle().fill(Color.green).frame(width: 30, height: 10)
              .matchedGeometryEffect(id: "scrolled", in: tabs)
              .accessibilityIdentifier("scroll-source")
            Color.clear.frame(width: 30, height: 200)
          }
        }
        .frame(width: 40, height: 60)
        .accessibilityIdentifier("scroll-box")
        Circle().fill(Color.orange).frame(width: 8, height: 8)
          .matchedGeometryEffect(id: "scrolled", in: tabs, properties: .position, isSource: false)
          .accessibilityIdentifier("scroll-follower")
      }

      // A target under a scaled ancestor: the page measures in the viewport, the target's CSS is in its own coordinates.
      HStack(alignment: .top, spacing: 20) {
        Rectangle().fill(Color.purple).frame(width: 30, height: 10)
          .matchedGeometryEffect(id: "scaled", in: tabs)
          .accessibilityIdentifier("scale-source")
        VStack {
          Circle().fill(Color.red).frame(width: 8, height: 8)
            .matchedGeometryEffect(id: "scaled", in: tabs, properties: .position, isSource: false)
            .accessibilityIdentifier("scale-follower")
        }
        .scaleEffect(2, anchor: .topLeading)
      }

      // Two colour multipliers with a blur between them: the page defines both matrices.
      Rectangle().fill(Color.white).frame(width: 20, height: 10)
        .colorMultiply(Color(red: 1, green: 0, blue: 1))
        .blur(radius: 1)
        .colorMultiply(Color(red: 0, green: 1, blue: 1))
        .accessibilityIdentifier("multiplied")

      // Readers under a 2x scale see their own points: the bar is as wide as the reader, and as wide as the bounds anchor.
      GeometryReader { proxy in
        Rectangle().fill(Color.red).frame(width: proxy.size.width, height: 4).accessibilityIdentifier("scaled-reader-bar")
      }
      .frame(width: 100, height: 20)
      .scaleEffect(2, anchor: .topLeading)
      Color.blue.opacity(0.2).frame(width: 100, height: 20)
        .anchorPreference(key: ScaledBoundsKey.self, value: .bounds) { $0 }
        .overlayPreferenceValue(ScaledBoundsKey.self) { anchor in
          GeometryReader { proxy in
            if let anchor { Rectangle().fill(Color.green).frame(width: proxy[anchor].width, height: 4).accessibilityIdentifier("scaled-anchor-bar") }
          }
        }
        .scaleEffect(2, anchor: .topLeading)
      // The anchored view is under the 2x scale and its reader is outside it: the anchor is where the view shows, 200 wide.
      VStack(alignment: .leading, spacing: 0) {
        Color.blue.opacity(0.2).frame(width: 100, height: 20)
          .anchorPreference(key: ScaledBoundsKey.self, value: .bounds) { $0 }
          .accessibilityIdentifier("outer-anchor-source")
          .scaleEffect(2, anchor: .topLeading)
      }
      .frame(width: 220, height: 44, alignment: .topLeading)
      .overlayPreferenceValue(ScaledBoundsKey.self) { anchor in
        GeometryReader { proxy in
          if let anchor {
            Rectangle().fill(Color.orange).frame(width: proxy[anchor].width, height: 4).offset(x: proxy[anchor].minX, y: proxy[anchor].minY)
              .accessibilityIdentifier("outer-anchor-bar")
          }
        }
      }
      // A visual effect that reads state as well as geometry: a change of the state shows without a change of geometry.
      // (The closure is Sendable, as in SwiftUI: it takes a copy of the state, which each render makes anew.)
      let dimmed = effectDimmed
      Text("Effect").frame(width: 80, height: 20)
        .visualEffect { content, proxy in content.opacity(dimmed ? 0.3 : 1).offset(x: proxy.size.width / 8) }
        .accessibilityIdentifier("state-effect")
      Button("Dim effect") { effectDimmed.toggle() }.accessibilityIdentifier("dim-effect")
      // A slow animated change of two properties, then a plain change of one before it ends: the plain value shows at once
      // and the other property goes on animating.
      Text("Fader").opacity(fade).offset(x: slide).accessibilityIdentifier("fader")
      Button("Fade slowly") { withAnimation(.linear(duration: 5)) { fade = 0.2; slide = 100 } }.accessibilityIdentifier("fade-slowly")
      Button("Fade now") { fade = 0.8 }.accessibilityIdentifier("fade-now")
      // Two phases whose animations differ: each is the one the view moves to its phase with, after its delay.
      Text("Phased")
        .phaseAnimator([false, true]) { content, phase in content.opacity(phase ? 0.5 : 1) } animation: { phase in
          phase ? .linear(duration: 0.3).delay(1) : .linear(duration: 0.2)
        }
        .accessibilityIdentifier("phased")
      // The anchored view is turned a quarter and its reader is not: the anchor's bounds are the turned box, 20 by 100.
      VStack(alignment: .leading, spacing: 0) {
        Color.blue.opacity(0.2).frame(width: 100, height: 20)
          .anchorPreference(key: ScaledBoundsKey.self, value: .bounds) { $0 }
          .accessibilityIdentifier("turned-anchor-source")
          .rotationEffect(.degrees(90))
      }
      .frame(width: 120, height: 110)
      .overlayPreferenceValue(ScaledBoundsKey.self) { anchor in
        GeometryReader { proxy in
          if let anchor {
            Rectangle().fill(Color.orange.opacity(0.5)).frame(width: proxy[anchor].width, height: proxy[anchor].height)
              .offset(x: proxy[anchor].minX, y: proxy[anchor].minY)
              .accessibilityIdentifier("turned-anchor-bar")
          }
        }
      }

      // A reader of the text's layout draws a bar on its first line's baseline, as wide as the line.
      Text("Measured line")
        .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
          GeometryReader { proxy in
            if let first = layouts.first, let line = first.layout.first {
              let origin = proxy[first.origin]
              Rectangle().fill(Color.red).frame(width: line.typographicBounds.width, height: 2)
                .offset(x: origin.x + line.origin.x, y: origin.y + line.origin.y - 1)
                .accessibilityIdentifier("baseline")
            }
          }
        }
        .accessibilityIdentifier("measured")

      // A renderer that draws the text as it is: its underline and its gradient come from the page.
      (Text("Under").underline(color: .red) + Text(" Gradient").foregroundStyle(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)))
        .textRenderer(AsIs())
        .accessibilityIdentifier("styled")

      // A gradient from the view around a renderer's text: the renderer draws it, the page's glyphs do not.
      VStack {
        Text("Around").font(.title).textRenderer(AsIs()).accessibilityIdentifier("around")
      }
      .foregroundStyle(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing))

      // A renderer that lays its text out 70 points wide, beside the same text the page lays out at that width.
      HStack(alignment: .top) {
        Text("wrap me into a few lines").textRenderer(Narrow(width: 70)).accessibilityIdentifier("narrow")
        Text("wrap me into a few lines").frame(width: 70).accessibilityIdentifier("narrow-reference")
        Text("wrap me into a few lines").lineLimit(2).textRenderer(Narrow(width: 70)).accessibilityIdentifier("limited")
        Text("wrap me into a few lines").lineLimit(2).frame(width: 70).accessibilityIdentifier("limited-reference")
        Text("One long line that does not fit").lineLimit(1).frame(width: 90).textRenderer(AsIs()).accessibilityIdentifier("ellipsized")
        Text("שלום עולם זה טקסט ארוך מאוד שלא נכנס").lineLimit(1).frame(width: 90).textRenderer(AsIs()).accessibilityIdentifier("ellipsized-rtl")
      }
    }
    .padding(16)
  }
}

/// A custom transition: half transparent and turned while not at identity.
struct Twist: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content
      .opacity(phase.isIdentity ? 1 : 0.5)
      .rotationEffect(.degrees(phase.isIdentity ? 0 : 90))
  }
}

/// An animatable view: its text shows the level its animation has reached.
struct Meter: View, Animatable {
  var level: Double
  nonisolated var animatableData: Double {
    get { level }
    set { level = newValue }
  }
  var body: some View { Text("level \(Int(level.rounded()))") }
}

/// A geometry effect that moves its content by `amount` points along x.
/// Moves its content right by its own width.
struct WidthShift: GeometryEffect {
  nonisolated func effectValue(size: CGSize) -> ProjectionTransform {
    ProjectionTransform(CGAffineTransform(translationX: size.width, y: 0))
  }
}

/// A custom transition whose identity phase is half transparent and whose active phases are invisible.
/// A custom transition whose identity phase is turned 10 degrees and whose active phases are turned 20.
struct Tilt: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.rotationEffect(.degrees(phase == .identity ? 10 : 20))
  }
}

struct HalfRest: Transition {
  func body(content: Content, phase: TransitionPhase) -> some View {
    content.opacity(phase == .identity ? 0.5 : 0)
  }
}

struct Shake: GeometryEffect {
  var amount: Double
  nonisolated var animatableData: Double {
    get { amount }
    set { amount = newValue }
  }
  nonisolated func effectValue(size: CGSize) -> ProjectionTransform {
    ProjectionTransform(CGAffineTransform(translationX: amount, y: 0))
  }
}

/// A custom animation that moves in four steps over `duration` seconds.
struct Steps: CustomAnimation {
  let duration: Double
  func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
    guard time < duration else { return nil }
    return value.scaled(by: (time / duration * 4).rounded(.down) / 4)
  }
}

/// A shape whose width animates: `fraction` of its rectangle.
struct Bar: Shape {
  var fraction: Double
  nonisolated var animatableData: Double {
    get { fraction }
    set { fraction = newValue }
  }
  nonisolated func path(in rect: CGRect) -> Path {
    Path(CGRect(x: 0, y: 0, width: rect.width * fraction, height: rect.height))
  }
}

/// A text attribute the typewriter underlines.
struct Emphasis: TextAttribute {}

/// A text renderer that types its text glyph by glyph as `progress` goes from 0 to 1, and underlines the runs that
/// carry `Emphasis` once it has typed everything.
struct Typewriter: TextRenderer {
  var progress: Double
  nonisolated var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  nonisolated func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
    var total = 0
    for line in layout { for run in line { total += run.count } }
    var index = 0
    for line in layout {
      for run in line {
        if progress >= 1, run[Emphasis.self] != nil {
          let bounds = run.typographicBounds
          ctx.fill(Path(CGRect(x: bounds.rect.minX, y: bounds.origin.y + 2, width: bounds.width, height: 2)), with: .color(.purple))
        }
        for slice in run {
          let shown = progress * Double(total) - Double(index)
          index += 1
          guard shown > 0 else { continue }
          var copy = ctx
          copy.opacity = min(1, shown)
          copy.draw(slice)
        }
      }
    }
  }
}

/// Draws every line of its text where the page laid it out.
struct AsIs: TextRenderer {
  nonisolated func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
    for line in layout { ctx.draw(line) }
  }
}

/// Draws its text laid out at `width`.
struct Narrow: TextRenderer {
  var width: Double
  nonisolated func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize {
    text.sizeThatFits(ProposedViewSize(width: width, height: nil))
  }
  nonisolated func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
    for line in layout { ctx.draw(line) }
  }
}

private struct ScaledBoundsKey: PreferenceKey {
  static var defaultValue: Anchor<CGRect>? { nil }
  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}
