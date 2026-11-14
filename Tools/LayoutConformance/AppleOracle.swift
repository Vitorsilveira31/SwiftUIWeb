import AppKit
import SwiftUI

struct RectValue: Codable { let x: Double; let y: Double; let width: Double; let height: Double }
struct Snapshot: Codable { let platform: String; let os: String; let nodes: [String: RectValue] }

private struct ProbeKey: PreferenceKey {
  static var defaultValue: [String: CGRect] = [:]
  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, n in n }) }
}
private extension SwiftUI.View {
  func probe(_ id: String) -> some SwiftUI.View {
    background(GeometryReader { proxy in Color.clear.preference(key: ProbeKey.self, value: [id: proxy.frame(in: .global)]) })
  }
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

private struct Fixture<Content: SwiftUI.View>: SwiftUI.View {
  let id: String; @ViewBuilder let content: () -> Content
  var body: some SwiftUI.View { content().frame(width: 320, height: 240).probe(id + ".host") }
}

@MainActor
final class Box { var frames: [String: CGRect] = [:] }

private struct OracleRoot: SwiftUI.View {
  let box: Box
  var body: some SwiftUI.View {
    VStack(spacing: 24) {
      Fixture(id: "root-text") { Text("Hello world").font(.system(size: 17)).probe("root-text.text") }
      Fixture(id: "proposal-probe") {
        ProposalProbeLayout {
          Text("Proposal sample").font(.system(size: 17)).probe("proposal-probe.zero")
          Text("Proposal sample").font(.system(size: 17)).probe("proposal-probe.unspecified")
          Text("Proposal sample").font(.system(size: 17)).probe("proposal-probe.infinity")
        }
      }
      Fixture(id: "vstack-center") { VStack(spacing: 10) { Color.red.frame(width: 40, height: 20).probe("vstack-center.a"); Color.blue.frame(width: 80, height: 30).probe("vstack-center.b") } }
      Fixture(id: "vstack-leading") { VStack(alignment: .leading, spacing: 10) { Color.red.frame(width: 40, height: 20).probe("vstack-leading.a"); Color.blue.frame(width: 80, height: 30).probe("vstack-leading.b") } }
      Fixture(id: "hstack-spacer") { HStack(spacing: 0) { Color.red.frame(width: 40, height: 20).probe("hstack-spacer.left"); Spacer(); Color.blue.frame(width: 60, height: 20).probe("hstack-spacer.right") }.frame(width: 260, height: 60) }
      Fixture(id: "spacer-min") { VStack(spacing: 0) { Color.red.frame(width: 30, height: 20).probe("spacer-min.top"); Spacer(minLength: 44); Color.blue.frame(width: 30, height: 20).probe("spacer-min.bottom") }.frame(width: 100, height: 120) }
      Fixture(id: "frame-strict") { Color.red.frame(width: 40, height: 20).frame(width: 180, height: 90).probe("frame-strict.child") }
      Fixture(id: "frame-infinity-leading") { Text("Leading").font(.system(size: 17)).probe("frame-infinity-leading.child").frame(maxWidth: .infinity, alignment: .leading) }
      Fixture(id: "layout-priority") { HStack(spacing: 0) { Text("HIGH PRIORITY CONTENT").font(.system(size: 17)).lineLimit(1).layoutPriority(1).probe("layout-priority.high"); Text("lower priority content").font(.system(size: 17)).lineLimit(1).probe("layout-priority.low") }.frame(width: 190, height: 50) }
      Fixture(id: "layout-priority-reversed") { HStack(spacing: 0) { Text("lower priority content").font(.system(size: 17)).lineLimit(1).probe("layout-priority-reversed.low"); Text("HIGH PRIORITY CONTENT").font(.system(size: 17)).lineLimit(1).layoutPriority(1).probe("layout-priority-reversed.high") }.frame(width: 190, height: 50) }
      Fixture(id: "layout-priority-three-levels") { HStack(spacing: 0) { Text("HIGH PRIORITY CONTENT").font(.system(size: 17)).lineLimit(1).layoutPriority(2).probe("layout-priority-three-levels.high"); Text("lower priority content").font(.system(size: 17)).lineLimit(1).layoutPriority(1).probe("layout-priority-three-levels.middle"); Text("lower priority content").font(.system(size: 17)).lineLimit(1).probe("layout-priority-three-levels.low") }.frame(width: 190, height: 50) }
      Fixture(id: "fixed-size") { Text("This text has an intentionally long intrinsic width").font(.system(size: 17)).fixedSize(horizontal: true, vertical: false).probe("fixed-size.text").frame(width: 120) }
      Fixture(id: "zstack-bottom-trailing") { ZStack(alignment: .bottomTrailing) { Color.clear.frame(width: 200, height: 120); Color.red.frame(width: 40, height: 30).probe("zstack-bottom-trailing.child") } }
      Fixture(id: "text-wrapping") { Text("SwiftUI proposes a width and this sentence should wrap into multiple lines.").font(.system(size: 17)).frame(width: 130).probe("text-wrapping.text") }
      Fixture(id: "nested-frames") { Color.red.frame(width: 30, height: 20).frame(width: 90, height: 70, alignment: .bottomTrailing).probe("nested-frames.inner").frame(width: 200, height: 140, alignment: .topLeading) }
      Group {
        Fixture(id: "hstack-text-spacer") { HStack(spacing: 0) { Text("A medium length title").font(.system(size: 17)).probe("hstack-text-spacer.text"); Spacer(minLength: 0) }.frame(width: 190, height: 50) }
        Fixture(id: "fixed-column-text") { HStack(spacing: 12) { Color.red.frame(width: 44, height: 60).probe("fixed-column-text.poster"); VStack(alignment: .leading, spacing: 0) { Text("A medium length title").font(.system(size: 17)).probe("fixed-column-text.title") }; Spacer(minLength: 0) }.frame(width: 240, height: 80) }
        Fixture(id: "lazy-grid-top") { LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 10) { Color.red.frame(width: 50, height: 40).probe("lazy-grid-top.a"); Color.blue.frame(width: 50, height: 80).probe("lazy-grid-top.b") }.frame(width: 300) }
        Fixture(id: "lazy-grid-fill") { LazyVGrid(columns: [GridItem(.flexible(), spacing: 30), GridItem(.flexible())], spacing: 10) { Color.red.frame(width: 50).frame(maxHeight: .infinity).probe("lazy-grid-fill.a"); Color.blue.frame(width: 50, height: 80).probe("lazy-grid-fill.b") }.frame(width: 300) }
        Fixture(id: "grid-row-alignment") { Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 10) { GridRow { Color.red.frame(width: 50, height: 40).probe("grid-row-alignment.a"); Color.blue.frame(width: 80, height: 80).probe("grid-row-alignment.b") }; GridRow(alignment: .bottom) { Color.red.frame(width: 30, height: 20).probe("grid-row-alignment.c"); Color.blue.frame(width: 50, height: 60).probe("grid-row-alignment.d") } } }
      }
    }.padding(20).onPreferenceChange(ProbeKey.self) { box.frames = $0 }
  }
}

@main
struct Main {
  @MainActor static func main() throws {
    let box = Box()
    _ = NSApplication.shared
    let hosting = NSHostingView(rootView: OracleRoot(box: box))
    hosting.frame = NSRect(x: 0, y: 0, width: 390, height: 6000)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    window.orderFrontRegardless()
    hosting.layoutSubtreeIfNeeded()
    let deadline = Date().addingTimeInterval(0.15)
    while Date() < deadline { RunLoop.current.run(mode: .default, before: deadline) }
    hosting.layoutSubtreeIfNeeded()

    var normalized: [String: RectValue] = [:]
    for (id, rect) in box.frames {
      let fixture = id.split(separator: ".").first.map(String.init) ?? id
      let hostID = fixture + ".host"
      guard let host = box.frames[hostID] else { continue }
      normalized[id] = RectValue(x: rect.minX - host.minX, y: rect.minY - host.minY, width: rect.width, height: rect.height)
    }
    let version = ProcessInfo.processInfo.operatingSystemVersionString
    let data = try JSONEncoder.pretty.encode(Snapshot(platform: "Apple SwiftUI", os: version, nodes: normalized))
    FileHandle.standardOutput.write(data)
  }
}

private extension JSONEncoder {
  static var pretty: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }
}
