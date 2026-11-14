import SwiftUIWeb
import SwiftUIWebBrowserIO
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebTransferable
@_spi(WebMount) import SwiftUIWebBrowser

internal enum _MediaEventName: String {
  case loadedMetadata = "loadedmetadata"
  case durationChange = "durationchange"
  case canPlay = "canplay"
  case canPlayThrough = "canplaythrough"
  case play
  case playing
  case pause
  case waiting
  case stalled
  case suspend
  case emptied
  case ended
  case timeUpdate = "timeupdate"
  case seeking
  case seeked
  case progress
  case error
  case rateChange = "ratechange"
  case volumeChange = "volumechange"
  case enterPictureInPicture = "enterpictureinpicture"
  case leavePictureInPicture = "leavepictureinpicture"
}

/// What the browser host reports about a media element: the `media-report` named event,
/// "<event>|<currentTime>|<duration>|<paused>|<muted>|<volume>[|<buffered>[|<rate>|<readyState>|<seeking>|<ended>|
/// <errorCode>|<seekSequence>|<hostTime>|<item>[|<intent>]]]" (Tools/media-host.js). A duration the element does not
/// know yet is -1; a report without the trailing fields describes an element that plays at rate 1 with enough data.
internal struct _MediaHostReport: Equatable {
  var event: _MediaEventName
  var currentTime: Double
  var duration: Double
  var paused: Bool
  var muted: Bool
  var volume: Double
  /// What the element has loaded, as "start-end" ranges separated by ";" (optional 7th field).
  var buffered: [WebMediaTimeRange] = []
  /// The element's `playbackRate`.
  var rate = 1.0
  /// The element's `readyState` (0 nothing, 1 metadata, 2 current frame, 3 future data, 4 enough data).
  var readyState = 4
  var seeking = false
  var ended = false
  /// `MediaError.code` (1 aborted, 2 network, 3 decode, 4 source not supported), 0 without an error.
  var errorCode = 0
  /// The newest seek command the element has taken; a `seeked` completes the seeks up to it.
  var seekSequence: UInt64 = 0
  /// When the host took the sample: its `Date.now()` in milliseconds, 0 when the report does not say.
  var hostTime = 0.0
  /// Which item the element was playing when it sampled (`data-media-item`); a sample of a replaced item is stale.
  var item: UInt64 = 0
  var namesItem = false
  /// The play intent the host had applied to the element when it sampled (`data-media-intent`), nil when the report does
  /// not name one. A report about an older intent than the player's newest describes the element before the player asked for
  /// what it wants now, so its play and pause state does not change the player's wish (section 12.27).
  var intent: UInt64?

  init?(_ payload: String) {
    let fields = payload.split(separator: "|", omittingEmptySubsequences: false)
    guard (6...7).contains(fields.count) || (14...16).contains(fields.count),
          let event = _MediaEventName(rawValue: String(fields[0])),
          let currentTime = Double(String(fields[1])), let duration = Double(String(fields[2])),
          let volume = Double(String(fields[5])) else { return nil }
    self.event = event
    self.currentTime = max(0, currentTime)
    self.duration = duration < 0 ? .nan : duration
    self.paused = fields[3] == "1"
    self.muted = fields[4] == "1"
    self.volume = min(max(0, volume), 1)
    if fields.count >= 7 {
      for range in fields[6].split(separator: ";") {
        let bounds = range.split(separator: "-")
        guard bounds.count == 2, let start = Double(String(bounds[0])), let end = Double(String(bounds[1])), end >= start else { continue }
        buffered.append(WebMediaTimeRange(start: start, end: end))
      }
    }
    if fields.count >= 14 {
      guard let rate = Double(String(fields[7])), let readyState = Int(String(fields[8])), let errorCode = Int(String(fields[11])),
            let sequence = UInt64(String(fields[12])), let hostTime = Double(String(fields[13])) else { return nil }
      self.rate = rate.isFinite ? max(0, rate) : 1
      self.readyState = readyState
      self.seeking = fields[9] == "1"
      self.ended = fields[10] == "1"
      self.errorCode = errorCode
      self.seekSequence = sequence
      self.hostTime = hostTime
      if fields.count >= 15 {
        guard let item = UInt64(String(fields[14])) else { return nil }
        self.item = item
        namesItem = true
      }
      if fields.count == 16, !fields[15].isEmpty {
        guard let intent = UInt64(String(fields[15])) else { return nil }
        self.intent = intent
      }
    }
  }
}

/// The clocks the mirror reads, replaceable in tests. Both are the runtime's own: the monotonic one the WASI clock (continuous
/// across the move from the Worker to the main thread, section 12.11), the wall one the `Date.now()` the page shares.
///
/// The overrides are optional stored properties that start as `nil`, and the behaviour is in static functions. A static
/// property initialised by a closure literal needs a lazily initialised global, and in a debug Embedded build the closure
/// initialisers of these stored properties were left unresolved at link time (section 12.20).
@MainActor internal enum _MediaClock {
  static var monotonicOverride: (() -> Double)? = nil
  static var wallMillisecondsOverride: (() -> Double)? = nil
  /// The backend a new player gets: the browser's declarative one, an in-memory one without a host. Tests pick.
  static var makeBackendOverride: (() -> _MediaBackend)? = nil
  /// Starts a one-shot timer and returns what cancels it. Tests replace it with a manual one.
  static var scheduleOverride: ((Double, @escaping @Sendable () -> Void) -> () -> Void)? = nil

  static func monotonic() -> Double {
    if let override = monotonicOverride { return override() }
    return _swiftUIWebMonotonicSeconds()
  }

  static func wallMilliseconds() -> Double {
    if let override = wallMillisecondsOverride { return override() }
    return _swiftUIWebWallClockMilliseconds()
  }

  static func makeBackend() -> _MediaBackend {
    if let override = makeBackendOverride { return override() }
    #if arch(wasm32)
    return _DeclarativeMediaBackend()
    #else
    return _InMemoryMediaBackend()
    #endif
  }

  static func schedule(_ seconds: Double, _ callback: @escaping @Sendable () -> Void) -> () -> Void {
    if let override = scheduleOverride { return override(seconds, callback) }
    let operation = BrowserTimer.schedule(after: seconds, callback)
    return { operation.cancel() }
  }
}

/// What Swift knows of one media element, readable synchronously. The element lives on the page's main thread and the app may
/// run in a Worker, so a read cannot ask it: the host sends a sample whenever the state changes (and about once a second while
/// playback is steady), and the mirror answers reads between samples by extrapolating the last one with the playback rate on the
/// monotonic clock. A sample is aged by the delay between the two threads, taken from the `Date.now()` the host stamped on it.
/// The same mirror serves the main-thread runtime, so an app sees one behaviour.
internal struct _MediaMirror {
  /// The element's time at `stamp` and the monotonic clock (seconds) when that sample was valid.
  private(set) var time = 0.0
  private(set) var stamp = 0.0
  var duration = Double.nan
  /// The element's `playbackRate`, which is the speed time advances at while it plays.
  var rate = 1.0
  var paused = true
  var seeking = false
  var ended = false
  var readyState = 0
  var errorCode = 0
  /// A seek the player asked for has not been taken yet: the time stays where it was until it is, as AVPlayer's does.
  var holdsTime = false
  /// A new sample that lands a little behind what the mirror had extrapolated does not take the time backwards: reads hold at
  /// the extrapolated value until playback catches up with it (AVPlayer's time never runs backwards while it plays).
  private var floor = 0.0

  /// Playback is moving the time: the element plays, has data to play and is not seeking.
  var isAdvancing: Bool { !paused && !seeking && !ended && !holdsTime && readyState >= 3 && rate > 0 }

  func time(at now: Double) -> Double {
    var value = time
    if isAdvancing { value += max(0, now - stamp) * rate }
    value = max(value, floor)
    if duration.isFinite { value = min(value, duration) }
    return value
  }

  /// Takes a sample of the element's time at `now` (the monotonic clock).
  mutating func rebase(to value: Double, at now: Double) {
    time = max(0, value)
    stamp = now
    floor = 0
  }

  mutating func take(_ report: _MediaHostReport, now: Double, wallMilliseconds: Double) {
    var age = 0.0
    if report.hostTime > 0 {
      // The sample is `age` old when it arrives; a clock that disagrees (a different machine's) is not believed past 5 s.
      age = min(max(0, (wallMilliseconds - report.hostTime) / 1000), 5)
    }
    let predicted = time(at: now)
    let wasAdvancing = isAdvancing
    rebase(to: report.currentTime, at: now - age)
    if report.duration.isFinite { duration = report.duration }
    rate = report.rate
    paused = report.paused
    seeking = report.seeking || report.event == .seeking
    ended = report.ended || report.event == .ended
    readyState = report.readyState
    errorCode = report.errorCode
    let jumped = report.event == .seeked || report.event == .seeking || report.seeking || holdsTime
    let behind = predicted - time(at: now)
    floor = wasAdvancing && !jumped && behind > 0 && behind < 0.25 ? predicted : 0
  }
}

@MainActor internal protocol _MediaBackend: AnyObject {
  /// The playback position, read synchronously: the last sample the element sent, advanced by the playback rate since.
  var currentTime: Double { get set }
  var duration: Double { get }
  var rate: Double { get set }
  /// The speed time advances at: the element's own rate once it has reported (it may differ for a moment from `rate`).
  var playbackRate: Double { get }
  var volume: Double { get set }
  var muted: Bool { get set }
  var bufferedRanges: [WebMediaTimeRange] { get }
  var seekableRanges: [WebMediaTimeRange] { get }
  /// Whether the player wants to play: what `VideoPlayer` asks the element for.
  var isPlaying: Bool { get }
  /// Whether the element is actually playing: it has data and is not seeking (a player that wants to play and is not
  /// there yet is waiting).
  var isAdvancing: Bool { get }
  /// Whether an element reports back. Without one (native tests, static rendering) the backend is the truth and a
  /// request takes effect at once.
  var reportsPlayback: Bool { get }
  /// `MediaError.code` of the element's failure, 0 without one.
  var errorCode: Int { get }
  var supportsPictureInPicture: Bool { get }
  var isPictureInPictureActive: Bool { get }
  /// A seek is pending: the time stays where it was until the element takes it (AVPlayer's does not jump either).
  var holdsTime: Bool { get set }
  /// How many requests the player has made (play, pause, mute, volume): the element is told the newest one, and each report
  /// names the one it was taken under (section 12.27).
  var intent: UInt64 { get }

  /// A new item starts over: time zero, nothing known of the element yet.
  func reset()
  func play()
  func pause()
  /// Asks for a seek. Returns whether an element will confirm it with a `seeked` report; if not, the time is the target.
  @discardableResult func seek(to seconds: Double) -> Bool
  func setPictureInPicture(_ enabled: Bool)
  /// Takes in what the element reports; the element is the truth for time, duration and volume.
  func apply(_ report: _MediaHostReport)
}

/// The browser backend. It never touches a DOM element: `VideoPlayer` renders the desired state as
/// attributes and the main-thread media host applies them, so playback works the same in the
/// worker runtime, which has no DOM, as on the main thread. The element's reports flow back
/// through `apply(_:)` into a mirror that answers reads synchronously (`_MediaMirror`).
@MainActor internal class _DeclarativeMediaBackend: _MediaBackend {
  private var wantsToPlay = false
  /// Bumped by every request the element has to take: play, pause, rate, mute and volume (section 12.27).
  private(set) var intent: UInt64 = 0
  internal var mirror = _MediaMirror()
  private var desiredRate = 1.0
  private var desiredVolume = 1.0
  private var desiredMuted = false
  private var pictureInPicture = false

  var currentTime: Double {
    get { mirror.time(at: _MediaClock.monotonic()) }
    set { mirror.rebase(to: newValue, at: _MediaClock.monotonic()) }
  }
  var duration: Double { mirror.duration }
  var playbackRate: Double { mirror.rate }
  var rate: Double {
    get { desiredRate }
    set {
      let rate = max(0, newValue)
      if rate != desiredRate { desiredRate = rate; intent &+= 1 }
    }
  }
  var volume: Double {
    get { desiredVolume }
    set { desiredVolume = min(max(0, newValue), 1); intent &+= 1 }
  }
  var muted: Bool {
    get { desiredMuted }
    set { desiredMuted = newValue; intent &+= 1 }
  }
  private var reportedBuffered: [WebMediaTimeRange] = []
  var bufferedRanges: [WebMediaTimeRange] { reportedBuffered }
  var seekableRanges: [WebMediaTimeRange] { mirror.duration.isFinite ? [WebMediaTimeRange(start: 0, end: mirror.duration)] : [] }
  var isPlaying: Bool { wantsToPlay }
  var isAdvancing: Bool { wantsToPlay && mirror.isAdvancing }
  var reportsPlayback: Bool { true }
  var errorCode: Int { mirror.errorCode }
  var supportsPictureInPicture: Bool { true }
  var isPictureInPictureActive: Bool { pictureInPicture }
  var holdsTime: Bool {
    get { mirror.holdsTime }
    set {
      // Re-anchor first, so the time that was extrapolated up to now is what stays.
      if newValue != mirror.holdsTime { mirror.rebase(to: mirror.time(at: _MediaClock.monotonic()), at: _MediaClock.monotonic()) }
      mirror.holdsTime = newValue
    }
  }

  func reset() {
    mirror = _MediaMirror()
    reportedBuffered = []
  }
  func play() { intent &+= 1; wantsToPlay = true }
  func pause() { intent &+= 1; wantsToPlay = false }
  func seek(to seconds: Double) -> Bool { true }
  func setPictureInPicture(_ enabled: Bool) { pictureInPicture = enabled }

  func apply(_ report: _MediaHostReport) {
    // A report taken under an older play intent than the newest one says nothing about what the player wants now: the element
    // had not yet taken the request (the browser queues `pause` and `play` events, and reads the element when they run).
    // Its play and pause state is the player's own wish, and only the element's time, rate and readiness are taken.
    let stale = report.intent.map { $0 < intent } ?? false
    var report = report
    if stale { report.paused = !wantsToPlay }
    mirror.take(report, now: _MediaClock.monotonic(), wallMilliseconds: _MediaClock.wallMilliseconds())
    reportedBuffered = report.buffered
    // The element's own volume and mute are the player's when the element changes them (its `volumechange`), unless the report
    // was taken under an older request: a held key or a dragged slider asks faster than a change travels to the element and back,
    // and an answer to an older request must not undo the newest one (section 12.27).
    if report.event == .volumeChange, !stale {
      desiredMuted = report.muted
      desiredVolume = report.volume
    }
    // The speed the viewer chose with the native controls is the player's rate, unless the report answers an older request:
    // a speed chosen just before `play()` must not be undone by the element's change to the speed before it.
    if report.event == .rateChange, report.rate > 0, !stale { desiredRate = report.rate }
    // A `play`/`playing` that reaches Swift after the element was paused again (a quick pause by the controls) is stale.
    if !stale {
      switch report.event {
      case .play, .playing: wantsToPlay = !report.paused
      case .pause, .ended: wantsToPlay = false
      default: break
      }
    }
    switch report.event {
    case .enterPictureInPicture: pictureInPicture = true
    case .leavePictureInPicture: pictureInPicture = false
    default: break
    }
  }
}

/// Native/WASI builds keep a deterministic backend rather than depending on Foundation's
/// AVFoundation framework. It preserves desired state, so static rendering and unit tests are
/// useful, while browser hosts provide the real media element.
@MainActor internal final class _InMemoryMediaBackend: _DeclarativeMediaBackend {
  override var reportsPlayback: Bool { false }
  override var playbackRate: Double { rate }
  /// No element advances it: the time is what was last set or reported.
  override var currentTime: Double {
    get { mirror.time }
    set { mirror.rebase(to: newValue, at: 0) }
  }
  override var isAdvancing: Bool { isPlaying }
  override var seekableRanges: [WebMediaTimeRange] { [] }
  override var supportsPictureInPicture: Bool { false }
  override var isPictureInPictureActive: Bool { false }
  override func setPictureInPicture(_ enabled: Bool) { _ = enabled }
  override func seek(to seconds: Double) -> Bool {
    currentTime = seconds
    return false
  }
}

@MainActor internal func _makeMediaBackend() -> _MediaBackend { _MediaClock.makeBackend() }
