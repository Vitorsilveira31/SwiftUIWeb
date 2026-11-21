import SwiftUIWeb

// Lottie animations for the web, with the API of Skip's SkipMotion (https://source.skip.dev/skip-motion): the same
// `MotionView` and `LottieContainer` that draw with lottie-ios on iOS and lottie-android on Android draw with lottie-web
// here, so a view that plays an animation builds for all three unchanged. An app maps the module with
// `-module-alias SkipMotion=SwiftUIWebMotion`.
//
// Swift renders what the view wants as attributes on one element, `div.motion-view`; `Tools/lottie-host.js` makes the
// player match them after every commit and reports the end of a playback as a `motion-complete` event:
//   data-motion-animation  the Lottie JSON text
//   data-motion-mode       "play" | "pause"
//   data-motion-loop       "once" | "loop" | "autoreverse" | "repeat:<n>" | "repeat-backwards:<n>"
//   data-motion-speed      the speed multiplier
//   data-motion-from, data-motion-to      the progress range a playback covers (playing, only when from < to)
//   data-motion-progress, data-motion-frame  where a paused animation stands (paused; progress wins)
//   data-motion-content-mode  "fit" | "fill"
// The host owns the element's children (`data-host-managed="*children"`): the SVG lottie-web draws.

/// Defines animation loop behavior.
public enum MotionLoopMode: Hashable, Sendable {
  /// Animation is played once then stops.
  case playOnce
  /// Animation will loop from beginning to end until stopped.
  case loop
  /// Animation will play forward, then backwards and loop until stopped.
  case autoReverse
  /// Animation will loop from beginning to end up to defined amount of times.
  case `repeat`(Int)
  /// Animation will play forward, then backwards a defined amount of times.
  case repeatBackwards(Int)

  var attributeValue: String {
    switch self {
    case .playOnce: return "once"
    case .loop: return "loop"
    case .autoReverse: return "autoreverse"
    case .repeat(let count): return "repeat:\(max(0, count))"
    case .repeatBackwards(let count): return "repeat-backwards:\(max(0, count))"
    }
  }
}

/// Defines how the animation content is scaled within its bounds.
public enum MotionContentMode: Hashable, Sendable {
  /// Scale the animation to fit within the bounds while preserving aspect ratio.
  case fit
  /// Scale the animation to fill the bounds while preserving aspect ratio, cropping if needed.
  case fill
}

/// A MotionView embeds an animation in the Lottie JSON format.
public struct MotionView: View {
  public typealias Body = Never

  let lottieContainer: LottieContainer?
  let animationSpeed: Double
  let loopMode: MotionLoopMode
  let isPlaying: Bool
  let contentMode: MotionContentMode
  let currentProgress: Double?
  let fromProgress: Double?
  let toProgress: Double?
  let enableMergePaths: Bool
  let currentFrame: CGFloat?
  let onComplete: ((Bool) -> Void)?

  public init(lottie lottieData: Data, animationSpeed: Double = 1.0, loopMode: MotionLoopMode = .loop, isPlaying: Bool = true, contentMode: MotionContentMode = .fit, currentProgress: Double? = nil, fromProgress: Double? = nil, toProgress: Double? = nil, enableMergePaths: Bool = false, currentFrame: CGFloat? = nil, onComplete: ((Bool) -> Void)? = nil) {
    // As on iOS and Android, data that is not a Lottie animation draws nothing.
    self.lottieContainer = try? LottieContainer(data: lottieData)
    self.animationSpeed = animationSpeed
    self.loopMode = loopMode
    self.isPlaying = isPlaying
    self.contentMode = contentMode
    self.currentProgress = currentProgress
    self.fromProgress = fromProgress
    self.toProgress = toProgress
    self.enableMergePaths = enableMergePaths
    self.currentFrame = currentFrame
    self.onComplete = onComplete
  }

  public init(lottie lottieContainer: LottieContainer, animationSpeed: Double = 1.0, loopMode: MotionLoopMode = .loop, isPlaying: Bool = true, contentMode: MotionContentMode = .fit, currentProgress: Double? = nil, fromProgress: Double? = nil, toProgress: Double? = nil, enableMergePaths: Bool = false, currentFrame: CGFloat? = nil, onComplete: ((Bool) -> Void)? = nil) {
    self.lottieContainer = lottieContainer
    self.animationSpeed = animationSpeed
    self.loopMode = loopMode
    self.isPlaying = isPlaying
    self.contentMode = contentMode
    self.currentProgress = currentProgress
    self.fromProgress = fromProgress
    self.toProgress = toProgress
    self.enableMergePaths = enableMergePaths
    self.currentFrame = currentFrame
    self.onComplete = onComplete
  }

  public func _render(in context: _RenderContext) -> _RenderNode {
    _ = context
    // An animation that did not load draws nothing, as `if let lottieContainer` does on iOS.
    guard let lottieContainer else { return _RenderNode.empty() }
    let node = _RenderNode.element("div")
    node.classes = ["motion-view"]
    node.attributes["data-host-managed"] = "*children"
    node.attributes["data-motion-animation"] = lottieContainer.json
    node.attributes["data-motion-loop"] = loopMode.attributeValue
    node.attributes["data-motion-speed"] = String(animationSpeed)
    node.attributes["data-motion-content-mode"] = contentMode == .fill ? "fill" : "fit"
    // The playback SkipMotion asks lottie-ios for: a range only when it runs forward, a paused position from the progress
    // first and the frame second (lottie-web plays merge paths without being asked, so `enableMergePaths` changes nothing).
    if isPlaying {
      node.attributes["data-motion-mode"] = "play"
      if let from = fromProgress, let to = toProgress, from < to {
        node.attributes["data-motion-from"] = String(from)
        node.attributes["data-motion-to"] = String(to)
      }
    } else {
      node.attributes["data-motion-mode"] = "pause"
      if let progress = currentProgress {
        node.attributes["data-motion-progress"] = String(progress)
      } else if let frame = currentFrame {
        node.attributes["data-motion-frame"] = String(frame)
      }
    }
    if let onComplete {
      node.events["motion-complete"] = _EventHandler(name: "motion-complete", action: { (value: String) in
        onComplete(value == "1")
      })
    }
    return node
  }
}

/// A container for Lottie data, which is an After Effects/Bodymovin JSON composition model.
///
/// This is the serialized model from which the animation will be created. It is designed to be stateless, cacheable, and shareable.
/// The format is described at [https://lottie.github.io/lottie-spec/](https://lottie.github.io/lottie-spec/).
///
/// On the web this holds the JSON text, which lottie-web draws, and the composition's header (its frames and size).
public struct LottieContainer: Sendable {
  let json: String
  let header: LottieHeader

  /// Creates a Lottie container with the data represented by the given Lottie JSON.
  public init(data lottieData: Data) throws {
    let bytes = Array(lottieData)
    guard let header = LottieHeader(scanning: bytes) else { throw LottieContainerError.notAnAnimation }
    self.header = header
    self.json = String(decoding: bytes, as: UTF8.self)
  }

  public var duration: TimeInterval {
    header.framerate > 0 ? (header.endFrame - header.startFrame) / header.framerate : 0
  }

  public var startFrame: CGFloat { header.startFrame }

  public var endFrame: CGFloat { header.endFrame }

  public var framerate: Double { header.framerate }

  public var width: Double { bounds.width }

  public var height: Double { bounds.height }

  public var bounds: CGRect { CGRect(x: 0, y: 0, width: header.width, height: header.height) }
}

enum LottieContainerError: Error {
  case notAnAnimation
}

/// The top-level numbers of a Lottie composition: `ip` and `op` (its first and last frame), `fr` (frames per second),
/// `w` and `h` (its size). They are read by one pass over the object's top level, which skips every nested value without
/// building it: a composition is mostly layers, which lottie-web parses itself.
struct LottieHeader: Hashable, Sendable {
  var startFrame: Double = 0
  var endFrame: Double = 0
  var framerate: Double = 0
  var width: Double = 0
  var height: Double = 0

  /// Nil when the bytes are not a JSON object with a positive frame rate, a last frame after the first, and layers.
  init?(scanning bytes: [UInt8]) {
    var scanner = JSONTopLevelScanner(bytes: bytes)
    var found: Set<String> = []
    let complete = scanner.scanObject { key, scanner in
      switch key {
      case "ip", "op", "fr", "w", "h":
        guard let number = scanner.number() else { return false }
        found.insert(key)
        switch key {
        case "ip": startFrame = number
        case "op": endFrame = number
        case "fr": framerate = number
        case "w": width = number
        default: height = number
        }
        return true
      case "layers":
        found.insert(key)
        return scanner.skipValue()
      default:
        return scanner.skipValue()
      }
    }
    guard complete, found.isSuperset(of: ["ip", "op", "fr", "layers"]), framerate > 0, endFrame > startFrame else { return nil }
  }
}

/// A forward reader of JSON text that visits the keys of the top-level object and skips the values it is not asked for.
struct JSONTopLevelScanner {
  private let bytes: [UInt8]
  private var index = 0

  init(bytes: [UInt8]) { self.bytes = bytes }

  /// Calls `visit` with each key of the top-level object, positioned at its value, which `visit` must consume (a number
  /// or a skip). False when the text is not a well-formed object or `visit` returns false.
  mutating func scanObject(_ visit: (String, inout JSONTopLevelScanner) -> Bool) -> Bool {
    skipWhitespace()
    // A UTF-8 byte order mark before the object.
    if index + 2 < bytes.count, bytes[index] == 0xEF, bytes[index + 1] == 0xBB, bytes[index + 2] == 0xBF { index += 3; skipWhitespace() }
    guard consume(UInt8(ascii: "{")) else { return false }
    skipWhitespace()
    if consume(UInt8(ascii: "}")) { return true }
    while true {
      skipWhitespace()
      guard let key = string() else { return false }
      skipWhitespace()
      guard consume(UInt8(ascii: ":")) else { return false }
      skipWhitespace()
      guard visit(key, &self) else { return false }
      skipWhitespace()
      if consume(UInt8(ascii: ",")) { continue }
      return consume(UInt8(ascii: "}"))
    }
  }

  /// A JSON number at the current position.
  mutating func number() -> Double? {
    var negative = false
    if consume(UInt8(ascii: "-")) { negative = true }
    var value = 0.0
    var digits = 0
    while index < bytes.count, let digit = Self.digit(bytes[index]) { value = value * 10 + Double(digit); index += 1; digits += 1 }
    guard digits > 0 else { return nil }
    if consume(UInt8(ascii: ".")) {
      var scale = 0.1
      var fraction = 0
      while index < bytes.count, let digit = Self.digit(bytes[index]) { value += Double(digit) * scale; scale /= 10; index += 1; fraction += 1 }
      guard fraction > 0 else { return nil }
    }
    if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
      index += 1
      var exponentNegative = false
      if consume(UInt8(ascii: "-")) { exponentNegative = true } else { _ = consume(UInt8(ascii: "+")) }
      var exponent = 0
      var exponentDigits = 0
      while index < bytes.count, let digit = Self.digit(bytes[index]) { exponent = min(exponent * 10 + digit, 400); index += 1; exponentDigits += 1 }
      guard exponentDigits > 0 else { return nil }
      for _ in 0..<exponent { value = exponentNegative ? value / 10 : value * 10 }
    }
    return negative ? -value : value
  }

  /// Moves past the value at the current position (any JSON value, nested ones included).
  mutating func skipValue() -> Bool {
    skipWhitespace()
    guard index < bytes.count else { return false }
    switch bytes[index] {
    case UInt8(ascii: "\""):
      return string() != nil
    case UInt8(ascii: "{"), UInt8(ascii: "["):
      var depth = 0
      while index < bytes.count {
        switch bytes[index] {
        case UInt8(ascii: "\""):
          guard string() != nil else { return false }
          continue
        case UInt8(ascii: "{"), UInt8(ascii: "["):
          depth += 1
        case UInt8(ascii: "}"), UInt8(ascii: "]"):
          depth -= 1
          if depth == 0 { index += 1; return true }
        default:
          break
        }
        index += 1
      }
      return false
    default:
      // A number, true, false or null: up to the next delimiter.
      let start = index
      while index < bytes.count {
        let byte = bytes[index]
        if byte == UInt8(ascii: ",") || byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]") || Self.isWhitespace(byte) { break }
        index += 1
      }
      return index > start
    }
  }

  /// The string at the current position, its escapes kept as written (the keys this reads have none).
  private mutating func string() -> String? {
    guard consume(UInt8(ascii: "\"")) else { return nil }
    let start = index
    while index < bytes.count {
      let byte = bytes[index]
      if byte == UInt8(ascii: "\\") { index += 2; continue }
      if byte == UInt8(ascii: "\"") {
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        index += 1
        return text
      }
      index += 1
    }
    return nil
  }

  private mutating func consume(_ byte: UInt8) -> Bool {
    guard index < bytes.count, bytes[index] == byte else { return false }
    index += 1
    return true
  }

  private mutating func skipWhitespace() {
    while index < bytes.count, Self.isWhitespace(bytes[index]) { index += 1 }
  }

  private static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
  }

  private static func digit(_ byte: UInt8) -> Int? {
    byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") ? Int(byte - UInt8(ascii: "0")) : nil
  }
}
