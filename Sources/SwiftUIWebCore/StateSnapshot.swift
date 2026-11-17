// State kept across a reload in the development loop. A rebuild makes a new WebAssembly module, so the page reloads and
// every `@State` starts over. In a debug build the page hands the values of its states to the next one: before the
// reload they are written as text (`_StateSnapshots.text(of:)`), and the new module gives each state that enters the
// store the value saved under its key (`StateStore.register`).
//
// Only a state of a plain value type has a text form (`_WriteEquatable._stateSnapshotTag`): booleans, integers, floating
// point numbers, strings, and optionals and arrays of them. A state whose key is not there any more (the view moved) or
// whose type changed starts from its initial value, as does every state of another type. None of this is in a release
// build.

#if DEBUG
package enum _StateSnapshots {
  /// Set by the browser launcher of a debug build before the first render; a `State` made while it is off keeps nothing.
  nonisolated(unsafe) package static var enabled = false
  /// The values an earlier page saved, by state key, until a state takes each one.
  nonisolated(unsafe) static var pending: [String: (tag: String, text: String)] = .init()

  /// The states of `store` that have a text form: one line each, `key<TAB>tag<TAB>text`, with line breaks, tabs and
  /// backslashes of the key and the text written `\n`, `\t` and `\\`. Sorted by key, so the text does not depend on the
  /// order of a dictionary.
  @MainActor package static func text(of store: StateStore) -> String {
    var byKey: [String: (tag: String, text: String)?] = .init()
    for entry in store._snapshotEntries() {
      let key = stableKey(entry.key)
      // Two states that only the type's address told apart cannot be told apart by the next page: neither is kept.
      byKey[key] = byKey[key] == nil ? .some((entry.tag, entry.text)) : .some(nil)
    }
    return byKey.keys.sorted().compactMap { key -> String? in
      guard let saved = byKey[key] ?? nil else { return nil }
      return escaped(key) + "\t" + saved.tag + "\t" + escaped(saved.text)
    }.joined(separator: "\n")
  }

  /// A state's key names the types around it by the address of their metadata (`type-2063624`), which is another number
  /// in every page. The key the pages share has those numbers left out.
  static func stableKey(_ key: String) -> String {
    var result = ""
    var afterType = false
    for character in key {
      if afterType, character.isNumber { continue }
      afterType = false
      result.append(character)
      if result.hasSuffix("type-") { afterType = true }
    }
    return result
  }

  /// Takes the text an earlier page wrote: the states made from now on start from it.
  package static func load(_ text: String) {
    pending.removeAll()
    for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
      let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
      guard fields.count == 3, !fields[1].isEmpty else { continue }
      pending[unescaped(fields[0])] = (String(fields[1]), unescaped(fields[2]))
    }
  }

  static func escaped(_ text: String) -> String {
    var result = ""
    for character in text {
      switch character {
      case "\\": result += "\\\\"
      case "\n": result += "\\n"
      case "\t": result += "\\t"
      default: result.append(character)
      }
    }
    return result
  }

  static func unescaped(_ text: Substring) -> String {
    var result = ""
    var escaping = false
    for character in text {
      if escaping {
        switch character {
        case "n": result.append("\n")
        case "t": result.append("\t")
        default: result.append(character)
        }
        escaping = false
      } else if character == "\\" {
        escaping = true
      } else {
        result.append(character)
      }
    }
    return result
  }
}

extension Bool {
  public static var _stateSnapshotTag: String { "b" }
  public static func _stateSnapshotText(_ value: Bool) -> String { value ? "1" : "0" }
  public static func _stateSnapshotValue(_ text: Substring) -> Bool? { text == "1" ? true : text == "0" ? false : nil }
}

extension Int {
  public static var _stateSnapshotTag: String { "i" }
  public static func _stateSnapshotText(_ value: Int) -> String { String(value) }
  public static func _stateSnapshotValue(_ text: Substring) -> Int? { Int(text) }
}

extension Double {
  public static var _stateSnapshotTag: String { "d" }
  public static func _stateSnapshotText(_ value: Double) -> String { String(value) }
  public static func _stateSnapshotValue(_ text: Substring) -> Double? { Double(String(text)) }
}

extension String {
  public static var _stateSnapshotTag: String { "s" }
  public static func _stateSnapshotText(_ value: String) -> String { value }
  public static func _stateSnapshotValue(_ text: Substring) -> String? { String(text) }
}

extension Optional where Wrapped: _WriteEquatable {
  public static var _stateSnapshotTag: String { Wrapped._stateSnapshotTag.isEmpty ? "" : "?" + Wrapped._stateSnapshotTag }
  /// `n` for nil, `s` and the wrapped value's text otherwise.
  public static func _stateSnapshotText(_ value: Wrapped?) -> String { value.map { "s" + Wrapped._stateSnapshotText($0) } ?? "n" }
  public static func _stateSnapshotValue(_ text: Substring) -> Wrapped?? {
    if text == "n" { return .some(nil) }
    guard text.first == "s", let wrapped = Wrapped._stateSnapshotValue(text.dropFirst()) else { return nil }
    return .some(wrapped)
  }
}

extension Array where Element: _WriteEquatable {
  public static var _stateSnapshotTag: String { Element._stateSnapshotTag.isEmpty ? "" : "[" + Element._stateSnapshotTag }
  /// Each element as `<number of characters>:<text>`, one after the other.
  public static func _stateSnapshotText(_ value: [Element]) -> String {
    var result = ""
    for element in value {
      let text = Element._stateSnapshotText(element)
      result += String(text.count) + ":" + text
    }
    return result
  }
  public static func _stateSnapshotValue(_ text: Substring) -> [Element]? {
    var rest = text
    var result: [Element] = []
    while !rest.isEmpty {
      guard let colon = rest.firstIndex(of: ":"), let count = Int(rest[..<colon]), count >= 0 else { return nil }
      let body = rest[rest.index(after: colon)...]
      guard body.count >= count else { return nil }
      let end = body.index(body.startIndex, offsetBy: count)
      guard let element = Element._stateSnapshotValue(body[..<end]) else { return nil }
      result.append(element)
      rest = body[end...]
    }
    return result
  }
}
#endif
