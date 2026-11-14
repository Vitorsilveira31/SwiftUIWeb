import SwiftUIWeb
import SwiftUIWebAVFoundation
import SwiftUIWebAVKit

// Link and lowering fixture for the Foundation and media surface an application reaches first: `URLSession.data(for:)`
// through a `URLProtocol` registered globally, `AVPlayer`/`VideoPlayer`, a custom environment key set with a key path,
// `.task(id:)` over an optional String, `.id` over an optional Int, and `AVURLAsset.load(.variants)`. Built in release and
// debug by `make embedded-link-test`: an unresolved symbol in either configuration fails the gate.

/// Answers `fixture://` requests without the browser transport, as an application stubs networking in tests.
private final class EmbeddedFixtureURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.scheme == "fixture"
  }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/plain"]) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("fixture".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private enum EmbeddedFixtureLabelKey: EnvironmentKey {
  static let defaultValue = "unset"
}

private extension EnvironmentValues {
  var fixtureLabel: String {
    get { self[EmbeddedFixtureLabelKey.self] }
    set { self[EmbeddedFixtureLabelKey.self] = newValue }
  }
}

private struct EmbeddedFixtureLabel: View {
  @Environment(\.fixtureLabel) private var fixtureLabel
  var body: some View { Text("Label: \(fixtureLabel)") }
}

/// A player created in a `@State` initializer, while the page renders: its creation must not publish a nested
/// render pass (the runtime refuses one in the same store, which trapped before `_embeddedRequestPublishForMedia`).
@MainActor final class EmbeddedFixturePlayerModel {
  let player = AVPlayer(url: URL(string: "/probe.mp4")!)
}

struct EmbeddedNetworkMediaFixtureView: View {
  let onExit: @MainActor () -> Void
  @State private var sourceName: String? = nil
  @State private var loadedBody = "not loaded"
  @State private var model = EmbeddedFixturePlayerModel()
  @State private var variantCount = -1

  var body: some View {
    VStack {
      Button("Return to conformance app", action: onExit)
      Text("Network: \(loadedBody)")
        .task {
          _ = URLProtocol.registerClass(EmbeddedFixtureURLProtocol.self)
          if let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: URL(string: "fixture://embedded/hello")!)) {
            loadedBody = String(decoding: data, as: UTF8.self)
          }
        }
      Text("Variants: \(variantCount)")
        .task(id: sourceName) {
          let asset = AVURLAsset(url: URL(string: "/probe.m3u8")!)
          if let variants = try? await asset.load(.variants) { variantCount = variants.count }
        }
      Text("Source: \(sourceName ?? "none")")
        .task(id: sourceName) {
          sourceName = sourceName ?? "fixture"
        }
      Text("Keyed").id(variantCount as Int?)
      EmbeddedFixtureLabel()
        .environment(\.fixtureLabel, "fixture")
      VideoPlayer(player: model.player)
    }
  }
}
