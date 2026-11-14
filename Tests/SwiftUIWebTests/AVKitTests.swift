import Foundation
import Testing
import SwiftUIWeb
import SwiftUIWebAVFoundation
import SwiftUIWebAVKit

@Suite
@MainActor
final class AVKitTests {
  private func makePlayer() -> AVPlayer {
    AVPlayer(url: URL(string: "https://example.com/movie.mp4")!)
  }

  @Test
  func testVideoPlayerComposesAccessibleResponsiveMediaSurface() {
    let player = makePlayer()
    let track = CaptionTrack(
      url: URL(string: "https://example.com/captions.vtt")!,
      languageCode: "en",
      label: "English",
      kind: .captions,
      isDefault: true
    )
    let html = StaticHTMLFiberRenderer().render(
      VideoPlayer(
        player: player,
        videoGravity: .resizeAspectFill,
        captionTracks: [track],
        accessibilityLabel: "Demo movie"
      )
    )

    _expectTrue(html.contains("avkit-video-player"))
    _expectTrue(html.contains("aria-label=\"Demo movie\""))
    _expectTrue(html.contains("data-avkit-keyboard-controls=\"true\""))
    _expectTrue(html.contains("aria-keyshortcuts=\"Space K ArrowLeft ArrowRight ArrowUp ArrowDown M F P\""))
    _expectTrue(html.contains("object-fit: cover;"))
    _expectTrue(html.contains("<track"))
    _expectTrue(html.contains("captions.vtt"))
    _expectTrue(html.contains("aria-label=\"Enter Full Screen\""))
    _expectTrue(html.contains("aria-label=\"Enter Picture in Picture\""))
  }

  @Test
  func testPresentationRequestsAreSafeBeforeMount() {
    let player = makePlayer()
    player.requestFullscreen()
    player.startPictureInPicture()
    player.stopPictureInPicture()
    _expectFalse(player.isPictureInPictureActive)
  }

  @Test
  func testOverlayUsesOrdinarySwiftUIView() {
    let html = StaticHTMLFiberRenderer().render(
      VideoPlayer(player: makePlayer()) {
        Text("Overlay watermark")
      }
    )
    _expectTrue(html.contains("avkit-overlay"))
    _expectTrue(html.contains("Overlay watermark"))
  }

  @Test
  func testAccessibilityLabelNamesTheMediaElementAndItsContainer() {
    let html = StaticHTMLFiberRenderer().render(
      VideoPlayer(player: makePlayer()).accessibilityLabel("Trailer")
    )
    _expectFalse(html.contains("aria-label=\"Video player\""), "The modifier replaces the default label")
    #expect(html.components(separatedBy: "aria-label=\"Trailer\"").count - 1 == 2, "Container and <video> both carry the label")
    _expectTrue(html.contains("data-label-follows=\"true\""))
  }

  @Test
  func testPlaybackControlsCanBeHiddenWithoutChangingPlayer() {
    let player = makePlayer()
    let html = StaticHTMLFiberRenderer().render(
      VideoPlayer(player: player, controlsVisibility: .hidden, fullscreenBehavior: .disabled, pictureInPictureBehavior: .disabled)
    )
    _expectTrue(html.contains("avkit-video-player"))
    _expectFalse(html.contains("<video controls"))
    _expectFalse(html.contains("data-avkit-fullscreen=\"true\""))
    _expectFalse(html.contains("data-avkit-picture-in-picture=\"true\""))
    _expectFalse(html.contains("avkit-controls"), "No controls are drawn when they are hidden")
    _expectFalse(html.contains("avkit-action"))
  }

  @Test
  func testDefaultInitializerUsesAccessibleAutomaticConfiguration() {
    let player = makePlayer()
    let view = VideoPlayer(player: player)
    _expectTrue(view.player === player)
    _expectEqual(view.videoGravity, .resizeAspect)
    _expectEqual(view.controlsVisibility, .visible)
    _expectTrue(view.showsPlaybackControls)
    _expectEqual(view.fullscreenBehavior, .automatic)
    _expectEqual(view.pictureInPictureBehavior, .automatic)
    _expectTrue(view.captionTracks.isEmpty)
    _expectEqual(view.accessibilityLabel, "Video player")

    let html = StaticHTMLFiberRenderer().render(view)
    _expectTrue(html.contains("object-fit: contain;"))
    _expectTrue(html.contains("aria-label=\"Video player\""))
    _expectTrue(html.contains("avkit-controls"))
    _expectFalse(html.contains("<video controls") || html.contains(" controls=\"\""), "The media element carries no native controls attribute")
    _expectFalse(html.contains("<track"))
  }

  @Test
  func testShowsPlaybackControlsSpellingMapsToControlsVisibility() {
    let hidden = VideoPlayer(player: makePlayer(), showsPlaybackControls: false, videoGravity: .resize)
    _expectEqual(hidden.controlsVisibility, .hidden)
    _expectFalse(hidden.showsPlaybackControls)
    _expectEqual(hidden.videoGravity, .resize)
    _expectTrue(StaticHTMLFiberRenderer().render(hidden).contains("object-fit: fill;"))

    let visible = VideoPlayer(player: makePlayer(), showsPlaybackControls: true, accessibilityLabel: "Trailer")
    _expectEqual(visible.controlsVisibility, .visible)
    _expectTrue(visible.showsPlaybackControls)
    _expectEqual(visible.accessibilityLabel, "Trailer")
  }

  @Test
  func testOptionalPlayerSpellingsDrawAnIdleSurface() {
    let idle = VideoPlayer(player: nil)
    _expectEqual(idle.controlsVisibility, .visible)
    _expectTrue(StaticHTMLFiberRenderer().render(idle).contains("avkit-video-player"))

    let player = makePlayer()
    let provided = VideoPlayer(player: Optional(player))
    _expectTrue(provided.player === player)

    let overlaid = StaticHTMLFiberRenderer().render(
      VideoPlayer(player: nil) { Text("Idle overlay") }
    )
    _expectTrue(overlaid.contains("avkit-overlay"))
    _expectTrue(overlaid.contains("Idle overlay"))
  }

  @Test
  func testEmptyOverlayIsNotEmitted() {
    let html = StaticHTMLFiberRenderer().render(
      VideoPlayer(player: makePlayer()) { EmptyView() }
    )
    _expectTrue(html.contains("avkit-video-player"))
    _expectFalse(html.contains("avkit-overlay"))
  }

  @Test
  func testEachPresentationAffordanceCanBeDisabledIndependently() {
    let fullscreenOnly = StaticHTMLFiberRenderer().render(
      VideoPlayer(player: makePlayer(), pictureInPictureBehavior: .disabled)
    )
    _expectTrue(fullscreenOnly.contains("Enter Full Screen"))
    _expectFalse(fullscreenOnly.contains("Picture in Picture"))
    _expectTrue(fullscreenOnly.contains("data-avkit-fullscreen=\"true\""))
    _expectTrue(fullscreenOnly.contains("data-avkit-picture-in-picture=\"false\""))

    let pictureInPictureOnly = StaticHTMLFiberRenderer().render(
      VideoPlayer(player: makePlayer(), fullscreenBehavior: .disabled)
    )
    _expectFalse(pictureInPictureOnly.contains("Enter Full Screen"))
    _expectTrue(pictureInPictureOnly.contains("title=\"Enter Picture in Picture\""))
    _expectTrue(pictureInPictureOnly.contains("data-avkit-fullscreen=\"false\""))
  }

  @Test
  func testControlsEventDrivesThePlayerBeforeMount() {
    let player = makePlayer()
    let root = VideoPlayer(player: player)._render(in: _RenderContext())
    guard let handler = root.events["avkit-action"], let act = handler.valueAction else {
      _expectTrue(false, "The player wraps the controls' one event")
      return
    }
    act("play")
    _expectEqual(player.timeControlStatus, .playing, "Without an element the request takes effect at once")
    act("pause")
    _expectEqual(player.timeControlStatus, .paused)
    act("toggle")
    _expectNotEqual(player.timeControlStatus, .paused)
    act("pause")
    act("mute|1")
    _expectTrue(player.isMuted)
    // A toggle is decided by the player's newest wish, so two toggles in a row end where they began (section 12.27).
    act("mute|toggle")
    _expectFalse(player.isMuted)
    act("mute|toggle")
    _expectTrue(player.isMuted, "Two toggles in a row end where they began")
    act("mute|toggle")
    _expectFalse(player.isMuted)
    act("volume|0.25")
    _expectEqual(player.volume, 0.25)
    _expectFalse(player.isMuted, "Raising the volume of a muted player sounds it")
    act("rate|1.5")
    _expectEqual(player.defaultRate, 1.5, "A paused player keeps the speed for its next play()")
    _expectEqual(player.rate, 0)
    act("seek|42")
    _expectEqual(player.currentTime().seconds, 42)
    act("skip|-10")
    _expectEqual(player.currentTime().seconds, 32)
    act("skip|-100")
    _expectEqual(player.currentTime().seconds, 0, "A skip does not go before the start")
    act("nonsense|1")
    act("seek|abc")
    _expectEqual(player.currentTime().seconds, 0)
    // Fullscreen and Picture in Picture belong to the host: the controls ask for them in the page, not through Swift.
    player.requestFullscreen()
    player.startPictureInPicture()
    player.stopPictureInPicture()
  }

  @Test
  func testControlsAreFrameworkDOMWithStableClassesAndNoNativeControls() {
    let html = StaticHTMLFiberRenderer().render(VideoPlayer(player: makePlayer()))
    for name in ["avkit-controls", "avkit-bar", "avkit-transport", "avkit-play-pause",
                 "avkit-scrubber", "avkit-mute", "avkit-volume", "avkit-speed",
                 "avkit-pip", "avkit-fullscreen", "avkit-elapsed", "avkit-remaining"] {
      _expectTrue(html.contains(name), "\(name) is drawn")
    }
    _expectTrue(html.contains("role=\"slider\""))
    _expectTrue(html.contains("aria-label=\"Seek\""))
    _expectTrue(html.contains("aria-label=\"Play\""))
    _expectTrue(html.contains("aria-haspopup=\"menu\""))
    _expectTrue(html.contains("role=\"menuitemradio\""))
    _expectFalse(html.contains("controls=\"\""))
    _expectFalse(html.contains("<video controls"))
    // Without a duration (nothing loaded) there is nothing to skip: the buttons are not drawn, the scrubber is disabled.
    _expectFalse(html.contains("avkit-skip-back"))
    _expectTrue(html.contains("aria-disabled=\"true\""))
  }

  @Test
  func testOverlayIsBelowTheControls() {
    let root = VideoPlayer(player: makePlayer()) { Text("Watermark") }._render(in: _RenderContext())
    let classes = root.children.map { $0.classes.first ?? "" }
    _expectEqual(classes.count, 3)
    _expectTrue(root.children[0].classes.contains("avkit-media"))
    _expectTrue(root.children[1].classes.contains("avkit-overlay"), "The app's overlay sits over the video")
    _expectTrue(root.children[2].classes.contains("avkit-controls"), "and under the controls, as on Apple")
  }

  @Test
  func testControlsModelFollowsThePlayerState() {
    var model = AVKitControlsModel()
    _expectEqual(model.transport, .play)
    _expectEqual(model.state, "paused")
    model.transport = .pause
    _expectEqual(model.state, "playing")
    model.isBuffering = true
    _expectEqual(model.state, "buffering")
    model.hasFailed = true
    _expectEqual(model.state, "failed", "A failure wins over buffering")
    model = AVKitControlsModel(transport: .replay)
    _expectEqual(model.state, "ended")

    model = AVKitControlsModel(canSeek: true, currentTime: 30, duration: 120)
    _expectEqual(model.progress, 0.25)
    model.currentTime = 500
    _expectEqual(model.progress, 1, "The position never leaves the track")
    _expectEqual(AVKitControlsModel(currentTime: 30, duration: 0).progress, 0, "Without a duration there is no progress")

    _expectEqual(AVKitControlsModel(volume: 1).volumeGlyph, .high)
    _expectEqual(AVKitControlsModel(volume: 0.3).volumeGlyph, .low)
    _expectEqual(AVKitControlsModel(volume: 0).volumeGlyph, .muted)
    _expectEqual(AVKitControlsModel(volume: 1, isMuted: true).volumeGlyph, .muted)
  }

  @Test
  func testControlsModelReadsAPlayer() {
    let player = makePlayer()
    var model = AVKitControlsModel(player: player)
    _expectEqual(model.transport, .play)
    _expectFalse(model.canSeek)
    _expectEqual(model.speed, 1)
    player.play()
    model = AVKitControlsModel(player: player)
    _expectEqual(model.transport, .pause, "Asked to play, the control offers to pause")
    _expectFalse(model.isBuffering, "No element is waiting on data here")
    player.pause()
    player.isMuted = true
    player.defaultRate = 1.5
    model = AVKitControlsModel(player: player)
    _expectEqual(model.transport, .play)
    _expectTrue(model.isMuted)
    _expectEqual(model.speed, 1.5)
    let html = StaticHTMLFiberRenderer().render(VideoPlayer(player: player))
    _expectTrue(html.contains("aria-label=\"Unmute\""))
    _expectTrue(html.contains("aria-label=\"Playback Speed, 1.5x\""))
  }

  @Test
  func testControlTimesAreFormattedAndSpokenAsAVKitDoes() {
    _expectEqual(AVKitTimeFormat.clock(0), "0:00")
    _expectEqual(AVKitTimeFormat.clock(5.9), "0:05")
    _expectEqual(AVKitTimeFormat.clock(65), "1:05")
    _expectEqual(AVKitTimeFormat.clock(3723), "1:02:03")
    _expectEqual(AVKitTimeFormat.clock(.nan), "0:00")
    _expectEqual(AVKitTimeFormat.clock(-4), "0:00")
    _expectEqual(AVKitTimeFormat.remaining(time: 5, duration: 65), "-1:00")
    _expectEqual(AVKitTimeFormat.remaining(time: 99, duration: 65), "-0:00")
    _expectEqual(AVKitTimeFormat.remaining(time: 5, duration: 0), "", "A live stream has no time left")
    _expectEqual(AVKitTimeFormat.spoken(0), "0 seconds")
    _expectEqual(AVKitTimeFormat.spoken(1), "1 second")
    _expectEqual(AVKitTimeFormat.spoken(65), "1 minute, 5 seconds")
    _expectEqual(AVKitTimeFormat.spoken(3600), "1 hour")
    _expectEqual(AVKitTimeFormat.spoken(7262), "2 hours, 1 minute, 2 seconds")
    _expectEqual(AVKitTimeFormat.speed(1), "1x")
    _expectEqual(AVKitTimeFormat.speed(1.5), "1.5x")
    _expectEqual(AVKitTimeFormat.speed(0.75), "0.75x")
    _expectEqual(AVKitTimeFormat.percent(0.5), "50.0%")
    _expectEqual(AVKitTimeFormat.percent(2), "100.0%")
    _expectEqual(AVKitTimeFormat.percent(.nan), "0.0%")
  }

  @Test
  func testSubtitleTrackDefaultsAreNotMarkedDefault() {
    let track = CaptionTrack(url: URL(string: "https://example.com/fr.vtt")!, languageCode: "fr", label: "Français")
    _expectEqual(track.kind, .subtitles)
    _expectFalse(track.isDefault)
    let html = StaticHTMLFiberRenderer().render(VideoPlayer(player: makePlayer(), captionTracks: [track]))
    _expectTrue(html.contains("kind=\"subtitles\""))
    _expectTrue(html.contains("srclang=\"fr\""))
    let defaultTrack = CaptionTrack(url: track.url, languageCode: "fr", label: "Français", isDefault: true)
    let defaultHTML = StaticHTMLFiberRenderer().render(VideoPlayer(player: makePlayer(), captionTracks: [defaultTrack]))
    func defaultMentions(_ html: String) -> Int { html.components(separatedBy: "default").count - 1 }
    _expectEqual(defaultMentions(defaultHTML), defaultMentions(html) + 1, "Only a default track carries the default attribute")
  }
}
