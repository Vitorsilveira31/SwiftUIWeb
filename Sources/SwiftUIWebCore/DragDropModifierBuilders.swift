// Non-generic builders for the `View` modifiers declared in DragDrop.swift.
// The generic methods only wrap the result with `modifier(_xxxModifier(...))`;
// building the style/attribute tables here compiles them once instead of once
// per view type the modifier is applied to.
@_spi(Browser) @_spi(Renderer) import SwiftUIWebTransferable

