import Foundation
import Testing
import SwiftUIWeb
import SwiftUIWebBrowserIO
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@testable import SwiftUIWebAVFoundation
@_spi(WebMount) import SwiftUIWebBrowser

/// The mirror of a media element: reads are synchronous and right between the samples the host sends, on a manual clock.
@Suite
@MainActor
struct AVFoundationMirrorTests {
  /// A clock and a timer the test drives: `advance` moves both clocks and runs the timers that fall due.
  @MainActor final class Harness: @unchecked Sendable {
    var now = 100.0
    var timers: [(due: Double, id: Int, run: @Sendable () -> Void)] = []
    var nextID = 0
    var cancelled = Set<Int>()

    init() {
      _MediaClock.makeBackendOverride = { _DeclarativeMediaBackend() }
      _MediaClock.monotonicOverride = { [unowned self] in self.now }
      _MediaClock.wallMillisecondsOverride = { [unowned self] in 10_000_000 + self.now * 1000 }
      _MediaClock.scheduleOverride = { [unowned self] delay, callback in
        self.nextID += 1
        let id = self.nextID
        self.timers.append((self.now + delay, id, callback))
        return { self.cancelled.insert(id) }
      }
    }

    func restore() {
      _MediaClock.makeBackendOverride = nil
      _MediaClock.monotonicOverride = nil
      _MediaClock.wallMillisecondsOverride = nil
      _MediaClock.scheduleOverride = nil
    }

    /// Wall clock in the host's `Date.now()` terms.
    var hostNow: Double { 10_000_000 + now * 1000 }

    func advance(_ seconds: Double) {
      let target = now + seconds
      while let next = timers.filter({ !cancelled.contains($0.id) && $0.due <= target }).min(by: { $0.due < $1.due }) {
        timers.removeAll { $0.id == next.id }
        now = max(now, next.due)
        next.run()
      }
      now = target
    }

    /// A host report: event, time, duration, paused, rate, readyState, seeking, ended, seekSequence, age in seconds.
    func report(_ event: String, time: Double, duration: Double = 10, paused: Bool = false, rate: Double = 1, ready: Int = 4,
                seeking: Bool = false, ended: Bool = false, seek: UInt64 = 0, age: Double = 0) -> String {
      "\(event)|\(time)|\(duration)|\(paused ? 1 : 0)|0|1||\(rate)|\(ready)|\(seeking ? 1 : 0)|\(ended ? 1 : 0)|0|\(seek)|\(hostNow - age * 1000)|G"
    }
  }

  private func render(_ player: AVPlayer) -> _RenderNode {
    VideoPlayer(player: player, showsPlaybackControls: false)._render(in: _RenderContext())
  }

  private func makePlayer() -> (AVPlayer, (String) -> Void) {
    let player = AVPlayer(url: URL(string: "https://media.example/movie.mp4")!)
    let handler = render(player).events["media-report"]
    return (player, { handler?.valueAction?($0.replacingOccurrences(of: "|G", with: "|\(player._itemGeneration)")) })
  }

  @Test func reads_between_samples_follow_the_rate() {
    let clock = Harness()
    defer { clock.restore() }
    let (player, receive) = makePlayer()
    player.play()
    #expect(player.timeControlStatus == .waitingToPlayAtSpecifiedRate, "wanting to play is not playing yet")
    #expect(player.rate == 1)
    receive(clock.report("loadedmetadata", time: 0, paused: true, ready: 1))
    #expect(player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
    receive(clock.report("playing", time: 2))
    #expect(player.timeControlStatus == .playing)
    #expect(player.currentTime().seconds == 2)
    clock.advance(0.5)
    #expect(abs(player.currentTime().seconds - 2.5) < 0.0001)
    clock.advance(0.25)
    #expect(abs(player.currentTime().seconds - 2.75) < 0.0001)

    receive(clock.report("ratechange", time: 2.75, rate: 2))
    clock.advance(1)
    #expect(abs(player.currentTime().seconds - 4.75) < 0.0001, "twice the speed")

    receive(clock.report("pause", time: 4.75, paused: true, rate: 2))
    #expect(player.timeControlStatus == .paused)
    #expect(player.rate == 0, "AVPlayer reports no rate while paused")
    clock.advance(3)
    #expect(player.currentTime().seconds == 4.75, "a pause stops the extrapolation")
  }

  @Test func extrapolation_stops_at_the_end_while_waiting_and_while_seeking() {
    let clock = Harness()
    defer { clock.restore() }
    let (player, receive) = makePlayer()
    player.play()
    receive(clock.report("playing", time: 8.5, duration: 10))
    clock.advance(5)
    #expect(player.currentTime().seconds == 10, "never past the duration")

    receive(clock.report("waiting", time: 4, ready: 2))
    #expect(player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
    clock.advance(2)
    #expect(player.currentTime().seconds == 4, "no data, no progress")
    receive(clock.report("playing", time: 4))
    #expect(player.timeControlStatus == .playing)
    receive(clock.report("seeking", time: 6, seeking: true))
    clock.advance(1)
    #expect(player.currentTime().seconds == 6)
  }

  @Test func a_sample_is_aged_by_the_delay_between_the_threads() {
    let clock = Harness()
    defer { clock.restore() }
    let (player, receive) = makePlayer()
    player.play()
    receive(clock.report("timeupdate", time: 3, age: 0.3))
    #expect(abs(player.currentTime().seconds - 3.3) < 0.0001, "the host took it 300 ms ago")
    receive(clock.report("timeupdate", time: 3, age: 3600))
    #expect(abs(player.currentTime().seconds - 8) < 0.0001, "a clock that disagrees is believed up to 5 s only")
  }

  @Test func a_seek_holds_the_time_until_the_element_takes_it_and_completes_then() {
    let clock = Harness()
    defer { clock.restore() }
    let (player, receive) = makePlayer()
    player.play()
    receive(clock.report("playing", time: 1))
    clock.advance(1)
    let results = _Box<[String]>([])
    player.seek(to: .seconds(7)) { results.value.append("A:\($0)") }
    #expect(abs(player.currentTime().seconds - 2) < 0.0001, "AVPlayer keeps the old time until the seek lands")
    #expect(render(player).attributes["data-media-command"] == "1:seek:7.0")
    clock.advance(0.5)
    #expect(abs(player.currentTime().seconds - 2) < 0.0001)

    player.seek(to: .seconds(5)) { results.value.append("B:\($0)") }
    #expect(results.value == ["A:false"], "an interrupted seek finishes false, at once")
    receive(clock.report("seeked", time: 5, seek: 1))
    #expect(results.value == ["A:false"], "a stale seeked does not complete the newer seek")
    receive(clock.report("seeked", time: 5, seek: 2))
    #expect(results.value == ["A:false", "B:true"])
    #expect(abs(player.currentTime().seconds - 5) < 0.0001)
    clock.advance(1)
    #expect(abs(player.currentTime().seconds - 6) < 0.0001, "playback goes on from the landing point")
  }

  @Test func periodic_observers_follow_the_interval_of_media_time() {
    let clock = Harness()
    defer { clock.restore() }
    let (player, receive) = makePlayer()
    let ticks = _Box<[Double]>([])
    let token = player.addPeriodicTimeObserver(forInterval: .seconds(0.5), queue: nil) { ticks.value.append($0.seconds) }
    #expect(render(player).attributes["data-media-observe"] == "500" || render(player).attributes["data-media-observe"] == nil)
    player.play()
    receive(clock.report("playing", time: 0))
    #expect(ticks.value == [0], "starting playback reaches the observer")
    clock.advance(2.01)
    #expect(ticks.value.count == 5)
    for (index, tick) in ticks.value.enumerated() { #expect(abs(tick - Double(index) * 0.5) < 0.01) }

    receive(clock.report("ratechange", time: 2.01, rate: 2))
    #expect(ticks.value.count == 6, "a rate change reaches the observer")
    let before = ticks.value.count
    clock.advance(1)
    #expect(ticks.value.count - before == 4, "at rate 2 an interval of media time passes every 250 ms")

    receive(clock.report("pause", time: 4.01, paused: true, rate: 2))
    #expect(ticks.value.count - before == 5, "a pause reaches the observer")
    clock.advance(5)
    #expect(ticks.value.count - before == 5, "nothing fires while paused")
    player.removeTimeObserver(token)
  }

  @Test func short_observers_ask_for_a_sample_stream() {
    let clock = Harness()
    defer { clock.restore() }
    let (player, _) = makePlayer()
    _ = clock
    #expect(render(player).attributes["data-media-observe"] == nil)
    let token = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: nil) { _ in }
    #expect(render(player).attributes["data-media-observe"] == "100")
    player.removeTimeObserver(token)
    #expect(render(player).attributes["data-media-observe"] == nil)
    let slow = player.addPeriodicTimeObserver(forInterval: .seconds(1), queue: nil) { _ in }
    #expect(render(player).attributes["data-media-observe"] == nil, "a slow observer is served by the mirror")
    player.removeTimeObserver(slow)
  }

  @Test func boundary_observers_fire_when_playback_passes_them() {
    let clock = Harness()
    defer { clock.restore() }
    let (player, receive) = makePlayer()
    let fired = _Box<[Double]>([])
    let token = player.addBoundaryTimeObserver(forTimes: [NSValue(time: .seconds(1.2)), NSValue(time: .seconds(3))], queue: nil) {
      fired.value.append(MainActor.assumeIsolated { clock.now })
    }
    player.play()
    receive(clock.report("playing", time: 0))
    clock.advance(1.0)
    #expect(fired.value.isEmpty)
    clock.advance(0.3)
    #expect(fired.value.count == 1 && abs(fired.value[0] - 101.2) < 0.01)
    clock.advance(2)
    #expect(fired.value.count == 2 && abs(fired.value[1] - 103) < 0.01)
    clock.advance(0.05)
    #expect(fired.value.count == 2, "a boundary fires once")
    // A seek past a boundary is a jump, not playback crossing it.
    player.seek(to: .seconds(0))
    receive(clock.report("seeked", time: 0, seek: 1))
    clock.advance(0.5)
    #expect(fired.value.count == 2)
    player.removeTimeObserver(token)
  }

  @Test func the_element_failing_surfaces_its_code() {
    let clock = Harness()
    defer { clock.restore() }
    let (player, receive) = makePlayer()
    receive("error|0|-1|1|0|1||1|0|0|0|4|0|\(clock.hostNow)|\(player._itemGeneration)")
    #expect(player.status == .failed)
    #expect((player.currentItem?.error as? AVMediaError)?.message == "The browser media element reported an error (MEDIA_ERR_SRC_NOT_SUPPORTED)")
    #expect(player.error != nil)
  }

  @Test func callbacks_run_where_assumeIsolated_holds() {
    let clock = Harness()
    defer { clock.restore() }
    let (player, receive) = makePlayer()
    let seen = _Box<[String]>([])
    let periodic = player.addPeriodicTimeObserver(forInterval: .seconds(0.5), queue: .main) { _ in
      MainActor.assumeIsolated { seen.value.append("periodic") }
    }
    let boundary = player.addBoundaryTimeObserver(forTimes: [NSValue(time: .seconds(0.2))], queue: nil) {
      MainActor.assumeIsolated { seen.value.append("boundary") }
    }
    player.play()
    receive(clock.report("playing", time: 0))
    clock.advance(0.6)
    player.seek(to: .seconds(3)) { _ in MainActor.assumeIsolated { seen.value.append("seek") } }
    receive(clock.report("seeked", time: 3, seek: 1))
    #expect(Set(seen.value) == ["periodic", "boundary", "seek"], "every kind of callback ran on the main actor: \(seen.value)")
    player.removeTimeObserver(periodic)
    player.removeTimeObserver(boundary)
  }

  @Test func a_player_nobody_holds_is_released_with_its_observers() {
    let clock = Harness()
    defer { clock.restore() }
    weak var released: AVPlayer?
    do {
      let player = AVPlayer(url: URL(string: "https://media.example/movie.mp4")!)
      released = player
      player.addPeriodicTimeObserver(forInterval: .seconds(0.5), queue: nil) { _ in }
      let handler = render(player).events["media-report"]
      player.play()
      handler?.valueAction?(clock.report("playing", time: 0).replacingOccurrences(of: "|G", with: "|\(player._itemGeneration)"))
      #expect(!clock.timers.isEmpty, "the observer's timer is armed")
    }
    #expect(released == nil, "the observer's timer does not keep the player alive, as with AVFoundation")
    clock.advance(2)
  }

  @Test func a_player_with_an_item_publishes_the_wish_of_a_hidden_element() {
    let clock = Harness()
    defer { clock.restore() }
    let wasAvailable = _HeadlessMedia.isAvailable
    _HeadlessMedia.isAvailable = true
    defer { _HeadlessMedia.isAvailable = wasAvailable }
    let audio = AVPlayer(url: URL(string: "https://media.example/book.mp3")!)
    let video = AVPlayer(url: URL(string: "https://media.example/clip.mp4")!)
    audio.play()
    let json = _HeadlessMedia.wishes()
    #expect(json.contains("\"id\":\"\(audio.mediaID)\",\"kind\":\"audio\""))
    #expect(json.contains("\"id\":\"\(video.mediaID)\",\"kind\":\"video\""))
    #expect(json.contains("\"data-media-playing\":\"1\""))
    #expect(json.contains("\"src\":\"https://media.example/clip.mp4\""))
    audio.replaceCurrentItem(with: nil)
    // The whole id field: another test's player can have an id that starts with this one ("media-a3" after "media-a").
    #expect(!_HeadlessMedia.wishes().contains("\"id\":\"\(audio.mediaID)\""))
    _ = video
  }

  /// A report names the play intent the host had applied; one taken under an older intent than the player's newest does not
  /// change what the player wants (section 12.27): the browser queues a `pause` event, and a play asked after it must not be undone.
  @Test func a_pause_report_taken_before_a_newer_play_does_not_undo_it() {
    let clock = Harness()
    defer { clock.restore() }
    let (player, _) = makePlayer()
    let node = render(player)
    let receive = node.events["media-report"]?.valueAction
    player.play()
    let played = node.attributes["data-media-intent"]
    receive?(clock.report("playing", time: 1).replacingOccurrences(of: "|G", with: "|\(player._itemGeneration)|\(played ?? "")"))
    #expect(player.timeControlStatus == .playing)
    // The host paused the element for the pause, then the player asks to play again before the `pause` event is delivered.
    player.pause()
    player.play()
    let newest = render(player).attributes["data-media-intent"] ?? ""
    #expect(newest != played)
    receive?("pause|1|10|1|0|1||1|4|0|0|0|0|0|\(player._itemGeneration)|\(played ?? "")")
    #expect(player.isPlaying == true, "a pause taken under the older intent is stale")
    #expect(player.timeControlStatus == .waitingToPlayAtSpecifiedRate || player.timeControlStatus == .playing)
    // The element takes the newest intent and reports it: the wish is what it reports.
    receive?("playing|1|10|0|0|1||1|4|0|0|0|0|0|\(player._itemGeneration)|\(newest)")
    #expect(player.isPlaying == true)
    receive?("pause|1|10|1|0|1||1|4|0|0|0|0|0|\(player._itemGeneration)|\(newest)")
    #expect(player.isPlaying == false, "a pause under the newest intent is the player's")
  }

  /// A `volumechange` the element sends for an older mute does not undo a newer unmute, however late it arrives (section 12.27):
  /// the report names the request it was taken under, not a time window.
  @Test func a_volume_report_taken_before_a_newer_mute_does_not_undo_it() {
    let (player, _) = makePlayer()
    player.isMuted = true
    let older = render(player).attributes["data-media-intent"] ?? ""
    player.isMuted = false
    let receive = render(player).events["media-report"]?.valueAction
    let gen = player._itemGeneration
    receive?("volumechange|1|10|0|1|1||1|4|0|0|0|0|0|\(gen)|\(older)")
    #expect(player.isMuted == false, "an answer to the older mute does not mute the player again")
    let newest = render(player).attributes["data-media-intent"] ?? ""
    receive?("volumechange|1|10|0|1|1||1|4|0|0|0|0|0|\(gen)|\(newest)")
    #expect(player.isMuted == true, "an answer to the newest request is the element's")
  }

  @Test func an_element_that_ended_is_not_extrapolated() {
    let clock = Harness()
    defer { clock.restore() }
    let (player, receive) = makePlayer()
    player.play()
    receive(clock.report("playing", time: 9))
    receive(clock.report("ended", time: 10, paused: true, ended: true))
    clock.advance(2)
    #expect(player.currentTime().seconds == 10)
    #expect(player.timeControlStatus == .paused)
    #expect(player.rate == 0)
  }
}

private final class _Box<Value>: @unchecked Sendable {
  var value: Value
  init(_ value: Value) { self.value = value }
}

@Suite
@MainActor
struct AVFoundationItemGenerationTests {
  @Test func samples_of_a_replaced_item_are_ignored() {
    let player = AVPlayer(url: URL(string: "https://media.example/a.mp4")!)
    let stale = player._itemGeneration
    player.replaceCurrentItem(with: AVPlayerItem(url: URL(string: "https://media.example/b.mp4")!))
    let node = VideoPlayer(player: player, showsPlaybackControls: false)._render(in: _RenderContext())
    #expect(node.attributes["data-media-item"] == String(player._itemGeneration))
    node.events["media-report"]?.valueAction?("timeupdate|6|6|1|0|1||1|4|0|1|0|0|0|\(stale)")
    #expect(player.currentTime().seconds == 0, "the old item's last sample does not move the new one")
    node.events["media-report"]?.valueAction?("timeupdate|1|6|1|0|1||1|4|0|0|0|0|0|\(player._itemGeneration)")
    #expect(player.currentTime().seconds == 1)
  }
}
