import Foundation
import Testing
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebHTML

/// Serializes `root` with the renderer under test, or with the reference serializer, using the options of the corpus.
@MainActor
func runHTMLWriter(_ root: _RenderNode, _ options: HTMLWriterCorpus.Options, legacy: Bool) -> [UInt8] {
  if legacy {
    return LegacyHTMLSerializer(maxElementDepth: options.depth).renderNodeUTF8(root)
  }
  return StaticHTMLFiberRenderer(maxElementDepth: options.depth).renderNodeUTF8(root)
}

/// The serializer against the reference one (`LegacyHTMLSerializer`, the single-buffer writer's predecessor), byte for byte, on
/// a corpus of trees and option sets and on seeded random trees. Nothing is recorded: the reference runs in the same process.
@Suite(.serialized)
@MainActor
struct HTMLWriterReferenceTests {
  /// The corpus against the reference serializer.
  @Test
  func theSerializerMatchesTheReferenceSerializerOnTheCorpus() {
    for tree in HTMLWriterCorpus.all {
      for options in HTMLWriterCorpus.options {
        let expected = runHTMLWriter(tree.make(), options, legacy: true)
        let actual = runHTMLWriter(tree.make(), options, legacy: false)
        #expect(actual == expected, "\(tree.name)|\(options.name): bytes")
      }
    }
  }

  @Test
  func theSerializerMatchesTheReferenceOnRandomTrees() {
    for seed in UInt64(1)...150 {
      let nodes = Int(seed % 5) * 20 + 3 + Int(seed % 7)
      for options in HTMLWriterCorpus.options {
        let expected = runHTMLWriter(HTMLWriterCorpus.randomTree(seed: seed &* 7919, nodes: nodes), options, legacy: true)
        let actual = runHTMLWriter(HTMLWriterCorpus.randomTree(seed: seed &* 7919, nodes: nodes), options, legacy: false)
        #expect(actual == expected, "seed \(seed)|\(options.name): bytes")
      }
    }
  }

  @Test
  func stringAndByteEntryPointsAgree() {
    for tree in HTMLWriterCorpus.all {
      let root = tree.make()
      let renderer = StaticHTMLFiberRenderer(maxElementDepth: 8)
      #expect(renderer.renderNode(root) == String(decoding: renderer.renderNodeUTF8(root), as: UTF8.self), "\(tree.name)")
      #expect(renderer.withRenderedUTF8(root) { Array($0) } == renderer.renderNodeUTF8(root), "\(tree.name): lent bytes")
    }
  }
}
