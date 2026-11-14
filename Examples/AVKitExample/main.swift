import SwiftUIWeb
import SwiftUIWebBrowser
import SwiftUIWebAVFoundation
import SwiftUIWebAVKit

/// Three real public streams exercise the native MP4 path, native/fallback HLS
/// path, and lazy adaptive (DASH/Shaka) path respectively. Shaka is only
/// loaded for the final player by the AVFoundation backend.
@main
private struct AVKitExample: BrowserApp {
  private static let mp4 = AVPlayer(
    url: URL(string: "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4")!
  )
  private static let hls = AVPlayer(
    url: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!
  )
  private static let adaptive = AVPlayer(
    url: URL(string: "https://storage.googleapis.com/shaka-demo-assets/angel-one/dash.mpd")!
  )

  var body: some View {
    WindowGroup {
      VStack {
        Text("SwiftUIWebAVKit")
        Text("MP4, HLS and adaptive streaming")

        VideoPlayer(player: Self.mp4)
          .frame(height: 240)
        VideoPlayer(player: Self.hls)
          .frame(height: 240)
        VideoPlayer(player: Self.adaptive)
          .frame(height: 240)

        HStack {
          Button("Play MP4") { Self.mp4.play() }
          Button("Pause MP4") { Self.mp4.pause() }
          Button("Seek 30s") { Self.mp4.seek(to: CMTime(seconds: 30, preferredTimescale: 600)) }
        }
      }
      .padding()
    }
  }
}

