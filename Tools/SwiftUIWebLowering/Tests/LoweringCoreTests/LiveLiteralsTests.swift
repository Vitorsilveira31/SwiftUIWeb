import Testing

@testable import LoweringCore

/// The `live-literals` pass alone, over an application file at `Sources/App/View.swift`.
private func live(_ source: String, path: String? = "Sources/App/View.swift") -> LoweringResult {
  let pipeline = LoweringPipeline.standard.selecting(["live-literals"])!
  return lower(pipeline, source, options: LoweringOptions(lowerCodable: true, liveLiteralsFile: path))
}

private let prefix = UInt64(LiveLiteralSites.pathHash("Sources/App/View.swift")) << 32
private func id(_ ordinal: UInt64) -> String { String(prefix | ordinal) }
private let marker = "\n// swiftuiweb:live-literals\n"

private func values(_ source: String) -> [String] { LiveLiteralSites.find(in: source).map { "\($0.kind.rawValue):\($0.value)" } }

@Suite struct LiveLiteralsTests {
  // MARK: What is wrapped

  @Test func literalsInABodyAreWrappedInSourceOrder() {
    let source = "struct V: View {\n  var body: some View { Text(\"Hi\").padding(8).opacity(0.5).disabled(false) }\n}\n"
    let result = live(source)
    #expect(
      result.text
        == "struct V: View {\n  var body: some View { Text(_live(\(id(0)), \"Hi\")).padding(_live(\(id(1)), 8)).opacity(_live(\(id(2)), 0.5)).disabled(_live(\(id(3)), false)) }\n}\n"
        + marker)
    #expect(result.counts["live-literals"] == 4)
  }

  @Test func functionsInitializersAndClosuresAreBodies() {
    #expect(values("func f() -> Int { 1 }\nstruct S { init() { _ = 2 }\n  var x: Int { get { 3 } }\n}\nlet c = { 4 }\n") == ["number:1", "number:2", "number:3", "number:4"])
  }

  @Test func aValueEvaluatedOnceIsLeftAlone() {
    // A stored property, a default argument, an enum's raw value and an attribute are read once or by the compiler.
    #expect(values("struct S {\n  static let a = 1\n  var b = \"x\"\n  func f(c: Int = 2) {}\n}\nenum E: Int { case a = 3 }\n@available(macOS 15, *) func g() {}\n").isEmpty)
  }

  @Test func aLiteralTheCompilerMustReadIsLeftAlone() {
    let source = "func f(x: Int) {\n  fatalError(\"never\")\n  logger.info(\"saved\")\n  switch x { case 1: break\n  default: break }\n  _ = a[0]\n  _ = \"n: \\(x)\"\n  _ = #\"raw\"#\n  _ = 0xFF\n}\n"
    #expect(values(source).isEmpty)
  }

  @Test func aStringIsReportedWithItsEscapesResolved() {
    let found = values("func f() -> String { \"a\\tb\\n\" }\n"); #expect(found == ["string:a\tb\n"], "\(found)")
  }

  @Test func aNumberLosesItsSeparators() {
    #expect(values("func f() -> Int { 1_000 }\nfunc g() -> Double { 1_0.5 }\n") == ["number:1000", "number:10.5"])
  }

  // MARK: Idempotence and files that do not apply

  @Test func aFileWithNothingToWrapStillGetsTheMarker() {
    #expect(live("struct S {}\n").text == "struct S {}\n" + marker)
  }

  @Test func aLoweredFileIsNotLoweredAgain() {
    let once = live("func f() -> Int { 1 }\n").text
    #expect(live(once).text == once)
  }

  @Test func withoutAFileNothingChanges() {
    let source = "func f() -> Int { 1 }\n"
    #expect(live(source, path: nil).text == source)
  }

  @Test func theIdHoldsThePathAndTheOrdinal() {
    let other = lower(LoweringPipeline.standard.selecting(["live-literals"])!, "func f() -> Int { 1 }\n", options: LoweringOptions(lowerCodable: true, liveLiteralsFile: "Sources/App/Other.swift")).text
    #expect(other.contains("_live(\(UInt64(LiveLiteralSites.pathHash("Sources/App/Other.swift")) << 32), 1)"))
    #expect(!other.contains("_live(\(id(0)), 1)"))
  }

  // MARK: The skeleton the development loop compares

  @Test func twoSourcesThatDifferOnlyInLiteralValuesShareASkeleton() throws {
    let old = "func f() -> some View { Text(\"Hi\").padding(8) }\n", new = "func f() -> some View { Text(\"Hello there\").padding(12.5) }\n"
    let before = LiveLiteralSites.find(in: old), after = LiveLiteralSites.find(in: new)
    let oldSkeleton = try LiveLiteralSites.skeleton(of: old, sites: before), newSkeleton = try LiveLiteralSites.skeleton(of: new, sites: after)
    #expect(oldSkeleton == newSkeleton)
    #expect(before.map(\.kind) == [.string, .number] && after.map(\.value) == ["Hello there", "12.5"])
  }

  // MARK: The replacements of a save

  private func replacements(_ old: String, _ new: String) -> [String]? {
    do {
      return try LiveLiteralSites.replacements(old: old, new: new, relativePath: "Sources/App/View.swift")
    } catch {
      Issue.record("replacements failed: \(error)")
      return nil
    }
  }

  @Test func aSaveThatOnlyChangesValuesGivesOneLinePerChangedLiteral() {
    let old = "func f() -> some View { Text(\"Hi\").padding(8).opacity(0.5).disabled(false) }\n"
    let new = "func f() -> some View { Text(\"a\\tb\").padding(8).opacity(0.75).disabled(true) }\n"
    #expect(replacements(old, new) == ["\(id(0))\ts\ta\\tb", "\(id(2))\tn\t0.75", "\(id(3))\tb\ttrue"])
    #expect(replacements(old, old) == [])
  }

  @Test func aSaveThatChangesAnythingElseNeedsABuild() {
    let old = "func f() -> some View { Text(\"Hi\").padding(8) }\n"
    #expect(replacements(old, "func f() -> some View { Text(\"Hi\").padding(8).bold() }\n") == nil)
    #expect(replacements(old, "func f() -> some View { Text(\"Hi\").padding(true) }\n") == nil)
    #expect(replacements(old, "func f() -> some View { Text(\"Hi\") }\n") == nil)
  }

  @Test func anIntegerThatBecomesAFractionNeedsABuild() {
    // `let amount = 1` is an Int and `let amount = 1.5` a Double: the page was compiled for the first.
    #expect(replacements("func f() { let amount = 1; use(amount) }\n", "func f() { let amount = 1.5; use(amount) }\n") == nil)
    #expect(replacements("func f() { let amount = 1.5; use(amount) }\n", "func f() { let amount = 2; use(amount) }\n") == nil)
    #expect(replacements("func f() { let amount = 1.5; use(amount) }\n", "func f() { let amount = 2.25; use(amount) }\n") == ["\(id(0))\tn\t2.25"])
    #expect(replacements("func f() { let amount = 1; use(amount) }\n", "func f() { let amount = 1_000; use(amount) }\n") == ["\(id(0))\tn\t1000"])
  }

  @Test func anEditOutsideALiteralChangesTheSkeleton() throws {
    let old = "func f() -> some View { Text(\"Hi\").padding(8) }\n", new = "func f() -> some View { Text(\"Hi\").padding(8).bold() }\n"
    let oldSkeleton = try LiveLiteralSites.skeleton(of: old, sites: LiveLiteralSites.find(in: old))
    let newSkeleton = try LiveLiteralSites.skeleton(of: new, sites: LiveLiteralSites.find(in: new))
    #expect(oldSkeleton != newSkeleton)
  }
}

@Suite struct DevelopmentExportsTests {
  private let entry = "import SwiftUIWeb\n@main struct Demo: BrowserApp {\n  var body: some Scene { WindowGroup { Text(\"Hi\") } }\n}\n"

  @Test func theEntryFileGetsTheStateSaveEntryPointOnlyWhenAsked() {
    let pipeline = LoweringPipeline.standard
    let with = lower(pipeline, entry, options: LoweringOptions(lowerCodable: true, developmentExports: true)).text
    let without = lower(pipeline, entry, options: LoweringOptions(lowerCodable: true)).text
    #expect(with.contains("@_expose(wasm, \"embedded_browser_state_save\")"))
    #expect(with.contains("BrowserAppLauncher.embeddedBrowserStateSave()"))
    #expect(!without.contains("embedded_browser_state_save"))
    #expect(without.contains("embedded_browser_start"), "the fixture is an entry file")
  }
}
