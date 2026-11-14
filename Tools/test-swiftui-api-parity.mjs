#!/usr/bin/env bun
// Tests for Tools/swiftui-api-parity.mjs and Tools/api-contract.mjs with controlled symbol graphs and sources.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { runCases } from "./audit-support.mjs";
import { declaration as contractDeclaration } from "./api-contract.mjs";
import * as parity from "./swiftui-api-parity.mjs";

const TOOLS = dirname(fileURLToPath(import.meta.url));
const key = JSON.stringify;
const fragments = (...spellings) => spellings.map(([kind, spelling]) => ({ kind, spelling }));
const symbol = (kind, path, declarationFragments, parameters = null, returns = []) => {
  const item = { kind: { identifier: kind }, identifier: { precise: `s:${path.join(".")}` }, pathComponents: path, declarationFragments };
  if (parameters !== null) item.functionSignature = { parameters, returns };
  return item;
};
const parameter = (items) => ({ name: "p", declarationFragments: fragments(...items) });
const writeGraph = (directory, name, symbols, relationships = []) => {
  mkdirSync(directory, { recursive: true });
  const path = join(directory, `${name}.symbols.json`);
  writeFileSync(path, JSON.stringify({ symbols, relationships }));
  return path;
};
const withTemporary = (body) => {
  const directory = mkdtempSync(join(tmpdir(), "parity-test-"));
  try {
    return body(directory);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
};
/** A table entry whose overloads are `{title: [declaration, ...]}` and whose default flags are `{[title, declaration]: flags}`. */
const entryOf = (overloads, defaults = []) => {
  const entry = parity.newEntry();
  for (const [title, declarations] of Object.entries(overloads)) {
    entry.overloads.set(title, new Map(declarations.map((declaration) => [key(declaration), declaration])));
  }
  for (const [title, declaration, flags] of defaults) entry.defaults.set(key([title, declaration]), new Map([[key(flags), flags]]));
  return entry;
};
const isolationsOf = (table, name) => [...table.get(name).isolation.values()].flatMap((entries) => [...entries.values()]);

const INTERFACE = `
public struct Tab<Value, Content, Label> {
}
@available(iOS 18.0, *)
extension SwiftUI.Tab : SwiftUICore.View where Value : Swift.Hashable {
  @_disfavoredOverload nonisolated public init<S>(_ title: S, value: Value, systemImage: Swift.String = "x", @SwiftUICore.ViewBuilder content: () -> Content) where S : Swift.StringProtocol {
    fatalError()
  }
  public init(_ titleKey: SwiftUICore.LocalizedStringKey, value: Value, systemImage: Swift.String?) {
  }
  public func tint(_ color: SwiftUICore.Color? = nil) -> Self
  public func animate(_ animation: SwiftUICore.Animation? = { _ in .default }) {
    let inside = 1
  }
}
extension SwiftUIWebCore.Tab {
  public init(keyed phases: some Swift.Sequence<Swift.Int>, count: CGFloat = 0.5) {
  }
}
`;
const interfaceFound = () => new Map(parity.interfaceDeclarations(INTERFACE, {}).map(([owner, title, parameters, flags]) => [key([owner, title]), [parameters, flags]]));

await runCases({
  // ---- api-contract ---------------------------------------------------------------------------------------------------
  "api-contract: a wrapped property does not consume the next declaration"() {
    assert.equal(contractDeclaration(["public static let enabled = true", "}", "public struct Next {"], 0), "public static let enabled");
  },
  "api-contract: same-line public declarations are individual"() {
    const lines = ["public static let first = 1; public static let second = 2"];
    assert.equal(contractDeclaration(lines, 0, 0), "public static let first");
    assert.equal(contractDeclaration(lines, 0, lines[0].indexOf("public", 1)), "public static let second");
  },
  "api-contract: a function default argument is kept"() {
    const lines = ["public func load(retryCount: Int = 2) async throws -> String {"];
    assert.equal(contractDeclaration(lines, 0), "public func load(retryCount: Int = 2) async throws -> String");
  },

  // ---- baseline -------------------------------------------------------------------------------------------------------
  "prune removes fixed entries and never adds"() {
    const known = { comment: "c", extra: ["func A.a()", "func A.b()"], foreign: ["func F.f()"], signature: [] };
    const current = { extra: ["func A.b()", "func A.c()"], foreign: ["func F.f()", "func F.g()"], signature: ["func S.s()"] };
    const [pruned, unlisted] = parity.pruneBaseline(known, current);
    assert.deepEqual(pruned, { comment: "c", extra: ["func A.b()"], foreign: ["func F.f()"], signature: [] });
    assert.deepEqual(unlisted, { extra: ["func A.c()"], foreign: ["func F.g()"], signature: ["func S.s()"] });
  },
  "prune keeps the baseline unchanged when nothing is fixed"() {
    const known = { comment: "c", extra: ["func A.a()"], foreign: [], signature: [] };
    const [pruned, unlisted] = parity.pruneBaseline(known, { extra: ["func A.a()"] });
    assert.deepEqual(pruned, known);
    assert.deepEqual(unlisted, { extra: [], foreign: [], signature: [] });
  },
  "isolation is gated with an empty baseline list"() {
    const known = { comment: "c", extra: [], foreign: [], signature: [], isolation: ["func A.a()"] };
    const [pruned, unlisted] = parity.pruneBaseline(known, { isolation: ["func A.b()"] });
    assert.deepEqual(pruned.isolation, []);
    assert.deepEqual(unlisted.isolation, ["func A.b()"]);
  },

  // ---- type identifiers -----------------------------------------------------------------------------------------------
  "an opaque argument is dropped so both graph spellings compare alike"() {
    const webui = fragments(["keyword", "some "], ["typeIdentifier", "Sequence"], ["text", "<"], ["typeIdentifier", "Phase"], ["text", ">"]);
    const swiftui = fragments(["keyword", "some "], ["typeIdentifier", "Sequence"]);
    assert.deepEqual(parity.typeIdentifiers(webui), ["Sequence"]);
    assert.deepEqual(parity.typeIdentifiers(swiftui), ["Sequence"]);
  },
  "generic arguments outside opaque types are kept"() {
    assert.deepEqual(parity.typeIdentifiers(fragments(["typeIdentifier", "Array"], ["text", "<"], ["typeIdentifier", "Int"], ["text", ">"])), ["Array", "Int"]);
    const nested = fragments(
      ["keyword", "some "], ["typeIdentifier", "Keyframes"], ["text", "<"], ["typeIdentifier", "Value"], ["text", ">"], ["text", " "], ["typeIdentifier", "View"],
    );
    assert.deepEqual(parity.typeIdentifiers(nested), ["Keyframes", "View"]);
  },
  "a parameter with an opaque argument matches the SwiftUI declaration"() {
    const webui = symbol("swift.method", ["View", "phaseAnimator"], [], [
      { name: "phases", declarationFragments: fragments(["keyword", "some "], ["typeIdentifier", "Sequence"], ["text", "<"], ["typeIdentifier", "Phase"], ["text", ">"]) },
    ]);
    const apple = symbol("swift.method", ["View", "phaseAnimator"], [], [
      { name: "phases", declarationFragments: fragments(["keyword", "some "], ["typeIdentifier", "Sequence"]) },
    ]);
    assert.deepEqual(parity.parseDeclaration(webui), parity.parseDeclaration(apple));
  },
  "a result builder argument is dropped whatever its spelling"() {
    // SwiftUI prints `@TabContentBuilder<SelectionValue>`; SwiftUIWeb prints the same-type substitution.
    const apple = fragments(
      ["attribute", "@"], ["attribute", "TabContentBuilder"], ["text", "<"], ["typeIdentifier", "SelectionValue"], ["text", ">"], ["text", " "],
      ["identifier", "content"], ["text", ": () -> "], ["typeIdentifier", "Content"],
    );
    const webui = fragments(
      ["attribute", "@"], ["attribute", "TabContentBuilder"], ["text", "<"], ["typeIdentifier", "Optional"], ["text", "<"], ["typeIdentifier", "V"],
      ["text", ">>"], ["text", " "], ["identifier", "content"], ["text", ": () -> "], ["typeIdentifier", "Content"],
    );
    assert.deepEqual(parity.typeIdentifiers(apple), ["Content"]);
    assert.deepEqual(parity.typeIdentifiers(webui), ["Content"]);
  },
  "an attribute without arguments does not swallow the parameter type"() {
    const items = fragments(
      ["attribute", "@"], ["attribute", "ViewBuilder"], ["text", " "], ["identifier", "content"], ["text", ": () -> "], ["typeIdentifier", "Content"],
    );
    assert.deepEqual(parity.typeIdentifiers(items), ["Content"]);
  },
  "other attribute arguments are kept"() {
    const items = fragments(["attribute", "Custom"], ["text", "<"], ["typeIdentifier", "Bar"], ["text", ">"], ["text", " "], ["typeIdentifier", "Baz"]);
    assert.deepEqual(parity.typeIdentifiers(items), ["Bar", "Baz"]);
  },

  // ---- isolation ------------------------------------------------------------------------------------------------------
  "isolation words join the at sign and keep only isolation"() {
    const found = parity.isolationWords(fragments(
      ["attribute", "@"], ["attribute", "MainActor"], ["text", " "], ["attribute", "@preconcurrency"], ["text", " "], ["keyword", "protocol"],
      ["attribute", "@escaping "], ["keyword", "sending "], ["attribute", "@isolated(any) "], ["attribute", "nonisolated"], ["attribute", "ContentBuilder"],
    ));
    assert.deepEqual(found, ["@MainActor", "@isolated(any)", "@preconcurrency", "nonisolated", "sending"]);
  },
  "isolation words find closure isolation inside text fragments"() {
    const found = parity.isolationWords(fragments(
      ["text", ": "], ["attribute", "@escaping"], ["text", " "], ["text", "@isolated(any) "], ["attribute", "@Sendable"], ["text", " () -> Value"], ["typeIdentifier", "Sendable"],
    ));
    assert.deepEqual(found, ["@Sendable", "@isolated(any)"]);
  },
  "isolation words read a global actor written as text and type identifier"() {
    // The symbol graph writes the `@MainActor` of a closure parameter as `: @` plus a type identifier.
    const found = parity.isolationWords(fragments(
      ["identifier", "action"], ["text", ": @"], ["typeIdentifier", "MainActor"], ["text", " "], ["attribute", "@Sendable"], ["text", " () -> "], ["typeIdentifier", "Void"],
    ));
    assert.deepEqual(found, ["@MainActor", "@Sendable"]);
    // A type that is merely named like an attribute never counts.
    assert.deepEqual(parity.isolationWords(fragments(["text", ": "], ["typeIdentifier", "MainActor"])), []);
  },
  "isolation of a function splits own, parameter and result words"() {
    const item = symbol(
      "swift.method", ["Box", "run(_:)"],
      fragments(["attribute", "@"], ["attribute", "MainActor"], ["text", " "], ["keyword", "func"], ["text", " "], ["identifier", "run"], ["text", "("], ["identifier", "Int"], ["text", ")"]),
      [parameter([["keyword", "sending"], ["text", " "], ["typeIdentifier", "Int"]])],
      fragments(["attribute", "@Sendable"], ["text", " () -> Void"]),
    );
    const [own, parameters, results] = parity.isolationOf(item);
    assert.deepEqual(own, ["@MainActor"]);
    assert.deepEqual(parameters, [["sending"]]);
    assert.deepEqual(results, ["@Sendable"]);
  },
  "isolation of a variable counts its closure type"() {
    const item = symbol(
      "swift.property", ["Box", "action"],
      fragments(["keyword", "var"], ["text", " "], ["identifier", "action"], ["text", ": "], ["attribute", "@"], ["attribute", "MainActor"], ["text", " () -> Void"]),
    );
    const [own, parameters, results] = parity.isolationOf(item);
    assert.deepEqual(own, ["@MainActor"]);
    assert.deepEqual(parameters, []);
    assert.deepEqual(results, []);
  },
  "members of a main-actor class inherit main actor unless written nonisolated"() {
    // Apple's binary graphs print only written isolation; AVPlayerItem.asset prints none but is main-actor.
    const cls = symbol("swift.class", ["Player"], fragments(["attribute", "@"], ["attribute", "MainActor"], ["text", " "], ["keyword", "class"], ["text", " "], ["identifier", "Player"]));
    const asset = symbol("swift.property", ["Player", "asset"], fragments(["keyword", "var"], ["text", " "], ["identifier", "asset"], ["text", ": "], ["typeIdentifier", "Asset"]));
    const status = symbol(
      "swift.property", ["Player", "status"],
      fragments(["keyword", "nonisolated"], ["text", " "], ["keyword", "var"], ["text", " "], ["identifier", "status"], ["text", ": "], ["typeIdentifier", "Status"]),
    );
    const plain = symbol("swift.class", ["Plain"], fragments(["keyword", "class"], ["text", " "], ["identifier", "Plain"]));
    const plainMember = symbol("swift.property", ["Plain", "value"], fragments(["keyword", "var"], ["text", " "], ["identifier", "value"], ["text", ": "], ["typeIdentifier", "Int"]));
    withTemporary((directory) => {
      const table = parity.load([writeGraph(directory, "Player", [cls, asset, status, plain, plainMember])], { inferProtocolIsolation: true });
      assert.deepEqual(isolationsOf(table, "var Player.asset"), [[["@MainActor"], [], []]]);
      assert.deepEqual(isolationsOf(table, "var Player.status"), [[["nonisolated"], [], []]]);
      assert.deepEqual(isolationsOf(table, "var Plain.value"), [[[], [], []]]);
    });
  },
  "alignment maps the candidate onto the reference in order"() {
    assert.deepEqual(parity.alignment([["_", ["Int"]]], [["_", ["Int"]], ["style", ["Int"]]]), [0]);
    assert.deepEqual(parity.alignment([["style", ["Int"]]], [["_", ["Int"]], ["style", ["Int"]]]), [1]);
    assert.equal(parity.alignment([["x", ["Int"]]], [["_", ["Int"]]]), null);
  },
  "compare reports an isolation mismatch and accepts matching isolation"() {
    withTemporary((temporary) => {
      const appleNonisolated = symbol(
        "swift.method", ["Box", "run(_:)"], fragments(["keyword", "nonisolated"], ["text", " "], ["keyword", "func"], ["identifier", "run"]), [parameter([["typeIdentifier", "Int"]])],
      );
      const apple = parity.load([writeGraph(join(temporary, "apple"), "SwiftUI", [appleNonisolated])]);
      const mainActor = symbol(
        "swift.method", ["Box", "run(_:)"],
        fragments(["attribute", "@"], ["attribute", "MainActor"], ["text", " "], ["keyword", "func"], ["identifier", "run"]), [parameter([["typeIdentifier", "Int"]])],
      );
      let webui = parity.load([writeGraph(join(temporary, "webui"), "SwiftUIWeb", [mainActor])]);
      const report = parity.compare(apple, webui);
      assert.deepEqual(report.isolation.map((item) => item.key), ["func Box.run(_:)"]);
      assert(report.isolation[0].detail.includes("@MainActor"));
      assert.deepEqual(report.signature, []);
      assert.deepEqual(report.extra, []);

      const nonisolated = symbol(
        "swift.method", ["Box", "run(_:)"], fragments(["keyword", "nonisolated"], ["text", " "], ["keyword", "func"], ["identifier", "run"]), [parameter([["typeIdentifier", "Int"]])],
      );
      webui = parity.load([writeGraph(join(temporary, "webui"), "SwiftUIWeb", [nonisolated])]);
      assert.deepEqual(parity.compare(apple, webui).isolation, []);
    });
  },
  "compare checks the type of a protocol and its parameter isolation"() {
    withTemporary((temporary) => {
      const appleView = symbol(
        "swift.protocol", ["View"],
        fragments(["attribute", "@"], ["attribute", "MainActor"], ["text", " "], ["attribute", "@preconcurrency"], ["text", " "], ["keyword", "protocol"], ["identifier", "View"]),
      );
      const appleRun = symbol(
        "swift.method", ["View", "run(_:)"], fragments(["keyword", "func"], ["identifier", "run"]), [parameter([["keyword", "sending"], ["text", " "], ["typeIdentifier", "Int"]])],
      );
      const apple = parity.load([writeGraph(join(temporary, "apple"), "SwiftUI", [appleView, appleRun])]);
      const webuiView = symbol(
        "swift.protocol", ["View"], fragments(["attribute", "@"], ["attribute", "MainActor"], ["text", " "], ["keyword", "protocol"], ["identifier", "View"]),
      );
      const webuiRun = symbol("swift.method", ["View", "run(_:)"], fragments(["keyword", "func"], ["identifier", "run"]), [parameter([["typeIdentifier", "Int"]])]);
      const webui = parity.load([writeGraph(join(temporary, "webui"), "SwiftUIWeb", [webuiView, webuiRun])]);
      const report = parity.compare(apple, webui);
      assert.deepEqual(report.isolation.map((item) => item.key).sort(), ["func View.run(_:)", "type View"]);
      const details = Object.fromEntries(report.isolation.map((item) => [item.key, item.detail]));
      assert(details["type View"].includes("@preconcurrency"));
      assert(details["func View.run(_:)"].includes("param0: sending"));
    });
  },
  "apple protocol isolation is inferred from the refined protocol"() {
    // SwiftUIWeb's source graphs print the isolation a protocol inherits (`protocol Dynamic: View` is `@MainActor`); Apple's
    // binary graphs print only what was written, so Apple's is rebuilt.
    withTemporary((temporary) => {
      const make = (kind, path, ...spellings) => symbol(kind, path, fragments(...spellings));
      const mainActor = [["attribute", "@"], ["attribute", "MainActor"], ["text", " "]];
      const appleView = make("swift.protocol", ["View"], ...mainActor, ["keyword", "protocol"], ["identifier", "View"]);
      const appleDynamic = make("swift.protocol", ["Dynamic"], ["keyword", "protocol"], ["identifier", "Dynamic"]);
      const appleShape = make("swift.protocol", ["Shape"], ["keyword", "nonisolated"], ["text", " "], ["keyword", "protocol"], ["identifier", "Shape"]);
      const appleInset = make("swift.protocol", ["Inset"], ["keyword", "protocol"], ["identifier", "Inset"]);
      const appleData = make("swift.property", ["Dynamic", "data"], ["keyword", "var"], ["identifier", "data"]);
      const relationships = [
        { kind: "conformsTo", source: "s:Dynamic", target: "s:View" },
        { kind: "conformsTo", source: "s:Inset", target: "s:Shape" },
        { kind: "conformsTo", source: "s:Inset", target: "s:View" },
        { kind: "requirementOf", source: "s:Dynamic.data", target: "s:Dynamic" },
      ];
      const graph = writeGraph(join(temporary, "apple"), "SwiftUI", [appleView, appleDynamic, appleShape, appleInset, appleData], relationships);
      const apple = parity.load([graph], { inferProtocolIsolation: true });
      const webuiDynamic = make("swift.protocol", ["Dynamic"], ...mainActor, ["keyword", "protocol"], ["identifier", "Dynamic"]);
      const webuiData = make("swift.property", ["Dynamic", "data"], ["attribute", "@"], ["attribute", "MainActor"], ["text", " "], ["keyword", "var"], ["identifier", "data"]);
      const webuiInset = make("swift.protocol", ["Inset"], ["keyword", "protocol"], ["identifier", "Inset"]);
      const webui = parity.load([writeGraph(join(temporary, "webui"), "SwiftUIWeb", [webuiDynamic, webuiData, webuiInset])]);
      assert.deepEqual(parity.compare(apple, webui).isolation, []);
      // Without the inference the same graphs diverge, so the rule is what makes them equal.
      const plainApple = parity.load([graph]);
      assert.deepEqual(parity.compare(plainApple, webui).isolation.map((item) => item.key).sort(), ["type Dynamic", "var Dynamic.data"]);
    });
  },

  // ---- default arguments ----------------------------------------------------------------------------------------------
  "interface declarations carry owner, labels, types and defaults"() {
    const found = interfaceFound();
    // `S` and `Content` are generic parameters (the function's and the owner's), so both are `_G`.
    assert.deepEqual(found.get(key(["Tab", "init(_:value:systemImage:content:)"])), [
      [["_", ["_G"]], ["value", ["_G"]], ["systemImage", ["String"]], ["content", ["_G"]]], [false, false, true, false],
    ]);
    assert.deepEqual(found.get(key(["Tab", "init(_:value:systemImage:)"])), [
      [["_", ["LocalizedStringKey"]], ["value", ["_G"]], ["systemImage", ["String"]]], [false, false, false],
    ]);
    assert.deepEqual(found.get(key(["Tab", "tint(_:)"])), [[["_", ["Color"]]], [true]]);
    // A default value with braces does not open a scope, so the next declaration is still a member.
    assert.deepEqual(found.get(key(["Tab", "animate(_:)"]))[1], [true]);
  },
  "module-qualified extensions and opaque argument names compare alike"() {
    // `SwiftUIWebCore.Tab` is the same owner as `SwiftUI.Tab`; `some Sequence<Int>` drops its argument.
    assert.deepEqual(interfaceFound().get(key(["Tab", "init(keyed:count:)"]))[0], [["keyed", ["Sequence"]], ["count", ["Number"]]]);
  },
  "renames apply to the owner path"() {
    const found = parity.interfaceDeclarations("public struct _Hidden {\n public init(x: Int = 0) {}\n}\n", { _Hidden: "UserDefaults" });
    assert.deepEqual(found.map(([owner]) => owner), ["UserDefaults"]);
  },
  "unreadable declarations are skipped, not guessed"() {
    // A parameter without a colon cannot be read exactly, so no declaration is produced for it.
    assert.deepEqual(parity.interfaceDeclarations("public struct Odd {\n public func broken(_ value) {}\n}\n", {}), []);
  },
  "the disfavored attribute is read on the declaration's line and on attribute lines above it"() {
    const found = new Map(parity.interfaceDeclarations(INTERFACE, {}).map(([owner, title, , , disfavored]) => [key([owner, title]), disfavored]));
    assert.equal(found.get(key(["Tab", "init(_:value:systemImage:content:)"])), true);
    assert.equal(found.get(key(["Tab", "init(_:value:systemImage:)"])), false);
    const above = parity.interfaceDeclarations(
      'extension Animation {\n  @_disfavoredOverload\n  @available(iOS, deprecated, message: "use f(x:)")\n  public static func spring(response: Swift.Double = 0.5) -> Animation\n  public static func spring(duration: Swift.Double = 0.5) -> Animation\n}\n', {});
    assert.deepEqual(above.map(([, title, , , disfavored]) => [title, disfavored]), [["spring(response:)", true], ["spring(duration:)", false]]);
  },
  "an attribute with nested generic arguments does not hide its parameter"() {
    const found = parity.interfaceDeclarations("extension SwiftUIWebCore.TabSection {\n  @_disfavoredOverload public init<V>(@SwiftUIWebCore::TabContentBuilder<Swift::Optional<V>> content: () -> Content)\n}\n", {});
    assert.deepEqual(found.map(([owner, title, parameters, , disfavored]) => [owner, title, parameters, disfavored]), [["TabSection", "init(content:)", [["content", ["Content"]]], true]]);
  },
  "a disfavored overload on one side only is a disfavored divergence"() {
    // SwiftUI disfavors `spring(response:)`, so `.spring()` is `spring(duration:)`; SwiftUIWeb had it the other way round.
    const response = [["response", ["Number"]]];
    const duration = [["duration", ["Number"]]];
    const table = (disfavoredTitle) => {
      const entry = entryOf({ "spring(response:)": [response], "spring(duration:)": [duration] });
      entry.disfavored.set(key(["spring(response:)", response]), new Set([disfavoredTitle === "spring(response:)"]));
      entry.disfavored.set(key(["spring(duration:)", duration]), new Set([disfavoredTitle === "spring(duration:)"]));
      return new Map([["static func Animation.spring", entry]]);
    };
    let report = parity.compare(table("spring(response:)"), table("spring(duration:)"));
    assert.deepEqual(report.disfavored.map((item) => item.key), ["static func Animation.spring(duration:)", "static func Animation.spring(response:)"]);
    assert(report.disfavored.find((item) => item.key.endsWith("(response:)")).detail.startsWith("Apple disfavors"));
    report = parity.compare(table("spring(response:)"), table("spring(response:)"));
    assert.deepEqual(report.disfavored, []);
    // An attribute the interfaces do not give unambiguously (a platform variant) is not compared.
    const unknown = table("spring(duration:)");
    unknown.get("static func Animation.spring").disfavored.set(key(["spring(duration:)", duration]), new Set([true, false]));
    unknown.get("static func Animation.spring").disfavored.set(key(["spring(response:)", response]), new Set([false, true]));
    assert.deepEqual(parity.compare(table("spring(response:)"), unknown).disfavored, []);
  },
  "attach records only unambiguous defaults"() {
    const declaration = [["_", ["Int"]]];
    const table = new Map([["init Tab.init", entryOf({ "init(_:)": [declaration] })]]);
    parity.attachDefaults(table, new Map([[key(["Tab", "init(_:)", declaration]), new Map([[key([false]), [false]]])]]));
    assert.deepEqual([...table.get("init Tab.init").defaults].map(([slot, flags]) => [slot, [...flags.values()]]), [[key(["init(_:)", declaration]), [[false]]]]);
    table.get("init Tab.init").defaults.clear();
    parity.attachDefaults(table, new Map([[key(["Tab", "init(_:)", declaration]), new Map([[key([false]), [false]], [key([true]), [true]]])]]));
    assert.equal(table.get("init Tab.init").defaults.size, 0);
  },
  "a SwiftUIWeb default where Apple has none is a default divergence"() {
    // `systemImage: String? = nil` where Apple requires `systemImage`.
    const declaration = [["_", ["T"]], ["value", ["_G"]], ["systemImage", ["String"]]];
    const title = "init(_:value:systemImage:)";
    const report = parity.compare(
      new Map([["init Tab.init", entryOf({ [title]: [declaration] }, [[title, declaration, [false, false, false]]])]]),
      new Map([["init Tab.init", entryOf({ [title]: [declaration] }, [[title, declaration, [false, false, true]]])]]),
    );
    assert.deepEqual(report.default.map((item) => item.key), ["init Tab.init(_:value:systemImage:)"]);
    assert(report.default[0].detail.includes("'systemImage' has a default"));
  },
  "omitting an Apple parameter without a default is divergent"() {
    const appleDeclaration = [["_", ["T"]], ["value", ["_G"]], ["systemImage", ["String"]]];
    const webDeclaration = [["_", ["T"]], ["value", ["_G"]]];
    const report = parity.compare(
      new Map([["init Tab.init", entryOf({ "init(_:value:systemImage:)": [appleDeclaration] }, [["init(_:value:systemImage:)", appleDeclaration, [false, false, false]]])]]),
      new Map([["init Tab.init", entryOf({ "init(_:value:)": [webDeclaration] }, [["init(_:value:)", webDeclaration, [false, false]]])]]),
    );
    assert.equal(report.default.length, 1);
    assert(report.default[0].detail.includes("Apple requires 'systemImage'"));
  },
  "a defaulted overload equals two Apple overloads"() {
    // Apple: f(x:) and f(x:y:); SwiftUIWeb: f(x:y: = d). Call-compatible, so no divergence.
    const short = [["x", ["Int"]]];
    const long = [["x", ["Int"]], ["y", ["Int"]]];
    const report = parity.compare(
      new Map([["init Tab.init", entryOf({ "init(x:)": [short], "init(x:y:)": [long] }, [["init(x:)", short, [false]], ["init(x:y:)", long, [false, false]]])]]),
      new Map([["init Tab.init", entryOf({ "init(x:y:)": [long] }, [["init(x:y:)", long, [false, true]]])]]),
    );
    assert.deepEqual(report.default, []);
    assert.deepEqual(report.signature, []);
  },
  "a required SwiftUIWeb parameter where Apple defaults needs the shorter call"() {
    const long = [["x", ["Int"]], ["y", ["Int"]]];
    const short = [["x", ["Int"]]];
    const apple = () => new Map([["init Tab.init", entryOf({ "init(x:y:)": [long] }, [["init(x:y:)", long, [false, true]]])]]);
    let report = parity.compare(apple(), new Map([["init Tab.init", entryOf({ "init(x:y:)": [long] }, [["init(x:y:)", long, [false, false]]])]]));
    assert.equal(report.default.length, 1);
    assert(report.default[0].detail.includes("'y' is required where Apple's declaration defaults it"));
    report = parity.compare(
      apple(),
      new Map([["init Tab.init", entryOf({ "init(x:y:)": [long], "init(x:)": [short] }, [["init(x:y:)", long, [false, false]], ["init(x:)", short, [false]]])]]),
    );
    assert.deepEqual(report.default, []);
  },
  "an ambiguous identical Apple shape is unchecked, not compared with a longer overload"() {
    // Apple: `init(wrappedValue:_:)` once per value type (no default) plus one where clause that defaults it, and a
    // `init(wrappedValue:_:store:)` whose where clause defaults `wrappedValue`. Only the identical shape is the counterpart.
    const short = [["wrappedValue", ["_G"]], ["_", ["String"]]];
    const long = [["wrappedValue", ["_G"]], ["_", ["String"]], ["store", ["UserDefaults"]]];
    const apple = parity.newEntry();
    apple.overloads.set("init(wrappedValue:_:)", new Map([[key(short), short]]));
    apple.overloads.set("init(wrappedValue:_:store:)", new Map([[key(long), long]]));
    apple.defaults.set(key(["init(wrappedValue:_:)", short]), new Map([[key([false, false]), [false, false]], [key([true, false]), [true, false]]]));
    apple.defaults.set(key(["init(wrappedValue:_:store:)", long]), new Map([[key([true, false, true]), [true, false, true]]]));
    const report = parity.compare(
      new Map([["init SceneStorage.init", apple]]),
      new Map([["init SceneStorage.init", entryOf({ "init(wrappedValue:_:)": [short] }, [["init(wrappedValue:_:)", short, [false, false]]])]]),
    );
    assert.deepEqual(report.default, []);
    assert.deepEqual(report.unchecked.map((item) => item.key), ["init SceneStorage.init(wrappedValue:_:)"]);
  },
  "unknown flags are unchecked and never divergent"() {
    const declaration = [["x", ["Int"]]];
    const report = parity.compare(
      new Map([["init Tab.init", entryOf({ "init(x:)": [declaration] })]]),
      new Map([["init Tab.init", entryOf({ "init(x:)": [declaration] })]]),
    );
    assert.deepEqual(report.default, []);
    assert.deepEqual(report.unchecked.map((item) => item.key), ["init Tab.init(x:)"]);
  },

  // ---- Notification.Name and browser graphs ---------------------------------------------------------------------------
  "a real member matches NSNotification.Name"() {
    const [apple, webui] = notificationTables(null);
    const report = parity.compare(apple, webui, null, null, {});
    assert.deepEqual(report.extra, []);
    assert.deepEqual(report.foreign, []);
  },
  "a bogus member on Notification.Name is extra"() {
    const [apple, webui] = notificationTables("bogusCookieNotification");
    const report = parity.compare(apple, webui, null, null, {});
    assert.deepEqual(report.extra.map((item) => item.key), ["static var Notification.Name.bogusCookieNotification"]);
    assert.deepEqual(report.foreign, []);
  },
  "a nested typealias resolves Notification.Name"() {
    const apple = new Map([["static var NSNotification.Name.X", entryOf({})]]);
    assert.notEqual(parity.counterpartOf("static var Notification.Name.X", apple, {}, {}), null);
    assert.equal(parity.counterpartOf("static var Notification.Name.Y", apple, {}, {}), null);
  },
  "moduleSources keeps only the module's own declarations"() {
    const item = (name, source) => ({
      ...symbol("swift.type.property", ["Notification", "Name", name], fragments(["keyword", "static"], ["text", " "], ["identifier", name])),
      location: { uri: `file:///repo/Sources/${source}`, position: { line: 1, character: 1 } },
    });
    withTemporary((directory) => {
      const path = writeGraph(directory, "WebFoundation", [item("own", "WebFoundation/UpstreamFoundation.swift"), item("reexported", "SwiftUIWebCore/Core.swift")]);
      assert.deepEqual([...parity.load([path], { moduleSources: "WebFoundation" }).keys()].sort(), ["static var Notification.Name.own"]);
    });
  },
  "only declarations of Apple-declared types are compared"() {
    const apple = new Map([["type Notification", entryOf({})]]);
    assert.equal(parity.declaredByApple("static var Notification.Name.own", apple), true);
    assert.equal(parity.declaredByApple("func ceil(_:)", apple), false);
    assert.equal(parity.declaredByApple("init DispatchQueue.init(label:)", apple), false);
  },

  // ---- command line, on a fixture repository -------------------------------------------------------------------------
  "the gate fails on a new divergence, passes once it is listed and prunes what was fixed"() {
    withTemporary((temporary) => {
      const method = (name, labels = "_:") => symbol("swift.method", ["Box", `${name}(${labels})`], fragments(["keyword", "func"], ["identifier", name]), [parameter([["typeIdentifier", "Int"]])]);
      const box = symbol("swift.struct", ["Box"], fragments(["keyword", "struct"], ["identifier", "Box"]));
      const apple = join(temporary, "apple-fixture");
      writeGraph(apple, "SwiftUI", [box, method("run")]);
      writeGraph(apple, "Foundation", [symbol("swift.struct", ["Date"], fragments(["keyword", "struct"], ["identifier", "Date"]))]);
      const webui = join(temporary, "webui");
      // SwiftUIWeb's symbols are the ones whose USR names a module of the package (`Sources/<module>`).
      mkdirSync(join(temporary, "Sources", "SwiftUIWeb"), { recursive: true });
      const own = (item) => ({ ...item, identifier: { precise: `s:10SwiftUIWeb${item.pathComponents.join(".")}` } });
      writeGraph(webui, "SwiftUIWeb", [box, method("run"), method("extraMember")].map(own));
      const browser = join(temporary, "browser");
      writeGraph(browser, "WebFoundation", []);
      const baselinePath = join(temporary, "Documentation", "API", "swiftui-parity-baseline.json");
      mkdirSync(dirname(baselinePath), { recursive: true });
      const baseline = (extra) => writeFileSync(baselinePath, `${JSON.stringify({ comment: "c", extra, foreign: [], signature: [], isolation: [], default: [] }, null, 1)}\n`);
      const gate = (...flags) => spawnSync("bun", [join(TOOLS, "swiftui-api-parity.mjs"), "--apple-graphs", apple, "--webui-graphs", webui, "--browser-graphs", browser, ...flags], {
        encoding: "utf8", env: { ...process.env, SWIFTUIWEB_AUDIT_ROOT: temporary },
      });

      baseline([]);
      let run = gate("--check");
      assert.equal(run.status, 1, run.stdout + run.stderr);
      assert(run.stdout.includes("NEW extra divergences from SwiftUI (1):"));
      assert(run.stdout.includes("func Box.extraMember(_:)"));

      baseline(["func Box.extraMember(_:)", "func Box.gone(_:)"]);
      run = gate("--check");
      assert.equal(run.status, 0, run.stdout + run.stderr);
      assert(run.stdout.includes("1 baseline extra entries are fixed; run --update to prune them"));

      run = gate("--update");
      assert.equal(run.status, 0, run.stdout + run.stderr);
      assert(run.stdout.includes("pruned 1 fixed entries from Documentation/API/swiftui-parity-baseline.json"));
      assert.deepEqual(JSON.parse(readFileSync(baselinePath, "utf8")).extra, ["func Box.extraMember(_:)"]);

      baseline([]);
      run = gate("--update");
      assert.equal(run.status, 1);
      assert(run.stdout.includes("  unlisted extra: func Box.extraMember(_:)"));
      assert(run.stdout.includes("divergences above are not in the baseline and were not added; fix them in code"));
      assert.deepEqual(JSON.parse(readFileSync(baselinePath, "utf8")).extra, []);

      run = gate("--rewrite-baseline");
      assert.equal(run.status, 0, run.stdout + run.stderr);
      assert.equal(
        readFileSync(baselinePath, "utf8"),
        '{\n "comment": "Reviewed divergences from SwiftUI; shrink this list, never grow it.",\n "extra": [\n  "func Box.extraMember(_:)"\n ],\n "foreign": [],\n "signature": [],\n "isolation": [],\n "default": [],\n "disfavored": []\n}\n',
      );
      assert(existsSync(baselinePath));
      assert.equal(gate("--check", "--update").status, 2, "--check and --update are mutually exclusive");
    });
  },
}, "test-swiftui-api-parity");

function notificationTables(webuiMember) {
  return withTemporary((temporary) => {
    const name = (member) => symbol("swift.type.property", ["NSNotification", "Name", member], fragments(["keyword", "static"], ["text", " "], ["identifier", member]));
    const cookies = name("NSHTTPCookieManagerCookiesChanged");
    const appleType = symbol("swift.struct", ["Notification"], fragments(["keyword", "struct"], ["text", " "], ["identifier", "Notification"]));
    const apple = parity.load([writeGraph(join(temporary, "apple"), "Foundation", [cookies, appleType])]);
    const webName = (member) => symbol("swift.type.property", ["Notification", "Name", member], fragments(["keyword", "static"], ["text", " "], ["identifier", member]));
    const members = [webName("NSHTTPCookieManagerCookiesChanged")];
    if (webuiMember) members.push(webName(webuiMember));
    const webui = parity.load([writeGraph(join(temporary, "webui"), "WebFoundation", members)]);
    return [apple, webui];
  });
}
