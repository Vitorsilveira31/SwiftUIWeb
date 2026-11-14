// Foundation's sorting vocabulary, on every host.
//
// Native builds compare through the key path, as Foundation does. Embedded Swift has no key paths, so a
// `KeyPathComparator` there wraps a getter closure plus the member's name. Application sources reach that initializer
// through the lowering tool: `KeyPathComparator(\Order.status, order: .reverse)` becomes
// `KeyPathComparator(_embeddedMember: "status", { (row: Order) in row.status }, order: .reverse)`.

public enum ComparisonResult: Int, Sendable {
  case orderedAscending = -1
  case orderedSame = 0
  case orderedDescending = 1
}

public enum SortOrder: Hashable, Sendable {
  case forward
  case reverse
}

/// Foundation's `SortComparator`.
@preconcurrency public protocol SortComparator<Compared>: Hashable, Sendable {
  associatedtype Compared
  func compare(_ lhs: Self.Compared, _ rhs: Self.Compared) -> ComparisonResult
  var order: SortOrder { get set }
}

/// Foundation's `KeyPathComparator`. Natively it keeps the key path, as Foundation's does; in an Embedded build, which
/// has no key paths, it keeps a getter and the member's name (see the file comment).
public struct KeyPathComparator<Compared>: SortComparator {
  #if !hasFeature(Embedded)
  @preconcurrency public let keyPath: any PartialKeyPath<Compared> & Sendable
  #else
  /// The compared member's name, written by the lowering tool; two comparators of one member are equal.
  public let _identity: String
  #endif
  public var order: SortOrder
  private let forwardCompare: @Sendable (Compared, Compared) -> ComparisonResult

  #if !hasFeature(Embedded)
  public init<Value: Comparable>(_ keyPath: any KeyPath<Compared, Value> & Sendable, order: SortOrder = .forward) {
    self.keyPath = keyPath
    self.order = order
    forwardCompare = { lhs, rhs in _compareComparable(lhs[keyPath: keyPath], rhs[keyPath: keyPath]) }
  }

  public init<Value: Comparable>(_ keyPath: any KeyPath<Compared, Value?> & Sendable, order: SortOrder = .forward) {
    self.keyPath = keyPath
    self.order = order
    forwardCompare = { lhs, rhs in _compareOptional(lhs[keyPath: keyPath], rhs[keyPath: keyPath], _compareComparable) }
  }

  public init<Value, Comparator: SortComparator>(
    _ keyPath: any KeyPath<Compared, Value> & Sendable, comparator: Comparator
  ) where Value == Comparator.Compared {
    self.init(keyPath, comparator: comparator, order: comparator.order)
  }

  public init<Value, Comparator: SortComparator>(
    _ keyPath: any KeyPath<Compared, Value?> & Sendable, comparator: Comparator
  ) where Value == Comparator.Compared {
    self.init(keyPath, comparator: comparator, order: comparator.order)
  }

  public init<Value, Comparator: SortComparator>(
    _ keyPath: any KeyPath<Compared, Value> & Sendable, comparator: Comparator, order: SortOrder
  ) where Value == Comparator.Compared {
    self.keyPath = keyPath
    self.order = order
    let forward = _forwardComparator(comparator)
    forwardCompare = { lhs, rhs in forward.compare(lhs[keyPath: keyPath], rhs[keyPath: keyPath]) }
  }

  public init<Value, Comparator: SortComparator>(
    _ keyPath: any KeyPath<Compared, Value?> & Sendable, comparator: Comparator, order: SortOrder
  ) where Value == Comparator.Compared {
    self.keyPath = keyPath
    self.order = order
    let forward = _forwardComparator(comparator)
    forwardCompare = { lhs, rhs in _compareOptional(lhs[keyPath: keyPath], rhs[keyPath: keyPath], forward.compare) }
  }
  #else
  public init<Value: Comparable>(
    _embeddedMember member: String,
    _ value: @escaping @Sendable (Compared) -> Value,
    order: SortOrder = .forward
  ) where Value: SendableMetatype {
    self.order = order
    _identity = member
    forwardCompare = { lhs, rhs in _compareComparable(value(lhs), value(rhs)) }
  }

  public init<Value, Comparator: SortComparator>(
    _embeddedMember member: String,
    _ value: @escaping @Sendable (Compared) -> Value,
    comparator: Comparator,
    order: SortOrder = .forward
  ) where Comparator.Compared == Value, Value: SendableMetatype {
    self.order = order
    _identity = member
    let forward = _forwardComparator(comparator)
    forwardCompare = { lhs, rhs in forward.compare(value(lhs), value(rhs)) }
  }
  #endif

  public func compare(_ lhs: Compared, _ rhs: Compared) -> ComparisonResult {
    let result = forwardCompare(lhs, rhs)
    guard order == .reverse else { return result }
    switch result {
    case .orderedAscending: return .orderedDescending
    case .orderedDescending: return .orderedAscending
    case .orderedSame: return .orderedSame
    }
  }

  public static func == (lhs: KeyPathComparator<Compared>, rhs: KeyPathComparator<Compared>) -> Bool {
    lhs.order == rhs.order && lhs._member == rhs._member
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(_member)
    hasher.combine(order)
  }

  #if !hasFeature(Embedded)
  private var _member: AnyHashable { AnyHashable(keyPath as PartialKeyPath<Compared>) }
  #else
  private var _member: String { _identity }
  #endif
}

private func _compareComparable<Value: Comparable>(_ left: Value, _ right: Value) -> ComparisonResult {
  if left < right { return .orderedAscending }
  if right < left { return .orderedDescending }
  return .orderedSame
}

/// Foundation orders `nil` before every value.
private func _compareOptional<Value>(
  _ left: Value?, _ right: Value?, _ compare: (Value, Value) -> ComparisonResult
) -> ComparisonResult {
  switch (left, right) {
  case (nil, nil): return .orderedSame
  case (nil, _): return .orderedAscending
  case (_, nil): return .orderedDescending
  case let (left?, right?): return compare(left, right)
  }
}

/// The comparator in forward order: the key-path comparator applies its own order.
private func _forwardComparator<Comparator: SortComparator>(_ comparator: Comparator) -> Comparator {
  var forward = comparator
  forward.order = .forward
  return forward
}

extension Sequence {
  public func sorted<Comparator: SortComparator>(using comparator: Comparator) -> [Element]
  where Comparator.Compared == Element {
    sorted { comparator.compare($0, $1) == .orderedAscending }
  }

  public func sorted<Comparators: Sequence, Comparator: SortComparator>(using comparators: Comparators) -> [Element]
  where Comparators.Element == Comparator, Comparator.Compared == Element {
    let ordered = Array(comparators)
    return sorted { lhs, rhs in
      for comparator in ordered {
        let result = comparator.compare(lhs, rhs)
        if result != .orderedSame { return result == .orderedAscending }
      }
      return false
    }
  }
}

extension MutableCollection where Self: RandomAccessCollection {
  public mutating func sort<Comparator: SortComparator>(using comparator: Comparator)
  where Comparator.Compared == Element {
    sort { comparator.compare($0, $1) == .orderedAscending }
  }

  public mutating func sort<Comparators: Sequence, Comparator: SortComparator>(using comparators: Comparators)
  where Comparators.Element == Comparator, Comparator.Compared == Element {
    let ordered = Array(comparators)
    sort { lhs, rhs in
      for comparator in ordered {
        let result = comparator.compare(lhs, rhs)
        if result != .orderedSame { return result == .orderedAscending }
      }
      return false
    }
  }
}

