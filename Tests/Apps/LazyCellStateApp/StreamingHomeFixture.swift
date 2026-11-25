import SwiftUIWeb

/// The fixture of `Tools/test-streaming-home-resize-browser.mjs`: the shape of a streaming app's home screen, which a window
/// resize has to stay cheap on. A hero of three slides (a poster over a blurred, scaled copy of itself, a second poster with a
/// shadow and a rotation, a gradient, a rounded clip, a height that follows the width, slides swapped with an opacity
/// transition), six rails of twelve poster tiles whose placeholder is a `Canvas` painting 16 by 16 colored rectangles under a
/// blur, and a navigation bar over a material. Everything is sized from the window's width, so a resize changes every box.
/// How many times a placeholder's drawing closure ran: the page shows it (`streaming-draws`) so a test counts the draws a resize costs.
enum StreamingStats {
  nonisolated(unsafe) static var draws = 0
}

struct StreamingHomeFixture: View {
  /// Whether each poster keeps its canvas placeholder mounted under the image that covers it (the default), or has none: the
  /// copy without placeholders measures what the covered placeholders cost.
  var placeholders = true
  /// The grid the placeholder paints: 16 by 16 as a blur hash is shown (the default); the copy with a coarser grid measures what each fill costs.
  var grid = 16
  static let rails = 6
  static let tilesPerRail = 12
  static let slides = 3

  var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        let width = proxy.size.width
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            StreamingHero(width: width, placeholders: placeholders, grid: grid)
            ForEach(0..<Self.rails, id: \.self) { rail in
              StreamingRail(rail: rail, tileWidth: min(max(width * 0.14, 110), 200), placeholders: placeholders, grid: grid)
            }
          }
          .padding(.bottom, 24)
        }
      }
      .navigationTitle("Streaming")
      .toolbarBackground(.regularMaterial, for: .navigationBar)
      .accessibilityIdentifier("streaming-home")
    }
  }
}

/// The hero: one slide at a time, swapped with `.transition(.opacity)`.
struct StreamingHero: View {
  let width: Double
  let placeholders: Bool
  let grid: Int
  @State private var slide = 0

  var body: some View {
    VStack(spacing: 8) {
      ZStack(alignment: .bottomLeading) {
        StreamingHeroSlide(index: slide, width: width, placeholders: placeholders, grid: grid).id(slide).transition(.opacity)
      }
      .animation(.easeInOut(duration: 0.4), value: slide)
      Text("draws \(StreamingStats.draws)").font(.caption).accessibilityIdentifier("streaming-draws")
      HStack(spacing: 8) {
        ForEach(0..<StreamingHomeFixture.slides, id: \.self) { index in
          Button("Slide \(index + 1)") { slide = index }.accessibilityIdentifier("streaming-slide-\(index)")
        }
      }
      .padding(.horizontal, 16)
    }
  }
}

struct StreamingHeroSlide: View {
  let index: Int
  let width: Double
  let placeholders: Bool
  let grid: Int

  var body: some View {
    let height = min(max(width * 0.42, 220), 520)
    let poster = min(max(width * 0.19, 120), 290)
    ZStack(alignment: .bottomLeading) {
      ZStack {
        StreamingArtwork(seed: index * 7 + 3, placeholder: placeholders, grid: grid)
          .blur(radius: 40)
          .scaleEffect(1.5)
          .opacity(0.8)
        StreamingArtwork(seed: index * 7 + 3, placeholder: placeholders, grid: grid)
          .frame(width: poster, height: poster * 1.5)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .shadow(color: .black.opacity(0.6), radius: 22, y: 18)
          .rotationEffect(.degrees(4))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
          .padding(.trailing, width * 0.12)
      }
      LinearGradient(
        stops: [
          .init(color: Color.black.opacity(0.92), location: 0),
          .init(color: Color.black.opacity(0.62), location: 0.34),
          .init(color: Color.black.opacity(0), location: 0.66),
        ],
        startPoint: .leading,
        endPoint: .trailing
      )
      Text("Featured story \(index + 1)").font(.largeTitle).foregroundStyle(.white).padding(24)
    }
    .frame(height: height)
    .frame(maxWidth: .infinity)
    .clipShape(RoundedRectangle(cornerRadius: 22))
    .padding(.horizontal, 16)
    .accessibilityIdentifier("streaming-hero-\(index)")
  }
}

struct StreamingRail: View {
  let rail: Int
  let tileWidth: Double
  let placeholders: Bool
  let grid: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Rail \(rail + 1)").font(.headline).padding(.horizontal, 16)
      ScrollView(.horizontal) {
        LazyHStack(spacing: 10) {
          ForEach(0..<StreamingHomeFixture.tilesPerRail, id: \.self) { tile in
            StreamingArtwork(seed: rail * 31 + tile, placeholder: placeholders, grid: grid)
              .frame(width: tileWidth, height: tileWidth * 1.5)
              .clipShape(RoundedRectangle(cornerRadius: 10))
              .accessibilityIdentifier("streaming-tile-\(rail)-\(tile)")
          }
        }
        .padding(.horizontal, 16)
      }
    }
  }
}

/// A poster: a placeholder painted from a 16 by 16 grid of colors (the way a blur hash is shown), blurred, over the poster's
/// image, which is a generated vector picture so the fixture needs no files.
struct StreamingArtwork: View {
  let seed: Int
  let placeholder: Bool
  let grid: Int

  var body: some View {
    ZStack {
      if placeholder { StreamingPlaceholder(seed: seed, grid: grid) }
      AsyncImage(url: URL(string: StreamingArtwork.imageURL(seed: seed))) { phase in
        if let image = phase.image {
          image.resizable().scaledToFill()
        } else {
          Color.clear
        }
      }
    }
    .clipped()
  }

  static func imageURL(seed: Int) -> String {
    let hue = (seed * 47) % 360
    let svg = "%3Csvg xmlns='http://www.w3.org/2000/svg' width='40' height='60'%3E%3Crect width='40' height='60' fill='hsl(\(hue),55%25,45%25)'/%3E%3Ccircle cx='20' cy='24' r='12' fill='hsl(\((hue + 40) % 360),60%25,65%25)'/%3E%3C/svg%3E"
    return "data:image/svg+xml," + svg
  }
}

struct StreamingPlaceholder: View {
  let seed: Int
  let grid: Int

  var body: some View {
    Canvas { context, size in
      StreamingStats.draws += 1
      let cell = grid
      for row in 0..<cell {
        for column in 0..<cell {
          let value = (seed &* 131 &+ row &* 17 &+ column &* 29) % 97
          let color = Color(red: Double(value) / 97, green: Double((value * 3) % 97) / 97, blue: Double((value * 7) % 97) / 97)
          let rect = CGRect(
            x: Double(column) / Double(cell) * size.width, y: Double(row) / Double(cell) * size.height,
            width: size.width / Double(cell), height: size.height / Double(cell))
          context.fill(Path(rect), with: .color(color))
        }
      }
    }
    .blur(radius: 8)
    .clipped()
  }
}
