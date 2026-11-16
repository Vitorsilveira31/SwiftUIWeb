@_spi(Renderer) import SwiftUIWebCore
import SwiftUIWeb

// MARK: - Media selection (subtitles, audio languages) and variants (renditions)
//
// The same shapes as AVFoundation: `AVURLAsset.loadMediaSelectionGroup(for:)`, `load(.variants)`,
// `AVPlayerItem.select(_:in:)`, `currentMediaSelection`, `preferredMaximumResolution` and
// `preferredPeakBitRate`. In the browser the media host learns the tracks from the adaptive player
// (Shaka) and reports them as a `media-tracks-report` event; the wished selection goes back as
// attributes on the media element (see `AVPlayerItem._renderSelection(into:)`).

/// What a group of alternative tracks is for.
public struct AVMediaCharacteristic: RawRepresentable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  /// Alternative audio: languages, descriptions.
  public static let audible = AVMediaCharacteristic(rawValue: "AVMediaCharacteristicAudible")
  /// Subtitles and captions.
  public static let legible = AVMediaCharacteristic(rawValue: "AVMediaCharacteristicLegible")
  public static let visual = AVMediaCharacteristic(rawValue: "AVMediaCharacteristicVisual")
}

/// One alternative of a selection group, such as the Portuguese subtitles.
public final class AVMediaSelectionOption: @unchecked Sendable {
  public let displayName: String
  /// The BCP 47 language tag, when the stream declares one.
  public let extendedLanguageTag: String?
  public let mediaType: AVMediaType
  /// How the host finds the track again (a Shaka text track id, the index of a `<track>`, or "language/role" for audio).
  package let _identifier: String

  internal init(identifier: String, displayName: String, extendedLanguageTag: String?, mediaType: AVMediaType) {
    _identifier = identifier
    self.displayName = displayName
    self.extendedLanguageTag = extendedLanguageTag
    self.mediaType = mediaType
  }

  public func hasMediaCharacteristic(_ characteristic: AVMediaCharacteristic) -> Bool {
    if mediaType == .audio { return characteristic == .audible }
    if mediaType == .subtitle { return characteristic == .legible }
    if mediaType == .video { return characteristic == .visual }
    return false
  }
}

/// The mutually exclusive alternatives for one characteristic.
public final class AVMediaSelectionGroup: @unchecked Sendable {
  public let options: [AVMediaSelectionOption]
  /// Subtitles can be off; audio always plays one option.
  public let allowsEmptySelection: Bool
  public let defaultOption: AVMediaSelectionOption?
  internal let _characteristic: AVMediaCharacteristic

  internal init(characteristic: AVMediaCharacteristic, options: [AVMediaSelectionOption], defaultOption: AVMediaSelectionOption?) {
    _characteristic = characteristic
    self.options = options
    self.allowsEmptySelection = characteristic == .legible
    self.defaultOption = defaultOption
  }
}

/// A player item's chosen options, one per group.
public final class AVMediaSelection: @unchecked Sendable {
  private let selected: [String: AVMediaSelectionOption]

  internal init(selected: [String: AVMediaSelectionOption]) { self.selected = selected }

  public func selectedMediaOption(in group: AVMediaSelectionGroup) -> AVMediaSelectionOption? {
    selected[group._characteristic.rawValue]
  }
}

/// One rendition of an adaptive stream.
public final class AVAssetVariant: @unchecked Sendable {
  public final class VideoAttributes: @unchecked Sendable {
    public let presentationSize: CGSize
    internal init(presentationSize: CGSize) { self.presentationSize = presentationSize }
  }

  public let videoAttributes: VideoAttributes?
  public let peakBitRate: Double?
  public let averageBitRate: Double?

  internal init(presentationSize: CGSize?, peakBitRate: Double?) {
    videoAttributes = presentationSize.map { VideoAttributes(presentationSize: $0) }
    self.peakBitRate = peakBitRate
    averageBitRate = nil
  }
}

/// A property of an asset that loads asynchronously, as `asset.load(.variants)`.
public class AVPartialAsyncProperty<Root>: @unchecked Sendable {
  internal init() {}
}

public final class AVAsyncProperty<Root, Value>: AVPartialAsyncProperty<Root>, @unchecked Sendable {
  internal let read: (Root) -> Value
  internal init(read: @escaping (Root) -> Value) { self.read = read }
}

extension AVPartialAsyncProperty where Root: AVAsset {
  /// The renditions of an adaptive stream; empty for a plain file.
  public static var variants: AVAsyncProperty<Root, [AVAssetVariant]> {
    AVAsyncProperty { $0._tracks?.variants ?? [] }
  }
}

/// What the host reported about an asset's tracks.
internal struct _MediaTracks {
  var variants: [AVAssetVariant] = []
  var audible: [AVMediaSelectionOption] = []
  var legible: [AVMediaSelectionOption] = []
  /// The options playing (audio) or shown (subtitles) right now, by characteristic.
  var active: [String: AVMediaSelectionOption] = .init()

  func options(for characteristic: AVMediaCharacteristic) -> [AVMediaSelectionOption] {
    switch characteristic {
    case .audible: audible
    case .legible: legible
    default: []
    }
  }

  /// One record per line, tab-separated: `v w h bandwidth`, `a id language label active`,
  /// `t id language label active`.
  init(_ payload: String) {
    for line in payload.split(separator: "\n") {
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      guard let kind = fields.first else { continue }
      if kind == "v", fields.count >= 4 {
        let width = Double(fields[1]) ?? 0, height = Double(fields[2]) ?? 0
        let size = width > 0 && height > 0 ? CGSize(width: width, height: height) : nil
        variants.append(AVAssetVariant(presentationSize: size, peakBitRate: Double(fields[3]).flatMap { $0 > 0 ? $0 : nil }))
      } else if kind == "a" || kind == "t", fields.count >= 5 {
        let language = fields[2].isEmpty ? nil : fields[2]
        let name = fields[3].isEmpty ? (language ?? fields[1]) : fields[3]
        let option = AVMediaSelectionOption(
          identifier: fields[1], displayName: name, extendedLanguageTag: language,
          mediaType: kind == "a" ? .audio : .subtitle
        )
        let characteristic: AVMediaCharacteristic = kind == "a" ? .audible : .legible
        if kind == "a" { audible.append(option) } else { legible.append(option) }
        if fields[4] == "1" { active[characteristic.rawValue] = option }
      }
    }
  }
}

extension AVAsset {
  /// Suspends until the host reports the tracks; a cancelled task stops waiting (with no tracks),
  /// so a screen left before its video loaded does not keep its loader alive.
  @MainActor
  internal func _loadedTracks() async -> _MediaTracks {
    if let tracks = _tracks { return tracks }
    _trackWaiterID &+= 1
    let id = _trackWaiterID
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        if Task.isCancelled { continuation.resume() } else { _trackWaiters[id] = continuation }
      }
    } onCancel: {
      Task { @MainActor in self._trackWaiters.removeValue(forKey: id)?.resume() }
    }
    return _tracks ?? _MediaTracks("")
  }
}

extension AVURLAsset {
  /// The subtitles or audio alternatives of the asset, or nil when it has none. Waits until the
  /// player has loaded the stream.
  public func loadMediaSelectionGroup(for characteristic: AVMediaCharacteristic) async throws -> AVMediaSelectionGroup? {
    let tracks = await _loadedTracks()
    let options = tracks.options(for: characteristic)
    guard !options.isEmpty else { return nil }
    let fallback = characteristic == .audible ? options.first : nil
    return AVMediaSelectionGroup(characteristic: characteristic, options: options, defaultOption: tracks.active[characteristic.rawValue] ?? fallback)
  }

  /// A `media-tracks-report` report: the asset's tracks are known, or changed.
  @MainActor
  internal func _receiveTracks(_ payload: String) {
    _tracks = _MediaTracks(payload)
    let waiters = _trackWaiters
    _trackWaiters = .init()
    for (_, waiter) in waiters { waiter.resume() }
  }
}

extension AVPlayerItem {
  /// Chooses an option of a group; nil turns the group off where it allows that (subtitles).
  nonisolated public func select(_ mediaSelectionOption: AVMediaSelectionOption?, in mediaSelectionGroup: AVMediaSelectionGroup) {
    _assumeMainActor {
      let key = mediaSelectionGroup._characteristic.rawValue
      if let option = mediaSelectionOption {
        _chosenOptions[key] = option
        _noneChosen[key] = nil
      } else {
        guard mediaSelectionGroup.allowsEmptySelection else { return }
        _chosenOptions[key] = nil
        _noneChosen[key] = true
      }
      _noteSelectionChanged()
    }
  }

  /// The chosen options, or for a group left automatic what the player plays or shows now.
  nonisolated public var currentMediaSelection: AVMediaSelection {
    _assumeMainActor {
      var selected = (asset as? AVURLAsset)?._tracks?.active ?? .init()
      for (key, _) in _noneChosen { selected[key] = nil }
      for (key, option) in _chosenOptions { selected[key] = option }
      return AVMediaSelection(selected: selected)
    }
  }

  /// The tracks of this item's stream arrived or changed.
  @MainActor internal func _receiveTracks(_ payload: String) {
    (asset as? AVURLAsset)?._receiveTracks(payload)
    // A selection rendered against the old tracks must be drawn again (the captions menu lists them).
    _noteSelectionChanged()
    objectWillChange.send()
  }

  /// The group of one characteristic as the host reported the stream's tracks, for the controls' menus, which cannot wait
  /// for `loadMediaSelectionGroup(for:)`. Nil when the stream has no alternatives of that kind (no legible track, no alternate audio).
  @MainActor package func _selectionGroup(for characteristic: AVMediaCharacteristic) -> AVMediaSelectionGroup? {
    guard let tracks = (asset as? AVURLAsset)?._tracks else { return nil }
    let options = tracks.options(for: characteristic)
    guard !options.isEmpty else { return nil }
    let fallback = characteristic == .audible ? options.first : nil
    return AVMediaSelectionGroup(
      characteristic: characteristic, options: options, defaultOption: tracks.active[characteristic.rawValue] ?? fallback)
  }

  /// The wished rendition limits and options, as the media host reads them
  /// (Tools/media-host.js); an absent attribute leaves the choice to the player.
  @MainActor internal func _renderSelection(into node: _RenderNode) {
    _ = _selectionRevision
    let size = preferredMaximumResolution
    if size.width > 0 || size.height > 0 {
      // Whole numbers in Int64 and bounded: the values can come back from a manifest's variants, and Int is 32 bits in the
      // browser build.
      node.attributes["data-media-max-size"] = _mediaWhole(size.width) + "x" + _mediaWhole(size.height)
    }
    if preferredPeakBitRate > 0 { node.attributes["data-media-peak-bitrate"] = _mediaWhole(preferredPeakBitRate) }
    let audible = AVMediaCharacteristic.audible.rawValue, legible = AVMediaCharacteristic.legible.rawValue
    if let option = _chosenOptions[audible] { node.attributes["data-media-audio"] = option._identifier }
    if let option = _chosenOptions[legible] {
      node.attributes["data-media-text"] = option._identifier
    } else if _noneChosen[legible] == true {
      node.attributes["data-media-text"] = "off"
    }
  }
}

/// A non-negative whole number for a media attribute, saturated at 1e15 (no real size or bit rate is larger).
private func _mediaWhole(_ value: Double) -> String {
  guard value.isFinite, value > 0 else { return "0" }
  return String(Int64(min(value, 1e15)))
}
