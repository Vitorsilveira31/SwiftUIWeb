import Testing

@testable import LoweringCore

@Suite struct SimpleRulesTests {
  private func simple(_ source: String) -> LoweringResult { lower(source, rules: ["simple-rules"]) }

  @Test func publicProjectionRules() {
    let result = simple(#"""
      ForEach(rows, id: \.id) { row in Text(row.name) }
      let names = rows.map(\.name)
      TextField(text: $viewModel.title)
      @Environment(\.colorScheme) var scheme
      """#)
    #expect(result.text.contains("id: { $0.id }"))
    #expect(result.text.contains(".map { $0.name }"))
    #expect(result.text.contains("_memberBinding(get: { viewModel.title }, set: { viewModel.title = $0 })"))
    #expect(result.text.contains("@Environment(_embedded: { $0.colorScheme })"))
  }

  @Test func nestedKeyPathsLowerLikeSwiftUI() {
    let result = simple(#"""
      ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in Text(row.name) }
      let titles = works.map(\.title.first)
      """#)
    #expect(result.text.contains("id: { $0.element.id }"))
    #expect(result.text.contains(".map { $0.title.first }"))
  }

  @Test func everyRuleOfTheCollectionAndImportFamilies() {
    let result = simple(#"""
      import Observation
      let a = rows.map(\.name)
      let b = rows.compactMap(\.value).filter(\.isValid)
      let c = rows.flatMap(\.genres)
      ForEach(rows, id: \.self) { _ in EmptyView() }
      ForEach(rows, id: \.id) { _ in EmptyView() }
      ForEach(Item.allCases) { _ in EmptyView() }
      TextField(text: $model.title)
      @Environment(\.colorScheme) var scheme
      OutlineGroup(items, children: \.children)
      KeyframeTrack(\.opacity)
      TableColumn("Title", value: \.title)
      """#)
    for rule in [
      "map-member", "compactMap-member", "flatMap-member", "filter-member", "foreach-id-self", "foreach-id-member",
      "foreach-allcases-rawvalue", "binding-member", "environment-member", "outline-children", "keyframe-track",
      "table-column-value", "observation-import",
    ] {
      #expect((result.counts[rule] ?? 0) > 0, "missing \(rule)")
    }
    #expect(!result.text.contains("import Observation"))
    #expect(result.text.hasPrefix("let a = rows.map { $0.name }\n"))
    #expect(result.text.contains("let b = rows.compactMap { $0.value }.filter { $0.isValid }"))
    #expect(result.text.contains(".flatMap { $0.genres }"))
    #expect(result.text.contains("ForEach(rows, id: { $0 }) {"))
    #expect(result.text.contains("ForEach(Item.allCases, id: { $0 }) {"))
    #expect(result.text.contains("OutlineGroup(items, _embeddedChildren: { $0.children })"))
    #expect(result.text.contains(#"KeyframeTrack(_embeddedMember: "opacity", _embeddedGet: { $0.opacity }, _embeddedSet: { $0.opacity = $1 })"#))
    #expect(result.text.contains(#"TableColumn("Title") { row in Text(row.title) }"#))
    #expect(simple(result.text).text == result.text)

    let rooted = simple(#"TableColumn("Name", value: \Person.name)"#)
    #expect(rooted.text == #"TableColumn("Name") { (row: Person) in Text(row.name) }"#)
  }

  @Test func listIdentitiesBecomeClosures() {
    let result = simple(#"""
      List(rows, id: \.id) { row in Text(row.name) }
      List(tags, id: \.self, selection: $picked) { Text($0) }
      List(items, id: \.owner.id, selection: $one) { _ in EmptyView() }
      List(selection: $picked) { Text("x") }

      """#)
    #expect(result.text.contains("List(rows, id: { $0.id }) { row in"))
    #expect(result.text.contains("List(tags, id: { $0 }, selection: "))
    #expect(result.text.contains("List(items, id: { $0.owner.id }, selection: "))
    #expect(!result.text.contains("\\."))
    #expect(result.counts["list-id-member"] == 3)
  }

  @Test func foreachIdentityMustBeTheLastArgument() {
    let result = simple(#"""
      ForEach(rows, id: \.id, content: { Text($0.name) })
      ForEach(rows, id: \.id) { Text($0.name) }
      ForEach(Dictionary(grouping: rows, by: \.kind).keys.sorted(), id: \.self) { Text($0) }
      """#)
    #expect(result.text.contains(#"ForEach(rows, id: \.id, content:"#))
    #expect(result.text.contains("ForEach(rows, id: { $0.id }) {"))
    #expect(result.text.contains("sorted(), id: { $0 }) {"))
    #expect(result.counts["foreach-id-member"] == 1)
    #expect(result.counts["foreach-id-self"] == 1)
  }

  @Test func collectionMethodsTakeOnlyAPlainKeyPath() {
    let result = simple(#"""
      let a = rows.map(\.name)
      let b = rows.map(\.owner?.name)
      let c = rows.map(\Row.name)
      let d = rows.map(\.items[0])
      let e = rows.map(transform: \.name)
      let f = map(\.name)
      let g = rows
        .filter(\.isOn)
        .compactMap(\.value)
      """#)
    #expect(result.text.contains("let a = rows.map { $0.name }"))
    #expect(result.text.contains(#"rows.map(\.owner?.name)"#))
    #expect(result.text.contains(#"rows.map(\Row.name)"#))
    #expect(result.text.contains(#"rows.map(\.items[0])"#))
    #expect(result.text.contains(#"rows.map(transform: \.name)"#))
    #expect(result.text.contains(#"let f = map(\.name)"#))
    #expect(result.text.contains("\n  .filter { $0.isOn }\n  .compactMap { $0.value }"))
  }

  @Test func bindingMemberLeavesQualifiedProjectionsAlone() {
    let result = simple("""
      Toggle(isOn: $model.enabled)
      await Runtime.$environment.withValue(value) { }
      let x = (Store.$items.count, $flag.wrappedValue)
      let y = self.$model.title

      """)
    #expect(result.text.contains("Toggle(isOn: _memberBinding(get: { model.enabled }"))
    #expect(result.text.contains("await Runtime.$environment.withValue(value) { }"))
    #expect(result.text.contains("Store.$items.count"))
    #expect(result.text.contains(", _memberBinding(get: { flag.wrappedValue }"))
    #expect(result.text.contains("self.$model.title"))
    #expect(result.counts["binding-member"] == 2)
  }

  @Test func projectedBindingReadsItsMemberInTheDeclaringBody() {
    #expect(
      simple("Child(selected: $model.selected)").text
        == "Child(selected: _memberBinding(get: { model.selected }, set: { model.selected = $0 }))"
    )
  }

  @Test func bindingMethodCallsAreNotProjectedThroughTheModel() {
    let result = simple("Toggle(\"Animate\", isOn: $flag.animation())\nTextField(\"\", text: $model.name)\n")
    #expect(result.text.contains("isOn: $flag.animation()"))
    #expect(result.text.contains("_memberBinding(get: { model.name }, set: { model.name = $0 })"))
  }

  @Test func shorthandArgumentsAreNotProjections() {
    let source = "let a = values.map { $0.name }\nlet b = values.map { $1.name }\n"
    #expect(simple(source).text == source)
  }

  @Test func environmentModifierKeyPathsLowerAndTheObjectOverloadStays() {
    let result = simple(#"""
      Text("Schedule")
        .environment(\.timeZone, TimeZone(secondsFromGMT: -10_800)!)
        .environment(ThemeModel())
      """#)
    #expect(result.text.contains(".modifier(EnvironmentOverride(apply: { $0.timeZone = TimeZone(secondsFromGMT: -10_800)! }))"))
    #expect(result.text.contains(".environment(ThemeModel())"))
    #expect(result.counts["environment-modifier"] == 1)
  }

  @Test func environmentModifierOnlyRewritesKeyPathOverrides() {
    let result = simple(#"""
      Text("a")
        .environment(\EnvironmentValues.colorScheme, .dark)
        .environmentObject(store)
        .environment(model)
        .environment(values[key], other)
        .environment(\.locale, )
        .environment(\.font, .body)
      let modifier = view.environment
      let unclosed = view.environment(\.font, .body
      """#)
    // A color scheme marks its subtree, so it lowers to the scheme-carrying override rather than a plain closure.
    #expect(result.text.contains(".modifier(EnvironmentOverride(colorScheme: .dark))"))
    #expect(result.text.contains(".modifier(EnvironmentOverride(apply: { $0.font = .body }))"))
    for untouched in [
      ".environmentObject(store)", ".environment(model)", ".environment(values[key], other)", #".environment(\.locale, )"#,
      "let modifier = view.environment\n",
    ] {
      #expect(result.text.contains(untouched), "\(untouched)")
    }
    #expect(result.counts["environment-modifier"] == 2)
  }

  @Test func environmentModifierValuesThatUseAClosureParameterOrAreClosuresAreLeftAsWritten() {
    // The value moves into a closure of its own: `$0` in it would be captured by that closure instead of the caller's.
    let result = simple(#"""
      Text("a")
        .environment(\.font, .body)
        .environment(\.locale, $0.locale)
        .environment(\.font, { $0 })
        .environment(\.colorScheme, { _ in .dark })
      """#)
    #expect(result.text.contains(".modifier(EnvironmentOverride(apply: { $0.font = .body }))"))
    #expect(result.text.contains(#".environment(\.locale, $0.locale)"#))
    #expect(result.text.contains(#".environment(\.font, { $0 })"#))
    #expect(result.text.contains(#".environment(\.colorScheme, { _ in .dark })"#))
    #expect(result.counts["environment-modifier"] == 1)
    #expect(result.counts["environment-modifier-refused"] == 3)
    // The refused calls are counted once, not once per round of the repeated rule.
    #expect(simple(result.text).counts["environment-modifier-refused"] == 3)
  }

  @Test func environmentModifierValuesMayHoldParenthesesInStringsAndOtherOverrides() {
    let string = simple("Text(\"x\")\n  .environment(\\.title, \")\")\n")
    #expect(string.text.contains(".modifier(EnvironmentOverride(apply: { $0.title = \")\" }))"))
    #expect(simple(string.text).text == string.text)

    let nested = simple(#"Outer().environment(\.a, Inner().environment(\.b, 1))"#)
    #expect(nested.text == "Outer().modifier(EnvironmentOverride(apply: { $0.a = Inner().modifier(EnvironmentOverride(apply: { $0.b = 1 })) }))")
    #expect(nested.counts["environment-modifier"] == 2)
    #expect(simple(nested.text).text == nested.text)

    let nestedKeyPaths = simple(#"view.environment(\.items, rows.map(\.name))"#)
    #expect(nestedKeyPaths.text == "view.modifier(EnvironmentOverride(apply: { $0.items = rows.map { $0.name } }))")
  }

  @Test func hoverClosuresThatOnlyMirrorThePointerIntoStateAreLowered() {
    let result = simple(#"""
      struct Card: View {
        @State private var hovered = false
        @State private var count = 0
        var body: some View {
          Text("a").onHover { hovered = $0 }
          Text("b").onHover { inside in hovered = inside }
          Text("c").onHover { withAnimation(.easeOut(duration: 0.1)) { hovered = $0 } }
          Text("d").onHover { count += 1 }
          Text("e").onHover { if $0 { store.prefetch() } }
          Text("f").onHover { other = $0 }
          Text("g").onHover { hovered = true }
          Text("h").onHover { inside in hovered = $0 }
        }
      }
      """#)
    #expect(result.text.components(separatedBy: ".onHover(_assigning: _hovered)").count - 1 == 3)
    #expect(result.text.contains(".onHover { count += 1 }"))
    #expect(result.text.contains(".onHover { if $0 { store.prefetch() } }"))
    #expect(result.text.contains(".onHover { other = $0 }"))
    #expect(result.text.contains(".onHover { hovered = true }"))
    #expect(result.text.contains(".onHover { inside in hovered = $0 }"))
    #expect(result.counts["hover-assign"] == 3)
    // A file reports every assigning hover it holds, written that way or lowered.
    #expect(simple(result.text).counts["hover-assign"] == 3)
  }

  @Test func hoverTargetsMustBeStateOfTheFile() {
    let result = simple(#"""
      struct A: View {
        @State var hovered = false
        @Binding var bound: Bool
        @State private(set) var narrow = false
        var body: some View {
          Text("a").onHover { hovered = $0 }
          Text("b").onHover { bound = $0 }
          Text("c").onHover { narrow = $0 }
        }
      }
      """#)
    #expect(result.text.contains(".onHover(_assigning: _hovered)"))
    #expect(result.text.contains(".onHover { bound = $0 }"))
    #expect(result.text.contains(".onHover { narrow = $0 }"))
    #expect(result.counts["hover-assign"] == 1)
  }

  @Test func hoverTargetsAreStateOfTheTypeThatHoldsTheHoverClosure() {
    // Two views in one file: the `hovered` of `Second` is not the `@State` of `First`.
    let result = simple(#"""
      struct First: View {
        @State var hovered = false
        var body: some View { Text("a").onHover { hovered = $0 } }
      }
      struct Second: View {
        var hovered = false
        var body: some View { Text("b").onHover { hovered = $0 } }
      }
      extension First {
        var more: some View { Text("c").onHover { hovered = $0 } }
      }
      """#)
    #expect(result.text.contains(#"Text("a").onHover(_assigning: _hovered)"#))
    #expect(result.text.contains(#"Text("b").onHover { hovered = $0 }"#))
    #expect(result.text.contains(#"Text("c").onHover(_assigning: _hovered)"#))
    #expect(result.counts["hover-assign"] == 2)
  }

  @Test func contentBuilderLowersIdempotentlyWithoutTouchingNonCode() {
    let result = simple(#"""
      // @ContentBuilder in a comment
      let documentation = "@ContentBuilder inside a string"
      struct Example {
        @ContentBuilder var body: some View { Text("body") }
        func make(@ContentBuilder _ content: () -> some View) {}
      }

      """#)
    #expect(result.counts["content-builder-to-view-builder"] == 2)
    #expect(result.text.contains("// @ContentBuilder in a comment"))
    #expect(result.text.contains(#""@ContentBuilder inside a string""#))
    #expect(result.text.contains("@ViewBuilder var body"))
    #expect(result.text.contains("@ViewBuilder _ content"))
    let again = simple(result.text)
    #expect(again.text == result.text)
    #expect(again.counts["content-builder-to-view-builder"] == nil)
  }

  @Test func observationImportGoesWithItsLine() {
    let result = simple("import SwiftUI\n  import Observation\nimport Observation // note\n#if canImport(Observation)\nimport Observation\n#endif\nlet x = 1\n")
    #expect(result.text == "import SwiftUI\nimport Observation // note\n#if canImport(Observation)\n#endif\nlet x = 1\n")
    #expect(result.counts["observation-import"] == 2)
    #expect(simple("import Observation").text == "import Observation")
    #expect(simple("@_exported import Observation\n").text == "@_exported import Observation\n")
  }

  @Test func theTextOfAStringIsNotCodeButItsInterpolationsAre() {
    let result = simple(#"""
      let a = "rows.map(\.name) and $model.title and ForEach(x, id: \.id)"
      let b = "\(rows.map(\.name).joined())"
      // rows.map(\.name) $model.title
      """#)
    #expect(result.text.contains(#"let a = "rows.map(\.name) and $model.title and ForEach(x, id: \.id)""#))
    #expect(result.text.contains(#"let b = "\(rows.map { $0.name }.joined())""#))
    #expect(result.text.contains("// rows.map(\\.name) $model.title"))
  }

  @Test func argumentsMayBeSplitOverLines() {
    let result = simple(#"""
      ForEach(
        sections,
        id: \.id
      ) { section in Text(section.name) }
      OutlineGroup(
        tree.nodes(1, 2),
        children: \.children
      ) { node in Text(node.name) }
      """#)
    #expect(result.text.contains("id: { $0.id }"))
    #expect(result.text.contains("children: \\.children") == false)
    #expect(result.text.contains("_embeddedChildren: { $0.children }"))
  }

  @Test func aKeyPathArgumentIsLoweredBeforeTheIdentityAfterIt() {
    // The key path in the first argument is lowered before the identity that follows it.
    let result = simple(#"ForEach($model.items.map(\.id), id: \.self) { Text($0) }"#)
    #expect(result.text == "ForEach(_memberBinding(get: { model.items }, set: { model.items = $0 }).map { $0.id }, id: { $0 }) { Text($0) }")
  }

  @Test func functionLabelsTakeAKeyPathAsAClosure() {
    let result = simple(#"""
      let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      let words = last.body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      let index = rows.firstIndex(where: \.isSelected)
      let rest = letters.drop(while: \.isSpace)
      let groups = Dictionary(grouping: rows, by: \.kind)
      let valid = rows.allSatisfy(\.isValid)
      let counts = table.mapValues(\.count)
      """#)
    #expect(result.text.contains("split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })"))
    #expect(result.text.contains(#"split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")"#))
    #expect(result.text.contains("firstIndex(where: { $0.isSelected })"))
    #expect(result.text.contains("drop(while: { $0.isSpace })"))
    #expect(result.text.contains("Dictionary(grouping: rows, by: { $0.kind })"))
    #expect(result.text.contains("rows.allSatisfy { $0.isValid }"))
    #expect(result.text.contains("table.mapValues { $0.count }"))
    #expect(result.counts["labeled-function-member"] == 5)
    #expect(result.counts["allSatisfy-member"] == 1)
    #expect(result.counts["mapValues-member"] == 1)
    #expect(simple(result.text).text == result.text)
  }

  @Test func keyPathArgumentsOfKeyPathAPIsStayKeyPaths() {
    let source = #"""
      let sorted = rows.sorted(using: KeyPathComparator(\.name))
      let value = rows[keyPath: \.name]
      let nested = rows.firstIndex(where: \Row.isSelected)
      let optional = rows.firstIndex(where: \.owner?.isSelected)
      let subscripted = rows.firstIndex(where: \.items[0])
      let mixed = make(by: \.kind, value: \.count)
      let named = rows.first(where: isSelected)
      let id = rows.first(id: \.id)
      """#
    let result = simple(source)
    #expect(result.text.contains(#"sorted(using: KeyPathComparator(\.name))"#))
    #expect(result.text.contains(#"rows[keyPath: \.name]"#))
    #expect(result.text.contains(#"firstIndex(where: \Row.isSelected)"#))
    #expect(result.text.contains(#"firstIndex(where: \.owner?.isSelected)"#))
    #expect(result.text.contains(#"firstIndex(where: \.items[0])"#))
    #expect(result.text.contains(#"make(by: \.kind, value: \.count)"#))
    #expect(result.text.contains("rows.first(where: isSelected)"))
    #expect(result.text.contains(#"rows.first(id: \.id)"#))
    #expect((result.counts["labeled-function-member"] ?? 0) == 0)
    #expect((result.counts["allSatisfy-member"] ?? 0) == 0)
  }

  @Test func environmentAndIdentityKeyPathsAreNotFunctionArguments() {
    let result = simple(#"""
      @Environment(\.dismiss) var dismiss
      ForEach(rows, id: \.self) { Text($0) }
      """#)
    #expect(result.text.contains("@Environment(_embedded: { $0.dismiss })"))
    #expect(result.text.contains("ForEach(rows, id: { $0 })"))
    #expect((result.counts["labeled-function-member"] ?? 0) == 0)
  }

  @Test func bindableMembersMakeBindingsOfTheModel() {
    let result = simple(#"""
      TextEditor(text: Bindable(model).source)
      Toggle(isOn: Bindable(model).showsSource) { Text("Source") }
      Button("Open").sheet(isPresented: Bindable(self.model).showsContents) { }
      TextField(text: Bindable(store.session).draft.title)
      """#)
    #expect(result.text.contains("TextEditor(text: _memberBinding(get: { model.source }, set: { model.source = $0 }))"))
    #expect(result.text.contains("Toggle(isOn: _memberBinding(get: { model.showsSource }, set: { model.showsSource = $0 })) { Text(\"Source\") }"))
    #expect(result.text.contains("isPresented: _memberBinding(get: { self.model.showsContents }, set: { self.model.showsContents = $0 })"))
    #expect(result.text.contains("_memberBinding(get: { store.session.draft.title }, set: { store.session.draft.title = $0 })"))
    #expect(result.counts["bindable-member"] == 4)
    #expect(simple(result.text).text == result.text)
  }

  @Test func bindableLeavesTheModelAndCallsAlone() {
    let source = """
      let whole = Bindable(model)
      let run = Bindable(model).run()
      let made = Bindable(makeModel()).source
      let indexed = Bindable(models[0]).source
      let plain = Bindable(model, extra).source

      """
    let result = simple(source)
    #expect(result.text == source)
    #expect((result.counts["bindable-member"] ?? 0) == 0)
  }

  @Test func bindableMemberOfACalledBindingIsStillLowered() {
    #expect(
      simple("Toggle(isOn: Bindable(model).flag.animation())").text
        == "Toggle(isOn: _memberBinding(get: { model.flag }, set: { model.flag = $0 }).animation())"
    )
  }
}
