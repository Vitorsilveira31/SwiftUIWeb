import SwiftUIWeb


// Plain Foundation-style Codable, as an Apple/Android app writes it. The
// Embedded lowerer maps the decoder spellings onto its JSON shim, so this file
// is identical on every platform.

struct CodableFixtureContent: Decodable {
  enum Kind: String, Codable { case movie, series }
  let id: String
  let kind: Kind
  let link: URL?
  let tags: [String]
}

struct CodableFixtureFlags: Decodable, Equatable {
  var rewardedAds = false
  var subscriptions = true
  enum CodingKeys: String, CodingKey {
    case rewardedAds = "rewardedAdsEnabled", subscriptions = "subscriptionsEnabled"
  }

  init() {}
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    rewardedAds = try c.decodeIfPresent(Bool.self, forKey: .rewardedAds) ?? false
    subscriptions = try c.decodeIfPresent(Bool.self, forKey: .subscriptions) ?? true
  }
}

enum CodableFixtureAccess: Decodable, Equatable {
  case free, locked, unknown
  init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    switch raw {
    case "free": self = .free
    case "locked": self = .locked
    default: self = .unknown
    }
  }
}

// A flattened composite: the parent's own fields and the child's share one object.
struct CodableFixtureComposite: Decodable {
  enum PlainKeys: CodingKey { case badge, meta }
  enum MetaKeys: String, CodingKey { case level, access }
  let content: CodableFixtureContent
  let badge: String
  let level: Int
  let access: CodableFixtureAccess
  init(from decoder: Decoder) throws {
    content = try CodableFixtureContent(from: decoder)
    let c = try decoder.container(keyedBy: PlainKeys.self)
    badge = try c.decode(String.self, forKey: .badge)
    let meta = try c.nestedContainer(keyedBy: MetaKeys.self, forKey: .meta)
    level = try meta.decode(Int.self, forKey: .level)
    access = try meta.decodeIfPresent(CodableFixtureAccess.self, forKey: .access) ?? .unknown
  }
}

// A nested type that names a sibling nested type declared in the parent.
struct CodableFixtureHome: Decodable {
  enum Layout: String, Codable { case row, grid }
  struct Section: Decodable {
    let layout: Layout
    let items: [CodableFixtureContent]
  }
  let sections: [Section]
}

enum CodableFixture {
  static func run() -> String {
    var step = "cancellation"
    do {
      try Task.checkCancellation()
      let decoder = JSONDecoder()
      step = "content"
      let content = try decoder.decode(
        CodableFixtureContent.self,
        from: Data(#"{"id":"a","kind":"series","link":"https://example.com/x","tags":["t"]}"#.utf8))
      guard content.kind == .series, content.link?.absoluteString == "https://example.com/x" else { return "FAIL content" }
      step = "flags"
      let flags = try decoder.decode(
        CodableFixtureFlags.self, from: Data(#"{"rewardedAdsEnabled":true}"#.utf8))
      guard flags.rewardedAds, flags.subscriptions else { return "FAIL flags" }
      step = "composite"
      let composite = try decoder.decode(
        CodableFixtureComposite.self,
        from: Data(
          #"{"id":"b","kind":"movie","link":null,"tags":[],"badge":"new","meta":{"level":3,"access":"locked"}}"#.utf8))
      guard composite.content.id == "b", composite.content.kind == .movie, composite.content.link == nil,
        composite.badge == "new", composite.level == 3, composite.access == .locked
      else { return "FAIL composite" }
      step = "home"
      let home = try decoder.decode(
        CodableFixtureHome.self,
        from: Data(
          #"{"sections":[{"layout":"grid","items":[{"id":"c","kind":"movie","link":null,"tags":["x"]}]}]}"#
            .utf8))
      guard home.sections.first?.layout == .grid, home.sections.first?.items.first?.id == "c" else {
        return "FAIL home"
      }
      return "PASS"
    } catch {
      return "FAIL threw at \(step)"
    }
  }
}

struct EmbeddedCodableFixtureView: View {
  var body: some View { Text("codable-parity: \(CodableFixture.run())") }
}
