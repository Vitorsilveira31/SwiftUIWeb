#!/usr/bin/env bun
/*
 * SwiftUIWeb release reachability planner.
 *
 * SwiftPM/LLVM still perform the authoritative Swift symbol reachability
 * pass.  This small build-time graph covers the assets and browser helpers
 * that Swift cannot see: ESM/provider chunks, CSS, icons, workers and static
 * files.  It is deliberately conservative.  An unknown dynamic reference
 * keeps the relevant category instead of silently deleting a resource.
 */
"use strict";

const fs = require("fs");
const path = require("path");

function argument(name, fallback = null) {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : fallback;
}

function hasFlag(name) { return process.argv.includes(name); }

const root = path.resolve(argument("--root", path.join(__dirname, "..")));
const product = argument("--product", "Application");
const output = path.resolve(argument("--output", path.join(root, ".build", "release-manifest.json")));
const bundleDir = argument("--bundle-dir");
// `--source` is APPLICATION evidence: the consumer's own code (for the
// framework's own examples and test apps, only Examples/<product> or Tests/Apps/<product>). `--framework-source` lists
// framework source trees that supply vocabulary only (CSS classes, the icon
// catalog, asset discovery). Their contents never turn an optional feature on:
// the framework mentions MeshGradient, Canvas or onDrop itself, which says
// nothing about whether the application uses them.
const sourceArgument = argument("--source");
const frameworkSourceArgument = argument("--framework-source");
const explicitManifestPath = argument("--assets", process.env.SWIFTUIWEB_RELEASE_ASSETS || null);

function readText(file) {
  try { return fs.readFileSync(file, "utf8"); } catch (_) { return ""; }
}

function readJSON(file) {
  if (!file) return null;
  try { return JSON.parse(fs.readFileSync(file, "utf8")); } catch (error) {
    throw new Error(`Unable to read JSON manifest ${file}: ${error.message}`);
  }
}

function walk(directory) {
  if (!directory || !fs.existsSync(directory)) return [];
  const result = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if ([".build", ".git", "node_modules", ".swiftpm"].includes(entry.name)) continue;
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) result.push(...walk(file));
    else if (entry.isFile()) result.push(file);
  }
  return result;
}

function productDirectory(name) {
  const candidates = ["Examples", path.join("Tests", "Apps")].flatMap((folder) => [
    path.join(root, folder, name),
    path.join(root, folder, name.replace(/App$/, "")),
    path.join(root, folder, name.replace(/Example$/, "")),
  ]);
  return candidates.find((value) => fs.existsSync(value)) || null;
}

const sourceRoots = [];
if (sourceArgument) {
  for (const value of sourceArgument.split(path.delimiter)) {
    const resolved = path.resolve(root, value);
    if (fs.existsSync(resolved)) sourceRoots.push(resolved);
  }
} else {
  const productRoot = productDirectory(product);
  if (productRoot) sourceRoots.push(productRoot);
}
// Core source is included for CSS vocabulary and feature wrappers, but the
// product source remains the authority for optional reachability decisions.
const baseFrameworkRoots = [
  path.join(root, "Sources", "SwiftUIWebCore"),
  path.join(root, "Sources", "SwiftUIWebFeatures"),
  path.join(root, "Sources", "SwiftUIWebBrowser")
];
// The framework vocabulary is Core, Features and Browser; the optional renderer targets join
// only when the product reaches their feature (`optionalFrameworkRoots` below).
// `--framework-source` may name a whole framework `Sources` directory (the
// consumer-package form); it is narrowed to those targets instead of being walked
// entirely, so Charts/MapKit/AVFoundation styles never ride along with a text-only app.
const frameworkSourceDirectories = [];
if (frameworkSourceArgument) {
  for (const value of frameworkSourceArgument.split(path.delimiter)) {
    const resolved = path.resolve(root, value);
    if (fs.existsSync(resolved)) frameworkSourceDirectories.push(resolved);
  }
}
const frameworkTargetDirectory = (directory, target) => {
  const candidate = path.basename(directory) === target ? directory : path.join(directory, target);
  return fs.existsSync(candidate) && path.basename(candidate) === target ? candidate : null;
};
for (const directory of frameworkSourceDirectories) {
  for (const target of ["SwiftUIWebCore", "SwiftUIWebFeatures", "SwiftUIWebBrowser"]) {
    const candidate = frameworkTargetDirectory(directory, target);
    if (candidate && !baseFrameworkRoots.includes(candidate)) baseFrameworkRoots.push(candidate);
  }
}

// Asset payloads (especially JSON fixtures) are not application reachability
// evidence. Only executable/template/style sources participate in feature
// detection; assets are considered separately by the provenance pass below.
// `--source` may include a fixture's shared Assets directory so the later
// provenance pass can retain static files.  Those files are payloads, not
// executable reachability evidence: a MapLibre contract stub (or a CSS
// comment mentioning `Map`) must not make every release appear to use the map
// backend.  Keep application-owned source trees authoritative while leaving
// asset retention to the explicit/manifest path below.
const applicationFiles = sourceRoots.flatMap(walk).filter((file) =>
  !file.split(path.sep).includes("Assets") &&
  /\.(swift|js|ts|tsx|css|html)$/.test(file)
);

// Comments are not reachability evidence. Preserve quoted strings while
// removing line/block comments so a documentation example mentioning Map,
// URLSession, or WebMount cannot pull an optional helper into a release.
function stripComments(value) {
  let output = "";
  let state = "code";
  let escaped = false;
  for (let index = 0; index < value.length; index += 1) {
    const character = value[index];
    const next = value[index + 1];
    const tripleQuote = value.slice(index, index + 3) === '"""';
    if (state === "line") {
      if (character === "\n") { state = "code"; output += character; }
      else output += " ";
      continue;
    }
    if (state === "block") {
      if (character === "*" && next === "/") { state = "code"; output += "  "; index += 1; }
      else output += character === "\n" ? "\n" : " ";
      continue;
    }
    if (state === "string") {
      if (tripleQuote) {
        // Swift multiline literals may contain comment-looking text and
        // feature names. Preserve the complete literal as evidence rather
        // than stripping its contents and risking an unsafe false negative.
        output += '"""';
        state = "multiline";
        index += 2;
        continue;
      }
      output += character;
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === '"') state = "code";
      continue;
    }
    if (state === "multiline") {
      output += tripleQuote ? '"""' : character;
      if (tripleQuote) {
        state = "code";
        index += 2;
      }
      continue;
    }
    if (state === "single") {
      output += character;
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === "'") state = "code";
      continue;
    }
    if (state === "template") {
      // JavaScript/TypeScript template literals can contain `//` and `/*`
      // as plain text. Keep them opaque for the same conservative reason as
      // Swift strings.
      output += character;
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === "`") state = "code";
      continue;
    }
    if (character === "/" && next === "/") { state = "line"; output += "  "; index += 1; continue; }
    if (character === "/" && next === "*") { state = "block"; output += "  "; index += 1; continue; }
    if (tripleQuote) {
      output += '"""';
      state = "multiline";
      index += 2;
      continue;
    }
    if (character === '"') state = "string";
    else if (character === "'") state = "single";
    else if (character === "`") state = "template";
    output += character;
  }
  return output;
}

const applicationText = applicationFiles.map((file) => stripComments(readText(file))).join("\n");

const rules = {
  // `Image(systemName:)` is rendered by the icon adapter and must not pull
  // the image loader. The negative lookahead still keeps all source/asset and
  // AsyncImage initializers reachable.
  // `Label(_, image:)` loads an asset image exactly like `Image(_)`; the lookbehind keeps
  // `systemImage:` (an icon-adapter symbol) out of the rule.
  images: /(?:\bAsyncImage\s*\(|\bImage\s*\(\s*(?!systemName\s*:|systemImage\s*:)|\bLabel\s*\([^\n]*(?<![A-Za-z])image\s*:)/.test(applicationText),
  adaptiveMedia: /\b(?:AVPlayer|AVAsset|AVURLAsset|VideoPlayer)\b/.test(applicationText),
  maps: /(?:MapLibre|\bMap\s*\(|MapProvider|Marker\s*\(|MapCameraPosition)/.test(applicationText),
  charts: /(?:\bChart\s*\(|BarMark|LineMark|PointMark|AreaMark|RuleMark)/.test(applicationText),
  datePickers: /(?:\bDatePicker\s*\(|\bMultiDatePicker\s*\()/.test(applicationText),
  webView: /(?:\bWebView\s*\(|WebViewConfiguration|WebContent)/.test(applicationText),
  // Include the presentation modifier as well as the labelled picker/item;
  // an application may use only `.photosPicker(...)` and still needs the
  // browser's media-input binding retained in a release.
  photos: /(?:PhotosPicker|PhotosPickerItem|\.photosPicker\s*\()/.test(applicationText),
  notifications: /(?:WebPush|WebNotification|requestAuthorization\s*\()/.test(applicationText),
  location: /(?:CLLocation|CLLocationCoordinate2D|LocationManager|LocationAccuracy)/.test(applicationText),
  webMount: /(?:WebMount|WebElementHandle|webMount|data-web-mount)/.test(applicationText),
  paste: /\bPasteButton\s*\(/.test(applicationText),
  canvas: /\b(?:Canvas|GraphicsContext|ResolvedText)\b/.test(applicationText),
  meshGradient: /\bMeshGradient\b/.test(applicationText),
  lazyCollections: /\b(?:LazyVStack|LazyHStack|LazyVGrid|LazyHGrid|ForEach|List|OutlineGroup)\b/.test(applicationText),
  geometry: /\b(?:GeometryReader|ScrollView|Layout|AnyLayout)\b/.test(applicationText),
  navigation: /\b(?:NavigationStack|NavigationView|NavigationLink|TabView|toolbar|sheet|fullScreenCover)\b/.test(applicationText),
  // `.draggable(_)` is `onDrag` for a Transferable value (DragDrop.swift).
  dragDrop: /(?:onDrag|onDrop|dropDestination|\.draggable\s*\(|Transferable)/.test(applicationText),
  networking: /(?:\bURLSession\b|\bURLRequest\b|\bURLComponents\b|\bWebSocket\b|NetworkRuntime|NetworkError|data\s*\(from:)/.test(applicationText),
  storage: /(?:@AppStorage|@SceneStorage|WebIndexedDB|StorageRuntime|UserDefaults|IndexedDB)/.test(applicationText)
};

const dynamic = {
  symbols: /(?:Image|Label|ContentUnavailableView)\s*\([^\n]*system(?:Name|Image)\s*:\s*(?!\s*")/.test(applicationText),
  assets: /(?:\bImage\s*\(\s*(?!\s*"|systemName\s*:|systemImage\s*:)[A-Za-z_][\w.]*(?:\s*[,\)])|Bundle\s*\.\s*(?:module|main)|url\s*\(\s*[^"'`)]*\$\{|(?:forResource|resourceURL|urlForResource|imageName|fontName|workerURL)\s*:\s*(?!\s*"))/i.test(applicationText),
  css: /(?:cssClass|htmlAttribute|className|rawHTML)/.test(applicationText)
};
// Labelled image initializers can hide a dynamic resource name after other
// arguments (for example `Image(name: imageName, bundle: bundle)`). Keep the
// complete asset set in that case; only a quoted literal is statically safe.
if (/\bImage\s*\([^\n)]*\b(?:name|resource|url|decorative)\s*:\s*(?!\s*")/i.test(applicationText)) {
  dynamic.assets = true;
}

const explicit = readJSON(explicitManifestPath) || (() => {
  const local = sourceRoots.map((value) => path.join(value, "Web", "release-assets.json"))
    .find((value) => fs.existsSync(value));
  return readJSON(local);
})();

if (explicit) {
  if (explicit.features) {
    // The original manifest format used an array (`["maps"]`), while
    // feature workspaces commonly describe capabilities as an object
    // (`{"maps": true}`). Accept both without treating arbitrary values as
    // proof of reachability.
    const featureNames = Array.isArray(explicit.features)
      ? explicit.features
      : Object.entries(explicit.features)
        .filter(([, reachable]) => reachable === true)
        .map(([feature]) => feature);
    for (const feature of featureNames) if (feature in rules) rules[feature] = true;
  }
  if (explicit.dynamic === true) dynamic.assets = true;
  if (explicit.dynamicSymbols === true) dynamic.symbols = true;
}

// Optional renderer targets contribute semantic classes and static sidecar
// assets only when the product reaches their corresponding SwiftUI feature.
// Keeping these roots out of the source graph is what prevents, for example,
// map/video/chart styles from inflating a text-only release.
const optionalFrameworkRoots = {
  adaptiveMedia: ["Sources/SwiftUIWebAVFoundation", "Sources/SwiftUIWebAVKit"],
  maps: ["Sources/SwiftUIWebMapKit"],
  charts: ["Sources/SwiftUIWebCharts"],
  photos: ["Sources/SwiftUIWebPhotosUI"],
  notifications: ["Sources/SwiftUIWebUserNotifications"],
  location: ["Sources/SwiftUIWebCoreLocation"]
};
const frameworkRoots = [...baseFrameworkRoots];
for (const [feature, roots] of Object.entries(optionalFrameworkRoots)) {
  if (!rules[feature]) continue;
  for (const relative of roots) {
    const resolved = path.join(root, relative);
    if (fs.existsSync(resolved)) frameworkRoots.push(resolved);
    for (const directory of frameworkSourceDirectories) {
      const candidate = frameworkTargetDirectory(directory, path.basename(relative));
      if (candidate && !frameworkRoots.includes(candidate)) frameworkRoots.push(candidate);
    }
  }
}

const literalSymbols = new Set();
for (const match of applicationText.matchAll(/(?:systemName|systemImage)\s*:\s*"([^"]+)"/g)) {
  literalSymbols.add(match[1]);
}

// The adaptive TabView chrome has built-in icons (a sidebar toggle, and a mobile menu button that
// opens and closes) even when tabs declare no SF Symbols. SwiftUIWebCore/Navigation.swift emits it
// only for `style == .sidebarAdaptable`, so the trigger is that style, spelled as the identifier or
// its raw value, or any `.tabViewStyle(...)` argument this scan cannot read (a variable or a
// custom style), which may resolve to it. A TabView with the default or page style emits none of it.
const readableTabViewStyle = /\.tabViewStyle\s*\(\s*\.(?:automatic|page|tabBarOnly|grouped)\b/g;
const tabViewStyleCalls = applicationText.match(/\.tabViewStyle\s*\(/g) || [];
const unreadableTabViewStyle = tabViewStyleCalls.length > (applicationText.match(readableTabViewStyle) || []).length +
  (applicationText.match(/\.tabViewStyle\s*\(\s*\.sidebarAdaptable\b/g) || []).length;
if (/\bsidebarAdaptable\b|["']sidebar-adaptable["']/.test(applicationText) || unreadableTabViewStyle) {
  for (const symbol of ["sidebar.left", "line.3.horizontal", "xmark"]) literalSymbols.add(symbol);
}

// A conditional expression made entirely of literals is just as safe as a
// literal call. This handles common SwiftUI state-driven icon changes without
// retaining the entire Lucide catalog.
for (const match of applicationText.matchAll(/(?:systemName|systemImage)\s*:\s*([^,\)\n]+)/g)) {
  const expression = match[1];
  if (!expression.includes("?") || !expression.includes(":")) continue;
  const values = [...expression.matchAll(/"([^"]+)"/g)].map((value) => value[1]);
  if (values.length >= 2) values.forEach((value) => literalSymbols.add(value));
}

// Detect finite computed `symbol` properties (for example an enum's switch
// over its CaseIterable cases). This is intentionally narrow: unknown
// expressions remain dynamic and therefore retain the complete compatibility
// catalog. A finite property is evidence only for the corresponding property
// name, never for arbitrary String values.
const finiteSymbolProperties = new Map();
const nonFiniteSymbolProperties = new Set();
for (const match of applicationText.matchAll(/(?:var|let)\s+(\w+)\s*:\s*String\s*\{([\s\S]*?)\n\s*\}/g)) {
  const body = match[2];
  // Two types may declare a property with the same name; a use site cannot be
  // attributed to one of them, so any non-finite definition poisons the name.
  if (!/\bswitch\b/.test(body) || /return\s+(?!")/.test(body)) { nonFiniteSymbolProperties.add(match[1]); continue; }
  // Single-expression switch arms (`case .home: "house"`) are literal returns
  // too; any arm whose value is not a bare string literal keeps the property
  // dynamic.
  const arms = [...body.matchAll(/^\s*(?:case\b[^\n]*?|default)\s*:[ \t]*(\S[^\n]*)?$/gm)].map((arm) => (arm[1] || "").trim());
  if (arms.some((value) => value !== "" && !/^"[^"\\]*"$/.test(value) && !/^return\s+"[^"\\]*"$/.test(value))) {
    nonFiniteSymbolProperties.add(match[1]);
    continue;
  }
  const values = [...body.matchAll(/(?:return\s+|:[ \t]*)"([^"]+)"[ \t]*$/gm)].map((value) => value[1]);
  if (!values.length) continue;
  const known = finiteSymbolProperties.get(match[1]) || new Set();
  values.forEach((value) => known.add(value));
  finiteSymbolProperties.set(match[1], known);
}
for (const name of nonFiniteSymbolProperties) finiteSymbolProperties.delete(name);
const unresolvedDynamicSymbols = [];
for (const match of applicationText.matchAll(/(?:Image|Label|ContentUnavailableView)\s*\([^\n]*system(?:Name|Image)\s*:\s*([^,\)\n]+)/g)) {
  const expression = match[1].trim();
  if (expression.startsWith('"')) continue;
  const ternaryValues = [...expression.matchAll(/"([^"]+)"/g)].map((value) => value[1]);
  if (expression.includes("?") && expression.includes(":") && ternaryValues.length >= 2) {
    ternaryValues.forEach((value) => literalSymbols.add(value));
    continue;
  }
  const property = expression.split(".").pop();
  const values = finiteSymbolProperties.get(property);
  if (values) values.forEach((value) => literalSymbols.add(value));
  else unresolvedDynamicSymbols.push(expression);
}
dynamic.symbols = unresolvedDynamicSymbols.length > 0;

// Symbols the framework draws itself (Views.swift glyph table, Navigation.swift search
// role) never appear in application source, so the literal set cannot see them. They
// join the icon subset whenever the icon adapter ships at all; an app that ships no
// icon asset keeps its text glyph fallbacks and pays nothing.
const frameworkChromeSymbols = ["checkmark", "xmark", "chevron.left", "magnifyingglass"];
if (literalSymbols.size > 0 || dynamic.symbols) for (const symbol of frameworkChromeSymbols) literalSymbols.add(symbol);
// A VideoPlayer draws its own AVKit-style controls (SwiftUIWebAVKit/AVKitControls.swift) with these symbols.
if (/\bVideoPlayer\s*\(/.test(applicationText)) {
  for (const symbol of ["play.fill", "pause.fill", "arrow.counterclockwise", "gobackward.10", "goforward.10", "speaker.wave.2.fill",
    "speaker.fill", "speaker.slash.fill", "arrow.up.left.and.arrow.down.right", "arrow.down.right.and.arrow.up.left", "pip.enter",
    "pip.exit", "exclamationmark.triangle.fill", "captions.bubble", "hifispeaker"]) literalSymbols.add(symbol);
}

// True when `candidate` is strictly inside `directory`; `retain` paths come from a manifest a package can write.
const isInside = (directory, candidate) => {
  const relative = path.relative(directory, candidate);
  return relative !== "" && relative.split(path.sep)[0] !== ".." && !path.isAbsolute(relative);
};
const requiredAssets = Array.isArray(explicit?.retain) ? explicit.retain.slice() : [];
const assetSourceByDestination = new Map();
for (const asset of requiredAssets) {
  if (path.isAbsolute(asset) || !isInside(root, path.resolve(root, asset))) throw new Error(`retain entry escapes the root: ${asset}`);
  const source = path.resolve(root, asset);
  // The file a retain entry names after its links are followed must be inside the root too: an in-tree link to a file
  // outside it would otherwise be copied into the bundle.
  if (fs.existsSync(source) && !isInside(fs.realpathSync(root), fs.realpathSync(source))) throw new Error(`retain entry escapes the root through a link: ${asset}`);
  if (fs.existsSync(source) && fs.statSync(source).isFile()) assetSourceByDestination.set(asset, source);
}
const needsFeatureLoader = rules.images || rules.adaptiveMedia || rules.maps || rules.charts || rules.notifications || rules.location || rules.webMount;

const runtime = {
  initial: [],
  lazy: []
};
if (needsFeatureLoader) runtime.initial.push("feature-loader.js");
if (rules.images) runtime.lazy.push("image-pipeline.js");
if (rules.adaptiveMedia) runtime.lazy.push("avfoundation.js", "shaka-loader.js");
if (literalSymbols.size > 0 || dynamic.symbols) runtime.initial.push("icon-adapter.js");
if (rules.meshGradient) runtime.initial.push("mesh-gradient.js");

// The browser adapter is one SwiftPM target for source compatibility, but its
// release compilation can still discard feature-owned implementation files.
// Keep the flag list in the manifest so build scripts and CI can verify that
// every compile-time gate has corresponding reachability evidence.
const swiftDefines = ["SWIFTUIWEB_RELEASE"];
const compileFeatureFlags = {
  images: "SWIFTUIWEB_RELEASE_HAS_IMAGES",
  photos: "SWIFTUIWEB_RELEASE_HAS_PHOTOS",
  dragDrop: "SWIFTUIWEB_RELEASE_HAS_DRAGDROP",
  canvas: "SWIFTUIWEB_RELEASE_HAS_CANVAS",
  meshGradient: "SWIFTUIWEB_RELEASE_HAS_MESH_GRADIENT",
  networking: "SWIFTUIWEB_RELEASE_HAS_NETWORKING",
  storage: "SWIFTUIWEB_RELEASE_HAS_STORAGE"
};
for (const [feature, flag] of Object.entries(compileFeatureFlags)) {
  if (rules[feature]) swiftDefines.push(flag);
}

const browserBindings = [];
if (rules.geometry || rules.lazyCollections) browserBindings.push("geometry", "intersection-observer");
if (rules.dragDrop) browserBindings.push("drag-drop", "transferable");
if (rules.canvas) browserBindings.push("canvas");
if (rules.meshGradient) browserBindings.push("mesh-gradient");
if (rules.webMount || rules.adaptiveMedia || rules.maps) browserBindings.push("web-mount");
if (rules.navigation) browserBindings.push("history", "navigation");
if (rules.images) browserBindings.push("image");
if (rules.networking) browserBindings.push("fetch", "websocket");
if (rules.storage) browserBindings.push("storage");

const allFiles = [...sourceRoots, ...frameworkRoots].flatMap(walk);
const assetExtensions = /\.(?:png|jpe?g|gif|webp|avif|svg|woff2?|ttf|otf|json|worker\.js)$/i;
const assetFiles = allFiles.filter((file) => {
  if (assetExtensions.test(file)) return true;
  // A package's Assets directory may contain a provider contract or a
  // browser-side feature module. Treat those files as static payloads only
  // when they live in Assets; generated browser modules remain outside
  // this closed-world candidate set and is therefore never guessed dead.
  return file.split(path.sep).includes("Assets") && /\.(?:css|js)$/i.test(file);
});
const assetFileSet = new Set(assetFiles);

// Keep only literal references that can be resolved to a file in the
// application/framework source roots. A source tree may contain many
// screenshots, fonts or workers for unrelated examples; copying every file
// would defeat whole-app asset reachability. `dynamic.assets` deliberately
// widens this back to the complete discovered set because a runtime Bundle or
// resource lookup cannot be proven statically safe to prune.
const assetByRelativePath = new Map(assetFiles.map((file) => [
  path.relative(root, file).replaceAll(path.sep, "/"), file
]));
const assetByBasename = new Map();
for (const file of assetFiles) {
  const basename = path.basename(file);
  const matches = assetByBasename.get(basename) || [];
  matches.push(file);
  assetByBasename.set(basename, matches);
}
const referencedAssetFiles = new Set();
const assetReferencePattern = /(?:["'`]|url\(\s*["']?)((?:[^"'`()\s]|\\.)+\.(?:png|jpe?g|gif|webp|avif|svg|woff2?|ttf|otf|json|worker\.js|js|css))(?:["'`]|["']?\s*\))/gi;
for (const file of allFiles.filter((value) => /\.(?:swift|json|js|ts|tsx|css|html)$/i.test(value))) {
  const text = readText(file);
  for (const match of text.matchAll(assetReferencePattern)) {
    const reference = match[1].replaceAll("\\\\", "/");
    const candidates = [
      path.resolve(path.dirname(file), reference),
      path.resolve(root, reference.replace(/^\.\//, ""))
    ];
    for (const candidate of candidates) {
      if (assetFileSet.has(candidate)) referencedAssetFiles.add(candidate);
    }
    // A root-relative literal may be written with a leading slash in HTML;
    // compare its normalized repository path without trusting arbitrary URLs.
    const relative = reference.replace(/^\/+/, "");
    if (assetByRelativePath.has(relative)) referencedAssetFiles.add(assetByRelativePath.get(relative));
    if (!relative.includes("/")) {
      const basenameMatches = assetByBasename.get(relative);
      // A duplicate basename cannot be resolved safely without a package
      // manifest, so preserve the complete dynamic asset set below.
      if (basenameMatches && basenameMatches.length === 1) referencedAssetFiles.add(basenameMatches[0]);
      else if (basenameMatches && basenameMatches.length > 1) dynamic.assets = true;
    }
  }
}
const reachableAssetFiles = dynamic.assets ? assetFiles : [...referencedAssetFiles];
const fixtureAssetRoot = sourceRoots.find((value) => path.basename(value) === "Assets");
function assetDestination(file) {
  // Browser fixtures copy their package Assets directory beside index.js. A
  // basename destination preserves the normal `Image("name.svg")` contract;
  // regular applications retain repository-relative paths so nested Web/
  // assets remain addressable without a special convention.
  if (fixtureAssetRoot && file.startsWith(`${fixtureAssetRoot}${path.sep}`)) return path.basename(file);
  return path.relative(root, file).replaceAll(path.sep, "/");
}
// Keep the complete candidate set in the proof. The bundle pruner uses this
// list to distinguish an unreferenced application asset (safe to delete) from
// an unrelated configuration JSON file (unknown, therefore kept).
const candidateAssetDestinations = [...new Set(assetFiles.map(assetDestination))].sort();
for (const assetFile of reachableAssetFiles) {
  const asset = assetDestination(assetFile);
  if (!requiredAssets.includes(asset)) requiredAssets.push(asset);
  assetSourceByDestination.set(asset, assetFile);
}

const manifest = {
  version: 1,
  product,
  configuration: argument("--configuration", "release"),
  // Evidence for optional features comes only from sourceRoots; frameworkRoots
  // contribute CSS vocabulary and asset discovery, never feature reachability.
  sourceRoots: sourceRoots.map((value) => path.relative(root, value)),
  frameworkRoots: frameworkRoots.map((value) => path.relative(root, value)),
  features: rules,
  browserBindings: [...new Set(browserBindings)],
  swiftDefines,
  runtime,
  icons: {
    symbols: [...literalSymbols].sort(),
    dynamic: dynamic.symbols,
    asset: literalSymbols.size > 0 || dynamic.symbols ? "icon-adapter.js" : null
  },
  css: {
    sourceRoots: [...new Set([...frameworkRoots, ...sourceRoots].map((value) => path.relative(root, value)))],
    dynamic: dynamic.css,
    proof: {
      dynamicReferenceDetected: dynamic.css,
      // Only the explicit optional semantic rule table is eligible for the
      // CSS pass. Unknown application CSS is always retained.
      safeToPruneOptionalRules: !dynamic.css
    }
  },
  assets: {
    retain: requiredAssets.sort(),
    candidates: candidateAssetDestinations,
    files: requiredAssets.map((destination) => ({
      destination,
      source: assetSourceByDestination.has(destination)
        ? path.relative(root, assetSourceByDestination.get(destination)).replaceAll(path.sep, "/")
        : destination
    })),
    dynamic: dynamic.assets,
    proof: {
      staticReferences: [...referencedAssetFiles].map((file) => path.relative(root, file).replaceAll(path.sep, "/")).sort(),
      dynamicReferenceDetected: dynamic.assets,
      complete: !dynamic.assets
    }
  },
  proof: {
    sourceFiles: applicationFiles.map((file) => path.relative(root, file).replaceAll(path.sep, "/")).sort(),
    featureEvidence: Object.fromEntries(Object.entries(rules).map(([feature, reachable]) => [feature, {
      reachable,
      basis: reachable ? "application-source-or-explicit-manifest" : "no-application-source-use"
    }])),
    dynamicSymbols: dynamic.symbols,
    dynamicAssets: dynamic.assets,
    dynamicCSS: dynamic.css,
    safeToPruneUnlistedAssets: !dynamic.assets,
    safeToSubsetIcons: !dynamic.symbols,
    safeToPruneOptionalCSS: !dynamic.css
  },
  notes: [
    "Swift symbol reachability remains owned by the Swift optimizer and linker.",
    "Unknown dynamic asset and icon references are retained conservatively."
  ]
};

fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, JSON.stringify(manifest, null, 2) + "\n");

if (bundleDir) {
  fs.mkdirSync(bundleDir, { recursive: true });
  const tools = path.join(root, "Tools");
  for (const file of [...runtime.initial, ...runtime.lazy]) {
    const source = path.join(tools, file);
    if (fs.existsSync(source)) fs.copyFileSync(source, path.join(bundleDir, file));
  }
  for (const asset of requiredAssets) {
    const source = assetSourceByDestination.get(asset) || path.join(root, asset);
    const destination = path.join(bundleDir, asset);
    if (path.isAbsolute(asset) || !isInside(bundleDir, destination)) throw new Error(`asset destination escapes the bundle: ${asset}`);
    if (!fs.existsSync(source) || !fs.statSync(source).isFile()) continue;
    // Checked before any folder is made: the nearest folder that exists, links followed, must be the bundle's.
    let existing = path.dirname(destination);
    while (!fs.existsSync(existing)) existing = path.dirname(existing);
    const bundleReal = fs.realpathSync(bundleDir), existingReal = fs.realpathSync(existing);
    if (existingReal !== bundleReal && !isInside(bundleReal, existingReal)) throw new Error(`asset destination escapes the bundle through a link: ${asset}`);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    // The destination folder, with its links followed, is still the bundle's, and no link stands where the file goes.
    if (!isInside(fs.realpathSync(bundleDir), path.join(fs.realpathSync(path.dirname(destination)), path.basename(destination)))) throw new Error(`asset destination escapes the bundle through a link: ${asset}`);
    if (fs.existsSync(destination) && fs.lstatSync(destination).isSymbolicLink()) fs.unlinkSync(destination);
    fs.copyFileSync(source, destination);
  }
}

console.log(
  `Release manifest written: ${output} ` +
    `(product=${product}, sources=${applicationFiles.length}, ` +
    `frameworkRoots=${frameworkRoots.length}, assets=${requiredAssets.length}, ` +
    `dynamicAssets=${dynamic.assets}, dynamicCSS=${dynamic.css})`
);
