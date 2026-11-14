# Motion: animations, transitions and content transitions

SwiftUI's motion has four parts that work together: an `Animation` says how a value moves over time, a `Transition`
says how a view enters or leaves, a `ContentTransition` says how a view's content changes in place, and the views
around a change move to their new places with the same animation. This page says how SwiftUIWeb plays each of them in
the browser, and which SwiftUI APIs behave as in SwiftUI, which only in part, and which are missing.

## How it works

Swift decides what moves and how; the page plays it. Nothing here needs a platform branch: the curves are computed in
Swift on every host, and the browser host only reads attributes.

- **Curves.** Timing curves are CSS keywords and `cubic-bezier()`. Springs are solved in closed form
  (`Sources/SwiftUIWebCore/SpringMotion.swift`): the damped oscillator SwiftUI's `Spring` describes (duration and bounce,
  response and damping fraction, or mass, stiffness and damping, with an initial velocity), sampled into a CSS `linear()`
  easing and played until it settles. `.default` is a critically damped spring of response 0.55 s, and the timing curves
  without a duration last 0.35 s, as in SwiftUI. An engine without `linear()` (Safari before 17.2) gets the nearest
  cubic Bézier.
- **What Swift animates itself** (`Sources/SwiftUIWebCore/Animator.swift`). The `animatableData` of an `Animatable` view, an
  `AnimatableModifier`, a `GeometryEffect` and a `Shape` is Swift data the page cannot interpolate: when it changes in an
  animated commit, the view keeps showing the value it showed and Swift moves it to the new one with the transaction's
  animation, evaluated in Swift (`AnimationCurves.swift`: Bézier timing curves, springs, custom animations). While it
  moves, its node runs a timeline on animation frames (`data-timeline-view="animation"`): every frame renders the view
  again with the value reached, and the page does not ease those frames again. An animation that interrupts another
  starts from where the value was; a spring with a `blendDuration` blends from the one it interrupted.
- **Custom animations.** `Animation(_:)` takes a `CustomAnimation`. Swift evaluates it for what it animates itself; the
  page plays it as a `linear()` easing sampled from it for the properties CSS animates.
- **Transactions.** `withAnimation` marks the commit (`data-animation-transaction`, numbered so that two commits in a
  row with the same animation both reach the page); `.animation(_:value:)` arms its element for the commit in which its
  value changed (`data-animation-timing`, `data-animation-value`). Style changes in that commit animate
  (`Tools/embedded-dom.js`, `patchStyle`). The modifier nearest a view decides its timing: an armed
  `.animation(_:value:)` replaces the commit's and that of a `.transaction` above it, for the views that enter or
  leave below it, the siblings that move and the styles the commit animates there; a `.transaction` below it has the
  last word.
- **Insertion and removal** (`Sources/SwiftUIWebCore/Transitions.swift`, `Tools/transition-host.js`). A transition
  publishes the state its view is in before it is inserted and after it is removed, as CSS declarations relative to
  its own box (`data-transition-insert`, `data-transition-remove`). In an animated commit the host plays an inserted
  element from that state, keeps a removed element in place (out of the layout, inert, `data-transition-leaving`) while
  it plays out, and slides the siblings of a changed parent from their old boxes to their new ones (an additive
  `translate`, so moves compose). A view without a transition fades, as in SwiftUI. A custom `Transition`, or
  `AnyTransition.modifier(active:identity:)`, is rendered once per phase against an empty placeholder, and what differs
  from identity is its state.
- **Content transitions.** When a text of a view with `.contentTransition` changes in an animated commit, the host
  stands a run of spans in for its text node: `numericText` rolls the changed characters vertically (up when the number
  grows, by `value` or `countsDown`), blurring as they pass, while the room for them eases to its new width; `.opacity`
  and `.interpolate` cross-fade. The text node comes back when the run ends.
- **Symbol effects.** Discrete effects (`symbolEffect(_:options:value:)`) play when the value changes; indefinite ones
  (`isActive:`) run while active (`Tools/styles.css`). They move the whole glyph: browser symbols have no layers.
- **Scroll transitions.** Each element's phase follows where it sits in its scroll view: interactive transitions
  interpolate continuously, animated ones switch phase with their animation when the element crosses the threshold.
- **Presentations.** Sheets, covers, popovers, alerts, dialogs, navigation destinations, toasts and tooltips play their
  entry animation when they are inserted after the first commit, and their exit when they are dismissed
  (`data-exit-animation`): they stay in the page, inert, until the exit ends. The motion is UIKit's, along its
  presentation curve (`--swu-ease-present`, `cubic-bezier(0.32, 0.72, 0, 1)`): a sheet rises from below the screen
  (0.5 s, back down in 0.4 s) while the page dims, a full-screen cover rises from the bottom edge, an alert settles
  from 1.15 times its size (0.4 s) and fades out, a popover grows in and fades out.
- **Pushes and pops.** A pushed destination slides in from the trailing edge (0.5 s) while the screen it covers stays
  in view under it, at its box and out of the layout, and moves a third of the way out (`data-navigation-motion`,
  `Tools/transition-host.js`, `playPush`); a pop slides the destination back out and the screen under it comes back
  from a third of the way. Both screens are painted with the color behind the stack, and the stack clips them while
  they move. A destination that arrives with its stack (a tab, a sheet, a path set at once) does not slide by itself.
- **Subtree transactions.** `.transaction(_:)`, `.transaction(value:_:)`, `.transaction(_:body:)` and `.animation(_:body:)`
  change the transaction below them: Swift reads it for what it animates, and the page plays the subtree's CSS changes
  with its timing (`data-transaction-timing`, "none" when it turns animations off). CSS animates whole elements, so a
  `.animation(_:body:)` scopes what Swift animates exactly, and CSS properties of the whole element.
- **Text renderers.** A text below `textRenderer(_:)` carries `data-text-layout`. After layout, the geometry host
  (`Tools/geometry-host.js`) measures its lines, runs and glyphs (graphemes, with their font, color, ascent and
  descent) and reports them as `textLayout`. Swift keeps that layout per fiber, gives it to the renderer's
  `draw(layout:in:)` as `Text.Layout`, and draws what the renderer records into a canvas over the text
  (`TextRenderer.swift`). The text stays in the page, with its glyphs transparent, for layout, selection and
  accessibility. Under a gradient `foregroundStyle` on a container, which the browser clips to the glyphs of every text
  inside, transparent or not, the text is hidden instead and the canvas reads it (`role="img"`, `aria-label`). Until the
  page has measured it, the text shows as usual. A run's underline, strikethrough and gradient
  are measured with it and drawn by `draw(_:)`. `TextProxy` lays the text out again at another width from the measured
  advances, breaking lines where the browser does (after white space, a hyphen or an ideograph), within the text's line
  limit (the page reports the glyphs of the lines a limit hides too). A run's `Text.customAttribute(_:)` values
  come from the text it was drawn from (`data-text-run`). The renderer is `Animatable`, so an animation of its data
  draws every frame. As in SwiftUI, a copy of a `GraphicsContext` draws into the same canvas with its own opacity,
  blend mode, transform and clip.
- **Matched geometry.** The source of a `matchedGeometryEffect` names its element for the browser's view transition, so
  that a source replaced by another morphs into it with the commit's animation (or, in a commit without one, with the
  `.animation(_:value:)` the commit armed above it); the views the transition names play no insertion or removal of
  their own in that commit, since a removed one left in the page would hold the name twice; with `properties` naming only the
  position or the size, the group takes the other part at once, around the `anchor`. A view that is not the source
  takes the source's frame (`Tools/transition-host.js`, `MatchedGeometryHost`): its size, written over the layout's own,
  and its place, with its anchor point on the source's; when the source changes in an animated commit it moves there
  from where it showed.
- **Symbol replacement.** Under `.contentTransition(.symbolEffect)`, a copy of the old symbol stays over the new one,
  inert and out of the layout, and plays the replace effect's leaving half while the new symbol plays its arriving half.
- **Anchors and text layouts** (`Sources/SwiftUIWebCore/AnchorPreferences.swift`). An anchor is made from the frame the
  page measured for its view in the window (`data-geometry-change`, measured again as an ancestor scrolls), and
  `GeometryProxy[anchor]` gives it in the reader's coordinates: the anchor keeps where its view's axes go in the window (the
  scales and rotations above it) and goes through the window, so the reader may be under the same transforms, others or none. A new frame renders the layer that draws the
  anchor again, not only the anchored view. `overlayPreferenceValue` and `backgroundPreferenceValue`
  draw their layer from the preference of the view's own subtree. A text below a reader of `Text.LayoutKey` is measured
  as a renderer's text is, and gives its layout with an anchor of its origin.
- **Reduced motion.** With `prefers-reduced-motion`, nothing plays: changes apply at once, removals take the view out at
  once. Scroll transitions still follow the scroll position.

`make motion-browser-test` (`Tests/Apps/MotionApp`, `Tools/test-motion-browser.mjs`) samples all of this in Chromium and
WebKit by pausing the animations at chosen times.

## SwiftUI parity

| API | Status |
|---|---|
| `Animation` `.default`, `.linear`, `.easeIn`, `.easeOut`, `.easeInOut`, `.timingCurve` | As in SwiftUI |
| `.spring` (every spelling), `.interactiveSpring`, `.interpolatingSpring`, `.smooth`, `.snappy`, `.bouncy`, `Spring` | As in SwiftUI (physical curve; `blendDuration` blends what Swift animates; `.spring()` is the duration/bounce spring, which does not overshoot) |
| `.delay`, `.speed`, `.repeatCount`, `.repeatForever`, `.logicallyComplete(after:)` | As in SwiftUI |
| `CustomAnimation`, `Animation(_:)`, `AnimationContext`, `AnimationState`, `AnimationStateKey`, `Animation.animate/velocity/shouldMerge` | As in SwiftUI (a custom animation is evaluated for the fraction of the change) |
| `UnitCurve` (`value(at:)`, `velocity(at:)`, `inverse`, circular curves) | As in SwiftUI |
| `withAnimation`, `Binding.animation`, `.animation(_:value:)` | As in SwiftUI |
| `withAnimation(_:completionCriteria:_:completion:)`, `Transaction.addAnimationCompletion` | As in SwiftUI (time-based completion) |
| `withTransaction` (both forms), `Transaction` (`animation`, `disablesAnimations`, `isContinuous`, `tracksVelocity`), `TransactionKey` | As in SwiftUI |
| `.transaction(_:)`, `.transaction(value:_:)`, `.transaction(_:body:)`, `.animation(_:body:)` | As in SwiftUI for what Swift animates; CSS properties follow the element's transaction |
| `Animatable` views, `AnimatableModifier`, `GeometryEffect`, `Shape` `animatableData`, `projectionEffect`, `ProjectionTransform` | As in SwiftUI (rendered frame by frame) |
| `.transition` with `.opacity`, `.scale`, `.scale(_:anchor:)`, `.slide`, `.move(edge:)`, `.offset`, `.push(from:)`, `.blurReplace`, `.identity`, `.asymmetric`, `.combined(with:)`, `.animation(_:)`, `.symbolEffect` | As in SwiftUI |
| The `Transition` protocol and custom transitions, `AnyTransition.modifier(active:identity:)` | As in SwiftUI for style effects (opacity, scale, offset, rotation, blur, colors) |
| Siblings that move when a view is inserted or removed | As in SwiftUI (parents of up to 64 children) |
| `.contentTransition(.identity / .opacity / .interpolate / .numericText(...))` | As in SwiftUI (`.interpolate` cross-fades) |
| `.contentTransition(.symbolEffect(...))` | As in SwiftUI for the whole glyph: the old symbol leaves while the new one arrives |
| `matchedGeometryEffect` (`properties`, `anchor`, `isSource`), `MatchedGeometryProperties`, `matchedTransitionSource`, `.navigationTransition(.zoom)` | As in SwiftUI: sources morph through browser view transitions with the commit's animation, a view that is not the source takes the source's frame |
| `PhaseAnimator`, `.phaseAnimator` | As in SwiftUI (spring phases use the physical curve) |
| `KeyframeAnimator`, `KeyframeTimeline`, `LinearKeyframe`, `CubicKeyframe` (velocities), `SpringKeyframe`, `MoveKeyframe`, several tracks | As in SwiftUI (Swift evaluates every curve; the page joins samples 60 a second) |
| `symbolEffect` `.bounce`, `.pulse`, `.variableColor`, `.scale`, `.appear`, `.disappear`, `.replace`, `.wiggle`, `.rotate`, `.breathe`, `.automatic`, options, `symbolEffectsRemoved` | As in SwiftUI for the whole glyph (no per-layer effects) |
| Animatable modifiers (`opacity`, `scaleEffect`, `rotationEffect`, `offset`, `blur`, color controls, `shadow`, `clipShape`, `trim`, `frame`, `padding`, colors, fonts) | Interpolated when their CSS value can be |
| `colorMultiply` | As in SwiftUI (an SVG color matrix) |
| `visualEffect(_:)` and `VisualEffect` (`offset`, `scaleEffect`, `rotationEffect`, `rotation3DEffect`, `blur`, `opacity`, `brightness`, `contrast`, `grayscale`, `saturation`, `hueRotation`, `blendMode`, `transformEffect`) | As in SwiftUI (the geometry is measured again as it scrolls) |
| `scrollTransition(_:axis:transition:)` with `.interactive`, `.animated`, `.identity`, `threshold` | As in SwiftUI |
| `scrollTransition(topLeading:bottomTrailing:axis:transition:)` | As in SwiftUI (each edge has its mode, curve, animation, threshold and inset) |
| `scrollIndicatorsFlash(trigger:)`, `scrollIndicatorsFlash(onAppear:)` | As in SwiftUI (a one-point scroll there and back shows overlay indicators) |
| Shaders (`Shader`, `ShaderLibrary`, `ShaderFunction`, `layerEffect`, `distortionEffect`, `colorEffect`) | API only: shaders are Metal functions, which a browser cannot run over the page's elements; the view draws unchanged |
| `TextRenderer` (`draw(layout:in:)`, `sizeThatFits(proposal:text:)`, `displayPadding`), `Text.Layout` (lines, runs, slices, `TypographicBounds`, `CharacterIndex`, `isTruncated`), `TextProxy`, `TextAttribute`, `Text.customAttribute(_:)`, `textRenderer(_:)`, `GraphicsContext.draw` of a line, run or slice | As in SwiftUI: the browser lays the text out and Swift draws it, runs with their underline, strikethrough and gradient (the text's own or a view's around it), and `TextProxy` sizes it at any width and line limit |
| `Text.LayoutKey` | As in SwiftUI: a text gives its layout to a reader above it (`overlayPreferenceValue`, `backgroundPreferenceValue`, `onPreferenceChange`, `transformPreference`), measured once a reader asks |
| `Anchor`, `Anchor.Source`, `anchorPreference`, `transformAnchorPreference`, `transformPreference`, `overlayPreferenceValue`, `backgroundPreferenceValue`, `GeometryProxy[anchor]` | As in SwiftUI (an anchor is measured after layout: the first render has a zero frame) |
| Sheet, cover, popover, alert, dialog, navigation, toast and tooltip entry and dismissal | As in SwiftUI |
| `accessibilityReduceMotion` | As in SwiftUI (nothing plays; what Swift animates jumps) |
