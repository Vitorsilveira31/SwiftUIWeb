import SwiftUIWeb
import SwiftUIWebAVFoundation

// AVKit-style playback controls for `VideoPlayer`.
//
// The browser's own `<video controls>` is not Apple's chrome, and in WebKit it lives in a shadow DOM that app CSS cannot reach.
// `VideoPlayer` therefore renders a control-less media element and draws these controls over it as ordinary DOM
// (`.avkit-controls`, which an app's CSS can restyle or hide).
//
// The split follows the project's layers:
// - Swift (this file) decides what is shown from the player's state: the play/pause/replay glyph, whether the player is
//   buffering or failed, whether it can seek or skip, the speed, the mute glyph, Picture in Picture, and every label and ARIA
//   attribute. The state comes from the player's mirror.
// - The host (`Tools/media-host.js`, `AVKitControlsHost`) handles what only the page can: pointer capture while
//   dragging the scrubber, the auto-hide timer, keyboard shortcuts, fullscreen and Picture in Picture requests (which need the
//   user's gesture), and the continuous values (elapsed and remaining time, the scrubber's position). Those nodes carry
//   `data-host-managed`, which tells the DOM patcher that the host owns them. Every action that changes the player goes back to
//   Swift as one `avkit-action` event (`"<verb>|<argument>"`), so `seek(to:)`, `volume`, `isMuted` and `defaultRate` stay the
//   source of truth.

/// A control-bar menu that picks one option of a selection group (subtitles, alternate audio): what it lists and which
/// option is checked. Built from the item's `AVMediaSelectionGroup`, so the menu and `AVPlayerItem.select(_:in:)` agree.
package struct AVKitSelectionMenu: Equatable, Sendable {
  package struct Entry: Equatable, Sendable {
    /// What the host sends back: `off` for subtitles turned off, otherwise the option's identifier.
    package let id: String
    package let label: String
    package let isChecked: Bool

    package init(id: String, label: String, isChecked: Bool) {
      self.id = id
      self.label = label
      self.isChecked = isChecked
    }
  }

  package var entries: [Entry]

  package init(entries: [Entry]) {
    self.entries = entries
  }

  /// The checked option's label: what the menu's button names (`Off`, `English`).
  package var checkedLabel: String {
    entries.first(where: { $0.isChecked })?.label ?? ""
  }
}

/// What the controls draw for a player's state. Pure value: the native tests drive it without a browser.
package struct AVKitControlsModel: Equatable, Sendable {
  package enum Transport: String, Sendable {
    case play
    case pause
    case replay
  }

  package enum VolumeGlyph: String, Sendable {
    case muted
    case low
    case high
  }

  package var transport: Transport
  /// Playback was asked for and the element has not started (or ran out of data): a spinner replaces the centre button.
  package var isBuffering: Bool
  package var hasFailed: Bool
  /// The duration is known: the scrubber moves and the skip buttons work. A live stream has none.
  package var canSeek: Bool
  package var currentTime: Double
  package var duration: Double
  package var loadedTime: Double
  package var volume: Double
  package var isMuted: Bool
  package var speed: Double
  package var isPictureInPictureActive: Bool
  /// The subtitles menu: present when the item has legible options (a `<track>`, a subtitle track of an HLS stream).
  package var captions: AVKitSelectionMenu?
  /// The audio menu: present when the item has alternate audio (HLS renditions); a plain file has none.
  package var audio: AVKitSelectionMenu?

  package init(
    transport: Transport = .play,
    isBuffering: Bool = false,
    hasFailed: Bool = false,
    canSeek: Bool = false,
    currentTime: Double = 0,
    duration: Double = 0,
    loadedTime: Double = 0,
    volume: Double = 1,
    isMuted: Bool = false,
    speed: Double = 1,
    isPictureInPictureActive: Bool = false,
    captions: AVKitSelectionMenu? = nil,
    audio: AVKitSelectionMenu? = nil
  ) {
    self.transport = transport
    self.isBuffering = isBuffering
    self.hasFailed = hasFailed
    self.canSeek = canSeek
    self.currentTime = currentTime
    self.duration = duration
    self.loadedTime = loadedTime
    self.volume = volume
    self.isMuted = isMuted
    self.speed = speed
    self.isPictureInPictureActive = isPictureInPictureActive
    self.captions = captions
    self.audio = audio
  }

  @MainActor package init(player: AVPlayer) {
    let failed = player.status == .failed || player.currentItem?.status == .failed
    let seconds = player.currentTime().seconds
    let canSeek = player._hasPlayableDuration
    let total = canSeek ? (player.currentItem?.duration.seconds ?? 0) : 0
    let time = seconds.isFinite ? max(0, seconds) : 0
    let atEnd = player._isAtEnd
    let transport: Transport
    if atEnd {
      transport = .replay
    } else if player.timeControlStatus == .paused {
      transport = .play
    } else {
      transport = .pause
    }
    self.init(
      transport: transport,
      isBuffering: !failed && player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
      hasFailed: failed,
      canSeek: canSeek && total.isFinite && total > 0,
      currentTime: canSeek ? min(time, total) : time,
      duration: total.isFinite ? total : 0,
      loadedTime: 0,
      volume: Double(player.volume),
      isMuted: player.isMuted,
      // While it plays the player's rate is the speed; paused, the speed the next `play()` starts at.
      speed: Double(player.rate != 0 ? player.rate : player.defaultRate),
      isPictureInPictureActive: player.isPictureInPictureActive,
      captions: Self.selectionMenu(player.currentItem, .legible),
      audio: Self.selectionMenu(player.currentItem, .audible)
    )
  }

  /// The menu of one selection group, or nil when the item has no options of that kind. Subtitles can be off, so their menu
  /// starts with `Off`; a group left automatic checks the option the player shows or plays now.
  @MainActor private static func selectionMenu(_ item: AVPlayerItem?, _ characteristic: AVMediaCharacteristic) -> AVKitSelectionMenu? {
    guard let item, let group = item._selectionGroup(for: characteristic) else { return nil }
    let selected = item.currentMediaSelection.selectedMediaOption(in: group)
    var entries: [AVKitSelectionMenu.Entry] = []
    if group.allowsEmptySelection {
      entries.append(AVKitSelectionMenu.Entry(id: "off", label: "Off", isChecked: selected == nil))
    }
    for option in group.options {
      let checked = selected.map { $0._identifier == option._identifier } ?? false
      entries.append(AVKitSelectionMenu.Entry(id: option._identifier, label: option.displayName, isChecked: checked))
    }
    return AVKitSelectionMenu(entries: entries)
  }

  package var volumeGlyph: VolumeGlyph {
    if isMuted || volume <= 0 { return .muted }
    return volume < 0.5 ? .low : .high
  }

  package var state: String {
    if hasFailed { return "failed" }
    if isBuffering { return "buffering" }
    switch transport {
    case .play: return "paused"
    case .pause: return "playing"
    case .replay: return "ended"
    }
  }

  /// The position as a fraction of the duration, 0 when it is unknown.
  package var progress: Double {
    guard canSeek, duration > 0 else { return 0 }
    return min(1, max(0, currentTime / duration))
  }
}

/// The controls' text: clock labels (`1:05`, `-12:34`, `1:02:03`) and the spoken form of a time for assistive technology.
package enum AVKitTimeFormat {
  private static func pad<Value: BinaryInteger>(_ value: Value) -> String { value < 10 ? "0" + String(value) : String(value) }

  /// The whole seconds, in Int64: Int is 32 bits in the browser build, and a media file can declare any duration.
  package static func wholeSeconds(_ seconds: Double) -> Int64 {
    guard seconds.isFinite, seconds > 0 else { return 0 }
    return seconds < 9.2e18 ? Int64(seconds) : Int64.max
  }

  /// `m:ss`, or `h:mm:ss` from an hour on. An unknown time reads `0:00`.
  package static func clock(_ seconds: Double) -> String {
    let whole = wholeSeconds(seconds)
    let hours = whole / 3600
    let minutes = (whole % 3600) / 60
    let rest = whole % 60
    if hours > 0 { return String(hours) + ":" + pad(minutes) + ":" + pad(rest) }
    return String(minutes) + ":" + pad(rest)
  }

  /// The time left, with a minus sign as AVKit draws it.
  package static func remaining(time: Double, duration: Double) -> String {
    guard duration.isFinite, duration > 0 else { return "" }
    return "-" + clock(max(0, duration - time))
  }

  /// `1 hour, 2 minutes, 3 seconds`: what a screen reader says for a position.
  package static func spoken(_ seconds: Double) -> String {
    let whole = wholeSeconds(seconds)
    let hours = whole / 3600
    let minutes = (whole % 3600) / 60
    let rest = whole % 60
    var parts: [String] = []
    if hours > 0 { parts.append(String(hours) + (hours == 1 ? " hour" : " hours")) }
    if minutes > 0 { parts.append(String(minutes) + (minutes == 1 ? " minute" : " minutes")) }
    if rest > 0 || parts.isEmpty { parts.append(String(rest) + (rest == 1 ? " second" : " seconds")) }
    var out = ""
    for (index, part) in parts.enumerated() {
      if index > 0 { out += ", " }
      out += part
    }
    return out
  }

  /// `1x`, `1.5x`, `0.75x`.
  package static func speed(_ rate: Double) -> String {
    let hundredths = Int((rate * 100).rounded())
    let whole = hundredths / 100
    let fraction = hundredths % 100
    if fraction == 0 { return String(whole) + "x" }
    if fraction % 10 == 0 { return String(whole) + "." + String(fraction / 10) + "x" }
    return String(whole) + "." + pad(fraction) + "x"
  }

  /// A CSS percentage with one decimal.
  package static func percent(_ fraction: Double) -> String {
    let tenths = Int((min(1, max(0, fraction.isFinite ? fraction : 0)) * 1000).rounded())
    return String(tenths / 10) + "." + String(tenths % 10) + "%"
  }
}

/// What the viewer asked of the controls. The host sends `"<verb>|<argument>"`; the player does the rest.
package enum AVKitControlsAction {
  /// The speeds of the speed menu, as AVKit's.
  package static let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]

  @MainActor package static func perform(_ payload: String, on player: AVPlayer) {
    var verb = Substring(payload)
    var argument = Substring("")
    if let bar = payload.firstIndex(of: "|") {
      verb = payload[..<bar]
      argument = payload[payload.index(after: bar)...]
    }
    switch verb {
    case "play":
      play(player)
    case "pause":
      player.pause()
    case "toggle":
      if player.timeControlStatus == .paused { play(player) } else { player.pause() }
    case "seek":
      if let seconds = number(argument) { seek(player, to: seconds) }
    case "skip":
      if let delta = number(argument) { seek(player, to: player.currentTime().seconds + delta) }
    case "mute":
      // "toggle" is decided here, where the player's newest wish is: the page's element may not show it yet, so a second key
      // press asked from the element would undo the first (section 12.27).
      if argument == "toggle" {
        player.isMuted = !(player.isMuted || player.volume == 0)
      } else {
        player.isMuted = argument == "1"
      }
    case "volume":
      if let level = number(argument) {
        player.volume = Float(min(1, max(0, level)))
        // Dragging the volume up from a muted player sounds it, as the system's volume does.
        if level > 0, player.isMuted { player.isMuted = false }
      }
    case "rate":
      if let speed = number(argument), speed > 0 {
        player.defaultRate = Float(speed)
        if player.rate != 0 { player.rate = Float(speed) }
      }
    case "caption":
      choose(.legible, argument, on: player)
    case "audio":
      choose(.audible, argument, on: player)
    default:
      break
    }
  }

  /// Chooses an option of the item's group with `select(_:in:)`; `off` turns the subtitles off.
  @MainActor private static func choose(_ characteristic: AVMediaCharacteristic, _ identifier: Substring, on player: AVPlayer) {
    guard let item = player.currentItem, let group = item._selectionGroup(for: characteristic) else { return }
    if identifier == "off" {
      item.select(nil, in: group)
    } else if let option = group.options.first(where: { $0._identifier == String(identifier) }) {
      item.select(option, in: group)
    }
  }

  @MainActor private static func play(_ player: AVPlayer) {
    // Playing from the end starts over, as AVKit's replay does.
    if player._isAtEnd { seek(player, to: 0) }
    player.play()
  }

  @MainActor private static func seek(_ player: AVPlayer, to seconds: Double) {
    let duration = player.currentItem?.duration.seconds ?? 0
    var target = seconds.isFinite ? max(0, seconds) : 0
    if player._hasPlayableDuration, duration.isFinite { target = min(target, duration) }
    player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
  }

  private static func number(_ text: Substring) -> Double? {
    // Embedded Swift has no `Double(Substring)`; the host sends plain decimals.
    var negative = false
    var whole = 0.0
    var scale = 0.0
    var seen = false
    for character in text {
      if character == "-" && !seen && scale == 0 {
        negative = true
      } else if character == "." && scale == 0 {
        scale = 1
      } else if let digit = character.wholeNumberValue, character.isASCII {
        seen = true
        if scale == 0 {
          whole = whole * 10 + Double(digit)
        } else {
          scale *= 10
          whole += Double(digit) / scale
        }
      } else {
        return nil
      }
    }
    return seen ? (negative ? -whole : whole) : nil
  }
}

/// The DOM of the controls.
@MainActor package struct AVKitControlsRenderer {
  package let model: AVKitControlsModel
  package let showsFullscreen: Bool
  package let showsPictureInPicture: Bool
  package let context: _RenderContext

  private func symbol(_ name: String, _ key: String) -> _RenderNode {
    let node = Image(systemName: name)._render(in: context.child(_FiberKey(key)))
    // The button names the action; the glyph is decoration.
    node.attributes["aria-hidden"] = "true"
    node.attributes["role"] = nil
    node.attributes["aria-label"] = nil
    return node
  }

  private func button(_ action: String, label: String, symbol glyph: String?, hostOwns: String? = nil) -> _RenderNode {
    let node = _RenderNode.element("button")
    node.attributes["type"] = "button"
    node.classes = ["avkit-button", "avkit-" + action]
    node.attributes["data-control-action"] = action
    node.attributes["aria-label"] = label
    node.attributes["title"] = label
    if let hostOwns { node.attributes["data-host-managed"] = hostOwns }
    if let glyph { node.children = [symbol(glyph, action)] }
    return node
  }

  private func group(_ name: String, label: String? = nil, children: [_RenderNode]) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["avkit-" + name]
    if let label {
      node.attributes["role"] = "group"
      node.attributes["aria-label"] = label
    }
    node.children = children
    return node
  }

  private func slider(
    _ name: String,
    label: String,
    now: Double,
    maximum: Double,
    text: String,
    fill: Double,
    disabled: Bool
  ) -> _RenderNode {
    let node = _RenderNode.element("div")
    node.classes = ["avkit-slider", "avkit-" + name]
    node.attributes["role"] = "slider"
    node.attributes["tabindex"] = "0"
    node.attributes["aria-label"] = label
    node.attributes["aria-orientation"] = "horizontal"
    node.attributes["aria-valuemin"] = "0"
    node.attributes["aria-valuemax"] = String(AVKitTimeFormat.wholeSeconds(maximum.rounded()))
    node.attributes["aria-valuenow"] = String(AVKitTimeFormat.wholeSeconds(now.rounded()))
    node.attributes["aria-valuetext"] = text
    node.attributes["data-control-slider"] = name
    if disabled { node.attributes["aria-disabled"] = "true" }
    // The host moves the slider continuously; the patcher leaves what it owns alone.
    node.attributes["data-host-managed"] = "*children aria-valuemax aria-valuenow aria-valuetext aria-disabled"

    let track = _RenderNode.element("div")
    track.classes = ["avkit-track"]
    var parts: [_RenderNode] = []
    if name == "scrubber" {
      let loaded = _RenderNode.element("div")
      loaded.classes = ["avkit-loaded"]
      loaded.styles["width"] = AVKitTimeFormat.percent(model.duration > 0 ? model.loadedTime / model.duration : 0)
      parts.append(loaded)
    }
    let played = _RenderNode.element("div")
    played.classes = ["avkit-played"]
    played.styles["width"] = AVKitTimeFormat.percent(fill)
    parts.append(played)
    track.children = parts
    let thumb = _RenderNode.element("div")
    thumb.classes = ["avkit-thumb"]
    thumb.styles["left"] = AVKitTimeFormat.percent(fill)
    node.children = [track, thumb]
    return node
  }

  private func timeLabel(_ name: String, _ text: String) -> _RenderNode {
    let node = _RenderNode.element("span")
    node.classes = ["avkit-time", "avkit-" + name]
    node.attributes["aria-hidden"] = "true"
    node.attributes["data-host-managed"] = "*children"
    node.children = [.text(text)]
    return node
  }

  private var transportGroup: _RenderNode {
    var children: [_RenderNode] = []
    if model.canSeek {
      children.append(button("skip-back", label: "Skip Back 10 Seconds", symbol: "gobackward.10"))
    }
    switch model.transport {
    case .play: children.append(button("play-pause", label: "Play", symbol: "play.fill"))
    case .pause: children.append(button("play-pause", label: "Pause", symbol: "pause.fill"))
    case .replay: children.append(button("play-pause", label: "Replay", symbol: "arrow.counterclockwise"))
    }
    if model.canSeek {
      children.append(button("skip-forward", label: "Skip Forward 10 Seconds", symbol: "goforward.10"))
    }
    return group("transport", label: "Transport controls", children: children)
  }

  private var timeline: _RenderNode {
    let spoken = model.canSeek
      ? AVKitTimeFormat.spoken(model.currentTime) + " of " + AVKitTimeFormat.spoken(model.duration)
      : AVKitTimeFormat.spoken(model.currentTime)
    let scrubber = slider(
      "scrubber", label: "Seek", now: model.currentTime, maximum: model.duration, text: spoken,
      fill: model.progress, disabled: !model.canSeek)
    return group("timeline", children: [
      timeLabel("elapsed", AVKitTimeFormat.clock(model.currentTime)),
      scrubber,
      timeLabel("remaining", AVKitTimeFormat.remaining(time: model.currentTime, duration: model.duration)),
    ])
  }

  private var volumeControl: _RenderNode {
    let muteLabel = model.volumeGlyph == .muted ? "Unmute" : "Mute"
    let glyph: String
    switch model.volumeGlyph {
    case .muted: glyph = "speaker.slash.fill"
    case .low: glyph = "speaker.fill"
    case .high: glyph = "speaker.wave.2.fill"
    }
    let level = model.isMuted ? 0 : model.volume
    let mute = button("mute", label: muteLabel, symbol: glyph)
    mute.attributes["aria-pressed"] = model.volumeGlyph == .muted ? "true" : "false"
    let volume = slider(
      "volume", label: "Volume", now: level * 100, maximum: 100,
      text: String(Int((level * 100).rounded())) + " percent", fill: level, disabled: false)
    return group("volume-group", children: [mute, volume])
  }

  private var speedMenu: _RenderNode {
    let toggle = button("speed", label: "Playback Speed", symbol: nil, hostOwns: "aria-expanded")
    toggle.attributes["aria-haspopup"] = "menu"
    toggle.attributes["aria-expanded"] = "false"
    toggle.attributes["aria-label"] = "Playback Speed, " + AVKitTimeFormat.speed(model.speed)
    toggle.children = [.text(AVKitTimeFormat.speed(model.speed))]

    let menu = _RenderNode.element("div")
    menu.classes = ["avkit-menu", "avkit-speed-menu"]
    menu.attributes["role"] = "menu"
    menu.attributes["aria-label"] = "Playback Speed"
    var items: [_RenderNode] = []
    for speed in AVKitControlsAction.speeds {
      let item = _RenderNode.element("button")
      item.attributes["type"] = "button"
      item.classes = ["avkit-menu-item"]
      item.attributes["role"] = "menuitemradio"
      item.attributes["data-control-action"] = "rate"
      item.attributes["data-control-argument"] = String(speed)
      let selected = abs(speed - model.speed) < 0.001
      item.attributes["aria-checked"] = selected ? "true" : "false"
      item.attributes["tabindex"] = "-1"
      item.children = [.text(AVKitTimeFormat.speed(speed))]
      items.append(item)
    }
    menu.children = items
    let wrapper = _RenderNode.element("div")
    wrapper.classes = ["avkit-speed-group", "avkit-menu-group"]
    wrapper.children = [toggle, menu]
    return wrapper
  }

  /// A menu that picks an option of a selection group, built as the speed menu is: a toggle button that names the checked
  /// option, and a `menu` of `menuitemradio` items. The host opens it (`data-ctl-menu`) and moves the focus.
  private func selectionMenu(_ name: String, title: String, symbol glyph: String, menu: AVKitSelectionMenu, itemAction: String) -> _RenderNode {
    let toggle = button(name, label: title + ", " + menu.checkedLabel, symbol: glyph, hostOwns: "aria-expanded")
    toggle.attributes["aria-haspopup"] = "menu"
    toggle.attributes["aria-expanded"] = "false"

    let list = _RenderNode.element("div")
    list.classes = ["avkit-menu", "avkit-" + name + "-menu"]
    list.attributes["role"] = "menu"
    list.attributes["aria-label"] = title
    var items: [_RenderNode] = []
    for entry in menu.entries {
      let item = _RenderNode.element("button")
      item.attributes["type"] = "button"
      item.classes = ["avkit-menu-item"]
      item.attributes["role"] = "menuitemradio"
      item.attributes["data-control-action"] = itemAction
      item.attributes["data-control-argument"] = entry.id
      item.attributes["aria-checked"] = entry.isChecked ? "true" : "false"
      item.attributes["tabindex"] = "-1"
      item.children = [.text(entry.label)]
      items.append(item)
    }
    list.children = items
    let wrapper = _RenderNode.element("div")
    wrapper.classes = ["avkit-menu-group", "avkit-" + name + "-group"]
    wrapper.children = [toggle, list]
    return wrapper
  }

  private var fullscreenButton: _RenderNode {
    // The host swaps the label with the document's fullscreen state; both glyphs are drawn and CSS shows one.
    let node = button("fullscreen", label: "Enter Full Screen", symbol: nil, hostOwns: "aria-label title")
    let enter = symbol("arrow.up.left.and.arrow.down.right", "fullscreen-enter")
    enter.classes.append("avkit-enter")
    let exit = symbol("arrow.down.right.and.arrow.up.left", "fullscreen-exit")
    exit.classes.append("avkit-exit")
    node.children = [enter, exit]
    return node
  }

  private var utilityGroup: _RenderNode {
    var children: [_RenderNode] = [volumeControl]
    if let captions = model.captions {
      children.append(selectionMenu("captions", title: "Subtitles and Captions", symbol: "captions.bubble", menu: captions, itemAction: "caption"))
    }
    if let audio = model.audio {
      children.append(selectionMenu("audio", title: "Audio", symbol: "hifispeaker", menu: audio, itemAction: "audio-track"))
    }
    children.append(speedMenu)
    if showsPictureInPicture {
      let active = model.isPictureInPictureActive
      let pip = button(
        "pip", label: active ? "Exit Picture in Picture" : "Enter Picture in Picture",
        symbol: active ? "pip.exit" : "pip.enter")
      pip.attributes["aria-pressed"] = active ? "true" : "false"
      children.append(pip)
    }
    if showsFullscreen { children.append(fullscreenButton) }
    return group("utility", children: children)
  }

  package func render() -> _RenderNode {
    let root = _RenderNode.element("div")
    root.classes = ["avkit-controls"]
    root.attributes["data-player-state"] = model.state
    root.attributes["data-can-seek"] = model.canSeek ? "true" : "false"
    // The host decides when the controls are shown (auto-hide) and what the page supports.
    root.attributes["data-host-managed"] = "data-ctl-hidden data-ctl-scrubbing data-ctl-fullscreen data-ctl-pip data-ctl-menu"

    var children: [_RenderNode] = []
    let scrim = _RenderNode.element("div")
    scrim.classes = ["avkit-scrim"]
    scrim.attributes["aria-hidden"] = "true"
    children.append(scrim)

    if model.hasFailed {
      let failure = _RenderNode.element("div")
      failure.classes = ["avkit-error"]
      failure.attributes["role"] = "alert"
      let text = _RenderNode.element("span")
      text.children = [.text("This video can\u{2019}t be played.")]
      failure.children = [symbol("exclamationmark.triangle.fill", "error"), text]
      children.append(failure)
    } else if model.isBuffering {
      let spinner = _RenderNode.element("div")
      spinner.classes = ["avkit-spinner"]
      spinner.attributes["role"] = "status"
      spinner.attributes["aria-label"] = "Buffering"
      children.append(spinner)
    }

    let bar = _RenderNode.element("div")
    bar.classes = ["avkit-bar"]
    bar.attributes["role"] = "group"
    bar.attributes["aria-label"] = "Playback controls"
    bar.children = [transportGroup, timeline, utilityGroup]
    children.append(bar)
    root.children = children
    return root
  }
}
