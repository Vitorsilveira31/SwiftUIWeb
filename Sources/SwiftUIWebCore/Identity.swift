/// A compact identity key used by Fiber paths and keyed reconciliation.
///
/// Regular Swift builds preserve the full `AnyHashable` behavior. Embedded
/// Swift intentionally does not ship `AnyHashable`; its key representation is
/// specialized for scalar IDs, with lifetime-bounded typed identity for custom
/// Hashable values. No AnyHashable or runtime reflection is required.
#if hasFeature(Embedded)
/// A value that maps to a scalar `_FiberKey` without a dynamic cast.
public protocol _FiberKeyScalar { var _fiberKey: _FiberKey { get } }
extension Int: _FiberKeyScalar { public var _fiberKey: _FiberKey { _FiberKey(self) } }
extension UInt64: _FiberKeyScalar { public var _fiberKey: _FiberKey { _FiberKey(self) } }
extension Bool: _FiberKeyScalar { public var _fiberKey: _FiberKey { _FiberKey(self) } }
extension String: _FiberKeyScalar { public var _fiberKey: _FiberKey { _FiberKey(self) } }
extension _FiberKey: _FiberKeyScalar { public var _fiberKey: _FiberKey { self } }

public struct _FiberKey: Hashable {
  private enum Storage {
    case integer(Int)
    case unsigned(UInt64)
    case boolean(Bool)
    case string(String)
    case opaque(_EmbeddedOpaqueIdentity)
  }

  private let storage: Storage

  // Scalar identities have their own initializers: a generic cast chain cannot be resolved for every fixed-width
  // type in Embedded Swift (it needs the runtime cast the target does not have).
  public init(_ value: Int) { storage = .integer(value) }
  public init(_ value: Int8) { storage = .integer(Int(value)) }
  public init(_ value: Int16) { storage = .integer(Int(value)) }
  public init(_ value: Int32) { storage = .integer(Int(value)) }
  public init(_ value: Int64) { storage = .integer(Int(truncatingIfNeeded: value)) }
  public init(_ value: UInt) { storage = .unsigned(UInt64(value)) }
  public init(_ value: UInt8) { storage = .unsigned(UInt64(value)) }
  public init(_ value: UInt16) { storage = .unsigned(UInt64(value)) }
  public init(_ value: UInt32) { storage = .unsigned(UInt64(value)) }
  public init(_ value: UInt64) { storage = .unsigned(value) }
  public init(_ value: Bool) { storage = .boolean(value) }
  public init(_ value: String) { storage = .string(value) }

  /// Any other Hashable identity is interned by type and value. A scalar that reaches this initializer through a
  /// generic API (`.id(row.id)`, `ForEach(id:)`, `scrollTo(_:)`) is still a scalar: it must equal the key the
  /// concrete initializers above build for the same value, and keep its readable DOM marker. The exact type is
  /// recognized by its stored type token, which needs no runtime cast.
  public init<ID: Hashable>(_ value: ID) {
    if let key = _FiberKey._scalar(value) { self = key } else { storage = .opaque(.intern(value)) }
  }

  @inline(__always)
  private static func _scalar<ID>(_ value: ID) -> _FiberKey? {
    if let value = _exactly(value, as: _FiberKey.self) { return value }
    if let value = _exactly(value, as: Int.self) { return _FiberKey(value) }
    if let value = _exactly(value, as: String.self) { return _FiberKey(value) }
    if let value = _exactly(value, as: UInt64.self) { return _FiberKey(value) }
    if let value = _exactly(value, as: Bool.self) { return _FiberKey(value) }
    if let value = _exactly(value, as: Int8.self) { return _FiberKey(value) }
    if let value = _exactly(value, as: Int16.self) { return _FiberKey(value) }
    if let value = _exactly(value, as: Int32.self) { return _FiberKey(value) }
    if let value = _exactly(value, as: Int64.self) { return _FiberKey(value) }
    if let value = _exactly(value, as: UInt.self) { return _FiberKey(value) }
    if let value = _exactly(value, as: UInt8.self) { return _FiberKey(value) }
    if let value = _exactly(value, as: UInt16.self) { return _FiberKey(value) }
    if let value = _exactly(value, as: UInt32.self) { return _FiberKey(value) }
    return nil
  }

  @inline(__always)
  private static func _exactly<Value, Target>(_ value: Value, as target: Target.Type) -> Target? {
    guard _storedTypeID(Value.self) == _storedTypeID(Target.self) else { return nil }
    // SAFETY: equal stored type tokens mean `Value` and `Target` are the same type, so the cast is an ordinary copy of the
    // value (retaining any reference it holds). A cast rather than `withUnsafePointer(to:)`: see `_identityExactly`.
    return unsafeBitCast(value, to: Target.self)
  }

  /// Identities that already are scalars (or keys) take the direct path, chosen by overload resolution.
  public init<ID: Hashable & _FiberKeyScalar>(_ value: ID) {
    self = value._fiberKey
  }

  /// An optional ID (`NavigationLink(value: selection.first)`): `nil` is its own key, a value is the wrapped value's key.
  public init<ID: Hashable>(_ value: ID?) {
    if let value { self = _FiberKey(value) } else { self = _FiberKey("\u{0}nil") }
  }

  fileprivate var displayDescription: String {
    switch storage {
    case .integer(let value): return String(value)
    case .unsigned(let value): return String(value)
    case .boolean(let value): return value ? "true" : "false"
    case .string(let value): return value
    case .opaque(let value): return "typed-\(value.serial)"
    }
  }

  public static func == (lhs: _FiberKey, rhs: _FiberKey) -> Bool {
    switch (lhs.storage, rhs.storage) {
    case (.integer(let lhs), .integer(let rhs)): return lhs == rhs
    case (.unsigned(let lhs), .unsigned(let rhs)): return lhs == rhs
    case (.boolean(let lhs), .boolean(let rhs)): return lhs == rhs
    case (.string(let lhs), .string(let rhs)): return lhs == rhs
    case (.opaque(let lhs), .opaque(let rhs)): return lhs === rhs
    default: return false
    }
  }

  public func hash(into hasher: inout Hasher) {
    switch storage {
    case .integer(let value): hasher.combine(0); hasher.combine(value)
    case .unsigned(let value): hasher.combine(1); hasher.combine(value)
    case .boolean(let value): hasher.combine(2); hasher.combine(value)
    case .string(let value):
      hasher.combine(3)
      hasher.combine(value)
    case .opaque(let value):
      hasher.combine(4); hasher.combine(value.fingerprint)
    }
  }
}
#else
public typealias _FiberKey = AnyHashable
#endif

// Embedded Swift intentionally omits runtime reflection. Keep diagnostic and
// browser-token generation behind one compatibility surface so public APIs do
// not need to expose an alternate Embedded spelling. Constrained values retain
// their semantic descriptions; opaque generic values use a stable token.
@inline(__always)
package func _swiftUIWebDescribe<T: CustomStringConvertible>(_ value: T) -> String {
  value.description
}

/// Optional identities (for example `.task(id: model.url)`) describe their
/// wrapped value without a dynamic cast, which Embedded Swift cannot perform.
@inline(__always)
func _swiftUIWebDescribe<T: CustomStringConvertible>(_ value: T?) -> String {
  value.map { "some(" + $0.description + ")" } ?? "nil"
}

/// Raw-value enums used as identities (`.task(id: tab)`, tags, focus values).
@inline(__always)
func _swiftUIWebDescribe<T: RawRepresentable>(_ value: T) -> String where T.RawValue: CustomStringConvertible {
  value.rawValue.description
}

@inline(__always)
func _swiftUIWebDescribe<T: RawRepresentable>(_ value: T?) -> String where T.RawValue: CustomStringConvertible {
  value.map { "some(" + $0.rawValue.description + ")" } ?? "nil"
}

/// The value as `Target` when `Value` is exactly `Target`, decided by the stored type token rather than a cast. Embedded
/// Swift has no dynamic casts, but a generic identity (`.task(id:)`) still needs its concrete type's description.
@inline(__always)
private func _identityExactly<Value, Target>(_ value: Value, as target: Target.Type) -> Target? {
  guard _storedTypeID(Value.self) == _storedTypeID(Target.self) else { return nil }
  // SAFETY: equal stored type tokens mean `Value` is `Target`, so the cast is an ordinary copy of the value (retaining any
  // reference it holds). Not `withUnsafePointer(to:)` with a closure: Embedded Swift specializes that closure once per
  // type and serializes the specializations in a different order on every compile, which made this module's
  // `.swiftmodule` change on every build and rebuilt everything that imports it
  // (Documentation/Performance/BUILD_TIME.md, "The development loop").
  return unsafeBitCast(value, to: Target.self)
}

/// Describes a generic identity whose concrete type is only known at run time: scalars and their optionals, which is
/// what `task(id:)` and `.id(_:)` callers pass. Other types keep a stable token, since Embedded has no reflection.
@inline(__always)
package func _swiftUIWebDescribe<T>(_ value: T) -> String {
  #if hasFeature(Embedded)
  if let text = _identityExactly(value, as: String.self) { return text }
  if let number = _identityExactly(value, as: Int.self) { return String(number) }
  if let number = _identityExactly(value, as: Int64.self) { return String(number) }
  if let number = _identityExactly(value, as: Int32.self) { return String(number) }
  if let number = _identityExactly(value, as: UInt.self) { return String(number) }
  if let number = _identityExactly(value, as: UInt64.self) { return String(number) }
  if let number = _identityExactly(value, as: UInt32.self) { return String(number) }
  if let number = _identityExactly(value, as: Double.self) { return String(number) }
  if let number = _identityExactly(value, as: Float.self) { return String(number) }
  if let flag = _identityExactly(value, as: Bool.self) { return flag ? "true" : "false" }
  if let text = _identityExactly(value, as: String?.self) { return _swiftUIWebDescribe(text) }
  if let number = _identityExactly(value, as: Int?.self) { return _swiftUIWebDescribe(number) }
  if let number = _identityExactly(value, as: Int64?.self) { return _swiftUIWebDescribe(number) }
  if let number = _identityExactly(value, as: UInt64?.self) { return _swiftUIWebDescribe(number) }
  if let number = _identityExactly(value, as: UInt?.self) { return _swiftUIWebDescribe(number) }
  if let flag = _identityExactly(value, as: Bool?.self) { return _swiftUIWebDescribe(flag) }
  return "value"
  #else
  return String(describing: value)
  #endif
}

@_transparent
package func _swiftUIWebTypeName<T>(_ type: T.Type) -> String {
  #if hasFeature(Embedded)
  return _swiftUIWebTypeName(id: _storedTypeID(type))
  #else
  return String(reflecting: type)
  #endif
}

#if hasFeature(Embedded)
/// The text of `_swiftUIWebTypeName`, out of the generic function so it is compiled once rather than once per type.
@inline(never)
func _swiftUIWebTypeName(id: ObjectIdentifier) -> String {
  "type-" + String(UInt(bitPattern: id))
}
#endif

/// Returns a deterministic textual form for a Fiber identity component.
/// This is public for the Fiber implementation module; applications normally
/// only observe the composed `FiberIdentity.description`.
@inline(__always)
/// A key as one component of a path's text. An identity from data ("a/b", "x#state0@Row") would otherwise read as two
/// components or as a state key's suffix, and two views would share state; "%", "/" and "#" are written as %25, %2F
/// and %23, so the text names one path only.
func _pathComponentText(_ key: _FiberKey) -> String {
  let text = fiberKeyDescription(key)
  guard text.contains(where: { $0 == "%" || $0 == "/" || $0 == "#" }) else { return text }
  var escaped = ""
  for character in text {
    switch character {
    case "%": escaped += "%25"
    case "/": escaped += "%2F"
    case "#": escaped += "%23"
    default: escaped.append(character)
    }
  }
  return escaped
}

package func fiberKeyDescription(_ key: _FiberKey) -> String {
  #if hasFeature(Embedded)
  return key.displayDescription
  #else
  return String(describing: key)
  #endif
}

/// The identity path of a view: the keys from the root to the view, kept as a chain that shares its prefix.
///
/// A path used to be an array of keys, so every level copied the whole path of the level above it (the context a view
/// renders in, the identity of the fiber that results, the state scope recorded for the node) and a tree `n` levels
/// deep cost `n^2` in time and memory. This is a persistent list instead: appending a key allocates one link that
/// points at its parent, so a level costs the same at any depth, and two paths with a common prefix share it. Each link
/// keeps its depth and a hash of everything above it, so hashing a path is a read and comparing two unequal paths
/// is too; two equal paths that were built apart are compared link by link, up to the first link they share.
///
/// The text of a path (`a/b/c`, the form state keys, DOM markers and storage scopes are built from) is made only for
/// the paths that ask for it, and kept on the link it was made for.
@_spi(Renderer) public struct _FiberPath: Hashable, CustomStringConvertible {
  final class Link {
    fileprivate(set) var parent: Link?
    let key: _FiberKey
    let depth: Int
    let hash: Int
    var text: String?
    /// Two independent 64-bit hashes of the path up to this link (0: not made yet), see `_FiberPath.compactID`.
    var compactHash: UInt64 = 0
    var compactFingerprint: UInt64 = 0

    init(parent: Link?, key: _FiberKey) {
      self.parent = parent
      self.key = key
      depth = (parent?.depth ?? 0) + 1
      var hasher = Hasher()
      hasher.combine(parent?.hash ?? 0)
      hasher.combine(key)
      hash = hasher.finalize()
    }

    /// Releases the chain above this link from a loop. Freeing the last link of a deep path would otherwise free its
    /// parent from inside its own `deinit`, and that one its parent, a few call frames per level.
    deinit {
      guard var current = parent else { return }
      parent = nil
      while isKnownUniquelyReferenced(&current), let next = current.parent {
        current.parent = nil
        current = next
      }
    }
  }

  /// Levels between the links that remember their text on the way to a requested one.
  private static var textCheckpointSpacing: Int { 64 }

  var link: Link?

  public init() {}
  init(link: Link?) { self.link = link }
  public init(_ keys: [_FiberKey]) {
    var path = _FiberPath()
    for key in keys { path.append(key) }
    self = path
  }

  public var count: Int { link?.depth ?? 0 }
  public var isEmpty: Bool { link == nil }
  /// The last key, the one this path ends with.
  public var last: _FiberKey? { link?.key }
  /// This path without its last key.
  public var parent: _FiberPath { _FiberPath(link: link?.parent) }

  public mutating func append(_ key: _FiberKey) { link = Link(parent: link, key: key) }
  public func appending(_ key: _FiberKey) -> _FiberPath { _FiberPath(link: Link(parent: link, key: key)) }

  /// The keys, from the root. Linear in the depth: for code that needs the whole list.
  public var keys: [_FiberKey] {
    var result: [_FiberKey] = []
    result.reserveCapacity(count)
    var current = link
    while let link = current { result.append(link.key); current = link.parent }
    result.reverse()
    return result
  }

  /// Whether this path is `other`, or a path above it.
  public func isPrefix(of other: _FiberPath) -> Bool {
    guard count <= other.count else { return false }
    var longer = other.link
    while let candidate = longer, candidate.depth > count { longer = candidate.parent }
    return _FiberPath(link: longer) == self
  }

  /// `a/b/c`: the description of each key, joined by `/`.
  public var description: String {
    guard let link else { return "" }
    if let text = link.text { return text }
    // The parts above the nearest link whose text is known, root-last.
    var parts: [Link] = []
    var current: Link? = link
    var base: String?
    while let candidate = current {
      if let text = candidate.text { base = text; break }
      parts.append(candidate)
      current = candidate.parent
    }
    var result = base ?? ""
    var first = base == nil
    var index = parts.count - 1
    while index >= 0 {
      if !first { result += "/" }
      result += _pathComponentText(parts[index].key)
      first = false
      // A checkpoint every `textCheckpointSpacing` levels, so that the text of a path whose ancestors were never asked
      // for (the render settles the inner levels of a chain first) builds from the nearest checkpoint, not the root.
      if index > 0, parts[index].depth % Self.textCheckpointSpacing == 0 { parts[index].text = result }
      index -= 1
    }
    link.text = result
    return result
  }

  /// A short, stable name for this path: the same path gets the same text in every run and in every document, and the
  /// text is as long as a 64-bit number at any depth (the text of the path, `description`, is as long as the depth).
  /// For DOM ids and attributes that only have to be unique and stable, where the path text made the HTML
  /// `O(nodes * depth)`. Two different paths that share the 64-bit hash get a `-N` suffix from `registry`, in the order the
  /// registry saw them. The empty path is `root`.
  /// `_compactID(in:)` if `registry` already gave this path one, without giving it one.
  package func _knownCompactID(in registry: _CompactPathIDRegistry) -> String? {
    guard let (hash, fingerprint) = compactHashes() else { return "root" }
    return registry.knownID(hash: hash, fingerprint: fingerprint)
  }

  public func _compactID(in registry: _CompactPathIDRegistry) -> String {
    guard let (hash, fingerprint) = compactHashes() else { return "root" }
    return registry.id(hash: hash, fingerprint: fingerprint)
  }

  /// The hash pair of this path, made from the nearest ancestor that has one: one pass over the keys that have none.
  private func compactHashes() -> (UInt64, UInt64)? {
    guard let link else { return nil }
    if link.compactHash != 0 { return (link.compactHash, link.compactFingerprint) }
    var pending: [Link] = []
    var current: Link? = link
    while let candidate = current, candidate.compactHash == 0 {
      pending.append(candidate)
      current = candidate.parent
    }
    var first = current?.compactHash ?? 0xcbf2_9ce4_8422_2325
    var second = current?.compactFingerprint ?? 0x9e37_79b9_7f4a_7c15
    for candidate in pending.reversed() {
      for byte in _pathComponentText(candidate.key).utf8 {
        first = (first ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        second = (second &+ UInt64(byte) &+ 1) &* 0x9e37_79b9_7f4a_7c15
        second ^= second >> 29
      }
      // The key separator, so that `ab/c` and `a/bc` differ.
      first = (first ^ 0x2f) &* 0x0000_0100_0000_01b3
      second = (second &+ 0x2f &+ 1) &* 0x9e37_79b9_7f4a_7c15
      second ^= second >> 29
      if first == 0 { first = 1 }
      candidate.compactHash = first
      candidate.compactFingerprint = second
    }
    return (link.compactHash, link.compactFingerprint)
  }

  public static func == (lhs: _FiberPath, rhs: _FiberPath) -> Bool {
    var left = lhs.link
    var right = rhs.link
    if left === right { return true }
    guard let l = left, let r = right, l.depth == r.depth, l.hash == r.hash else { return false }
    left = l
    right = r
    while let a = left, let b = right {
      if a === b { return true }
      if a.hash != b.hash || a.key != b.key { return false }
      left = a.parent
      right = b.parent
    }
    return left == nil && right == nil
  }

  public func hash(into hasher: inout Hasher) { hasher.combine(link?.hash ?? 0) }
}

/// Hands out the compact ids of `_FiberPath._compactID`, one registry per document (it lives in the state store).
///
/// The id of a path is its 64-bit hash. A second, independent hash of the same path tells a collision from the same
/// path asked again: the first path to claim a hash keeps the bare id, the next different one with the same hash gets
/// `-1`, and so on, so two live paths never share an id. The registry keeps 16 bytes per distinct path, no paths; when it
/// holds more than `capacity` it is emptied (ids stay the same, only the suffix of a path that collided could change).
@_spi(Renderer) public final class _CompactPathIDRegistry {
  private var claims: [UInt64: [UInt64]] = [:]
  private var count = 0
  private let capacity: Int

  public init(capacity: Int = 1 << 18) { self.capacity = capacity }

  /// The id `id(hash:fingerprint:)` gave this pair, or nil when it never gave one (it claims nothing).
  package func knownID(hash: UInt64, fingerprint: UInt64) -> String? {
    guard let existing = claims[hash], let index = existing.firstIndex(of: fingerprint) else { return nil }
    let base = String(hash, radix: 36)
    return index > 0 ? base + "-" + String(index) : base
  }

  public func id(hash: UInt64, fingerprint: UInt64) -> String {
    var base = String(hash, radix: 36)
    if let existing = claims[hash] {
      if let index = existing.firstIndex(of: fingerprint) {
        if index > 0 { base += "-" + String(index) }
        return base
      }
      claims[hash]!.append(fingerprint)
      count += 1
      return base + "-" + String(existing.count)
    }
    if count >= capacity {
      claims.removeAll(keepingCapacity: true)
      count = 0
    }
    claims[hash] = [fingerprint]
    count += 1
    return base
  }
}

// Duplicate IDs are invalid as a SwiftUI collection identity, but they must
// never collapse two live records into one Fiber path. Later occurrences get
// a typed deterministic scope shared by rendering, state lookup and retained
// reconciliation. This is not a DOM-order identity.
#if hasFeature(Embedded)
private struct _EmbeddedDuplicateIdentity: Hashable {
  let base: _FiberKey
  let occurrence: Int
}
#else
private struct _DuplicateIdentity: Hashable {
  let base: AnyHashable
  let occurrence: Int
}
#endif

@_spi(Renderer) @inline(__always)
public func _fiberKeyWithOccurrence(_ key: _FiberKey, _ occurrence: Int) -> _FiberKey {
  guard occurrence > 0 else { return key }
  #if hasFeature(Embedded)
  return _FiberKey(_EmbeddedDuplicateIdentity(base: key, occurrence: occurrence))
  #else
  return _FiberKey(_DuplicateIdentity(base: key, occurrence: occurrence))
  #endif
}
