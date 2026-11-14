// Foundation-free, type-preserving storage shared by standard and Embedded builds.
// Values are immutable once boxed. Replacing a dictionary entry preserves the
// value semantics of copied environments, including optional values whose payload
// is nil. There is no reflection, Any, unsafeBitCast, or hash-only type identity.

private final class _StoredValue {
  let typeID: ObjectIdentifier
  /// What the environment wrote here, for `EquatableView` (see `_EnvironmentStamp`).
  let stamp: _EnvironmentStamp
  private let copyValue: (UnsafeMutableRawPointer) -> Void

  private init(typeID: ObjectIdentifier, stamp: _EnvironmentStamp, copyValue: @escaping (UnsafeMutableRawPointer) -> Void) {
    self.typeID = typeID
    self.stamp = stamp
    self.copyValue = copyValue
  }

  static func storing<Value>(_ value: Value, stamp: _EnvironmentStamp = .absent) -> _StoredValue {
    // Capture the typed value instead of casting a generic class at runtime.
    // This also avoids asking Embedded IRGen for class metadata whose generic
    // destructor has never been instantiated (for a missing/mismatched type).
    return _StoredValue(typeID: _storedTypeID(Value.self), stamp: stamp) { destination in
      // SAFETY: read(as:) checks the exact type token and supplies an initialized
      // Optional<Value> stack slot. The closure does not retain the pointer.
      destination.assumingMemoryBound(to: Optional<Value>.self).pointee = .some(value)
    }
  }

  func read<Value>(as type: Value.Type) -> Value? {
    guard typeID == _storedTypeID(type) else { return nil }
    var result: Value? = nil
    // The inout-to-pointer conversion, not `withUnsafeMutablePointer(to:)`: a closure passed to it from a generic function
    // gets one specialization per type, and Embedded Swift serializes those in a different order on every compile, so the
    // module of this target changed on every build and rebuilt everything that imports it
    // (Documentation/Performance/BUILD_TIME.md, "The development loop").
    copyValue(&result)
    return result
  }
}

/// A class metatype gives Embedded Swift a stable type token even for value types.
/// The token is private to this module and never crosses the JavaScript ABI.
private final class _StoredTypeToken<Value> {}

@inline(__always)
func _storedTypeID<Value>(_ type: Value.Type) -> ObjectIdentifier {
  ObjectIdentifier(_StoredTypeToken<Value>.self)
}

/// A second identifier per type, for the environment-object stamp of `Value` (its key-path entries use
/// `_storedTypeID`).
private final class _ObjectStampToken<Value> {}
func _objectStampID<Value>(_ type: Value.Type) -> ObjectIdentifier {
  ObjectIdentifier(_ObjectStampToken<Value>.self)
}

struct _TypedValueStorage<Key: Hashable> {
  private var entries: [Key: _StoredValue] = [:]

  var count: Int { entries.count }
  var keys: [Key] { Array(entries.keys) }
  var isEmpty: Bool { entries.isEmpty }

  func contains(_ key: Key) -> Bool { entries[key] != nil }

  func value<Value>(for key: Key, as type: Value.Type = Value.self) -> Value? {
    guard let box = entries[key] else { return nil }
    // The outer Optional describes presence; the stored value may itself be nil.
    return box.read(as: type)
  }

  mutating func set<Value>(_ value: Value, for key: Key, stamp: _EnvironmentStamp = .absent) {
    entries[key] = _StoredValue.storing(value, stamp: stamp)
  }

  func stamp(for key: Key) -> _EnvironmentStamp? { entries[key]?.stamp }

  /// Takes `other`'s entry for `key` (or its absence) as this storage's.
  mutating func _copyEntry(_ key: Key, from other: _TypedValueStorage<Key>) { entries[key] = other.entries[key] }

  /// Removes before returning a value so a mutable accumulator does not retain
  /// a second, obsolete owner and force an Array copy on every append.
  mutating func takeValue<Value>(for key: Key, as type: Value.Type = Value.self) -> Value? {
    guard let box = entries[key], box.typeID == _storedTypeID(type) else { return nil }
    entries.removeValue(forKey: key)
    return box.read(as: type)
  }

  mutating func removeValue(for key: Key) { entries.removeValue(forKey: key) }

  mutating func removeAll(keepingCapacity: Bool = false) {
    entries.removeAll(keepingCapacity: keepingCapacity)
  }
}

/// Internal onChange history. Optional.none is a value, not a missing entry.
struct _TypedChangeHistory<Key: Hashable> {
  private var values = _TypedValueStorage<Key>()

  mutating func remember<Value: Equatable>(
    _ key: Key, value: Value
  ) -> (changed: Bool, previous: Value?, initial: Bool) {
    guard let previous: Value = values.value(for: key) else {
      values.set(value, for: key)
      return (false, nil, true)
    }
    values.set(value, for: key)
    return (previous != value, .some(previous), false)
  }

  /// Returns a generation that changes exactly when `value` differs from the
  /// value remembered for `key`.
  mutating func generation<Value: Equatable>(_ key: Key, value: Value) -> UInt64 {
    guard let record: _IdentityGeneration<Value> = values.value(for: key) else {
      values.set(_IdentityGeneration(value: value, generation: 0), for: key)
      return 0
    }
    if record.value == value { return record.generation }
    let next = _IdentityGeneration(value: value, generation: record.generation &+ 1)
    values.set(next, for: key)
    return next.generation
  }

  mutating func removeValue(for key: Key) { values.removeValue(for: key) }
  mutating func removeAll(keepingCapacity: Bool = false) {
    values.removeAll(keepingCapacity: keepingCapacity)
  }
}

private struct _IdentityGeneration<Value> {
  let value: Value
  let generation: UInt64
}

/// Private cross-module renderer payload. Reading requires the exact static type.
/// This replaces `Any` in navigation and sampled animation timelines.
@_spi(Renderer) public struct _RuntimeValue {
  let typeID: ObjectIdentifier
  private var storage = _TypedValueStorage<Int>()

  public init<Value>(_ value: Value) {
    typeID = _storedTypeID(Value.self)
    storage.set(value, for: 0)
  }

  public func read<Value>(_ type: Value.Type = Value.self) -> Value? {
    storage.value(for: 0, as: type)
  }
}
