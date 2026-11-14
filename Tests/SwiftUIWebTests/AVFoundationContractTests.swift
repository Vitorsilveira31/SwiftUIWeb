import Foundation
import Testing
import SwiftUIWeb
@testable import SwiftUIWebAVFoundation
@_spi(WebMount) import SwiftUIWebBrowser

private final class TestMediaBackend: _MediaBackend {
  var currentTime = 4.0
  var duration = 60.0
  var rate = 1.0
  var playbackRate: Double { rate }
  var volume = 0.5
  var muted = false
  var bufferedRanges = [WebMediaTimeRange(start: 5, end: 20)]
  var seekableRanges = [WebMediaTimeRange(start: 0, end: 60)]
  var isPlaying = false
  var supportsPictureInPicture = true
  var isPictureInPictureActive = false
  var isAdvancing: Bool { isPlaying }
  var reportsPlayback = false
  var errorCode = 0
  var holdsTime = false
  var intent: UInt64 = 0

  func reset() { currentTime = 0 }
  func play() { intent &+= 1; isPlaying = true }
  func pause() { intent &+= 1; isPlaying = false }
  func seek(to seconds: Double) -> Bool { currentTime = max(0, seconds); return false }
  func setPictureInPicture(_ enabled: Bool) { isPictureInPictureActive = enabled }
  func apply(_ report: _MediaHostReport) { currentTime = report.currentTime }
}

@Suite
@MainActor
struct AVFoundationContractTests {
  @Test
  func timeValuesHandleInvalidInfinityComparisonsAndScaleNormalization() {
    let invalid = CMTime.seconds(.nan)
    let positiveInfinity = CMTime.seconds(.infinity)
    let negativeInfinity = CMTime.seconds(-.infinity)
    let finite = CMTime.seconds(2.5, preferredTimescale: -100)
    let zeroScale = CMTime.seconds(3, preferredTimescale: 0)

    _expectFalse(invalid.isValid)
    _expectFalse(invalid.isNumeric)
    _expectTrue(invalid.seconds.isNaN)
    _expectTrue(positiveInfinity.isPositiveInfinity)
    _expectTrue(positiveInfinity.seconds.isInfinite)
    _expectTrue(negativeInfinity.isNegativeInfinity)
    _expectTrue(negativeInfinity.seconds < 0)
    _expectEqual(finite.timescale, 100)
    _expectEqual(finite.seconds, 2.5, accuracy: 0.0001)
    _expectEqual(zeroScale.timescale, 600)
    _expectEqual(zeroScale.seconds, 3, accuracy: 0.0001)
    _expectTrue(invalid < finite)
    _expectFalse(finite < invalid)
    _expectTrue(negativeInfinity < finite)
    _expectTrue(positiveInfinity > finite)
    _expectFalse(CMTime.indefinite.isNumeric)
    _expectTrue(CMTime.indefinite.seconds.isNaN)

    _expectFalse((invalid + finite).isValid)
    _expectFalse((finite - positiveInfinity).isValid)
    _expectEqual((CMTime.seconds(1) + CMTime.seconds(2)).seconds, 3, accuracy: 0.0001)
    _expectEqual((CMTime.seconds(4) - CMTime.seconds(1.5)).seconds, 2.5, accuracy: 0.0001)
  }

  @Test
  func timeRangesCoverHalfOpenContainmentAndInvalidIntersections() {
    let range = CMTimeRange(start: .seconds(10), end: .seconds(20))
    _expectTrue(range.isValid)
    _expectFalse(range.isEmpty)
    _expectEqual(range.duration.seconds, 10, accuracy: 0.0001)
    _expectTrue(range.containsTime(.seconds(10)))
    _expectTrue(range.containsTime(.seconds(19.99)))
    _expectFalse(range.containsTime(.seconds(20)))
    _expectFalse(range.containsTime(.seconds(.infinity)))

    let overlap = range.intersection(CMTimeRange(start: .seconds(15), duration: .seconds(12)))
    _expectEqual(overlap.start.seconds, 15, accuracy: 0.0001)
    _expectEqual(overlap.end.seconds, 20, accuracy: 0.0001)
    _expectTrue(CMTimeRange(start: .seconds(4), duration: .zero).isEmpty)
    _expectEqual(range.intersection(CMTimeRange(start: .seconds(20), duration: .seconds(4))), .zero)
    _expectEqual(range.intersection(.invalid), .zero)
    _expectFalse(CMTimeRange.invalid.containsTime(.seconds(10)))
  }

  @Test
  func urlAssetsClassifyMediaAdaptiveSourcesAndMetadataFallbacks() {
    let audioExtensions = ["song.mp3", "song.m4a", "song.aac", "song.ogg", "song.wav"]
    for filename in audioExtensions {
      let asset = AVURLAsset(url: URL(string: "https://media.example/\(filename)")!)
      _expectEqual(asset.mediaType, .audio)
      _expectEqual(asset.commonMetadata.first?.stringValue, filename)
    }

    for filename in ["movie.mp4", "movie.webm", "movie.mov", "live.m3u8", "dash.mpd"] {
      let asset = AVURLAsset(url: URL(string: "https://media.example/\(filename)")!)
      _expectEqual(asset.mediaType, .video)
    }

    let unknown = AVURLAsset(url: URL(string: "https://media.example/no-extension")!)
    _expectEqual(unknown.mediaType, .unclassified)
    _expectEqual(unknown.commonMetadata.first?.stringValue, "no-extension")
    _expectFalse(unknown.requiresAdaptiveStreaming)

    let metadata = AVURLAsset(
      url: URL(string: "https://media.example/STREAM.MPD")!,
      options: ["title": "Episode", "artist": "Artist", "album": "Album", "drm": true]
    )
    #expect(metadata.requiresAdaptiveStreaming, "An .mpd URL should select adaptive streaming")
    _expectEqual(metadata.mediaType, .video)
    _expectEqual(metadata.commonMetadata.map(\.commonKey), ["title", "artist", "albumName"])
    _expectEqual(metadata.commonMetadata.map(\.stringValue), ["Episode", "Artist", "Album"])

    let adaptiveOption = AVURLAsset(
      url: URL(string: "https://media.example/file.bin")!,
      options: ["adaptive": true, "title": true]
    )
    #expect(adaptiveOption.requiresAdaptiveStreaming, "The adaptive option should accept Bool true")
    _expectEqual(adaptiveOption.commonMetadata.first?.stringValue, "true")

    let fallbackTitle = AVURLAsset(url: URL(string: "https://media.example/path/fallback.mp4?token=one")!)
    _expectEqual(fallbackTitle.commonMetadata.first?.stringValue, "fallback.mp4?token=one")
    let completed = _TestBox(false)
    fallbackTitle.loadValuesAsynchronously(forKeys: ["duration", "metadata"]) { completed.value = true }
    #expect(completed.value, "URL asset metadata completion is synchronous")
  }

  @Test
  func endAndFailureEventsPostTheItemNotifications() {
    let item = AVPlayerItem(asset: AVURLAsset(url: URL(string: "https://media.example/movie.mp4")!))
    let backend = TestMediaBackend()
    let ended = _TestBox(0)
    let failed = _TestBox(0)
    let center = NotificationCenter.default
    let endToken = center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: nil) { _ in
      ended.value += 1
    }
    let failToken = center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: nil) { _ in
      failed.value += 1
    }
    defer {
      center.removeObserver(endToken)
      center.removeObserver(failToken)
    }

    item._handle(event: .playing, backend: backend)
    _expectEqual(ended.value + failed.value, 0, "playing posts neither notification")
    item._handle(event: .ended, backend: backend)
    _expectEqual(ended.value, 1)
    _expectEqual(failed.value, 0)
    item._handle(event: .error, backend: backend)
    _expectEqual(failed.value, 1)
    _expectEqual(AVPlayerItemFailedToPlayToEndTimeErrorKey, "error")
    _expectEqual(AVPlayerItem.didPlayToEndTimeNotification.rawValue, "AVPlayerItemDidPlayToEndTimeNotification")
  }

  @Test
  func itemEventsUpdateDurationBufferingRangesAndFailureState() {
    let urlAsset = AVURLAsset(url: URL(string: "https://media.example/movie.mp4")!)
    let item = AVPlayerItem(asset: urlAsset)
    let backend = TestMediaBackend()

    item._handle(event: .loadedMetadata, backend: backend)
    _expectEqual(item.status, .readyToPlay)
    _expectEqual(item.bufferingState, .empty)
    _expectEqual(item.duration.seconds, 60, accuracy: 0.0001)
    _expectEqual(urlAsset.duration.seconds, 60, accuracy: 0.0001)
    _expectEqual(item.currentTime.seconds, 4, accuracy: 0.0001)
    _expectEqual(item.loadedTimeRanges.first?.start.seconds ?? .nan, 5, accuracy: 0.0001)
    _expectEqual(item.seekableTimeRanges.first?.end.seconds ?? .nan, 60, accuracy: 0.0001)
    _expectTrue(item.isPlaybackBufferEmpty)
    _expectFalse(item.isPlaybackLikelyToKeepUp)

    item._handle(event: .canPlay, backend: backend)
    _expectTrue(item.isPlaybackLikelyToKeepUp)
    _expectFalse(item.isPlaybackBufferEmpty)
    item._handle(event: .waiting, backend: backend)
    _expectTrue(item.isPlaybackBufferEmpty)
    item._handle(event: .ended, backend: backend)
    _expectTrue(item.isPlaybackBufferFull)
    _expectTrue(item.isPlaybackLikelyToKeepUp)
    item._handle(event: .error, backend: backend)
    _expectEqual(item.status, .failed)
    _expectEqual((item.error as? AVMediaError)?.message, "The browser media element reported an error")
    _expectEqual(item.metadata, urlAsset.commonMetadata)
  }

  @Test
  func itemRejectsNonFiniteDurationAndHandlesTheRemainingNeutralEvents() {
    let asset = AVAsset(duration: .seconds(12))
    let item = AVPlayerItem(asset: asset)
    let backend = TestMediaBackend()
    backend.duration = .nan
    for event in [
      _MediaEventName.durationChange, .canPlayThrough, .playing, .progress,
      .stalled, .suspend, .emptied, .play, .pause, .timeUpdate, .rateChange,
      .volumeChange, .enterPictureInPicture, .leavePictureInPicture
    ] {
      item._handle(event: event, backend: backend)
    }
    _expectEqual(item.duration.seconds, 12, accuracy: 0.0001)
    _expectEqual(item.status, .readyToPlay)
    _expectTrue(item.isPlaybackBufferEmpty)
    #expect(item.error == nil)

    backend.duration = .infinity
    item._handle(event: .durationChange, backend: backend)
    _expectEqual(item.duration.seconds, 12, accuracy: 0.0001)
  }

  @Test
  func playerClampsControlsHandlesMissingItemsAndThrottlesObservers() {
    let player = AVPlayer()
    player.play()
    _expectFalse(player.isPlaying)
    _expectEqual(player.timeControlStatus, .paused)

    player.rate = -2
    _expectEqual(player.rate, 0, accuracy: 0.001)
    player.volume = -1
    _expectEqual(player.volume, 0, accuracy: 0.001)
    player.volume = 2
    _expectEqual(player.volume, 1, accuracy: 0.001)
    player.startPictureInPicture()
    _expectFalse(player.isPictureInPictureSupported)
    _expectFalse(player.isPictureInPictureActive)
    player.stopPictureInPicture()

    player.replaceCurrentItem(with: AVPlayerItem(url: URL(string: "https://media.example/movie.mp4")!))
    player.play()
    _expectTrue(player.isPlaying)
    _expectEqual(player.timeControlStatus, .playing, "without an element the backend is the truth")
    player.rate = 1.5
    _expectEqual(player.rate, 1.5, accuracy: 0.001)

    let ticks = _TestBox<[Double]>([])
    let observer = player.addPeriodicTimeObserver(forInterval: .seconds(5), queue: nil) { ticks.value.append($0.seconds) }
    let completed = _TestBox<Bool?>(nil)
    player.seek(to: .seconds(3), toleranceBefore: .seconds(1), toleranceAfter: .seconds(2)) { completed.value = $0 }
    player.seek(to: .seconds(4))
    player.seek(to: .seconds(8))
    _expectEqual(completed.value, true)
    _expectEqual(ticks.value, [3, 4, 8], "every seek reaches the observers")
    _expectEqual(player.currentTime().seconds, 8, accuracy: 0.0001)
    player.removeTimeObserver(observer)
    player.seek(to: .seconds(20))
    _expectEqual(ticks.value, [3, 4, 8])

    player.pause()
    _expectFalse(player.isPlaying)
    _expectEqual(player.timeControlStatus, .paused)
    player.replaceCurrentItem(with: nil)
    player.playImmediately(atRate: 2)
    _expectEqual(player.timeControlStatus, .paused)
    _expectNil(player.currentItem)
  }

  @Test
  func inMemoryBackendClampsStateAndViewControlsCanBeHidden() {
    let backend = _InMemoryMediaBackend()
    backend.currentTime = -4
    backend.rate = -1
    backend.volume = 3
    _expectEqual(backend.currentTime, 0)
    _expectEqual(backend.rate, 0)
    _expectEqual(backend.volume, 1)
    backend.play()
    _expectTrue(backend.isPlaying)
    backend.seek(to: 7)
    _expectEqual(backend.currentTime, 7)
    backend.pause()
    _expectFalse(backend.isPlaying)
    _expectTrue(_makeMediaBackend() is _InMemoryMediaBackend)

    let player = AVPlayer()
    let video = VideoPlayer(player: player, showsPlaybackControls: false)._render(in: _RenderContext())
    _expectEqual(video.kind.displayName, "video")
    _expectNil(video.attributes["controls"])
    _expectEqual(video.attributes["aria-label"], "Video player")

    let audio = AudioPlayer(player: player, showsPlaybackControls: false)._render(in: _RenderContext())
    _expectEqual(audio.kind.displayName, "audio")
    _expectNil(audio.attributes["controls"])
    _expectEqual(audio.attributes["aria-label"], "Audio player")
  }
}

/// A reference box for values that Sendable callbacks in these tests write.
private final class _TestBox<Value>: @unchecked Sendable {
  var value: Value
  init(_ value: Value) { self.value = value }
}
