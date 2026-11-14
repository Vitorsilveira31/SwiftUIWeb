// Non-generic builders for the `View` modifiers declared in Modifiers.swift.
// The generic methods only wrap the result with `modifier(_xxxModifier(...))`;
// building the style/attribute tables here compiles them once instead of once
// per view type the modifier is applied to.


// Same formatting as the private `clean` in the source file these builders belong to.
// Int64(exactly:) is nil, not a trap, for a whole value Int64 cannot hold (`.opacity(1e300)`).
private extension Double { var clean: String { Int64(exactly: self).map { String($0) } ?? String(self) } }

@inline(never)
func _onTapGestureModifier(count: Int, perform action: @escaping @MainActor () -> Void) -> EventModifier {
  return EventModifier(name: count == 2 ? "dblclick" : "click", action: action)
}


@inline(never)
func _onFocusModifier(_ action: @escaping @MainActor () -> Void) -> EventModifier {
  return EventModifier(name: "focus", action: action)
}

@inline(never)
func _onBlurModifier(_ action: @escaping @MainActor () -> Void) -> EventModifier {
  return EventModifier(name: "blur", action: action)
}

@inline(never)
func _onHoverModifier(perform action: @escaping @MainActor (Bool) -> Void) -> HoverModifier {
  return HoverModifier(action: action)
}

@inline(never)
func _defaultHoverEffectModifier(_ effect: HoverEffect) -> DefaultHoverEffectModifier {
  return DefaultHoverEffectModifier(effect: effect)
}

@inline(never)
func _hoverEffectDisabledModifier(_ disabled: Bool) -> HoverEffectDisabledModifier {
  return HoverEffectDisabledModifier(disabled: disabled)
}

@inline(never)
func _hoverEffectGroupModifier() -> HoverEffectGroupModifier {
  return HoverEffectGroupModifier(group: nil, implicit: true)
}

@inline(never)
func _hoverEffectGroupModifier(_ group: HoverEffectGroup?) -> HoverEffectGroupModifier {
  return HoverEffectGroupModifier(group: group)
}

@inline(never)
func _hoverEffectGroupModifier(id: String?, in namespace: Namespace.ID, behavior: HoverEffectGroup.Behavior) -> HoverEffectGroupModifier {
  return HoverEffectGroupModifier(group: HoverEffectGroup(id: id, in: namespace, behavior: behavior))
}

@inline(never)
func _listRowHoverEffectModifier(_ effect: HoverEffect?) -> ListRowHoverEffectModifier {
  return ListRowHoverEffectModifier(effect: effect)
}

@inline(never)
func _listRowHoverEffectDisabledModifier(_ disabled: Bool) -> ListRowHoverEffectDisabledModifier {
  return ListRowHoverEffectDisabledModifier(disabled: disabled)
}

@inline(never)
func _onAppearModifier(perform action: @escaping @MainActor () -> Void) -> LifecycleModifier {
  return LifecycleModifier(appear: action, disappear: nil)
}

@inline(never)
func _onDisappearModifier(perform action: @escaping @MainActor () -> Void) -> LifecycleModifier {
  return LifecycleModifier(appear: nil, disappear: action)
}

@inline(never)
func _foregroundColorModifier(_ color: Color) -> ForegroundModifier {
  return ForegroundModifier(color: color)
}


@inline(never)
func _offsetModifier(x: Double, y: Double) -> StyleModifier {
  return StyleModifier(styles: ["transform": "translate(\(x.clean)px, \(y.clean)px)"])
}

@inline(never)
func _opacityModifier(_ value: Double) -> StyleModifier {
  return StyleModifier(styles: ["opacity": "\(value.clean)"])
}

@inline(never)
func _accessibilityLabelModifier(_ label: String) -> AttributeModifier {
  return AttributeModifier(attributes: ["aria-label": label])
}

@inline(never)
func _accessibilityIdentifierModifier(_ identifier: String) -> AttributeModifier {
  return AttributeModifier(attributes: ["data-testid": identifier])
}

@inline(never)
func _fontModifier(_ font: Font) -> FontModifier {
  return FontModifier(font: font)
}

@inline(never)
func _boldModifier() -> StyleModifier {
  return StyleModifier(styles: ["font-weight": "700"])
}

@inline(never)
func _italicModifier() -> StyleModifier {
  return StyleModifier(styles: ["font-style": "italic"])
}

@inline(never)
func _disabledModifier(_ disabled: Bool) -> DisabledModifier {
  return DisabledModifier(disabled: disabled)
}

@inline(never)
func _hiddenModifier() -> StyleModifier {
  return StyleModifier(styles: ["display": "none"])
}

@inline(never)
func _clippedModifier() -> StyleModifier {
  return StyleModifier(styles: ["overflow": "hidden"])
}

@inline(never)
func _cornerRadiusModifier(_ radius: Double) -> StyleModifier {
  return StyleModifier(styles: ["border-radius": "\(radius.clean)px"])
}

@inline(never)
func _borderModifier(_ color: Color, width: Double) -> StyleModifier {
  return StyleModifier(styles: ["border": "\(width.clean)px solid \(color.cssValue)"])
}

@inline(never)
func _multilineTextAlignmentModifier(_ alignment: TextAlignment) -> StyleModifier {
  return StyleModifier(styles: ["text-align": alignment.rawValue])
}

@inline(never)
func _layoutPriorityModifier(_ value: Double) -> LayoutPriorityModifier {
  return LayoutPriorityModifier(value: value)
}

@inline(never)
func _taskModifier(priority: TaskPriority, _ action: @escaping @MainActor () async -> Void) -> TaskModifier {
  return TaskModifier(priority: priority, action: action)
}

/// The runtime runs task bodies on the main actor, so Apple's `@isolated(any)`
/// action is forwarded through a main-actor closure.
func _mainActorTask(_ action: sending @escaping @isolated(any) () async -> Void) -> @MainActor () async -> Void {
  return { await action() }
}

@inline(never)
func _transitionModifier(_ transition: AnyTransition) -> TransitionModifier {
  return TransitionModifier(transition: transition)
}

@inline(never)
func _badgeModifier(_ value: Int) -> BadgeModifier {
  // As in SwiftUI, a count of zero shows no badge.
  return BadgeModifier(value: value > 0 ? String(value) : nil)
}

@inline(never)
func _badgeModifier(_ value: Int?) -> BadgeModifier {
  return BadgeModifier(value: value.flatMap { $0 > 0 ? String($0) : nil })
}

@inline(never)
func _badgeModifier(_ value: String) -> BadgeModifier {
  return BadgeModifier(value: value)
}

@inline(never)
func _badgeModifier(_ value: String?) -> BadgeModifier {
  return BadgeModifier(value: value)
}

@inline(never)
func _badgeModifier(_ value: Text) -> BadgeModifier {
  return BadgeModifier(value: value.value)
}

@inline(never)
func _badgeModifier(_ value: Text?) -> BadgeModifier {
  return BadgeModifier(value: value?.value)
}

@inline(never)
func _customizationIDModifier(_ identifier: String) -> TabCustomizationIDModifier {
  return TabCustomizationIDModifier(identifier: identifier)
}

@inline(never)
func _tabViewCustomizationModifier(_ customization: Binding<TabViewCustomization>?) -> TabViewCustomizationModifier {
  // A nil binding leaves the tab view uncustomized, as an empty customization does.
  guard let customization else { return TabViewCustomizationModifier(value: TabViewCustomization()) }
  return TabViewCustomizationModifier(binding: customization)
}

@inline(never)
func _tabViewMountPolicyModifier(_ policy: TabViewMountPolicy) -> TabViewMountPolicyModifier {
  return TabViewMountPolicyModifier(policy: policy)
}

@inline(never)
func _preferredColorSchemeModifier(_ scheme: ColorScheme?) -> ColorSchemeModifier {
  return ColorSchemeModifier(scheme: scheme)
}

@inline(never)
func _searchableModifier(text: Binding<String>, placement: SearchFieldPlacement, prompt: String) -> SearchableModifier {
  return SearchableModifier(text: text, placement: placement, prompt: prompt)
}
