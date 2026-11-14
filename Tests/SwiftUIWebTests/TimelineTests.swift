import Testing
import Foundation
import SwiftUIWebCore
import SwiftUIWebFeatures
@testable import SwiftUIWeb

@Suite
@MainActor
final class TimelineTests {
  @Test
  func testPeriodicScheduleProducesStableIncreasingEntries() {
    let origin = Date(timeIntervalSince1970: 100)
    let schedule = PeriodicTimelineSchedule(from: origin, by: 2)
    let entries = Array(schedule.entries(from: origin, mode: .normal).prefix(4))
    _expectEqual(entries.map(\.timeIntervalSince1970), [100, 102, 104, 106])
    var direct = schedule.entries(from: origin, mode: .normal)
    _expectEqual(direct.next()?.timeIntervalSince1970, 100)
    _expectEqual(direct.next()?.timeIntervalSince1970, 102)
    _expectEqual(schedule._swiftUIWebNextDate(after: origin.addingTimeInterval(2.1))?.timeIntervalSince1970, 104)
    _expectEqual(schedule._swiftUIWebCurrentDate(now: origin.addingTimeInterval(2.1)).timeIntervalSince1970, 102)
    var aligned = schedule.entries(from: origin.addingTimeInterval(5), mode: .normal).makeIterator()
    _expectEqual(aligned.next()?.timeIntervalSince1970, 104)
  }

  @Test
  func testPeriodicScheduleClampsInvalidIntervalsAndSkipsPastStart() {
    let origin = Date(timeIntervalSince1970: 100)
    let schedule = PeriodicTimelineSchedule(from: origin, by: 0)
    var iterator = schedule.entries(from: origin.addingTimeInterval(3), mode: .normal).makeIterator()
    let first = iterator.next()
    _expectEqual(first?.timeIntervalSince1970, 103)
    _expectEqual(schedule._swiftUIWebInterval, 0.001)
  }

  @Test
  func testEveryMinuteUsesMinuteCadence() {
    let schedule = EveryMinuteTimelineSchedule()
    _expectEqual(schedule._swiftUIWebCadence, .minutes)
    _expectEqual(schedule._swiftUIWebInterval, 60)
    var iterator = schedule.entries(from: Date(timeIntervalSince1970: 12), mode: .lowFrequency).makeIterator()
    let first = iterator.next()
    _expectEqual(first?.timeIntervalSince1970, 0)
  }

  @Test
  func testSchedulesHandlePreEpochTimeExplicitDatesAndFloatingPointSaturation() {
    let beforeEpoch = Date(timeIntervalSince1970: -1)
    let minute = EveryMinuteTimelineSchedule()
    _expectEqual(minute._swiftUIWebCurrentDate(now: beforeEpoch).timeIntervalSince1970, -60)
    _expectEqual(minute._swiftUIWebNextDate(after: beforeEpoch)?.timeIntervalSince1970, 0)

    let dates = [
      Date(timeIntervalSince1970: 10),
      Date(timeIntervalSince1970: 20),
      Date(timeIntervalSince1970: 30)
    ]
    let explicit = ExplicitTimelineSchedule(dates)
    _expectEqual(explicit._swiftUIWebCurrentDate(now: .init(timeIntervalSince1970: 5)).timeIntervalSince1970, 5)
    _expectEqual(explicit._swiftUIWebCurrentDate(now: .init(timeIntervalSince1970: 25)).timeIntervalSince1970, 20)
    _expectEqual(explicit._swiftUIWebNextDate(after: .init(timeIntervalSince1970: 20))?.timeIntervalSince1970, 30)
    _expectNil(explicit._swiftUIWebNextDate(after: .init(timeIntervalSince1970: 30)))
    _expectEqual(explicit.entries(from: .init(timeIntervalSince1970: 99), mode: .lowFrequency), dates)

    let saturatedStart = Date(timeIntervalSince1970: 1e300)
    var saturated = PeriodicTimelineSchedule(from: saturatedStart, by: 1)
      .entries(from: saturatedStart, mode: .normal)
    _expectEqual(saturated.next(), saturatedStart)
    _expectNil(saturated.next(), "a schedule must stop when floating-point precision cannot advance time")
  }

  @Test
  func testDefaultScheduleHooksAndConvenienceFactoriesRemainSourceCompatible() throws {
    struct DefaultSchedule: TimelineSchedule {
      typealias Entries = [Date]
      func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries { [] }
    }

    let now = Date(timeIntervalSince1970: 42)
    let custom = DefaultSchedule()
    _expectNil(custom._swiftUIWebNextDate(after: now))
    _expectEqual(custom._swiftUIWebCurrentDate(now: now), now)
    _expectEqual(TimelineViewDefaultContext.Cadence.live < .seconds, true)
    _expectEqual(TimelineViewDefaultContext.Cadence.seconds < .minutes, true)

    let defaultAnimation: AnimationTimelineSchedule = .animation
    let constrainedAnimation: AnimationTimelineSchedule = .animation(minimumInterval: 0.05)
    _expectTrue(defaultAnimation._swiftUIWebUsesAnimationFrame)
    _expectFalse(constrainedAnimation._swiftUIWebUsesAnimationFrame)
    let nextAnimationDate = try _require(defaultAnimation._swiftUIWebNextDate(after: now))
    #expect(abs(nextAnimationDate.timeIntervalSince1970 - (42 + 1.0 / 60.0)) < 0.000001)

    let dates = [now, now.addingTimeInterval(1)]
    let explicit: ExplicitTimelineSchedule<[Date]> = .explicit(dates)
    _expectEqual(Array(explicit.entries(from: now, mode: .normal)), dates)
  }

  @Test
  func testAnimationScheduleSupportsPausedAndFrameDrivenModes() {
    let running = AnimationTimelineSchedule()
    _expectTrue(running._swiftUIWebUsesAnimationFrame)
    _expectNil(running._swiftUIWebInterval)
    _expectEqual(Array(running.entries(from: .init(timeIntervalSince1970: 0), mode: .normal).prefix(2)).count, 2)
    _expectEqual(Array(running.entries(from: .init(timeIntervalSince1970: 0), mode: .lowFrequency).prefix(1)).count, 0)

    let paused = AnimationTimelineSchedule(minimumInterval: 0.1, paused: true)
    _expectTrue(paused._swiftUIWebIsPaused)
    _expectFalse(paused._swiftUIWebUsesAnimationFrame)
    _expectEqual(Array(paused.entries(from: .init(timeIntervalSince1970: 0), mode: .normal).prefix(1)).count, 0)
    _expectNil(paused._swiftUIWebNextDate(after: .init(timeIntervalSince1970: 0)))
  }

  @Test
  func testCustomScheduleRemainsSourceCompatibleAndRendersContext() {
    struct CustomSchedule: TimelineSchedule {
      typealias Entries = [Date]
      func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        [startDate.addingTimeInterval(5)]
      }
    }

    var observedCadence: TimelineViewDefaultContext.Cadence?
    let html = StaticHTMLFiberRenderer().render(
      TimelineView(CustomSchedule()) { context in
        observedCadence = context.cadence
        return Text("timeline")
      }
    )
    _expectEqual(observedCadence, .seconds)
    _expectTrue(html.contains("timeline-view"))
    _expectTrue(html.contains("data-timeline-cadence=\"seconds\""))
  }

  @Test
  func testCustomScheduleAcceptsSwiftUINestedModeSpelling() {
    struct NestedModeSchedule: TimelineSchedule {
      typealias Entries = [Date]
      func entries(from startDate: Date, mode: TimelineSchedule.Mode) -> [Date] {
        [startDate]
      }
    }
    let schedule = NestedModeSchedule()
    _expectEqual(schedule.entries(from: Date(timeIntervalSince1970: 7), mode: .normal).count, 1)
  }

  @Test
  func testPausedTimelineProvidesStableContentAndPausedMarker() {
    let html = StaticHTMLFiberRenderer().render(
      TimelineView(.animation(minimumInterval: 0.1, paused: true)) { context in
        Text(context.cadence == .live ? "paused" : "running")
      }
    )
    _expectTrue(html.contains("paused"))
    _expectTrue(html.contains("data-timeline-paused=\"true\""))
  }

  @Test
  func testTimelineStateAndIdentitySurviveRetainedUpdates() {
    struct Counter: View {
      @State private var value = 0
      var body: some View {
        TimelineView(.periodic(from: .init(timeIntervalSince1970: 0), by: 1)) { _ in
          Button("Increment \(value)") { value += 1 }
        }
      }
    }

    let tree = FiberTree(Counter())
    _expectTrue(tree.renderNode.htmlDescription.contains("Increment 0"))
    tree.dispatch(event: "click")
    _expectTrue(tree.renderNode.htmlDescription.contains("Increment 1"))
    func findTimeline(_ node: _RenderNode) -> _RenderNode? {
      if node.attributes["data-timeline-view"] == "true" { return node }
      for child in node.children {
        if let found = findTimeline(child) { return found }
      }
      return nil
    }
    _expectEqual(findTimeline(tree.renderNode)?.key, _FiberKey("__timeline:root"))
  }

  @Test
  func testSiblingTimelinesHaveDistinctStableOwners() {
    let tree = FiberTree(Group {
      TimelineView(.everyMinute) { _ in Text("A") }
      TimelineView(.everyMinute) { _ in Text("B") }
    })
    func owners(_ node: _RenderNode) -> [_RenderNode] {
      var result: [_RenderNode] = []
      if node.attributes["data-timeline-view"] == "true" { result.append(node) }
      for child in node.children { result.append(contentsOf: owners(child)) }
      return result
    }
    let timelines = owners(tree.renderNode)
    _expectEqual(timelines.count, 2)
    _expectNotEqual(timelines[0].key, timelines[1].key)
    _expectNotEqual(timelines[0].attributes["data-timeline-id"], timelines[1].attributes["data-timeline-id"])
  }

  @Test
  func testTimelineLifecycleFollowsFiberInsertionAndRemoval() {
    var appears = 0
    var disappears = 0
    let timeline = TimelineView(.periodic(from: .init(timeIntervalSince1970: 0), by: 60)) { _ in
      Text("clock")
    }
    .onAppear { appears += 1 }
    .onDisappear { disappears += 1 }

    let tree = FiberTree(timeline)
    _expectEqual(appears, 1)
    _ = tree.update(EmptyView())
    _expectEqual(disappears, 1)
    _ = tree.update(timeline)
    _expectEqual(appears, 2)
  }

  @Test
  func testExplicitScheduleExposesItsNextFutureEntryToRenderer() {
    let now = Date(timeIntervalSince1970: 100)
    let schedule = ExplicitTimelineSchedule([
      now.addingTimeInterval(-1),
      now.addingTimeInterval(4),
      now.addingTimeInterval(9)
    ])
    _expectEqual(schedule._swiftUIWebNextDate(after: now)?.timeIntervalSince1970, 104)
    _expectEqual(schedule._swiftUIWebCurrentDate(now: now).timeIntervalSince1970, 99)
  }
}
