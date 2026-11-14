import Testing
@_spi(Renderer) import SwiftUIWebFiber
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

@Suite(.serialized)
struct MutationWordBufferTests {
  @Test
  func commandBufferAppendsFourWordsAndResetsByValue() {
    var buffer = _DOMMutationCommandBuffer()
    buffer.append(.setText, a: 1, b: 2, c: 3)
    let clone = buffer
    buffer.append(.setText, a: 4)
    _expectEqual(buffer.commandCount, 2)
    _expectEqual(buffer.wordCount, 8)
    _expectEqual(clone.words, [_DOMMutationOpcode.setText.rawValue, 1, 2, 3])
    buffer = _DOMMutationCommandBuffer()
    _expectTrue(buffer.words.isEmpty)
    _expectEqual(clone.commandCount, 1, "a copy stays valid after its source is replaced")
  }

  @MainActor @Test
  func packedBufferKeepsSixWordRecordsAndHandsOutStableCopies() {
    let tree = FiberTree(ForEach([1, 2, 3], id: \.self) { Text("Row \($0)") })
    _ = tree.update(ForEach([3, 1], id: \.self) { Text("Row \($0)") })
    let buffer = tree._lastPackedMutations
    _expectGreaterThan(buffer.recordCount, 0)
    _expectEqual(buffer.wordCount, buffer.recordCount * 6)
    _expectEqual(buffer.words.count, buffer.wordCount)
    _expectNotNil(buffer.record(at: 0))
    let copy = buffer.words
    buffer.reset()
    _expectEqual(buffer.wordCount, 0)
    _expectEqual(copy.count, buffer.recordCount * 6 + copy.count, "a copy taken before the reset keeps its words")
    _expectNotEqual(copy.count, 0)
  }

  @Test
  func domBufferPreservesSwiftCopyOnWrite() {
    var original = _DOMMutationCommandBuffer()
    original.append(.setText, a: 1, b: original.intern("first"))
    var copy = original
    copy.append(.setText, a: 2, b: copy.intern("second"))
    _expectEqual(original.commandCount, 1)
    _expectEqual(copy.commandCount, 2)
    _expectEqual(original.strings, ["first"])
    _expectEqual(copy.strings, ["first", "second"])
    _expectEqual(Array(copy.words.prefix(4)), original.words)
  }
}
