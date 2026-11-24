import SwiftUIWeb

/// The fixture of the lazy cell state browser test (`Tools/test-lazy-cell-state-browser.mjs`). A view in a cell of a lazy
/// grid keeps state of its own, and a change of that state has to redraw it as it would in a plain stack. Three kinds of cell,
/// each in a `LazyVGrid` and, as the control, in a `VStack`: a view that holds its state itself, a generic card that stores the
/// content it was built with (the way a design system's card does), and a view whose state changes inside `withAnimation`.
struct LazyCellStateRootView: View {
  @State private var tab = 0

  var body: some View {
    // The cells are on the second tab, which the page draws while it is hidden and then selects by itself right after it starts,
    // as the project site does when it is opened at the address of its last page.
    TabView(selection: $tab) {
      // A page before the cells with a lazy grid of its own (static cells), as the site's Benefits page has: the grid with state is
      // the second lazy collection of the tree.
      ScrollView {
        Text("home").accessibilityIdentifier("home")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
          ForEach(0..<6, id: \.self) { index in Text("static \(index)").padding(8).background(Color.gray.opacity(0.12)) }
        }
      }
      .tabItem { Label("Home", systemImage: "house") }.tag(0)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("lazy grid").font(.headline)
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) { cells(prefix: "lazy") }
          Text("v1: keyed ForEach, a cell directly").font(.headline)
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
            ForEach(Self.items, id: \.id) { item in OwnStateCell(id: "v1-\(item.id)") }
          }
          Text("v1n: keyed ForEach, a numeric cell directly").font(.headline)
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
            ForEach(Self.items, id: \.id) { item in NumericCell(id: "v1n-\(item.id)") }
          }
          Text("v2: keyed ForEach, a card with its content").font(.headline)
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
            ForEach(Self.items, id: \.id) { item in CardCell(id: "v2-\(item.id)") { CardContent(id: "v2-\(item.id)") } }
          }
          Text("v3: keyed ForEach, a switch").font(.headline)
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
            ForEach(Self.items, id: \.id) { item in picked(item.kind, "v3-\(item.id)") }
          }
          Text("lazy grid over a keyed ForEach").font(.headline)
          // The shape of the project site's page: rows from a ForEach over values with ids, each a generic card that stores a view
          // its closure built with a switch.
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
            ForEach(Self.items, id: \.id) { item in
              CardCell(id: "keyed-\(item.id)") { picked(item.kind, "keyed-\(item.id)") }
            }
          }
          Text("plain stack").font(.headline)
          VStack(alignment: .leading, spacing: 8) { cells(prefix: "plain") }
        }
        .padding()
      }
      .tabItem { Label("Cells", systemImage: "square.grid.2x2") }.tag(1)
      // One lazy grid of many equal cells for each kind of grid: the fixtures of `Tools/test-lazy-grid-lanes-browser.mjs`.
      VerticalGridFixture(kind: "adaptive", columns: [GridItem(.adaptive(minimum: 140), spacing: 8)])
        .tabItem { Label("Adaptive", systemImage: "house") }.tag(2)
      VerticalGridFixture(kind: "mixed", columns: [GridItem(.fixed(90), spacing: 8), GridItem(.adaptive(minimum: 120), spacing: 8)])
        .tabItem { Label("Mixed", systemImage: "house") }.tag(3)
      VerticalGridFixture(kind: "flexible", columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3))
        .tabItem { Label("Flexible", systemImage: "house") }.tag(4)
      HorizontalGridFixture(kind: "across")
        .tabItem { Label("Across", systemImage: "house") }.tag(5)
      GrowingGridFixture(kind: "growing")
        .tabItem { Label("Growing", systemImage: "house") }.tag(6)
    }
    .task { tab = 1 }
  }

  @ViewBuilder
  private func cells(prefix: String) -> some View {
    OwnStateCell(id: "\(prefix)-own")
    CardCell(id: "\(prefix)-card") { CardContent(id: "\(prefix)-card") }
    AnimatedStateCell(id: "\(prefix)-animated")
    NumericCell(id: "\(prefix)-numeric")
    SymbolCell(id: "\(prefix)-symbol")
    // The content of a card chosen by a `switch` in a view builder, so the view the card stores is a conditional content.
    CardCell(id: "\(prefix)-pick-a") { picked("a", prefix) }
    CardCell(id: "\(prefix)-pick-b") { picked("b", prefix) }
  }

  private struct Item { let id: String; let kind: String }
  private static let items = [Item(id: "a", kind: "a"), Item(id: "b", kind: "b"), Item(id: "c", kind: "a")]

  @ViewBuilder
  private func picked(_ kind: String, _ prefix: String) -> some View {
    switch kind {
    case "a": NumericCell(id: "\(prefix)-pa")
    case "b": OwnStateCell(id: "\(prefix)-pb")
    default: EmptyView()
    }
  }
}

/// A view that holds its own state and draws it.
struct OwnStateCell: View {
  let id: String
  @State private var count = 0
  @State private var on = false

  var body: some View {
    VStack(alignment: .leading) {
      Text("count \(count)").accessibilityIdentifier("\(id)-count")
      Button("Add") { count += 1 }.accessibilityIdentifier("\(id)-add")
      Text(on ? "on" : "off").accessibilityIdentifier("\(id)-flag")
      Button("Flip") { on.toggle() }.accessibilityIdentifier("\(id)-flip")
    }
    .padding(8)
    .background(Color.gray.opacity(0.12))
  }
}

/// A card that stores the content it was built with, as a generic container does.
struct CardCell<Content: View>: View {
  let id: String
  let content: Content

  init(id: String, @ViewBuilder content: () -> Content) {
    self.id = id
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading) { content }
      .padding(8)
      .background(Color.gray.opacity(0.12))
  }
}

struct CardContent: View {
  let id: String
  @State private var count = 0

  var body: some View {
    Text("count \(count)").accessibilityIdentifier("\(id)-count")
    Button("Add") { count += 1 }.accessibilityIdentifier("\(id)-add")
  }
}

/// State that changes inside `withAnimation`, with a value-scoped animation on what shows it.
struct AnimatedStateCell: View {
  let id: String
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading) {
      Text("count \(count)")
        .animation(.easeInOut(duration: 0.2), value: count)
        .accessibilityIdentifier("\(id)-count")
      Button("Add") { withAnimation(.easeInOut(duration: 0.2)) { count += 1 } }.accessibilityIdentifier("\(id)-add")
    }
    .padding(8)
    .background(Color.gray.opacity(0.12))
  }
}

/// The shape that failed on the project site: a number with a content transition and a value-scoped spring, driven by
/// buttons whose style is set on the stack that holds them.
struct NumericCell: View {
  let id: String
  @State private var count = 128

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("\(count)")
        .font(.system(size: 40, weight: .bold, design: .rounded))
        .contentTransition(.numericText(value: Double(count)))
        .animation(.snappy, value: count)
        .accessibilityIdentifier("\(id)-count")
      HStack(spacing: 8) {
        Button("-7") { count -= 7 }.accessibilityIdentifier("\(id)-minus")
        Button("+100") { count += 100 }.accessibilityIdentifier("\(id)-add")
      }
      .buttonStyle(.bordered)
    }
    .padding(8)
    .background(Color.gray.opacity(0.12))
  }
}

/// A symbol effect that a button switches on and off, and a symbol that swaps.
struct SymbolCell: View {
  let id: String
  @State private var listening = false
  @State private var starred = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 20) {
        Image(systemName: "wifi").symbolEffect(.pulse, isActive: listening)
        Image(systemName: starred ? "star.fill" : "star").contentTransition(.symbolEffect(.replace))
      }
      HStack(spacing: 8) {
        Button(listening ? "Stop" : "Listen") { listening.toggle() }.accessibilityIdentifier("\(id)-listen")
        Button("Star") { withAnimation { starred.toggle() } }.accessibilityIdentifier("\(id)-star")
      }
      .buttonStyle(.bordered)
      Text(starred ? "starred" : "plain").accessibilityIdentifier("\(id)-starred")
    }
    .padding(8)
    .background(Color.gray.opacity(0.12))
  }
}
