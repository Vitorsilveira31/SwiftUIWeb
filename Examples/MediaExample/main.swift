import SwiftUIWeb
import SwiftUIWebBrowser
import SwiftUIWebAVFoundation
import SwiftUIWebAVKit

/// A real browser-media fixture. The AVFoundation-shaped player controls the
/// native HTML media element; the same source can be used from ordinary Swift
/// code without importing browser bridge or DOM types.
@main
private struct MediaExample: BrowserApp {
  private static let player = AVPlayer(
    url: URL(string: "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4")!
  )
  private static let audioPlayer = AVPlayer(
    url: URL(string: "https://interactive-examples.mdn.mozilla.net/media/cc0-audio/t-rex-roar.mp3")!
  )

  var body: some View {
    WindowGroup {
      VStack {
        Text("SwiftUIWebAVFoundation")
        Text("Native HTML media playback with an AVPlayer-shaped API")
        VideoPlayer(player: Self.player)
          .frame(height: 280)
        HStack {
          Button("Play") { Self.player.play() }
          Button("Pause") { Self.player.pause() }
          Button("Seek 30s") { Self.player.seek(to: CMTime(seconds: 30, preferredTimescale: 600)) }
        }
        Text("Duration: \(Self.player.currentItem?.duration.seconds ?? .nan)")
        VideoPlayer(player: Self.audioPlayer)
      }
      .padding()
    }
  }
}
