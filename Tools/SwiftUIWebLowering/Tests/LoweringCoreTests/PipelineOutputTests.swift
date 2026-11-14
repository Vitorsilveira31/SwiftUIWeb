import Testing

@testable import LoweringCore

/// What an application source is lowered to by every pass together, for the imports the passes add to each other's
/// output.
@Suite struct PipelineOutputTests {
  private static let model = "@Observable final class Model {\n  var value = 1\n}\n"

  @Test func theObservableClassGetsTheImportOfTheModuleTheTargetUses() {
    let aliased = lowered(Self.model, aliased: true)
    #expect(aliased.hasPrefix("@_spi(Renderer) import SwiftUI\n"))
    #expect(aliased.contains("@Published(memberID: 1) var value = 1"))
    #expect(lowered(Self.model).hasPrefix("@_spi(Renderer) import SwiftUIWeb\n"))
  }

  @Test func loweringNeverWritesCombine() {
    for aliased in [true, false] {
      #expect(!lowered(Self.model, aliased: aliased).contains("Combine"), "aliased: \(aliased)")
    }
  }

  @Test func theImportIsAddedInsideAFileThatIsOneConditionalBlock() {
    let output = lowered("#if !WEB\n\(Self.model)#endif\n")
    #expect(output.hasPrefix("#if !WEB\n@_spi(Renderer) import SwiftUIWeb\n"))
    #expect(output.hasSuffix("#endif\n"))
    #expect(output.components(separatedBy: "import SwiftUIWeb").count - 1 == 1)
  }

  @Test func theImportIsAddedToEveryBranchOfAGuardedFile() {
    let output = lowered("#if !WEB\nlet tag = 1\n#else\n\(Self.model)#endif\n", aliased: true)
    #expect(output.hasPrefix("#if !WEB\n@_spi(Renderer) import SwiftUI\nlet tag = 1\n#else\n@_spi(Renderer) import SwiftUI\n"))
    #expect(output.contains("@Published(memberID: 1) var value = 1"))
  }

  @Test func theSecondPassAddsNoSecondImport() {
    for source in [Self.model, "#if !WEB\n\(Self.model)#endif\n"] {
      let once = lowered(source, aliased: true)
      #expect(lowered(once, aliased: true) == once)
    }
  }

  @Test func anImportOfTheFrameworkIsNotImportedAgain() {
    for (existing, aliased) in [("import SwiftUIWeb", false), ("import SwiftUI", true)] {
      let output = lowered("\(existing)\n\(Self.model)", aliased: aliased)
      #expect(output.components(separatedBy: "import ").count - 1 == 1, "\(output)")
    }
  }
}
