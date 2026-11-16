/// A render node's attributes or styles: a few named values, kept in the order they were first set.
///
/// A node carries a handful of them, read and written a few times each per render and compared by every reconcile. A
/// `[String: String]` paid for that with a hash table per node: hashing each key on every read and write, growing the
/// table as values were added, and hashing again to compare two nodes. Here a read is a scan of a few short keys
/// (most are small strings, compared without touching memory), a node's values are one array, and two nodes a render
/// built the same way compare in order. It reads like the dictionary it replaces: a subscript that returns nil for a
/// missing name and removes the value when set to nil, `removeValue(forKey:)`, `keys`, iteration as `(key:value:)`.
public struct _NodeValues: Hashable, Sendable, Sequence, ExpressibleByDictionaryLiteral {
  public typealias Element = (key: String, value: String)
  @usableFromInline var entries: [Element]

  @inlinable public init() { entries = [] }

  public init(dictionaryLiteral elements: (String, String)...) {
    entries = []
    entries.reserveCapacity(elements.count)
    for (key, value) in elements { self[key] = value }
  }

  public init(_ dictionary: [String: String]) {
    entries = []
    entries.reserveCapacity(dictionary.count)
    for (key, value) in dictionary { entries.append((key, value)) }
  }

  /// Most names that differ differ in length, and a string knows its length: comparing it first spares the full
  /// comparison a long name (`data-embedded-node-id`, past what a string holds inline) would cost.
  @inlinable func index(of key: String) -> Int? {
    let length = key.utf8.count
    for index in entries.indices where entries[index].key.utf8.count == length && entries[index].key == key { return index }
    return nil
  }

  @inlinable public subscript(key: String) -> String? {
    get { index(of: key).map { entries[$0].value } }
    set {
      if let index = index(of: key) {
        if let newValue { entries[index].value = newValue } else { entries.remove(at: index) }
      } else if let newValue {
        entries.append((key, newValue))
      }
    }
  }

  @inlinable @discardableResult public mutating func removeValue(forKey key: String) -> String? {
    guard let index = index(of: key) else { return nil }
    return entries.remove(at: index).value
  }

  /// The values in their order, for a serializer that reads them in place instead of copying each pair out.
  package var _entries: [Element] { entries }

  @inlinable public var isEmpty: Bool { entries.isEmpty }
  @inlinable public var count: Int { entries.count }
  public var keys: [String] { entries.map { $0.key } }
  public var values: [String] { entries.map { $0.value } }

  /// The values that pass `isIncluded`, in their order.
  public func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> _NodeValues {
    var result = _NodeValues()
    result.entries = try entries.filter(isIncluded)
    return result
  }

  public mutating func reserveCapacity(_ minimumCapacity: Int) { entries.reserveCapacity(minimumCapacity) }

  /// Adds `other`'s values; for a name both have, `combine` picks the value.
  public mutating func merge(_ other: _NodeValues, uniquingKeysWith combine: (String, String) throws -> String) rethrows {
    for entry in other.entries {
      if let index = index(of: entry.key) { entries[index].value = try combine(entries[index].value, entry.value) } else { entries.append(entry) }
    }
  }

  /// The same values as a dictionary, for an API that takes one.
  public var dictionary: [String: String] {
    var result: [String: String] = .init()
    result.reserveCapacity(entries.count)
    for entry in entries { result[entry.key] = entry.value }
    return result
  }

  @inlinable public func makeIterator() -> IndexingIterator<[Element]> { entries.makeIterator() }

  /// Whatever their order, as `==` compares them.
  public func hash(into hasher: inout Hasher) {
    var combined = 0
    for entry in entries {
      var pair = Hasher()
      pair.combine(entry.key)
      pair.combine(entry.value)
      combined ^= pair.finalize()
    }
    hasher.combine(entries.count)
    hasher.combine(combined)
  }

  /// Equal when they hold the same values, whatever their order. Two nodes rendered by the same code set them in the
  /// same order, which the first loop compares without searching.
  public static func == (lhs: _NodeValues, rhs: _NodeValues) -> Bool {
    guard lhs.entries.count == rhs.entries.count else { return false }
    var index = 0
    while index < lhs.entries.count, lhs.entries[index].key.utf8.count == rhs.entries[index].key.utf8.count,
          lhs.entries[index].key == rhs.entries[index].key {
      guard lhs.entries[index].value == rhs.entries[index].value else { return false }
      index += 1
    }
    while index < lhs.entries.count {
      guard rhs[lhs.entries[index].key] == lhs.entries[index].value else { return false }
      index += 1
    }
    return true
  }
}

package extension Dictionary where Key == String, Value == String {
  /// Adds a node's values (`_NodeValues`) to a dictionary.
  mutating func merge(_ other: _NodeValues, uniquingKeysWith combine: (String, String) throws -> String) rethrows {
    for entry in other {
      if let existing = self[entry.key] { self[entry.key] = try combine(existing, entry.value) } else { self[entry.key] = entry.value }
    }
  }
}

/// A render node's event handlers by name: a few at most, kept in the order they were first set.
///
/// The same trade as `_NodeValues`: a node carries a handful of handlers, so a scan of the names is quicker than a hash
/// table, and it spares the binary a `Dictionary<String, _EventHandler>` (Embedded Swift emits the hashed-collection
/// code for every key and value type it is used with). It reads like the dictionary it replaces: a subscript that
/// returns nil for a missing name and removes the handler when set to nil, `removeValue(forKey:)`, `keys`, iteration as
/// `(key:value:)`.
public struct _NodeEvents: Sequence, ExpressibleByDictionaryLiteral {
  public typealias Element = (key: String, value: _EventHandler)
  @usableFromInline var entries: [Element]

  @inlinable public init() { entries = [] }

  public init(dictionaryLiteral elements: (String, _EventHandler)...) {
    entries = []
    for (key, value) in elements { self[key] = value }
  }

  @usableFromInline func index(of key: String) -> Int? {
    let length = key.utf8.count
    for index in entries.indices where entries[index].key.utf8.count == length && entries[index].key == key { return index }
    return nil
  }

  public subscript(key: String) -> _EventHandler? {
    get { index(of: key).map { entries[$0].value } }
    set {
      if let index = index(of: key) {
        if let newValue { entries[index].value = newValue } else { entries.remove(at: index) }
      } else if let newValue {
        entries.append((key, newValue))
      }
    }
  }

  @discardableResult public mutating func removeValue(forKey key: String) -> _EventHandler? {
    guard let index = index(of: key) else { return nil }
    return entries.remove(at: index).value
  }

  @inlinable public var isEmpty: Bool { entries.isEmpty }
  @inlinable public var count: Int { entries.count }
  public var keys: [String] { entries.map { $0.key } }

  /// Whether both hold handlers for the same names, whatever their order.
  public func hasSameNames(as other: _NodeEvents) -> Bool {
    guard entries.count == other.entries.count else { return false }
    for entry in entries where other.index(of: entry.key) == nil { return false }
    return true
  }

  @inlinable public func makeIterator() -> IndexingIterator<[Element]> { entries.makeIterator() }
}
