@_spi(Browser) @_spi(Generated) @_spi(Renderer) import SwiftUIWebCore

public extension TimelineSchedule where Self == PeriodicTimelineSchedule {
  static func periodic(from startDate: Date, by interval: TimeInterval) -> PeriodicTimelineSchedule {
    PeriodicTimelineSchedule(from: startDate, by: interval)
  }
}

public extension TimelineSchedule where Self == EveryMinuteTimelineSchedule {
  static var everyMinute: EveryMinuteTimelineSchedule { EveryMinuteTimelineSchedule() }
}
