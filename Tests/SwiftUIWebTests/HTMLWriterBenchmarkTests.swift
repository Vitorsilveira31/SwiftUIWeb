import Foundation
import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebHTML

/// Times the serializer against the reference one (`LegacyHTMLSerializer`) on a small, a large and a text-heavy tree.
/// Nothing is asserted. Run in release, which is the only build whose numbers mean anything:
///
///     SWIFTUIWEB_HTML_BENCH=1 swift test -c release --enable-swift-testing --disable-xctest --no-parallel \
///       --disable-sandbox --filter HTMLWriterBenchmarkTests
@Suite(.serialized)
@MainActor
struct HTMLWriterBenchmarkTests {
  private struct Case {
    let name: String
    let root: _RenderNode
    var elements = 0
    var nodes = 0
  }

  private static func census(_ root: _RenderNode) -> (elements: Int, nodes: Int) {
    var elements = 0, nodes = 0
    var stack = [root]
    while let node = stack.popLast() {
      nodes += 1
      if case .element = node.kind { elements += 1 }
      stack.append(contentsOf: node.children)
    }
    return (elements, nodes)
  }

  /// Nanoseconds per call: the best of several batches, each as long as `batch` calls.
  private static func time(batches: Int = 9, batch: Int, _ body: () -> Int) -> (nanoseconds: Double, bytes: Int) {
    var best = Double.infinity
    var bytes = 0
    for _ in 0..<batches {
      let start = DispatchTime.now().uptimeNanoseconds
      for _ in 0..<batch { bytes = body() }
      let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / Double(batch)
      best = min(best, elapsed)
    }
    return (best, bytes)
  }

  @Test
  func serializationSpeed() {
    guard HostFiles.environment("SWIFTUIWEB_HTML_BENCH") == "1" else { return }
    var cases: [Case] = [
      Case(name: "small (12 rows)", root: HTMLWriterCorpus.worksList(rows: 12)),
      Case(name: "large (200 rows, the works list)", root: HTMLWriterCorpus.worksList(rows: 200)),
      Case(name: "text-heavy (escaping)", root: HTMLWriterCorpus.element("div", [:], (0..<200).map {
        HTMLWriterCorpus.element("p", ["data-embedded-node-id": "p:\($0)"], [.text(String(repeating: "Fish & chips <b>\"quoted\"</b> and plain text. ", count: 6))])
      })),
    ]
    for index in cases.indices { (cases[index].elements, cases[index].nodes) = Self.census(cases[index].root) }

    for benchCase in cases {
      let batch = max(5, 200_000 / max(benchCase.nodes, 1))
      let reference = Self.time(batch: batch) { LegacyHTMLSerializer().renderNodeUTF8(benchCase.root).count }
      let writer = Self.time(batch: batch) { StaticHTMLFiberRenderer().renderNodeUTF8(benchCase.root).count }
      func line(_ label: String, _ result: (nanoseconds: Double, bytes: Int)) -> String {
        let perElement = result.nanoseconds / Double(benchCase.elements)
        let megabytesPerSecond = Double(result.bytes) / result.nanoseconds * 1000
        return "\(label): \(String(format: "%9.0f", result.nanoseconds / 1000)) us per tree, \(String(format: "%7.1f", perElement)) ns per element, \(String(format: "%7.1f", megabytesPerSecond)) bytes/us (\(result.bytes) bytes)"
      }
      print("html-writer-bench [\(benchCase.name), \(benchCase.elements) elements, \(benchCase.nodes) nodes]")
      print("  reference \(line("", reference))")
      print("  writer    \(line("", writer))   speedup \(String(format: "%.2f", reference.nanoseconds / writer.nanoseconds))x")
    }
  }

  /// The binary encoder against the HTML serializer on the same tree, for a host that holds nothing: the time of each and
  /// the bytes of each. The serializer is the one the binary publications use for a fallback.
  @Test
  func binaryEncodingSpeed() {
    guard HostFiles.environment("SWIFTUIWEB_HTML_BENCH") == "1" else { return }
    var cases: [Case] = [
      Case(name: "small (12 rows)", root: HTMLWriterCorpus.worksList(rows: 12)),
      Case(name: "large (200 rows, the works list)", root: HTMLWriterCorpus.worksList(rows: 200)),
      Case(name: "a rendered list screen", root: HTMLWriterCorpus.views[3].make()),
    ]
    for index in cases.indices { (cases[index].elements, cases[index].nodes) = Self.census(cases[index].root) }
    for benchCase in cases {
      let batch = max(5, 100_000 / max(benchCase.nodes, 1))
      func publish(encode: Bool) -> (nanoseconds: Double, bytes: Int) {
        Self.time(batch: batch) {
          if encode {
            let encoder = BinaryFiberEncoder(maxElementDepth: 510, acked: 0, covered: 1, rootRecord: BinaryNodeRecord(), lookup: { _ in nil })
            return encoder.encode(benchCase.root)?.bytes.count ?? -1
          }
          return StaticHTMLFiberRenderer(maxElementDepth: 510).withRenderedUTF8(benchCase.root) { $0.count }
        }
      }
      let html = publish(encode: false)
      let binary = publish(encode: true)
      print("binary-bench [\(benchCase.name), \(benchCase.elements) elements]")
      print("  html     \(String(format: "%9.0f", html.nanoseconds / 1000)) us, \(html.bytes) bytes")
      print("  binary   \(String(format: "%9.0f", binary.nanoseconds / 1000)) us, \(binary.bytes) bytes   \(String(format: "%.2f", binary.nanoseconds / html.nanoseconds))x the time of the markup")
      #expect(binary.bytes > 0)
    }
  }
}
