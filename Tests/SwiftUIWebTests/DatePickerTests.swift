import Foundation
import Testing
@testable import SwiftUIWeb
@_spi(Renderer) import SwiftUIWebFiber

@Suite
@MainActor
final class DatePickerTests {
  private func findNode(_ node: _RenderNode, where predicate: (_RenderNode) -> Bool) -> _RenderNode? {
    if predicate(node) { return node }
    for child in node.children {
      if let match = findNode(child, where: predicate) { return match }
    }
    return nil
  }

  @Test
  func testSwiftUIStyleConcreteSpellingsCompile() {
    let _: DefaultDatePickerStyle = .automatic
    let _: CompactDatePickerStyle = .compact
    let _: GraphicalDatePickerStyle = .graphical
    let _: WheelDatePickerStyle = .wheel
    let _: FieldDatePickerStyle = .field
    let _: StepperFieldDatePickerStyle = .stepperField
    _ = DatePicker("Date", selection: .constant(Date(timeIntervalSince1970: 0)))
      .datePickerStyle(.automatic)
    let localizedTitle: LocalizedStringKey = "Localized date"
    let _: DatePicker.Components = [.date, .hourAndMinute]
    _ = DatePicker(localizedTitle, selection: .constant(Date(timeIntervalSince1970: 0)))
  }

  @Test
  func testAllComponentsRenderDateTimeWithSeconds() {
    var date = Date(timeIntervalSince1970: 1_704_110_400)
    let binding = Binding<Date>(get: { date }, set: { date = $0 })
    let picker = DatePicker(
      "When",
      selection: binding,
      displayedComponents: [.date, .hourMinuteAndSecond]
    )
    let html = StaticHTMLFiberRenderer().render(picker)

    _expectTrue(html.contains("type=\"datetime-local\""))
    _expectTrue(html.contains("step=\"1\""))
    _expectTrue(html.contains("data-date-picker-components=\"date,hourMinuteAndSecond\""))
    _expectTrue(html.contains("T"))
    _expectTrue(html.contains("date-input-native"))
    _expectFalse(html.contains("date-picker-trigger"))
  }

  @Test
  func testTimeOnlyKeepsNativeTimeControlVisible() {
    var date = Date(timeIntervalSince1970: 1_704_110_400)
    let picker = DatePicker(
      "Time",
      selection: Binding(get: { date }, set: { date = $0 }),
      displayedComponents: .hourAndMinute
    )
    let html = StaticHTMLFiberRenderer().render(picker)

    _expectTrue(html.contains("type=\"time\""))
    _expectTrue(html.contains("date-input-native"))
    _expectFalse(html.contains("date-picker-trigger"))
    _expectTrue(html.contains("step=\"60\""))
  }

  @Test
  func testFieldStyleUsesNativeDateField() {
    let picker = DatePicker(
      "Date",
      selection: .constant(Date(timeIntervalSince1970: 0)),
      displayedComponents: .date
    ).datePickerStyle(.field)
    let html = StaticHTMLFiberRenderer().render(picker)

    _expectTrue(html.contains("date-input-native"))
    _expectFalse(html.contains("date-picker-trigger"))
    _expectTrue(html.contains("data-date-picker-style=\"field\""))
  }

  @Test
  func testClosedAndPartialRangesEmitNativeBounds() {
    let lower = Date(timeIntervalSince1970: 1_704_067_200)
    let upper = Date(timeIntervalSince1970: 1_704_153_600)
    let closed = DatePicker("Date", selection: .constant(lower), in: lower...upper, displayedComponents: .date)
    let from = DatePicker("From", selection: .constant(lower), in: lower..., displayedComponents: .date)
    let through = DatePicker("Through", selection: .constant(upper), in: ...upper, displayedComponents: .date)
    let renderer = StaticHTMLFiberRenderer()

    let closedHTML = renderer.render(closed)
    _expectTrue(closedHTML.contains("min=\"2024-01-01\""))
    _expectTrue(closedHTML.contains("max=\"2024-01-02\""))
    _expectTrue(renderer.render(from).contains("min=\"2024-01-01\""))
    _expectFalse(renderer.render(from).contains("max=\""))
    _expectTrue(renderer.render(through).contains("max=\"2024-01-02\""))
    _expectFalse(renderer.render(through).contains("min=\""))
  }

  @Test
  func testDateBindingPreservesUnspecifiedTimeAndRejectsOutOfRange() {
    var date = Date(timeIntervalSince1970: 1_704_153_600 + 43_200)
    let lower = Date(timeIntervalSince1970: 1_704_067_200)
    let upper = Date(timeIntervalSince1970: 1_704_326_400)
    let picker = DatePicker("Date", selection: Binding(get: { date }, set: { date = $0 }), in: lower...upper, displayedComponents: .date)
    let tree = FiberTree(picker)

    tree.dispatch(event: "change", value: "2024-01-03")
    _expectEqual(date.timeIntervalSince1970, 1_704_240_000 + 43_200)
    tree.dispatch(event: "change", value: "2023-12-01")
    _expectEqual(date.timeIntervalSince1970, 1_704_240_000 + 43_200)
  }

  @Test
  func testTimeAndSecondsBindingRoundTrip() {
    var date = Date(timeIntervalSince1970: 1_704_067_200)
    let picker = DatePicker(
      "Time",
      selection: Binding(get: { date }, set: { date = $0 }),
      displayedComponents: .hourMinuteAndSecond
    )
    let tree = FiberTree(picker)

    tree.dispatch(event: "change", value: "13:45:27")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    _expectEqual(calendar.component(.hour, from: date), 13)
    _expectEqual(calendar.component(.minute, from: date), 45)
    _expectEqual(calendar.component(.second, from: date), 27)
  }

  @Test
  func testCustomLabelStyleLocaleAndTimeZoneAreSemantic() {
    let date = Date(timeIntervalSince1970: 0)
    let picker = DatePicker(
      selection: .constant(date),
      displayedComponents: .date
    ) {
      Text("Quando")
    }
    var environment = EnvironmentValues()
    environment.locale = Locale(identifier: "pt_BR")
    environment.timeZone = TimeZone(secondsFromGMT: -10_800)!
    let styled = picker.datePickerStyle(.graphical)
    let html = StaticHTMLFiberRenderer().render(styled, environment: environment)

    _expectTrue(html.contains("Quando"))
    _expectTrue(html.contains("data-date-picker-style=\"graphical\""))
    _expectTrue(html.contains("data-date-picker-locale=\"pt-BR\""))
    _expectTrue(html.contains("data-date-picker-time-zone=\"GMT-0300\""))
    _expectTrue(html.contains("value=\"1969-12-31\""))
  }

  @Test
  func testDisabledDatePickerDoesNotMutateBinding() {
    var date = Date(timeIntervalSince1970: 0)
    let picker = DatePicker("Date", selection: Binding(get: { date }, set: { date = $0 })).disabled(true)
    let tree = FiberTree(picker)

    tree.dispatch(event: "change", value: "2024-01-01")
    _expectEqual(date.timeIntervalSince1970, 0)
    _expectTrue(tree.renderNode.htmlDescription.contains("disabled=\"disabled\""))
  }

  @Test
  func testMultiDatePickerRendersCalendarAndSelectedDates() {
    var selected: Set<DateComponents> = [DateComponents(year: 2024, month: 1, day: 15)]
    let picker = MultiDatePicker("Dates", selection: Binding(get: { selected }, set: { selected = $0 }))
    let environment = EnvironmentValues()
    let html = StaticHTMLFiberRenderer().render(picker, environment: environment)

    _expectTrue(html.contains("data-multi-date-picker=\"true\""))
    _expectTrue(html.contains("data-date=\"2024-01-15\""))
    _expectTrue(html.contains("data-selected=\"true\""))
    _expectTrue(html.contains("aria-pressed=\"true\""))
    _expectTrue(html.contains("data-selected-count=\"1\""))
    _expectTrue(html.contains("role=\"grid\""))
    _expectTrue(html.contains("aria-multiselectable=\"true\""))
    _expectFalse(html.contains("<input"))
  }

  @Test
  func testMultiDatePickerSelectsAndDeselectsDatesThroughBinding() {
    var selected: Set<DateComponents> = [DateComponents(year: 2024, month: 1, day: 15)]
    let binding = Binding(get: { selected }, set: { selected = $0 })
    let picker = MultiDatePicker("Dates", selection: binding)
    let tree = FiberTree(picker)
    guard let day = findNode(tree.renderNode, where: { $0.attributes["data-date"] == "2024-01-16" }) else {
      return _fail("January 16 button was not rendered")
    }

    tree.dispatch(event: "click", on: day)
    _expectTrue(selected.contains { $0.year == 2024 && $0.month == 1 && $0.day == 16 })
    guard let selectedDay = findNode(tree.renderNode, where: { $0.attributes["data-date"] == "2024-01-15" }) else {
      return _fail("January 15 button was not rendered")
    }
    tree.dispatch(event: "click", on: selectedDay)
    _expectFalse(selected.contains { $0.year == 2024 && $0.month == 1 && $0.day == 15 })
  }

  @Test
  func testMultiDatePickerRangeDisablesOutOfRangeDays() {
    let lower = Date(timeIntervalSince1970: 1_705_795_200) // 2024-01-21 UTC
    let upper = Date(timeIntervalSince1970: 1_705_968_000) // 2024-01-23 UTC
    var selected: Set<DateComponents> = [DateComponents(year: 2024, month: 1, day: 22)]
    let picker = MultiDatePicker("Dates", selection: Binding(get: { selected }, set: { selected = $0 }), in: lower..<upper.addingTimeInterval(86_400))
    let tree = FiberTree(picker)
    guard let disabledDay = findNode(tree.renderNode, where: { $0.attributes["data-date"] == "2024-01-20" }) else {
      return _fail("Out-of-range day was not rendered")
    }
    _expectEqual(disabledDay.attributes["disabled"], "disabled")
    tree.dispatch(event: "click", on: disabledDay)
    _expectEqual(selected.count, 1)
    _expectTrue(selected.contains { $0.day == 22 })
    guard let validDay = findNode(tree.renderNode, where: { $0.attributes["data-date"] == "2024-01-23" }) else {
      return _fail("In-range day was not rendered")
    }
    tree.dispatch(event: "click", on: validDay)
    _expectTrue(selected.contains { $0.day == 23 })
  }

  @Test
  func testMultiDatePickerEmptySelectionStartsAtRangeMonth() {
    let lower = Date(timeIntervalSince1970: 1_705_795_200) // 2024-01-21 UTC
    let upper = Date(timeIntervalSince1970: 1_705_968_000) // 2024-01-23 UTC
    let picker = MultiDatePicker("Dates", selection: .constant(Set<DateComponents>()), in: lower..<upper.addingTimeInterval(86_400))
    let html = StaticHTMLFiberRenderer().render(picker)
    _expectTrue(html.contains("January 2024"))
    _expectTrue(html.contains("data-min-date=\"2024-01-21\""))
    _expectTrue(html.contains("data-max-date=\"2024-01-23\""))
  }

  @Test
  func testMultiDatePickerBindingChangesAndLocaleCalendarAreReflected() {
    var selected: Set<DateComponents> = [DateComponents(year: 2024, month: 1, day: 15)]
    let binding = Binding(get: { selected }, set: { selected = $0 })
    let picker = MultiDatePicker(selection: binding) { Text("Termine") }
    var environment = EnvironmentValues()
    environment.locale = Locale(identifier: "de_DE")
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = environment.locale
    calendar.firstWeekday = 2
    environment.calendar = calendar
    let renderer = StaticHTMLFiberRenderer()
    let html = renderer.render(picker, environment: environment)
    _expectTrue(html.contains("lang=\"de-DE\""))
    _expectTrue(html.contains("data-multi-date-picker-first-weekday=\"2\""))
    _expectTrue(html.contains("Januar 2024") || html.contains("januar 2024"))
    _expectTrue(html.contains("Termine"))

    selected = [DateComponents(year: 2024, month: 1, day: 20)]
    let updated = renderer.render(picker, environment: environment)
    // Attributes are written in alphabetical order, so look at the day's own tag instead of at adjacent text.
    if let range = updated.range(of: "data-date=\"2024-01-20\""),
       let open = updated[..<range.lowerBound].lastIndex(of: "<"),
       let close = updated[range.upperBound...].firstIndex(of: ">") {
      _expectTrue(updated[open...close].contains("data-selected=\"true\""))
    } else {
      _fail("The day 2024-01-20 was not rendered")
    }
  }

  @Test
  func testMultiDatePickerMonthNavigationPreservesSelection() {
    var selected: Set<DateComponents> = [DateComponents(year: 2024, month: 1, day: 15)]
    let picker = MultiDatePicker("Dates", selection: Binding(get: { selected }, set: { selected = $0 }))
    let tree = FiberTree(picker)
    guard let next = findNode(tree.renderNode, where: { $0.classes.contains("multi-date-picker-nav") && $0.attributes["aria-label"] == "Next month" }) else {
      return _fail("Next-month button was not rendered")
    }
    tree.dispatch(event: "click", on: next)
    _expectTrue(tree.renderNode.htmlDescription.contains("February 2024"))
    _expectEqual(selected.count, 1)
  }
}
