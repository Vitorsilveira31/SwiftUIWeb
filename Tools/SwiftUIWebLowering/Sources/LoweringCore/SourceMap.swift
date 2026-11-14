import Foundation

/// The provenance metadata the report carries for each rewritten file: a generated-line to source-line map, line and
/// column anchors, and stable content hashes. It is diagnostic metadata, never compiler input, and it is the previous
/// lowerer's algorithm over lines: most rules preserve line breaks, so unchanged lines are anchors and the runs between
/// anchors are interpolated. Lines are compared as bytes and columns count Unicode scalars.
///
/// Consumers: the failure message of `Tools/run-browser-embedded.sh` points a build error in a lowered file at the
/// `lineMap` of the report, and `Tools/test-lowering.mjs` reads `sourceMap` and `hashes`.
public enum SourceMap {
  private static func lines(of text: String) -> [[UInt8]] {
    text.utf8.split(separator: 0x0A, omittingEmptySubsequences: false).map { Array($0) }
  }

  /// For each generated line (index) the 1-based source line it comes from.
  public static func lineMap(original: String, generated: String) -> [Int] {
    lineMap(sourceLines: lines(of: original), generatedLines: lines(of: generated))
  }

  /// The first value of an ascending `values` that is at least `bound`, by binary search: a line that occurs many times
  /// would otherwise make the scan quadratic.
  private static func firstIndex(atLeast bound: Int, in values: [Int]) -> Int? {
    var low = 0, high = values.count
    while low < high {
      let middle = (low + high) / 2
      if values[middle] < bound { low = middle + 1 } else { high = middle }
    }
    return low < values.count ? values[low] : nil
  }

  private static func lineMap(sourceLines: [[UInt8]], generatedLines: [[UInt8]]) -> [Int] {
    var occurrences: [[UInt8]: [Int]] = [:]
    for (index, line) in sourceLines.enumerated() { occurrences[line, default: []].append(index) }

    var anchors: [(generated: Int, source: Int)] = []
    var nextSource = 0
    for (generatedIndex, line) in generatedLines.enumerated() {
      guard let indices = occurrences[line], let sourceIndex = firstIndex(atLeast: nextSource, in: indices) else { continue }
      anchors.append((generatedIndex, sourceIndex))
      nextSource = sourceIndex + 1
    }

    let lastGenerated = max(generatedLines.count - 1, 0)
    let lastSource = max(sourceLines.count - 1, 0)
    var result = [Int](repeating: 0, count: generatedLines.count)
    var previous = (generated: 0, source: 0)
    for next in anchors + [(generated: generatedLines.count, source: sourceLines.count)] {
      let generatedEnd = min(next.generated, lastGenerated)
      let sourceEnd = min(next.source, lastSource)
      let generatedSpan = max(generatedEnd - previous.generated, 0)
      let sourceSpan = max(sourceEnd - previous.source, 0)
      if previous.generated <= generatedEnd {
        for generatedIndex in previous.generated...generatedEnd {
          let offset = max(generatedIndex - previous.generated, 0)
          let mapped = generatedSpan == 0 ? previous.source : previous.source + offset * sourceSpan / generatedSpan
          result[generatedIndex] = mapped + 1
        }
      }
      if next.generated < generatedLines.count { result[next.generated] = min(next.source, lastSource) + 1 }
      previous = next
    }
    return result
  }

  /// The 1-based column of the first character that is not white space, or 1.
  private static func firstColumn(_ line: [UInt8]) -> Int {
    let scalars = String(decoding: line, as: UTF8.self).unicodeScalars
    return (scalars.firstIndex { !$0.properties.isWhitespace }.map { scalars.distance(from: scalars.startIndex, to: $0) } ?? 0) + 1
  }

  /// Line and column anchors for every generated line: where its first non-blank character came from, and, when the
  /// line was rewritten, where it still shares a prefix with the source line.
  static func points(original: String, generated: String) -> [JSONValue] {
    let sourceLines = lines(of: original)
    let generatedLines = lines(of: generated)
    let lineMap = lineMap(sourceLines: sourceLines, generatedLines: generatedLines)
    func point(_ generatedLine: Int, _ generatedColumn: Int, _ sourceLine: Int, _ sourceColumn: Int) -> JSONValue {
      .object([
        "generated": .object(["line": .int(generatedLine), "column": .int(generatedColumn)]),
        "source": .object(["line": .int(sourceLine), "column": .int(sourceColumn)]),
      ])
    }
    var result: [JSONValue] = []
    for (generatedIndex, generatedLine) in generatedLines.enumerated() {
      let sourceIndex = min(max((generatedIndex < lineMap.count ? lineMap[generatedIndex] : 1) - 1, 0), max(sourceLines.count - 1, 0))
      let sourceLine = sourceIndex < sourceLines.count ? sourceLines[sourceIndex] : []
      result.append(point(generatedIndex + 1, firstColumn(generatedLine), sourceIndex + 1, firstColumn(sourceLine)))
      if generatedLine != sourceLine {
        // Prefixes inserted by a rule resolve to the start of the original declaration, while the first shared token
        // is the more useful editor anchor when one exists.
        let shared = zip(String(decoding: generatedLine, as: UTF8.self).unicodeScalars, String(decoding: sourceLine, as: UTF8.self).unicodeScalars)
          .prefix { $0 == $1 }.count
        if shared > 0 { result.append(point(generatedIndex + 1, shared + 1, sourceIndex + 1, shared + 1)) }
      }
    }
    return result
  }

  /// FNV-1a over the UTF-8 bytes, as 16 hex digits: the content identity of the report and the state file. It is an
  /// incremental provenance marker, not a security hash, and unlike `Hasher` it does not depend on a per-process seed.
  public static func stableHash(_ text: String) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in text.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0100_0000_01b3
    }
    let digits = String(hash, radix: 16)
    return String(repeating: "0", count: 16 - digits.count) + digits
  }
}
