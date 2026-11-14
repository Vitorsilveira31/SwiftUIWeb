import Testing
@_spi(Renderer) @testable import SwiftUIWebCore
import SwiftUIWebFiber
import SwiftUIWeb

/// Apple's `Image("name")` loads an asset or a file of the app's own site; a remote URL loads only through
/// `Image(_:alt:)`, so a name taken from server data cannot make the page fetch from another host.
@Suite(.serialized)
@MainActor
struct ImageSourceTests {
  private func _allNodes(_ node: _RenderNode) -> [_RenderNode] { [node] + node.children.flatMap(_allNodes) }

  @Test
  func onlyLocalPathsStandForThemselves() {
    #expect(_ImageAssets.isLocalPath("media/cover.jpg"))
    #expect(_ImageAssets.isLocalPath("/assets/a.png"))
    #expect(_ImageAssets.isLocalPath("a.png?v=1:2"))
    #expect(_ImageAssets.isLocalPath("data:image/png;base64,AAAA"))
    #expect(!_ImageAssets.isLocalPath("https://tracker.example.test/p.gif"))
    #expect(!_ImageAssets.isLocalPath("//tracker.example.test/p.gif"))
    #expect(!_ImageAssets.isLocalPath("javascript:alert(1)"))
    #expect(!_ImageAssets.isLocalPath("\\\\host\\share"))
    // As the browser reads them: leading spaces and every tab or line break are dropped.
    #expect(!_ImageAssets.isLocalPath(" //attacker.example/pixel"))
    #expect(!_ImageAssets.isLocalPath("/\t/attacker.example/pixel"))
    #expect(!_ImageAssets.isLocalPath("\n https://attacker.example/pixel"))
    #expect(_ImageAssets.isLocalPath("media/cover photo (1).png"))
    #expect(_ImageAssets.source(for: "https://cdn.example.test/a.png") == nil)
    #expect(_ImageAssets.source(for: "https://cdn.example.test/a.png", allowsRemote: true) == "https://cdn.example.test/a.png")
  }

  @Test
  func anAsyncImageShowsTheRemoteImageItLoaded() {
    let url = URL(string: "https://cdn.example.test/photo.png")!
    let view = AsyncImage(url: url) { phase in
      if let image = phase.image { image } else { Text("Loading") }
    }
    let tree = FiberTree(view)
    guard let loader = tree.findNode(withEvent: "load") else { Issue.record("no load event"); return }
    tree.dispatch(event: "load", on: loader)
    _ = tree.update(view)
    // The loaded image is shown with its URL: AsyncImage exists to load remote images.
    #expect(_allNodes(tree.renderNode).contains { $0.classes.contains("picture-view") && $0.attributes["src"] == url.absoluteString })
  }

  @Test
  func aRemoteCapableImageKeepsItsSourceInPaintsAndText() {
    let url = "https://cdn.example.test/photo.png"
    #expect(_resolvedImagePaint(ImagePaint(image: Image(url, alt: "p")))?.source == url)
    #expect(_resolvedImagePaint(AnyShapeStyle(ImagePaint(image: Image(url, alt: "p"))))?.source == url)
    #expect(_resolvedImagePaint(ImagePaint(image: Image(url))) == nil)
    let inline = FiberTree(Text(Image(url, alt: "p")), deferLazyCollections: false).renderNode
    #expect(_allNodes(inline).contains { $0.classes.contains("inline-image") && $0.attributes["src"] == url })
    let named = FiberTree(Text(Image(url)), deferLazyCollections: false).renderNode
    #expect(!_allNodes(named).contains { $0.attributes["src"] == url })
  }

  @Test
  func aCanvasDrawsARemoteCapableImageButNotARemoteName() {
    let url = "https://cdn.example.test/photo.png"
    let wire = { (image: Image) -> String in
      let canvas = Canvas { context, _ in context.draw(image, in: CGRect(x: 0, y: 0, width: 10, height: 10)) }
      return self._allNodes(FiberTree(canvas, deferLazyCollections: false).renderNode).compactMap { $0.attributes["data-canvas-commands"] }.joined()
    }
    #expect(wire(Image(url, alt: "p")).contains(url))
    #expect(!wire(Image(url)).contains(url))
  }

  @Test
  func aNameFromDataCannotForgeTheRemoteMark() {
    let forged = "\u{1}https://attacker.example/pixel"
    #expect(_ImageAssets.source(forMarked: _ImageAssets.marked(forged, allowsRemote: false)) == nil)
    #expect(_ImageAssets.source(forMarked: _ImageAssets.marked("\u{2}\u{1}https://attacker.example/p", allowsRemote: false)) == nil)
    let inline = FiberTree(Text(Image(forged)), deferLazyCollections: false).renderNode
    #expect(!_allNodes(inline).contains { $0.attributes["src"]?.contains("attacker") == true })
    let canvas = Canvas { context, _ in context.draw(Image(forged), in: CGRect(x: 0, y: 0, width: 4, height: 4)) }
    #expect(!_allNodes(FiberTree(canvas, deferLazyCollections: false).renderNode).contains { $0.attributes["data-canvas-commands"]?.contains("attacker") == true })
    #expect(_ImageAssets.source(forMarked: _ImageAssets.marked("media/a.png", allowsRemote: false)) == "media/a.png")
    // A name that carries the interpolation marker cannot close it early and open one with the mark.
    let split = "a\u{FFFC}\u{1}https://attacker.example/q\u{FFFC}"
    let interpolated = FiberTree(Text("x \(Image(split)) y"), deferLazyCollections: false).renderNode
    #expect(!_allNodes(interpolated).contains { $0.attributes["src"]?.contains("attacker") == true })
  }

  @Test
  func canvasSymbolsKeepDataImageSources() {
    let canvas = Canvas(renderer: { context, _ in
      if let symbol = context.resolveSymbol(id: 9) { context.draw(symbol, at: CGPoint(x: 4, y: 4)) }
    }, symbols: {
      Image("data:image/png;base64,AAAA").tag(9)
    })
    let commands = FiberTree(canvas, deferLazyCollections: false).renderNode._canvasCommands
    guard case .symbol(let markup, _, _, _, _, _) = commands.first else { Issue.record("no symbol drawn"); return }
    #expect(markup.contains("data:image/png;base64,AAAA"), "\(markup)")
  }

  @Test
  func aRemoteNameRendersNoSource() {
    _ImageAssets.install(nil)
    let remote = FiberTree(Image("https://tracker.example.test/p.gif"), deferLazyCollections: false).renderNode
    #expect(!_allNodes(remote).contains { $0.attributes["src"] != nil })
    let local = FiberTree(Image("media/cover.jpg"), deferLazyCollections: false).renderNode
    #expect(_allNodes(local).contains { $0.attributes["src"] == "media/cover.jpg" })
  }
}
