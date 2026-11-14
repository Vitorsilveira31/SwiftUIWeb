import SwiftUIWeb


// Foundation's stream-based JSONSerialization as an app writes it: serialize into an OutputStream, parse from an
// InputStream, over memory, a fixed buffer and a file. The expected lines were produced by Apple's Foundation, so the
// browser build has to print exactly what the native build prints.
struct EmbeddedJSONStreamFixtureView: View {
  var body: some View {
    VStack {
      ForEach(EmbeddedJSONStreamFixtureView.lines, id: \.self) { line in
        Text(line)
      }
    }
  }

  static var lines: [String] {
    var result: [String] = []
    let object: [String: Any] = ["name": "stream", "values": [1, 2, 3], "nested": ["ok": true]]

    // Memory output: the bytes written, the return value and the stream states.
    let memory = OutputStream(toMemory: ())
    var status = "\(memory.streamStatus.rawValue)"
    memory.open()
    status += " \(memory.streamStatus.rawValue) \(memory.hasSpaceAvailable)"
    var failure: NSError?
    let count = JSONSerialization.writeJSONObject(object, to: memory, options: [.sortedKeys], error: &failure)
    let written = (memory.property(forKey: .dataWrittenToMemoryStreamKey) as? Data).map { String(decoding: $0, as: UTF8.self) } ?? "none"
    memory.close()
    status += " \(memory.streamStatus.rawValue) \(memory.hasSpaceAvailable)"
    result.append("json stream write: \(count) \(failure == nil ? "no error" : "error") \(status)")
    result.append("json stream bytes: \(written)")

    // Pretty printing goes through the same stream path.
    let pretty = OutputStream(toMemory: ())
    pretty.open()
    let prettyCount = JSONSerialization.writeJSONObject(["a": [1, 2]], to: pretty, options: [.prettyPrinted, .sortedKeys], error: nil)
    let prettyText = (pretty.property(forKey: .dataWrittenToMemoryStreamKey) as? Data).map { String(decoding: $0, as: UTF8.self) } ?? "none"
    result.append("json stream pretty: \(prettyCount) \(prettyText.replacingOccurrences(of: "\n", with: "|"))")

    // Input: read until the end, then the stream reports it.
    let input = InputStream(data: Data(written.utf8))
    input.open()
    let parsed = try? JSONSerialization.jsonObject(with: input) as? [String: Any]
    result.append("json stream read: \(parsed?["name"] as? String ?? "nil") \((parsed?["values"] as? [Any])?.count ?? -1) \(input.streamStatus.rawValue) \(input.hasBytesAvailable)")

    // Parse errors match the Data variant: a truncated document fails, a fragment needs the option.
    let truncated = InputStream(data: Data("[1,".utf8))
    truncated.open()
    result.append("json stream truncated: \((try? JSONSerialization.jsonObject(with: truncated)) == nil ? "throws" : "parsed")")
    let fragment = InputStream(data: Data("5".utf8))
    fragment.open()
    result.append("json stream fragment: \((try? JSONSerialization.jsonObject(with: fragment)) == nil ? "throws" : "parsed")")
    let allowed = InputStream(data: Data("5".utf8))
    allowed.open()
    result.append("json stream fragment allowed: \((try? JSONSerialization.jsonObject(with: allowed, options: [.fragmentsAllowed])) as? Int ?? -1)")

    // A fixed buffer takes whole writes only: "{" fits, the 5-byte string does not.
    let storage = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
    defer { storage.deallocate() }
    let bounded = OutputStream(toBuffer: storage, capacity: 4)
    bounded.open()
    var overflow: NSError?
    let overflowCount = JSONSerialization.writeJSONObject(["abc": 1], to: bounded, options: [], error: &overflow)
    result.append("json stream overflow: \(overflowCount) \(overflow?.domain ?? "nil") \(overflow?.code ?? 0) \(bounded.streamStatus.rawValue) \(bounded.hasSpaceAvailable)")

    // Direct reads: statuses around the end of a memory stream.
    let direct = InputStream(data: Data("abcde".utf8))
    var chunk = [UInt8](repeating: 0, count: 3)
    var reads = "\(direct.streamStatus.rawValue) \(direct.read(&chunk, maxLength: 3))"
    direct.open()
    reads += " \(direct.hasBytesAvailable)"
    reads += " \(direct.read(&chunk, maxLength: 3)) \(direct.streamStatus.rawValue)"
    reads += " \(direct.read(&chunk, maxLength: 3)) \(direct.streamStatus.rawValue) \(direct.hasBytesAvailable)"
    reads += " \(direct.read(&chunk, maxLength: 3)) \(direct.streamStatus.rawValue)"
    result.append("stream reads: \(reads)")

    // Literals infer typed containers (`[String: Int]`, `[Int]`, ...): every shape serializes like Foundation.
    let optionalFields: [String: Any?] = ["a": 1, "b": nil]
    let optionalItems: [Any?] = [1, nil]
    let optionalInts: [String: Int?] = ["a": 1, "b": nil]
    let typed: [(String, Any)] = [
      ("int", ["a": 1]), ("string", ["a": "x"]), ("bool", ["a": true]), ("double", ["a": 1.5, "b": 2.0]),
      ("null", ["a": NSNull()]), ("array", ["a": [1, 2]]), ("object", ["a": ["b": 1]]), ("ints", [1, 2]),
      ("strings", ["a", "b"]), ("doubles", [1.5, 2]), ("bools", [true, false]), ("objects", [["a": 1]]),
      ("string objects", [["a": "x"]]), ("optional fields", optionalFields), ("optional items", optionalItems),
      ("optional ints", optionalInts), ("nan", ["a": Double.nan]), ("int keys", [1: 2]), ("date", ["a": Date(timeIntervalSince1970: 0)]),
    ]
    for (name, value) in typed {
      let valid = JSONSerialization.isValidJSONObject(value)
      let text = valid ? ((try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "throws") : "-"
      result.append("json typed \(name): \(valid) \(text)")
    }

    // A file round trip through URL streams; a URL with another scheme is not a file.
    let url = URL(fileURLWithPath: "/tmp/json-stream-fixture.json")
    let file = OutputStream(url: url, append: false)
    file?.open()
    let fileCount = file.map { JSONSerialization.writeJSONObject(["file": true], to: $0, options: [], error: nil) } ?? -2
    file?.close()
    let reader = InputStream(url: url)
    reader?.open()
    let fileObject = reader.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    let remote = InputStream(url: URL(string: "https://example.com/data.json")!) == nil
    result.append("json stream file: \(fileCount) \(fileObject?["file"] as? Bool ?? false) \(reader?.streamStatus.rawValue ?? 99) remote nil: \(remote)")
    let missing = InputStream(url: URL(fileURLWithPath: "/tmp/json-stream-missing.json"))
    missing?.open()
    result.append("stream missing file: \(missing?.streamStatus.rawValue ?? 99) \((missing?.streamError as? NSError)?.domain ?? "nil") \((missing?.streamError as? NSError)?.code ?? 0)")
    return result
  }
}
