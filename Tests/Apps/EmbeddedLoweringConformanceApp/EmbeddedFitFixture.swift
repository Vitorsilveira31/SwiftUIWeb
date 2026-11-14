import SwiftUIWeb

/// `ViewThatFits`: the first candidate whose ideal size fits what it is offered is shown, else the last.
/// - Candidates that take the width they are offered, in frames of three widths and in one that follows the window, so a
///   resize selects another. "Count" changes a text in every candidate: the publication patches them, the selection stays.
/// - Candidates as wide as their content beside a Spacer in an HStack (Food Truck's parking spot card), offered a share
///   of the stack, and in a VStack.
/// - A vertical choice in frames of two heights.
/// - Edge cases: no candidate (an `EmptyView`, between two texts and alone), a single candidate that fits and one that
///   does not, a ViewThatFits in a candidate, candidates from a `ForEach` and from an `if`, one in a ZStack, in a
///   horizontal ScrollView and in a frame with both axes.
/// CSS layout must lay it out (`Tools/test-css-layout-fixtures-browser.mjs`).
struct EmbeddedFitFixture: View {
  let onDone: () -> Void
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button("Return to conformance app") { onDone() }
      Button("Count") { count += 1 }
      choice.frame(width: 260)
      choice.frame(width: 160)
      choice.frame(width: 60)
      choice.padding(.horizontal, 40)
      shared.frame(width: 260)
      shared.frame(width: 180)
      shared.frame(width: 120)
      compact.frame(width: 260, alignment: .leading)
      compact.frame(width: 140, alignment: .leading)
      tall.frame(width: 160, height: 60)
      tall.frame(width: 160, height: 30)
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Before")
            ViewThatFits(in: .horizontal) { EmptyView() }
            Text("After")
          }
          ViewThatFits { EmptyView() }.background(Color.gray.opacity(0.15))
          only.frame(width: 260)
          only.frame(width: 90)
          nested.frame(width: 260)
          nested.frame(width: 190)
          nested.frame(width: 70)
          listed.frame(width: 260)
          listed.frame(width: 110)
          listed.frame(width: 50)
          conditional.frame(width: 200)
          conditional.frame(width: 80)
          ZStack(alignment: .topLeading) { choice }.frame(width: 160, height: 50)
          ScrollView(.horizontal) { compact }.frame(width: 200, height: 60)
          both.frame(width: 200, height: 40)
          both.frame(width: 60, height: 40)
          both.frame(width: 200, height: 14)
        }
      }
      .frame(height: 220)
    }
    .padding(16)
  }

  /// Food Truck's parking spot card: a text with priority, a Spacer and a ViewThatFits of shrinking rows.
  private var shared: some View {
    HStack {
      VStack(alignment: .leading) {
        Text("Spot")
        Text("Park")
      }
      .layoutPriority(1)
      Spacer()
      ViewThatFits {
        HStack {
          Text("72°")
          Text("Popular")
          Text("Trending")
        }
        HStack {
          Text("72°")
          Text("Popular")
        }
        Text("72°")
      }
    }
    .background(Color.gray.opacity(0.15))
  }

  private var compact: some View {
    ViewThatFits(in: .horizontal) {
      HStack {
        Text("A wide layout with controls")
        Text("Go")
      }
      VStack(alignment: .leading) {
        Text("Compact")
        Text("Go")
      }
    }
    .background(Color.gray.opacity(0.15))
  }

  private var tall: some View {
    ViewThatFits(in: .vertical) {
      VStack {
        Text("One")
        Text("Two")
        Text("Three")
      }
      VStack {
        Text("One")
        Text("Two")
      }
      Text("One")
    }
    .background(Color.gray.opacity(0.15))
  }

  private var choice: some View {
    ViewThatFits(in: .horizontal) {
      HStack {
        Text("Wide layout, \(count)")
        Spacer()
        Text("Action")
      }
      .frame(maxWidth: .infinity)
      HStack {
        Text("Compact \(count)")
        Spacer()
      }
      Text("Tiny")
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Color.gray.opacity(0.15))
  }

  private var only: some View {
    ViewThatFits(in: .horizontal) {
      Text("The only candidate")
    }
    .background(Color.gray.opacity(0.15))
  }

  /// A candidate that holds a ViewThatFits of its own.
  private var nested: some View {
    ViewThatFits(in: .horizontal) {
      HStack {
        Text("Outer wide row")
        ViewThatFits(in: .horizontal) {
          Text("Inner long label")
          Text("Inner")
        }
      }
      Text("Outer short")
    }
    .background(Color.gray.opacity(0.15))
  }

  private var listed: some View {
    ViewThatFits(in: .horizontal) {
      ForEach(["A much longer label", "Medium label", "Tiny"], id: \.self) { label in
        Text(label)
      }
    }
    .background(Color.gray.opacity(0.15))
  }

  private var conditional: some View {
    ViewThatFits(in: .horizontal) {
      if count % 2 == 0 {
        Text("An even, longer label")
      } else {
        Text("Odd label")
      }
      Text("Fallback")
    }
    .background(Color.gray.opacity(0.15))
  }

  private var both: some View {
    ViewThatFits {
      VStack {
        Text("Wide and tall layout")
        Text("Second line")
      }
      HStack {
        Text("Wide layout")
        Text("Wide")
      }
      Text("Short")
    }
    .background(Color.gray.opacity(0.15))
  }
}
