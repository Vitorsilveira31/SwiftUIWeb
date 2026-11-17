// More Foundation and Dispatch for the browser build: notifications, queues, timers, sleeping by `Duration`,
// bundle resources, printf-style formatting of integers. Browser builds only.
import SwiftUIWebBrowserIO
@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures
@_spi(Renderer) import SwiftUIWebLocking

// MARK: Defaults and keyed archives

/// `@AppStorage("key") var data: Data?`, kept as base64 text in the defaults.
extension AppStorage where Value == Data? {
  public init(_ key: String, store: UserDefaults? = nil) {
    let store = store ?? .standard
    self.init(initial: nil, key: key, read: { store.string(forKey: key).flatMap { Data(base64Encoded: $0) }.map { Optional($0) } }, write: { value in
      if let value { store.set(value.base64EncodedString(), forKey: key) } else { store.removeObject(forKey: key) }
    })
  }
}

public let NSEC_PER_SEC: UInt64 = 1_000_000_000
public let NSEC_PER_MSEC: UInt64 = 1_000_000

/// What `NSKeyedArchiver` can round-trip here: classes that spell out their own bytes.
public protocol _KeyedArchivable: AnyObject {
  static func _unarchive(_ data: Data) -> Self?
}

public enum NSKeyedArchiver {
  public static func archivedData(withRootObject object: Any, requiringSecureCoding: Bool) throws -> Data {
    guard let archivable = object as? NSObject else { throw _KeyedArchiveError.notArchivable }
    return try archivable._keyedArchiveBytes()
  }
}

public enum NSKeyedUnarchiver {
  public static func unarchivedObject<T: _KeyedArchivable>(ofClass cls: T.Type, from data: Data) throws -> T? {
    T._unarchive(data)
  }
}

// MARK: Notifications

public protocol NSObjectProtocol: AnyObject {}
extension NSObject: NSObjectProtocol, Hashable {
  public static func == (lhs: NSObject, rhs: NSObject) -> Bool { lhs.isEqual(rhs) }
  public func hash(into hasher: inout Hasher) { hasher.combine(hash) }
}

public struct Notification: Sendable {
  public struct Name: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
  }
  public var name: Name
  public init(name: Notification.Name) { self.name = name }
}

/// Apple's `NSNotification.Name` is the name type `Notification.Name` (Apple spells it through `NSNotification` in
/// the notification-center signatures), so the same spelling works here.
public typealias NSNotification = Notification

extension Notification.Name {
  /// Apple's `NSHTTPCookieManagerCookiesChangedNotification` (imported by Swift as `.NSHTTPCookieManagerCookiesChanged`):
  /// posted when the page's cookies change, from any tab or a
  /// server response, after the Embedded worker's cookie mirror has been refreshed.
  public static let NSHTTPCookieManagerCookiesChanged = Notification.Name("NSHTTPCookieManagerCookiesChangedNotification")
}

public final class NotificationObserverToken: NSObjectProtocol, @unchecked Sendable {
  let id: Int
  let name: Notification.Name
  /// The only sender whose notifications the observer takes; nil takes every sender's.
  let sender: AnyObject?
  let handler: @Sendable (Notification) -> Void
  init(id: Int, name: Notification.Name, sender: AnyObject?, handler: @escaping @Sendable (Notification) -> Void) {
    self.id = id; self.name = name; self.sender = sender; self.handler = handler
  }
}

public final class NotificationCenter: @unchecked Sendable {
  public static let `default` = NotificationCenter()
  /// Native hosts post, observe and cancel from several threads, so the observer list is guarded; handlers run outside the
  /// lock (the browser has one thread and the lock costs nothing there).
  private let lock = _RuntimeLock(recursive: false)
  private var observers: [NotificationObserverToken] = []
  private var nextID = 0
  public init() {}

  /// Apple's `post(name:object:)`. Embedded Swift cannot cast `Any` to a class, so there an observer that asked for
  /// one sender is reached only by the framework's own posts (`_post(name:sender:)`); the full language compares the
  /// object with the sender the observer asked for, as Foundation does.
  public func post(name aName: NSNotification.Name, object anObject: Any?) {
    #if hasFeature(Embedded)
      _post(name: aName, sender: nil)
    #else
      _post(name: aName, sender: anObject.map { $0 as AnyObject })
    #endif
  }

  /// Posts `name` from `sender` (no sender when nil): observers that asked for a different sender are skipped.
  package func _post(name aName: NSNotification.Name, sender anObject: AnyObject?) {
    let notification = Notification(name: aName)
    let current = lock.withLock { observers }
    for observer in current where observer.name == aName || observer.name == Self.anyName {
      if let sender = observer.sender, anObject !== sender { continue }
      observer.handler(notification)
    }
  }

  @discardableResult
  public func addObserver(forName name: NSNotification.Name?, object obj: Any?, queue: OperationQueue?, using block: @escaping @Sendable (Notification) -> Void) -> any NSObjectProtocol {
    // A nil name takes every notification, and an object takes only that sender's, as Foundation does. Embedded Swift
    // cannot cast `Any` to a class, so there the sender filter applies to the framework's own posts only.
    #if hasFeature(Embedded)
      return add(name: name ?? Self.anyName, block)
    #else
      return add(name: name ?? Self.anyName, sender: obj.map { $0 as AnyObject }, block)
    #endif
  }

  /// The name an observer of every notification is registered under; no posted name can equal it.
  private static let anyName = Notification.Name("\u{0}any-notification")

  private func add(name: Notification.Name, sender: AnyObject? = nil, _ block: @escaping @Sendable (Notification) -> Void) -> NotificationObserverToken {
    lock.withLock {
      nextID += 1
      let token = NotificationObserverToken(id: nextID, name: name, sender: sender, handler: block)
      observers.append(token)
      return token
    }
  }

  public func removeObserver(_ observer: Any) {
    guard let token = observer as? NotificationObserverToken else { return }
    lock.withLock { observers.removeAll { $0.id == token.id } }
  }

  /// The subscription used by `publisher(for:)` (see WebCombine): returns a cancel closure.
  public func _subscribe(to name: Notification.Name, _ handler: @escaping @Sendable (Notification) -> Void) -> @Sendable () -> Void {
    let token = add(name: name, handler)
    return { [self] in self.removeObserver(token) }
  }

  /// Observes `name` from `sender` (every sender when nil) until the returned closure runs.
  func _observe(name: Notification.Name, sender: AnyObject?, _ handler: @escaping @Sendable (Notification) -> Void) -> @Sendable () -> Void {
    let token = add(name: name, sender: sender, handler)
    return { [self] in self.removeObserver(token) }
  }
}

extension NotificationCenter {
  /// Apple's `notifications(named:object:)`: an `AsyncSequence` of the notifications posted under `name` (from `object`,
  /// when one is given). The observer is registered now, so a notification posted before the iteration starts waits for
  /// it. The observer is removed when the iteration ends, when the task is cancelled, or when the sequence is released.
  @preconcurrency public func notifications(named name: Notification.Name, object: (any AnyObject & Sendable)? = nil) -> NotificationCenter.Notifications {
    let buffer = _NotificationBuffer()
    buffer.stopObserving(_observe(name: name, sender: object) { buffer.deliver($0) })
    return NotificationCenter.Notifications(lease: _NotificationLease(buffer: buffer))
  }

  /// `NotificationCenter.Notifications`: the notifications of one `notifications(named:object:)` call.
  public final class Notifications: AsyncSequence, Sendable {
    public typealias Element = Notification

    public struct Iterator: AsyncIteratorProtocol {
      public typealias Element = Notification
      private let lease: _NotificationLease

      fileprivate init(lease: _NotificationLease) { self.lease = lease }

      public mutating func next() async -> Notification? { await lease.buffer.next() }
    }

    private let lease: _NotificationLease

    fileprivate init(lease: _NotificationLease) { self.lease = lease }

    public func makeAsyncIterator() -> Iterator { Iterator(lease: lease) }
  }
}

/// The notifications a `Notifications` sequence has not yet taken, and the consumer waiting for the next one. Native hosts
/// deliver, iterate and cancel from different threads, so every transition of the state happens under the lock and a
/// continuation is taken out of the state (once) before it is resumed, outside the lock.
final class _NotificationBuffer: @unchecked Sendable {
  private let lock = _RuntimeLock(recursive: false)
  private var pending: [Notification] = []
  private var waiter: CheckedContinuation<Notification?, Never>?
  private var finished = false
  private var stop: (@Sendable () -> Void)?

  /// Takes the call that removes the observer. A sequence that was already released removes it at once.
  func stopObserving(_ stop: @escaping @Sendable () -> Void) {
    let alreadyFinished = lock.withLock {
      if finished { return true }
      self.stop = stop
      return false
    }
    if alreadyFinished { stop() }
  }

  func deliver(_ notification: Notification) {
    let waiting: CheckedContinuation<Notification?, Never>? = lock.withLock {
      guard !finished else { return nil }
      if let waiter {
        self.waiter = nil
        return waiter
      }
      pending.append(notification)
      return nil
    }
    waiting?.resume(returning: notification)
  }

  private enum Install {
    case waiting
    case ready(Notification)
    case ended
  }

  func next() async -> Notification? {
    let ready: Notification? = lock.withLock { pending.isEmpty ? nil : pending.removeFirst() }
    if let ready { return ready }
    if lock.withLock({ finished }) || Task.isCancelled {
      finish()
      return nil
    }
    return await withTaskCancellationHandler(operation: {
      await withCheckedContinuation { (continuation: CheckedContinuation<Notification?, Never>) in
        // Checking and installing the waiter is one step: a notification, the end or a cancellation that comes in between
        // is seen here, not lost, and the continuation is resumed by exactly one of them.
        let install: Install = lock.withLock {
          if !pending.isEmpty { return .ready(pending.removeFirst()) }
          if finished || Task.isCancelled { return .ended }
          waiter = continuation
          return .waiting
        }
        switch install {
        case .waiting: break
        case .ready(let notification): continuation.resume(returning: notification)
        case .ended: continuation.resume(returning: nil)
        }
      }
    }, onCancel: {
      self.finish()
    })
  }

  /// Ends the sequence and removes the observer. Idempotent: the lease and the cancellation may both call it.
  func finish() {
    let taken: (stop: (@Sendable () -> Void)?, waiter: CheckedContinuation<Notification?, Never>?) = lock.withLock {
      guard !finished else { return (nil, nil) }
      finished = true
      pending.removeAll()
      let result = (stop: stop, waiter: waiter)
      stop = nil
      waiter = nil
      return result
    }
    taken.stop?()
    taken.waiter?.resume(returning: nil)
  }
}

/// Owns the observer of one `Notifications` sequence: once the sequence and its iterators are released, it is removed.
final class _NotificationLease: @unchecked Sendable {
  let buffer: _NotificationBuffer

  init(buffer: _NotificationBuffer) { self.buffer = buffer }

  deinit { buffer.finish() }
}

// MARK: Object caches

/// A heterogeneous cache (`cache[key] as? Controller`). Embedded Swift cannot hash an arbitrary `Any`, so keys are
/// the value kinds Foundation bridges here: `String`, `Int`, `Bool` and `NSObject` instances (by identity). Entries
/// are stored by the key's hash value.
public final class NSMutableDictionary: ExpressibleByDictionaryLiteral {
  /// Keys are kept whole: keyed by hash alone, two keys whose hashes collide (32 bits in the browser build) shared a slot.
  private enum StoredKey: Hashable { case string(String), int(Int), bool(Bool), object(ObjectIdentifier) }
  private var storage: [StoredKey: Any] = .init()
  public init() {}
  public init(dictionaryLiteral elements: (Int, AnyObject)...) {}
  public subscript(key: Any) -> Any? {
    get { _hash(of: key).flatMap { storage[$0] } }
    set {
      guard let hash = _hash(of: key) else {
        preconditionFailure("NSMutableDictionary keys must be String, Int, Bool or NSObject instances")
      }
      storage[hash] = newValue
    }
  }
  private func _hash(of key: Any) -> StoredKey? {
    if let text = key as? String { return .string(text) }
    if let number = key as? Int { return .int(number) }
    if let flag = key as? Bool { return .bool(flag) }
    if let object = key as? NSObject { return .object(ObjectIdentifier(object)) }
    return nil
  }
  public func removeAllObjects() { storage.removeAll() }
}

/// Notification delivery already happens on the page's one thread; the queue only names where a block runs.
public final class OperationQueue: @unchecked Sendable {
  public static let main = OperationQueue()
  public static let current: OperationQueue? = main
  public init() {}
}

// MARK: Dispatch

// Hosts with threads (macOS, Linux, Windows, Android) use the real libdispatch, which is part of the open-source
// Swift toolchain there. The browser has one page thread, so it gets this stand-in, which runs every queue's work on
// the main actor.
#if canImport(Dispatch) && !hasFeature(Embedded) && !os(WASI)
@_exported import Dispatch
/// Apple's Dispatch C typealias for a queue, as Foundation and AVFoundation signatures spell it. Apple's Dispatch declares it
/// too; this module's declaration shadows the one it re-exports, so the name means the same type on every host.
public typealias dispatch_queue_t = DispatchQueue
#else
public enum DispatchTimeInterval: Sendable {
  case seconds(Int), milliseconds(Int), microseconds(Int), nanoseconds(Int), never
  var seconds: Double {
    switch self {
    case .seconds(let v): return Double(v)
    case .milliseconds(let v): return Double(v) / 1_000
    case .microseconds(let v): return Double(v) / 1_000_000
    case .nanoseconds(let v): return Double(v) / 1_000_000_000
    case .never: return Double.infinity
    }
  }
}

public struct DispatchTime: Sendable, Comparable {
  public var uptimeSeconds: Double
  public static func now() -> DispatchTime { DispatchTime(uptimeSeconds: Date().timeIntervalSince1970) }
  public static func + (lhs: DispatchTime, rhs: DispatchTimeInterval) -> DispatchTime { DispatchTime(uptimeSeconds: lhs.uptimeSeconds + rhs.seconds) }
  public static func + (lhs: DispatchTime, rhs: Double) -> DispatchTime { DispatchTime(uptimeSeconds: lhs.uptimeSeconds + rhs) }
  public static func < (lhs: DispatchTime, rhs: DispatchTime) -> Bool { lhs.uptimeSeconds < rhs.uptimeSeconds }
}

/// Apple's Dispatch C typealias for a queue, as spelled by Foundation and AVFoundation signatures.
public typealias dispatch_queue_t = DispatchQueue

public final class DispatchQueue: @unchecked Sendable {
  public struct QoS: Sendable {
    public static let userInteractive = QoS(), userInitiated = QoS(), `default` = QoS(), utility = QoS(), background = QoS(), unspecified = QoS()
  }
  public static let main = DispatchQueue()
  public static func global(qos: QoS = .default) -> DispatchQueue { main }
  public init(label: String = "") {}

  public func async(execute work: @escaping @Sendable () -> Void) {
    Task { @MainActor in work() }
  }
  public func async(qos: QoS = .default, execute work: @escaping @Sendable () -> Void) { async(execute: work) }
  public func asyncAfter(deadline: DispatchTime, execute work: @escaping @Sendable () -> Void) {
    let delay = max(0, deadline.uptimeSeconds - Date().timeIntervalSince1970)
    BrowserTimer.schedule(after: delay) { Task { @MainActor in work() } }
  }
  public func asyncAfter(deadline: DispatchTime, qos: QoS, execute work: @escaping @Sendable () -> Void) { asyncAfter(deadline: deadline, execute: work) }
  public func sync<T>(execute work: () -> T) -> T { work() }
}
#endif

// MARK: Timer

public final class Timer: @unchecked Sendable {
  private var valid = true
  public var isValid: Bool { valid }
  private init() {}

  @discardableResult
  public static func scheduledTimer(withTimeInterval interval: TimeInterval, repeats: Bool, block: @escaping @Sendable (Timer) -> Void) -> Timer {
    let timer = Timer()
    @Sendable func fire() {
      guard timer.valid else { return }
      block(timer)
      if repeats && timer.valid { BrowserTimer.schedule(after: interval) { fire() } } else { timer.valid = false }
    }
    BrowserTimer.schedule(after: interval) { fire() }
    return timer
  }

  public func invalidate() { valid = false }
}

// MARK: Concurrency

// Embedded Swift has no `Task.sleep`; the browser owns the timer. Full Swift uses the standard library's.
#if hasFeature(Embedded)
extension Task where Success == Never, Failure == Never {
  public static func sleep(for duration: Duration) async throws {
    let parts = duration.components
    try await BrowserTimer.sleep(for: Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
  }
}
#endif

// MARK: Bundle, Locale, Security

extension Bundle {
  /// Resources are served next to the page; a resource name resolves to a relative URL.
  public func url(forResource name: String?, withExtension ext: String?) -> URL? {
    guard let name else { return nil }
    return URL(string: ext.map { name + "." + $0 } ?? name)
  }
}

extension Locale {
  public var language: Language { Language() }
}

public let kSecRandomDefault: Int = 0
public func SecRandomCopyBytes(_ rnd: Int, _ count: Int, _ bytes: UnsafeMutableRawPointer) -> Int32 {
  let buffer = bytes.bindMemory(to: UInt8.self, capacity: count)
  for index in 0..<count { buffer[index] = UInt8.random(in: 0...255) }
  return 0
}

// MARK: Math

public func round(_ value: Double) -> Double { value.rounded(.toNearestOrAwayFromZero) }
public func round(_ value: Float) -> Float { value.rounded(.toNearestOrAwayFromZero) }
public func trunc(_ value: Double) -> Double { value.rounded(.towardZero) }
public func sqrt(_ value: Double) -> Double { value.squareRoot() }
public func fabs(_ value: Double) -> Double { value < 0 ? -value : value }

// MARK: Formatting

/// "a, b, and c" for the user's language (English rules; other languages join with the same list pattern).
public final class ListFormatter: @unchecked Sendable {
  public init() {}
  public static func localizedString(byJoining strings: [String]) -> String {
    switch strings.count {
    case 0: return ""
    case 1: return strings[0]
    case 2: return strings[0] + " and " + strings[1]
    default: return strings.dropLast().joined(separator: ", ") + ", and " + strings[strings.count - 1]
    }
  }
  /// Joins string items; an item that is not a `String` makes the result `nil`, as Foundation's formatter does.
  public func string(from items: [Any]) -> String? {
    var strings: [String] = []
    for item in items {
      guard let text = item as? String else { return nil }
      strings.append(text)
    }
    return Self.localizedString(byJoining: strings)
  }
}

extension String {
  /// `%@` / `%d` / `%lld` / `%s` substitution of string and integer arguments, in order.
  public static func localizedStringWithFormat(_ format: String, _ arguments: String...) -> String {
    var result = ""
    var next = 0
    let chars = Array(format)
    var index = 0
    while index < chars.count {
      guard chars[index] == "%", index + 1 < chars.count else { result.append(chars[index]); index += 1; continue }
      var end = index + 1
      while end < chars.count, !chars[end].isLetter && chars[end] != "@" && chars[end] != "%" { end += 1 }
      // "Save 20%!": a "%" that no conversion follows is kept as text, rather than read past the end.
      guard end < chars.count else { result.append(contentsOf: chars[index...]); break }
      if chars[end] == "%" { result.append("%"); index = end + 1; continue }
      // Skip length modifiers (`ll`, `l`) to the conversion character.
      while end < chars.count, chars[end] == "l" || chars[end] == "h" { end += 1 }
      if end < chars.count, next < arguments.count { result += arguments[next]; next += 1 }
      index = end + 1
    }
    return result
  }
}



extension String {
  /// printf-style formatting for integer arguments: `%d`, `%x`, `%X`, `%o` with the `0` flag, a width, a precision and
  /// the `h`/`hh`/`l` length modifiers (which do not change the output).
  public init<T: BinaryInteger>(format: String, arguments: [T]) {
    var out = ""
    var next = 0
    let chars = Array(format)
    var index = 0
    while index < chars.count {
      guard chars[index] == "%" else { out.append(chars[index]); index += 1; continue }
      index += 1
      guard index < chars.count else { break }
      if chars[index] == "%" { out.append("%"); index += 1; continue }
      var zero = false
      if chars[index] == "0" { zero = true; index += 1 }
      var width = 0
      while index < chars.count, let digit = chars[index]._asciiDigitValue { width = Swift.min(width * 10 + digit, _printfFieldLimit); index += 1 }
      var precision: Int?
      if index < chars.count, chars[index] == "." {
        index += 1
        var value = 0
        while index < chars.count, let digit = chars[index]._asciiDigitValue { value = Swift.min(value * 10 + digit, _printfFieldLimit); index += 1 }
        precision = value
      }
      while index < chars.count, chars[index] == "h" || chars[index] == "l" { index += 1 }
      guard index < chars.count else { break }
      let conversion = chars[index]
      index += 1
      guard next < arguments.count else { continue }
      let value = arguments[next]
      next += 1
      var digits: String
      switch conversion {
      case "x": digits = String(value, radix: 16)
      case "X": digits = String(value, radix: 16, uppercase: true)
      case "o": digits = String(value, radix: 8)
      default: digits = String(value)
      }
      if let precision, digits.count < precision { digits = String(repeating: "0", count: precision - digits.count) + digits }
      if digits.count < width { digits = String(repeating: zero ? "0" : " ", count: width - digits.count) + digits }
      out += digits
    }
    self = out
  }
}

// MARK: Number formatting

public final class NSNumber {
  public let doubleValue: Double
  /// The value truncated toward zero, saturated at Int's range (NaN is 0): a number from the network past 2^31 does not
  /// trap the browser build, where Int is 32 bits.
  public var intValue: Int {
    guard !doubleValue.isNaN else { return 0 }
    return Int(exactly: doubleValue.rounded(.towardZero)) ?? (doubleValue < 0 ? Int.min : Int.max)
  }
  /// The number as the predicate engine reads it: an `Int`, a `Double` or a `Bool`, as it was created.
  package let _predicateValue: Any
  public init(value: Int) { doubleValue = Double(value); _predicateValue = value }
  public init(value: Double) { doubleValue = value; _predicateValue = value }
  public init(value: Bool) { doubleValue = value ? 1 : 0; _predicateValue = value }
}

public final class NumberFormatter {
  public enum Style { case none, decimal, percent, currency, scientific, spellOut, ordinal }
  public var numberStyle: Style = .none
  public var maximumFractionDigits = 3
  public var minimumFractionDigits = 0
  public var groupingSeparator = ","
  public var decimalSeparator = "."
  public init() {}

  public func string(from number: NSNumber) -> String? {
    var value = number.doubleValue
    if numberStyle == .percent { value *= 100 }
    let negative = value < 0
    if negative { value = -value }
    let digits = numberStyle == .none ? 0 : maximumFractionDigits
    var scale = 1.0
    for _ in 0..<digits { scale *= 10 }
    let scaled = (value * scale).rounded()
    // Int64 parts (Int is 32 bits in the browser build); a value past Int64's range is written as Swift writes a Double.
    guard scaled.isFinite, scaled < 9.2e18 else { return (negative ? "-" : "") + "\(value)" + (numberStyle == .percent ? "%" : "") }
    var whole = Int64(scaled / scale)
    var fraction = Int64(scaled - Double(whole) * scale)
    if fraction < 0 { fraction = 0; whole += 0 }
    var fractionText = String(fraction)
    while fractionText.count < digits { fractionText = "0" + fractionText }
    while fractionText.count > minimumFractionDigits && fractionText.hasSuffix("0") { fractionText.removeLast() }
    var wholeText = String(whole)
    if numberStyle != .none {
      var grouped = ""
      var index = 0
      for character in wholeText.reversed() {
        if index > 0 && index % 3 == 0 { grouped = groupingSeparator + grouped }
        grouped = String(character) + grouped
        index += 1
      }
      wholeText = grouped
    }
    var result = wholeText + (fractionText.isEmpty ? "" : decimalSeparator + fractionText)
    if numberStyle == .percent { result += "%" }
    return negative ? "-" + result : result
  }
}
