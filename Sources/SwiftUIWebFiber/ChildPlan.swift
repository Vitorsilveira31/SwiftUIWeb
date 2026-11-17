/// How a parent's previous children map onto its new ones, matched by key. A key listed twice matches its first
/// occurrence once; the other records are removed rather than leaked.
struct ChildPlan: Equatable {
  /// Marks a new child with no previous record.
  static let insert = UInt32.max
  /// For each new child, the index of the previous child it keeps, or `insert`.
  var oldIndices: [UInt32]
  /// The previous children no new child keeps, in order. They are retired before any insertion is allocated.
  var removals: [UInt32]

  init<Key: Hashable>(old: [Key], new: [Key]) {
    var firstByKey: [Key: UInt32] = .init()
    firstByKey.reserveCapacity(old.count)
    // Walking backwards leaves the first occurrence of a duplicate in the table.
    for index in old.indices.reversed() { firstByKey[old[index]] = UInt32(index) }
    var used = [Bool](repeating: false, count: old.count)
    oldIndices = []
    oldIndices.reserveCapacity(new.count)
    for key in new {
      if let index = firstByKey.removeValue(forKey: key) {
        used[Int(index)] = true
        oldIndices.append(index)
      } else {
        oldIndices.append(Self.insert)
      }
    }
    removals = []
    for index in used.indices where !used[index] { removals.append(UInt32(index)) }
  }
}
