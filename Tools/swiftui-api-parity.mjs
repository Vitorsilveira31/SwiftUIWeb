#!/usr/bin/env bun
// Checks SwiftUIWeb's public API against Apple's SwiftUI.
//
// SwiftUIWeb promises source compatibility with SwiftUI: application code written against the shared API must compile
// unchanged with Apple's SwiftUI on iOS and with SwiftUIWeb in the browser. `api-contract.mjs` only detects drift from
// SwiftUIWeb's own baseline; this tool compares against the real SwiftUI symbol graphs from the active Xcode SDKs (iOS
// simulator and macOS; a declaration matches Apple when it matches either platform).
//
// Three kinds of divergence are reported:
//
// * extra     public SwiftUIWeb member of a SwiftUI type with no SwiftUI counterpart (name, kind and argument labels,
//             tolerating defaulted parameters). Application code that uses it cannot compile on Apple platforms. Gated.
// * foreign   public SwiftUIWeb declaration on a type no compared Apple framework has: runtime internals, browser-only
//             features. Gated, so new ones need review.
// * signature the declaration exists in both but its parameter types differ after normalizing generics and CGFloat/Double.
//             Informational unless --strict-signatures is passed.
// * isolation a matched declaration's isolation differs: `nonisolated`, `@MainActor`, `@preconcurrency` (on types and
//             protocols), `sending` (parameters and results), `@Sendable`, `@isolated(any)` and `@concurrent`, on the
//             declaration itself, its parameters' types (closure types) and its result. Gated, with an empty baseline list:
//             every mismatch is fixed in code. Apple's graphs come from binary modules and print only written isolation, so
//             a protocol that refines a main-actor protocol (and its requirements) is read as main-actor isolated, as
//             SwiftUIWeb's source graphs print it.
// * default   a matched declaration's default arguments differ from Apple's. Apple's defaults come from the SDK's textual
//             interfaces (`.swiftinterface`), SwiftUIWeb's from its own module interfaces. A parameter SwiftUIWeb defaults
//             must be defaulted by Apple too, unless Apple has the same call without it (`f(x:)` plus `f(x:y:)` is
//             call-compatible with `f(x:y: = d)`); a parameter Apple defaults must be defaulted by SwiftUIWeb too, unless
//             SwiftUIWeb has the call without it; an Apple parameter without a default must not be omitted. Declarations
//             whose defaults cannot be read unambiguously from the interfaces are counted as `unchecked`, never guessed.
//             Gated, with an empty baseline list.
// * disfavored a matched function or initializer is `@_disfavoredOverload` on one side only. The attribute decides which
//             overload an unlabelled call picks (`.spring()` is SwiftUI's duration/bounce spring because the response/damping
//             one is disfavored), so a mismatch compiles on both and behaves differently. Read from the same textual
//             interfaces as defaults; a declaration whose attribute cannot be read unambiguously is not compared. Gated, with
//             an empty baseline list.
// * missing   SwiftUI API that SwiftUIWeb does not provide yet (coverage report).
//
// SwiftUIWeb also imitates a few non-SwiftUI Apple frameworks (Foundation's `UserDefaults` and `NumberFormatter`, StoreKit's
// `RequestReviewAction`, DeveloperToolsSupport's `PreviewLayout`, CoreGraphics' `CGFloat`/`CGPoint`/`CGRect`/`CGSize`/
// `CGAffineTransform` and `CGLineCap`/`CGLineJoin` (CGFloat is declared by CoreFoundation), Combine's `ObservableObject` and
// `Published`). Those frameworks' symbol graphs are compared too, with the rules used for SwiftUI: a declaration matching the
// framework's name, kind and labels is accepted, and one whose parameter types differ is a signature divergence. A class
// inherits its superclasses' members (`NumberFormatter()` is NSObject's `init()`), and a stand-in that application code
// reaches through an Apple name (the browser-only `public typealias UserDefaults = _WebUserDefaults`) has its members matched
// against that Apple type. A declaration on a non-SwiftUI type that matches nothing stays `foreign`, the category and key it
// had before these frameworks were compared, so it still fails the gate.
//
// WebFoundation is SwiftUIWeb's Foundation on every host. Its declarations (from the native graphs, and from an Embedded
// WebAssembly build of WebFoundation for the Embedded-only ones; `SWIFTUI_PARITY_EMBEDDED_SDK` names the SDK) are compared
// only on types an Apple framework declares: its extensions of the standard library (`String.components(separatedBy:)`)
// and its runtime helpers are not SwiftUI API. Modules the native graphs list only because SwiftUIWeb re-exports them
// (Dispatch, as Foundation re-exports it) are not compared. Nested Apple names resolve through NESTED_TYPEALIASES
// (`Notification.Name` is `NSNotification.Name`).
//
// Known divergences live in Documentation/API/swiftui-parity-baseline.json, so the gate fails only on new drift while the
// reviewed list is burned down.
//
// Baseline maintenance has two explicit modes:
//
// * `--update` only prunes: entries that no longer diverge are removed from the baseline. It never adds an entry; new
//   divergences are listed and must be fixed in code (or, after review, recorded by a rewrite). It exits non-zero while any
//   divergence is unlisted, so it is safe to run whenever fixes land.
// * `--rewrite-baseline` regenerates the baseline from the current state, adding every current divergence. Use it only when a
//   reviewed change legitimately accepts new divergences, and review the resulting diff line by line.
//
// usage: bun Tools/swiftui-api-parity.mjs [--generate] [--apple-graphs DIR...] [--webui-graphs DIR] [--browser-graphs DIR]
//        [--check | --update | --rewrite-baseline] [--strict-signatures] [--top N]
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, rmSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { basename, dirname, join, relative, resolve } from "node:path";
import {
  compareStrings, filesWithSuffix, isMain, jsonDumps, jsonEqual, stripWhitespace, SPACE_CLASS, readText, ROOT, rx, sortedStrings,
} from "./audit-support.mjs";

const BASELINE = join(ROOT, "Documentation", "API", "swiftui-parity-baseline.json");
const CACHE = join(ROOT, ".build", "api-parity");
// Apple's textual interfaces, per platform directory: (SDK name, target triples in preference order).
const APPLE_INTERFACES = {
  swiftui: ["iphonesimulator", ["arm64-apple-ios-simulator", "x86_64-apple-ios-simulator"]],
  macos: ["macosx", ["arm64e-apple-macos", "arm64-apple-macos", "x86_64-apple-macos"]],
};
// `quickLookPreview` is declared in the `_QuickLook_SwiftUI` module that SwiftUI re-exports.
const APPLE_MODULES = ["SwiftUI", "SwiftUICore", "_QuickLook_SwiftUI"];
// Other Apple frameworks SwiftUIWeb imitates. Only each framework's own graph is read (plus StoreKit's SwiftUI cross-import
// overlay, which `import StoreKit` brings into a SwiftUI app), not its extensions of the standard library.
const FRAMEWORK_MODULES = [
  "Foundation", "StoreKit", "DeveloperToolsSupport", "ObjectiveC", "CoreTransferable", "UniformTypeIdentifiers", "Observation",
  "CoreFoundation", "CoreGraphics", "Combine", "Symbols", "AVFoundation", "AVKit", "CoreMedia",
];
// Platform frameworks whose types SwiftUI's own modifiers take by name (`keyboardType(_: UIKeyboardType)`,
// `textContentType(_: UITextContentType?)`). Each platform compares only its own framework: the UIKit graph comes from the iOS
// simulator SDK and the AppKit graph from the macOS SDK.
const PLATFORM_FRAMEWORKS = { swiftui: ["UIKit"], macos: ["AppKit"] };
const FRAMEWORK_OVERLAYS = ["_StoreKit_SwiftUI", "_AVKit_SwiftUI"];
// Cross-import overlays of Foundation types (`Data.transferRepresentation`, `URL.contentType`): `import CoreTransferable`
// brings them into an app that also imports Foundation. CoreGraphics' overlay of CoreFoundation's clang types declares
// `CGPoint`, `CGSize`, `CGRect` and `CGAffineTransform`. Foundation's extensions of ObjectiveC's `NSObject` hold key-value
// coding (`value(forKey:)`). AVFoundation's extensions of `NSValue` hold `NSValue(time:)` and `timeValue`.
const FRAMEWORK_FOUNDATION_OVERLAYS = [
  "CoreTransferable@Foundation", "UniformTypeIdentifiers@Foundation", "CoreGraphics@CoreFoundation", "Foundation@ObjectiveC",
  "AVFoundation@Foundation",
  // Foundation's extensions of the standard library (`String.CompareOptions`, `String(localized:)`, `Sequence.sorted(using:)`):
  // SwiftUIWeb declares them on every host, as part of its Foundation.
  "Foundation@Swift",
];
// Cache directory -> (SDK, target). Source lowering evaluates `os(macOS)` as true in application code, so the macOS side of
// Apple's multiplatform API is as legitimate as the iOS side: a declaration matches Apple if it matches either.
const APPLE_PLATFORMS = {
  swiftui: ["iphonesimulator", "arm64-apple-ios17.0-simulator"],
  macos: ["macosx", "arm64-apple-macos14.0"],
};
// The consumer-facing SwiftUI replacement: SwiftUIWeb re-exports Core and Features.
const WEBUI_MODULES = ["SwiftUIWeb", "SwiftUIWebCore", "SwiftUIWebFeatures", "SwiftUIWebAVFoundation", "SwiftUIWebAVKit"];
// Every module of the package, read from `Sources/`: their symbols are SwiftUIWeb's, whichever graph lists them.
const SWIFTUIWEB_MODULES = existsSync(join(ROOT, "Sources"))
  ? readdirSync(join(ROOT, "Sources")).filter((name) => statSync(join(ROOT, "Sources", name)).isDirectory())
  : [];
const WEBUI_GRAPHS = join(ROOT, ".build", "out", "symbolgraph");
const WEBUI_INTERMEDIATES = join(ROOT, ".build", "out", "Intermediates.noindex");
// WebFoundation's browser-only shims (`UpstreamFoundation.swift`) compile only where Foundation is not imported, so the native
// graphs never contain them. Their graph and interface come from an Embedded WebAssembly build of that one module
// (SWIFTUI_PARITY_EMBEDDED_SDK names the installed SDK).
const BROWSER_GRAPHS = join(ROOT, ".build", "api-parity", "browser");
const BROWSER_SCRATCH = join(ROOT, ".build", "api-parity", "browser-build");
const BROWSER_SDK = process.env.SWIFTUI_PARITY_EMBEDDED_SDK ?? "swift-6.4.0-RELEASE_wasm-embedded";

const KIND_FAMILY = {
  "swift.struct": "type", "swift.class": "type", "swift.enum": "type", "swift.protocol": "type", "swift.actor": "type",
  "swift.typealias": "type", "swift.associatedtype": "associatedtype", "swift.method": "func", "swift.func": "func",
  "swift.func.op": "operator", "swift.type.method": "static func", "swift.property": "var", "swift.var": "var",
  "swift.type.property": "static var", "swift.init": "init",
  // An enum case and a static constant are used identically by callers.
  "swift.enum.case": "static var", "swift.subscript": "subscript", "swift.type.subscript": "static subscript",
};
const NUMBER_TYPES = new Set(["CGFloat", "Double", "Float", "Float64"]);

// ---- values -------------------------------------------------------------------------------------------------------------
// Maps and sets keyed by tuples. Here a declaration is `[[label, [type, ...]], ...]` and a set of declarations
// a Map from its JSON text to the declaration; isolation values are `[own, parameters, results]` with each word set a sorted
// array. Where only a message depends on the order of a set, insertion order is used.
const dk = (value) => JSON.stringify(value);
const addTo = (map, value) => map.set(dk(value), value);
const words = (items) => [...new Set(items)].sort(compareStrings);
const sameWords = (a, b) => a.length === b.length && a.every((word, index) => word === b[index]);
const unionWords = (a, b) => words([...a, ...b]);
const lastOf = (items) => items[items.length - 1];

/** The text after the last space-like separator of a key (split once from the right). */
function rsplitSpace(key) {
  const index = key.lastIndexOf(" ");
  return [key.slice(0, index), key.slice(index + 1)];
}

function run(command) {
  const result = spawnSync(command[0], command.slice(1), { cwd: ROOT, encoding: "utf8", maxBuffer: 1 << 28 });
  if (result.error || result.status !== 0) {
    fail(`${command.slice(0, 6).join(" ")} failed:\n${(result.stderr ?? String(result.error)).slice(-2000)}`);
  }
}

/** `sys.exit(message)`: the message goes to stderr and the status is 1. */
function fail(message) {
  console.error(message);
  process.exit(1);
}

function sdkPath(sdkName) {
  const result = spawnSync("xcrun", ["--show-sdk-path", "--sdk", sdkName], { encoding: "utf8" });
  if (result.error || result.status !== 0) fail(`xcrun --show-sdk-path --sdk ${sdkName} failed:\n${result.stderr ?? result.error}`);
  return result.stdout.trim();
}

/** Runs the native `swift`. */
function swift(args) {
  run(["swift", ...args]);
}

function generate() {
  // Writes the symbol graphs: Apple's from the iOS simulator and macOS SDKs.
  for (const [directory, [sdkName, target]] of Object.entries(APPLE_PLATFORMS)) {
    const sdk = sdkPath(sdkName);
    const apple = join(CACHE, directory);
    mkdirSync(apple, { recursive: true });
    for (const module of [...APPLE_MODULES, ...FRAMEWORK_MODULES, ...(PLATFORM_FRAMEWORKS[directory] ?? [])]) {
      run([
        "xcrun", "swift-symbolgraph-extract", "-module-name", module, "-target", target, "-sdk", sdk, "-output-dir", apple,
        "-minimum-access-level", "public", "-skip-synthesized-members",
      ]);
    }
  }
  // SwiftPM reuses the graph of the wrapper module (which re-exports the others) while its own sources are unchanged, even
  // after an imported module changed. Its build intermediates are removed so the graph is emitted again; the previous graphs
  // are removed as well.
  rmSync(join(ROOT, ".build", "out", "Intermediates.noindex", "SwiftUIWeb.build"), { recursive: true, force: true });
  if (existsSync(WEBUI_GRAPHS)) {
    for (const name of readdirSync(WEBUI_GRAPHS)) if (name.endsWith(".symbols.json")) unlinkSync(join(WEBUI_GRAPHS, name));
  }
  swift(["package", "dump-symbol-graph", "--minimum-access-level", "public", "--skip-synthesized-members"]);
  // The module interfaces carry SwiftUIWeb's default arguments; they are written by the same build.
  swift(["build", ...WEBUI_MODULES.flatMap((module) => ["--target", module]), "-Xswiftc", "-emit-module-interface"]);
  generateBrowser();
}

/** Writes WebFoundation's browser graph and interface from an Embedded WebAssembly build. */
function generateBrowser() {
  rmSync(BROWSER_SCRATCH, { recursive: true, force: true });
  rmSync(BROWSER_GRAPHS, { recursive: true, force: true });
  run([
    "swift", "build", "--disable-sandbox", "--swift-sdk", BROWSER_SDK, "--scratch-path", BROWSER_SCRATCH, "--target", "WebFoundation",
    "-Xswiftc", "-emit-symbol-graph", "-Xswiftc", "-emit-symbol-graph-dir", "-Xswiftc", BROWSER_GRAPHS,
    "-Xswiftc", "-symbol-graph-minimum-access-level", "-Xswiftc", "public",
    "-Xswiftc", "-symbol-graph-skip-synthesized-members", "-Xswiftc", "-emit-module-interface",
  ]);
}

/** The most recently written file called `name` under `root`, or null. */
function newestFile(root, name) {
  const matches = existsSync(root) && statSync(root).isDirectory() ? filesWithSuffix(root, "").filter((path) => basename(path) === name) : [];
  let best = null;
  for (const path of matches) if (best === null || statSync(path).mtimeMs > statSync(best).mtimeMs) best = path;
  return best;
}

/**
 * The newest module interface of every SwiftUIWeb module built in the package.
 *
 * A declaration can live in a module the parity graphs do not load (`Text.init(_:style:)` is in
 * SwiftUIWebInternationalization), so every SwiftUIWeb module's interface is read. WebFoundation's native interface is left
 * out: its browser-only shims come from the browser build's interface instead.
 */
function swiftuiwebInterfaces() {
  const newest = new Map();
  if (existsSync(WEBUI_INTERMEDIATES) && statSync(WEBUI_INTERMEDIATES).isDirectory()) {
    for (const path of filesWithSuffix(WEBUI_INTERMEDIATES, ".swiftinterface")) {
      const name = basename(path);
      if (name.startsWith("SwiftUIWeb") && name.split(".").length === 2) {
        const current = newest.get(name);
        if (current === undefined || statSync(path).mtimeMs > statSync(current).mtimeMs) newest.set(name, path);
      }
    }
  }
  return sortedStrings(newest.keys()).map((name) => newest.get(name));
}

/** Whether the declaration's owner type is one an Apple framework declares. */
export function declaredByApple(key, apple) {
  const owner = rsplitSpace(key)[1].split(".")[0];
  return apple.has(`type ${owner}`);
}

/**
 * Ordered [argument label, normalized type names] pairs of one declaration.
 *
 * The symbol graph does not record default values, so a declaration is later matched as a subsequence of its SwiftUI
 * counterpart's parameters.
 */
export function parseDeclaration(symbol) {
  const generics = new Set((symbol.swiftGenerics?.parameters ?? []).map((parameter) => parameter.name));
  const parameters = symbol.functionSignature?.parameters;
  if (parameters === undefined || parameters === null) return [];
  const title = lastOf(symbol.pathComponents);
  let concrete = {};
  // A member copied from a protocol extension still spells its owner `Self`.
  if (symbol.identifier.precise.includes("::SYNTHESIZED::") && symbol.pathComponents.length > 1) {
    generics.delete("Self");
    concrete = { Self: symbol.pathComponents[symbol.pathComponents.length - 2] };
  }
  const labels = title.includes("(") ? title.slice(title.indexOf("(") + 1, -1).split(":").slice(0, -1) : [];
  return parameters.map((parameter, index) => {
    const types = typeIdentifiers(parameter.declarationFragments ?? []).map((original) => {
      const name = Object.hasOwn(concrete, original) ? concrete[original] : original;
      return generics.has(name) ? "_G" : NUMBER_TYPES.has(name) ? "Number" : name;
    });
    return [index < labels.length ? labels[index] : "_", types];
  });
}

const countOf = (text, character) => text.split(character).length - 1;

/**
 * The type names a parameter's fragments spell, without opaque-type arguments.
 *
 * `some Sequence<Phase>` is printed with its generic argument in the graphs SwiftUIWeb's own modules emit, but SwiftUI's graph
 * prints the same source as `some Sequence`. Dropping the arguments of an opaque type's protocol makes both spellings compare
 * alike; other generic arguments are kept.
 */
export function typeIdentifiers(fragments) {
  const names = [];
  let skipping = 0; // open angle brackets inside an opaque type's arguments
  let afterSome = false;
  let opaqueName = false;
  let builderPending = false; // the previous fragment was a result-builder attribute name
  let builderDepth = 0; // open angle brackets inside a result-builder attribute's arguments
  for (const fragment of fragments) {
    const { kind, spelling } = fragment;
    if (skipping) {
      if (kind === "text") skipping += countOf(spelling, "<") - countOf(spelling, ">");
      continue;
    }
    if (builderDepth) {
      // `@TabContentBuilder<SelectionValue>`: Apple's graph spells the argument as the generic parameter, while a same-type
      // `SelectionValue == V?` makes SwiftUIWeb's spell it `Optional<V>`. Only the argument is dropped; the parameter's own
      // types still compare.
      if (kind === "text") builderDepth += countOf(spelling, "<") - countOf(spelling, ">");
      continue;
    }
    if (builderPending && kind === "text" && spelling.startsWith("<")) {
      builderPending = false;
      builderDepth = countOf(spelling, "<") - countOf(spelling, ">");
      continue;
    }
    builderPending = kind === "attribute" && spelling.endsWith("ContentBuilder");
    if (kind === "text" && !stripWhitespace(spelling)) continue;
    if (opaqueName && kind === "text" && spelling.startsWith("<")) {
      skipping = countOf(spelling, "<") - countOf(spelling, ">");
      opaqueName = false;
      continue;
    }
    opaqueName = afterSome && kind === "typeIdentifier";
    afterSome = kind === "keyword" && stripWhitespace(spelling) === "some";
    if (kind === "typeIdentifier") names.push(spelling);
  }
  return names;
}

/** Whether `candidate` is an ordered subsequence of `reference`, items compared through `key`. */
export function isSubsequence(candidate, reference, key = (item) => dk(item)) {
  let position = 0;
  const keys = reference.map(key);
  for (const item of candidate) {
    const wanted = key(item);
    let found = false;
    while (position < keys.length) {
      const matches = keys[position] === wanted;
      position += 1;
      if (matches) {
        found = true;
        break;
      }
    }
    if (!found) return false;
  }
  return true;
}

/** Indices of `reference` that `candidate` maps onto, in order, or null when it is not a subsequence. */
export function alignment(candidate, reference) {
  const indices = [];
  let start = 0;
  const keys = reference.map((item) => dk(item));
  for (const item of candidate) {
    const wanted = dk(item);
    let found = false;
    for (let index = start; index < reference.length; index += 1) {
      if (keys[index] === wanted) {
        indices.push(index);
        start = index + 1;
        found = true;
        break;
      }
    }
    if (!found) return null;
  }
  return indices;
}

// Keywords that end a declaration's own attributes: what follows is the declared name or the kind.
const DECLARATION_KEYWORDS = new Set([
  "func", "var", "let", "init", "subscript", "struct", "class", "enum", "protocol", "actor", "typealias", "associatedtype", "case", "macro",
]);

const ISOLATION_PATTERN = rx(
  String.raw`@MainActor(?!\w)|@preconcurrency(?!\w)|@Sendable(?!\w)|@isolated\(any\)|@concurrent(?!\w)` +
    String.raw`|nonisolated\(unsafe\)|nonisolated\(nonsending\)|nonisolated(?!\w)|sending(?!\w)`,
  "g",
);

/**
 * The isolation keywords and attributes among `fragments`.
 *
 * Spellings are joined before matching, because the writer splits `@MainActor` into `@` and `MainActor` and puts
 * `@isolated(any)` in a text fragment (`: @isolated(any) `). Type and identifier fragments are skipped, so a type named
 * `Sendable` never counts.
 */
export function isolationWords(fragments) {
  let text = "";
  let afterAtSign = false;
  for (const fragment of fragments) {
    const { spelling } = fragment;
    // A global actor inside a closure type is written as text `@` plus a type identifier (`: @`, `MainActor`).
    if (fragment.kind === "typeIdentifier" && text.endsWith("@")) {
      text += spelling;
      afterAtSign = false;
      continue;
    }
    if (!["attribute", "keyword", "text"].includes(fragment.kind)) continue;
    // A space separates fragments, except that a bare `@` attaches to the attribute name after it.
    text += afterAtSign ? spelling : ` ${spelling}`;
    afterAtSign = stripWhitespace(spelling) === "@";
  }
  return words(text.match(ISOLATION_PATTERN) ?? []);
}

/**
 * Isolation of one declaration: [its own, per parameter, its result].
 *
 * A function's own words are those before its name (`@MainActor nonisolated func`); a variable or typealias has no parameter
 * list, so its whole type counts as its own (`var action: @MainActor () -> Void`). Parameter and result words come from the
 * parameters' and return type's fragments, so a `sending` parameter or a `@Sendable` closure parameter type is compared where
 * it occurs.
 */
export function isolationOf(symbol) {
  const fragments = symbol.declarationFragments ?? [];
  const signature = symbol.functionSignature ?? null;
  let own;
  if (signature === null) own = isolationWords(fragments);
  else {
    const prefix = [];
    for (const fragment of fragments) {
      if (fragment.kind === "identifier" || (fragment.kind === "keyword" && DECLARATION_KEYWORDS.has(fragment.spelling))) break;
      prefix.push(fragment);
    }
    own = isolationWords(prefix);
  }
  const parameters = (signature?.parameters ?? []).map((parameter) => isolationWords(parameter.declarationFragments ?? []));
  const results = isolationWords(signature?.returns ?? []);
  return [own, parameters, results];
}

const isolationKey = (isolation) => JSON.stringify(isolation);

/**
 * Whether a synthesized member's source (`s:7SwiftUI11_VectorMathP...`) is declared on an underscored type, which the symbol
 * graph leaves out.
 */
export function declaredInHiddenType(precise) {
  let match = /^s:(\d+)/u.exec(precise);
  if (match === null) return false;
  const rest = precise.slice(match[0].length + Number.parseInt(match[1], 10));
  match = /^(\d+)/u.exec(rest);
  return match !== null && rest.slice(match[0].length).startsWith("_");
}

const BASELINE_CATEGORIES = ["extra", "foreign", "signature", "isolation", "default", "disfavored"];
// Categories that fail the gate when a divergence is not in the baseline. `isolation`, `default` and `disfavored` are gated
// from the start: their baseline lists are empty, so every mismatch is fixed in code or explicitly recorded.
const GATED_CATEGORIES = ["extra", "foreign", "isolation", "default", "disfavored"];

/**
 * Removes from `known` the entries that no longer diverge; never adds one.
 *
 * Returns the pruned baseline (same categories and comment as `known`) and, per category, the current divergences the
 * baseline does not list. Those are not added: they must be fixed, or recorded by an explicit rewrite after review.
 */
export function pruneBaseline(known, current) {
  const pruned = {};
  for (const [key, value] of Object.entries(known)) if (!BASELINE_CATEGORIES.includes(key)) pruned[key] = value;
  const unlisted = {};
  for (const name of BASELINE_CATEGORIES) {
    if (!Object.hasOwn(known, name)) continue;
    const live = new Set(current[name] ?? []);
    pruned[name] = known[name].filter((key) => live.has(key));
    const listed = new Set(known[name]);
    unlisted[name] = sortedStrings([...live].filter((key) => !listed.has(key)));
  }
  return [pruned, unlisted];
}

/** Every graph of `modules`; only the module's own graph of `frameworks`. */
export function graphFiles(directory, modules, frameworks = []) {
  const files = [];
  const names = readdirSync(directory).filter((name) => name.endsWith(".symbols.json")).sort(compareStrings);
  for (const name of names) {
    const stem = name.slice(0, -".symbols.json".length);
    const module = stem.split("@")[0];
    if (
      modules.includes(module) || frameworks.includes(stem) || (frameworks.length > 0 && FRAMEWORK_OVERLAYS.includes(module)) ||
      (frameworks.length > 0 && FRAMEWORK_FOUNDATION_OVERLAYS.includes(stem))
    ) files.push(join(directory, name));
  }
  return files;
}

/**
 * Names of protocols whose declaration is `@MainActor` or refines one that is.
 *
 * SwiftUIWeb's symbol graphs come from source, where the compiler records the isolation a protocol inherits from a refined
 * protocol (`protocol DynamicViewContent: View` prints `@MainActor`). Apple's graphs come from binary modules, which print
 * only what was written. Apple's effective isolation for those protocols is therefore rebuilt from the refinement chain
 * before comparing.
 */
export function inferredMainActorProtocols(graphs) {
  const own = new Map();
  const refines = new Map();
  for (const graph of graphs) {
    const byId = new Map();
    for (const symbol of graph.symbols) {
      const parts = symbol.pathComponents;
      if (symbol.kind.identifier === "swift.protocol" && parts.length === 1) {
        byId.set(symbol.identifier.precise, parts[0]);
        own.set(parts[0], isolationOf(symbol)[0]);
      }
    }
    for (const relation of graph.relationships ?? []) {
      if (relation.kind !== "conformsTo" || !byId.has(relation.source)) continue;
      const target = byId.get(relation.target) || lastOf((relation.targetFallback ?? "").split("."));
      if (target) {
        if (!refines.has(byId.get(relation.source))) refines.set(byId.get(relation.source), new Set());
        refines.get(byId.get(relation.source)).add(target);
      }
    }
  }
  const result = new Set([...own].filter(([, ownWords]) => ownWords.includes("@MainActor")).map(([name]) => name));
  let changed = true;
  while (changed) {
    changed = false;
    for (const [name, parents] of refines) {
      const explicitNonisolated = [...parents].some((parent) => (own.get(parent) ?? []).includes("nonisolated"));
      if (!result.has(name) && !(own.get(name) ?? []).includes("nonisolated") && !explicitNonisolated && [...parents].some((parent) => result.has(parent))) {
        result.add(name);
        changed = true;
      }
    }
  }
  return result;
}

// Members whose isolation is their own: nested types and enum cases are not isolated by their owner.
const MEMBER_KINDS_INHERITING_ISOLATION = new Set([
  "swift.property", "swift.var", "swift.method", "swift.func", "swift.init", "swift.subscript", "swift.type.method", "swift.type.property",
]);

/**
 * Names of top-level classes, structs and enums that are written `@MainActor`.
 *
 * Apple's binary graphs print only what each member writes, so a member of a `@MainActor` class that prints no isolation
 * inherits `@MainActor` (AVPlayerItem.asset). SwiftUIWeb's source graphs print the inherited attribute themselves. A member
 * that writes `nonisolated` keeps it.
 */
export function inferredMainActorTypes(graphs) {
  const names = new Set();
  for (const graph of graphs) {
    for (const symbol of graph.symbols) {
      const parts = symbol.pathComponents;
      if (parts.length === 1 && ["swift.class", "swift.struct", "swift.enum"].includes(symbol.kind.identifier) && isolationOf(symbol)[0].includes("@MainActor")) names.add(parts[0]);
    }
  }
  return names;
}

/**
 * One declaration's overloads, its files, its isolation per (title, parameter types) overload, its default-argument flags,
 * and whether each overload is `@_disfavoredOverload` (the set of values its interfaces declare).
 */
export function newEntry() {
  return { overloads: new Map(), files: new Set(), isolation: new Map(), defaults: new Map(), disfavored: new Map() };
}

const overloadKey = (title, declaration) => dk([title, declaration]);

function addIsolation(entry, title, declaration, isolation) {
  const key = overloadKey(title, declaration);
  if (!entry.isolation.has(key)) entry.isolation.set(key, new Map());
  entry.isolation.get(key).set(isolationKey(isolation), isolation);
}

const overloadDeclarations = (entry, title) => {
  if (!entry.overloads.has(title)) entry.overloads.set(title, new Map());
  return entry.overloads.get(title);
};

/**
 * Declarations keyed by kind and path without argument labels.
 *
 * Every entry keeps all overloads as (full title, parameters) pairs, because labels are compared later with default-argument
 * tolerance. `options.superclasses`, when given, collects each class's superclass name. `options.renames` maps a top-level
 * type to the name it is compared and reported under. `options.moduleSources`, when given, keeps only declarations written
 * under `Sources/<module>/`: a module's graph also lists declarations of the modules it re-exports.
 *
 * `options.hiddenProtocolMembers` keeps the synthesized copies of members a type inherits from an underscored protocol's
 * extension (SwiftUI's `Angle` gets its prefix `-` from `_VectorMath`): the protocol itself is skipped, so the copies are the
 * only record that the type really has the member.
 */
export function load(files, options = {}) {
  const {
    superclasses = null, renames = {}, hiddenProtocolMembers = false, inferProtocolIsolation = false, moduleSources = null,
    ownModules = null, excludedModules = [],
  } = options;
  const table = new Map();
  const graphs = files.map((path) => (typeof path === "string" ? JSON.parse(readText(path)) : path));
  const inferred = inferProtocolIsolation ? inferredMainActorProtocols(graphs) : new Set();
  const mainTypes = inferProtocolIsolation ? inferredMainActorTypes(graphs) : new Set();
  for (const name of mainTypes) inferred.add(name);
  for (const graph of graphs) {
    const requirementOwner = new Map();
    if (inferred.size > 0) {
      const namesById = new Map(graph.symbols.map((symbol) => [symbol.identifier.precise, symbol.pathComponents]));
      for (const relation of graph.relationships ?? []) {
        if (relation.kind === "requirementOf") {
          const owner = namesById.get(relation.target);
          if (owner && owner.length === 1) requirementOwner.set(relation.source, owner[0]);
        }
      }
    }
    if (superclasses !== null) {
      const names = new Map(graph.symbols.map((symbol) => [symbol.identifier.precise, symbol.pathComponents]));
      for (const relation of graph.relationships ?? []) {
        if (relation.kind !== "inheritsFrom" || (names.get(relation.source) ?? []).length !== 1) continue;
        let target = names.get(relation.target);
        target = target && target.length > 0 ? target.join(".") : lastOf((relation.targetFallback ?? "").split("."));
        if (target) superclasses[names.get(relation.source)[0]] = target;
      }
    }
    for (const symbol of graph.symbols) {
      const kind = symbol.kind.identifier;
      const family = KIND_FAMILY[kind];
      let parts = symbol.pathComponents;
      if (parts.length > 0 && Object.hasOwn(renames, parts[0])) parts = [renames[parts[0]], ...parts.slice(1)];
      if (family === undefined || parts.some((part) => part.startsWith("_"))) continue;
      const uri = symbol.location?.uri ?? "";
      if (moduleSources !== null && !uri.includes(`/Sources/${moduleSources}/`)) continue;
      // A symbol's USR names the module that declares it (`s:14SwiftUIWebCore...`, `s:SS14SwiftUIWebCoreE...` for an
      // extension of `String`); a re-exported module's symbols carry their own (`s:8Dispatch...`).
      const declaring = (name) => symbol.identifier.precise.includes(`${name.length}${name}`);
      if (ownModules !== null && !ownModules.some(declaring)) continue;
      if (excludedModules.some(declaring)) continue;
      // Members a type merely inherits from a protocol extension appear as synthesized copies on every conforming type; the
      // protocol's own declaration already represents them, unless that protocol is hidden.
      const precise = symbol.identifier.precise;
      if (precise.includes("::SYNTHESIZED::") && !(hiddenProtocolMembers && declaredInHiddenType(precise))) continue;
      const base = parts.map((part) => part.split("(")[0]);
      const key = `${family} ${base.join(".")}`;
      if (!table.has(key)) table.set(key, newEntry());
      const entry = table.get(key);
      // Overloads that share argument labels differ only in their types, so every one of them is kept under the same title.
      const declaration = parseDeclaration(symbol);
      const title = lastOf(parts);
      addTo(overloadDeclarations(entry, title), declaration);
      let isolation = isolationOf(symbol);
      if (inferred.size > 0) {
        // A protocol that refines `View` (or another main-actor protocol) is main-actor isolated, and so are its requirements
        // unless they say otherwise.
        let owner;
        if (parts.length === 1 && kind === "swift.protocol") owner = parts[0];
        else if (parts.length === 2 && mainTypes.has(parts[0]) && MEMBER_KINDS_INHERITING_ISOLATION.has(kind)) owner = parts[0];
        else owner = requirementOwner.get(symbol.identifier.precise);
        if (owner !== undefined && inferred.has(owner) && kind !== "swift.associatedtype" && !isolation[0].some((word) => ["@MainActor", "nonisolated", "nonisolated(unsafe)"].includes(word))) {
          isolation = [unionWords(isolation[0], ["@MainActor"]), isolation[1], isolation[2]];
        }
      }
      addIsolation(entry, title, declaration, isolation);
      if (uri) entry.files.add(lastOf(uri.split("/Sources/")));
    }
  }
  return table;
}

// ---- Default arguments, read from textual module interfaces ---------------------------------------------------------------
// Symbol graphs record no default values. The `.swiftinterface` files of Apple's SDK and of SwiftUIWeb's own modules do. The
// scanner below reads each function, initializer and subscript of a type or file scope: its owner path, its title
// (`init(_:value:)`), its parameters as (label, normalized types) pairs (the same shape `parseDeclaration` gives symbol-graph
// declarations) and whether each parameter has a default. A declaration that cannot be read exactly is skipped, never guessed.

// Module names an interface spells before a declaration or type (`SwiftUICore.Tab`, `SwiftUIWebCore::Tab`).
const INTERFACE_MODULES = new Set([
  "Swift", "SwiftUI", "SwiftUICore", "_QuickLook_SwiftUI", "Foundation", "CoreFoundation", "CoreGraphics", "Combine", "StoreKit",
  "DeveloperToolsSupport", "CoreTransferable", "UniformTypeIdentifiers", "Symbols", "AVFoundation", "AVKit", "AVFAudio", "CoreMedia",
  "UIKit", "AppKit", "Observation", "_Concurrency", "Dispatch", "ObjectiveC", "Darwin", "_StringProcessing", "CoreVideo", "CoreImage",
  "CoreText", "QuickLook", "SwiftUIWeb", "SwiftUIWebCore", "SwiftUIWebFeatures", "SwiftUIWebAVFoundation", "SwiftUIWebAVKit", "WebFoundation",
  "SwiftUIWebInternationalization", "SwiftUIWebNetworking", "SwiftUIWebTransferable", "SwiftUIWebBrowserIO",
]);
const INTERFACE_TYPE_KEYWORDS = new Set(["some", "any", "inout", "sending", "consuming", "borrowing", "escaping", "async", "throws", "rethrows", "where"]);
const INTERFACE_TOKEN_SOURCE = String.raw`"(?:[^"\\\n]|\\.)*"|//[^\n]*|/\*.*?\*/|[{};()\[\]]|\b(?:func|init|subscript)\b`;
const INTERFACE_HEADER_SOURCE = String.raw`\b(struct|class|enum|protocol|actor|extension|func|init|subscript|var|let|case|typealias|associatedtype|deinit|operator|precedencegroup|macro)\b`;
const INTERFACE_TYPE_HEADERS = new Set(["struct", "class", "enum", "protocol", "actor", "extension"]);

const stripInterfaceComments = (text) => text.replace(/\/\*.*?\*\//gsu, " ").replace(/\/\/[^\n]*/gu, "");

/** Index of the parenthesis closing the one at `openIndex`, or -1. */
function matchingParen(text, openIndex) {
  let depth = 0;
  let index = openIndex;
  while (index < text.length) {
    const character = text[index];
    if (character === '"') {
      index = text.indexOf('"', index + 1);
      if (index < 0) return -1;
    } else if (character === "(") depth += 1;
    else if (character === ")") {
      depth -= 1;
      if (depth === 0) return index;
    }
    index += 1;
  }
  return -1;
}

/** Splits `text` at `separator` where no bracket is open (`->` is not a bracket). */
function splitTopLevel(text, separator) {
  const parts = [];
  let depth = 0;
  let current = [];
  let index = 0;
  while (index < text.length) {
    if (text.startsWith("->", index)) {
      current.push("->");
      index += 2;
      continue;
    }
    const character = text[index];
    if ("([{<".includes(character)) depth += 1;
    else if (")]}>".includes(character)) depth -= 1;
    if (character === separator && depth === 0) {
      parts.push(current.join(""));
      current = [];
    } else current.push(character);
    index += 1;
  }
  parts.push(current.join(""));
  return parts;
}

/** Index of the first `target` character outside brackets, or -1; `=` ignores `==`, `<=`, `>=`, `!=`, `=>`. */
function topLevelIndex(text, target) {
  let depth = 0;
  let index = 0;
  while (index < text.length) {
    if (text.startsWith("->", index)) {
      index += 2;
      continue;
    }
    const character = text[index];
    if ("([{<".includes(character)) depth += 1;
    else if (")]}>".includes(character)) depth -= 1;
    else if (character === target && depth === 0) {
      if (target !== "=") return index;
      const before = index > 0 ? text[index - 1] : " ";
      const after = index + 1 < text.length ? text[index + 1] : " ";
      if (!"=!<>".includes(before) && !"=>".includes(after)) return index;
    }
    index += 1;
  }
  return -1;
}

const CONTENT_BUILDER = rx(String.raw`@[\w.:]*ContentBuilder(?:<(?:[^<>]|<[^<>]*>)*>)?`, "g");
const MAIN_ACTOR_ATTRIBUTE = rx(String.raw`@((?:[\w]+[.:]+)*MainActor)\b`, "g");
const ANY_ATTRIBUTE = rx(String.raw`@[\w.:]+(?:\([^()]*\))?`, "g");
const OPAQUE_ARGUMENTS = rx(String.raw`\b(some)\s+([\w.:]+)\s*<(?:[^<>]|<[^<>]*>)*>`, "g");
const IDENTIFIER = rx(String.raw`[A-Za-z_]\w*`, "g");
const ELEMENT_LABEL = rx(String.raw`^\s*:(?!:)`);
const TRAILING_SPACE = new RegExp(`${SPACE_CLASS}+$`, "u");

/**
 * The type names a parameter's type spells, in order, in the shape `typeIdentifiers` gives.
 *
 * Attributes spell no type except a global actor (`@MainActor () -> Void` keeps `MainActor`); a `...ContentBuilder` attribute
 * takes its arguments with it, while other attributes keep their generic arguments. An opaque type's protocol drops its
 * arguments (`some Sequence<Phase>` is `Sequence`), module qualifiers (`SwiftUICore.`, `SwiftUIWebCore::`) are dropped, generic
 * parameters become `_G` and numeric types `Number`.
 */
export function interfaceTypeNames(text, generics) {
  text = text.replace(CONTENT_BUILDER, " ");
  text = text.replace(MAIN_ACTOR_ATTRIBUTE, " $1 ");
  text = text.replace(ANY_ATTRIBUTE, " ");
  text = text.replace(OPAQUE_ARGUMENTS, "$1 $2");
  const names = [];
  for (const match of text.matchAll(IDENTIFIER)) {
    const name = match[0];
    const end = match.index + name.length;
    const following = text.slice(end, end + 2);
    if (following === "::" || (following.slice(0, 1) === "." && INTERFACE_MODULES.has(name))) continue;
    if (INTERFACE_TYPE_KEYWORDS.has(name) || name === "_") continue;
    // A metatype suffix (`Value.Type`) and an element label (`(x: CGFloat)`) are not type names.
    if (((name === "Type" || name === "Protocol") && text.slice(0, match.index).replace(TRAILING_SPACE, "").endsWith(".")) || ELEMENT_LABEL.test(text.slice(end))) continue;
    if (generics.has(name)) names.push("_G");
    else if (NUMBER_TYPES.has(name)) names.push("Number");
    else names.push(name);
  }
  return names;
}

// An attribute's generic arguments may nest once (`@TabContentBuilder<Swift::Optional<V>>`, how an interface spells `V?`).
const LEADING_ATTRIBUTES = rx(String.raw`^(?:@[\w.:]+(?:<(?:[^<>]|<[^<>]*>)*>)?(?:\([^()]*\))?\s*)+`);
const LEADING_OWNERSHIP = rx(String.raw`^(?:inout|sending|consuming|borrowing|__owned|__shared)\s+`);
const LABEL_WORD = rx(String.raw`^[A-Za-z_]\w*$`);
const SPACE_RUN = new RegExp(`${SPACE_CLASS}+`, "u");

/** [label, normalized types, has default] per parameter of one parameter list, or null when unreadable. */
export function interfaceParameters(text, generics) {
  const result = [];
  for (let piece of splitTopLevel(text, ",")) {
    piece = stripWhitespace(piece);
    if (!piece) continue;
    piece = piece.replace(LEADING_ATTRIBUTES, "");
    piece = piece.replace(LEADING_OWNERSHIP, "");
    const colon = topLevelIndex(piece, ":");
    if (colon < 0) return null;
    const labels = piece.slice(0, colon).split(SPACE_RUN).filter(Boolean);
    if (!(labels.length === 1 || labels.length === 2) || !labels.every((word) => LABEL_WORD.test(word))) return null;
    const rest = piece.slice(colon + 1);
    const equals = topLevelIndex(rest, "=");
    const typeText = equals < 0 ? rest : rest.slice(0, equals);
    result.push([labels[0], interfaceTypeNames(typeText, generics), equals >= 0]);
  }
  return result;
}

const SCOPE_NAME = rx(String.raw`^\s+((?:[A-Za-z_]\w*(?:\.|::))*[A-Za-z_]\w*)`);

/** [kind, owner name, generic parameters] of the scope a `{` opens. Kind is `type`, `body` or `other`. */
function interfaceScope(header, ownerGenerics) {
  const keywords = [...header.matchAll(rx(INTERFACE_HEADER_SOURCE, "g"))];
  if (keywords.length === 0) return ["other", "", new Set()];
  const last = lastOf(keywords);
  if (!INTERFACE_TYPE_HEADERS.has(last[1])) return ["body", "", new Set()];
  const nameMatch = SCOPE_NAME.exec(header.slice(last.index + last[0].length));
  if (nameMatch === null) return ["other", "", new Set()];
  let parts = nameMatch[1].split(/\.|::/u);
  while (parts.length > 1 && INTERFACE_MODULES.has(parts[0])) parts = parts.slice(1);
  return ["type", parts.join("."), ownerGenerics.get(lastOf(parts)) ?? new Set()];
}

/**
 * [owner path, title, [[label, types], ...], default flags] of every member and top-level function.
 *
 * Declarations inside function, accessor and initializer bodies are not members, so the scanner tracks the scopes its braces
 * open. Parameter lists are read with their brackets balanced, so a default value that contains braces
 * (`= { _ in .default }`) does not open a scope.
 */
export function interfaceDeclarations(text, renames) {
  text = stripInterfaceComments(text);
  const ownerGenerics = new Map();
  for (const match of text.matchAll(rx(String.raw`\b(?:struct|class|enum|actor)\s+(\w+)\s*<([^{}()]*?)>`, "g"))) {
    const merged = new Set(ownerGenerics.get(match[1]) ?? []);
    for (const word of match[2].matchAll(IDENTIFIER)) merged.add(word[0]);
    ownerGenerics.set(match[1], merged);
  }
  const scopes = [];
  const declarations = [];
  let nest = 0;
  let headerStart = 0;
  for (const token of text.matchAll(rx(INTERFACE_TOKEN_SOURCE, "gs"))) {
    const spelling = token[0];
    const start = token.index;
    const end = start + spelling.length;
    if (spelling[0] === '"' || spelling[0] === "/") continue;
    if (spelling === "(" || spelling === "[") {
      nest += 1;
      continue;
    }
    if (spelling === ")" || spelling === "]") {
      nest -= 1;
      continue;
    }
    if (nest) continue;
    if (spelling === ";") headerStart = end;
    else if (spelling === "{") {
      scopes.push(interfaceScope(text.slice(headerStart, start), ownerGenerics));
      headerStart = end;
    } else if (spelling === "}") {
      if (scopes.length > 0) scopes.pop();
      headerStart = end;
    } else if (scopes.length === 0 || lastOf(scopes)[0] === "type") {
      const declaration = interfaceMember(text, end, spelling, scopes, renames);
      if (declaration !== null) declarations.push(declaration);
    }
  }
  return declarations;
}

const FUNC_NAME_STICKY = rx(String.raw`\s+([A-Za-z_]\w*)`, "y");
const GENERIC_CLAUSE = rx(String.raw`\s*<([^<>(){}]*)>`, "y");
const OPEN_PARENTHESIS = rx(String.raw`\s*\(`, "y");

/** The declaration a `func`, `init` or `subscript` keyword ending at `end` begins, or null when it is not one. */
function interfaceMember(text, end, keyword, scopes, renames) {
  let name;
  let position;
  if (keyword === "func") {
    FUNC_NAME_STICKY.lastIndex = end;
    const nameMatch = FUNC_NAME_STICKY.exec(text);
    if (nameMatch === null) return null;
    name = nameMatch[1];
    position = FUNC_NAME_STICKY.lastIndex;
  } else if (keyword === "init") {
    if (text.slice(end, end + 1) === "?" || text.slice(end, end + 1) === "!") return null;
    name = "init";
    position = end;
  } else return null;
  const generics = new Set();
  GENERIC_CLAUSE.lastIndex = position;
  const clause = GENERIC_CLAUSE.exec(text);
  if (clause !== null) {
    for (const word of clause[1].matchAll(IDENTIFIER)) generics.add(word[0]);
    position = GENERIC_CLAUSE.lastIndex;
  }
  OPEN_PARENTHESIS.lastIndex = position;
  const parenthesis = OPEN_PARENTHESIS.exec(text);
  if (parenthesis === null) return null;
  const open = OPEN_PARENTHESIS.lastIndex;
  const close = matchingParen(text, open - 1);
  if (close < 0) return null;
  const typeGenerics = new Set();
  for (const [kind, , ownerGeneric] of scopes) if (kind === "type") for (const word of ownerGeneric) typeGenerics.add(word);
  const parameters = interfaceParameters(text.slice(open, close), new Set([...generics, ...typeGenerics]));
  if (parameters === null) return null;
  const title = `${name}(${parameters.map(([label]) => `${label}:`).join("")})`;
  let owner = scopes.filter(([kind]) => kind === "type").map(([, ownerName]) => ownerName).join(".");
  if (owner) {
    const dot = owner.indexOf(".");
    const first = dot < 0 ? owner : owner.slice(0, dot);
    const rest = dot < 0 ? "" : owner.slice(dot + 1);
    owner = (Object.hasOwn(renames, first) ? renames[first] : first) + (rest ? `.${rest}` : "");
  }
  const disfavored = DISFAVORED.test(leadingAttributes(text, end - keyword.length));
  return [owner, title, parameters.map(([label, types]) => [label, types]), parameters.map(([, , flag]) => flag), disfavored];
}

const DISFAVORED = rx(String.raw`@_disfavoredOverload\b`);
const DECLARATION_WORD = rx(String.raw`\b(?:func|init|subscript|var|let|struct|class|enum|actor|extension|protocol|typealias|case|associatedtype|macro)\b`);

/**
 * The attributes written before the keyword at `start`: the rest of its line, and the lines above it that hold attributes
 * only (`@available(...)` on a line of its own).
 */
export function leadingAttributes(text, start) {
  let lineStart = text.lastIndexOf("\n", start - 1) + 1;
  let attributes = text.slice(lineStart, start);
  while (lineStart > 0) {
    const previousStart = text.lastIndexOf("\n", lineStart - 2) + 1;
    const line = text.slice(previousStart, lineStart - 1);
    const bare = line.replace(/"(?:[^"\\\n]|\\.)*"/gu, '""').trim();
    if (!bare.startsWith("@") || DECLARATION_WORD.test(bare)) break;
    attributes = `${line}\n${attributes}`;
    lineStart = previousStart;
  }
  return attributes;
}

/**
 * Default flags per (owner, title, parameters) read from `paths`; every flag tuple seen is kept. With `disfavored`, also
 * fills it with the `@_disfavoredOverload` values seen per (owner, title, parameters).
 */
export function interfaceDefaults(paths, renames, disfavored = null) {
  const index = new Map();
  for (const path of paths) {
    for (const [owner, title, parameters, flags, isDisfavored] of interfaceDeclarations(readText(path), renames)) {
      const key = dk([owner, title, parameters]);
      if (!index.has(key)) index.set(key, new Map());
      index.get(key).set(dk(flags), flags);
      if (disfavored !== null) {
        if (!disfavored.has(key)) disfavored.set(key, new Set());
        disfavored.get(key).add(isDisfavored);
      }
    }
  }
  return index;
}

/** Records whether each overload is `@_disfavoredOverload`, as the interfaces of `index` (from `interfaceDefaults`) declare. */
export function attachDisfavored(table, index) {
  for (const [key, entry] of table) {
    const owner = rsplitSpace(key)[1].split(".").slice(0, -1).join(".");
    for (const [title, declarations] of entry.overloads) {
      for (const declaration of declarations.values()) {
        const values = index.get(dk([owner, title, declaration]));
        if (values === undefined) continue;
        const slot = overloadKey(title, declaration);
        if (!entry.disfavored.has(slot)) entry.disfavored.set(slot, new Set());
        for (const value of values) entry.disfavored.get(slot).add(value);
      }
    }
  }
}

/** Whether the overload `key` is disfavored, or null when its interfaces do not say so unambiguously. */
function knownDisfavored(disfavored, key) {
  const values = disfavored.get(key);
  return values && values.size === 1 ? [...values][0] : null;
}

/**
 * Why `declaration`'s `@_disfavoredOverload` differs from Apple's, or null when it matches or cannot be compared.
 *
 * The Apple overload of the same shape decides; without one, the declaration passes when some Apple overload it aligns with
 * agrees.
 */
export function disfavoredDetail(declaration, title, entry, counterpart) {
  const own = knownDisfavored(entry.disfavored, overloadKey(title, declaration));
  if (own === null) return null;
  const shape = `(${declaration.map(([label, types]) => `${label}: ${types.join(" ")}`).join(", ")})`;
  const describe = (apple) => (apple ? `Apple disfavors ${shape} (@_disfavoredOverload); SwiftUIWeb does not` : `SwiftUIWeb disfavors ${shape}; Apple does not`);
  const twin = counterpart.overloads.get(title)?.get(dk(declaration));
  if (twin !== undefined) {
    const apple = knownDisfavored(counterpart.disfavored, overloadKey(title, twin));
    if (apple !== null) return apple === own ? null : describe(apple);
  }
  let disagreeing = null;
  for (const [referenceTitle, references] of counterpart.overloads) {
    for (const reference of references.values()) {
      if (alignment(declaration, reference) === null) continue;
      const apple = knownDisfavored(counterpart.disfavored, overloadKey(referenceTitle, reference));
      if (apple === null) continue;
      if (apple === own) return null;
      disagreeing = apple;
    }
  }
  return disagreeing === null ? null : describe(disagreeing);
}

/**
 * Records each overload's default flags when its interface declaration is unambiguous.
 *
 * A declaration seen with two different flag tuples (a `#if` alternative, a platform variant) is left unrecorded, so it is
 * reported as unchecked rather than compared against a guess.
 */
export function attachDefaults(table, index) {
  for (const [key, entry] of table) {
    const path = rsplitSpace(key)[1];
    const owner = path.split(".").slice(0, -1).join(".");
    for (const [title, declarations] of entry.overloads) {
      for (const declaration of declarations.values()) {
        const flags = index.get(dk([owner, title, declaration]));
        if (flags !== undefined && flags.size === 1) {
          const slot = overloadKey(title, declaration);
          if (!entry.defaults.has(slot)) entry.defaults.set(slot, new Map());
          for (const [flagKey, value] of flags) entry.defaults.get(slot).set(flagKey, value);
        }
      }
    }
  }
}

/** The one flag tuple recorded for `key`, or null when unknown. */
function knownFlags(defaults, key) {
  const values = defaults.get(key);
  if (!values || values.size !== 1) return null;
  return [...values.values()][0];
}

/** Why SwiftUIWeb's defaults for `declaration` differ from Apple's `reference`, aligned by `mapping`. */
function defaultProblems(declaration, flags, reference, referenceFlags, mapping, appleCalls, webCalls) {
  const problems = [];
  declaration.forEach(([label], index) => {
    const target = mapping[index];
    if (flags[index] && !referenceFlags[target]) {
      if (!appleCalls.has(dk([...declaration.slice(0, index), ...declaration.slice(index + 1)]))) {
        problems.push(`'${label}' has a default that Apple's declaration does not have`);
      }
    } else if (referenceFlags[target] && !flags[index]) {
      if (!webCalls.has(dk([...reference.slice(0, target), ...reference.slice(target + 1)]))) {
        problems.push(`'${label}' is required where Apple's declaration defaults it`);
      }
    }
  });
  const mapped = new Set(mapping);
  reference.forEach(([label], target) => {
    if (!mapped.has(target) && !referenceFlags[target]) problems.push(`Apple requires '${label}' and this declaration omits it`);
  });
  return problems;
}

/**
 * Stand-in types that application code reaches through an Apple name.
 *
 * `public typealias UserDefaults = _WebUserDefaults` makes the stand-in's members the Apple type's members for callers, so
 * they are matched against that Apple type (the stand-in's own name is still a declaration of its own). An underscored
 * stand-in such as `_WebUserDefaults` is public only so that a browser-only `public typealias UserDefaults = _WebUserDefaults`
 * can name it: callers know it solely by the Apple name, so it is loaded under that name instead of being skipped like other
 * underscored declarations.
 */
export function standIns(apple) {
  const pattern = rx(String.raw`^public typealias (\w+) = (\w+)\s*$`, "gm");
  const names = {};
  for (const source of filesWithSuffix(join(ROOT, "Sources"), ".swift")) {
    for (const match of readText(source).matchAll(pattern)) {
      const [, appleName, standIn] = match;
      if (apple.has(`type ${appleName}`) && !apple.has(`type ${standIn}`)) names[standIn] = appleName;
    }
  }
  return names;
}

/** Adds `table`'s declarations to `into`, keeping every overload of both. */
export function merge(into, table) {
  for (const [key, entry] of table) {
    if (!into.has(key)) into.set(key, newEntry());
    const target = into.get(key);
    for (const [title, declarations] of entry.overloads) {
      const slot = overloadDeclarations(target, title);
      for (const [declarationKey, declaration] of declarations) slot.set(declarationKey, declaration);
    }
    for (const [overload, isolations] of entry.isolation) {
      if (!target.isolation.has(overload)) target.isolation.set(overload, new Map());
      for (const [isolationText, isolation] of isolations) target.isolation.get(overload).set(isolationText, isolation);
    }
    for (const [overload, flags] of entry.defaults) {
      if (!target.defaults.has(overload)) target.defaults.set(overload, new Map());
      for (const [flagText, value] of flags) target.defaults.get(overload).set(flagText, value);
    }
    for (const [overload, values] of entry.disfavored) {
      if (!target.disfavored.has(overload)) target.disfavored.set(overload, new Set());
      for (const value of values) target.disfavored.get(overload).add(value);
    }
    for (const file of entry.files) target.files.add(file);
  }
}

/**
 * The SDK interface of every Apple module that `directory`'s graphs compare, for that platform.
 *
 * A module without an interface in the SDK (`ObjectiveC`, `Observation`) contributes no defaults, so its declarations are
 * reported as unchecked.
 */
function appleInterfaceFiles(directory) {
  const platform = basename(directory);
  if (!Object.hasOwn(APPLE_INTERFACES, platform)) return [];
  const [sdkName, triples] = APPLE_INTERFACES[platform];
  const frameworks = join(sdkPath(sdkName), "System", "Library", "Frameworks");
  const paths = [];
  for (const module of [...APPLE_MODULES, ...FRAMEWORK_MODULES, ...(PLATFORM_FRAMEWORKS[platform] ?? [])]) {
    for (const triple of triples) {
      const candidate = join(frameworks, `${module}.framework`, "Modules", `${module}.swiftmodule`, `${triple}.swiftinterface`);
      if (existsSync(candidate)) {
        paths.push(candidate);
        break;
      }
    }
  }
  return paths;
}

/**
 * SwiftUI's declarations, those of every compared Apple framework, and superclasses.
 *
 * Each is the union over the platform directories (iOS and macOS): only a declaration absent from every platform is a
 * divergence. Each platform's overloads carry the default arguments its SDK interfaces declare.
 */
function appleTables(directories) {
  const swiftui = new Map();
  const apple = new Map();
  const superclasses = {};
  for (const directory of directories) {
    const platform = basename(directory);
    const own = load(graphFiles(directory, APPLE_MODULES), { hiddenProtocolMembers: true, inferProtocolIsolation: true });
    const frameworks = load(graphFiles(directory, [], [...FRAMEWORK_MODULES, ...(PLATFORM_FRAMEWORKS[platform] ?? [])]), {
      superclasses, hiddenProtocolMembers: true, inferProtocolIsolation: true,
    });
    if (own.size === 0 || frameworks.size === 0) fail(`missing Apple graphs in ${directory}; run with --generate`);
    const disfavored = new Map();
    const index = interfaceDefaults(appleInterfaceFiles(directory), {}, disfavored);
    attachDefaults(own, index);
    attachDefaults(frameworks, index);
    attachDisfavored(own, disfavored);
    attachDisfavored(frameworks, disfavored);
    merge(swiftui, own);
    merge(apple, frameworks);
    merge(apple, own);
  }
  return [swiftui, apple, superclasses];
}

// Nested Apple typealiases whose members are declared on the aliased type: `URLRequest.CachePolicy` is
// `typealias CachePolicy = NSURLRequest.CachePolicy` in Foundation, so its cases live under the target.
const NESTED_TYPEALIASES = {
  "URLRequest.CachePolicy": "NSURLRequest.CachePolicy",
  "Notification.Name": "NSNotification.Name",
  "Data.WritingOptions": "NSData.WritingOptions",
  "Data.ReadingOptions": "NSData.ReadingOptions",
  "String.CompareOptions": "NSString.CompareOptions",
  "Locale.LanguageDirection": "NSLocale.LanguageDirection",
};
// Literal initializers Apple's graphs do not record, because the conformance is not in them: probed with
// `xcrun --sdk macosx swiftc -typecheck` (`let d: NSMutableDictionary = [:]` compiles on macOS and iOS). Only these exact
// initializers are accepted without an Apple declaration; nothing else is exempted.
const APPLE_LITERAL_INITIALIZERS = { NSMutableDictionary: new Set(["init(dictionaryLiteral:)"]) };

/**
 * The Apple declaration for `key`.
 *
 * Looks through a class's superclasses (`NumberFormatter()` is NSObject's `init()`), through the Apple type a stand-in is
 * exposed as, and through the nested typealiases listed in `NESTED_TYPEALIASES`.
 */
export function counterpartOf(key, apple, superclasses, aliases) {
  if (apple.has(key)) return apple.get(key);
  const [family, path] = rsplitSpace(key); // "static var X.y" has a two-word family
  for (const [nested, target] of Object.entries(NESTED_TYPEALIASES)) {
    if (path.startsWith(`${nested}.`)) {
      const candidate = `${family} ${target}.${path.slice(nested.length + 1)}`;
      if (apple.has(candidate)) return apple.get(candidate);
    }
  }
  const dot = path.indexOf(".");
  let owner = dot < 0 ? path : path.slice(0, dot);
  const member = dot < 0 ? "" : path.slice(dot + 1);
  if (member && Object.hasOwn(aliases, owner)) {
    owner = aliases[owner];
    if (apple.has(`${family} ${owner}.${member}`)) return apple.get(`${family} ${owner}.${member}`);
  }
  const seen = new Set();
  while (member && Object.hasOwn(superclasses, owner) && !seen.has(owner)) {
    seen.add(owner);
    owner = superclasses[owner];
    if (apple.has(`${family} ${owner}.${member}`)) return apple.get(`${family} ${owner}.${member}`);
  }
  return null;
}

export function describeIsolation([own, parameters, results]) {
  const parts = [own.join(" ") || "-"];
  parameters.forEach((parameterWords, index) => {
    if (parameterWords.length > 0) parts.push(`param${index}: ${parameterWords.join(" ")}`);
  });
  if (results.length > 0) parts.push(`result: ${results.join(" ")}`);
  return parts.join("; ");
}

/**
 * Why `declaration`'s isolation differs from Apple's, or null when it matches or has no Apple counterpart.
 *
 * Apple's overloads are those `declaration` maps onto exactly (same labels and types, in order, with defaulted parameters
 * skipped). The declaration passes when one of them has the same isolation, so a declaration that matches either platform's
 * graph is accepted.
 */
export function isolationDetail(webuiIsolations, counterpart, declaration) {
  if (!webuiIsolations || webuiIsolations.size === 0) return null;
  const appleCandidates = [];
  for (const [title, declarations] of counterpart.overloads) {
    for (const reference of declarations.values()) {
      const mapping = alignment(declaration, reference);
      if (mapping === null) continue;
      for (const isolation of (counterpart.isolation.get(overloadKey(title, reference)) ?? new Map()).values()) appleCandidates.push([isolation, mapping]);
    }
  }
  if (appleCandidates.length === 0) return null;
  for (const [webOwn, webParameters, webResults] of webuiIsolations.values()) {
    for (const [[own, parameters, results], mapping] of appleCandidates) {
      if (sameWords(webOwn, own) && sameWords(webResults, results) && mapping.every((target, index) => sameWords(webParameters[index], parameters[target]))) return null;
    }
  }
  const [appleIsolation] = appleCandidates[0];
  const webuiIsolation = webuiIsolations.values().next().value;
  return `SwiftUIWeb [${describeIsolation(webuiIsolation)}] != Apple [${describeIsolation(appleIsolation)}]`;
}

/**
 * ['ok' | 'unchecked' | 'divergent', detail] for one SwiftUIWeb declaration against its Apple counterpart.
 *
 * The declaration passes when some aligned Apple overload agrees on every default, so an overload set that Apple spells as
 * several declarations (`f(x:)` and `f(x:y:)`) is call-compatible with one defaulted `f(x:y: = d)`. Unknown flags on either
 * side leave the declaration unchecked.
 */
export function defaultCheck(declaration, title, entry, counterpart) {
  if (declaration.length === 0) {
    // A variable, a type, or a function without parameters: no argument can be defaulted.
    return ["ok", ""];
  }
  const flags = knownFlags(entry.defaults, overloadKey(title, declaration));
  if (flags === null) return ["unchecked", ""];
  const appleCalls = new Set([...counterpart.overloads.values()].flatMap((refs) => [...refs.keys()]));
  const webCalls = new Set([...entry.overloads.values()].flatMap((refs) => [...refs.keys()]));
  // Apple overloads that differ only in their `where` clause (`SceneStorage.init(wrappedValue:_:)` for `Bool`, `Int`, ...)
  // share one shape; when their defaults disagree the shape is ambiguous. An identical Apple shape is the counterpart, so
  // its ambiguity leaves the declaration unchecked instead of comparing it with a longer overload of another `where` clause.
  const twin = counterpart.overloads.get(title)?.get(dk(declaration));
  if (twin !== undefined && knownFlags(counterpart.defaults, overloadKey(title, twin)) === null) return ["unchecked", ""];
  let first = null;
  let checked = false;
  for (const [referenceTitle, references] of counterpart.overloads) {
    for (const reference of references.values()) {
      const mapping = alignment(declaration, reference);
      if (mapping === null) continue;
      const referenceFlags = knownFlags(counterpart.defaults, overloadKey(referenceTitle, reference));
      if (referenceFlags === null) continue;
      checked = true;
      const problems = defaultProblems(declaration, flags, reference, referenceFlags, mapping, appleCalls, webCalls);
      if (problems.length === 0) return ["ok", ""];
      first = first && first.length > 0 ? first : problems;
    }
  }
  if (!checked) return ["unchecked", ""];
  return ["divergent", first.join("; ")];
}

/**
 * Matches by name and kind, then by (possibly defaulted) labels and types.
 *
 * SwiftUIWeb may omit trailing or leading parameters that SwiftUI defaults, so a declaration whose labels are an ordered
 * subset of one SwiftUI overload's still counts as the same API.
 *
 * `swiftui` is the subset of `apple` that SwiftUI itself declares (all of it when omitted). An unmatched declaration on a
 * SwiftUI type is `extra`; one on a type only another Apple framework declares stays `foreign`, the category it had before
 * those frameworks were compared, so either way it is gated.
 */
export function compare(apple, webui, superclasses = null, swiftui = null, aliases = null) {
  swiftui = swiftui === null ? new Set(apple.keys()) : swiftui;
  superclasses = superclasses ?? {};
  aliases = aliases ?? {};
  const roots = new Set([...swiftui].map((key) => key.slice(key.indexOf(" ") + 1).split(".")[0]));
  const report = { extra: [], foreign: [], signature: [], isolation: [], default: [], disfavored: [], unchecked: [], missing: [] };
  for (const key of sortedStrings(webui.keys())) {
    const entry = webui.get(key);
    const counterpart = counterpartOf(key, apple, superclasses, aliases);
    const file = entry.files.size > 0 ? sortedStrings(entry.files)[0] : "";
    const [family, path] = rsplitSpace(key); // "static var X.y" has a two-word family
    for (const title of sortedStrings(entry.overloads.keys())) {
      const declarations = [...entry.overloads.get(title).values()];
      const item = { key: `${family} ${[...path.split(".").slice(0, -1), title].join(".")}`, file };
      const owner = path.split(".")[0];
      const ownerPath = path.split(".").slice(0, -1).join(".");
      if (Object.hasOwn(APPLE_LITERAL_INITIALIZERS, ownerPath) && APPLE_LITERAL_INITIALIZERS[ownerPath].has(title)) continue;
      if (
        title === "rawValue" && counterpartOf(`init ${ownerPath}.init`, apple, superclasses, aliases) &&
        counterpartOf(`var ${ownerPath}.rawValue`, apple, superclasses, aliases) === null
      ) {
        // Apple's `rawValue` of a RawRepresentable or OptionSet type is synthesized (C-imported newtypes have no declaration
        // in the graph, which is generated with --skip-synthesized-members), while its `init(rawValue:)` is declared.
        // SwiftUIWeb must declare the stored property itself.
        continue;
      }
      if (counterpart === null) {
        // A member of a SwiftUI type is a real divergence; a declaration on a type SwiftUI lacks is a separate, usually
        // internal one. A member of a type some Apple framework declares is extra when Apple lacks it.
        report[(roots.has(owner) || apple.has(`type ${owner}`)) && path.includes(".") ? "extra" : "foreign"].push(item);
        continue;
      }
      const references = [...counterpart.overloads.values()].flatMap((refs) => [...refs.values()]);
      if (!declarations.every((declaration) => references.some((reference) => isSubsequence(declaration, reference, (parameter) => dk(parameter[0]))))) {
        report[swiftui.has(key) || roots.has(owner) || apple.has(`type ${owner}`) ? "extra" : "foreign"].push(item);
      } else if (!declarations.every((declaration) => references.some((reference) => isSubsequence(declaration, reference)))) {
        report.signature.push(item);
      } else {
        const verdicts = declarations.map((declaration) => defaultCheck(declaration, title, entry, counterpart));
        if (verdicts.some(([verdict]) => verdict === "unchecked")) report.unchecked.push(item);
        if (verdicts.some(([verdict]) => verdict === "divergent")) {
          report.default.push({ ...item, detail: verdicts.find(([verdict]) => verdict === "divergent")[1] });
        }
        const details = [];
        for (const declaration of declarations) {
          const detail = isolationDetail(entry.isolation.get(overloadKey(title, declaration)) ?? new Map(), counterpart, declaration);
          if (detail) details.push(detail);
        }
        if (details.length > 0) report.isolation.push({ ...item, detail: details[0] });
        const ranking = declarations.map((declaration) => disfavoredDetail(declaration, title, entry, counterpart)).find((detail) => detail !== null);
        if (ranking) report.disfavored.push({ ...item, detail: ranking });
      }
    }
  }
  report.missing = sortedStrings(swiftui).filter((key) => !webui.has(key)).map((key) => ({ key }));
  return report;
}

// ---- command line -------------------------------------------------------------------------------------------------------
const USAGE =
  "usage: swiftui-api-parity.mjs [-h] [--generate] [--apple-graphs DIR [DIR ...]] [--webui-graphs DIR] [--browser-graphs DIR]\n" +
  "                              [--check | --update | --rewrite-baseline] [--strict-signatures] [--top TOP]";

function parseArguments(argv) {
  const args = {
    generate: false, appleGraphs: Object.keys(APPLE_PLATFORMS).map((directory) => join(CACHE, directory)), webuiGraphs: WEBUI_GRAPHS,
    browserGraphs: BROWSER_GRAPHS, mode: null, strictSignatures: false, top: 15,
  };
  const error = (message) => {
    console.error(`${USAGE}\nswiftui-api-parity.mjs: error: ${message}`);
    process.exit(2);
  };
  const setMode = (name) => {
    if (args.mode !== null && args.mode !== name) error(`argument --${name}: not allowed with argument --${args.mode}`);
    args.mode = name;
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const next = () => {
      if (index + 1 >= argv.length || argv[index + 1].startsWith("--")) error(`argument ${argument}: expected one argument`);
      return argv[(index += 1)];
    };
    if (argument === "--generate") args.generate = true;
    else if (argument === "--apple-graphs") {
      const values = [];
      while (index + 1 < argv.length && !argv[index + 1].startsWith("--")) values.push(resolve(argv[(index += 1)]));
      if (values.length === 0) error("argument --apple-graphs: expected at least one argument");
      args.appleGraphs = values;
    } else if (argument === "--webui-graphs") args.webuiGraphs = resolve(next());
    else if (argument === "--browser-graphs") args.browserGraphs = resolve(next());
    else if (argument === "--check" || argument === "--update" || argument === "--rewrite-baseline") setMode(argument.slice(2));
    else if (argument === "--strict-signatures") args.strictSignatures = true;
    else if (argument === "--top") {
      const value = next();
      if (!/^-?\d+$/u.test(value)) error(`argument --top: invalid int value: '${value}'`);
      args.top = Number.parseInt(value, 10);
    } else if (argument === "-h" || argument === "--help") {
      console.log(`${USAGE}\n\nChecks SwiftUIWeb's public API against Apple's SwiftUI.`);
      process.exit(0);
    } else error(`unrecognized arguments: ${argument}`);
  }
  return args;
}

const baselineName = () => relative(ROOT, BASELINE);
const DETAILED_CATEGORIES = ["isolation", "default", "disfavored"];
const suffixDetail = (details, key, name) => (Object.hasOwn(details, key) && DETAILED_CATEGORIES.includes(name) ? ` (${details[key]})` : "");

function main() {
  const args = parseArguments(process.argv.slice(2));
  if (args.generate) generate();
  for (const directory of [...args.appleGraphs, args.webuiGraphs, args.browserGraphs]) {
    if (!existsSync(directory) || !statSync(directory).isDirectory()) fail(`missing symbol graphs in ${directory}; run with --generate`);
  }
  const [swiftui, apple, superclasses] = appleTables(args.appleGraphs);
  let aliases = standIns(apple);
  const renames = Object.fromEntries(Object.entries(aliases).filter(([name]) => name.startsWith("_")));
  // The native graphs also list the modules SwiftUIWeb re-exports. Apple's own (Dispatch, which WebFoundation re-exports as
  // Foundation does) are not SwiftUIWeb's declarations; WebFoundation's are compared as its browser graph is, below.
  const ownModules = SWIFTUIWEB_MODULES.filter((name) => name !== "WebFoundation");
  const webui = load(graphFiles(args.webuiGraphs, WEBUI_MODULES), { renames, ownModules, excludedModules: ["WebFoundation"] });
  const nativeShims = load(graphFiles(args.webuiGraphs, WEBUI_MODULES), { renames, ownModules: ["WebFoundation"] });
  merge(webui, new Map([...nativeShims].filter(([key]) => declaredByApple(key, apple))));
  const browser = load(graphFiles(args.browserGraphs, [], ["WebFoundation"]), { renames, moduleSources: "WebFoundation" });
  merge(webui, new Map([...browser].filter(([key]) => declaredByApple(key, apple))));
  const interfaces = swiftuiwebInterfaces();
  const browserInterface = newestFile(BROWSER_SCRATCH, "WebFoundation.swiftinterface");
  if (browserInterface) interfaces.push(browserInterface);
  const disfavored = new Map();
  attachDefaults(webui, interfaceDefaults(interfaces, renames, disfavored));
  attachDisfavored(webui, disfavored);
  aliases = Object.fromEntries(Object.entries(aliases).filter(([name]) => webui.has(`type ${name}`) && !Object.hasOwn(renames, name)));
  const report = compare(apple, webui, superclasses, new Set(swiftui.keys()), aliases);
  console.log(`SwiftUI declarations: ${swiftui.size}  with other Apple frameworks: ${apple.size}  SwiftUIWeb declarations: ${webui.size}`);
  for (const [standIn, appleName] of Object.entries({ ...aliases, ...renames }).sort(([a], [b]) => compareStrings(a, b))) {
    console.log(`  ${standIn} members are compared with ${appleName}`);
  }
  console.log(Object.entries(report).map(([name, items]) => `${name} ${items.length}`).join("  "));

  const byFile = new Map();
  for (const item of report.extra) {
    const parts = item.file.split("/");
    const name = `${parts.length > 1 ? parts[parts.length - 2] : ""}/${lastOf(parts)}`;
    byFile.set(name, (byFile.get(name) ?? 0) + 1);
  }
  const ranked = [...byFile].sort((a, b) => b[1] - a[1]);
  for (const [name, count] of args.top >= 0 ? ranked.slice(0, args.top) : []) console.log(`  extra ${String(count).padStart(4)}  ${name}`);

  const gated = args.strictSignatures ? [...GATED_CATEGORIES, "signature"] : [...GATED_CATEGORIES];
  const current = Object.fromEntries(BASELINE_CATEGORIES.map((name) => [name, sortedStrings(report[name].map((item) => item.key))]));
  const details = {};
  for (const name of DETAILED_CATEGORIES) for (const item of report[name]) details[item.key] = item.detail;
  if (args.mode === "rewrite-baseline") {
    mkdirSync(dirname(BASELINE), { recursive: true });
    writeFileSync(BASELINE, jsonDumps({ comment: "Reviewed divergences from SwiftUI; shrink this list, never grow it.", ...current }, { indent: 1 }) + "\n", "utf8");
    console.log(`baseline rewritten (review the diff; this adds entries): ${baselineName()}`);
    return 0;
  }
  if (args.mode === "update") {
    if (!existsSync(BASELINE)) fail(`no baseline at ${baselineName()}; use --rewrite-baseline after review`);
    const known = JSON.parse(readText(BASELINE));
    const [pruned, unlisted] = pruneBaseline(known, current);
    const removed = BASELINE_CATEGORIES.filter((name) => Object.hasOwn(known, name)).reduce((sum, name) => sum + known[name].length - pruned[name].length, 0);
    if (!jsonEqual(pruned, known)) writeFileSync(BASELINE, jsonDumps(pruned, { indent: 1 }) + "\n", "utf8");
    console.log(`pruned ${removed} fixed entries from ${baselineName()}`);
    // Signature differences are informational unless gated, so only gated ones fail the run.
    for (const [name, items] of Object.entries(unlisted)) {
      for (const key of items.slice(0, 50)) console.log(`  unlisted ${name}: ${key}${suffixDetail(details, key, name)}`);
    }
    if (gated.some((name) => (unlisted[name] ?? []).length > 0)) {
      console.log("divergences above are not in the baseline and were not added; fix them in code");
      return 1;
    }
    return 0;
  }
  if (args.mode === "check") {
    const known = existsSync(BASELINE) ? JSON.parse(readText(BASELINE)) : {};
    let failed = false;
    for (const name of gated) {
      const listed = new Set(known[name] ?? []);
      const live = new Set(current[name]);
      const added = sortedStrings([...live].filter((key) => !listed.has(key)));
      const fixed = sortedStrings([...listed].filter((key) => !live.has(key)));
      if (fixed.length > 0) console.log(`${fixed.length} baseline ${name} entries are fixed; run --update to prune them`);
      if (added.length > 0) {
        failed = true;
        console.log(`\nNEW ${name} divergences from SwiftUI (${added.length}):`);
        for (const key of added.slice(0, 50)) console.log("  ", key + suffixDetail(details, key, name));
      }
    }
    return failed ? 1 : 0;
  }
  return 0;
}

if (isMain(import.meta.url)) process.exit(main());
