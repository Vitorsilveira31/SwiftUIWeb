import SwiftUIWeb

/// Hidden fixture (`/stackDepth`) that nests erased views to a chosen depth, to measure how deep a view tree the
/// browser's WebAssembly call stack can render (WebKit's is the smallest). Each level is a padded VStack around an
/// `AnyView` of the next level; the innermost Text is `depth-leaf`. The padding is a layout node of its own, so the
/// padded variant has two layout nodes per level and the unpadded one (`plain-N`) has one.
/// The other variants nest through something else than stacks, to cover each kind of place a render is staged:
/// `eager-N` through a modifier that is applied in render order (`onChange`), `pref-N` through preference writers and
/// readers, `sheet-N` through presentation modifiers, `nav-N` through navigation modifiers inside a `NavigationStack`,
/// `anim-N` through `.animation`, `custom-N` through a `ViewModifier` with its own `body`, `forcing-N` through all of
/// those in turn, `form-N`, `section-N`, `disclosure-N`, `groupbox-N`, `labeled-N` and `menu-N` through those containers,
/// `chain-N` through one modifier, `mods-N` through a run of modifiers that only write to their node, `if-N` through
/// conditionals, `hstack-N`, `scroll-N`, `list-N` and `grid-N` through those containers, and `mix-N` through all of
/// them in turn. None of them has a stack to stage the render in the way a `VStack` does.
/// `picker-N` nests segmented pickers through their options, `tabview-in-tabview-N` tab views through their tabs
/// (the tab bars take no recursion per level), `tabview-nested-N` tags
/// nested under one tab view, `nav-nested-N` navigation stacks, `equatable-N` equatable views, and
/// `combo-N` all four in turn: containers that gather what their content registered once it has rendered.
struct StackDepthProbe: View, Equatable {
  enum Style: Hashable {
    case padded, plain, chain, eager, mods, conditional, hstack, scroll, list, grid, mix
    case pref, sheet, nav, anim, custom, forcing, form, section, disclosure, groupbox, labeled, menu, group, groups, recurse
    case picker, tabs, tags, navNested, equatable, combo
    case wide, wideForm, wideList
  }
  let depth: Int
  var style = Style.padded

  var body: some View {
    if depth == 0 {
      Text("leaf").accessibilityIdentifier("depth-leaf")
    } else if style == .padded {
      VStack(spacing: 0) {
        AnyView(StackDepthProbe(depth: depth - 1, style: .padded))
      }
      .padding(1)
    } else if style == .plain {
      VStack(spacing: 0) {
        AnyView(StackDepthProbe(depth: depth - 1, style: .plain))
      }
    } else if style == .chain {
      AnyView(StackDepthProbe(depth: depth - 1, style: .chain)).opacity(0.99)
    } else if style == .eager {
      AnyView(StackDepthProbe(depth: depth - 1, style: .eager)).onChange(of: depth) {}
    } else if style == .pref {
      AnyView(StackDepthProbe(depth: depth - 1, style: .pref))
        .preference(key: StackDepthKey.self, value: depth)
        .onPreferenceChange(StackDepthKey.self) { _ in }
    } else if style == .sheet {
      AnyView(StackDepthProbe(depth: depth - 1, style: .sheet))
        .sheet(isPresented: .constant(false)) { Text("sheet \(depth)") }
    } else if style == .nav {
      AnyView(StackDepthProbe(depth: depth - 1, style: .nav))
        .navigationTitle("level \(depth)")
        .navigationDestination(for: Int.self) { Text("destination \($0)") }
        .toolbar { Text("toolbar \(depth)") }
    } else if style == .anim {
      AnyView(StackDepthProbe(depth: depth - 1, style: .anim)).animation(.easeInOut, value: depth)
    } else if style == .custom {
      AnyView(StackDepthProbe(depth: depth - 1, style: .custom)).modifier(StackDepthModifier(level: depth))
    } else if style == .forcing {
      switch depth % 6 {
      case 0: AnyView(StackDepthProbe(depth: depth - 1, style: .forcing)).onChange(of: depth) {}
      case 1:
        AnyView(StackDepthProbe(depth: depth - 1, style: .forcing))
          .preference(key: StackDepthKey.self, value: depth)
          .onPreferenceChange(StackDepthKey.self) { _ in }
      case 2: AnyView(StackDepthProbe(depth: depth - 1, style: .forcing)).sheet(isPresented: .constant(false)) { Text("sheet") }
      case 3: AnyView(StackDepthProbe(depth: depth - 1, style: .forcing)).navigationTitle("level \(depth)")
      case 4: AnyView(StackDepthProbe(depth: depth - 1, style: .forcing)).animation(.easeInOut, value: depth)
      default: AnyView(StackDepthProbe(depth: depth - 1, style: .forcing)).modifier(StackDepthModifier(level: depth))
      }
    } else if style == .form {
      Form { AnyView(StackDepthProbe(depth: depth - 1, style: .form)) }
    } else if style == .section {
      Section("section \(depth)") { AnyView(StackDepthProbe(depth: depth - 1, style: .section)) }
    } else if style == .disclosure {
      DisclosureGroup("group \(depth)") { AnyView(StackDepthProbe(depth: depth - 1, style: .disclosure)) }
    } else if style == .groupbox {
      GroupBox("box \(depth)") { AnyView(StackDepthProbe(depth: depth - 1, style: .groupbox)) }
    } else if style == .labeled {
      LabeledContent("row \(depth)") { AnyView(StackDepthProbe(depth: depth - 1, style: .labeled)) }
    } else if style == .menu {
      Menu("menu \(depth)") { AnyView(StackDepthProbe(depth: depth - 1, style: .menu)) }
    } else if style == .group {
      Group { AnyView(StackDepthProbe(depth: depth - 1, style: .group)) }.opacity(0.99)
    } else if style == .groups {
      Group { Text("g\(depth)"); AnyView(StackDepthProbe(depth: depth - 1, style: .groups)) }.opacity(0.99)
    } else if style == .picker {
      StackDepthPicker(depth: depth, style: .picker)
    } else if style == .tabs {
      StackDepthTabs(depth: depth, style: .tabs)
    } else if style == .tags {
      AnyView(StackDepthProbe(depth: depth - 1, style: .tags)).tag(depth)
    } else if style == .navNested {
      NavigationStack { AnyView(StackDepthProbe(depth: depth - 1, style: .navNested)) }
    } else if style == .equatable {
      StackDepthProbe(depth: depth - 1, style: .equatable).equatable()
    } else if style == .combo {
      switch depth % 4 {
      case 0: StackDepthPicker(depth: depth, style: .combo)
      case 1: StackDepthTabs(depth: depth, style: .combo)
      case 2: NavigationStack { AnyView(StackDepthProbe(depth: depth - 1, style: .combo)) }
      default: StackDepthProbe(depth: depth - 1, style: .combo).equatable()
      }
    } else if style == .wide || style == .wideForm || style == .wideList {
      EmptyView()
    } else if style == .recurse {
      Text("recursed \(stackDepthRecurse(depth))").accessibilityIdentifier("depth-leaf")
    } else if style == .mods {
      AnyView(StackDepthProbe(depth: depth - 1, style: .mods))
        .opacity(0.99)
        .foregroundColor(.red)
        .id(depth)
        .accessibilityLabel("level \(depth)")
        .font(.body)
        .onTapGesture {}
    } else if style == .conditional {
      if depth % 2 == 0 {
        StackDepthProbe(depth: depth - 1, style: .conditional)
      } else {
        StackDepthProbe(depth: depth - 1, style: .conditional).opacity(0.99)
      }
    } else if style == .hstack {
      HStack(spacing: 0) {
        if depth % 4 == 0 { Spacer(minLength: 0) }
        AnyView(StackDepthProbe(depth: depth - 1, style: .hstack))
      }
    } else if style == .scroll {
      ScrollView { AnyView(StackDepthProbe(depth: depth - 1, style: .scroll)) }
    } else if style == .list {
      List { AnyView(StackDepthProbe(depth: depth - 1, style: .list)) }
    } else if style == .grid {
      Grid { GridRow { AnyView(StackDepthProbe(depth: depth - 1, style: .grid)) } }
    } else {
      switch depth % 5 {
      case 0: HStack(spacing: 0) { Spacer(minLength: 0); AnyView(StackDepthProbe(depth: depth - 1, style: .mix)) }
      case 1: ScrollView(.horizontal) { StackDepthProbe(depth: depth - 1, style: .mix).opacity(0.99) }
      case 2: VStack(spacing: 0) { StackDepthProbe(depth: depth - 1, style: .mix) }
      case 3: ZStack { StackDepthProbe(depth: depth - 1, style: .mix) }
      default: StackDepthProbe(depth: depth - 1, style: .mix).foregroundColor(.blue).id(depth)
      }
    }
  }
}

/// A segmented picker whose only options hold the next level.
struct StackDepthPicker: View {
  let depth: Int
  let style: StackDepthProbe.Style
  var body: some View {
    Picker("level \(depth)", selection: .constant(0)) {
      AnyView(StackDepthProbe(depth: depth - 1, style: style)).tag(0)
      Text("other").tag(1)
    }
    .pickerStyle(.segmented)
  }
}

/// A tab view whose only tab holds the next level.
struct StackDepthTabs: View {
  let depth: Int
  let style: StackDepthProbe.Style
  var body: some View {
    TabView {
      Tab("tab \(depth)", systemImage: "circle") {
        AnyView(StackDepthProbe(depth: depth - 1, style: style))
      }
    }
  }
}

nonisolated(unsafe) private var stackDepthSink = 0

/// Application code that recurses by itself, once per unit of `depth`: staging cannot cut a recursion the framework does
/// not own, so a deep one is what is left to overflow a Worker's call stack (`recurse-N`, the safety net's test case).
/// The two functions call each other and write a global after the call, which no optimization can turn into a loop.
@inline(never) private func stackDepthRecurseEven(_ n: Int) -> Int {
  if n <= 0 { return stackDepthSink }
  let inner = stackDepthRecurseOdd(n - 1)
  stackDepthSink &+= n
  return inner &+ 1
}

@inline(never) private func stackDepthRecurseOdd(_ n: Int) -> Int {
  if n <= 0 { return stackDepthSink }
  let inner = stackDepthRecurseEven(n - 1)
  stackDepthSink ^= n
  return inner &+ 2
}

private func stackDepthRecurse(_ n: Int) -> Int { stackDepthRecurseEven(n) & 0xff }

/// The preference the `pref` and `forcing` variants write and read at every level.
struct StackDepthKey: PreferenceKey {
  static let defaultValue = 0
  static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

/// A modifier with a `body` of its own, which the render cannot apply to the node it modifies.
struct StackDepthModifier: ViewModifier {
  let level: Int
  func body(content: Content) -> some View {
    content.padding(1).opacity(0.99).accessibilityLabel("custom \(level)")
  }
}

struct StackDepthVariant: Hashable {
  let style: StackDepthProbe.Style
  let name: String
  let depths: [Int]
}

struct StackDepthFixture: View {
  static let depths = Array(10...60) + Array(stride(from: 65, through: 120, by: 5)) + [140, 160, 200, 250, 300, 500, 1000, 2000, 5000, 8000]
  static let plainDepths = [100, 150, 200, 250, 1000, 5000]
  static let chainDepths = [150, 300, 1000]
  static let eagerDepths = [150, 300, 1000]
  /// Style, button prefix and the depths of each of the other variants.
  static let variants: [StackDepthVariant] = [
    StackDepthVariant(style: .mods, name: "mods", depths: [300, 1000]),
    StackDepthVariant(style: .conditional, name: "if", depths: [300, 1000]),
    StackDepthVariant(style: .hstack, name: "hstack", depths: [120, 240, 500, 1000]),
    StackDepthVariant(style: .scroll, name: "scroll", depths: [100, 300]),
    StackDepthVariant(style: .list, name: "list", depths: [80, 200]),
    StackDepthVariant(style: .grid, name: "grid", depths: [100, 300]),
    StackDepthVariant(style: .mix, name: "mix", depths: [250, 1000]),
    StackDepthVariant(style: .pref, name: "pref", depths: [300, 1000]),
    StackDepthVariant(style: .sheet, name: "sheet", depths: [300, 1000]),
    StackDepthVariant(style: .nav, name: "nav", depths: [300, 1000]),
    StackDepthVariant(style: .anim, name: "anim", depths: [300, 1000]),
    StackDepthVariant(style: .custom, name: "custom-mod", depths: [300, 1000]),
    StackDepthVariant(style: .forcing, name: "forcing", depths: [300, 1000]),
    StackDepthVariant(style: .form, name: "form", depths: [300, 1000]),
    StackDepthVariant(style: .section, name: "section", depths: [300, 1000]),
    StackDepthVariant(style: .disclosure, name: "disclosure", depths: [300, 1000]),
    StackDepthVariant(style: .groupbox, name: "groupbox", depths: [300, 1000]),
    StackDepthVariant(style: .labeled, name: "labeled", depths: [100, 300, 1000]),
    StackDepthVariant(style: .menu, name: "menu", depths: [300, 1000]),
    StackDepthVariant(style: .group, name: "group", depths: [150, 300]),
    StackDepthVariant(style: .groups, name: "groups", depths: [150, 300]),
    StackDepthVariant(style: .picker, name: "picker", depths: [300, 1000]),
    StackDepthVariant(style: .tabs, name: "tabview-in-tabview", depths: [60, 90, 300, 1000]),
    StackDepthVariant(style: .tags, name: "tabview-nested", depths: [300, 1000]),
    StackDepthVariant(style: .navNested, name: "nav-nested", depths: [300, 1000]),
    StackDepthVariant(style: .equatable, name: "equatable", depths: [300, 1000]),
    StackDepthVariant(style: .combo, name: "combo", depths: [300, 1000]),
    StackDepthVariant(style: .recurse, name: "recurse", depths: [1000, 5000, 12000]),
    StackDepthVariant(style: .wide, name: "wide", depths: [1000, 10000]),
    StackDepthVariant(style: .wideForm, name: "wide-form", depths: [1000, 5000]),
    StackDepthVariant(style: .wideList, name: "wide-list", depths: [1000, 5000]),
  ]
  @State private var depth = 0
  @State private var style = StackDepthProbe.Style.padded
  @State private var survivors = false
  @State private var later = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Button("survivors") { survivors = true }.accessibilityIdentifier("survivors-on")
        // The overflow comes out of a task a timer resumes, not out of an event: the Worker's task drain overflows.
        Button("recurse later") { later += 1 }.accessibilityIdentifier("recurse-later")
      }
      if survivors { StackDepthSurvivors() }
      ScrollView(.horizontal) {
        HStack(spacing: 4) {
          ForEach(StackDepthFixture.depths, id: \.self) { value in
            Button("\(value)") { style = .padded; depth = value }.accessibilityIdentifier("depth-\(value)")
          }
          ForEach(StackDepthFixture.plainDepths, id: \.self) { value in
            Button("plain \(value)") { style = .plain; depth = value }.accessibilityIdentifier("plain-\(value)")
          }
          ForEach(StackDepthFixture.chainDepths, id: \.self) { value in
            Button("chain \(value)") { style = .chain; depth = value }.accessibilityIdentifier("chain-\(value)")
          }
          ForEach(StackDepthFixture.eagerDepths, id: \.self) { value in
            Button("eager \(value)") { style = .eager; depth = value }.accessibilityIdentifier("eager-\(value)")
          }
          ForEach(StackDepthFixture.variants, id: \.self) { variant in
            ForEach(variant.depths, id: \.self) { value in
              Button("\(variant.name) \(value)") { style = variant.style; depth = value }
                .accessibilityIdentifier("\(variant.name)-\(value)")
            }
          }
        }
      }
      LabeledGeometryFixture()
      Text("depth \(depth)").accessibilityIdentifier("depth-value")
      if style == .wide {
        // `depth` siblings in one stack, then the leaf.
        ScrollView {
          VStack(spacing: 0) {
            ForEach(0..<depth, id: \.self) { Text("row \($0)") }
            Text("leaf").accessibilityIdentifier("depth-leaf")
          }
        }
      } else if style == .wideForm {
        Form {
          ForEach(0..<depth, id: \.self) { i in LabeledContent("row \(i)") { Text("value \(i)") } }
          Text("leaf").accessibilityIdentifier("depth-leaf")
        }
      } else if style == .wideList {
        List {
          ForEach(0..<depth, id: \.self) { Text("row \($0)") }
          Text("leaf").accessibilityIdentifier("depth-leaf")
        }
      } else if style == .nav || style == .forcing {
        NavigationStack { StackDepthProbe(depth: depth, style: style) }
      } else if style == .tags {
        TabView(selection: .constant(depth)) { StackDepthProbe(depth: depth, style: style) }
      } else {
        StackDepthProbe(depth: depth, style: style)
      }
    }
    .task(id: later) {
      if later == 0 { return }
      try? await Task.sleep(nanoseconds: 300_000_000)
      style = .recurse
      depth = 12000
    }
  }
}

/// State the app keeps while a Worker's call stack runs out (`Tools/test-worker-overflow-browser.mjs`): a counter, a toggle,
/// a text field, a navigation path, a tab selection and a scrolled list. After `recurse-N` overflows the Worker, these
/// must read what they read before.
struct StackDepthSurvivors: View {
  @State private var count = 0
  @State private var flag = false
  @State private var text = ""
  @State private var path: [Int] = []
  @State private var tab = "alpha"

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button("count \(count)") { count += 1 }.accessibilityIdentifier("survivor-count")
      Toggle("flag", isOn: $flag).accessibilityIdentifier("survivor-flag")
      Text("flag is \(flag ? "on" : "off")").accessibilityIdentifier("survivor-flag-value")
      TextField("Text", text: $text).accessibilityIdentifier("survivor-text")
      Text("text is \(text)").accessibilityIdentifier("survivor-text-value")
      TabView(selection: $tab) {
        Tab("Alpha", systemImage: "a.circle", value: "alpha") { Text("Alpha panel") }
        Tab("Beta", systemImage: "b.circle", value: "beta") { Text("Beta panel") }
      }
      .frame(height: 90)
      Text("tab is \(tab)").accessibilityIdentifier("survivor-tab-value")
      NavigationStack(path: $path) {
        Button("push") { path.append(path.count + 1) }.accessibilityIdentifier("survivor-push")
          .navigationDestination(for: Int.self) { value in
            Text("pushed \(value)").accessibilityIdentifier("survivor-pushed")
          }
      }
      .frame(height: 60)
      Text("path \(path.count)").accessibilityIdentifier("survivor-path-value")
      ScrollView {
        VStack(alignment: .leading) {
          ForEach(0..<60, id: \.self) { row in Text("row \(row)").accessibilityIdentifier("survivor-row-\(row)") }
        }
      }
      .frame(height: 80)
      .accessibilityIdentifier("survivor-scroll")
    }
  }
}

/// Geometry fixture for `LabeledContent` (`labeled-form`, `labeled-plain`, `labeled-narrow`): the same rows inside a
/// `Form`, in a plain column, and in a 210pt column where the labels wrap. The layout tests compare its rects.
struct LabeledGeometryFixture: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Form {
        LabeledContent("Status", value: "Ready")
        LabeledContent("Plan") { Text("SwiftUIWeb Pro") }
        LabeledContent("Empty") { EmptyView() }
      }
      .accessibilityIdentifier("labeled-form")
      VStack(alignment: .leading, spacing: 0) {
        LabeledContent("Network", value: "Connected")
        LabeledContent("A longer label that takes the remaining width") { Text("Value") }
      }
      .accessibilityIdentifier("labeled-plain")
      VStack(alignment: .leading, spacing: 0) {
        LabeledContent("A label that has to wrap over several lines in a narrow column", value: "Ready now")
        LabeledContent("Short", value: "A value that is long enough to wrap in a narrow column too")
      }
      .frame(width: 210)
      .accessibilityIdentifier("labeled-narrow")
    }
  }
}
