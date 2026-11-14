@_spi(Renderer) import SwiftUIWebLocking

/// NSPredicate's format language (parsing, `predicateFormat`, substitution, evaluation) runs in the browser host,
/// `Tools/BrowserIO/predicate-engine.mjs`. Swift sends a predicate's format, its arguments, its variables and, to evaluate
/// it, the object under test as flat bytes (`_PredicateWire` in WebFoundation); the host keeps the parsed predicate under
/// the id Swift gives it and parses again from the bytes when it has lost it.
package enum BrowserPredicate {
  package struct Description {
    package let format: String
    package let keyNames: [String]
    package let keyDepth: Int
  }

  private static let lastIdentifier = _Locked(UInt32(0))

  /// An id no other predicate of this application has.
  package static func makeIdentifier() -> UInt32 {
    lastIdentifier.withLock { id -> UInt32 in
      id &+= 1
      return id
    }
  }

  private static func ask(_ id: UInt32, _ format: String, _ arguments: [UInt8], _ bindings: [UInt8], _ object: [UInt8]) -> IOReader? {
    var writer = IOWriter()
    writer.u32(id); writer.text(format); writer.data(arguments); writer.data(bindings); writer.data(object)
    return try? IORuntime.sync(_BrowserIOProtocol.predicate, writer)
  }

  /// The canonical `predicateFormat` and the keys the predicate reads. `bindings` is the variable dictionaries to apply, one
  /// after another. Nil when Foundation would raise for the format, or no host answers.
  package static func describe(id: UInt32, format: String, arguments: [UInt8], bindings: [UInt8]) -> Description? {
    guard var reader = ask(id, format, arguments, bindings, []), reader.u32() != 0 else { return nil }
    let canonical = reader.text()
    let depth = Int(reader.u32())
    let count = Int(reader.u32())
    guard count <= 1_000_000 else { return nil }
    var names: [String] = []
    for _ in 0..<count { names.append(reader.text()) }
    guard reader.finish() == nil else { return nil }
    return Description(format: canonical, keyNames: names, keyDepth: depth)
  }

  /// Whether `object` (one wire value) satisfies the predicate; nil when Foundation would raise, the format does not parse
  /// or no host answers.
  package static func evaluate(id: UInt32, format: String, arguments: [UInt8], bindings: [UInt8], object: [UInt8]) -> Bool? {
    guard var reader = ask(id, format, arguments, bindings, object) else { return nil }
    let verdict = reader.u32()
    return reader.finish() == nil && verdict < 2 ? verdict == 1 : nil
  }
}
