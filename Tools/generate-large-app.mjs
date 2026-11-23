#!/usr/bin/env bun
// Writes a deterministic, synthetic SwiftUI application shaped like a layered app: feature folders with a model, a store,
// pure rules, a screen and a set of row, card and sheet views. Its size is the ruler for "bytes per view"
// (Documentation/Performance/WASM_SIZE.md, "Measuring a large application").
//
//   bun Tools/generate-large-app.mjs --out <directory> [--views 200] [--seed 1]
//
// The directory is created, or emptied when this generator wrote it before (it holds the marker file). Any other
// non-empty directory is refused, so the tool never removes a folder it did not make. The same arguments write the same
// bytes: the only randomness is a seeded mulberry32, and every collection is walked in a fixed order.
import { existsSync, mkdirSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, posix, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
export const MARKER = ".generated-large-app";
const TARGET = "LargeApp";

/** Singular and plural domain words. Feature k uses DOMAINS[k % 20], with a number after the word beyond 20 features. */
const DOMAINS = [
  ["Order", "Orders"], ["Task", "Tasks"], ["Note", "Notes"], ["Item", "Items"], ["Invoice", "Invoices"],
  ["Shipment", "Shipments"], ["Contact", "Contacts"], ["Event", "Events"], ["Reminder", "Reminders"], ["Stock", "Inventory"],
  ["Message", "Messages"], ["Project", "Projects"], ["Expense", "Expenses"], ["Booking", "Bookings"], ["Ticket", "Tickets"],
  ["Recipe", "Recipes"], ["Route", "Routes"], ["Sample", "Samples"], ["Survey", "Surveys"], ["Report", "Reports"],
];
/** The names of the non-screen views, cycled in order. "Row" views are rendered in a ForEach over the store. */
const NOUNS = ["Row", "Card", "Section", "Toolbar", "Detail", "Header", "Badge", "Panel", "Footer", "Strip", "Tile", "Banner", "Chip", "Sheet"];
const WORDS = ["Pending", "Recent", "Due soon", "Archived", "Priority", "Review", "Ready", "Draft", "Shared", "Overdue", "Local", "Synced", "Starred", "Queued", "Closed", "Open"];
const SYMBOLS = ["tray", "star", "clock", "tag", "bell", "doc.text", "person.crop.circle", "calendar", "paperplane", "checkmark.circle", "exclamationmark.triangle", "folder"];
const STATUSES = ["open", "closed", "draft"];

/** mulberry32: a small seeded generator. Every value the generator draws comes from one instance, in a fixed order. */
export function mulberry32(seed) {
  let state = seed >>> 0;
  const next = () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return {
    next,
    int: (min, max) => min + Math.floor(next() * (max - min + 1)),
    chance: (probability) => next() < probability,
    pick: (items) => items[Math.floor(next() * items.length)],
    number: (min, max, digits) => Number((min + next() * (max - min)).toFixed(digits)),
    shuffle(items) {
      const out = items.slice();
      for (let i = out.length - 1; i > 0; i--) {
        const j = Math.floor(next() * (i + 1));
        [out[i], out[j]] = [out[j], out[i]];
      }
      return out;
    },
  };
}

/** The number of feature folders for a view count: one per ten views, at least two. */
export function featureCount(views) {
  return Math.max(2, Math.round(views / 10));
}

function featureNames(index) {
  const [singular, plural] = DOMAINS[index % DOMAINS.length];
  const round = index >= DOMAINS.length ? String(Math.floor(index / DOMAINS.length) + 1) : "";
  return { sing: singular + round, plural: plural + round };
}

// ---- Modifiers, items and bodies -------------------------------------------------------------------------------------

/** Each entry writes one modifier line (with the two-space continuation indent) from the generator's random draws. */
const MODIFIERS = [
  (r) => `  .font(${r.pick(["Typography.heading", "Typography.caption", "Typography.body"])})`,
  (r) => `  .foregroundStyle(${r.pick(["Palette.accent", "Palette.ink", "Palette.warm", ".secondary"])})`,
  (r) => (r.chance(0.5) ? `  .padding(.horizontal, ${r.int(4, 16)})` : `  .padding(${r.int(4, 16)})`),
  (r) => (r.chance(0.5)
    ? "  .frame(maxWidth: .infinity, alignment: .leading)"
    : `  .frame(width: ${r.int(40, 140)}, height: ${r.int(20, 48)})`),
  (r) => `  .background(${r.pick(["Palette.surface", "Palette.light", "Palette.warm"])})`,
  (r) => `  .clipShape(RoundedRectangle(cornerRadius: ${r.int(4, 16)}))`,
  (r) => `  .overlay(RoundedRectangle(cornerRadius: ${r.int(4, 16)}).stroke(Palette.accent, lineWidth: 1))`,
  (r) => `  .opacity(0.${r.int(5, 9)})`,
  (r) => `  .lineLimit(${r.int(1, 3)})`,
];

/** Between `min` and `max` modifiers, in the table's order (font first, line limit last). */
function chain(rng, min, max) {
  const count = rng.int(min, max);
  const picked = rng.shuffle(MODIFIERS.map((_, index) => index)).slice(0, count).sort((a, b) => a - b);
  return picked.map((index) => MODIFIERS[index](rng));
}

function textContent(ctx) {
  const { rng, view, sing } = ctx;
  const word = rng.pick(WORDS);
  if (view.shape === "row") {
    return rng.pick(["record.title", `"\\(record.count) ${word}"`, `${sing}Rules.label(for: record.status)`]);
  }
  return rng.pick([`"${word}"`, "store.headline", `"\\(store.visibleRecords.count) ${word}"`]);
}

function textItem(ctx) {
  return [`Text(${textContent(ctx)})`, ...chain(ctx.rng, 2, 5)];
}

function leafItem(ctx) {
  const kind = ctx.rng.pick(["image", "text", "spacer"]);
  if (kind === "image") return [`Image(systemName: "${ctx.rng.pick(SYMBOLS)}")`];
  if (kind === "text") return [`Text(${textContent(ctx)})`];
  return ["Spacer()"];
}

function stackItem(ctx) {
  const { rng } = ctx;
  const horizontal = rng.chance(0.5);
  const head = horizontal
    ? `HStack(alignment: .center, spacing: ${rng.int(2, 10)}) {`
    : `VStack(alignment: .leading, spacing: ${rng.int(2, 8)}) {`;
  const leaves = [];
  for (let k = 0, count = rng.int(2, 3); k < count; k++) leaves.push(...leafItem(ctx));
  const lines = [head, ...leaves.map((line) => `  ${line}`), "}"];
  if (rng.chance(0.5)) lines.push(...chain(rng, 1, 2));
  return lines;
}

function zstackItem(ctx) {
  const { rng } = ctx;
  return [
    `ZStack(alignment: .${rng.pick(["topTrailing", "bottomLeading", "center"])}) {`,
    `  RoundedRectangle(cornerRadius: ${rng.int(4, 14)})`,
    "    .fill(Palette.surface)",
    `    .frame(width: ${rng.int(60, 140)}, height: ${rng.int(30, 60)})`,
    ...textItem(ctx).map((line) => `  ${line}`),
    "}",
  ];
}

function buttonItem(ctx) {
  const { rng, view, state } = ctx;
  const actions = view.shape === "row"
    ? ["store.select(record.id)", "store.toggleArchived(record.id)", "store.bump(record.id)"]
    : ["store.reload()", "store.clearQuery()"];
  for (const toggle of state.toggles) actions.push(`${toggle}.toggle()`);
  if (view.shape === "binding") actions.push("isOn.toggle()");
  return [
    "Button {",
    `  ${rng.pick(actions)}`,
    "} label: {",
    "  HStack(spacing: 4) {",
    `    Image(systemName: "${rng.pick(SYMBOLS)}")`,
    `    Text("${rng.pick(WORDS)}")`,
    "  }",
    "}",
    ".buttonStyle(TokenButtonStyle())",
  ];
}

function branchItem(ctx) {
  const { rng, view, state, addState } = ctx;
  const kind = rng.pick(["count", "empty", "summary", "revision", "expand"]);
  if (kind === "count") {
    return ["if store.visibleRecords.isEmpty {", `  Text("Nothing ${rng.pick(WORDS)}")`, "} else {",
      '  Text("\\(store.visibleRecords.count) shown")', "}"];
  }
  if (kind === "empty") {
    if (view.shape === "row") {
      return ["if record.isArchived {", '  Text("Archived")', "} else {", `  Text(${textContent(ctx)})`, "}"];
    }
    return ["if let selected = store.selectedRecord {", "  Text(selected.title)", "    .font(Typography.heading)", "}"];
  }
  if (kind === "summary") {
    return ["if let summary = store.summary {", '  Text("\\(summary.label): \\(Int(store.total()))")', "}"];
  }
  if (kind === "revision") {
    return [`if store.revision > ${rng.int(1, 4)} {`, '  Text("Reloaded")', "} else {", "  Text(store.headline)", "}"];
  }
  addState("@State private var expanded = false");
  if (!state.toggles.includes("expanded")) state.toggles.push("expanded");
  return ["Button {", "  expanded.toggle()", '} label: {', '  Text("More")', "}",
    "if expanded {", `  Text(${textContent(ctx)})`, "}"];
}

function envItem(ctx) {
  ctx.addState("@Environment(\\.colorScheme) private var colorScheme");
  return [`Text(${textContent(ctx)})`, "  .foregroundStyle(colorScheme == .dark ? Palette.light : Palette.ink)",
    ...chain(ctx.rng, 1, 2)];
}

function scrollItem(ctx) {
  return ["ScrollView {", "  VStack(alignment: .leading, spacing: 4) {", ...textItem(ctx).map((line) => `    ${line}`),
    "  }", "}", `.frame(height: ${ctx.rng.int(80, 160)})`];
}

function randomItem(ctx) {
  const kind = ctx.rng.pick(["text", "text", "text", "stack", "zstack", "button", "button", "branch", "branch", "divider", "scroll", "env"]);
  switch (kind) {
    case "text": return textItem(ctx);
    case "stack": return stackItem(ctx);
    case "zstack": return zstackItem(ctx);
    case "button": return buttonItem(ctx);
    case "branch": return branchItem(ctx);
    case "divider": return ["Divider()"];
    case "scroll": return scrollItem(ctx);
    default: return envItem(ctx);
  }
}

/** A child view rendered by its parent: a ForEach row, a binding into the parent's flag, a sheet, or an inline view. */
function childItem(ctx, child) {
  const { rng, state, addState } = ctx;
  if (child.shape === "row") {
    return [`ForEach(store.visibleRecords, id: \\.id) { record in`, `  ${child.name}(record: record, store: store)`, "}"];
  }
  if (child.shape === "binding") {
    addState(`@State private var flag${child.index} = false`);
    if (!state.toggles.includes(`flag${child.index}`)) state.toggles.push(`flag${child.index}`);
    return [`${child.name}(store: store, isOn: $flag${child.index})`];
  }
  if (child.via === "sheet") {
    addState(`@State private var presented${child.index} = false`);
    state.sheets.push(child);
    return ["Button {", `  presented${child.index} = true`, "} label: {", `  Text("${rng.pick(WORDS)}")`, "}",
      ".buttonStyle(TokenButtonStyle())"];
  }
  return [`${child.name}(store: store)`];
}

/** One view struct: its stored properties, an explicit initializer (so @State can keep its defaults), and its body. */
function viewSource(rng, view, sing) {
  const store = `${sing}Store`;
  const record = `${sing}Record`;
  const state = { decls: [], sheets: [], toggles: [] };
  const addState = (line) => {
    if (!state.decls.includes(line)) state.decls.push(line);
  };
  const ctx = { rng, view, sing, state, addState };

  const props = [];
  const params = [];
  const assigns = [];
  if (view.isScreen) {
    props.push(`@StateObject private var store = ${store}()`);
  } else {
    if (view.shape === "row") {
      props.push(`let record: ${record}`);
      params.push(`record: ${record}`);
      assigns.push("self.record = record");
    }
    if (view.shape === "observed") {
      props.push(`@ObservedObject var store: ${store}`);
      assigns.push("self._store = ObservedObject(wrappedValue: store)");
    } else {
      props.push(`let store: ${store}`);
      assigns.push("self.store = store");
    }
    params.push(`store: ${store}`);
    if (view.shape === "binding") {
      props.push("@Binding var isOn: Bool");
      params.push("isOn: Binding<Bool>");
      assigns.push("self._isOn = isOn");
    }
  }

  const items = [];
  for (const child of view.children) items.push(childItem(ctx, child));
  for (let k = 0, extra = (view.isScreen ? 4 : 3) + rng.int(0, 2); k < extra; k++) items.push(randomItem(ctx));
  const ordered = rng.shuffle(items);

  const stack = [`VStack(alignment: .leading, spacing: ${rng.pick([4, 6, 8, 10, 12])}) {`];
  for (const item of ordered) for (const line of item) stack.push(`  ${line}`);
  stack.push("}");

  const modifiers = [];
  if (view.isScreen) {
    modifiers.push(".padding(16)", ".task { store.reload() }");
  } else {
    if (rng.chance(0.5)) modifiers.push(".padding(12)");
    if (rng.chance(0.5)) modifiers.push(".modifier(CardModifier(tint: Palette.accent))");
    if (rng.chance(0.3)) modifiers.push(".onChange(of: store.query) { store.reload() }");
  }
  for (const child of state.sheets) {
    modifiers.push(`.sheet(isPresented: $presented${child.index}) {`, `  ${child.name}(store: store)`, "}");
  }
  let block = [...stack, ...modifiers];
  if (view.isScreen) block = ["ScrollView {", ...block.map((line) => `  ${line}`), "}"];
  const bodyLines = ["var body: some View {", ...block.map((line) => `  ${line}`), "}"];

  const out = [`struct ${view.name}: View {`];
  for (const line of [...props, ...state.decls]) out.push(`  ${line}`);
  if (!view.isScreen) {
    out.push("", `  init(${params.join(", ")}) {`, ...assigns.map((line) => `    ${line}`), "  }");
  }
  out.push("", ...bodyLines.map((line) => `  ${line}`), "}");
  return `${out.join("\n")}\n`;
}

// ---- Model, store, rules and screen ----------------------------------------------------------------------------------

function seedJSON(rng, sing, plural) {
  const line = () => ({
    sku: `SKU-${rng.int(100, 999)}`,
    quantity: rng.int(1, 5),
    unitPrice: rng.number(1, 90, 2),
    isTaxable: rng.chance(0.7),
  });
  const records = [];
  for (let i = 0, count = rng.int(4, 7); i < count; i++) {
    const lines = [];
    for (let k = 0, lineCount = rng.int(1, 3); k < lineCount; k++) lines.push(line());
    records.push({
      id: `${sing.toLowerCase()}-${i + 1}`,
      title: `${rng.pick(WORDS)} ${i + 1}`,
      count: rng.int(0, 20),
      amount: rng.number(0, 500, 2),
      isArchived: rng.chance(0.2),
      note: rng.chance(0.5) ? rng.pick(WORDS) : null,
      status: rng.pick(STATUSES),
      lines,
    });
  }
  const summary = { label: `${plural} total`, total: rng.number(0, 900, 2), lines: rng.chance(0.8) ? [line()] : null };
  return JSON.stringify({ version: 1, records, summary, tags: WORDS.slice(0, rng.int(3, 6)) });
}

function modelSource(sing) {
  const record = `${sing}Record`;
  const line = `${sing}Line`;
  return `import Foundation

struct ${record}: Codable {
  let id: String
  var title: String
  var count: Int
  var amount: Double
  var isArchived: Bool
  var note: String?
  var status: String
  var lines: [${line}]
}

struct ${line}: Codable {
  let sku: String
  let quantity: Int
  let unitPrice: Double
  let isTaxable: Bool
}

struct ${sing}Summary: Codable {
  let label: String
  let total: Double
  let lines: [${line}]?
}

struct ${sing}Catalog: Codable {
  let version: Int
  let records: [${record}]
  let summary: ${sing}Summary?
  let tags: [String]
}
`;
}

function storeSource(sing, json) {
  return `import Foundation
import SwiftUI

/// ${sing} state: loaded from a JSON literal, changed by the buttons of its screens.
final class ${sing}Store: ObservableObject {
  private static let seedJSON = #"${json}"#

  @Published var records: [${sing}Record] = []
  @Published var query = ""
  @Published var selectedID: String?
  @Published var summary: ${sing}Summary?
  @Published var revision = 0

  init() {
    reload()
  }

  var visibleRecords: [${sing}Record] {
    ${sing}Rules.visible(records, query: query)
  }

  var selectedRecord: ${sing}Record? {
    guard let selectedID else { return nil }
    return records.first { $0.id == selectedID }
  }

  var headline: String {
    "\\(visibleRecords.count) of \\(records.count)"
  }

  var statusCounts: [String: Int] {
    var counts: [String: Int] = [:]
    for (status, group) in ${sing}Rules.grouped(records) {
      counts[status] = group.count
    }
    return counts
  }

  func total() -> Double {
    ${sing}Rules.total(summary?.lines ?? [])
  }

  func reload() {
    guard let catalog = try? JSONDecoder().decode(${sing}Catalog.self, from: Data(Self.seedJSON.utf8)) else { return }
    records = ${sing}Rules.sorted(catalog.records)
    summary = catalog.summary
    revision += 1
  }

  func select(_ id: String) {
    selectedID = id
  }

  func toggleArchived(_ id: String) {
    guard let index = records.firstIndex(where: { $0.id == id }) else { return }
    records[index].isArchived.toggle()
    revision += 1
  }

  func bump(_ id: String) {
    guard let index = records.firstIndex(where: { $0.id == id }) else { return }
    records[index].count += 1
    revision += 1
  }

  func clearQuery() {
    query = ""
  }
}
`;
}

function rulesSource(sing, rng) {
  const record = `${sing}Record`;
  const [first, second, third] = [rng.pick(WORDS), rng.pick(WORDS), rng.pick(WORDS)];
  return `/// Pure rules of ${sing}: no state, so each function is testable on its own.
enum ${sing}Rules {
  static func label(for status: String) -> String {
    switch status {
    case "${STATUSES[0]}": return "${first}"
    case "${STATUSES[1]}": return "${second}"
    default: return "${third}"
    }
  }

  static func sorted(_ records: [${record}]) -> [${record}] {
    records.sorted(by: { $0.count > $1.count })
  }

  static func visible(_ records: [${record}], query: String) -> [${record}] {
    records.filter { !$0.isArchived && (query.isEmpty || $0.title.hasPrefix(query)) }
  }

  static func grouped(_ records: [${record}]) -> [String: [${record}]] {
    var groups: [String: [${record}]] = [:]
    for record in records {
      groups[record.status, default: []].append(record)
    }
    return groups
  }

  static func total(_ lines: [${sing}Line]) -> Double {
    lines.reduce(0) { $0 + Double($1.quantity) * $1.unitPrice }
  }
}
`;
}


// ---- Feature and project ---------------------------------------------------------------------------------------------

/**
 * One feature folder for `count` views (the screen included). The components form a tree of fan-out three below the
 * screen, so every view is rendered by its parent and none is dead code.
 */
export function generateFeature(rng, index, count) {
  const { sing, plural } = featureNames(index);
  const folder = `Sources/${TARGET}/Features/${sing}`;
  const comps = [];
  for (let j = 0; j < count - 1; j++) {
    const noun = NOUNS[j % NOUNS.length];
    const shape = noun === "Row" ? "row" : rng.pick(["let", "let", "observed", "binding"]);
    const via = shape === "row" || shape === "binding" ? "inline" : rng.chance(0.4) ? "sheet" : "inline";
    comps.push({ name: `${sing}${noun}${j + 1}`, index: j, shape, via, parent: j < 3 ? -1 : Math.floor(j / 3) - 1 });
  }
  const childrenOf = (parent) => comps.filter((comp) => comp.parent === parent);
  const screen = { name: `${sing}Screen`, index: -1, isScreen: true, shape: "let", children: childrenOf(-1) };
  const componentViews = comps.map((comp) => ({ ...comp, isScreen: false, children: childrenOf(comp.index) }));

  const files = new Map();
  files.set(`${folder}/${sing}Model.swift`, modelSource(sing));
  files.set(`${folder}/${sing}Store.swift`, storeSource(sing, seedJSON(rng, sing, plural)));
  files.set(`${folder}/${sing}Rules.swift`, rulesSource(sing, rng));
  files.set(`${folder}/${sing}Components.swift`, `import SwiftUI\n\n${componentViews.map((view) => viewSource(rng, view, sing)).join("\n")}`);
  files.set(`${folder}/${sing}Screen.swift`, `import SwiftUI\n\n/// The ${plural} tab: owns the store and renders the views of its feature.\n${viewSource(rng, screen, sing)}`);
  return { files, screen: screen.name, views: 1 + componentViews.length };
}

const SHARED = `import SwiftUI

/// Colors every feature uses.
enum Palette {
  static let accent = Color.blue
  static let surface = Color.gray
  static let ink = Color.black
  static let light = Color.white
  static let warm = Color.orange
}

/// Font styles every feature uses.
enum Typography {
  static let heading = Font.headline
  static let body = Font.body
  static let caption = Font.caption
}

/// The card look shared by the views of every feature.
struct CardModifier: ViewModifier {
  let tint: Color

  func body(content: Content) -> some View {
    content
      .padding(12)
      .background(Palette.surface)
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint, lineWidth: 1))
  }
}

/// The button look shared by the views of every feature.
struct TokenButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(8)
      .background(Palette.accent)
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}
`;

const MAIN = `import SwiftUI
import SwiftUIWebBrowser
import Foundation

@main
struct LargeAppApp: BrowserApp {
  var body: some View { WindowGroup { LargeAppRoot() } }
}
`;

function rootSource(screens) {
  const tabs = screens.map((screen, index) => [
    `      ${screen.screen}()`,
    `        .tabItem { Text("${screen.plural}") }`,
    `        .tag(${index})`,
  ].join("\n"));
  return `import SwiftUI

/// The root: one tab per feature, so every feature's screen is reachable from the application.
struct LargeAppRoot: View {
  @State private var selection = 0

  var body: some View {
    TabView(selection: $selection) {
${tabs.join("\n")}
    }
  }
}
`;
}

function packageSource(relativeRoot) {
  return `// swift-tools-version: 6.4
import PackageDescription

// Generated by Tools/generate-large-app.mjs. Regenerate instead of editing.
let aliases = [
  "SwiftUI=SwiftUIWeb",
  "Foundation=WebFoundation"
]
let aliasFlags = aliases.flatMap { ["-module-alias", $0] }

let package = Package(
  name: "${TARGET}",
  platforms: [.macOS(.v15)],
  products: [.executable(name: "${TARGET}", targets: ["${TARGET}"])],
  dependencies: [.package(path: "${relativeRoot}")],
  targets: [
    .executableTarget(
      name: "${TARGET}",
      dependencies: [
        .product(name: "SwiftUIWeb", package: "swiftuiweb"),
        .product(name: "SwiftUIWebBrowser", package: "swiftuiweb"),
        .product(name: "WebFoundation", package: "swiftuiweb")
      ],
      path: "Sources/${TARGET}",
      swiftSettings: [.unsafeFlags(aliasFlags), .swiftLanguageMode(.v5)]
    )
  ]
)
`;
}

/**
 * The whole application for `views` views, as a Map of relative path to text in a fixed order. `out` is the directory
 * it will be written to: the manifest reaches the repository root from there.
 */
export function generateProject({ views = 200, seed = 1, out = join(ROOT, ".build", "large-app") } = {}) {
  if (!Number.isInteger(views) || views < 10) throw new Error(`--views must be an integer of at least 10, not ${views}`);
  if (!Number.isInteger(seed) || seed < 0 || seed > 0xffffffff) throw new Error(`--seed must be an integer from 0 to 4294967295, not ${seed}`);
  const rng = mulberry32(seed);
  const features = featureCount(views);
  const files = new Map();
  const screens = [];
  let remaining = views - 1;
  for (let index = 0; index < features; index++) {
    const count = Math.floor(remaining / (features - index));
    remaining -= count;
    const feature = generateFeature(rng, index, count);
    for (const [path, text] of feature.files) files.set(path, text);
    screens.push({ screen: feature.screen, plural: featureNames(index).plural });
  }
  files.set(`Sources/${TARGET}/Shared/Shared.swift`, SHARED);
  files.set(`Sources/${TARGET}/App/Root.swift`, rootSource(screens));
  files.set(`Sources/${TARGET}/main.swift`, MAIN);
  files.set("Package.swift", packageSource(posix.relative(resolve(out), ROOT) || "."));
  files.set(MARKER, "Written by Tools/generate-large-app.mjs. The generator empties this directory on its next run.\n");
  return { files, views, features };
}

/**
 * Writes the files into `directory`, which is emptied first when the generator wrote it, refused otherwise. The marker
 * stays while the directory is emptied and is written before any other file, so a run that stops halfway (a full disk, a
 * path that cannot be written) leaves a directory the next run may still empty.
 */
export function writeProject(directory, files) {
  const dir = resolve(directory);
  if (existsSync(dir)) {
    if (!statSync(dir).isDirectory()) throw new Error(`${directory} exists and is not a directory`);
    const entries = readdirSync(dir);
    if (entries.length && !existsSync(join(dir, MARKER))) {
      throw new Error(`refusing to empty ${directory}: it has ${entries.length} entries and no ${MARKER} marker, so the generator did not write it`);
    }
    for (const entry of entries) {
      const path = join(dir, entry);
      if (entry === MARKER && statSync(path).isFile()) continue;
      rmSync(path, { recursive: true, force: true });
    }
  }
  mkdirSync(dir, { recursive: true });
  if (files.has(MARKER)) writeFileSync(join(dir, MARKER), files.get(MARKER));
  for (const [path, text] of files) {
    if (path === MARKER) continue;
    const target = join(dir, path);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, text);
  }
  return dir;
}

function parseArguments(argv) {
  const options = { out: undefined, views: 200, seed: 1 };
  for (let index = 0; index < argv.length; index++) {
    const flag = argv[index];
    const value = () => {
      if (index + 1 >= argv.length) throw new Error(`${flag} needs a value`);
      index += 1;
      return argv[index];
    };
    if (flag === "--out") options.out = value();
    else if (flag === "--views") options.views = Number(value());
    else if (flag === "--seed") options.seed = Number(value());
    else throw new Error(`unknown argument ${flag}; usage: bun Tools/generate-large-app.mjs --out <directory> [--views 200] [--seed 1]`);
  }
  if (!options.out) throw new Error("--out <directory> is required");
  return options;
}

if (import.meta.main) {
  try {
    const options = parseArguments(process.argv.slice(2));
    const out = resolve(options.out);
    const { files, views, features } = generateProject({ views: options.views, seed: options.seed, out });
    writeProject(out, files);
    const lines = [...files.values()].reduce((sum, text) => sum + text.split("\n").length - 1, 0);
    console.log(`wrote ${files.size} files to ${out}: ${views} views in ${features} features, ${lines} lines`);
  } catch (error) {
    console.error(`generate-large-app: ${error.message}`);
    process.exit(2);
  }
}
