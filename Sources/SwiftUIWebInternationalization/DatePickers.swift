@_spi(Renderer) import SwiftUIWebCore
@_spi(Renderer) import SwiftUIWebFeatures

// The Core module keeps lightweight calendar values on WASI. Geometry now
// aliases platform types, so ICU reachability must be measured. Date-picker code is the
// explicit internationalization boundary; keep its public spellings mapped to
// those values while delegating browser presentation to native Intl.
public typealias Calendar = SwiftUIWebCore.Calendar
public typealias DateComponents = SwiftUIWebCore.DateComponents
public typealias TimeZone = SwiftUIWebCore.TimeZone
public typealias Locale = SwiftUIWebCore.Locale

private func _twoDigits(_ value: Int) -> String { value < 10 ? "0\(value)" : String(value) }
private func _fourDigits(_ value: Int) -> String {
  if value >= 1000 { return String(value) }
  if value >= 100 { return "0\(value)" }
  if value >= 10 { return "00\(value)" }
  return "000\(value)"
}

/// SwiftUI's option set of date and time fields, spelt `DatePicker.Components`.
public struct DatePickerComponents: OptionSet, Hashable, Sendable {
  public let rawValue: UInt
  public init(rawValue: UInt) { self.rawValue = rawValue }
  public static let date = DatePickerComponents(rawValue: 1 << 0)
  public static let hourAndMinute = DatePickerComponents(rawValue: 1 << 1)
  package static let hourMinuteAndSecond = DatePickerComponents(rawValue: 1 << 2)
  package static let all: DatePickerComponents = [.date, .hourAndMinute]
}

private struct _DatePickerRange {
  let lowerBound: Date?
  let upperBound: Date?
  /// `Range` and `PartialRangeUpTo` (MultiDatePicker) exclude their upper bound, as in SwiftUI.
  var upperIsExclusive: Bool = false
}


/// SwiftUI's date-picker view. `Label` is the view that names the control; the
/// title overloads use a `Text` label, as SwiftUI does.
public nonisolated struct DatePicker<Label: View>: View {
  public typealias Body = Never

  /// SwiftUI's `DatePicker.Components`: the date and time fields the picker shows.
  public typealias Components = DatePickerComponents

  package let title: String
  package let selection: Binding<Date>?
  package let displayedComponents: Components
  private let range: _DatePickerRange?
  private let labelView: Label

  private init(
    title: String,
    selection: Binding<Date>?,
    displayedComponents: Components,
    range: _DatePickerRange?,
    labelView: Label
  ) {
    self.title = title
    self.selection = selection
    self.displayedComponents = displayedComponents
    self.range = range
    self.labelView = labelView
  }

  // MARK: Labeled by a view

  public nonisolated init(
    selection: Binding<Date>,
    displayedComponents: Components = [.hourAndMinute, .date],
    @ViewBuilder label: () -> Label
  ) {
    self.init(title: "", selection: selection, displayedComponents: displayedComponents, range: nil, labelView: label())
  }

  public nonisolated init(
    selection: Binding<Date>,
    in range: ClosedRange<Date>,
    displayedComponents: Components = [.hourAndMinute, .date],
    @ViewBuilder label: () -> Label
  ) {
    self.init(
      title: "", selection: selection, displayedComponents: displayedComponents,
      range: _DatePickerRange(lowerBound: range.lowerBound, upperBound: range.upperBound), labelView: label()
    )
  }

  public nonisolated init(
    selection: Binding<Date>,
    in range: PartialRangeFrom<Date>,
    displayedComponents: Components = [.hourAndMinute, .date],
    @ViewBuilder label: () -> Label
  ) {
    self.init(
      title: "", selection: selection, displayedComponents: displayedComponents,
      range: _DatePickerRange(lowerBound: range.lowerBound, upperBound: nil), labelView: label()
    )
  }

  public nonisolated init(
    selection: Binding<Date>,
    in range: PartialRangeThrough<Date>,
    displayedComponents: Components = [.hourAndMinute, .date],
    @ViewBuilder label: () -> Label
  ) {
    self.init(
      title: "", selection: selection, displayedComponents: displayedComponents,
      range: _DatePickerRange(lowerBound: nil, upperBound: range.upperBound), labelView: label()
    )
  }

  // MARK: Labeled by a title

  @_disfavoredOverload public nonisolated init<S: StringProtocol>(
    _ title: S,
    selection: Binding<Date>,
    displayedComponents: Components = [.hourAndMinute, .date]
  ) where Label == Text {
    self.init(title: String(title), selection: selection, displayedComponents: displayedComponents,
              range: nil, labelView: Text(String(title)))
  }

  public nonisolated init(
    _ titleKey: LocalizedStringKey,
    selection: Binding<Date>,
    displayedComponents: Components = [.hourAndMinute, .date]
  ) where Label == Text {
    self.init(titleKey.resolved, selection: selection, displayedComponents: displayedComponents)
  }

  @_disfavoredOverload public nonisolated init<S: StringProtocol>(
    _ title: S,
    selection: Binding<Date>,
    in range: ClosedRange<Date>,
    displayedComponents: Components = [.hourAndMinute, .date]
  ) where Label == Text {
    self.init(title: String(title), selection: selection, displayedComponents: displayedComponents,
              range: _DatePickerRange(lowerBound: range.lowerBound, upperBound: range.upperBound),
              labelView: Text(String(title)))
  }

  public nonisolated init(
    _ titleKey: LocalizedStringKey,
    selection: Binding<Date>,
    in range: ClosedRange<Date>,
    displayedComponents: Components = [.hourAndMinute, .date]
  ) where Label == Text {
    self.init(titleKey.resolved, selection: selection, in: range, displayedComponents: displayedComponents)
  }

  @_disfavoredOverload public nonisolated init<S: StringProtocol>(
    _ title: S,
    selection: Binding<Date>,
    in range: PartialRangeFrom<Date>,
    displayedComponents: Components = [.hourAndMinute, .date]
  ) where Label == Text {
    self.init(title: String(title), selection: selection, displayedComponents: displayedComponents,
              range: _DatePickerRange(lowerBound: range.lowerBound, upperBound: nil),
              labelView: Text(String(title)))
  }

  public nonisolated init(
    _ titleKey: LocalizedStringKey,
    selection: Binding<Date>,
    in range: PartialRangeFrom<Date>,
    displayedComponents: Components = [.hourAndMinute, .date]
  ) where Label == Text {
    self.init(titleKey.resolved, selection: selection, in: range, displayedComponents: displayedComponents)
  }

  @_disfavoredOverload public nonisolated init<S: StringProtocol>(
    _ title: S,
    selection: Binding<Date>,
    in range: PartialRangeThrough<Date>,
    displayedComponents: Components = [.hourAndMinute, .date]
  ) where Label == Text {
    self.init(title: String(title), selection: selection, displayedComponents: displayedComponents,
              range: _DatePickerRange(lowerBound: nil, upperBound: range.upperBound),
              labelView: Text(String(title)))
  }

  public nonisolated init(
    _ titleKey: LocalizedStringKey,
    selection: Binding<Date>,
    in range: PartialRangeThrough<Date>,
    displayedComponents: Components = [.hourAndMinute, .date]
  ) where Label == Text {
    self.init(titleKey.resolved, selection: selection, in: range, displayedComponents: displayedComponents)
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    // Keep the native input in the tree for forms, keyboard input, and
    // progressive enhancement. The browser adapter may add a calendar
    // popover, but this node remains the single source of truth for values.
    let hasDate = displayedComponents.contains(.date) || displayedComponents.isEmpty
    let hasTime = displayedComponents.contains(.hourAndMinute) || displayedComponents.contains(.hourMinuteAndSecond)
    let hasSeconds = displayedComponents.contains(.hourMinuteAndSecond)
    let inputType: String
    if hasDate && hasTime { inputType = "datetime-local" }
    else if hasDate { inputType = "date" }
    else if hasTime { inputType = "time" }
    else { inputType = "date" }
    var calendar = context.environment.calendar
    calendar.timeZone = context.environment.timeZone
    calendar.locale = context.environment.locale
    let localeIdentifier = _datePickerLocaleIdentifier(context.environment.locale)
    let style = context.environment.datePickerStyle
    // A browser's datetime-local control is the only backend primitive that
    // can edit the clock portion without a second Swift/JavaScript bridge.
    // Keep date-only automatic/compact/graphical pickers on the semantic
    // calendar trigger, but leave combined date+time controls native so both
    // portions (including seconds) remain genuinely editable.
    let usesNativeFieldStyle = style == "wheel" || style == "field" || style == "stepperField"
    // `.labelsHidden()` + `.datePickerStyle(.compact)` is the SwiftUI spelling
    // for an inline field that the application decorates itself. Render the
    // native date/time input without framework chrome in that case.
    let labelsHidden = context.environment._labelsHidden
    let plainChrome = labelsHidden && style == "compact"
    let usesNativeControl = !hasDate || usesNativeFieldStyle || hasTime || plainChrome

    let node = _RenderNode.element("label")
    node.classes = ["date-picker"]
    node.attributes["data-control-kind"] = "date-picker"
    node.attributes["data-date-picker"] = "true"
    node.attributes["data-date-picker-calendar"] = hasDate ? "true" : "false"
    node.attributes["data-date-picker-calendar-identifier"] = _datePickerCalendarIdentifier(calendar)
    node.attributes["data-date-picker-components"] = _datePickerComponentsValue(displayedComponents)
    node.attributes["data-date-picker-style"] = style
    node.attributes["data-date-picker-locale"] = localeIdentifier
    node.attributes["data-date-picker-time-zone"] = context.environment.timeZone.identifier
    node.attributes["lang"] = localeIdentifier
    if plainChrome { node.attributes["data-field-chrome"] = "plain" }

    if !labelsHidden {
      let titleNode = _RenderNode.element("span")
      titleNode.classes = ["date-picker-label"]
      let renderedLabel = labelView._render(in: context.child(_FiberKey("label")))
      if !renderedLabel.isEmpty { titleNode.children = [renderedLabel] }
      node.children.append(titleNode)
    }

    let input = _RenderNode.element("input")
    input.classes = ["date-input"]
    input.attributes["data-control-kind"] = "date-input"
    if usesNativeControl { input.classes.append("date-input-native") }
    if plainChrome { input.attributes["data-field-chrome"] = "plain" }
    input.attributes["type"] = inputType
    input.attributes["lang"] = localeIdentifier
    input.attributes["aria-label"] = title.isEmpty ? "Date" : title
    input.attributes["data-date-picker-components"] = _datePickerComponentsValue(displayedComponents)
    input.attributes["data-date-picker-calendar-identifier"] = _datePickerCalendarIdentifier(calendar)
    input.attributes["data-date-picker-time-zone"] = context.environment.timeZone.identifier
    input.attributes["data-date-picker-locale"] = localeIdentifier
    if hasTime { input.attributes["step"] = hasSeconds ? "1" : "60" }
    if let selection {
      let value = _datePickerInputValue(selection.wrappedValue, components: displayedComponents, calendar: calendar, timeZone: context.environment.timeZone)
      input.attributes["value"] = value
      if let sourceID = selection._sourceID {
        input.leafBindings.append(_LeafBindingDescriptor(
          sourceID: sourceID,
          operation: .property("value"),
          value: { _datePickerInputValue(selection.wrappedValue, components: displayedComponents, calendar: calendar, timeZone: context.environment.timeZone) }
        ))
      }
      if let range {
        if let lowerBound = range.lowerBound {
          input.attributes["min"] = _datePickerInputValue(lowerBound, components: displayedComponents, calendar: calendar, timeZone: context.environment.timeZone)
        }
        if let upperBound = range.upperBound {
          input.attributes["max"] = _datePickerInputValue(upperBound, components: displayedComponents, calendar: calendar, timeZone: context.environment.timeZone)
        }
      }
      if context.environment.isEnabled {
        input.events["change"] = _EventHandler(name: "change", action: { rawValue in
          guard let date = _dateFromInput(
            rawValue,
            components: displayedComponents,
            existing: selection.wrappedValue,
            calendar: calendar,
            timeZone: context.environment.timeZone
          ), _datePickerDateIsInRange(date, range: range, components: displayedComponents, calendar: calendar, timeZone: context.environment.timeZone) else { return }
          selection.wrappedValue = date
        })
      }
    } else {
      input.attributes["readonly"] = "readonly"
      input.attributes["aria-readonly"] = "true"
    }
    if !context.environment.isEnabled {
      input.attributes["disabled"] = "disabled"
      input.attributes["aria-disabled"] = "true"
    }

    // Date-only pickers get the calendar trigger. Time-only and combined
    // date+time pickers keep a native field visible so every requested
    // component can be edited instead of presenting an incomplete day grid.
    if hasDate && !usesNativeControl {
      let trigger = _RenderNode.element("button")
      trigger.classes = ["date-picker-trigger"]
      trigger.attributes["type"] = "button"
      trigger.attributes["aria-haspopup"] = "dialog"
      trigger.attributes["aria-expanded"] = "false"
      trigger.attributes["data-date-picker-style"] = style
      trigger.attributes["aria-label"] = title.isEmpty ? "Date" : title
      if !context.environment.isEnabled || selection == nil {
        trigger.attributes["disabled"] = "disabled"
        trigger.attributes["aria-disabled"] = "true"
      }

      let value = _RenderNode.element("span")
      value.classes = ["date-picker-value"]
      if let selection {
        value.children = [.text(_dateDisplayValue(selection.wrappedValue, components: displayedComponents, calendar: calendar, locale: context.environment.locale, timeZone: context.environment.timeZone))]
      } else {
        value.attributes["data-placeholder"] = title
        value.children = [.text(title)]
      }
      let icon = Image(systemName: "calendar")._render(in: context.child(_FiberKey("calendar-icon")))
      trigger.children = [value, icon]
      node.children.append(trigger)
    } else {
      node.children.append(input)
      return node
    }
    // `input` was appended after the label only once. Date-only controls keep
    // it hidden behind the semantic trigger; native controls returned above
    // retain their input directly in the tree.
    if !node.children.contains(where: { $0 === input }) { node.children.insert(input, at: labelsHidden ? 0 : 1) }
    return node
  }
}

/// A calendar control that can select more than one civil date.
///
/// The selection intentionally uses `Set<DateComponents>`, matching SwiftUI's
/// API.  Dates are compared by their year/month/day fields in the active
/// calendar, so callers may supply components created with a different
/// calendar or time zone without losing selection state.
public nonisolated struct MultiDatePicker<Label: View>: View {
  public typealias Body = Never

  package let title: String
  package let selection: Binding<Set<DateComponents>>
  private let range: _DatePickerRange?
  private let labelView: Label
  @State private var displayedMonth: Date

  private init(
    title: String,
    selection: Binding<Set<DateComponents>>,
    range: _DatePickerRange?,
    labelView: Label,
    initialMonth: Date
  ) {
    self.title = title
    self.selection = selection
    self.range = range
    self.labelView = labelView
    self._displayedMonth = State(wrappedValue: initialMonth)
  }

  // MARK: Labeled by a view

  public nonisolated init(selection: Binding<Set<DateComponents>>, @ViewBuilder label: () -> Label) {
    self.init(title: "", selection: selection, range: nil, labelView: label(),
              initialMonth: _multiDatePickerInitialMonth(selection.wrappedValue))
  }

  public nonisolated init(selection: Binding<Set<DateComponents>>, in range: Range<Date>, @ViewBuilder label: () -> Label) {
    self.init(
      title: "", selection: selection,
      range: _DatePickerRange(lowerBound: range.lowerBound, upperBound: range.upperBound, upperIsExclusive: true),
      labelView: label(),
      initialMonth: _multiDatePickerInitialMonth(selection.wrappedValue, fallback: range.lowerBound)
    )
  }

  public nonisolated init(selection: Binding<Set<DateComponents>>, in range: PartialRangeFrom<Date>, @ViewBuilder label: () -> Label) {
    self.init(
      title: "", selection: selection,
      range: _DatePickerRange(lowerBound: range.lowerBound, upperBound: nil),
      labelView: label(),
      initialMonth: _multiDatePickerInitialMonth(selection.wrappedValue, fallback: range.lowerBound)
    )
  }

  public nonisolated init(selection: Binding<Set<DateComponents>>, in range: PartialRangeUpTo<Date>, @ViewBuilder label: () -> Label) {
    self.init(
      title: "", selection: selection,
      range: _DatePickerRange(lowerBound: nil, upperBound: range.upperBound, upperIsExclusive: true),
      labelView: label(),
      initialMonth: _multiDatePickerInitialMonth(selection.wrappedValue, fallback: range.upperBound)
    )
  }

  // MARK: Labeled by a title

  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, selection: Binding<Set<DateComponents>>) where Label == Text {
    self.init(title: String(title), selection: selection, range: nil, labelView: Text(String(title)),
              initialMonth: _multiDatePickerInitialMonth(selection.wrappedValue))
  }

  public nonisolated init(_ titleKey: LocalizedStringKey, selection: Binding<Set<DateComponents>>) where Label == Text {
    self.init(titleKey.resolved, selection: selection)
  }

  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, selection: Binding<Set<DateComponents>>, in range: Range<Date>) where Label == Text {
    self.init(
      title: String(title), selection: selection,
      range: _DatePickerRange(lowerBound: range.lowerBound, upperBound: range.upperBound, upperIsExclusive: true),
      labelView: Text(String(title)),
      initialMonth: _multiDatePickerInitialMonth(selection.wrappedValue, fallback: range.lowerBound)
    )
  }

  public nonisolated init(_ titleKey: LocalizedStringKey, selection: Binding<Set<DateComponents>>, in range: Range<Date>) where Label == Text {
    self.init(titleKey.resolved, selection: selection, in: range)
  }

  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, selection: Binding<Set<DateComponents>>, in range: PartialRangeFrom<Date>) where Label == Text {
    self.init(
      title: String(title), selection: selection,
      range: _DatePickerRange(lowerBound: range.lowerBound, upperBound: nil),
      labelView: Text(String(title)),
      initialMonth: _multiDatePickerInitialMonth(selection.wrappedValue, fallback: range.lowerBound)
    )
  }

  public nonisolated init(_ titleKey: LocalizedStringKey, selection: Binding<Set<DateComponents>>, in range: PartialRangeFrom<Date>) where Label == Text {
    self.init(titleKey.resolved, selection: selection, in: range)
  }

  @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, selection: Binding<Set<DateComponents>>, in range: PartialRangeUpTo<Date>) where Label == Text {
    self.init(
      title: String(title), selection: selection,
      range: _DatePickerRange(lowerBound: nil, upperBound: range.upperBound, upperIsExclusive: true),
      labelView: Text(String(title)),
      initialMonth: _multiDatePickerInitialMonth(selection.wrappedValue, fallback: range.upperBound)
    )
  }

  public nonisolated init(_ titleKey: LocalizedStringKey, selection: Binding<Set<DateComponents>>, in range: PartialRangeUpTo<Date>) where Label == Text {
    self.init(titleKey.resolved, selection: selection, in: range)
  }

  @MainActor public func _render(in context: _RenderContext) -> _RenderNode {
    var calendar = context.environment.calendar
    calendar.timeZone = context.environment.timeZone
    calendar.locale = context.environment.locale
    let localeIdentifier = _datePickerLocaleIdentifier(context.environment.locale)
    let selected = selection.wrappedValue
    var monthDate = _multiDatePickerStartOfMonth(displayedMonth, calendar: calendar, timeZone: context.environment.timeZone)
    // A range-only picker with no selected dates should still open on the
    // first usable month. This second, environment-aware check fixes civil
    // month boundaries when the range instant is near midnight in a different
    // time zone than the picker state was initialized with.
    if selected.isEmpty, let range,
       !_multiDatePickerMonthIsSelectable(monthDate, calendar: calendar, timeZone: context.environment.timeZone, range: range),
       let anchor = range.lowerBound ?? range.upperBound {
      monthDate = _multiDatePickerStartOfMonth(anchor, calendar: calendar, timeZone: context.environment.timeZone)
    }
    let monthTitle = _multiDatePickerMonthTitle(monthDate, calendar: calendar, locale: context.environment.locale, timeZone: context.environment.timeZone)
    let days = _multiDatePickerMonthDays(monthDate, calendar: calendar, timeZone: context.environment.timeZone)
    let root = _RenderNode.element("div")
    root.classes = ["multi-date-picker"]
    root.attributes["data-multi-date-picker"] = "true"
    root.attributes["data-multi-date-picker-calendar-identifier"] = _datePickerCalendarIdentifier(calendar)
    root.attributes["data-multi-date-picker-first-weekday"] = String(calendar.firstWeekday)
    root.attributes["data-multi-date-picker-locale"] = localeIdentifier
    root.attributes["data-multi-date-picker-time-zone"] = context.environment.timeZone.identifier
    root.attributes["lang"] = localeIdentifier
    root.attributes["role"] = "group"
    if !title.isEmpty { root.attributes["aria-label"] = title }
    root.attributes["data-selected-count"] = String(selected.count)
    if let lowerBound = range?.lowerBound {
      root.attributes["data-min-date"] = _datePickerInputValue(lowerBound, components: .date, calendar: calendar, timeZone: context.environment.timeZone)
    }
    if let upperBound = range?.upperBound {
      // The last selectable instant is just before an exclusive upper bound.
      let last = range?.upperIsExclusive == true ? upperBound.addingTimeInterval(-1) : upperBound
      root.attributes["data-max-date"] = _datePickerInputValue(last, components: .date, calendar: calendar, timeZone: context.environment.timeZone)
    }
    if !context.environment.isEnabled {
      root.attributes["aria-disabled"] = "true"
    }

    let labelNode = _RenderNode.element("div")
    labelNode.classes = ["multi-date-picker-label"]
    let rendered = labelView._render(in: context.child(_FiberKey("label")))
    if !rendered.isEmpty { labelNode.children = [rendered] }
    root.children.append(labelNode)

    let header = _RenderNode.element("div")
    header.classes = ["multi-date-picker-header"]
    header.attributes["role"] = "group"
    let previous = _RenderNode.element("button")
    previous.classes = ["multi-date-picker-nav"]
    previous.attributes["type"] = "button"
    previous.attributes["aria-label"] = _multiDatePickerLocalizedString("Previous month", locale: context.environment.locale)
    previous.children = [.text("‹")]
    let previousMonth = calendar.date(byAdding: .month, value: -1, to: monthDate) ?? monthDate
    if context.environment.isEnabled && _multiDatePickerMonthIsSelectable(previousMonth, calendar: calendar, timeZone: context.environment.timeZone, range: range) {
      previous.events["click"] = _EventHandler(name: "click", action: {
        displayedMonth = previousMonth
      })
    } else {
      previous.attributes["disabled"] = "disabled"
      previous.attributes["aria-disabled"] = "true"
    }
    let month = _RenderNode.element("span")
    month.classes = ["multi-date-picker-month"]
    month.attributes["aria-live"] = "polite"
    month.children = [.text(monthTitle)]
    let next = _RenderNode.element("button")
    next.classes = ["multi-date-picker-nav"]
    next.attributes["type"] = "button"
    next.attributes["aria-label"] = _multiDatePickerLocalizedString("Next month", locale: context.environment.locale)
    next.children = [.text("›")]
    let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthDate) ?? monthDate
    if context.environment.isEnabled && _multiDatePickerMonthIsSelectable(nextMonth, calendar: calendar, timeZone: context.environment.timeZone, range: range) {
      next.events["click"] = _EventHandler(name: "click", action: {
        displayedMonth = nextMonth
      })
    } else {
      next.attributes["disabled"] = "disabled"
      next.attributes["aria-disabled"] = "true"
    }
    header.children = [previous, month, next]
    root.children.append(header)

    let grid = _RenderNode.element("div")
    grid.classes = ["multi-date-picker-grid"]
    grid.attributes["role"] = "grid"
    grid.attributes["aria-multiselectable"] = "true"
    grid.attributes["aria-label"] = monthTitle
    let weekdays = _multiDatePickerWeekdaySymbols(calendar: calendar, locale: context.environment.locale)
    for (index, weekday) in weekdays.enumerated() {
      let weekdayNode = _RenderNode.element("span")
      weekdayNode.key = _FiberKey("weekday-\(index)")
      weekdayNode.classes = ["multi-date-picker-weekday"]
      weekdayNode.attributes["role"] = "columnheader"
      weekdayNode.attributes["aria-label"] = weekday
      weekdayNode.children = [.text(weekday)]
      grid.children.append(weekdayNode)
    }

    let firstWeekday = days.first.map { calendar.component(.weekday, from: $0.date) } ?? calendar.firstWeekday
    let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
    for index in 0..<leading {
      let blank = _RenderNode.element("span")
      blank.key = _FiberKey("blank-\(index)")
      blank.classes = ["multi-date-picker-blank"]
      blank.attributes["aria-hidden"] = "true"
      grid.children.append(blank)
    }
    for day in days {
      let dayNode = _RenderNode.element("button")
      dayNode.key = _FiberKey("day-\(day.year)-\(day.month)-\(day.day)")
      dayNode.classes = ["multi-date-picker-day"]
      dayNode.attributes["type"] = "button"
      dayNode.attributes["role"] = "gridcell"
      dayNode.attributes["data-date"] = "\(_fourDigits(day.year))-\(_twoDigits(day.month))-\(_twoDigits(day.day))"
      let isSelected = selected.contains { _multiDatePickerComponentsMatch($0, year: day.year, month: day.month, day: day.day) }
      dayNode.attributes["data-selected"] = isSelected ? "true" : "false"
      dayNode.attributes["aria-pressed"] = isSelected ? "true" : "false"
      dayNode.attributes["aria-label"] = _dateDisplayValue(day.date, components: .date, calendar: calendar, locale: context.environment.locale, timeZone: context.environment.timeZone)
      if calendar.isDateInToday(day.date) { dayNode.attributes["aria-current"] = "date" }
      let inRange = _datePickerDateIsInRange(day.date, range: range, components: .date, calendar: calendar, timeZone: context.environment.timeZone)
      if !context.environment.isEnabled || !inRange {
        dayNode.attributes["disabled"] = "disabled"
        dayNode.attributes["aria-disabled"] = "true"
      } else {
        dayNode.events["click"] = _EventHandler(name: "click", action: {
          var nextSelection = selection.wrappedValue
          let matching = nextSelection.filter { _multiDatePickerComponentsMatch($0, year: day.year, month: day.month, day: day.day) }
          if matching.isEmpty {
            nextSelection.insert(DateComponents(year: day.year, month: day.month, day: day.day))
          } else {
            for existing in matching { nextSelection.remove(existing) }
          }
          selection.wrappedValue = nextSelection
        })
      }
      dayNode.children = [.text(String(day.day))]
      grid.children.append(dayNode)
    }
    let trailing = (7 - ((leading + days.count) % 7)) % 7
    for index in 0..<trailing {
      let blank = _RenderNode.element("span")
      blank.key = _FiberKey("trailing-\(index)")
      blank.classes = ["multi-date-picker-blank"]
      blank.attributes["aria-hidden"] = "true"
      grid.children.append(blank)
    }
    root.children.append(grid)
    let summary = _RenderNode.element("span")
    summary.classes = ["multi-date-picker-selection-summary"]
    summary.attributes["aria-live"] = "polite"
    summary.children = [.text(_multiDatePickerSelectionSummary(selected.count, locale: context.environment.locale))]
    root.children.append(summary)
    return root
  }
}
private func _datePickerComponentsValue(_ components: DatePickerComponents) -> String {
  var values: [String] = []
  if components.contains(.date) || components.isEmpty { values.append("date") }
  if components.contains(.hourAndMinute) { values.append("hourAndMinute") }
  if components.contains(.hourMinuteAndSecond) { values.append("hourMinuteAndSecond") }
  return values.joined(separator: ",")
}

@inline(__always)
private func _datePickerCalendarIdentifier(_ calendar: Calendar) -> String {
  switch calendar.identifier {
  case .gregorian: return "gregorian"
  case .iso8601: return "iso8601"
  }
}

private func _datePickerLocaleIdentifier(_ locale: Locale) -> String {
  locale.identifier.split(separator: "_").joined(separator: "-")
}

private func _datePickerInputValue(
  _ date: Date,
  components: DatePickerComponents,
  calendar: Calendar,
  timeZone: TimeZone
) -> String {
  var calendar = calendar
  calendar.timeZone = timeZone
  let fields = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
  let hasDate = components.contains(.date) || components.isEmpty
  let hasTime = components.contains(.hourAndMinute) || components.contains(.hourMinuteAndSecond)
  let hasSeconds = components.contains(.hourMinuteAndSecond)
  // The HTML date input takes years 0001...9999 only; a date outside them is written at the nearest bound.
  let dateOnly = "\(_fourDigits(Swift.min(Swift.max(fields.year ?? 1970, 1), 9999)))-\(_twoDigits(fields.month ?? 1))-\(_twoDigits(fields.day ?? 1))"
  guard hasTime else { return dateOnly }
  let timeOnly = "\(_twoDigits(fields.hour ?? 0)):\(_twoDigits(fields.minute ?? 0))" + (hasSeconds ? ":\(_twoDigits(fields.second ?? 0))" : "")
  return hasDate ? dateOnly + "T" + timeOnly : timeOnly
}

private func _dateDisplayValue(
  _ date: Date,
  components: DatePickerComponents,
  calendar: Calendar,
  locale: Locale,
  timeZone: TimeZone
) -> String {
  let hasDate = components.contains(.date) || components.isEmpty
  let hasTime = components.contains(.hourAndMinute) || components.contains(.hourMinuteAndSecond)
  let seconds = components.contains(.hourMinuteAndSecond)
  // Keep the compact date trigger's value canonical and round-trippable.
  // Browser-native Intl is still used for month/weekday labels and textual
  // date formatting, but a date-only control must not change its visible
  // shape with the user's browser locale (or invalidate visual baselines).
  if !hasTime {
    return _datePickerInputValue(date, components: components, calendar: calendar, timeZone: timeZone)
  }
  let style: _BrowserDateFormatStyle = hasDate
    ? (hasTime ? (seconds ? .longDateSecondTime : .longDateShortTime) : .longDate)
    : (seconds ? .secondPickerTime : .shortPickerTime)
  if let value = _BrowserDateFormatting.format(.init(
    epochSeconds: date.timeIntervalSince1970, style: style, locale: locale._formatterTag,
    calendar: calendar.identifier == .iso8601 ? "iso8601" : "gregory",
    offsetSeconds: timeZone.secondsFromGMT(for: date)
  )) { return value }
  // Deterministic, unambiguous output on hosts without an Intl provider.
  return _datePickerInputValue(date, components: components, calendar: calendar, timeZone: timeZone)
}

private func _dateFromInput(
  _ value: String,
  components: DatePickerComponents,
  existing: Date,
  calendar: Calendar,
  timeZone: TimeZone
) -> Date? {
  var calendar = calendar
  calendar.timeZone = timeZone
  let hasDate = components.contains(.date) || components.isEmpty
  let hasTime = components.contains(.hourAndMinute) || components.contains(.hourMinuteAndSecond)
  let hasSeconds = components.contains(.hourMinuteAndSecond)
  let parts = value.split(separator: "T", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
  let datePart = hasDate ? (parts.first ?? value) : nil
  let timePart = hasTime ? (parts.count > 1 ? parts[1] : (hasDate ? nil : parts.first)) : nil
  var previous = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: existing)
  if let datePart {
    let fields = datePart.split(separator: "-")
    guard fields.count == 3,
          let year = Int(fields[0]), let month = Int(fields[1]), let day = Int(fields[2]),
          (1...12).contains(month), (1...31).contains(day) else { return nil }
    previous.year = year; previous.month = month; previous.day = day
  }
  if let timePart {
    let fields = timePart.split(separator: ":")
    guard fields.count >= 2,
          let hour = Int(fields[0]), let minute = Int(fields[1]),
          (0...23).contains(hour), (0...59).contains(minute) else { return nil }
    previous.hour = hour; previous.minute = minute
    if hasSeconds {
      guard fields.count >= 3, let second = Int(fields[2]), (0...59).contains(second) else { return nil }
      previous.second = second
    } else {
      previous.second = 0
    }
  }
  var dateComponents = DateComponents()
  dateComponents.calendar = calendar
  dateComponents.timeZone = timeZone
  dateComponents.year = previous.year; dateComponents.month = previous.month; dateComponents.day = previous.day
  dateComponents.hour = previous.hour ?? 0; dateComponents.minute = previous.minute ?? 0; dateComponents.second = previous.second ?? 0
  let candidate = calendar.date(from: dateComponents)
  guard let candidate else { return nil }
  // Foundation normalizes invalid civil dates. Reject those values rather
  // than silently turning February 31 into a day in March.
  let roundTrip = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: candidate)
  guard roundTrip.year == dateComponents.year,
        roundTrip.month == dateComponents.month,
        roundTrip.day == dateComponents.day,
        roundTrip.hour == dateComponents.hour,
        roundTrip.minute == dateComponents.minute,
        roundTrip.second == dateComponents.second else { return nil }
  return candidate
}

private func _datePickerDateIsInRange(
  _ date: Date,
  range: _DatePickerRange?,
  components: DatePickerComponents,
  calendar: Calendar,
  timeZone: TimeZone
) -> Bool {
  guard let range else { return true }
  var calendar = calendar
  calendar.timeZone = timeZone
  let hasTime = components.contains(.hourAndMinute) || components.contains(.hourMinuteAndSecond)
  func comparable(_ value: Date) -> Date {
    hasTime ? value : calendar.startOfDay(for: value)
  }
  let candidate = comparable(date)
  if let lower = range.lowerBound, candidate < comparable(lower) { return false }
  if let upper = range.upperBound {
    if range.upperIsExclusive {
      if candidate >= upper { return false }
    } else if candidate > comparable(upper) {
      return false
    }
  }
  return true
}

private struct _MultiDatePickerDay {
  let date: Date
  let year: Int
  let month: Int
  let day: Int
}

private func _multiDatePickerInitialMonth(_ selection: Set<DateComponents>, fallback: Date? = nil) -> Date {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let candidates = selection.compactMap { component -> Date? in
    guard let year = component.year, let month = component.month, let day = component.day else { return nil }
    // DateComponents produced by Calendar.dateComponents often carry their
    // source calendar. Preserve it when available so a Buddhist, Islamic,
    // or other non-Gregorian selection opens on the expected civil month.
    var componentCalendar = component.calendar ?? calendar
    if let componentTimeZone = component.timeZone { componentCalendar.timeZone = componentTimeZone }
    var value = DateComponents()
    value.calendar = componentCalendar
    value.timeZone = componentCalendar.timeZone
    value.year = year; value.month = month; value.day = day
    // Anchor the civil date at midday to avoid opening on the previous day
    // when the active environment later uses a negative time-zone offset.
    value.hour = 12
    return componentCalendar.date(from: value)
  }
  return _multiDatePickerStartOfMonth(candidates.min() ?? fallback ?? Date(), calendar: calendar, timeZone: calendar.timeZone)
}

private func _multiDatePickerStartOfMonth(
  _ date: Date,
  calendar: Calendar,
  timeZone: TimeZone
) -> Date {
  var calendar = calendar
  calendar.timeZone = timeZone
  let fields = calendar.dateComponents([.year, .month], from: date)
  var components = DateComponents()
  components.calendar = calendar
  components.timeZone = timeZone
  components.year = fields.year ?? 1970
  components.month = fields.month ?? 1
  components.day = 1
  components.hour = 0
  components.minute = 0
  components.second = 0
  return calendar.date(from: components) ?? date
}

private func _multiDatePickerMonthDays(
  _ monthDate: Date,
  calendar: Calendar,
  timeZone: TimeZone
) -> [_MultiDatePickerDay] {
  var calendar = calendar
  calendar.timeZone = timeZone
  let fields = calendar.dateComponents([.year, .month], from: monthDate)
  guard let year = fields.year, let month = fields.month else { return [] }
  var days: [_MultiDatePickerDay] = []
  // A civil month is at most 31 days. Construct each component and round
  // trip through Calendar so leap years, non-Gregorian calendars and invalid
  // dates are handled by the active calendar rather than fixed web rules.
  for day in 1...31 {
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = timeZone
    components.year = year; components.month = month; components.day = day
    guard let date = calendar.date(from: components) else { break }
    let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
    guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else { break }
    days.append(_MultiDatePickerDay(date: date, year: year, month: month, day: day))
  }
  return days
}

private func _multiDatePickerMonthIsSelectable(
  _ monthDate: Date,
  calendar: Calendar,
  timeZone: TimeZone,
  range: _DatePickerRange?
) -> Bool {
  guard let range else { return true }
  return _multiDatePickerMonthDays(monthDate, calendar: calendar, timeZone: timeZone).contains {
    _datePickerDateIsInRange($0.date, range: range, components: .date, calendar: calendar, timeZone: timeZone)
  }
}

private func _multiDatePickerComponentsMatch(_ value: DateComponents, year: Int, month: Int, day: Int) -> Bool {
  value.year == year && value.month == month && value.day == day
}

private func _multiDatePickerMonthTitle(
  _ date: Date,
  calendar: Calendar,
  locale: Locale,
  timeZone: TimeZone
) -> String {
  if let value = _BrowserDateFormatting.format(.init(
    epochSeconds: date.timeIntervalSince1970, style: .monthYear, locale: locale._formatterTag,
    calendar: calendar.identifier == .iso8601 ? "iso8601" : "gregory",
    offsetSeconds: timeZone.secondsFromGMT(for: date)
  )) { return value }
  var displayCalendar = calendar
  displayCalendar.timeZone = timeZone
  let fields = displayCalendar.dateComponents([.year, .month], from: date)
  let names = _multiDatePickerMonthNames(locale: locale)
  guard let month = fields.month, (1...names.count).contains(month) else { return "\(fields.year ?? 1970)" }
  return "\(names[month - 1]) \(fields.year ?? 1970)"
}

private func _multiDatePickerWeekdaySymbols(calendar: Calendar, locale: Locale) -> [String] {
  let start = max(0, min(6, calendar.firstWeekday - 1))
  // 1970-01-04 is Sunday in UTC. This formats names, not calendar arithmetic.
  let localized = (0..<7).compactMap { day in
    _BrowserDateFormatting.format(.init(epochSeconds: 259_200 + Double(day) * 86_400,
      style: .narrowWeekday, locale: locale._formatterTag))
  }
  if localized.count == 7 { return Array(localized[start...]) + Array(localized[..<start]) }
  let symbols = _multiDatePickerWeekdayNames(locale: locale)
  return Array(symbols[start...]) + Array(symbols[..<start])
}

private func _multiDatePickerMonthNames(locale: Locale) -> [String] {
  let identifier = locale.identifier.lowercased()
  if identifier.hasPrefix("pt") { return ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"] }
  if identifier.hasPrefix("de") { return ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"] }
  if identifier.hasPrefix("fr") { return ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"] }
  if identifier.hasPrefix("es") { return ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"] }
  return ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
}

private func _multiDatePickerWeekdayNames(locale: Locale) -> [String] {
  let identifier = locale.identifier.lowercased()
  if identifier.hasPrefix("pt") { return ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"] }
  if identifier.hasPrefix("de") { return ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"] }
  if identifier.hasPrefix("fr") { return ["di", "lu", "ma", "me", "je", "ve", "sa"] }
  if identifier.hasPrefix("es") { return ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"] }
  return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
}

private func _multiDatePickerLocalizedString(_ value: String, locale: Locale) -> String {
  let identifier = locale.identifier.lowercased()
  if identifier.hasPrefix("pt") {
    switch value { case "Previous month": return "Mês anterior"; case "Next month": return "Próximo mês"; default: return value }
  }
  if identifier.hasPrefix("de") {
    switch value { case "Previous month": return "Vorheriger Monat"; case "Next month": return "Nächster Monat"; default: return value }
  }
  if identifier.hasPrefix("fr") {
    switch value { case "Previous month": return "Mois précédent"; case "Next month": return "Mois suivant"; default: return value }
  }
  return value
}

private func _multiDatePickerSelectionSummary(_ count: Int, locale: Locale) -> String {
  let identifier = locale.identifier.lowercased()
  if identifier.hasPrefix("pt") { return count == 1 ? "1 data selecionada" : "\(count) datas selecionadas" }
  if identifier.hasPrefix("de") { return count == 1 ? "1 Datum ausgewählt" : "\(count) Daten ausgewählt" }
  if identifier.hasPrefix("fr") { return count == 1 ? "1 date sélectionnée" : "\(count) dates sélectionnées" }
  return count == 1 ? "1 date selected" : "\(count) dates selected"
}
