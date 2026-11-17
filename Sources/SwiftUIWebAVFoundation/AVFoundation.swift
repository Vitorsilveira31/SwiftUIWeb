import WebFoundation  // `NSValue` and `dispatch_queue_t`, the same spelling on every host.
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebTransferable
import SwiftUIWeb
@_spi(WebMount) import SwiftUIWebBrowser

// MARK: - Core Media values

/// Apple's Core Media scalar typealiases.
public typealias CMTimeValue = Int64
public typealias CMTimeScale = Int32
public typealias CMTimeEpoch = Int64

/// Apple's `CMTimeFlags`: the state bits of a `CMTime`.
public struct CMTimeFlags: OptionSet, Hashable, Sendable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  public static let valid = CMTimeFlags(rawValue: 1 << 0)
  public static let hasBeenRounded = CMTimeFlags(rawValue: 1 << 1)
  public static let positiveInfinity = CMTimeFlags(rawValue: 1 << 2)
  public static let negativeInfinity = CMTimeFlags(rawValue: 1 << 3)
  public static let indefinite = CMTimeFlags(rawValue: 1 << 4)
  public static let impliedValueFlagsMask = CMTimeFlags(rawValue: 0x1F)
}

/// A compact, Foundation-free representation of a media timestamp.
public struct CMTime: Hashable, Comparable, Sendable {
  public let value: Int64
  public let timescale: Int32
  public let flags: CMTimeFlags
  public let epoch: Int64

  public init(value: CMTimeValue, timescale: CMTimeScale, flags: CMTimeFlags, epoch: CMTimeEpoch) {
    self.value = value
    self.timescale = timescale
    self.flags = flags
    self.epoch = epoch
  }

  public init(seconds: Double, preferredTimescale: CMTimeScale) {
    // Int32.min has no positive counterpart: abs would trap.
    let scale = preferredTimescale == 0 ? 600 : (preferredTimescale == .min ? .max : abs(preferredTimescale))
    if seconds.isNaN {
      self.init(value: 0, timescale: 0, flags: [], epoch: 0)
    } else if seconds == .infinity {
      self.init(value: 0, timescale: 0, flags: [.positiveInfinity], epoch: 0)
    } else if seconds == -.infinity {
      self.init(value: 0, timescale: 0, flags: [.negativeInfinity], epoch: 0)
    } else {
      // Saturated: a media file can declare any duration, and Int64(_:) traps past its range (about 1.5e16 seconds at
      // a timescale of 600). Core Media has no larger value either.
      let ticks = (seconds * Double(scale)).rounded()
      let value = ticks >= 9.2e18 ? Int64.max : ticks <= -9.2e18 ? Int64.min : Int64(ticks)
      self.init(value: value, timescale: scale, flags: [.valid], epoch: 0)
    }
  }

  package static func seconds(_ seconds: Double, preferredTimescale: Int32 = 600) -> CMTime {
    CMTime(seconds: seconds, preferredTimescale: preferredTimescale)
  }

  public static let zero = CMTime(value: 0, timescale: 600, flags: [.valid], epoch: 0)
  public static let invalid = CMTime(value: 0, timescale: 0, flags: [], epoch: 0)
  public static let indefinite = CMTime(value: 0, timescale: 0, flags: [.indefinite], epoch: 0)
  public static let positiveInfinity = CMTime(value: 0, timescale: 0, flags: [.positiveInfinity], epoch: 0)
  public static let negativeInfinity = CMTime(value: 0, timescale: 0, flags: [.negativeInfinity], epoch: 0)

  public var isValid: Bool { flags.contains(.valid) }
  public var isNumeric: Bool { isValid && timescale != 0 && !flags.contains(.indefinite) && !flags.contains(.positiveInfinity) && !flags.contains(.negativeInfinity) }
  public var isIndefinite: Bool { flags.contains(.indefinite) }
  public var isPositiveInfinity: Bool { flags.contains(.positiveInfinity) }
  public var isNegativeInfinity: Bool { flags.contains(.negativeInfinity) }
  public var seconds: Double {
    if isPositiveInfinity { return .infinity }
    if isNegativeInfinity { return -.infinity }
    if isIndefinite || !isNumeric { return .nan }
    return Double(value) / Double(timescale)
  }

  public static func < (lhs: CMTime, rhs: CMTime) -> Bool {
    let left = lhs.seconds
    let right = rhs.seconds
    if left.isNaN { return !right.isNaN }
    if right.isNaN { return false }
    return left < right
  }

  public static func + (lhs: CMTime, rhs: CMTime) -> CMTime {
    guard lhs.isNumeric, rhs.isNumeric else { return .invalid }
    let scale = max(lhs.timescale, rhs.timescale)
    return CMTime(seconds: lhs.seconds + rhs.seconds, preferredTimescale: scale)
  }

  public static func - (lhs: CMTime, rhs: CMTime) -> CMTime {
    guard lhs.isNumeric, rhs.isNumeric else { return .invalid }
    let scale = max(lhs.timescale, rhs.timescale)
    return CMTime(seconds: lhs.seconds - rhs.seconds, preferredTimescale: scale)
  }
}

public struct CMTimeRange: Hashable, Sendable {
  public var start: CMTime
  public var duration: CMTime

  public init(start: CMTime, duration: CMTime) {
    self.start = start
    self.duration = duration
  }

  public init(start: CMTime, end: CMTime) {
    self.init(start: start, duration: end - start)
  }

  public static let zero = CMTimeRange(start: .zero, duration: .zero)
  public static let invalid = CMTimeRange(start: .invalid, duration: .invalid)
  public var end: CMTime { start + duration }
  public var isValid: Bool { start.isValid && duration.isValid }
  public var isEmpty: Bool { duration.isNumeric && duration.seconds <= 0 }

  public func containsTime(_ time: CMTime) -> Bool {
    guard start.isNumeric, duration.isNumeric, time.isNumeric else { return false }
    return time >= start && time < end
  }

  public func intersection(_ other: CMTimeRange) -> CMTimeRange {
    guard start.isNumeric, duration.isNumeric, other.start.isNumeric, other.duration.isNumeric else { return .zero }
    let lower = max(start, other.start)
    let upper = min(end, other.end)
    return upper > lower ? CMTimeRange(start: lower, end: upper) : .zero
  }
}

// MARK: - Metadata and errors

/// The failure a browser media element reports. Apple's `AVPlayerItem.error` is an `Error`; this is its value.
package struct AVMediaError: Error, Hashable, Sendable {
  package let message: String
  package init(_ message: String) { self.message = message }
}

/// Apple's `AVMetadataItem` cannot be built by applications; the browser host creates these from the media element.
public struct AVMetadataItem: Hashable, Sendable {
  public let identifier: String
  public let commonKey: String?
  public let stringValue: String?

  package init(identifier: String, commonKey: String? = nil, stringValue: String? = nil) {
    self.identifier = identifier
    self.commonKey = commonKey
    self.stringValue = stringValue
  }
}

/// Apple's `AVMediaType`: a string-backed struct with static members for each media type.
public struct AVMediaType: RawRepresentable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let video = AVMediaType(rawValue: "vide")
  public static let audio = AVMediaType(rawValue: "soun")
  public static let text = AVMediaType(rawValue: "text")
  public static let closedCaption = AVMediaType(rawValue: "clcp")
  public static let subtitle = AVMediaType(rawValue: "sbtl")
  public static let timecode = AVMediaType(rawValue: "tmcd")
  public static let metadata = AVMediaType(rawValue: "meta")
  public static let muxed = AVMediaType(rawValue: "muxx")
  public static let haptic = AVMediaType(rawValue: "hapt")

  /// A media type the browser cannot classify from the URL. Not an Apple member.
  package static let unclassified = AVMediaType(rawValue: "unclassified")
}

// MARK: - Assets and items

/// Apple's protocol for asset property loading (`load(_:)`) and the callback-style loading that `AVAsset` provides.
public protocol AVAsynchronousKeyValueLoading {
  func loadValuesAsynchronously(forKeys keys: [String], completionHandler handler: (@Sendable () -> Void)?)
  /// Suspends until the browser host has reported what the asset's properties hold. Not Apple's; `load(_:)` waits on it.
  @_spi(Renderer) @MainActor func _awaitLoadedValues() async
}

extension AVAsynchronousKeyValueLoading {
  /// Values are already available synchronously for URL assets where the host exposes them, so the handler runs at once.
  public func loadValuesAsynchronously(forKeys keys: [String], completionHandler handler: (@Sendable () -> Void)?) {
    _ = keys
    handler?()
  }

  @_spi(Renderer) @MainActor public func _awaitLoadedValues() async {}
}

extension AVAsynchronousKeyValueLoading where Self: Sendable {
  /// Apple's `load(_:isolation:)`: the value of an asynchronously loaded property of the asset, once the host has it.
  /// The asset crosses to the main actor where the host's report lives, so it must be `Sendable` (AVAsset is).
  public func load<Value>(_ property: AVAsyncProperty<Self, Value>, isolation: isolated (any Actor)? = #isolation) async throws -> Value {
    await _awaitLoadedValues()
    return property.read(self)
  }
}

open class AVAsset: AVAsynchronousKeyValueLoading, @unchecked Sendable {
  public private(set) var duration: CMTime
  public private(set) var isPlayable: Bool
  public private(set) var commonMetadata: [AVMetadataItem]

  internal init(duration: CMTime = .indefinite, isPlayable: Bool = true, metadata: [AVMetadataItem] = []) {
    self.duration = duration
    self.isPlayable = isPlayable
    self.commonMetadata = metadata
  }

  /// The tracks the media host reported (see MediaSelection.swift), and who waits for them.
  internal var _tracks: _MediaTracks?
  internal var _trackWaiters: [UInt64: CheckedContinuation<Void, Never>] = .init()
  internal var _trackWaiterID: UInt64 = 0

  @_spi(Renderer) @MainActor public func _awaitLoadedValues() async { await _loadedTracks() }

  fileprivate final func _setDuration(_ duration: CMTime) { self.duration = duration }

  /// The browser backend resolves metadata from the media element as it
  /// loads. Keeping this familiar callback spelling makes code that loads an
  /// asset asynchronously source-compatible; values are already available
  /// synchronously for URL assets where the host exposes them.
}

public final class AVURLAsset: AVAsset, @unchecked Sendable {
  public let url: URL
  package let options: [String: Any]
  package let mediaType: AVMediaType
  package let requiresAdaptiveStreaming: Bool
  public init(url: URL, options: [String: Any]? = nil) {
    self.url = url
    let resolvedOptions = options ?? .init()
    self.options = resolvedOptions
    let source = url.absoluteString.lowercased()
    func stringOption(_ key: String) -> String? {
      #if hasFeature(Embedded)
      _ = key
      return nil
      #else
      if let value = resolvedOptions[key] as? String { return value }
      if let value = resolvedOptions[key] as? Bool { return value ? "true" : "false" }
      return nil
      #endif
    }
    var hasDRMOption = false
    #if !hasFeature(Embedded)
    hasDRMOption = resolvedOptions["drm"] != nil
    #endif
    if _swiftUIWebAVContainsLiteral(source, ".m3u8") || _swiftUIWebAVContainsLiteral(source, ".mpd")
        || stringOption("adaptive")?.lowercased() == "true"
        || hasDRMOption {
      requiresAdaptiveStreaming = true
    } else {
      requiresAdaptiveStreaming = false
    }
    if _swiftUIWebAVContainsLiteral(source, ".mp3") || _swiftUIWebAVContainsLiteral(source, ".m4a") || _swiftUIWebAVContainsLiteral(source, ".aac") || _swiftUIWebAVContainsLiteral(source, ".ogg") || _swiftUIWebAVContainsLiteral(source, ".wav") {
      mediaType = .audio
    } else if _swiftUIWebAVContainsLiteral(source, ".mp4") || _swiftUIWebAVContainsLiteral(source, ".webm") || _swiftUIWebAVContainsLiteral(source, ".mov") || _swiftUIWebAVContainsLiteral(source, ".m3u8") || _swiftUIWebAVContainsLiteral(source, ".mpd") {
      mediaType = .video
    } else {
      mediaType = .unclassified
    }

    var metadata: [AVMetadataItem] = []
    if let title = stringOption("title") {
      metadata.append(AVMetadataItem(identifier: "commonIdentifierTitle", commonKey: "title", stringValue: title))
    }
    if let artist = stringOption("artist") {
      metadata.append(AVMetadataItem(identifier: "commonIdentifierArtist", commonKey: "artist", stringValue: artist))
    }
    if let album = stringOption("album") {
      metadata.append(AVMetadataItem(identifier: "commonIdentifierAlbumName", commonKey: "albumName", stringValue: album))
    }
    if metadata.isEmpty,
       let filename = source.split(separator: "/").last.map(String.init),
       !filename.isEmpty {
      metadata.append(AVMetadataItem(identifier: "commonIdentifierTitle", commonKey: "title", stringValue: filename))
    }
    super.init(metadata: metadata)
  }
}

// Embedded Swift currently exposes String.contains only for Character. Keep
// media URL checks on a Foundation-free stdlib scan so native and browser
// builds share the same detection semantics.
internal func _swiftUIWebAVContainsLiteral(_ value: String, _ needle: String) -> Bool {
  guard !needle.isEmpty else { return true }
  var index = value.startIndex
  while index < value.endIndex {
    if value[index...].hasPrefix(needle) { return true }
    index = value.index(after: index)
  }
  return false
}

// Apple's AVPlayerItem is nonisolated. Its state is written by the browser host on the main actor, so the
// members that touch it are `@MainActor` helpers reached through `_assumeMainActor` from the public API.
// Apple's AVPlayerItem is main-actor isolated as a type; the members Apple marks `nonisolated` are spelled so here,
// and they reach the main-actor state through `_assumeMainActor`.
@MainActor public final class AVPlayerItem: ObservableObject {
  public enum Status: Int, Hashable, Sendable {
    case unknown
    case readyToPlay
    case failed
  }

  package enum BufferingState: String, Hashable, Sendable {
    case unknown
    case empty
    case likelyToKeepUp
    case full
  }

  public let asset: AVAsset
  // Stored state is main-actor isolated; the `nonisolated` read-only members below are Apple's spelling, and the
  // `_` storage is what the browser host writes.
  private nonisolated(unsafe) var _status: Status = .unknown
  private nonisolated(unsafe) var _error: (any Error)?
  private nonisolated(unsafe) var _duration: CMTime
  package private(set) var currentTime: CMTime = .zero
  private nonisolated(unsafe) var _loadedTimeRanges: [CMTimeRange] = []
  private nonisolated(unsafe) var _seekableTimeRanges: [CMTimeRange] = []
  package private(set) var bufferingState: BufferingState = .unknown

  nonisolated public var status: Status { _assumeMainActor { _status } }
  nonisolated public var error: (any Error)? { _assumeMainActor { _error } }
  nonisolated public var duration: CMTime { _assumeMainActor { _duration } }
  nonisolated public var loadedTimeRanges: [CMTimeRange] { _assumeMainActor { _loadedTimeRanges } }
  nonisolated public var seekableTimeRanges: [CMTimeRange] { _assumeMainActor { _seekableTimeRanges } }

  nonisolated public var isPlaybackLikelyToKeepUp: Bool {
    _assumeMainActor { bufferingState == .likelyToKeepUp || bufferingState == .full }
  }
  nonisolated public var isPlaybackBufferEmpty: Bool { _assumeMainActor { bufferingState == .empty } }
  nonisolated public var isPlaybackBufferFull: Bool { _assumeMainActor { bufferingState == .full } }
  package var metadata: [AVMetadataItem] { asset.commonMetadata }

  /// The largest rendition the adaptive player may pick; `.zero` leaves it free.
  nonisolated public var preferredMaximumResolution: CGSize {
    get { _assumeMainActor { _preferredMaximumResolution } }
    set { _assumeMainActor { _preferredMaximumResolution = newValue; _selectionRevision &+= 1 } }
  }
  /// The highest bit rate, in bits per second, the adaptive player may pick; 0 leaves it free.
  nonisolated public var preferredPeakBitRate: Double {
    get { _assumeMainActor { _preferredPeakBitRate } }
    set { _assumeMainActor { _preferredPeakBitRate = newValue; _selectionRevision &+= 1 } }
  }
  private nonisolated(unsafe) var _preferredMaximumResolution: CGSize = .zero
  private nonisolated(unsafe) var _preferredPeakBitRate: Double = 0

  internal func _noteSelectionChanged() {
    _assumeMainActor { _selectionRevision &+= 1 }
  }
  /// Options chosen with `select(_:in:)`, by characteristic; `_noneChosen` marks a group turned
  /// off (subtitles). A characteristic in neither is automatic.
  internal nonisolated(unsafe) var _chosenOptions: [String: AVMediaSelectionOption] = .init()
  internal nonisolated(unsafe) var _noneChosen: [String: Bool] = .init()
  /// Bumped by every preference or selection; read while the media view renders.
  private let _counters: _AVRevisionCounters
  internal var _selectionRevision: UInt64 {
    get { _counters.selection }
    set { _counters.selection = newValue }
  }

  @MainActor @preconcurrency public init(asset: AVAsset) {
    self.asset = asset
    _duration = asset.duration
    _counters = _AVRevisionCounters()
  }

  /// Apple's `init(url:)` is nonisolated, so it cannot delegate to the main-actor `init(asset:)`; it sets the same
  /// two stored properties itself.
  nonisolated public init(url: URL) {
    let asset = AVURLAsset(url: url)
    self.asset = asset
    _duration = asset.duration
    _counters = _assumeMainActor { _AVRevisionCounters() }
  }

  internal var adaptive: Bool { (asset as? AVURLAsset)?.requiresAdaptiveStreaming == true }
  internal var source: String {
    guard let asset = asset as? AVURLAsset else { return "" }
    return asset.url.absoluteString
  }

  /// Whether the source is an audio file. SwiftUI's `VideoPlayer` plays audio
  /// too; the browser needs an `<audio>` element for it. Decided from the
  /// path extension (ignoring query and fragment) or a `data:audio/` URL.
  internal var isAudioSource: Bool {
    let value = source
    if value.hasPrefix("data:audio/") { return true }
    var path = Substring(value)
    if let end = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = path[..<end] }
    guard let dot = path.lastIndex(of: ".") else { return false }
    switch path[path.index(after: dot)...].lowercased() {
    case "mp3", "m4a", "aac", "wav", "oga", "ogg", "opus", "flac", "weba", "caf", "aif", "aiff": return true
    default: return false
    }
  }

  @MainActor internal func _handle(event: _MediaEventName, backend: _MediaBackend) {
    currentTime = CMTime(seconds: backend.currentTime, preferredTimescale: 600)
    let ranges = backend.bufferedRanges.map { CMTimeRange(start: .seconds($0.start), end: .seconds($0.end)) }
    _loadedTimeRanges = ranges
    _seekableTimeRanges = backend.seekableRanges.map { CMTimeRange(start: .seconds($0.start), end: .seconds($0.end)) }
    switch event {
    case .loadedMetadata, .durationChange:
      if backend.duration.isFinite && !backend.duration.isNaN {
        _duration = CMTime(seconds: backend.duration, preferredTimescale: 600)
        if let urlAsset = asset as? AVURLAsset { urlAsset._setDuration(_duration) }
      }
      _status = .readyToPlay
      if bufferingState == .unknown { bufferingState = .empty }
    case .canPlay, .canPlayThrough, .playing, .progress:
      bufferingState = .likelyToKeepUp
    case .waiting, .stalled, .suspend, .emptied:
      bufferingState = .empty
    case .ended:
      bufferingState = .full
    case .error:
      _status = .failed
      let reason: String
      switch backend.errorCode {
      case 1: reason = " (MEDIA_ERR_ABORTED)"
      case 2: reason = " (MEDIA_ERR_NETWORK)"
      case 3: reason = " (MEDIA_ERR_DECODE)"
      case 4: reason = " (MEDIA_ERR_SRC_NOT_SUPPORTED)"
      default: reason = ""
      }
      _error = AVMediaError("The browser media element reported an error" + reason)
    case .play, .pause, .timeUpdate, .seeking, .seeked, .rateChange, .volumeChange,
         .enterPictureInPicture, .leavePictureInPicture:
      break
    }
    // The browser reports the end and the failure of playback as events; Apple posts both as notifications on the item.
    switch event {
    case .ended:
      NotificationCenter.default._post(name: AVPlayerItem.didPlayToEndTimeNotification, sender: self)
    case .error:
      NotificationCenter.default._post(name: AVPlayerItem.failedToPlayToEndTimeNotification, sender: self)
    default:
      break
    }
  }

  /// Posted when playback reaches the end of the item. The object is the item.
  @MainActor public static let didPlayToEndTimeNotification = Notification.Name("AVPlayerItemDidPlayToEndTimeNotification")
  /// Posted when playback of the item fails. The object is the item, whose `error` describes the failure.
  @MainActor public static let failedToPlayToEndTimeNotification = Notification.Name("AVPlayerItemFailedToPlayToEndTimeNotification")
}

/// Apple's `AVPlayerItemFailedToPlayToEndTimeErrorKey`: the key of the error in a failed-to-play notification's user
/// info. The notification carries no user info here; read the error from the item's `error`.
public let AVPlayerItemFailedToPlayToEndTimeErrorKey: String = "error"

// MARK: - Player

/// Playback state lives in Swift; `VideoPlayer`/`AudioPlayer` render what the player wants and the
/// browser host makes the element match (see `_DeclarativeMediaBackend`). `_renderRevision` changes
/// with every request, which is what makes the media view render again.
@MainActor public final class AVPlayer: ObservableObject {
  public enum Status: Int, Hashable, Sendable {
    case unknown
    case readyToPlay
    case failed
  }

  public enum TimeControlStatus: Int, Hashable, Sendable {
    case paused
    case waitingToPlayAtSpecifiedRate
    case playing
  }

  public enum ActionAtItemEnd: Int, Hashable, Sendable {
    case advance
    case pause
    case none
  }

  /// What `addPeriodicTimeObserver` returns (as `Any`, like Apple's); not an Apple type.
  package final class TimeObserverToken: Sendable {
    fileprivate let id: Int
    fileprivate init(id: Int) { self.id = id }
  }

  private struct PeriodicObserver {
    let interval: Double
    let callback: (CMTime) -> Void
    var lastFire: Double
  }

  private struct BoundaryObserver {
    let times: [Double]
    let callback: @Sendable () -> Void
  }

  /// A seek the element has not taken yet: `sequence` is its command's, what a `seeked` report names.
  private struct PendingSeek {
    let sequence: UInt64
    let completion: (@Sendable (Bool) -> Void)?
  }

  // Stored state is main-actor isolated (the class is); the `nonisolated` members are Apple's spelling over it.
  private nonisolated(unsafe) var _currentItem: AVPlayerItem?
  private nonisolated(unsafe) var _status: Status = .unknown
  private nonisolated(unsafe) var _timeControlStatus: TimeControlStatus = .paused
  private nonisolated(unsafe) var _actionAtItemEnd: ActionAtItemEnd = .pause
  private nonisolated(unsafe) var _automaticallyWaitsToMinimizeStalling = true
  private nonisolated(unsafe) var _defaultRate: Float = 1

  nonisolated public var currentItem: AVPlayerItem? { _assumeMainActor { _currentItem } }
  nonisolated public var status: Status { _assumeMainActor { _status } }
  nonisolated public var timeControlStatus: TimeControlStatus { _assumeMainActor { _timeControlStatus } }
  nonisolated public var actionAtItemEnd: ActionAtItemEnd {
    get { _assumeMainActor { _actionAtItemEnd } }
    set { _assumeMainActor { _actionAtItemEnd = newValue } }
  }
  nonisolated public var automaticallyWaitsToMinimizeStalling: Bool {
    get { _assumeMainActor { _automaticallyWaitsToMinimizeStalling } }
    set { _assumeMainActor { _automaticallyWaitsToMinimizeStalling = newValue } }
  }
  package var isPlaying: Bool { _assumeMainActor { backend.isPlaying } }

  nonisolated public var rate: Float {
    // Like AVPlayer's, zero while paused (and after the end), the playback rate while it plays or waits to.
    get { _assumeMainActor { backend.isPlaying ? Float(backend.rate) : 0 } }
    set {
      _assumeMainActor { backend.rate = Double(max(0, newValue)) }
      if newValue == 0 { pause() } else { playImmediately(atRate: newValue) }
    }
  }

  /// The rate `play()` starts at, as a playback speed chosen by the viewer.
  nonisolated public var defaultRate: Float {
    get { _assumeMainActor { _defaultRate } }
    // A paused player shows this rate (the speed menu's check), so a change draws again.
    set { _assumeMainActor { _defaultRate = newValue; _invalidate() } }
  }

  nonisolated public var volume: Float {
    get { _assumeMainActor { Float(backend.volume) } }
    set {
      _assumeMainActor {
        backend.volume = Double(min(max(0, newValue), 1))
        _invalidate()
      }
    }
  }

  nonisolated public var isMuted: Bool {
    get { _assumeMainActor { backend.muted } }
    set {
      _assumeMainActor {
        backend.muted = newValue
        _invalidate()
      }
    }
  }

  /// Requests the browser's native fullscreen presentation for the media element. Native/WASI
  /// hosts safely ignore the request. Not Apple API: AVKit's controls call it.
  package func requestFullscreen() { _assumeMainActor { _command("fullscreen") } }

  package func exitFullscreen() { _assumeMainActor { _command("exitfullscreen") } }

  /// Starts or stops Picture in Picture when the host supports it. The capability query is
  /// exposed so AVKit can hide unavailable affordances without importing browser types.
  package var isPictureInPictureSupported: Bool { _assumeMainActor { backend.supportsPictureInPicture } }
  package private(set) var isPictureInPictureActive: Bool {
    get { _assumeMainActor { _pictureInPictureActive } }
    set { _assumeMainActor { _pictureInPictureActive = newValue } }
  }
  private nonisolated(unsafe) var _pictureInPictureActive = false

  package func startPictureInPicture() {
    _assumeMainActor {
      backend.setPictureInPicture(true)
      _pictureInPictureActive = backend.isPictureInPictureActive
      _command("pip", "1")
    }
  }

  package func stopPictureInPicture() {
    _assumeMainActor {
      backend.setPictureInPicture(false)
      _pictureInPictureActive = backend.isPictureInPictureActive
      _command("pip", "0")
    }
  }

  internal let mediaID: String
  // Assigned by Apple's nonisolated initializers; every use after initialization is main-actor work.
  private nonisolated(unsafe) let backend: _MediaBackend
  /// Counts the items the player has had; the element echoes it, so samples of a replaced item are told apart.
  private nonisolated(unsafe) var itemGeneration: UInt64 = 0
  internal var _itemGeneration: UInt64 { itemGeneration }
  private nonisolated(unsafe) var observerID = 0
  private nonisolated(unsafe) var observers: [Int: PeriodicObserver] = .init()
  private nonisolated(unsafe) var boundaryObservers: [Int: BoundaryObserver] = .init()
  private nonisolated(unsafe) var pendingSeeks: [PendingSeek] = []
  /// Where the boundary observers last looked: a boundary fires when playback moves past it.
  private nonisolated(unsafe) var boundaryCursor = 0.0
  /// What the observers last saw of playback (moving, rate, waiting on a seek): a change is reported to them at once.
  private nonisolated(unsafe) var observedState: (advancing: Bool, rate: Double, holding: Bool) = (false, 1, false)
  private nonisolated(unsafe) var cancelObserverTimer: (() -> Void)?
  private nonisolated(unsafe) var timerKey = 0
  /// Bumped by every request the element has to carry out; read while the media view renders.
  private let _counters: _AVRevisionCounters
  internal var _renderRevision: UInt64 {
    get { _counters.render }
    set { _counters.render = newValue }
    // A bump is a write: it must not subscribe the view that is rendering (the player is created by that view's `@State`
    // initializer, see section 12.22).
    _modify { yield &_counters.render }
  }
  /// The newest one-shot request ("<sequence>:<verb>[:<argument>]"); the host runs each sequence once.
  nonisolated(unsafe) internal private(set) var _pendingCommand: String?
  private nonisolated(unsafe) var commandSequence: UInt64 = 0

  nonisolated public init(url: URL) {
    self.mediaID = "media-\(UUIDString.next())"
    self.backend = _assumeMainActor { _makeMediaBackend() }
    self._counters = _assumeMainActor { _AVRevisionCounters() }
    _assumeMainActor { replaceCurrentItem(with: AVPlayerItem(url: url)) }
  }

  nonisolated public init() {
    self.mediaID = "media-\(UUIDString.next())"
    self.backend = _assumeMainActor { _makeMediaBackend() }
    self._counters = _assumeMainActor { _AVRevisionCounters() }
  }

  nonisolated public init(playerItem: AVPlayerItem) {
    self.mediaID = "media-\(UUIDString.next())"
    self.backend = _assumeMainActor { _makeMediaBackend() }
    self._counters = _assumeMainActor { _AVRevisionCounters() }
    _assumeMainActor { replaceCurrentItem(with: playerItem) }
  }

  nonisolated public func replaceCurrentItem(with item: AVPlayerItem?) {
    _assumeMainActor {
      _currentItem = item
      itemGeneration &+= 1
      _status = item == nil ? .unknown : .unknown
      _timeControlStatus = .paused
      backend.pause()
      backend.reset()
      // The last request (a seek, say) belonged to the old item; an element for the new one must not replay it.
      _pendingCommand = nil
      _HeadlessPlayers.register(self, hasItem: item != nil)
      _interruptSeeks()
      _invalidate()
      _noteTransition()
    }
  }

  nonisolated public func play() {
    _assumeMainActor {
      guard currentItem != nil else { return }
      backend.rate = Double(max(0, defaultRate))
      backend.play()
      _updateTimeControl()
      _invalidate()
      _noteTransition()
    }
  }

  nonisolated public func playImmediately(atRate rate: Float) {
    _assumeMainActor {
      backend.rate = Double(max(0, rate))
      guard currentItem != nil else { return }
      backend.play()
      _updateTimeControl()
      _invalidate()
      _noteTransition()
    }
  }

  nonisolated public func pause() {
    _assumeMainActor {
      backend.pause()
      _updateTimeControl()
      _invalidate()
      _noteTransition()
    }
  }

  nonisolated public func seek(to time: CMTime) {
    _assumeMainActor { _seek(to: time, completion: nil) }
  }

  nonisolated public func seek(
    to time: CMTime,
    toleranceBefore: CMTime = .zero,
    toleranceAfter: CMTime = .zero,
    completionHandler: (@Sendable (Bool) -> Void)? = nil
  ) {
    _ = toleranceBefore
    _ = toleranceAfter
    _assumeMainActor { _seek(to: time, completion: completionHandler) }
  }

  /// The position, read at once: the last sample the element sent, advanced by the playback rate since (`_MediaMirror`), so
  /// it is right between samples and in the Worker, where the element cannot be asked.
  nonisolated public func currentTime() -> CMTime {
    _assumeMainActor { CMTime(seconds: backend.currentTime, preferredTimescale: 600) }
  }

  /// The failure of the current item, as AVPlayer reports it.
  nonisolated public var error: (any Error)? { _assumeMainActor { _currentItem?.error } }

  @discardableResult
  nonisolated public func addPeriodicTimeObserver(
    forInterval interval: CMTime,
    queue: dispatch_queue_t?,
    using block: @escaping @Sendable (CMTime) -> Void
  ) -> Any {
    let callback = block
    _ = queue
    return _assumeMainActor {
      let before = _observeInterval
      observerID += 1
      observers[observerID] = PeriodicObserver(interval: max(0.001, interval.seconds), callback: callback, lastFire: backend.currentTime)
      if _observeInterval != before { _invalidate() }
      _reschedule()
      return TimeObserverToken(id: observerID)
    }
  }

  /// Calls `block` each time playback moves past one of `times`.
  @discardableResult
  nonisolated public func addBoundaryTimeObserver(
    forTimes times: [NSValue],
    queue: dispatch_queue_t?,
    using block: @escaping @Sendable () -> Void
  ) -> Any {
    _ = queue
    let seconds = times.map { $0.timeValue.seconds }.filter { $0.isFinite && $0 >= 0 }
    return _assumeMainActor {
      observerID += 1
      if boundaryObservers.isEmpty { boundaryCursor = backend.currentTime }
      boundaryObservers[observerID] = BoundaryObserver(times: seconds, callback: block)
      _reschedule()
      return TimeObserverToken(id: observerID)
    }
  }

  nonisolated public func removeTimeObserver(_ observer: Any) {
    guard let token = observer as? TimeObserverToken else { return }
    _assumeMainActor {
      let before = _observeInterval
      observers.removeValue(forKey: token.id)
      boundaryObservers.removeValue(forKey: token.id)
      if _observeInterval != before { _invalidate() }
      _reschedule()
    }
  }

  // MARK: Time control

  /// Wanting to play is not playing: until the element has data and plays, the player waits, as AVPlayer does.
  @MainActor private func _updateTimeControl() {
    if !backend.isPlaying {
      _timeControlStatus = .paused
    } else if !backend.reportsPlayback || backend.isAdvancing {
      _timeControlStatus = .playing
    } else {
      _timeControlStatus = .waitingToPlayAtSpecifiedRate
    }
  }

  @MainActor private func _seek(to time: CMTime, completion: (@Sendable (Bool) -> Void)?) {
    let seconds = time.seconds.isFinite ? max(0, time.seconds) : 0
    // A seek in flight is interrupted by the next: its handler hears `false` now, the new one's hears the result.
    _interruptSeeks()
    let confirmed = backend.seek(to: seconds)
    _command("seek", String(seconds))
    if confirmed {
      backend.holdsTime = true
      pendingSeeks.append(PendingSeek(sequence: commandSequence, completion: completion))
      _noteTransition()
    } else {
      // Nothing carries it out (no element): the target is the position.
      currentItem?._handle(event: .seeked, backend: backend)
      boundaryCursor = backend.currentTime
      completion?(true)
      _notifyObservers(force: true)
    }
    _reschedule()
  }

  @MainActor private func _interruptSeeks() {
    guard !pendingSeeks.isEmpty else { return }
    let interrupted = pendingSeeks
    pendingSeeks.removeAll()
    backend.holdsTime = false
    for seek in interrupted { seek.completion?(false) }
  }

  /// The element took the seeks up to `sequence`.
  @MainActor private func _completeSeeks(upTo sequence: UInt64) {
    let done = pendingSeeks.filter { $0.sequence <= sequence }
    guard !done.isEmpty else { return }
    pendingSeeks.removeAll { $0.sequence <= sequence }
    if pendingSeeks.isEmpty { backend.holdsTime = false }
    boundaryCursor = backend.currentTime
    for seek in done { seek.completion?(true) }
  }

  /// The shortest periodic interval in milliseconds when it is short enough to ask the host for a high-rate sample stream.
  private var _observeInterval: Int {
    var shortest = Double.infinity
    for observer in observers.values { shortest = min(shortest, observer.interval) }
    return shortest < 0.25 ? max(1, Int(shortest * 1000)) : 0
  }

  /// Tells the observers when playback starts, stops, changes speed or waits on a seek, not only when time advances.
  @discardableResult
  @MainActor private func _noteTransition() -> Bool {
    let state = (backend.isAdvancing, backend.playbackRate, backend.holdsTime)
    guard state != observedState else { _reschedule(); return false }
    observedState = state
    _notifyObservers(force: true)
    _reschedule()
    return true
  }

  /// Fires the periodic observers whose interval has passed (or all, when `force`d) and the boundaries playback has crossed.
  @MainActor private func _notifyObservers(force: Bool = false) {
    let now = backend.currentTime
    for id in Array(observers.keys) {
      guard var observer = observers[id] else { continue }
      let due = now - observer.lastFire >= observer.interval - Self.timerTolerance
      guard force || now < observer.lastFire || due else { continue }
      // Keep the cadence of the interval rather than that of the timer, unless time jumped or stood still.
      observer.lastFire = (force || !due || now - observer.lastFire >= observer.interval * 2) ? now : observer.lastFire + observer.interval
      observers[id] = observer
      observer.callback(CMTime(seconds: now, preferredTimescale: 600))
    }
    if now > boundaryCursor {
      // A timer may wake a few milliseconds before the boundary: it counts as crossed, and the cursor moves past it so the
      // next wake does not fire it again.
      let crossed = (boundaryCursor, now + Self.timerTolerance)
      var cursor = now
      for id in Array(boundaryObservers.keys) {
        guard let observer = boundaryObservers[id] else { continue }
        let hits = observer.times.filter { $0 > crossed.0 && $0 <= crossed.1 }
        if let latest = hits.max() {
          cursor = max(cursor, latest)
          observer.callback()
        }
      }
      boundaryCursor = cursor
    } else {
      boundaryCursor = now
    }
  }

  /// A timer may fire a little before the instant it was set for.
  private static var timerTolerance: Double { 0.004 }

  /// One timer for the next moment an observer is due, set from the mirror: the periodic ones every interval of media time
  /// (so every half interval of wall time at rate 2), a boundary when playback gets to it.
  @MainActor private func _reschedule() {
    cancelObserverTimer?()
    cancelObserverTimer = nil
    guard backend.reportsPlayback, backend.isAdvancing, !(observers.isEmpty && boundaryObservers.isEmpty) else { return }
    let now = backend.currentTime
    var wait = Double.infinity
    for observer in observers.values { wait = min(wait, max(0, observer.lastFire + observer.interval - now)) }
    for observer in boundaryObservers.values {
      for time in observer.times where time > boundaryCursor && time > now - Self.timerTolerance { wait = min(wait, max(0, time - now)) }
    }
    guard wait.isFinite else { return }
    let delay = max(0.001, wait / max(0.01, backend.playbackRate))
    // The timer must not keep the player alive (AVFoundation's does not retain either: a player nobody holds is deallocated
    // with its observers), and Embedded Swift has no `weak`. It holds a number; the table answers with the player while
    // it lives, and the player's `deinit` removes itself.
    if timerKey == 0 {
      _PlayerTable.next += 1
      timerKey = _PlayerTable.next
    }
    _PlayerTable.players[timerKey] = Unmanaged.passUnretained(self)
    let key = timerKey
    cancelObserverTimer = _MediaClock.schedule(delay) {
      _assumeMainActor {
        guard let live = _PlayerTable.players[key]?.takeUnretainedValue() else { return }
        live.cancelObserverTimer = nil
        live._notifyObservers()
        live._reschedule()
      }
    }
  }

  deinit {
    cancelObserverTimer?()
    let key = timerKey
    let id = mediaID
    _assumeMainActor {
      if key != 0 { _PlayerTable.players.removeValue(forKey: key) }
      _HeadlessPlayers.forget(id)
    }
  }

  // MARK: Renderer and host

  @MainActor private func _invalidate() {
    _renderRevision &+= 1
    _HeadlessMedia.invalidate()
  }

  @MainActor private func _command(_ verb: String, _ argument: String? = nil) {
    commandSequence &+= 1
    _pendingCommand = String(commandSequence) + ":" + verb + (argument.map { ":" + $0 } ?? "")
    _invalidate()
  }

  /// Takes in a `media-report` report from the browser host and tells the item and observers.
  @MainActor internal func _receive(_ payload: String) {
    guard let report = _MediaHostReport(payload), !report.namesItem || report.item == itemGeneration else { return }
    let wanted = (backend.isPlaying, backend.muted, backend.volume, backend.rate)
    let controls = _controlsSignature
    backend.apply(report)
    if report.event == .seeked {
      // A report from a host that does not number its seeks completes every one.
      _completeSeeks(upTo: report.hostTime == 0 ? .max : report.seekSequence)
    }
    _updateTimeControl()
    _handle(report.event)
    // The element changed on its own (native controls, a refused autoplay, the end): render the new
    // wish so the host does not undo it.
    // Controls drawn over the video (AVKit's) show waiting, failing, the end and Picture in Picture too.
    if wanted != (backend.isPlaying, backend.muted, backend.volume, backend.rate) || controls != _controlsSignature { _invalidate() }
  }

  /// Everything besides the wished state that AVKit's controls draw, so a report that changes one renders the view again.
  @MainActor private var _controlsSignature: UInt64 {
    var value = UInt64(_timeControlStatus.rawValue)
    value |= UInt64(_status.rawValue) << 2
    value |= UInt64(_currentItem?.status.rawValue ?? 0) << 4
    if _hasPlayableDuration { value |= 1 << 6 }
    if _isAtEnd { value |= 1 << 7 }
    if backend.isPictureInPictureActive { value |= 1 << 8 }
    if backend.errorCode != 0 { value |= 1 << 9 }
    return value
  }

  /// The item's duration is known and finite (a live stream has none): the controls can seek.
  @MainActor package var _hasPlayableDuration: Bool { backend.duration.isFinite && backend.duration > 0 }

  /// Playback stopped at the end of the item.
  @MainActor package var _isAtEnd: Bool {
    _hasPlayableDuration && !backend.isPlaying && backend.currentTime >= backend.duration - 0.05
  }

  /// What the page's media host should do for this player when no `VideoPlayer` shows it: the element it would render,
  /// as JSON (`{"id","kind","attrs"}`), or nil without an item.
  @MainActor internal func _headlessWish() -> String? {
    guard let item = currentItem, !item.source.isEmpty else { return nil }
    let audio = item.isAudioSource
    let node = _RenderNode.element(audio ? "audio" : "video")
    _renderMedia(into: node)
    node.attributes["preload"] = "metadata"
    if !audio { node.attributes["playsinline"] = "" }
    var out = "{\"id\":" + _jsonString(mediaID) + ",\"kind\":\"" + (audio ? "audio" : "video") + "\",\"attrs\":{"
    var first = true
    for key in node.attributes.keys.sorted() {
      if !first { out += "," }
      first = false
      out += _jsonString(key) + ":" + _jsonString(node.attributes[key] ?? "")
    }
    return out + "}}"
  }

  /// The attributes the browser host applies to the element (Tools/media-host.js).
  @MainActor internal func _renderMedia(into node: _RenderNode) {
    _ = _renderRevision
    node.attributes["data-player-id"] = mediaID
    if let item = currentItem, !item.source.isEmpty {
      if item.adaptive { node.attributes["data-media-source"] = item.source } else { node.attributes["src"] = item.source }
    }
    node.attributes["data-media-playing"] = backend.isPlaying ? "1" : "0"
    node.attributes["data-media-intent"] = String(backend.intent)
    node.attributes["data-media-muted"] = backend.muted ? "1" : "0"
    node.attributes["data-media-volume"] = String(backend.volume)
    node.attributes["data-media-rate"] = String(backend.rate)
    node.attributes["data-media-item"] = String(itemGeneration)
    // A short periodic time observer asks the host for a high-rate stream of samples (interval in milliseconds).
    if _observeInterval > 0 { node.attributes["data-media-observe"] = String(_observeInterval) }
    if let command = _pendingCommand { node.attributes["data-media-command"] = command }
    // Where a new element for this player starts: the same playback can move to another element
    // (an inline player handing over to a full-screen one), which would otherwise start at zero.
    if backend.currentTime > 0 { node.attributes["data-media-start"] = String(backend.currentTime) }
    node.events["media-report"] = _EventHandler(name: "media-report", action: { value in self._receive(value) })
    if let item = currentItem {
      item._renderSelection(into: node)
      node.events["media-tracks-report"] = _EventHandler(name: "media-tracks-report", action: { value in self.currentItem?._receiveTracks(value) })
    }
  }

  @MainActor private func _handle(_ event: _MediaEventName) {
    guard let item = currentItem else { return }
    item._handle(event: event, backend: backend)
    switch event {
    case .play, .playing:
      _status = .readyToPlay
    case .enterPictureInPicture:
      isPictureInPictureActive = true
    case .leavePictureInPicture:
      isPictureInPictureActive = false
    case .error:
      _status = .failed
    case .pause, .ended, .waiting, .stalled, .seeking, .seeked, .loadedMetadata, .durationChange, .canPlay, .canPlayThrough, .suspend,
         .emptied, .timeUpdate, .progress, .rateChange, .volumeChange:
      if status == .unknown { _status = .readyToPlay }
    }
    // As AVFoundation does, observers also hear when playback starts, stops, changes speed or lands a seek, not only when time
    // advances by their interval: a custom control has to see the end and every pause.
    if !_noteTransition() && (event == .seeked || event == .ended) { _notifyObservers(force: true) }
    _notifyObservers()
  }
}

/// A JSON string literal (the page parses the headless wishes).
private func _jsonString(_ value: String) -> String {
  // Per Unicode scalar: a quote, backslash or control character followed by a combining mark is one Character that no
  // case matched, and left the JSON of every headless player unreadable.
  var out = "\""
  for scalar in value.unicodeScalars {
    switch scalar {
    case "\"": out += "\\\""
    case "\\": out += "\\\\"
    case "\n": out += "\\n"
    case "\r": out += "\\r"
    case "\t": out += "\\t"
    default:
      if scalar.value < 0x20 {
        let digits = Array("0123456789abcdef")
        out += "\\u00" + String(digits[Int(scalar.value >> 4)]) + String(digits[Int(scalar.value & 15)])
      } else {
        out.unicodeScalars.append(scalar)
      }
    }
  }
  return out + "\""
}

/// Players that have an item are known to the page's media host, which plays them without a view and hands the element
/// over to a `VideoPlayer` that shows them (`_HeadlessMedia`). They are held until their item is removed.
/// Players by number, for the timers that must not own them.
@MainActor internal enum _PlayerTable {
  static var players: [Int: Unmanaged<AVPlayer>] = .init()
  static var next = 0
}

@MainActor internal enum _HeadlessPlayers {
  private static var players: [String: Unmanaged<AVPlayer>] = .init()
  private static var installed = false

  /// The player was deallocated: its element goes at the next publication.
  static func forget(_ id: String) {
    guard players.removeValue(forKey: id) != nil else { return }
    _ = BrowserTimer.schedule(after: 0) { _assumeMainActor { _HeadlessMedia.invalidate() } }
  }

  static func register(_ player: AVPlayer, hasItem: Bool) {
    guard _HeadlessMedia.isAvailable else { return }
    // Unretained, like AVFoundation's: a player nobody holds is gone, and `deinit` calls `forget`.
    if hasItem { players[player.mediaID] = Unmanaged.passUnretained(player) } else { players.removeValue(forKey: player.mediaID) }
    if !installed {
      installed = true
      _HeadlessMedia.wishes = {
        var out = "["
        var first = true
        for id in players.keys.sorted() {
          guard let wish = players[id]?.takeUnretainedValue()._headlessWish() else { continue }
          if !first { out += "," }
          first = false
          out += wish
        }
        return out + "]"
      }
      _HeadlessMedia.receive = { id, kind, payload in
        guard let player = players[id]?.takeUnretainedValue() else { return }
        if kind == "media-report" { player._receive(payload) } else { player.currentItem?._receiveTracks(payload) }
      }
    }
  }
}

// A tiny monotonic ID source that works in standard and Embedded WASM builds
// without Foundation UUID or random-number support.
private enum UUIDString {
  private final class Counter: @unchecked Sendable {
    private let lock = _RuntimeLock()
    private var value: UInt64 = 0
    func next() -> UInt64 { lock.withLock { value &+= 1; return value } }
  }
  private static let counter = Counter()
  static func next() -> String { String(counter.next(), radix: 36) }
}

// MARK: - SwiftUIWeb media views

/// The revision counters a player bumps when its render or selection changes. `@Published` needs the main actor on
/// Embedded, so the counters live in this main-actor object and the nonisolated player initializers create one.
@MainActor private final class _AVRevisionCounters: ObservableObject {
  @Published var render: UInt64 = 0
  @Published var selection: UInt64 = 0
}

/// The browser media element behind SwiftUIWebAVKit's `VideoPlayer`. Apple's `VideoPlayer` lives in AVKit, and its
/// controls are not a parameter of its SwiftUI initializers, so this type is package-internal.
package struct VideoPlayer: View {
  public typealias Body = Never
  package let player: AVPlayer
  package let showsPlaybackControls: Bool

  package init(player: AVPlayer, showsPlaybackControls: Bool = true) {
    self.player = player
    self.showsPlaybackControls = showsPlaybackControls
  }

  public func _render(in context: _RenderContext) -> _RenderNode {
    // SwiftUI's VideoPlayer plays audio files as well; they need `<audio>`.
    if player.currentItem?.isAudioSource == true {
      return AudioPlayer(player: player, showsPlaybackControls: showsPlaybackControls)._render(in: context)
    }
    let node = _RenderNode.element("video")
    player._renderMedia(into: node)
    node.attributes["playsinline"] = ""
    node.attributes["preload"] = "metadata"
    if showsPlaybackControls { node.attributes["controls"] = "" }
    node.attributes["aria-label"] = "Video player"
    node.classes = ["video-surface"]
    return node
  }
}

/// The `<audio>` element `VideoPlayer` uses for audio-only sources. Not Apple API, so package-internal.
package struct AudioPlayer: View {
  public typealias Body = Never
  package let player: AVPlayer
  package let showsPlaybackControls: Bool

  package init(player: AVPlayer, showsPlaybackControls: Bool = true) {
    self.player = player
    self.showsPlaybackControls = showsPlaybackControls
  }

  public func _render(in context: _RenderContext) -> _RenderNode {
    _ = context
    let node = _RenderNode.element("audio")
    player._renderMedia(into: node)
    node.attributes["preload"] = "metadata"
    if showsPlaybackControls { node.attributes["controls"] = "" }
    node.attributes["aria-label"] = "Audio player"
    node.classes = ["audio-surface"]
    return node
  }
}

// MARK: - NSValue

extension NSValue {
  /// Apple's `NSValue(time:)` (declared in Core Media): the boundary observers take their times as these.
  public convenience init(time: CMTime) {
    self.init(_words: [time.value, Int64(time.timescale), Int64(time.flags.rawValue), time.epoch])
  }

  /// The `CMTime` an `NSValue(time:)` holds.
  public var timeValue: CMTime {
    let words = _words
    guard words.count == 4 else { return .invalid }
    return CMTime(value: words[0], timescale: CMTimeScale(truncatingIfNeeded: words[1]), flags: CMTimeFlags(rawValue: UInt32(truncatingIfNeeded: words[2])), epoch: words[3])
  }
}
