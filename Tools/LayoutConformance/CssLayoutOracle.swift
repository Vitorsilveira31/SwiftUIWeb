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

/// Food Truck's Glaze picker (DonutEditor): a menu Picker without its label, the second option selected.
private struct GlazePicker: SwiftUI.View {
  let id: String
  @State private var glaze = 1
  var body: some SwiftUI.View {
    Picker("Glaze", selection: $glaze) { Text("None").tag(0); Text("Chocolate Glaze").tag(1); Text("Sour Candy Glaze").tag(2); Text("Strawberry Glaze").tag(3) }
      .pickerStyle(.menu).labelsHidden().probe(id)
  }
}
/// Places each subview at the width it is given, one per row: what a view answers each proposal.
private struct WidthProposals: Layout {
  let widths: [CGFloat?]
  func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize { CGSize(width: 300, height: 30 * CGFloat(widths.count)) }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
    for (index, subview) in subviews.enumerated() {
      subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY + CGFloat(index * 30)), anchor: .topLeading, proposal: ProposedViewSize(width: widths[index], height: nil))
    }
  }
}

/// A TextEditor and a Canvas, which paint nothing the oracle reads.
private struct ControlEditor: SwiftUI.View {
  @State private var notes = "Notes"
  var body: some SwiftUI.View { TextEditor(text: $notes) }
}
private struct ControlCanvas: SwiftUI.View {
  var body: some SwiftUI.View { Canvas { _, _ in } }
}
/// Food Truck's HeroSquareTilingLayout (Orders card): a hero square beside a 2 x 2 tiling, the pair as wide as twice the hero plus the spacing.
private struct HeroSquareTilingLayout: Layout {
  var spacing: Double = 10
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
    let size = proposal.replacingUnspecifiedDimensions(by: CGSize(width: 100, height: 100))
    let heroLength = min((size.width - spacing) * 0.5, size.height)
    return CGSize(width: heroLength * 2 + spacing, height: heroLength)
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
    let heroLength = min((bounds.width - spacing) * 0.5, bounds.height)
    let half = CGSize(width: heroLength, height: heroLength)
    let origin = CGPoint(x: bounds.minX + (bounds.width - (heroLength * 2 + spacing)) * 0.5, y: bounds.minY + (bounds.height - heroLength) * 0.5)
    for index in subviews.indices { subviews[index].place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(half)) }
  }
}
/// Food Truck's DonutLatticeLayout (Donuts card): a lattice of 5 x 3 cells that answers a missing dimension with an unbounded one, so
/// it is as tall as three fifths of its width when it is proposed no height.
private struct DonutLatticeLayout: Layout {
  var columns = 5, rows = 3
  var defaultAxesSize: CGSize { CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude) }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
    let size = proposal.replacingUnspecifiedDimensions(by: defaultAxesSize)
    let cellLength = min(size.width / Double(columns), size.height / Double(rows))
    return CGSize(width: cellLength * Double(columns), height: cellLength * Double(rows))
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
    let size = proposal.replacingUnspecifiedDimensions(by: defaultAxesSize)
    let cellLength = min(size.width / Double(columns), size.height / Double(rows))
    let origin = CGPoint(x: bounds.minX + (bounds.width - cellLength * Double(columns)), y: bounds.minY + (bounds.height - cellLength * Double(rows)))
    for index in subviews.indices { subviews[index].place(at: origin, proposal: ProposedViewSize(width: cellLength, height: cellLength)) }
  }
}
private struct Tiles: SwiftUI.View { var body: some SwiftUI.View { ForEach(0..<14, id: \.self) { _ in Color.brown } } }

private struct ExtraRoot: SwiftUI.View {
  let box: Box
  var body: some SwiftUI.View {
    VStack(spacing: 24) {
      // Water-filling between texts and the caps of frames (the CSS flex mapping's central claim).
      Fixture(id: "x-two-texts") { HStack(spacing: 8) { Text("A fairly long first text that needs room").font(.system(size: 17)).probe("x-two-texts.a"); Text("Another quite long second text here").font(.system(size: 17)).probe("x-two-texts.b") }.frame(width: 260) }
      Fixture(id: "x-three-texts") { HStack(spacing: 6) { Text("Short").font(.system(size: 17)).probe("x-three-texts.a"); Text("A medium sized text").font(.system(size: 17)).probe("x-three-texts.b"); Text("A rather long closing text, longer").font(.system(size: 17)).probe("x-three-texts.c") }.frame(width: 280) }
      Fixture(id: "x-frame-cap") { VStack(alignment: .leading, spacing: 0) { Text("Capped").font(.system(size: 17)).frame(maxWidth: 120, alignment: .leading).probe("x-frame-cap.cap") }.frame(width: 300) }
      Fixture(id: "x-frame-cap-hug") { VStack(alignment: .leading, spacing: 4) { Text("Capped text wraps at its maximum width of one hundred and twenty").font(.system(size: 17)).frame(maxWidth: 120).probe("x-frame-cap-hug.cap"); Text("Next").font(.system(size: 17)).probe("x-frame-cap-hug.next") }.probe("x-frame-cap-hug.stack") }
      Fixture(id: "x-frame-min") { Text("Hi").font(.system(size: 17)).frame(minWidth: 150, minHeight: 60).probe("x-frame-min.f") }
      Fixture(id: "x-frame-minmax") { VStack(spacing: 4) { Text("a").font(.system(size: 17)).frame(minWidth: 100, maxWidth: 200).probe("x-frame-minmax.a"); Text("A longer text inside").font(.system(size: 17)).frame(minWidth: 100, maxWidth: 200).probe("x-frame-minmax.b") }.frame(width: 300) }
      Fixture(id: "x-padding") { Text("Padded").font(.system(size: 17)).padding(.horizontal, 20).padding(.top, 8).probe("x-padding.p") }
      Fixture(id: "x-padding-fill") { Text("Pad").font(.system(size: 17)).frame(maxWidth: .infinity, alignment: .leading).padding(16).probe("x-padding-fill.p") }
      Fixture(id: "x-overlay") { Color.blue.frame(width: 120, height: 60).overlay(alignment: .bottomTrailing) { Color.red.frame(width: 30, height: 20).probe("x-overlay.o") }.probe("x-overlay.base") }
      Fixture(id: "x-overlay-fill") { Text("Label").font(.system(size: 17)).overlay { Color.green.opacity(0.3).probe("x-overlay-fill.o") }.probe("x-overlay-fill.base") }
      // A Grid proposes each cell its row's height: a card holding a GeometryReader grows to the row, which the card
      // with a capped aspect box sets (Food Truck's Truck page).
      Fixture(id: "x-grid-fill-row") { Grid(horizontalSpacing: 12, verticalSpacing: 12) { GridRow { VStack(spacing: 8) { Text("Orders").font(.system(size: 17)); Color.green.aspectRatio(2, contentMode: .fit).frame(maxWidth: .infinity, maxHeight: 100).probe("x-grid-fill-row.tiles") }.probe("x-grid-fill-row.a"); VStack(spacing: 8) { Text("Weather").font(.system(size: 17)); GeometryReader { _ in Color.orange }.frame(minHeight: 60).probe("x-grid-fill-row.chart") }.probe("x-grid-fill-row.b") } }.fixedSize(horizontal: false, vertical: true).probe("x-grid-fill-row.grid") }
      // A frame with a minimum, proposed no height, proposes its minimum: the GeometryReader in it is that tall.
      Fixture(id: "x-frame-min-geo") { VStack(spacing: 8) { Text("Total").font(.system(size: 17)); GeometryReader { _ in Color.red }.probe("x-frame-min-geo.reader").frame(minHeight: 120).probe("x-frame-min-geo.frame") }.fixedSize(horizontal: false, vertical: true).probe("x-frame-min-geo.stack") }
      // A frame with a finite maximum, proposed no height, is as tall as what it holds up to that maximum.
      Fixture(id: "x-frame-max-hug") { VStack(spacing: 8) { Text("Tiles").font(.system(size: 17)); Color.green.aspectRatio(2, contentMode: .fit).probe("x-frame-max-hug.aspect").frame(maxWidth: .infinity, maxHeight: 80).probe("x-frame-max-hug.frame") }.fixedSize(horizontal: false, vertical: true).probe("x-frame-max-hug.stack") }
      // A finite maximum height caps the aspect box inside it (SwiftUI proposes the frame's own height to what it holds): the box is as
      // wide as that height gives, not the width and a ratio's height that overflow the frame.
      Fixture(id: "x-aspect-cap-tall") { VStack(spacing: 8) { Text("Tiles").font(.system(size: 17)); Color.green.aspectRatio(0.5, contentMode: .fit).probe("x-aspect-cap-tall.aspect").frame(maxWidth: .infinity, maxHeight: 80).probe("x-aspect-cap-tall.frame") }.fixedSize(horizontal: false, vertical: true).probe("x-aspect-cap-tall.stack") }
      Fixture(id: "x-aspect-cap-padded") { VStack(spacing: 8) { Text("Tiles").font(.system(size: 17)); Color.green.aspectRatio(2, contentMode: .fit).probe("x-aspect-cap-padded.aspect").padding(10).frame(maxWidth: .infinity, maxHeight: 80).probe("x-aspect-cap-padded.frame") }.fixedSize(horizontal: false, vertical: true).probe("x-aspect-cap-padded.stack") }
      Fixture(id: "x-aspect-cap-narrow") { VStack(spacing: 8) { Text("Tiles").font(.system(size: 17)); Color.green.aspectRatio(2, contentMode: .fit).probe("x-aspect-cap-narrow.aspect").frame(maxWidth: .infinity, maxHeight: 80).probe("x-aspect-cap-narrow.frame") }.fixedSize(horizontal: false, vertical: true).frame(width: 100).probe("x-aspect-cap-narrow.stack") }
      // Food Truck's Orders hero: a user-defined Layout in a capped aspect box (it answers 95 tall where the box is 100).
      Fixture(id: "x-aspect-hero") { VStack(spacing: 8) { Text("Tiles").font(.system(size: 17)); HeroSquareTilingLayout { ForEach(0..<5, id: \.self) { _ in Color.orange } }.probe("x-aspect-hero.layout").aspectRatio(2, contentMode: .fit).probe("x-aspect-hero.aspect").frame(maxWidth: .infinity, maxHeight: 100).probe("x-aspect-hero.frame") }.fixedSize(horizontal: false, vertical: true).probe("x-aspect-hero.stack") }
      // A user-defined Layout is proposed no height down a chain of hugging views (a fixedSize stack, a Grid in one, a ScrollView): the
      // lattice answers 3/5 of its width and the row, the card, the frame grow to it.
      Fixture(id: "x-layout-stack-hug") { VStack(spacing: 8) { HStack { Text("Donuts").font(.system(size: 17)); Spacer() }; DonutLatticeLayout { Tiles() }.probe("x-layout-stack-hug.lattice").frame(minHeight: 60, maxHeight: .infinity).probe("x-layout-stack-hug.frame") }.fixedSize(horizontal: false, vertical: true).probe("x-layout-stack-hug.stack") }
      Fixture(id: "x-layout-grid-hug") { Grid(horizontalSpacing: 12, verticalSpacing: 12) { GridRow { VStack(spacing: 8) { HStack { Text("Donuts").font(.system(size: 17)); Spacer() }; DonutLatticeLayout { Tiles() }.probe("x-layout-grid-hug.lattice").frame(minHeight: 60, maxHeight: .infinity).probe("x-layout-grid-hug.frame") }.probe("x-layout-grid-hug.card") } }.fixedSize(horizontal: false, vertical: true).probe("x-layout-grid-hug.grid") }
      Fixture(id: "x-layout-grid-tall") { Grid(horizontalSpacing: 12, verticalSpacing: 12) { GridRow { VStack(spacing: 8) { HStack { Text("Donuts").font(.system(size: 17)); Spacer() }; DonutLatticeLayout { Tiles() }.probe("x-layout-grid-tall.lattice").frame(minHeight: 60, maxHeight: .infinity).probe("x-layout-grid-tall.frame") }.probe("x-layout-grid-tall.card"); Color.blue.frame(height: 200).probe("x-layout-grid-tall.other") } }.fixedSize(horizontal: false, vertical: true).probe("x-layout-grid-tall.grid") }
      Fixture(id: "x-layout-scroll") { ScrollView(.vertical) { DonutLatticeLayout { Tiles() }.probe("x-layout-scroll.lattice").frame(minHeight: 60, maxHeight: .infinity).probe("x-layout-scroll.frame") }.probe("x-layout-scroll.scroll") }
      // A frame with a minimum proposes it to an HStack of views that fill: they are that tall (a media gallery).
      Fixture(id: "x-frame-min-fill") { HStack(spacing: 4) { VStack(alignment: .leading, spacing: 6) { Spacer(); Text("Bora").font(.system(size: 17)) }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).probe("x-frame-min-fill.a"); VStack(alignment: .leading, spacing: 6) { Spacer(); Text("Lagoon").font(.system(size: 17)) }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).probe("x-frame-min-fill.b") }.frame(maxWidth: .infinity, minHeight: 120).probe("x-frame-min-fill.gallery").fixedSize(horizontal: false, vertical: true) }
      Fixture(id: "x-background") { Text("Background").font(.system(size: 17)).padding(10).background { Color.orange.probe("x-background.bg") }.probe("x-background.base") }
      Fixture(id: "x-aspect-fit") { Color.red.aspectRatio(2, contentMode: .fit).probe("x-aspect-fit.a").frame(width: 100, height: 100) }
      Fixture(id: "x-aspect-width") { VStack(spacing: 0) { Color.red.aspectRatio(0.75, contentMode: .fit).probe("x-aspect-width.a") }.frame(width: 150) }
      Fixture(id: "x-geometry") { GeometryReader { proxy in Text("Top leading").font(.system(size: 17)).probe("x-geometry.t").frame(width: proxy.size.width / 2) }.frame(width: 200, height: 100).probe("x-geometry.g") }
      Fixture(id: "x-fixed-vertical") { Text("A long sentence that has to wrap into several lines inside this narrow frame.").font(.system(size: 17)).fixedSize(horizontal: false, vertical: true).frame(width: 110).probe("x-fixed-vertical.f") }
      Fixture(id: "x-zstack-topleading") { ZStack(alignment: .topLeading) { Color.blue.frame(width: 160, height: 100); Color.red.frame(width: 50, height: 40).probe("x-zstack-topleading.r"); Text("Text").font(.system(size: 17)).probe("x-zstack-topleading.t") }.probe("x-zstack-topleading.z") }
      Fixture(id: "x-vstack-spacer") { VStack(spacing: 0) { Text("Top").font(.system(size: 17)).probe("x-vstack-spacer.t"); Spacer(); Text("Bottom").font(.system(size: 17)).probe("x-vstack-spacer.b") }.frame(width: 150, height: 200) }
      Fixture(id: "x-flex-vs-text") { HStack(spacing: 10) { Color.red.probe("x-flex-vs-text.c"); Text("A text beside a color").font(.system(size: 17)).probe("x-flex-vs-text.t") }.frame(width: 260, height: 40) }
      Fixture(id: "x-trailing-stack") { VStack(alignment: .trailing, spacing: 4) { Text("Short").font(.system(size: 17)).probe("x-trailing-stack.a"); Text("A much longer line").font(.system(size: 17)).probe("x-trailing-stack.b") }.probe("x-trailing-stack.v") }
      Fixture(id: "x-baseline") { HStack(alignment: .firstTextBaseline, spacing: 8) { Text("Big").font(.system(size: 28)).probe("x-baseline.a"); Text("small").font(.system(size: 12)).probe("x-baseline.b") }.probe("x-baseline.h") }
      Fixture(id: "x-nested-flex") { HStack(spacing: 8) { VStack(alignment: .leading, spacing: 2) { Text("Title that is long enough to wrap around").font(.system(size: 17)); Text("Subtitle").font(.system(size: 13)) }.probe("x-nested-flex.v"); Spacer(minLength: 0); Text("Go").font(.system(size: 15)).probe("x-nested-flex.g") }.frame(width: 240).probe("x-nested-flex.h") }
      Fixture(id: "x-text-in-frame-height") { VStack(spacing: 0) { Text("Line one line two line three line four line five").font(.system(size: 17)).frame(width: 120).probe("x-text-in-frame-height.t") }.frame(height: 40).probe("x-text-in-frame-height.v") }
      // A screen smaller than its navigation container is centred in it (macOS draws no bar here). The TabView's tab is
      // below the segmented tab bar macOS draws, which the web does not, so the CSS oracle does not map it.
      Fixture(id: "x-navigation") { NavigationStack { Text("Detail").font(.system(size: 17)).probe("x-navigation.t") } }
      Fixture(id: "x-navigation-pushed") { NavigationStack(path: .constant([1])) { Text("Root").font(.system(size: 17)).navigationDestination(for: Int.self) { _ in Text("Pushed").font(.system(size: 17)).probe("x-navigation-pushed.t") } } }
      Fixture(id: "x-navigation-tab") { TabView { Text("Tab").font(.system(size: 17)).probe("x-navigation-tab.t").tabItem { Text("One") } } }
      // A Picker row of a grouped Form (Food Truck's Glaze row, as the web renders it): the picker is more flexible than
      // the label (it shrinks to its arrows), so the label is offered space first and the picker keeps its ideal width when
      // the row has room for it. A macOS pop-up button is not a <select>, so the CSS oracle does not map these; the
      // oracle's `ported:picker-*` cases model the picker with the sizes x-picker-sizes records.
      Fixture(id: "x-picker-row") { HStack(spacing: 0) { Text("Glaze").font(.system(size: 17)).probe("x-picker-row.label"); Spacer(minLength: 12).probe("x-picker-row.spacer"); GlazePicker(id: "x-picker-row.picker") }.frame(width: 270).probe("x-picker-row.row") }
      Fixture(id: "x-picker-row-tight") { HStack(spacing: 0) { Text("Glaze").font(.system(size: 17)).probe("x-picker-row-tight.label"); Spacer(minLength: 12).probe("x-picker-row-tight.spacer"); GlazePicker(id: "x-picker-row-tight.picker") }.frame(width: 150).probe("x-picker-row-tight.row") }
      Fixture(id: "x-picker-sizes") { WidthProposals(widths: [0, nil, 60]) { GlazePicker(id: "x-picker-sizes.zero"); GlazePicker(id: "x-picker-sizes.unspecified"); GlazePicker(id: "x-picker-sizes.w60") } }
      // Controls the browser sizes by itself, sized as SwiftUI sizes them: a Divider runs across its stack (vertically in an HStack, also
      // through a frame, a padding or an overlay) and is a point thick; a progress bar, a slider and a gauge take the width they are
      // offered; a menu Picker hugs its selected label and shrinks to the width it is given; a TextEditor and a Canvas take what they are
      // offered. The heights of the bars, the slider and the gauge and the label of a gauge are macOS chrome (20, 16 and 46.5 pt where
      // the web authors 8, 6 and 40 px), so the oracle compares their widths and positions only (`PARTIAL` in css-layout-oracle.mjs).
      Fixture(id: "x-divider-vstack") { VStack(alignment: .leading, spacing: 8) { Text("Above").font(.system(size: 17)); Divider().probe("x-divider-vstack.d"); Text("Below").font(.system(size: 17)) }.frame(width: 200).probe("x-divider-vstack.v") }
      Fixture(id: "x-divider-vstack-centred") { VStack(spacing: 8) { Text("Above").font(.system(size: 17)); Divider().probe("x-divider-vstack-centred.d"); Text("Below").font(.system(size: 17)) }.probe("x-divider-vstack-centred.v") }
      Fixture(id: "x-divider-hstack") { HStack(spacing: 8) { Text("Left").font(.system(size: 17)); Divider().probe("x-divider-hstack.d"); Text("Right").font(.system(size: 17)) }.frame(width: 200, height: 40).probe("x-divider-hstack.h") }
      Fixture(id: "x-divider-hstack-fills") { HStack(spacing: 8) { Text("Left").font(.system(size: 17)); Divider().probe("x-divider-hstack-fills.d"); Text("Right").font(.system(size: 17)) }.probe("x-divider-hstack-fills.h") }
      Fixture(id: "x-divider-fixed-hstack") { HStack(spacing: 8) { Text("Left").font(.system(size: 17)); Divider().probe("x-divider-fixed-hstack.d"); Text("Right").font(.system(size: 17)) }.fixedSize(horizontal: false, vertical: true).probe("x-divider-fixed-hstack.h") }
      Fixture(id: "x-divider-fixed-vstack") { VStack(alignment: .leading, spacing: 8) { Text("Above").font(.system(size: 17)); Divider().probe("x-divider-fixed-vstack.d"); Text("Below").font(.system(size: 17)) }.fixedSize().probe("x-divider-fixed-vstack.v") }
      Fixture(id: "x-divider-framed") { VStack(alignment: .leading, spacing: 8) { Divider().probe("x-divider-framed.a").frame(width: 100).probe("x-divider-framed.fa"); Divider().probe("x-divider-framed.b").frame(height: 20).probe("x-divider-framed.fb") }.frame(width: 200).probe("x-divider-framed.v") }
      Fixture(id: "x-divider-alone") { Divider().probe("x-divider-alone.d") }
      Fixture(id: "x-divider-width") { Divider().probe("x-divider-width.d").frame(width: 100).probe("x-divider-width.f") }
      Fixture(id: "x-divider-frame-in-hstack") { HStack(spacing: 8) { Text("Left").font(.system(size: 17)); Divider().probe("x-divider-frame-in-hstack.d").frame(height: 20).probe("x-divider-frame-in-hstack.f"); Text("Right").font(.system(size: 17)) }.probe("x-divider-frame-in-hstack.h") }
      Fixture(id: "x-divider-padding-in-hstack") { HStack(spacing: 8) { Text("Left").font(.system(size: 17)); Divider().probe("x-divider-padding-in-hstack.d").padding(.horizontal, 4).probe("x-divider-padding-in-hstack.p"); Text("Right").font(.system(size: 17)) }.frame(width: 200, height: 40).probe("x-divider-padding-in-hstack.h") }
      Fixture(id: "x-divider-width-in-hstack") { HStack(spacing: 8) { Text("Left").font(.system(size: 17)); Divider().probe("x-divider-width-in-hstack.d").frame(width: 30).probe("x-divider-width-in-hstack.f"); Text("Right").font(.system(size: 17)) }.frame(width: 200, height: 40).probe("x-divider-width-in-hstack.h") }
      Fixture(id: "x-divider-max-height-in-hstack") { HStack(spacing: 8) { Text("Left").font(.system(size: 17)); Divider().probe("x-divider-max-height-in-hstack.d").frame(maxHeight: .infinity).probe("x-divider-max-height-in-hstack.f"); Text("Right").font(.system(size: 17)) }.frame(width: 200, height: 40).probe("x-divider-max-height-in-hstack.h") }
      Fixture(id: "x-divider-overlay-in-hstack") { HStack(spacing: 8) { Text("Left").font(.system(size: 17)); Color.clear.frame(width: 20).overlay(Divider().probe("x-divider-overlay-in-hstack.d")).probe("x-divider-overlay-in-hstack.o"); Text("Right").font(.system(size: 17)) }.frame(width: 200, height: 40).probe("x-divider-overlay-in-hstack.h") }
      Fixture(id: "x-divider-zstack-in-hstack") { HStack(spacing: 8) { Text("Left").font(.system(size: 17)); ZStack { Divider().probe("x-divider-zstack-in-hstack.d") }.probe("x-divider-zstack-in-hstack.z"); Text("Right").font(.system(size: 17)) }.frame(width: 200, height: 40).probe("x-divider-zstack-in-hstack.h") }
      Fixture(id: "x-divider-vstack-in-hstack") { HStack(spacing: 8) { Text("Left").font(.system(size: 17)); VStack { Divider().probe("x-divider-vstack-in-hstack.d") }.probe("x-divider-vstack-in-hstack.v"); Text("Right").font(.system(size: 17)) }.frame(width: 200, height: 40).probe("x-divider-vstack-in-hstack.h") }
      Fixture(id: "x-progress-vstack") { VStack(alignment: .leading, spacing: 8) { Text("Label").font(.system(size: 17)); ProgressView(value: 0.4).probe("x-progress-vstack.p") }.frame(width: 200).probe("x-progress-vstack.v") }
      Fixture(id: "x-progress-hstack") { HStack(spacing: 8) { Text("Label").font(.system(size: 17)); ProgressView(value: 0.4).probe("x-progress-hstack.p") }.frame(width: 260).probe("x-progress-hstack.h") }
      Fixture(id: "x-progress-framed") { ProgressView(value: 0.4).probe("x-progress-framed.p").frame(width: 150).probe("x-progress-framed.f") }
      Fixture(id: "x-progress-alone") { ProgressView(value: 0.4).probe("x-progress-alone.p") }
      Fixture(id: "x-progress-centred") { VStack(spacing: 8) { Text("Label").font(.system(size: 17)); ProgressView(value: 0.4).probe("x-progress-centred.p") }.probe("x-progress-centred.v") }
      Fixture(id: "x-slider-vstack") { VStack(alignment: .leading, spacing: 8) { Text("Label").font(.system(size: 17)); Slider(value: .constant(0.4)).probe("x-slider-vstack.p") }.frame(width: 200).probe("x-slider-vstack.v") }
      Fixture(id: "x-slider-hstack") { HStack(spacing: 8) { Text("Label").font(.system(size: 17)); Slider(value: .constant(0.4)).probe("x-slider-hstack.p") }.frame(width: 260).probe("x-slider-hstack.h") }
      Fixture(id: "x-slider-framed") { Slider(value: .constant(0.4)).probe("x-slider-framed.p").frame(width: 150).probe("x-slider-framed.f") }
      Fixture(id: "x-slider-alone") { Slider(value: .constant(0.4)).probe("x-slider-alone.p") }
      Fixture(id: "x-slider-centred") { VStack(spacing: 8) { Text("Label").font(.system(size: 17)); Slider(value: .constant(0.4)).probe("x-slider-centred.p") }.probe("x-slider-centred.v") }
      Fixture(id: "x-gauge-vstack") { VStack(alignment: .leading, spacing: 8) { Text("Label").font(.system(size: 17)); Gauge(value: 0.5) { Text("Level").font(.system(size: 17)) }.probe("x-gauge-vstack.p") }.frame(width: 200).probe("x-gauge-vstack.v") }
      Fixture(id: "x-gauge-hstack") { HStack(spacing: 8) { Text("Label").font(.system(size: 17)); Gauge(value: 0.5) { Text("Level").font(.system(size: 17)) }.probe("x-gauge-hstack.p") }.frame(width: 260).probe("x-gauge-hstack.h") }
      Fixture(id: "x-gauge-framed") { Gauge(value: 0.5) { Text("Level").font(.system(size: 17)) }.probe("x-gauge-framed.p").frame(width: 150).probe("x-gauge-framed.f") }
      Fixture(id: "x-gauge-alone") { Gauge(value: 0.5) { Text("Level").font(.system(size: 17)) }.probe("x-gauge-alone.p") }
      Fixture(id: "x-gauge-centred") { VStack(spacing: 8) { Text("Label").font(.system(size: 17)); Gauge(value: 0.5) { Text("Level").font(.system(size: 17)) }.probe("x-gauge-centred.p") }.probe("x-gauge-centred.v") }
      Fixture(id: "x-slider-row") { HStack(spacing: 8) { Text("Vol").font(.system(size: 17)); Slider(value: .constant(0.4)).probe("x-slider-row.p"); Text("100").font(.system(size: 17)) }.frame(width: 260).probe("x-slider-row.h") }
      Fixture(id: "x-menu-picker-hstack") { HStack(spacing: 8) { Text("Genre").font(.system(size: 17)); GlazePicker(id: "x-menu-picker-hstack.p"); Spacer() }.frame(width: 300).probe("x-menu-picker-hstack.h") }
      Fixture(id: "x-menu-picker-framed") { GlazePicker(id: "x-menu-picker-framed.p").frame(width: 150).probe("x-menu-picker-framed.f") }
      Fixture(id: "x-menu-picker-wide-frame") { GlazePicker(id: "x-menu-picker-wide-frame.p").frame(width: 250).probe("x-menu-picker-wide-frame.f") }
      Fixture(id: "x-menu-picker-tiny-frame") { GlazePicker(id: "x-menu-picker-tiny-frame.p").frame(width: 40).probe("x-menu-picker-tiny-frame.f") }
      Fixture(id: "x-menu-picker-alone") { GlazePicker(id: "x-menu-picker-alone.p") }
      Fixture(id: "x-menu-picker-centred") { VStack(spacing: 8) { Text("Genre").font(.system(size: 17)); GlazePicker(id: "x-menu-picker-centred.p") }.probe("x-menu-picker-centred.v") }
      Fixture(id: "x-menu-picker-share") { HStack(spacing: 8) { GlazePicker(id: "x-menu-picker-share.a"); GlazePicker(id: "x-menu-picker-share.b") }.frame(width: 250, height: 40).probe("x-menu-picker-share.h") }
      Fixture(id: "x-editor-height") { ControlEditor().probe("x-editor-height.e").frame(height: 90).probe("x-editor-height.f") }
      Fixture(id: "x-editor-size") { ControlEditor().probe("x-editor-size.e").frame(width: 200, height: 90).probe("x-editor-size.f") }
      Fixture(id: "x-editor-alone") { ControlEditor().probe("x-editor-alone.e") }
      Fixture(id: "x-editor-vstack") { VStack(alignment: .leading, spacing: 8) { Text("Notes").font(.system(size: 17)); ControlEditor().probe("x-editor-vstack.e") }.frame(width: 200, height: 150).probe("x-editor-vstack.v") }
      Fixture(id: "x-editor-framed-in-vstack") { VStack(alignment: .leading, spacing: 8) { Text("Notes").font(.system(size: 17)); ControlEditor().probe("x-editor-framed-in-vstack.e").frame(height: 90).probe("x-editor-framed-in-vstack.f") }.frame(width: 200).probe("x-editor-framed-in-vstack.v") }
      Fixture(id: "x-editor-padded") { ControlEditor().probe("x-editor-padded.e").frame(width: 200, height: 90).padding(4).probe("x-editor-padded.p") }
      Fixture(id: "x-canvas-size") { ControlCanvas().probe("x-canvas-size.c").frame(width: 200, height: 12).probe("x-canvas-size.f") }
      Fixture(id: "x-canvas-height") { VStack(alignment: .leading, spacing: 8) { Text("Canvas").font(.system(size: 17)); ControlCanvas().probe("x-canvas-height.c").frame(height: 12).probe("x-canvas-height.f") }.frame(width: 200).probe("x-canvas-height.v") }
      Fixture(id: "x-canvas-alone") { ControlCanvas().probe("x-canvas-alone.c") }
      // Offered no height (below a fixedSize) a Canvas is 10 pt tall; the web's canvas has a 1 px border, which the web layer adds to that.
      Fixture(id: "x-canvas-ideal") { VStack(alignment: .leading, spacing: 8) { Text("Canvas").font(.system(size: 17)); ControlCanvas().probe("x-canvas-ideal.c") }.fixedSize(horizontal: false, vertical: true).probe("x-canvas-ideal.v") }
      Fixture(id: "x-canvas-vstack") { VStack(alignment: .leading, spacing: 8) { Text("Canvas").font(.system(size: 17)); ControlCanvas().probe("x-canvas-vstack.c") }.frame(width: 200, height: 100).probe("x-canvas-vstack.v") }
    }.padding(20).onPreferenceChange(ProbeKey.self) { box.frames = $0 }
  }
}

@main
struct Main {
  @MainActor static func main() throws {
    let box = Box()
    _ = NSApplication.shared
    let hosting = NSHostingView(rootView: ExtraRoot(box: box))
    hosting.frame = NSRect(x: 0, y: 0, width: 390, height: 30000)
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
