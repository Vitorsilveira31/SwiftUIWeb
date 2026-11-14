import Foundation
import Dispatch
import Testing
import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
final class DOMMutationBatchTests {
  @Test
  func testCommandBufferUsesFourNumericWordsAndInternsStrings() {
    var buffer = _DOMMutationCommandBuffer()
    let textID = buffer.intern("same value")
    let duplicateID = buffer.intern("same value")
    _expectEqual(textID, duplicateID)

    buffer.append(.create, a: 0, b: textID)
    buffer.append(.insert, a: 1, b: 0, c: _DOMMutationCommandBuffer.noHandle)
    buffer.append(.setText, a: 0, b: textID)
    buffer.append(.removeAttribute, a: 0, b: buffer.intern("class"))
    buffer.append(.setStyle, a: 0, b: buffer.intern("color"), c: textID)
    buffer.append(.addEvent, a: 0, b: buffer.intern("click"), c: buffer.intern("event-1"))
    buffer.append(.removeEvent, a: 0, b: buffer.intern("click"))

    _expectEqual(buffer.commandCount, 7)
    _expectEqual(buffer.wordCount, buffer.commandCount * 4)
    _expectEqual(buffer.encodedByteCount, buffer.wordCount * MemoryLayout<UInt32>.size)
    _expectEqual(buffer.strings.filter { $0 == "same value" }.count, 1)
  }

  @Test
  func testFrameworkVocabularyUsesStaticTokensOutsideDynamicStringTable() {
    var buffer = _DOMMutationCommandBuffer()
    let firstClass = buffer.intern(.attributeClass)
    let secondClass = buffer.intern(.attributeClass)
    let click = buffer.intern(.eventClick)
    let custom = buffer.internFramework("data-my-application-value")
    buffer.append(.create, a: 1, b: buffer.intern(.tagDiv), c: 1)

    _expectEqual(firstClass, secondClass)
    _expectNotEqual(firstClass & 0x8000_0000, 0)
    _expectNotEqual(click & 0x8000_0000, 0)
    _expectEqual(buffer.strings, ["data-my-application-value"])
    _expectEqual(buffer.staticInternHits, 4)
    _expectEqual(buffer.dynamicInternHits, 0)
    _expectEqual(custom, 0)
    _expectEqual(buffer.words.suffix(4), [1, 1, _DOMStaticStringID.tagDiv.token, 1])
  }

  @Test
  func testFrameworkLookupKeepsUnknownValuesDynamic() {
    var buffer = _DOMMutationCommandBuffer()
    let known = buffer.internFramework("display")
    let unknown = buffer.internFramework("--app-accent")
    _expectEqual(known, _DOMStaticStringID.styleDisplay.token)
    _expectEqual(unknown, 0)
    _expectEqual(buffer.strings, ["--app-accent"])
  }

  /// Release runs print a reproducible construction comparison of the Swift-side
  /// cost and payload reduction, without requiring a WASM browser SDK on the host.
  @Test
  func testCommandBufferConstructionBenchmark() {
    for count in [1, 10, 100, 1_000, 10_000] {
      let start = DispatchTime.now().uptimeNanoseconds
      var buffer = _DOMMutationCommandBuffer()
      let valueID = buffer.intern("value")
      for index in 0..<count {
        buffer.append(.setText, a: UInt32(index), b: valueID)
      }
      let elapsed = DispatchTime.now().uptimeNanoseconds - start
      // A per-operation bridge must carry the four command fields repeatedly,
      // while the batch has one invocation and a single interned value.
      let individualPayloadBytes = count * (4 * MemoryLayout<UInt32>.size + "value".utf8.count)
      let batchPayloadBytes = buffer.encodedByteCount + "value".utf8.count
      print("dom-batch,mutations=\(count),swiftEncodeNs=\(elapsed),bridgeCallsIndividual=\(count),bridgeCallsBatch=1,commandWords=\(buffer.wordCount),payloadBytes=\(batchPayloadBytes),individualPayloadBytes=\(individualPayloadBytes),strings=\(buffer.strings.count)")
      _expectEqual(buffer.commandCount, count)
      _expectEqual(buffer.strings.count, 1)
      _expectLessThanOrEqual(batchPayloadBytes, individualPayloadBytes)
    }
  }

  /// Compares the two string paths used by the renderer. Static vocabulary
  /// tokens avoid hashing and bridge-payload copies; dynamic values remain
  /// commit-local and are still deduplicated by the ordinary table.
  @Test
  func testStringInterningBenchmark() {
    for count in [1, 10, 100, 1_000, 10_000] {
      let frameworkNames = ["class", "style", "display", "flex", "click"]
      var dynamicBuffer = _DOMMutationCommandBuffer()
      let dynamicStart = DispatchTime.now().uptimeNanoseconds
      for index in 0..<count { _ = dynamicBuffer.intern(frameworkNames[index % frameworkNames.count]) }
      let dynamicNs = DispatchTime.now().uptimeNanoseconds - dynamicStart

      var staticBuffer = _DOMMutationCommandBuffer()
      let staticStart = DispatchTime.now().uptimeNanoseconds
      for index in 0..<count {
        switch frameworkNames[index % frameworkNames.count] {
        case "class": _ = staticBuffer.intern(.attributeClass)
        case "style": _ = staticBuffer.intern(.attributeStyle)
        case "display": _ = staticBuffer.intern(.styleDisplay)
        case "flex": _ = staticBuffer.intern(.styleFlex)
        default: _ = staticBuffer.intern(.eventClick)
        }
      }
      let staticNs = DispatchTime.now().uptimeNanoseconds - staticStart
      var frameworkBuffer = _DOMMutationCommandBuffer()
      let frameworkStart = DispatchTime.now().uptimeNanoseconds
      for index in 0..<count { _ = frameworkBuffer.internFramework(frameworkNames[index % frameworkNames.count]) }
      let frameworkNs = DispatchTime.now().uptimeNanoseconds - frameworkStart
      let dynamicPayloadBytes = dynamicBuffer.strings.reduce(0) { $0 + $1.utf8.count }
      let staticPayloadBytes = staticBuffer.strings.reduce(0) { $0 + $1.utf8.count }
      print("string-intern,count=\(count),dynamicNs=\(dynamicNs),staticNs=\(staticNs),frameworkNs=\(frameworkNs),dynamicStrings=\(dynamicBuffer.strings.count),staticStrings=\(staticBuffer.strings.count),frameworkStrings=\(frameworkBuffer.strings.count),dynamicStringBytes=\(dynamicPayloadBytes),staticStringBytes=\(staticPayloadBytes),dynamicHits=\(dynamicBuffer.dynamicInternHits),staticHits=\(staticBuffer.staticInternHits)")
      _expectEqual(dynamicBuffer.strings.count, min(count, frameworkNames.count))
      _expectEqual(staticBuffer.strings.count, 0)
      _expectEqual(staticBuffer.staticInternHits, count)
      _expectEqual(frameworkBuffer.strings.count, 0)
      _expectEqual(frameworkBuffer.staticInternHits, count)
    }
  }

  @Test
  func testPackedMutationBufferPreservesSemanticOperations() {
    let tree = FiberTree(ForEach([1, 2, 3], id: \.self) { Text("\($0)") })
    _ = tree.update(ForEach([3, 1, 4], id: \.self) { Text("\($0)") })

    let packed = tree._lastPackedMutations
    let materialized = packed.materialize()
    _expectEqual(packed.recordCount, materialized.count)
    _expectEqual(materialized.count, tree.lastMutations.count)
    _expectTrue((0..<packed.recordCount).allSatisfy { packed.record(at: $0) != nil })
    _expectTrue(materialized.contains { if case .move = $0 { return true }; return false })
    _expectTrue(materialized.contains { if case .insert = $0 { return true }; return false })
    _expectTrue(materialized.contains { if case .remove = $0 { return true }; return false })
    _expectGreaterThan(packed.wordCount, 0)
    _expectGreaterThan(packed.storageByteCount, packed.wordCount * MemoryLayout<UInt32>.stride)
    _expectGreaterThan(tree.metrics.packedMutationRecords, 0)
    _expectGreaterThan(tree.metrics.packedMutationMaterializations, 0)

    _ = tree.update(ForEach([3, 1, 4], id: \.self) { Text("\($0)") })
    _expectGreaterThan(tree.metrics.packedMutationBufferReuses, 0)
  }

  @Test
  func testPackedUpdateAndReplaceRetainGenerationalTarget() {
    let updateTree = FiberTree(Text("before"))
    let updateFiberID = updateTree.root.structuralID
    _ = updateTree.update(Text("after"))
    _expectEqual(updateTree._lastPackedMutations.record(at: 0)?.opcode, .update)
    _expectEqual(updateTree._lastPackedMutations.structuralID(at: updateTree._lastPackedMutations.record(at: 0)!.target), updateFiberID)
    _expectTrue(updateTree._lastPackedMutations.materialize().contains { if case .update = $0 { return true }; return false })

    let replaceTree = FiberTree(Text("before"))
    _ = replaceTree.update(Button("after", action: {}))
    _expectEqual(replaceTree._lastPackedMutations.record(at: 0)?.opcode, .replace)
    _expectTrue(replaceTree._lastPackedMutations.materialize().contains { if case .replace = $0 { return true }; return false })
  }

  @Test
  func testRendererEntryPointAvoidsCompatibilityMaterialization() {
    let tree = FiberTree(Text("before"))
    let packed = tree._updateForRenderer(Text("after"))
    _expectEqual(packed.recordCount, 1)
    _expectTrue(tree.lastMutations.isEmpty)
    _expectEqual(tree.metrics.packedMutationMaterializations, 0)

    let compatibility = tree._materializeLastPackedMutations()
    _expectEqual(compatibility.count, 1)
    _expectEqual(tree.metrics.packedMutationMaterializations, 1)
  }

  @Test
  func testDisabledRecordingSkipsPackedMutationsButStillReconciles() {
    // The Embedded browser never reads the packed buffer, so it switches recording off.
    let recorded = FiberTree(ForEach([1, 2, 3], id: \.self) { Text("\($0)") })
    let silent = FiberTree(ForEach([1, 2, 3], id: \.self) { Text("\($0)") })
    silent._setRecordsPackedMutations(false)
    _ = recorded._updateForRenderer(ForEach([3, 1, 4], id: \.self) { Text("\($0)") })
    let packed = silent._updateForRenderer(ForEach([3, 1, 4], id: \.self) { Text("\($0)") })

    _expectGreaterThan(recorded._lastPackedMutations.recordCount, 0)
    _expectEqual(packed.recordCount, 0)
    _expectEqual(packed.wordCount, 0)
    _expectTrue(packed.nodes.isEmpty)
    _expectEqual(silent.metrics.packedMutationRecords, 0)
    // The retained tree is the same either way: only the side stream is skipped.
    _expectEqual(silent.renderNode.children.count, recorded.renderNode.children.count)
    _expectEqual(silent.renderNode.children.map { $0.children.first?.text ?? $0.text }, recorded.renderNode.children.map { $0.children.first?.text ?? $0.text })

    // Switching it back on resumes recording.
    silent._setRecordsPackedMutations(true)
    _ = silent._updateForRenderer(ForEach([5, 3], id: \.self) { Text("\($0)") })
    _expectGreaterThan(silent._lastPackedMutations.recordCount, 0)
  }

  /// Release-only numbers make the semantic representation trade-off visible
  /// without requiring a browser or a WASM toolchain.  The packed record
  /// stream is fixed-width and reusable; `Mutation` is materialized solely at
  /// the compatibility boundary.
  @Test
  func testPackedMutationConstructionBenchmark() {
    for count in [1, 10, 100, 1_000, 10_000] {
      let root = FiberTree(Text("root")).root
      let shared = _RenderNode.text("value")
      let richStart = DispatchTime.now().uptimeNanoseconds
      var rich: [Mutation] = []
      rich.reserveCapacity(count)
      for _ in 0..<count {
        rich.append(.update(previous: shared, new: shared, fiber: root))
      }
      let richNs = DispatchTime.now().uptimeNanoseconds - richStart
      let start = DispatchTime.now().uptimeNanoseconds
      let packed = _PackedMutationBuffer(reserveCapacity: count)
      packed.setOwnerRoot(root)
      for _ in 0..<count { packed.appendUpdate(previous: shared, new: shared, fiber: root) }
      let encodeNs = DispatchTime.now().uptimeNanoseconds - start
      let richBytes = packed.recordCount * MemoryLayout<Mutation>.stride
      let packedBytes = packed.storageByteCount
      print("packed-mutation,count=\(count),richEncodeNs=\(richNs),packedEncodeNs=\(encodeNs),records=\(packed.recordCount),words=\(packed.wordCount),packedBytes=\(packedBytes),richEnumBytes=\(richBytes),ids=\(packed.structuralIDs.count),nodes=\(packed.nodes.count)")
      _expectEqual(rich.count, count)
      _expectEqual(packed.recordCount, count)
      _expectEqual(packed.wordCount, count * _PackedMutationRecord.wordStride)
      _expectEqual(packed.materialize().count, count)
    }
  }
}
