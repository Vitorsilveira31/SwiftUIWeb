import SwiftUIWeb
import SwiftUIWebAVFoundation

/// How the media frame fits its responsive container.
package enum VideoGravity: String, Hashable, Sendable {
  case resizeAspect = "contain"
  case resizeAspectFill = "cover"
  case resize = "fill"
}

/// Whether the AVKit-style controls (`AVKitControls.swift`) are drawn over the video. Apple's SwiftUI `VideoPlayer` has no
/// parameter or modifier for it, so this stays package-internal; an app that draws its own controls hides
/// `.avkit-controls` with CSS.
package enum VideoControlsVisibility: Hashable, Sendable {
  case visible
  case hidden

  var showsControls: Bool {
    switch self {
    case .visible: return true
    case .hidden: return false
    }
  }
}

package enum VideoPresentationBehavior: Hashable, Sendable {
  case automatic
  case disabled
}

package enum CaptionTrackKind: String, Hashable, Sendable {
  case subtitles
  case captions
}

/// A WebVTT (or browser-supported equivalent) text track. The source remains
/// a normal SwiftUIWeb URL; HTML track details are emitted only by the private
/// renderer.
package struct CaptionTrack: Hashable, Sendable {
  package let url: URL
  package let languageCode: String
  package let label: String
  package let kind: CaptionTrackKind
  package let isDefault: Bool

  package init(
    url: URL,
    languageCode: String,
    label: String,
    kind: CaptionTrackKind = .subtitles,
    isDefault: Bool = false
  ) {
    self.url = url
    self.languageCode = languageCode
    self.label = label
    self.kind = kind
    self.isDefault = isDefault
  }
}


/// SwiftUI-compatible video presentation backed by the AVFoundation-shaped
/// `AVPlayer`. Playback, buffering, adaptive streaming and lifecycle are all
/// delegated to `SwiftUIWebAVFoundation`; this type only contributes layout,
/// captions, accessibility and presentation affordances.
@MainActor @preconcurrency public struct VideoPlayer: View {
  public typealias Body = Never

  package let player: AVPlayer
  package let videoGravity: VideoGravity
  package let controlsVisibility: VideoControlsVisibility
  package let fullscreenBehavior: VideoPresentationBehavior
  package let pictureInPictureBehavior: VideoPresentationBehavior
  package let captionTracks: [CaptionTrack]
  package let accessibilityLabel: String

  /// Source-compatible spelling shared with the AVFoundation media view.
  package var showsPlaybackControls: Bool { controlsVisibility.showsControls }

  private let overlay: AnyView?

  package init(player: AVPlayer) {
    self.player = player
    self.videoGravity = .resizeAspect
    self.controlsVisibility = .visible
    self.fullscreenBehavior = .automatic
    self.pictureInPictureBehavior = .automatic
    self.captionTracks = []
    self.accessibilityLabel = "Video player"
    self.overlay = nil
  }

  package init(
    player: AVPlayer,
    videoGravity: VideoGravity = .resizeAspect,
    controlsVisibility: VideoControlsVisibility = .visible,
    fullscreenBehavior: VideoPresentationBehavior = .automatic,
    pictureInPictureBehavior: VideoPresentationBehavior = .automatic,
    captionTracks: [CaptionTrack] = [],
    accessibilityLabel: String = "Video player"
  ) {
    self.player = player
    self.videoGravity = videoGravity
    self.controlsVisibility = controlsVisibility
    self.fullscreenBehavior = fullscreenBehavior
    self.pictureInPictureBehavior = pictureInPictureBehavior
    self.captionTracks = captionTracks
    self.accessibilityLabel = accessibilityLabel
    self.overlay = nil
  }

  package init(
    player: AVPlayer,
    showsPlaybackControls: Bool,
    videoGravity: VideoGravity = .resizeAspect,
    fullscreenBehavior: VideoPresentationBehavior = .automatic,
    pictureInPictureBehavior: VideoPresentationBehavior = .automatic,
    captionTracks: [CaptionTrack] = [],
    accessibilityLabel: String = "Video player"
  ) {
    self.init(
      player: player,
      videoGravity: videoGravity,
      controlsVisibility: showsPlaybackControls ? .visible : .hidden,
      fullscreenBehavior: fullscreenBehavior,
      pictureInPictureBehavior: pictureInPictureBehavior,
      captionTracks: captionTracks,
      accessibilityLabel: accessibilityLabel
    )
  }

  /// Convenience spelling for applications that want an arbitrary SwiftUI
  /// overlay while retaining the same AVKit-shaped configuration.
  package init<Overlay: View>(
    player: AVPlayer,
    videoGravity: VideoGravity = .resizeAspect,
    controlsVisibility: VideoControlsVisibility = .visible,
    fullscreenBehavior: VideoPresentationBehavior = .automatic,
    pictureInPictureBehavior: VideoPresentationBehavior = .automatic,
    captionTracks: [CaptionTrack] = [],
    accessibilityLabel: String = "Video player",
    @ViewBuilder overlay: () -> Overlay
  ) {
    self.player = player
    self.videoGravity = videoGravity
    self.controlsVisibility = controlsVisibility
    self.fullscreenBehavior = fullscreenBehavior
    self.pictureInPictureBehavior = pictureInPictureBehavior
    self.captionTracks = captionTracks
    self.accessibilityLabel = accessibilityLabel
    self.overlay = AnyView(overlay())
  }

  /// Apple's spelling: an optional player (none yet draws an idle video surface) and a `videoOverlay`.
  @MainActor @preconcurrency public init<Overlay: View>(player: AVPlayer?, @ViewBuilder videoOverlay: () -> Overlay) {
    self.init(player: player ?? AVPlayer(), overlay: videoOverlay)
  }

  @MainActor @preconcurrency public init(player: AVPlayer?) {
    self.init(player: player ?? AVPlayer())
  }

  private func renderCaptionTrack(_ track: CaptionTrack) -> _RenderNode {
    let node = _RenderNode.element("track")
    node.attributes["kind"] = track.kind.rawValue
    node.attributes["src"] = track.url.absoluteString
    node.attributes["srclang"] = track.languageCode
    node.attributes["label"] = track.label
    if track.isDefault { node.attributes["default"] = "" }
    return node
  }

  public func _render(in context: _RenderContext) -> _RenderNode {
    // The element is control-less: the controls below are DOM the framework draws (the browser's own live in a shadow DOM).
    let avFoundationPlayer = SwiftUIWebAVFoundation.VideoPlayer(player: player, showsPlaybackControls: false)
    let media = avFoundationPlayer._render(in: context.child(_FiberKey("media")))
    media.classes.append("avkit-media")
    media.styles["width"] = "100%"
    media.styles["height"] = "100%"
    media.styles["object-fit"] = videoGravity.rawValue
    media.attributes["aria-label"] = accessibilityLabel
    // Modifiers such as `.accessibilityLabel` retarget the wrapper; this flag makes them retarget the media element too.
    media.attributes["data-label-follows"] = "true"
    media.attributes["aria-roledescription"] = "video"
    media.children.append(contentsOf: captionTracks.map(renderCaptionTrack))

    let wrapper = _RenderNode.element("div")
    wrapper.classes = ["avkit-video-player", "avkit-responsive"]
    // Keyboard shortcuts work while the player (or anything in it) has focus.
    wrapper.attributes["role"] = "group"
    wrapper.attributes["tabindex"] = "0"
    wrapper.attributes["aria-label"] = accessibilityLabel
    wrapper.attributes["aria-roledescription"] = "video player"
    wrapper.styles["position"] = "relative"
    wrapper.styles["width"] = "100%"
    wrapper.styles["min-height"] = "1px"
    wrapper.styles["overflow"] = "hidden"
    wrapper.styles["background"] = "#000"
    wrapper.children = [media]

    if let overlay {
      let overlayNode = overlay._render(in: context.child(_FiberKey("overlay")))
      if !overlayNode.isEmpty {
        overlayNode.classes.append("avkit-overlay")
        // The overlay covers the video surface, as SwiftUI's `videoOverlay` does, and sits under the controls.
        overlayNode.styles["position"] = "absolute"
        overlayNode.styles["inset"] = "0"
        wrapper.children.append(overlayNode)
      }
    }
    if controlsVisibility.showsControls {
      var model = AVKitControlsModel(player: player)
      if let loaded = player.currentItem?.loadedTimeRanges.last { model.loadedTime = loaded.end.seconds }
      let controls = AVKitControlsRenderer(
        model: model,
        showsFullscreen: fullscreenBehavior == .automatic,
        showsPictureInPicture: pictureInPictureBehavior == .automatic,
        context: context.child(_FiberKey("controls"))
      ).render()
      wrapper.children.append(controls)
      let player = self.player
      wrapper.attributes["aria-keyshortcuts"] = "Space K ArrowLeft ArrowRight ArrowUp ArrowDown M F P"
      wrapper.attributes["data-avkit-keyboard-controls"] = "true"
      wrapper.attributes["data-avkit-fullscreen"] = fullscreenBehavior == .automatic ? "true" : "false"
      wrapper.attributes["data-avkit-picture-in-picture"] = pictureInPictureBehavior == .automatic ? "true" : "false"
      // One event carries what the viewer did with the controls (seek, skip, volume, speed, play, pause).
      wrapper.events["avkit-action"] = _EventHandler(name: "avkit-action", action: { value in
        AVKitControlsAction.perform(value, on: player)
      })
    }
    return wrapper
  }
}
