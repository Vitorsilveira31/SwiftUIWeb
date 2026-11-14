/// Backend-neutral timeline primitives.  A browser host can use the private
/// scheduling hints emitted by `TimelineView` to invalidate the retained
/// Fiber tree without exposing a clock, timer or DOM type to applications.

// The WASI SDK intentionally ships without the Foundation/libm overlay. Keep
// cadence calculations deterministic on that target instead of relying on
// `floor`, which is unavailable when Foundation cannot be imported.
// Int64, not Int: Int is 32 bits in the browser build, where a schedule that started a year ago at 60 entries a second is
// past 2^31 steps. Past 2^53 a Double is already whole.
@inline(__always) private func _timelineFloor(_ value: Double) -> Double {
  guard value.isFinite, value.magnitude < 9_007_199_254_740_992 else { return value }
  let truncated = Double(Int64(value))
  return truncated > value ? truncated - 1 : truncated
}

public enum TimelineScheduleMode: Hashable, Sendable {
  case normal
  case lowFrequency
}

public protocol TimelineSchedule {
  /// SwiftUI spells the schedule mode as `TimelineSchedule.Mode`. Keep the
  /// existing module-level name as the canonical representation while also
  /// exposing the nested spelling for source-compatible custom schedules.
  typealias Mode = TimelineScheduleMode
  associatedtype Entries: Sequence where Entries.Element == Date
  func entries(from startDate: Date, mode: Self.Mode) -> Entries
  /// Hosts use this semantic cadence to decide how aggressively to invalidate
  /// a Fiber tree. The default keeps custom schedules source-compatible.
  var _swiftUIWebCadence: _TimelineCadence { get }

  /// Renderer hints. These are intentionally underscored and have defaults so
  /// existing custom schedules continue to compile unchanged. A schedule may
  /// provide either a steady interval or exact future dates; animation
  /// schedules opt into a requestAnimationFrame-style backend.
  var _swiftUIWebInterval: Double? { get }
  var _swiftUIWebUsesAnimationFrame: Bool { get }
  var _swiftUIWebIsPaused: Bool { get }
  func _swiftUIWebNextDate(after date: Date) -> Date?
  func _swiftUIWebCurrentDate(now: Date) -> Date
}

public extension TimelineSchedule {
  var _swiftUIWebCadence: _TimelineCadence { .seconds }
  var _swiftUIWebInterval: Double? {
    switch _swiftUIWebCadence {
    case .live: return nil
    case .seconds: return 1
    case .minutes: return 60
    }
  }
  var _swiftUIWebUsesAnimationFrame: Bool { _swiftUIWebCadence == .live }
  var _swiftUIWebIsPaused: Bool { false }
  func _swiftUIWebNextDate(after date: Date) -> Date? { nil }
  func _swiftUIWebCurrentDate(now: Date) -> Date { now }
}

/// Semantic update cadence shared by schedules and the renderer. Schedules
/// reference it from a public protocol requirement, so it cannot be the nested
/// `TimelineView.Context.Cadence` (which depends on the generic parameters).
public enum _TimelineCadence: Int, Comparable, Hashable, Sendable {
  case live = 0
  case seconds = 1
  case minutes = 2

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// The concrete context alias exposed by SwiftUI for documentation and APIs
/// that need a non-generic timeline context type.
public typealias TimelineViewDefaultContext = TimelineView<EveryMinuteTimelineSchedule, Never>.Context

public struct TimelineView<Schedule: TimelineSchedule, Content: View> {
  public typealias Body = Never

  /// The context passed to a `TimelineView` content closure.
  public struct Context {
    public enum Cadence: Comparable, Hashable, Sendable {
      case live
      case seconds
      case minutes

      public static func < (a: TimelineView<Schedule, Content>.Context.Cadence, b: TimelineView<Schedule, Content>.Context.Cadence) -> Bool {
        a._rank < b._rank
      }

      package init(_ cadence: _TimelineCadence) {
        switch cadence {
        case .live: self = .live
        case .seconds: self = .seconds
        case .minutes: self = .minutes
        }
      }

      fileprivate var _rank: Int {
        switch self {
        case .live: return 0
        case .seconds: return 1
        case .minutes: return 2
        }
      }
    }

    public let date: Date
    public let cadence: Cadence

    package init(date: Date, cadence: Cadence) {
      self.date = date
      self.cadence = cadence
    }
  }

  private let schedule: Schedule
  private let content: (Context) -> Content

  // SwiftUI's public initializer takes the non-generic default context. The
  // generic `Context` overload is disfavored so multi-statement closures can
  // infer their parameter type without a cyclic `Content` dependency.
  public nonisolated init(_ schedule: Schedule, @ViewBuilder content: @escaping (TimelineViewDefaultContext) -> Content) {
    self.schedule = schedule
    // `TimelineView<EveryMinuteTimelineSchedule, Never>.Context` and
    // `TimelineView<Schedule, Content>.Context` have identical layout: the
    // generic parameters only select a type identity.
    self.content = { context in
      content(unsafeBitCast(context, to: TimelineViewDefaultContext.self))
    }
  }

  /// Disfavored so that `TimelineView(schedule) { _ in ... }` picks the default-context form, as in SwiftUI.
  @_disfavoredOverload
  public nonisolated init(_ schedule: Schedule, @ViewBuilder content: @escaping (TimelineView<Schedule, Content>.Context) -> Content) {
    self.schedule = schedule
    self.content = content
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    let now = Date.now
    let hasEntry: Bool
    if schedule._swiftUIWebIsPaused {
      // A paused schedule is explicitly inactive; avoid even constructing a
      // potentially expensive custom entry sequence on every retained render.
      hasEntry = false
    } else {
      var entries = schedule.entries(from: now, mode: .normal).makeIterator()
      hasEntry = entries.next() != nil
    }
    let cadence = hasEntry ? schedule._swiftUIWebCadence : .live
    let rendered = content(Context(date: schedule._swiftUIWebCurrentDate(now: now), cadence: Context.Cadence(cadence)))._render(in: context.child(_FiberKey("timeline")))

    // Timeline content is often a text node, which cannot carry host
    // metadata. A transparent wrapper gives browser schedulers one stable DOM
    // owner while the actual content keeps the historical `timeline` render
    // path (and therefore its State identity). Static/WASI renderers simply
    // serialize the wrapper and never schedule anything.
    let node = _RenderNode.element("div")
    let identifier = context._compactPathID
    // Include the semantic path in the owner key. A constant key would make
    // two sibling TimelineViews collide during keyed reconciliation, while a
    // path-derived key remains stable across schedule ticks and keyed moves.
    node.key = _FiberKey("__timeline:" + identifier)
    node.classes = ["timeline-view"]
    // `display: contents` keeps the owner transparent to parent layout
    // primitives, matching TimelineView's historical direct-content shape.
    node.styles["display"] = "contents"
    node.children = rendered.isEmpty ? [] : [rendered]
    node.attributes["data-timeline-view"] = "true"
    node.attributes["data-timeline-id"] = identifier
    node.attributes["data-timeline-cadence"] = _timelineCadenceName(cadence)
    if let interval = schedule._swiftUIWebInterval, interval.isFinite, interval > 0 {
      node.attributes["data-timeline-interval"] = String(interval)
    }
    node.attributes["data-timeline-animation-frame"] = schedule._swiftUIWebUsesAnimationFrame ? "true" : "false"
    node.attributes["data-timeline-paused"] = (schedule._swiftUIWebIsPaused || !hasEntry) ? "true" : "false"
    // Exact-date schedules can advance without a fixed interval. The closure
    // is renderer metadata only; browser and native semantic APIs remain
    // entirely SwiftUI-shaped.
    node._timeline = _TimelineDescriptor(
      identifier: identifier,
      interval: schedule._swiftUIWebInterval,
      usesAnimationFrame: schedule._swiftUIWebUsesAnimationFrame,
      paused: schedule._swiftUIWebIsPaused || !hasEntry,
      nextDate: { date in schedule._swiftUIWebNextDate(after: date) }
    )
    return node
  }
}
extension TimelineView: View {}

private func _timelineCadenceName(_ cadence: _TimelineCadence) -> String {
  switch cadence {
  case .live: return "live"
  case .seconds: return "seconds"
  case .minutes: return "minutes"
  }
}

/// Renderer-only metadata retained by the Fiber node. It contains no DOM or
/// JavaScript value; browser hosts may choose a private scheduling primitive.
@_spi(Renderer) public struct _TimelineDescriptor {
  public let identifier: String
  public let interval: Double?
  public let usesAnimationFrame: Bool
  public let paused: Bool
  public let nextDate: ((Date) -> Date?)?

  public init(
    identifier: String,
    interval: Double?,
    usesAnimationFrame: Bool,
    paused: Bool,
    nextDate: ((Date) -> Date?)?
  ) {
    self.identifier = identifier
    self.interval = interval
    self.usesAnimationFrame = usesAnimationFrame
    self.paused = paused
    self.nextDate = nextDate
  }
}

public struct PeriodicTimelineSchedule: TimelineSchedule, Sendable {
  /// Infinite, allocation-free date sequence used by periodic schedules. As in
  /// SwiftUI, callers can consume only the prefix they need; TimelineView itself
  /// asks for the first entry and the browser host uses the exact next-date hook.
  public struct Entries: Sequence, IteratorProtocol, Sendable {
    public struct Iterator: IteratorProtocol, Sendable {
      private var nextDate: Date
      private let interval: Double
      private var exhausted = false

      fileprivate init(start: Date, interval: Double, paused: Bool = false) {
        nextDate = start
        self.interval = interval
        exhausted = paused
      }

      @_spi(Renderer) public mutating func next() -> Date? {
        guard !exhausted else { return nil }
        let value = nextDate
        let advanced = nextDate.addingTimeInterval(interval)
        guard advanced > nextDate else {
          exhausted = true
          return value
        }
        nextDate = advanced
        return value
      }
    }

    private let start: Date
    private let interval: Double
    private let paused: Bool
    private var iterator: Iterator?

    fileprivate init(start: Date, interval: Double, paused: Bool = false) {
      self.start = start
      self.interval = interval
      self.paused = paused
      iterator = nil
    }

    @_spi(Renderer) public func makeIterator() -> Iterator {
      // Preserve iterator progress when callers use the SwiftUI-style direct
      // `entries.next()` API before switching to sequence iteration.
      iterator ?? Iterator(start: start, interval: interval, paused: paused)
    }

    /// `Entries` is also an iterator in SwiftUI, so callers may either use
    /// `for`/`prefix` or pull dates directly with a mutating `next()` call.
    public mutating func next() -> Date? {
      if iterator == nil { iterator = Iterator(start: start, interval: interval, paused: paused) }
      return iterator?.next()
    }
  }

  private let startDate: Date
  private let interval: Double

  public init(from startDate: Date, by interval: TimeInterval) {
    self.startDate = startDate
    self.interval = max(0.001, interval.isFinite ? interval : 1)
  }

  public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
    let first: Date
    if startDate <= self.startDate {
      first = self.startDate
    } else {
      let elapsed = startDate.timeIntervalSince(self.startDate)
      // SwiftUI starts with the beginning of the interval that overlaps the
      // requested date, so the first entry may precede `startDate`.
      let step = max(0, _timelineFloor((elapsed / interval) + 1e-9))
      first = self.startDate.addingTimeInterval(step * interval)
    }
    return PeriodicTimelineSchedule.Entries(start: first, interval: interval)
  }

  public var _swiftUIWebInterval: Double? { interval }
  public func _swiftUIWebCurrentDate(now: Date) -> Date {
    guard now >= startDate else { return now }
    let elapsed = now.timeIntervalSince(startDate)
    let step = max(0, _timelineFloor((elapsed / interval) + 1e-9))
    return startDate.addingTimeInterval(step * interval)
  }
  public func _swiftUIWebNextDate(after date: Date) -> Date? {
    if date < startDate { return startDate }
    let elapsed = date.timeIntervalSince(startDate)
    let step = _timelineFloor(elapsed / interval) + 1
    return startDate.addingTimeInterval(step * interval)
  }
}

public struct EveryMinuteTimelineSchedule: TimelineSchedule, Sendable {
  public typealias Entries = PeriodicTimelineSchedule.Entries
  public init() {}
  public var _swiftUIWebCadence: _TimelineCadence { .minutes }
  public var _swiftUIWebInterval: Double? { 60 }
  public func _swiftUIWebCurrentDate(now: Date) -> Date {
    Date(timeIntervalSince1970: _timelineFloor(now.timeIntervalSince1970 / 60) * 60)
  }
  public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
    // The first entry is the beginning of the minute containing the request,
    // including when the request is not minute-aligned. Subsequent entries
    // advance one minute at a time.
    let seconds = startDate.timeIntervalSince1970
    let minute = _timelineFloor(seconds / 60) * 60
    return PeriodicTimelineSchedule.Entries(start: Date(timeIntervalSince1970: minute), interval: 60)
  }
  public func _swiftUIWebNextDate(after date: Date) -> Date? {
    _nextMinute(after: date)
  }
}

private func _nextMinute(after date: Date) -> Date {
  let seconds = date.timeIntervalSince1970
  let boundary = _timelineFloor(seconds / 60) + 1
  return Date(timeIntervalSince1970: boundary * 60)
}

public struct ExplicitTimelineSchedule<Dates: Sequence>: TimelineSchedule where Dates.Element == Date {
  private let dates: Dates
  public init(_ dates: Dates) { self.dates = dates }
  public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Dates { dates }
  public func _swiftUIWebNextDate(after date: Date) -> Date? {
    for candidate in dates where candidate > date { return candidate }
    return nil
  }
  public func _swiftUIWebCurrentDate(now: Date) -> Date {
    var current: Date?
    for candidate in dates where candidate <= now { current = candidate }
    return current ?? now
  }
}

public struct AnimationTimelineSchedule: TimelineSchedule, Sendable {
  public typealias Entries = PeriodicTimelineSchedule.Entries
  let minimumInterval: Double?
  let isPaused: Bool
  public init(minimumInterval: Double? = nil, paused: Bool = false) {
    self.minimumInterval = minimumInterval
    isPaused = paused
  }
  public var _swiftUIWebCadence: _TimelineCadence { .live }
  private var effectiveMinimumInterval: Double? {
    guard let minimumInterval, minimumInterval.isFinite, minimumInterval > 0 else { return nil }
    return minimumInterval
  }
  public var _swiftUIWebInterval: Double? { effectiveMinimumInterval }
  public var _swiftUIWebUsesAnimationFrame: Bool { effectiveMinimumInterval == nil || effectiveMinimumInterval! <= (1.0 / 60.0) }
  public var _swiftUIWebIsPaused: Bool { isPaused }
  public func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
    // SwiftUI asks animation schedules for a low-frequency sequence when the
    // host is constrained; returning no entries pauses frame-driven work.
    let pausedForMode = isPaused || mode == .lowFrequency
    return PeriodicTimelineSchedule.Entries(start: startDate, interval: effectiveMinimumInterval ?? (1.0 / 60.0), paused: pausedForMode)
  }
  public func _swiftUIWebNextDate(after date: Date) -> Date? {
    guard !isPaused else { return nil }
    return date.addingTimeInterval(effectiveMinimumInterval ?? (1.0 / 60.0))
  }
}

public extension TimelineSchedule where Self == AnimationTimelineSchedule {
  static var animation: AnimationTimelineSchedule { AnimationTimelineSchedule() }
  static func animation(minimumInterval: Double? = nil, paused: Bool = false) -> AnimationTimelineSchedule {
    AnimationTimelineSchedule(minimumInterval: minimumInterval, paused: paused)
  }
}

public extension TimelineSchedule {
  static func explicit<Dates: Sequence>(_ dates: Dates) -> ExplicitTimelineSchedule<Dates>
    where Self == ExplicitTimelineSchedule<Dates>, Dates.Element == Date {
    ExplicitTimelineSchedule(dates)
  }
}
