@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

/// What a view's generated `_sameInputs` compares each of its stored inputs with (the source lowering writes one call per
/// property: `_swiftUIWebSame(lhs.title, rhs.title) && ...`). The overload is chosen where the call is compiled, from the
/// property's type: a value that is `Equatable` by `==`, an object by identity, anything else (a struct that is not
/// `Equatable`, a closure) by its bytes: the same bytes are the same values and the same references, as SwiftUI compares
/// a view's fields. A value rebuilt from new storage (a new array, a closure with a new context) does not compare the
/// same, and its view is rendered again as it would be without the comparison. The remembered value keeps what it
/// refers to alive, so an address is never compared after it was reused for something else.
///
/// An object compared by identity may have changed inside: an `@Observable` model is read through the state store, so a
/// view that read what changed is invalidated by it whether or not its parent rendered again. A plain class read in a
/// body is not, as in SwiftUI.
@MainActor @inlinable public func _swiftUIWebSame<T>(_ lhs: T, _ rhs: T) -> Bool {
  withUnsafeBytes(of: lhs) { left in withUnsafeBytes(of: rhs) { right in left.elementsEqual(right) } }
}

@MainActor @inlinable public func _swiftUIWebSame<T: Equatable>(_ lhs: T, _ rhs: T) -> Bool { lhs == rhs }

@MainActor @inlinable public func _swiftUIWebSame<T: AnyObject>(_ lhs: T, _ rhs: T) -> Bool { lhs === rhs }

@MainActor @inlinable public func _swiftUIWebSame<T: AnyObject & Equatable>(_ lhs: T, _ rhs: T) -> Bool { lhs === rhs || lhs == rhs }

@MainActor @inlinable public func _swiftUIWebSame<T: AnyObject>(_ lhs: T?, _ rhs: T?) -> Bool { lhs === rhs }

@MainActor @inlinable public func _swiftUIWebSame<T: AnyObject & Equatable>(_ lhs: T?, _ rhs: T?) -> Bool { lhs === rhs || lhs == rhs }
