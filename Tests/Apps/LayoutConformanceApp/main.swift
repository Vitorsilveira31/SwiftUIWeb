import SwiftUIWeb
import SwiftUIWebBrowser

private extension View {
  func probe(_ id: String) -> some View { accessibilityIdentifier(id) }
}

private struct ProposalProbeLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize { CGSize(width: 300, height: 90) }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
    let proposals: [ProposedViewSize] = [.zero, .unspecified, .infinity]
    for (index, subview) in subviews.enumerated() {
      let p = proposals[index]
      subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY + CGFloat(index * 30)), anchor: .topLeading, proposal: p)
    }
  }
}

private struct Fixture<Content: View>: View {
  let id: String
  @ViewBuilder let content: () -> Content
  var body: some View {
    content()
      .frame(width: 320, height: 240)
      .probe(id + ".host")
  }
}

private struct ConformanceView: View {
  var body: some View {
    VStack(spacing: 24) {
      Group {
        Fixture(id: "root-text") {
        Text("Hello world").font(.system(size: 17)).probe("root-text.text")
      }
      Fixture(id: "proposal-probe") {
        ProposalProbeLayout {
          Text("Proposal sample").font(.system(size: 17)).probe("proposal-probe.zero")
          Text("Proposal sample").font(.system(size: 17)).probe("proposal-probe.unspecified")
          Text("Proposal sample").font(.system(size: 17)).probe("proposal-probe.infinity")
        }
      }
      Fixture(id: "vstack-center") {
        VStack(spacing: 10) {
          Color.red.frame(width: 40, height: 20).probe("vstack-center.a")
          Color.blue.frame(width: 80, height: 30).probe("vstack-center.b")
        }
      }
      Fixture(id: "vstack-leading") {
        VStack(alignment: .leading, spacing: 10) {
          Color.red.frame(width: 40, height: 20).probe("vstack-leading.a")
          Color.blue.frame(width: 80, height: 30).probe("vstack-leading.b")
        }
      }
      Fixture(id: "hstack-spacer") {
        HStack(spacing: 0) {
          Color.red.frame(width: 40, height: 20).probe("hstack-spacer.left")
          Spacer()
          Color.blue.frame(width: 60, height: 20).probe("hstack-spacer.right")
        }.frame(width: 260, height: 60)
      }
      Fixture(id: "spacer-min") {
        VStack(spacing: 0) {
          Color.red.frame(width: 30, height: 20).probe("spacer-min.top")
          Spacer(minLength: 44)
          Color.blue.frame(width: 30, height: 20).probe("spacer-min.bottom")
        }.frame(width: 100, height: 120)
      }
      Fixture(id: "frame-strict") {
        Color.red.frame(width: 40, height: 20).frame(width: 180, height: 90).probe("frame-strict.child")
      }
      }
      Group {
        Fixture(id: "frame-infinity-leading") {
        Text("Leading").font(.system(size: 17)).probe("frame-infinity-leading.child")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      Fixture(id: "layout-priority") {
        HStack(spacing: 0) {
          Text("HIGH PRIORITY CONTENT").font(.system(size: 17)).lineLimit(1).layoutPriority(1).probe("layout-priority.high")
          Text("lower priority content").font(.system(size: 17)).lineLimit(1).probe("layout-priority.low")
        }.frame(width: 190, height: 50)
      }
      Fixture(id: "layout-priority-reversed") {
        HStack(spacing: 0) {
          Text("lower priority content").font(.system(size: 17)).lineLimit(1).probe("layout-priority-reversed.low")
          Text("HIGH PRIORITY CONTENT").font(.system(size: 17)).lineLimit(1).layoutPriority(1).probe("layout-priority-reversed.high")
        }.frame(width: 190, height: 50)
      }
      Fixture(id: "layout-priority-three-levels") {
        HStack(spacing: 0) {
          Text("HIGH PRIORITY CONTENT").font(.system(size: 17)).lineLimit(1).layoutPriority(2).probe("layout-priority-three-levels.high")
          Text("lower priority content").font(.system(size: 17)).lineLimit(1).layoutPriority(1).probe("layout-priority-three-levels.middle")
          Text("lower priority content").font(.system(size: 17)).lineLimit(1).probe("layout-priority-three-levels.low")
        }.frame(width: 190, height: 50)
      }
      Fixture(id: "fixed-size") {
        Text("This text has an intentionally long intrinsic width").font(.system(size: 17))
          .fixedSize(horizontal: true, vertical: false).probe("fixed-size.text")
          .frame(width: 120)
      }
      Fixture(id: "zstack-bottom-trailing") {
        ZStack(alignment: .bottomTrailing) {
          Color.clear.frame(width: 200, height: 120)
          Color.red.frame(width: 40, height: 30).probe("zstack-bottom-trailing.child")
        }
      }
      Fixture(id: "text-wrapping") {
        Text("SwiftUI proposes a width and this sentence should wrap into multiple lines.")
          .font(.system(size: 17)).frame(width: 130).probe("text-wrapping.text")
      }
        Fixture(id: "nested-frames") {
          Color.red.frame(width: 30, height: 20)
            .frame(width: 90, height: 70, alignment: .bottomTrailing)
            .probe("nested-frames.inner")
            .frame(width: 200, height: 140, alignment: .topLeading)
        }
      }
      Group {
        Fixture(id: "hstack-text-spacer") {
          HStack(spacing: 0) {
            Text("A medium length title").font(.system(size: 17)).probe("hstack-text-spacer.text")
            Spacer(minLength: 0)
          }.frame(width: 190, height: 50)
        }
        Fixture(id: "fixed-column-text") {
          HStack(spacing: 12) {
            Color.red.frame(width: 44, height: 60).probe("fixed-column-text.poster")
            VStack(alignment: .leading, spacing: 0) {
              Text("A medium length title").font(.system(size: 17)).probe("fixed-column-text.title")
            }
            Spacer(minLength: 0)
          }.frame(width: 240, height: 80)
        }
        Fixture(id: "lazy-grid-top") {
          LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 10) {
            Color.red.frame(width: 50, height: 40).probe("lazy-grid-top.a")
            Color.blue.frame(width: 50, height: 80).probe("lazy-grid-top.b")
          }.frame(width: 300)
        }
        Fixture(id: "lazy-grid-fill") {
          LazyVGrid(columns: [GridItem(.flexible(), spacing: 30), GridItem(.flexible())], spacing: 10) {
            Color.red.frame(width: 50).frame(maxHeight: .infinity).probe("lazy-grid-fill.a")
            Color.blue.frame(width: 50, height: 80).probe("lazy-grid-fill.b")
          }.frame(width: 300)
        }
        Fixture(id: "grid-row-alignment") {
          Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
              Color.red.frame(width: 50, height: 40).probe("grid-row-alignment.a")
              Color.blue.frame(width: 80, height: 80).probe("grid-row-alignment.b")
            }
            GridRow(alignment: .bottom) {
              Color.red.frame(width: 30, height: 20).probe("grid-row-alignment.c")
              Color.blue.frame(width: 50, height: 60).probe("grid-row-alignment.d")
            }
          }
        }
      }
    }.padding(20)
  }
}

@main
struct LayoutConformanceApp: BrowserApp {
  var body: some Scene { WindowGroup { ConformanceView() } }
}
