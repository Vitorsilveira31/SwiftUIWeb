import Foundation
import Testing
import SwiftUIWeb
import SwiftUIWebAVFoundation

@Suite
@MainActor
final class AVFoundationTests {
  @Test
  func testCMTimeAndRangeMath() {
    let start = CMTime.seconds(30)
    let duration = CMTime.seconds(15)
    let range = CMTimeRange(start: start, duration: duration)

    _expectEqual(range.end.seconds, 45, accuracy: 0.0001)
    _expectTrue(range.containsTime(.seconds(30)))
    _expectTrue(range.containsTime(.seconds(44.5)))
    _expectFalse(range.containsTime(.seconds(45)))
    _expectEqual(range.intersection(CMTimeRange(start: .seconds(40), duration: .seconds(10))).duration.seconds, 5, accuracy: 0.0001)
  }

  @Test
  func testPlayerControlsPersistBeforeBrowserMount() {
    let player = AVPlayer(url: URL(string: "https://example.com/movie.mp4")!)
    player.rate = 1.5
    player.volume = 0.35
    player.isMuted = true
    player.seek(to: .seconds(30))

    _expectEqual(player.rate, 1.5, accuracy: 0.001)
    _expectEqual(player.volume, 0.35, accuracy: 0.001)
    _expectTrue(player.isMuted)
    _expectEqual(player.currentTime().seconds, 30, accuracy: 0.001)

    player.play()
    _expectEqual(player.timeControlStatus, .playing)
    player.pause()
    _expectEqual(player.timeControlStatus, .paused)
  }

  @Test
  func testVideoPlayerRendersSemanticMediaElement() {
    let player = AVPlayer(url: URL(string: "https://example.com/movie.mp4")!)
    let html = StaticHTMLFiberRenderer().render(VideoPlayer(player: player))

    _expectTrue(html.contains("<video"))
    _expectTrue(html.contains("src=\"https://example.com/movie.mp4\""))
    _expectTrue(html.contains("data-media-playing=\"0\""))
    _expectTrue(html.contains("data-player-id=\"media-"))
    _expectTrue(html.contains("controls"))
  }

  @Test
  func testVideoPlayerRendersAnAudioElementForAudioSources() {
    let audio = AVPlayer(url: URL(string: "https://example.com/files/review.m4a?token=a.b.mp4#t=1")!)
    let audioHTML = StaticHTMLFiberRenderer().render(VideoPlayer(player: audio))
    _expectTrue(audioHTML.contains("<audio"))
    _expectFalse(audioHTML.contains("<video"))
    _expectTrue(audioHTML.contains("controls"))

    let hidden = StaticHTMLFiberRenderer().render(VideoPlayer(player: audio, showsPlaybackControls: false))
    _expectTrue(hidden.contains("<audio"))
    _expectFalse(hidden.contains("controls"))

    let video = AVPlayer(url: URL(string: "https://example.com/movie.mp4?name=a.mp3")!)
    _expectTrue(StaticHTMLFiberRenderer().render(VideoPlayer(player: video)).contains("<video"))
  }

  @Test
  func testAdaptiveAssetIsMarkedWithoutExposingShaka() {
    let asset = AVURLAsset(
      url: URL(string: "https://example.com/stream.m3u8")!,
      options: ["title": "Live stream", "drm": true]
    )
    _expectTrue(asset.requiresAdaptiveStreaming)
    _expectEqual(asset.mediaType, .video)
    _expectEqual(asset.commonMetadata.first?.stringValue, "Live stream")
  }
}
