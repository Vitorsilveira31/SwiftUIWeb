import Testing
@testable import SwiftUIWebCore
@testable import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

// Test-only custom gesture: its renderer payload is passed through as the value.
private struct RawGesture: Gesture {
  typealias Value = String
  typealias Body = Never
  let name: String
  let spec: _GestureSpec
  init(name: String, spec: _GestureSpec) { self.name = name; self.spec = spec }
  func _makeRendererGesture() -> _RendererGesture { _RendererGesture(name: name, spec: spec) }
  func _rendererValue(from raw: String) -> String? { raw }
  func _rendererDefaultValue() -> String? { "" }
}

@MainActor func _eraseGesture<G: Gesture>(_ gesture: G) -> _RendererGesture {
  gesture._makeRendererGesture()
}

private struct IntegerGesture: Gesture {
  typealias Value = Int
  typealias Body = Never
}

private struct StringGesture: Gesture {
  typealias Value = String
  typealias Body = Never
}

private struct OpaqueGesture: Gesture {
  struct Value {}
}

@Suite
@MainActor
struct GestureContractTests {
  @Test
  func gestureNamesRemainStableForConcreteAndErasedGestures() {
    #expect(TapGesture()._swiftUIWebGestureName == String(reflecting: TapGesture.self))
    #expect(_eraseGesture(RawGesture(name: "settings-gesture", spec: _GestureSpec(kind: "settings-gesture"))).name == "settings-gesture")
  }

  @Test
  func descriptorClampsValuesEscapesStringsAndNormalizesNonFiniteNumbers() {
    let descriptor = _GestureSpec(
      kind: "custom;kind|\\",
      count: 0,
      minimumDistance: -1,
      minimumDuration: .infinity,
      maximumDistance: -2,
      minimumScaleDelta: .infinity,
      minimumAngleDelta: -4,
      coordinateSpace: .named("surface;west|\\"),
      first: "tap;first",
      second: "drag|second"
    )

    _expectEqual(descriptor.count, 1)
    _expectEqual(descriptor.minimumDistance, 0)
    _expectEqual(descriptor.maximumDistance, 0)
    _expectEqual(descriptor.minimumAngleDelta, 0)
    _expectTrue(descriptor.encoded.contains("minScale=0"))
    _expectTrue(descriptor.encoded.contains("kind=custom\\;kind\\|\\\\"))
    _expectTrue(descriptor.encoded.contains("minDuration=0"))
    _expectTrue(descriptor.encoded.contains("space=named:surface\\;west\\|\\\\"))
    _expectTrue(descriptor.encoded.contains("first=tap\\;first"))
    _expectTrue(descriptor.encoded.contains("second=drag\\|second"))

    let equal = _GestureSpec(kind: "drag", coordinateSpace: .named("canvas"))
    _expectEqual(equal, _GestureSpec(kind: "drag", coordinateSpace: .named("canvas")))
    _expectNotEqual(equal, _GestureSpec(kind: "drag", coordinateSpace: .global))
  }

  @Test
  func typeErasureInitializersAndReplacementKeepIdentityAndCallbacksExplicit() {
    let erased = AnyGesture<TapGesture.Value>(TapGesture(count: 2))
    _expectEqual(erased._makeRendererGesture().name, "tap")
    _expectEqual(erased._makeRendererGesture()._swiftUIWebSpec.count, 2)

    var calls = 0
    let configured = _eraseGesture(TapGesture().onChanged { _ in calls += 1 })
    configured.actionBox.changed?("tap")
    _expectEqual(calls, 1)

    let replacement = _RendererGesture(name: "custom", spec: _GestureSpec(kind: "custom"))
    _expectEqual(replacement.name, "custom")
    _expectEqual(replacement._swiftUIWebSpec.kind, "custom")
    _expectNil(replacement.actionBox.changed)

    var tapChanges = 0
    let tapCallbacks = TapGesture().onChanged { tapChanges += 1 }
    _eraseGesture(tapCallbacks).actionBox.changed?("ignored")
    _expectEqual(tapChanges, 1)

    let plainLongPress = _eraseGesture(LongPressGesture(minimumDuration: 0))
    _expectEqual(plainLongPress._swiftUIWebSpec.kind, "longpress")
    // Primitive gestures carry no callbacks; wrappers add them.
    _expectNil(plainLongPress.actionBox.ended)
  }

  @Test
  func erasedGesturePreservesCallbackOrderHashAndSharedCopies() {
    var callbacks: [String] = []
    let gesture = RawGesture(name: "custom", spec: _GestureSpec(kind: "custom"))
      .onChanged { value in callbacks.append("changed-1:\(value)") }
      .onChanged { value in callbacks.append("changed-2:\(value)") }
      .onEnded { _ in callbacks.append("ended-value") }
      .onEnded { _ in callbacks.append("ended-void") }
    let copy = _eraseGesture(gesture)

    copy.actionBox.changed?("payload")
    copy.actionBox.ended?("payload")
    copy.actionBox.endedAction?()

    _expectEqual(callbacks, [
      "changed-1:payload", "changed-2:payload", "ended-value", "ended-void",
      "ended-value", "ended-void"
    ])
    _expectEqual(Set([copy, _eraseGesture(RawGesture(name: "custom", spec: _GestureSpec(kind: "custom")))]).count, 1)
    _expectEqual(Set([copy, _eraseGesture(RawGesture(name: "different", spec: _GestureSpec(kind: "different")))]).count, 2)
  }

  @Test
  func tapCallbacksAndGestureStateSupportBothProjectedAndInoutForms() {
    var calls: [String] = []
    let callbacks = TapGesture(count: 3)
      .onChanged { calls.append("changed-1") }
      .onChanged { calls.append("changed-2") }
      .onEnded { calls.append("ended-1") }
      .onEnded { calls.append("ended-2") }
    let tap = _eraseGesture(callbacks)
    tap.actionBox.changed?("ignored")
    tap.actionBox.ended?("ignored")
    _expectEqual(calls, ["changed-1", "changed-2", "ended-1", "ended-2"])
    _expectTrue(tap._swiftUIWebSpec.encoded.contains("count=3"))

    let projected = GestureState(wrappedValue: 2)
    let projectedGesture = _eraseGesture(TapGesture().updating(projected) { _, state, transaction in
      state += 3
      transaction.disablesAnimations = true
    })
    projectedGesture.actionBox.changed?("")
    _expectEqual(projected.wrappedValue, 5)
    projectedGesture.actionBox.reset?()
    _expectEqual(projected.wrappedValue, 2)

    var legacy = GestureState(wrappedValue: 4)
    let legacyGesture = TapGesture().updating(legacy) { _, state, _ in state *= 2 }
    let erasedLegacy = _eraseGesture(legacyGesture)
    erasedLegacy.actionBox.changed?("")
    _expectEqual(legacy.wrappedValue, 8)
    erasedLegacy.actionBox.reset?()
    _expectEqual(legacy.wrappedValue, 4)
  }

  @Test
  func dragPayloadValidationDefaultsAndValueEqualityAreStable() {
    var changed: [DragGesture.Value] = []
    var ended: [DragGesture.Value] = []
    let erased = _eraseGesture(
      DragGesture(minimumDistance: 0)
        .onChanged { changed.append($0) }
        .onEnded { ended.append($0) }
    )

    erased.actionBox.changed?("1,2,0,0,5,6,8,9,10")
    erased.actionBox.changed?("1,2,0")
    erased.actionBox.ended?("bad")
    erased.actionBox.endedAction?()

    _expectEqual(changed.count, 1)
    _expectEqual(changed[0].translation.width, 1)
    _expectEqual(changed[0].velocity.width, 28)
    _expectEqual(changed[0].predictedEndTranslation.height, 9)
    _expectEqual(ended.count, 1)
    _expectEqual(ended[0], DragGesture.Value())

    let defaulted = DragGesture.Value(location: CGPoint(x: 7, y: 8))
    _expectEqual(defaulted.predictedEndLocation, defaulted.location)
    _expectEqual(defaulted.predictedEndTranslation, defaulted.translation)
    _expectTrue(defaulted == DragGesture.Value(location: defaulted.location))
    _expectTrue(defaulted != DragGesture.Value(location: CGPoint(x: 7, y: 9)))
  }

  @Test
  func transientDragIsOptInAndRetainsDeclaredCallbacks() {
    let regular = _eraseGesture(DragGesture(minimumDistance: 4).onEnded { _ in })
    let transient = _eraseGesture(
      DragGesture(minimumDistance: 4)
        .transientRendering()
        .onChanged { _ in }
        .onEnded { _ in }
    )

    #expect(!regular._swiftUIWebSpec.encoded.contains("transient=true"))
    #expect(transient._swiftUIWebSpec.encoded.contains("transient=true"))
    #expect(transient.actionBox.changed != nil)
    #expect(transient.actionBox.ended != nil)
  }

  @Test
  func magnifyAndRotatePayloadsAcceptPartialValuesAndRejectEmptyValues() {
    var magnifications: [MagnifyGesture.Value] = []
    var secondaryMagnifications: [Double] = []
    var magnifyEnds: [Double] = []
    let magnify = _eraseGesture(
      MagnifyGesture()
        .onChanged { magnifications.append($0) }
        .onChanged { secondaryMagnifications.append($0.magnification) }
        .onEnded { magnifyEnds.append($0.magnification) }
    )
    magnify.actionBox.changed?("1.5")
    magnify.actionBox.changed?("not-a-number")
    magnify.actionBox.changed?("2,1.25,0.5,10,3,4,5,6")
    magnify.actionBox.ended?("3")
    magnify.actionBox.endedAction?()
    _expectEqual(magnifications.count, 2)
    _expectEqual(magnifications[0].magnification, 1.5)
    _expectEqual(magnifications[0].startMagnification, 1)
    _expectEqual(magnifications[1].velocity, 0.5)
    _expectEqual(magnifications[1].startLocation.x, 3)
    _expectEqual(magnifications[1].location.y, 6)
    _expectEqual(Set(magnifications.map { $0.magnification }).count, 2)
    _expectEqual(secondaryMagnifications, [1.5, 2])
    _expectEqual(magnifyEnds, [3, 1])

    var rotations: [RotateGesture.Value] = []
    var rotationEnds: [Angle] = []
    let rotate = _eraseGesture(
      RotateGesture()
        .onChanged { rotations.append($0) }
        .onChanged { rotations.append($0) }
        .onEnded { rotationEnds.append($0.rotation) }
    )
    rotate.actionBox.changed?("")
    rotate.actionBox.changed?("0.5,0.2,0.1,11,1,2,3,4")
    rotate.actionBox.ended?("0.75")
    rotate.actionBox.endedAction?()
    _expectEqual(rotations.count, 2)
    _expectEqual(rotations[0].rotation, .radians(0.5))
    _expectEqual(rotations[0].startRotation, .radians(0.2))
    _expectEqual(rotations[0].velocity, .radians(0.1))
    _expectEqual(rotations[0].location.x, 3)
    _expectEqual(Set(rotations.map { $0.rotation.radians }).count, 1)
    _expectEqual(RotateGesture.Value(velocity: .radians(0.25)).velocity, .radians(0.25))
    _expectEqual(rotationEnds, [.radians(0.75), .zero])
  }

  @Test
  func gestureMetadataPropagatesAcrossFlattenedGroups() {
    struct GroupWithGesture: View {
      var body: some View {
        Group {
          Text("first")
          Text("second")
        }
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in })
      }
    }
    func collect(_ node: _RenderNode, into hosts: inout [_RenderNode]) {
      if node.attributes["data-gesture-count"] != nil { hosts.append(node) }
      for child in node.children { collect(child, into: &hosts) }
    }

    var hosts: [_RenderNode] = []
    collect(GroupWithGesture()._render(in: _RenderContext()), into: &hosts)
    _expectEqual(hosts.count, 2)
    _expectTrue(hosts.allSatisfy { $0.events.keys.contains { $0.hasSuffix("-changed") } })
  }

  @Test
  func longPressTreatsOnlyExplicitFalseAndCancellationAsFalse() {
    var values: [Bool] = []
    let longPress = _eraseGesture(
      LongPressGesture()
        .onChanged { values.append($0) }
        .onChanged { values.append(!$0) }
    )
    ["true", "false", "cancelled", "", "0"].forEach { longPress.actionBox.changed?($0) }
    _expectEqual(values, [true, false, false, true, false, true, true, false, true, false])

    var endings: [Bool] = []
    let ended = _eraseGesture(LongPressGesture().onEnded { endings.append($0) })
    ended.actionBox.ended?("cancelled")
    ended.actionBox.endedAction?()
    _expectEqual(endings, [false, true])
    var noArgumentEnds = 0
    let noArgumentEnd = _eraseGesture(LongPressGesture().onEnded { _ in noArgumentEnds += 1 })
    noArgumentEnd.actionBox.ended?("false")
    noArgumentEnd.actionBox.endedAction?()
    _expectEqual(noArgumentEnds, 2)

    var projected = GestureState(wrappedValue: false)
    let update = LongPressGesture().updating(projected) { pressed, state, _ in state = pressed }
      .onChanged { _ in }
    let erasedUpdate = _eraseGesture(update)
    erasedUpdate.actionBox.changed?("true")
    _expectTrue(projected.wrappedValue)
    erasedUpdate.actionBox.reset?()
    _expectFalse(projected.wrappedValue)

    let inoutGesture = LongPressGesture().updating(projected) { pressed, state, _ in state = pressed }
    let erasedInout = _eraseGesture(inoutGesture)
    erasedInout.actionBox.changed?("false")
    _expectFalse(projected.wrappedValue)
    erasedInout.actionBox.reset?()
  }

  @Test
  func genericGestureFallbackDecodesKnownValuesAndDoesNotInventUnknownDefaults() {
    var changes: [Int] = []
    var endings: [Int] = []
    let erased = _eraseGesture(IntegerGesture().onChanged { changes.append($0) })
    erased.actionBox.changed?("integer|42")
    erased.actionBox.changed?("integer|not-an-int")
    let erasedEnd = _eraseGesture(IntegerGesture().onEnded { (value: Int) in endings.append(value) })
    erasedEnd.actionBox.ended?("integer|7")
    erasedEnd.actionBox.endedAction?()
    _expectEqual(changes, [42])
    _expectEqual(endings, [7])

    var strings: [String] = []
    let stringGesture = _eraseGesture(StringGesture().onChanged { strings.append($0) })
    stringGesture.actionBox.changed?("custom|payload")
    _expectEqual(strings, ["payload"])
    var stringEnds: [String] = []
    let stringEnd = _eraseGesture(StringGesture().onEnded { stringEnds.append($0) })
    stringEnd.actionBox.ended?("custom|end")
    stringEnd.actionBox.endedAction?()
    _expectEqual(stringEnds, ["end"])

    var opaqueEnded = 0
    let opaque = _eraseGesture(OpaqueGesture().onEnded { _ in opaqueEnded += 1 })
    opaque.actionBox.ended?("unknown|payload")
    opaque.actionBox.endedAction?()
    _expectEqual(opaqueEnded, 0)

    var state = GestureState(wrappedValue: 1)
    let updating = IntegerGesture().updating(state) { value, current, _ in current = value }
    let erasedUpdating = _eraseGesture(updating)
    erasedUpdating.actionBox.changed?("bad")
    _expectEqual(state.wrappedValue, 1)
    erasedUpdating.actionBox.changed?("9")
    _expectEqual(state.wrappedValue, 9)
    erasedUpdating.actionBox.reset?()
    _expectEqual(state.wrappedValue, 1)

    let projectedState = GestureState(wrappedValue: 3)
    let projectedUpdating = IntegerGesture().updating(projectedState) { value, current, _ in current += value }
    let erasedProjected = _eraseGesture(projectedUpdating)
    erasedProjected.actionBox.changed?("2")
    _expectEqual(projectedState.wrappedValue, 5)
    erasedProjected.actionBox.reset?()
    _expectEqual(projectedState.wrappedValue, 3)
  }

  @Test
  func magnifyRotateAndErasedNoArgumentCallbacksKeepTheirLifecycle() {
    var magnifications: [Double] = []
    let magnify = _eraseGesture(MagnifyGesture().onEnded { value in
      magnifications.append(value.magnification)
    })
    magnify.actionBox.ended?("1.5,1,0,2,0,0,10,20")
    _expectEqual(magnifications, [1.5])

    var magnifyState = GestureState(wrappedValue: 1.0)
    let magnifyUpdating = MagnifyGesture().updating(magnifyState) { value, state, _ in
      state = value.magnification
    }
    let erasedMagnifyUpdating = _eraseGesture(magnifyUpdating)
    erasedMagnifyUpdating.actionBox.changed?("2,1,0,0,0,0,0,0")
    _expectEqual(magnifyState.wrappedValue, 2)
    erasedMagnifyUpdating.actionBox.reset?()
    _expectEqual(magnifyState.wrappedValue, 1)

    let rotateState = GestureState(wrappedValue: 0.0)
    let rotateUpdating = RotateGesture().updating(rotateState) { value, state, _ in
      state = value.rotation.radians
    }
    let erasedRotateUpdating = _eraseGesture(rotateUpdating)
    erasedRotateUpdating.actionBox.changed?("0.75,0,0,0,0,0")
    _expectEqual(rotateState.wrappedValue, 0.75)
    erasedRotateUpdating.actionBox.reset?()
    _expectEqual(rotateState.wrappedValue, 0)

    var noArgumentEnds = 0
    let noArgumentEnd = _eraseGesture(IntegerGesture().onEnded { _ in noArgumentEnds += 1 })
    noArgumentEnd.actionBox.endedAction?()
    // An integer value has no default, so an end without payload invents nothing.
    _expectEqual(noArgumentEnds, 0)
  }

  @Test
  func simultaneousUnknownGestureKindFallsBackToTheFirstTypedValue() {
    var received: [Int] = []
    let combined = IntegerGesture().simultaneously(with: StringGesture())
      .onChanged { value in
        if let first = value.first { received.append(first) }
      }

    _eraseGesture(combined).actionBox.changed?("custom|23")

    _expectEqual(received, [23])
  }

  @Test
  func simultaneousSequenceAndExclusiveCompositionsRouteValuesAndResetLifecycle() {
    var simultaneous: [String] = []
    let together = TapGesture().simultaneously(with: LongPressGesture())
      .onChanged { value in
        if let pressed = value.second { simultaneous.append("press:\(pressed)") }
        if value.first != nil { simultaneous.append("tap") }
      }
    let erasedTogether = _eraseGesture(together)
    erasedTogether.actionBox.changed?("longpress|true")
    erasedTogether.actionBox.changed?("tap|")
    _expectEqual(simultaneous, ["press:true", "tap"])

    var phases: [String] = []
    let sequence = IntegerGesture().sequenced(before: LongPressGesture()).onChanged { value in
      switch value {
      case .first(let first): phases.append("first:\(first)")
      case .second(let first, let second): phases.append("second:\(first):\(second ?? false)")
      }
    }
    let erasedSequence = _eraseGesture(sequence)
    erasedSequence.actionBox.changed?("7")
    erasedSequence.actionBox.changed?("longpress|true")
    erasedSequence.actionBox.reset?()
    erasedSequence.actionBox.changed?("longpress|true")
    _expectEqual(phases, ["first:7", "second:7:true"])

    var winners: [String] = []
    let exclusive = TapGesture().exclusively(before: LongPressGesture()).onEnded { value in
      switch value {
      case .first: winners.append("tap")
      case .second(let pressed): winners.append("press:\(pressed)")
      }
    }
    let erasedExclusive = _eraseGesture(exclusive)
    erasedExclusive.actionBox.ended?("longpress|false")
    erasedExclusive.actionBox.ended?("tap|")
    erasedExclusive.actionBox.endedAction?()
    _expectEqual(winners, ["press:false", "tap", "tap"])
  }

  @Test
  func compositionCallbacksChainForEndedPhasesAndNestedTaggedPayloads() {
    var simultaneousValues: [String] = []
    let simultaneous = TapGesture().simultaneously(with: LongPressGesture())
      .onEnded { value in
        simultaneousValues.append("first:\(value.first != nil),second:\(value.second ?? false)")
      }
      .onEnded { value in
        simultaneousValues.append("again:\(value.first != nil),\(value.second ?? false)")
      }
    let erasedSimultaneous = _eraseGesture(simultaneous)
    erasedSimultaneous.actionBox.ended?("longpress|true")
    erasedSimultaneous.actionBox.endedAction?()
    _expectEqual(simultaneousValues, [
      "first:false,second:true", "again:false,true", "first:false,second:false",
      "again:false,false"
    ])

    var sequenceChanges: [String] = []
    let sequence = TapGesture().sequenced(before: LongPressGesture())
      .onChanged { value in
        if case .first = value { sequenceChanges.append("first") }
      }
      .onChanged { value in
        if case .first = value { sequenceChanges.append("first-again") }
      }
    _eraseGesture(sequence).actionBox.changed?("tap|")
    _expectEqual(sequenceChanges, ["first", "first-again"])

    var dragValues: [Double] = []
    var pressValues: [Bool] = []
    let nested = DragGesture(minimumDistance: 0)
      .onChanged { dragValues.append($0.translation.width) }
      .simultaneously(with: LongPressGesture().onChanged { pressValues.append($0) })
      .sequenced(before: TapGesture())
    let erasedNested = _eraseGesture(nested)
    erasedNested.actionBox.changed?("drag|12,0,0,0,12,0")
    erasedNested.actionBox.changed?("longpress|true")
    _expectEqual(dragValues, [12])
    _expectEqual(pressValues, [true])
  }

  @Test
  func composedCallbacksFanOutEndCancellationAndGestureStateCleanup() {
    var calls: [String] = []
    let dragState = GestureState(wrappedValue: 0)
    let drag = DragGesture().updating(dragState) { value, state, _ in
      state = Int(value.translation.width)
    }.onEnded { value in calls.append("drag:\(value.translation.width)") }
    let pressState = GestureState(wrappedValue: false)
    let press = LongPressGesture().updating(pressState) { value, state, _ in state = value }
      .onEnded { value in calls.append("press:\(value)") }
    let composed = _eraseGesture(drag.simultaneously(with: press))

    composed.actionBox.changed?("drag|12,0,0,0,12,0")
    composed.actionBox.changed?("longpress|true")
    _expectEqual(dragState.wrappedValue, 12)
    _expectTrue(pressState.wrappedValue)
    composed.actionBox.ended?("drag|12,0,0,0,12,0")
    composed.actionBox.ended?("longpress|false")
    _expectEqual(calls, ["drag:12.0", "press:false"])
    composed.actionBox.endedAction?()
    _expectTrue(calls.contains("drag:0.0"))
    _expectTrue(calls.contains("press:true"))

    composed.actionBox.reset?()
    _expectEqual(dragState.wrappedValue, 0)
    _expectFalse(pressState.wrappedValue)
  }
}
