/// A lightweight preference accumulator used by SwiftUI's
/// `preference(key:value:)` and `onPreferenceChange` APIs.  Preferences flow
/// upward during a render pass; the storage object is shared by child
/// `_RenderContext` values and retains the previous pass for change detection.
public final class _PreferenceStore: @unchecked Sendable {
  private var values = _TypedValueStorage<ObjectIdentifier>()
  private var previousValues = _TypedValueStorage<ObjectIdentifier>()
  /// Where each written value belongs in the reduction, per key and parallel to its sequence. Empty unless the
  /// render was staged (see `_RenderStaging`): a deferred subtree writes later than plain recursion would have,
  /// and its writes are placed by tag where its container stood. An untagged value was written before the first
  /// deferral, so it sorts first.
  private var tags: [ObjectIdentifier: [_OrderTag]] = [:]
  private var previousTags: [ObjectIdentifier: [_OrderTag]] = [:]

  public init() {}

  /// The order the writes of a key reduce in (indices into its sequence, by tag), computed once per pass and key: a
  /// reader at every level of a deep tree would otherwise sort the whole sequence again each time it reads.
  private var orders: [ObjectIdentifier: [Int]] = [:]
  private var previousOrders: [ObjectIdentifier: [Int]] = [:]

  public func beginPass() {
    previousValues = values
    previousTags = tags
    previousOrders = orders
    values.removeAll(keepingCapacity: true)
    tags.removeAll(keepingCapacity: true)
    orders.removeAll(keepingCapacity: true)
  }

  public func write<Key: PreferenceKey>(_ value: Key.Value, for key: Key.Type = Key.self) {
    let identifier = _storedTypeID(key)
    var sequence: [Key.Value] = values.takeValue(for: identifier) ?? []
    sequence.append(value)
    values.set(sequence, for: identifier)
    if _RenderStaging.tagging {
      var keyTags = tags.removeValue(forKey: identifier) ?? []
      while keyTags.count < sequence.count - 1 { keyTags.append(_OrderTag()) }
      keyTags.append(_RenderStaging.nextWriteTag())
      tags[identifier] = keyTags
      orders.removeValue(forKey: identifier)
    }
  }

  public func value<Key: PreferenceKey>(for key: Key.Type = Key.self) -> Key.Value {
    // Plain recursion has rendered everything before a reader by the time it reads.
    _RenderStaging.flushFromAnywhere()
    return reduce(values, tags, &orders, for: key)
  }

  public func previousValue<Key: PreferenceKey>(for key: Key.Type = Key.self) -> Key.Value {
    reduce(previousValues, previousTags, &previousOrders, for: key)
  }

  /// The value a reader at position `limit` reads: what was written before that position. For a reader that waited
  /// for the end of the pass (`_RenderStaging.ordered`), where plain recursion would have read as it went and seen
  /// only the writes before it; the writes of the rest of the pass are there already and are left out by their tags.
  func value<Key: PreferenceKey>(for key: Key.Type = Key.self, before limit: _OrderTag) -> Key.Value {
    reduce(values, tags, &orders, for: key, before: limit)
  }

  func changed<Key: PreferenceKey>(for key: Key.Type = Key.self, before limit: _OrderTag) -> Bool where Key.Value: Equatable {
    value(for: key, before: limit) != previousValue(for: key)
  }

  private func reduce<Key: PreferenceKey>(
    _ storage: _TypedValueStorage<ObjectIdentifier>, _ storageTags: [ObjectIdentifier: [_OrderTag]],
    _ cache: inout [ObjectIdentifier: [Int]], for key: Key.Type, before limit: _OrderTag? = nil
  ) -> Key.Value {
    let identifier = _storedTypeID(key)
    let sequence: [Key.Value] = storage.value(for: identifier) ?? []
    var result = Key.defaultValue
    if let keyTags = storageTags[identifier], sequence.count > 1 || limit != nil {
      let order = Self.order(of: sequence.count, by: keyTags, cache: &cache, for: identifier)
      // The order is sorted by tag, so what comes before `limit` is a prefix of it.
      let end = limit.map { Self.countBefore($0, in: order, tags: keyTags) } ?? order.count
      var position = 0
      while position < end {
        let next = sequence[order[position]]
        Key.reduce(value: &result) { next }
        position += 1
      }
      return result
    }
    for next in sequence { Key.reduce(value: &result) { next } }
    return result
  }

  /// The indices of a sequence of `count` values in tag order; equal tags keep the order they were written in.
  private static func order(
    of count: Int, by keyTags: [_OrderTag], cache: inout [ObjectIdentifier: [Int]], for identifier: ObjectIdentifier
  ) -> [Int] {
    if let cached = cache[identifier], cached.count == count { return cached }
    var order = Array(0..<count)
    // Stable, and linear when the sequence is already in order.
    _stableSort(&order) { lhs, rhs in
      let left = lhs < keyTags.count ? keyTags[lhs] : _OrderTag()
      let right = rhs < keyTags.count ? keyTags[rhs] : _OrderTag()
      return left.compare(to: right) < 0
    }
    cache[identifier] = order
    return order
  }

  /// How many of the sorted `order` have a tag before `limit`.
  private static func countBefore(_ limit: _OrderTag, in order: [Int], tags: [_OrderTag]) -> Int {
    var low = 0, high = order.count
    while low < high {
      let middle = (low + high) / 2
      let index = order[middle]
      let tag = index < tags.count ? tags[index] : _OrderTag()
      if _orderTagLess(tag, limit) { low = middle + 1 } else { high = middle }
    }
    return low
  }

  public func changed<Key: PreferenceKey>(for key: Key.Type = Key.self) -> Bool where Key.Value: Equatable {
    value(for: key) != previousValue(for: key)
  }

  // MARK: Subtrees

  /// How many values of `key` were written so far: where the writes of a subtree about to render start.
  func _writeCount<Key: PreferenceKey>(for key: Key.Type) -> Int {
    // The writes an earlier sibling's staged job has still to make land first: a count taken without them would take them
    // for the subtree's (`value(for:since:)` runs the pending jobs too).
    _RenderStaging.flushFromAnywhere()
    let sequence: [Key.Value]? = values.value(for: _storedTypeID(key))
    return sequence?.count ?? 0
  }

  /// The values of `key` written since `start` (a `_writeCount`), reduced in the order they belong in: what the
  /// subtree that rendered since then gives the views above it.
  func value<Key: PreferenceKey>(for key: Key.Type, since start: Int) -> Key.Value {
    _RenderStaging.flushFromAnywhere()
    let identifier = _storedTypeID(key)
    let sequence: [Key.Value] = values.value(for: identifier) ?? []
    var result = Key.defaultValue
    guard start < sequence.count else { return result }
    if let keyTags = tags[identifier], sequence.count > 1 {
      for index in Self.order(of: sequence.count, by: keyTags, cache: &orders, for: identifier) where index >= start {
        let next = sequence[index]
        Key.reduce(value: &result) { next }
      }
      return result
    }
    for index in start..<sequence.count {
      let next = sequence[index]
      Key.reduce(value: &result) { next }
    }
    return result
  }

  /// Replaces the values of `key` written since `start` by `value`: `transformPreference` and
  /// `transformAnchorPreference` hand the views above one value for the whole subtree.
  func replace<Key: PreferenceKey>(_ value: Key.Value, for key: Key.Type, since start: Int) {
    let identifier = _storedTypeID(key)
    var sequence: [Key.Value] = values.takeValue(for: identifier) ?? []
    if start < sequence.count { sequence.removeSubrange(start...) }
    values.set(sequence, for: identifier)
    if var keyTags = tags.removeValue(forKey: identifier) {
      if start < keyTags.count { keyTags.removeSubrange(start...) }
      tags[identifier] = keyTags
    }
    orders.removeValue(forKey: identifier)
    write(value, for: key)
  }
}

/// A preference key combines values emitted by descendants while rendering.
/// This is intentionally the same source shape as SwiftUI/Tokamak.
public protocol PreferenceKey {
  associatedtype Value
  static var defaultValue: Value { get }
  static func reduce(value: inout Self.Value, nextValue: () -> Self.Value)
}

public extension PreferenceKey where Value: ExpressibleByNilLiteral {
  static var defaultValue: Value { nil }
}
