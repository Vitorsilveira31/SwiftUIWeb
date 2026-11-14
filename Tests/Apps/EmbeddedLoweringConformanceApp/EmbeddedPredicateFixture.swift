import SwiftUIWeb


// NSPredicate as an Apple application writes it. The same file runs against Foundation on native hosts and
// against WebFoundation's predicates in the browser; the expected answers are Foundation's.

final class PredicateFixturePerson: NSObject {
  let name: String
  let age: Int
  let tags: [String]
  init(_ name: String, _ age: Int, tags: [String] = []) {
    self.name = name
    self.age = age
    self.tags = tags
    super.init()
  }

  // Key-value coding: predicates read class instances through value(forKey:).
  override func value(forKey key: String) -> Any? {
    switch key {
    case "name": return name
    case "age": return age
    case "tags": return tags
    default: return nil
    }
  }
}

enum PredicateFixture {
  static func run() -> String {
    let alice: [String: Any] = [
      "name": "Alice", "age": 30, "score": 2.5, "active": true, "email": "alice@example.com",
      "tags": ["swift", "web"], "city": "café", "nick": NSNull(), "joined": Date(timeIntervalSince1970: 1_600_000_000),
      "address": ["city": "Lisbon"],
      "friends": [["name": "Bob", "age": 25], ["name": "Carol", "age": 35]],
    ]
    let bob: [String: Any] = ["name": "bob", "age": 25, "tags": [String](), "city": "cafe", "friends": [[String: Any]]()]
    var failures = ""
    func check(_ format: String, _ object: Any?, _ expected: Bool, _ arguments: [Any]? = nil) {
      let predicate = NSPredicate(format: format, argumentArray: arguments)
      if predicate.evaluate(with: object) != expected { failures += " [\(format)]" }
    }

    check("name == 'Alice'", alice, true)
    check("name == 'Alice'", bob, false)
    check("name = \"Alice\" && age > 20", alice, true)
    check("age <> 30 OR NOT (age < 18)", alice, true)
    check("age == 30.0 AND score > 2 AND active == YES", alice, true)
    check("age BETWEEN {25, 30}", alice, true)
    check("age BETWEEN {26, 34}", bob, false)
    check("age IN {25, 35}", bob, true)
    check("name BEGINSWITH[c] 'al' AND name ENDSWITH 'ce' AND name CONTAINS 'lic'", alice, true)
    check("name LIKE 'A?ice' AND email LIKE[c] '*@EXAMPLE.COM'", alice, true)
    check("name MATCHES '[A-Z][a-z]+' AND email MATCHES '[a-z]+@[a-z]+\\\\.com'", alice, true)
    check("city ==[d] 'cafe' AND city ==[cd] 'CAFE' AND city != 'cafe'", alice, true)
    check("nick == nil AND missing == nil AND name != nil", alice, true)
    check("ANY tags == 'web' AND NONE tags == 'go' AND tags.@count == 2", alice, true)
    check("ALL tags BEGINSWITH 's'", alice, false)
    check("friends.@count == 2 AND friends.@sum.age == 60 AND friends.@max.age == 35", alice, true)
    check("ANY friends.name == 'Bob' AND address.city == 'Lisbon'", alice, true)
    check("age + 1 == 31 AND age * 2 == 60 AND age / 4 == 7", alice, true)
    check("name IN %@ AND age > %d", alice, true, [["Alice", "Carol"], 18])
    check("%K == %@", alice, true, ["name", "Alice"])
    check("joined > %@", alice, true, [Date(timeIntervalSince1970: 1_500_000_000)])
    check("SELF IN {1, 2, 3}", 2, true)
    check("SELF MATCHES 'Hello.*' AND SELF CONTAINS[c] 'WORLD'", "Hello, World", true)
    check("TRUEPREDICATE AND NOT FALSEPREDICATE", nil, true)

    let carol = PredicateFixturePerson("Carol", 35, tags: ["swift"])
    check("name == 'Carol' AND age >= 35 AND ANY tags == 'swift'", carol, true)
    check("name == 'Carol' AND age < 35", carol, false)

    let adult = NSPredicate(format: "age >= %d", 18)
    let unbound = NSPredicate(format: "age > $MIN AND name == $NAME")
    if adult.predicateFormat != "age >= 18" { failures += " [predicateFormat \(adult.predicateFormat)]" }
    let canonical = NSPredicate(format: "name = 'a' && age <> 3 || NOT (x BETWEEN {1,2})")
    if canonical.predicateFormat != "(name == \"a\" AND age != 3) OR (NOT x BETWEEN {1, 2})" {
      failures += " [canonical \(canonical.predicateFormat)]"
    }
    let bound = unbound.withSubstitutionVariables(["MIN": 18, "NAME": "Alice"])
    if bound.predicateFormat != "age > 18 AND name == \"Alice\"" { failures += " [bound \(bound.predicateFormat)]" }
    if !bound.evaluate(with: alice) { failures += " [bound evaluate]" }
    if !unbound.evaluate(with: alice, substitutionVariables: ["MIN": 18, "NAME": "Alice"]) { failures += " [evaluate with variables]" }
    if unbound.evaluate(with: bob, substitutionVariables: ["MIN": 30, "NAME": "bob"]) { failures += " [bob below the minimum]" }
    if !NSPredicate(value: true).evaluate(with: nil) || NSPredicate(value: false).evaluate(with: alice) { failures += " [value]" }
    let block = NSPredicate { object, _ in (object as? Int ?? 0) > 3 }
    if !block.evaluate(with: 4) || block.evaluate(with: 3) { failures += " [block]" }

    let people: [Any] = [alice, bob, ["name": "Dan", "age": 41, "tags": ["swift"]] as [String: Any]]
    let filtered = NSArray(array: people).filtered(using: NSPredicate(format: "age > 26 AND ANY tags == 'swift'"))
    if filtered.count != 2 { failures += " [filtered \(filtered.count)]" }
    let mutable = NSMutableArray(array: people)
    mutable.filter(using: NSPredicate(format: "name BEGINSWITH[c] 'B'"))
    if mutable.count != 1 { failures += " [filter \(mutable.count)]" }
    if people.filter({ NSPredicate(format: "age >= 30").evaluate(with: $0) }).count != 2 { failures += " [Array.filter]" }
    return failures.isEmpty ? "PASS" : "FAIL" + failures
  }
}

struct EmbeddedPredicateFixtureView: View {
  var body: some View { Text("predicate-parity: \(PredicateFixture.run())") }
}
