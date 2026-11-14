import Foundation
import Testing
import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@testable import SwiftUIWebAVFoundation

/// The media view renders what the player wants and the browser host reports what the element
/// did; nothing else crosses, so the same contract holds on the main thread and in the worker.
@Suite
@MainActor
struct AVFoundationHostContractTests {
  private func render(_ player: AVPlayer) -> _RenderNode {
    VideoPlayer(player: player, showsPlaybackControls: false)._render(in: _RenderContext())
  }

  @Test func the_view_renders_the_wished_state() {
    let player = AVPlayer(url: URL(string: "https://media.example/movie.mp4")!)
    var node = render(player)
    #expect(node.attributes["src"] == "https://media.example/movie.mp4")
    #expect(node.attributes["data-media-source"] == nil)
    #expect(node.attributes["data-media-playing"] == "0")
    #expect(node.events["media-report"] != nil)

    player.play()
    player.isMuted = true
    player.volume = 0.5
    node = render(player)
    #expect(node.attributes["data-media-playing"] == "1")
    #expect(node.attributes["data-media-muted"] == "1")
    #expect(node.attributes["data-media-volume"] == "0.5")

    player.pause()
    #expect(render(player).attributes["data-media-playing"] == "0")
  }

  @Test func adaptive_sources_are_left_to_the_host() {
    let player = AVPlayer(url: URL(string: "https://media.example/show/index.m3u8")!)
    let node = render(player)
    #expect(node.attributes["src"] == nil, "the host picks native HLS or Shaka")
    #expect(node.attributes["data-media-source"] == "https://media.example/show/index.m3u8")
  }

  @Test func one_shot_requests_carry_a_growing_sequence() {
    let player = AVPlayer(url: URL(string: "https://media.example/movie.mp4")!)
    #expect(render(player).attributes["data-media-command"] == nil)
    player.seek(to: .seconds(12.5))
    #expect(render(player).attributes["data-media-command"] == "1:seek:12.5")
    player.requestFullscreen()
    #expect(render(player).attributes["data-media-command"] == "2:fullscreen")
    player.startPictureInPicture()
    #expect(render(player).attributes["data-media-command"] == "3:pip:1")
  }

  @Test func every_request_changes_the_render_revision() {
    let player = AVPlayer(url: URL(string: "https://media.example/movie.mp4")!)
    var last = player._renderRevision
    for request in [{ player.play() }, { player.pause() }, { player.isMuted = true }, { player.volume = 0.2 },
                    { player.seek(to: .seconds(3)) }, { player.requestFullscreen() }] {
      request()
      #expect(player._renderRevision != last)
      last = player._renderRevision
    }
  }

  @Test func host_reports_update_time_duration_and_the_wish() {
    let player = AVPlayer(url: URL(string: "https://media.example/movie.mp4")!)
    let ticks = _TestBox<[Double]>([])
    _ = player.addPeriodicTimeObserver(forInterval: .seconds(1), queue: nil) { ticks.value.append($0.seconds) }
    player.play()
    let handler = render(player).events["media-report"]

    handler?.valueAction?("loadedmetadata|0|42.5|1|0|1")
    #expect(player.currentItem?.duration.seconds == 42.5)
    handler?.valueAction?("timeupdate|7.25|42.5|0|0|1")
    #expect(player.currentTime().seconds == 7.25)
    #expect(ticks.value.last == 7.25)

    // The browser paused on its own (native controls, a refused autoplay): the wish follows, so the
    // next render does not ask to play again.
    let revision = player._renderRevision
    handler?.valueAction?("pause|7.25|42.5|1|0|1")
    #expect(player.timeControlStatus == .paused)
    #expect(player._renderRevision != revision)
    #expect(render(player).attributes["data-media-playing"] == "0")

    #expect(ticks.value.last == 7.25 && ticks.value.count == 3, "a pause reaches observers even though time did not move")
    handler?.valueAction?("timeupdate|1|42.5|1|0|1")
    #expect(ticks.value.last == 1, "a jump backwards reaches observers")

    handler?.valueAction?("volumechange|7.25|42.5|1|1|0.3")
    #expect(player.isMuted)
    #expect(abs(player.volume - 0.3) < 0.001)
  }

  @Test func a_new_element_learns_where_the_player_is() {
    let player = AVPlayer(url: URL(string: "https://media.example/movie.mp4")!)
    #expect(render(player).attributes["data-media-start"] == nil, "nothing to resume at zero")
    render(player).events["media-report"]?.valueAction?("timeupdate|12.5|40|0|0|1")
    #expect(render(player).attributes["data-media-start"] == "12.5")
  }

  @Test func malformed_reports_are_ignored() {
    #expect(_MediaHostReport("timeupdate|1|2|0|0") == nil)
    #expect(_MediaHostReport("bogus|1|2|0|0|1") == nil)
    #expect(_MediaHostReport("timeupdate|x|2|0|0|1") == nil)
    #expect(_MediaHostReport("durationchange|1|-1|0|0|1")?.duration.isNaN == true)
    #expect(_MediaHostReport("seeked|3|10|1|0|1")?.event == .seeked)
    #expect(_MediaHostReport("pause|3|10|1|0|1||1|4|0|0|0|0|0|7|12")?.intent == 12)
    #expect(_MediaHostReport("pause|3|10|1|0|1||1|4|0|0|0|0|0|7|")?.intent == nil, "a report without an intent names none")
    #expect(_MediaHostReport("pause|3|10|1|0|1||1|4|0|0|0|0|0|7|x") == nil)
  }

  @Test func loaded_ranges_reach_the_item() {
    let player = AVPlayer(url: URL(string: "https://media.example/movie.mp4")!)
    let report = render(player).events["media-report"]?.valueAction
    report?("progress|3|40|0|0|1|0-12.5;20-25")
    let ranges = player.currentItem?.loadedTimeRanges.map { [$0.start.seconds, $0.end.seconds] }
    #expect(ranges == [[0, 12.5], [20, 25]])
    report?("timeupdate|4|40|0|0|1")
    #expect(player.currentItem?.loadedTimeRanges.isEmpty == true, "a report without the field has nothing loaded")
  }
}


/// A reference box for values that Sendable callbacks in these tests write.
private final class _TestBox<Value>: @unchecked Sendable {
  var value: Value
  init(_ value: Value) { self.value = value }
}
