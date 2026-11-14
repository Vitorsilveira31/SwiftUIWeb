import SwiftUIWeb


// The JSON codec running in the Embedded build: documents it must read (with the compact text with sorted keys it writes
// back) and documents it must refuse. Native coverage of the full corpus is in Tests/EmbeddedJSONTests.
enum JSONCorpusFixture {
  static let accepted: [(String, String)] = [
    (#" { "b" : [ 1 , 2.5 , -3e2 ] , "a" : "x" } "#, #"{"a":"x","b":[1,2.5,-300]}"#),
    (#"["\u00e9\ud83d\ude00\n\t\"\\", "é😀"]"#, "[\"é😀\\n\\t\\\"\\\\\",\"é😀\"]"),
    (#"[0, -0, 1E2, 1e-2, 0.5, 2147483647, 123456789012345678, 1e-6]"#, "[0,0,100,0.01,0.5,2147483647,123456789012345680,1e-6]"),
    (#"{"a":1,"a":2,"":[[],{}]}"#, #"{"":[[],{}],"a":2}"#),
  ]
  static let refused = [
    "[1,]", #"{"a":1,}"#, "[01]", "[1.]", "[.5]", "[+1]", "[1e]", "[tru]", "[1] x", "{'a':1}", #"["\ud800"]"#, #"["\udc00"]"#, #"["\x"]"#,
    "[1e999]", String(repeating: "[", count: 200) + String(repeating: "]", count: 200),
  ]

  static func run() -> String {
    for (input, expected) in accepted {
      guard let object = try? JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed]),
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]),
        String(decoding: data, as: UTF8.self) == expected
      else { return "FAIL accepted \(input)" }
    }
    for input in refused where (try? JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed])) != nil {
      return "FAIL refused \(input)"
    }
    return "PASS"
  }
}

struct EmbeddedJSONCorpusFixtureView: View {
  var body: some View { Text("json-corpus: \(JSONCorpusFixture.run())") }
}
