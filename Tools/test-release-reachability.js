#!/usr/bin/env bun
/* Deterministic regression tests for conservative release reachability. */
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const zlib = require("zlib");
const { spawnSync } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
const PLANNER = path.join(ROOT, "Tools", "release-reachability.js");
const PRUNER = path.join(ROOT, "Tools", "prune-release-assets.js");
const PRUNE_CSS = path.join(ROOT, "Tools", "prune-release-css.js");
const REPORT_SIZE = path.join(ROOT, "Tools", "report-release-size.js");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function run(command, args) {
  const result = spawnSync(command, args, { cwd: ROOT, encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`${path.basename(command)} failed (${result.status ?? "signal"}): ${result.stderr || result.stdout}`);
  }
  return result.stdout;
}

function write(file, contents) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, contents);
}

function walk(directory) {
  const files = [];
  if (!fs.existsSync(directory)) return files;
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...walk(file));
    else if (entry.isFile()) files.push(file);
  }
  return files;
}

function sizes(directory) {
  const value = { raw: 0, gzip: 0, brotli: 0 };
  for (const file of walk(directory)) {
    const bytes = fs.readFileSync(file);
    value.raw += bytes.length;
    value.gzip += zlib.gzipSync(bytes, { level: 9, mtime: 0 }).length;
    value.brotli += zlib.brotliCompressSync(bytes, {
      params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 11 }
    }).length;
  }
  return value;
}

function fixtureSource(dynamic) {
  return `import SwiftUIWeb\nimport SwiftUIWebBrowser\n\n// Map, URLSession, and WebMount are documentation words only.\n/* Calendar and @AppStorage are also not used by this fixture. */\nprivate struct Content: View {\n  var body: some View {\n    ${dynamic ? 'let name = "used.svg"\n    Image(name)' : 'Image("used.svg")'}\n  }\n}\n`;
}

function plan(source, assets, output) {
  const stdout = run(process.execPath, [
    PLANNER,
    "--root", ROOT,
    "--product", "ReachabilityRegression",
    "--configuration", "release",
    "--source", `${source}${path.delimiter}${assets}`,
    "--output", output
  ]);
  assert(stdout.includes("Release manifest written:"), "planner should report the manifest path concisely");
  assert(!stdout.includes('"sourceFiles"'), "planner must not stream the full reachability manifest to stdout");
  return JSON.parse(fs.readFileSync(output, "utf8"));
}

function makeBundle(directory, files) {
  fs.mkdirSync(directory, { recursive: true });
  for (const [relative, contents] of Object.entries(files)) write(path.join(directory, relative), contents);
}

function main() {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "swiftuiweb-reachability-"));
  try {
    const source = path.join(temporary, "Sources", "ReachabilityRegression");
    const assets = path.join(temporary, "Assets");
    write(path.join(source, "main.swift"), fixtureSource(false));
    write(path.join(assets, "used.svg"), "<svg/>\n");
    write(path.join(assets, "unused.svg"), "<svg id=unused/>\n");
    write(path.join(assets, "unused.json"), "{\"unused\":true}\n");
    write(path.join(assets, "provider.js"), "export function install() {}\n");
    write(path.join(assets, "provider.css"), ".provider-host { display: block; }\n");
    const manifestPath = path.join(temporary, "manifest.json");
    const manifest = plan(source, assets, manifestPath);

    assert(manifest.features.images === true, "literal Image did not reach the image feature");
    for (const feature of ["maps", "networking", "storage", "adaptiveMedia", "charts", "webMount"]) {
      assert(manifest.features[feature] === false, `comment-only feature '${feature}' was marked reachable`);
    }
    assert(manifest.runtime.lazy.includes("image-pipeline.js"), "image helper was not classified as lazy");
    assert(!manifest.runtime.lazy.includes("avfoundation.js"), "unused media helper was retained");
    assert(manifest.assets.retain.includes("used.svg"), "literal basename asset was not retained");
    assert(manifest.assets.candidates.includes("unused.json"), "asset candidate proof omitted an unreferenced asset");
    assert(!manifest.assets.retain.includes("unused.svg"), "unreferenced asset was retained");
    assert(manifest.proof.safeToPruneUnlistedAssets === true, "static fixture did not receive a prune proof");

    // Provider-side JavaScript/CSS in an Assets directory follows the same
    // proof rule as images: retain a literal reference, but do not copy an
    // unreferenced provider payload into every release fixture.
    const providerSource = path.join(temporary, "Sources", "ProviderRegression");
    write(path.join(providerSource, "main.swift"), [
      "import SwiftUIWeb",
      "let providerScript = \"/provider.js\"",
      "let providerStylesheet = \"/provider.css\""
    ].join("\n") + "\n");
    const providerManifestPath = path.join(temporary, "provider-manifest.json");
    const providerManifest = plan(providerSource, assets, providerManifestPath);
    assert(providerManifest.assets.candidates.includes("provider.js"), "provider JavaScript was not included in the asset proof");
    assert(providerManifest.assets.candidates.includes("provider.css"), "provider CSS was not included in the asset proof");
    assert(providerManifest.assets.retain.includes("provider.js"), "literal provider JavaScript was not retained");
    assert(providerManifest.assets.retain.includes("provider.css"), "literal provider CSS was not retained");

    const iconSource = path.join(temporary, "IconOnly");
    write(path.join(iconSource, "main.swift"), 'import SwiftUIWeb\nlet icon = Image(systemName: "heart.fill")\n');
    const iconManifestPath = path.join(temporary, "icon-manifest.json");
    const iconManifest = plan(iconSource, assets, iconManifestPath);
    assert(iconManifest.features.images === false, "system-only Image pulled the image pipeline");
    assert(iconManifest.icons.symbols.includes("heart.fill"), "literal SF Symbol was not retained");
    assert(iconManifest.runtime.initial.includes("icon-adapter.js"), "icon helper was not retained");

    const bundle = path.join(temporary, "bundle");
    makeBundle(bundle, {
      "index.html": "<!doctype html>",
      "index.js": "export function init() {}",
      "instantiate.js": "export {}",
      "runtime.js": "export {}",
      "package.json": "{}",
      "styles.css": ".text-run {}",
      "feature-loader.js": "feature loader",
      "image-pipeline.js": "image helper",
      "avfoundation.js": "unused media helper",
      "icon-adapter.js": "unused icon helper",
      "used.svg": "<svg/>",
      "unused.svg": "<svg id=unused/>",
      "unused.json": "{\"unused\":true}",
      "provider.js": "export function install() {}\n",
      "provider.css": ".provider-host { display: block; }\n",
      "unknown.bin": "keep unknown files",
      "generated-config.json": "{\"keep\":true}"
    });
    fs.copyFileSync(manifestPath, path.join(bundle, "release-manifest.json"));
    const before = sizes(bundle);
    run(process.execPath, [PRUNER, "--bundle", bundle]);
    const after = sizes(bundle);
    assert(fs.existsSync(path.join(bundle, "used.svg")), "pruner removed a proven static asset");
    assert(!fs.existsSync(path.join(bundle, "unused.svg")), "pruner kept an unreferenced static asset");
    assert(!fs.existsSync(path.join(bundle, "unused.json")), "pruner kept an unreferenced JSON asset");
    assert(!fs.existsSync(path.join(bundle, "avfoundation.js")), "pruner kept an unused helper");
    assert(!fs.existsSync(path.join(bundle, "icon-adapter.js")), "pruner kept an unused icon helper");
    // The original static fixture does not reference provider payloads, so
    // the closed-world pruner must remove both formats when proof is complete.
    assert(!fs.existsSync(path.join(bundle, "provider.js")), "pruner kept an unreferenced provider JavaScript asset");
    assert(!fs.existsSync(path.join(bundle, "provider.css")), "pruner kept an unreferenced provider CSS asset");
    assert(fs.existsSync(path.join(bundle, "unknown.bin")), "pruner deleted an unknown file without proof");
    assert(fs.existsSync(path.join(bundle, "generated-config.json")), "pruner deleted an unknown generated JSON file");
    assert(after.raw < before.raw && after.gzip < before.gzip && after.brotli < before.brotli,
      "pruning did not reduce raw/gzip/Brotli bundle size");

    const sizeReportPath = path.join(bundle, "test-release-size.json");
    run(process.execPath, [REPORT_SIZE, "--bundle", bundle, "--manifest", path.join(bundle, "release-manifest.json"), "--output", sizeReportPath]);
    const sizeReport = JSON.parse(fs.readFileSync(sizeReportPath, "utf8"));
    assert(sizeReport.files.some(entry => entry.file === "generated-config.json") === true,
      "release size report omitted an unknown JSON resource");

    // Optional semantic CSS is removed only when every selector in a rule is
    // proven optional. Mixed selectors remain intact so a shared rule cannot
    // be lost for a reachable feature.
    write(path.join(bundle, "styles.css"), [
      ".vstack{display:flex}",
      ".date-picker{display:flex}",
      ".mapkit-view,.data-chart{display:block}",
      ".mapkit-view,.web-view{display:block}"
    ].join(""));
    run(process.execPath, [PRUNE_CSS, "--css", path.join(bundle, "styles.css"), "--manifest", path.join(bundle, "release-manifest.json")]);
    const prunedCSS = fs.readFileSync(path.join(bundle, "styles.css"), "utf8");
    assert(prunedCSS.includes("vstack"), "shared CSS was removed by semantic pruner");
    assert(!prunedCSS.includes("date-picker"), "unreachable date-picker CSS was retained");
    assert(!prunedCSS.includes("mapkit-view"), "unreachable map CSS was retained");

    const reachableMapManifestPath = path.join(bundle, "reachable-map-manifest.json");
    const reachableMapManifest = { ...manifest, features: { ...manifest.features, maps: true } };
    write(reachableMapManifestPath, JSON.stringify(reachableMapManifest));
    write(path.join(bundle, "mixed.css"), ".mapkit-view,.data-chart{display:block}");
    run(process.execPath, [PRUNE_CSS, "--css", path.join(bundle, "mixed.css"), "--manifest", reachableMapManifestPath]);
    assert(fs.readFileSync(path.join(bundle, "mixed.css"), "utf8").includes("mapkit-view"),
      "mixed CSS rule was removed despite a reachable selector");

    // A dynamic resource lookup widens the proof. The same pruner must then
    // retain every static asset rather than guessing which name can occur.
    const dynamicSource = path.join(temporary, "Dynamic", "Sources");
    write(path.join(dynamicSource, "main.swift"), fixtureSource(true));
    const dynamicManifestPath = path.join(temporary, "dynamic-manifest.json");
    const dynamicManifest = plan(dynamicSource, assets, dynamicManifestPath);
    assert(dynamicManifest.assets.dynamic === true, "dynamic Image lookup was treated as static");
    const dynamicBundle = path.join(temporary, "dynamic-bundle");
    makeBundle(dynamicBundle, {
      "index.html": "<!doctype html>",
      "index.js": "export {}",
      "instantiate.js": "export {}",
      "runtime.js": "export {}",
      "package.json": "{}",
      "styles.css": "",
      "used.svg": "<svg/>",
      "unknown.svg": "<svg id=unknown/>"
    });
    fs.copyFileSync(dynamicManifestPath, path.join(dynamicBundle, "release-manifest.json"));
    run(process.execPath, [PRUNER, "--bundle", dynamicBundle]);
    assert(fs.existsSync(path.join(dynamicBundle, "unknown.svg")), "dynamic asset was pruned without proof");

    // An external consumer is judged by its own code. The framework sources
    // (which mention MeshGradient, Canvas, onDrop, ...) only supply vocabulary,
    // so a consumer that never uses them must not get those features.
    const consumer = path.join(temporary, "Consumer", "Sources", "App");
    write(path.join(consumer, "main.swift"), [
      "import SwiftUIWeb",
      "enum Tab: String { case home, search",
      "  var symbol: String {",
      "    switch self {",
      '    case .home: "house"',
      '    case .search: "magnifyingglass"',
      "    }",
      "  }",
      "}",
      "struct Content: View {",
      "  var body: some View {",
      "    Image(systemName: Tab.home.symbol)",
      "    let _ = URLSession.shared",
      "  }",
      "}",
      ""
    ].join("\n"));
    const externalPath = path.join(temporary, "external.json");
    run(process.execPath, [
      PLANNER, "--root", ROOT, "--product", "ExternalConsumer", "--configuration", "release",
      "--source", consumer, "--framework-source", path.join(ROOT, "Sources"), "--output", externalPath
    ]);
    const external = JSON.parse(fs.readFileSync(externalPath, "utf8"));
    for (const feature of ["meshGradient", "canvas", "dragDrop", "photos", "maps", "charts"]) {
      assert(external.features[feature] === false, `framework-only mention of '${feature}' marked it reachable for an external consumer`);
    }
    assert(external.features.networking === true, "consumer URLSession use did not keep networking");
    assert(!external.swiftDefines.includes("SWIFTUIWEB_RELEASE_HAS_MESH_GRADIENT"), "mesh gradient define leaked from framework sources");
    assert(external.swiftDefines.includes("SWIFTUIWEB_RELEASE_HAS_NETWORKING"), "networking define missing");
    assert(!external.runtime.initial.includes("mesh-gradient.js"), "mesh gradient helper shipped without consumer use");
    assert(external.icons.dynamic === false && external.icons.symbols.includes("house") && external.icons.symbols.includes("magnifyingglass"),
      "finite implicit-return symbol property should resolve to literal icons");
    assert(external.frameworkRoots.some((value) => value.endsWith("SwiftUIWebCore")), "framework source was not recorded as vocabulary");
    assert(!external.frameworkRoots.some((value) => value.endsWith("Sources")), "the whole framework Sources directory was recorded instead of Core and Browser");
    // The conservative rule still holds: a consumer reference brings the feature back.
    write(path.join(consumer, "Gradient.swift"), "import SwiftUIWeb\nstruct G: View { var body: some View { MeshGradient(width: 2, height: 2, points: [], colors: []) } }\n");
    write(path.join(consumer, "Dynamic.swift"), "import SwiftUIWeb\nstruct D: View { let n: String\n var body: some View { Image(systemName: n) } }\n");
    run(process.execPath, [
      PLANNER, "--root", ROOT, "--product", "ExternalConsumer", "--configuration", "release",
      "--source", consumer, "--framework-source", path.join(ROOT, "Sources"), "--output", externalPath
    ]);
    const widened = JSON.parse(fs.readFileSync(externalPath, "utf8"));
    assert(widened.features.meshGradient === true, "consumer MeshGradient use did not enable the feature");
    assert(widened.icons.dynamic === true, "non-literal symbol did not fall back to the full icon catalog");

    // Rules added after the first reachability round: each construct must switch its
    // feature on from consumer code alone, with `--framework-source` pointing at the
    // whole framework `Sources` directory (the form external consumers use).
    const planFor = (name, source) => {
      const dir = path.join(temporary, name, "Sources", "App");
      write(path.join(dir, "main.swift"), source);
      const out = path.join(temporary, `${name}.json`);
      run(process.execPath, [
        PLANNER, "--root", ROOT, "--product", name, "--configuration", "release",
        "--source", dir, "--framework-source", path.join(ROOT, "Sources"), "--output", out
      ]);
      return JSON.parse(fs.readFileSync(out, "utf8"));
    };
    const draggable = planFor("Draggable", "import SwiftUIWeb\nstruct V: View { let item: Item\n var body: some View { Text(\"a\").draggable(item) } }\n");
    assert(draggable.features.dragDrop === true, "`.draggable(` alone did not enable dragDrop");
    assert(draggable.swiftDefines.includes("SWIFTUIWEB_RELEASE_HAS_DRAGDROP"), "`.draggable(` alone did not keep BrowserDragDrop compiled in");
    assert(draggable.browserBindings.includes("drag-drop"), "`.draggable(` alone did not keep the drag-drop binding");
    const hover = planFor("Hover", "import SwiftUIWeb\nstruct V: View { @State private var hovered = false\n var body: some View { Text(\"a\").onHover { hovered = $0 } } }\n");
    assert(hover.features.hover === true, "`.onHover` did not enable hover");
    assert(hover.swiftDefines.includes("SWIFTUIWEB_RELEASE_HAS_HOVER"), "`.onHover` did not keep the hover rules compiled in");
    assert(!draggable.swiftDefines.includes("SWIFTUIWEB_RELEASE_HAS_HOVER"), "an app without `onHover` kept the hover rules");
    const labelImage = planFor("LabelImage", "import SwiftUIWeb\nstruct V: View { var body: some View { Label(\"Logo\", image: \"logo\") } }\n");
    assert(labelImage.features.images === true, "`Label(_, image:)` did not enable the image loader");
    assert(labelImage.swiftDefines.includes("SWIFTUIWEB_RELEASE_HAS_IMAGES"), "`Label(_, image:)` did not keep image support compiled in");
    const labelSystem = planFor("LabelSystem", "import SwiftUIWeb\nstruct V: View { var body: some View { Label(\"Home\", systemImage: \"house\") } }\n");
    assert(labelSystem.features.images === false, "`Label(_, systemImage:)` pulled in the image loader");
    const chrome = ["checkmark", "xmark", "chevron.left", "magnifyingglass"];
    assert(chrome.every((symbol) => labelSystem.icons.symbols.includes(symbol)),
      "framework chrome symbols are missing from the icon subset of an app that ships icons");
    assert(labelSystem.icons.symbols.includes("house"), "the application's own symbol disappeared from the subset");
    // The adaptive TabView chrome draws its own sidebar toggle and mobile menu icons, but only for `.sidebarAdaptable`.
    const sidebar = ["sidebar.left", "line.3.horizontal", "xmark"];
    const adaptive = planFor("AdaptiveTabs", "import SwiftUIWeb\nstruct V: View { var body: some View { TabView { Text(\"a\").tabItem { Text(\"A\") } }.tabViewStyle(.sidebarAdaptable) } }\n");
    assert(sidebar.every((symbol) => adaptive.icons.symbols.includes(symbol)) && adaptive.runtime.initial.includes("icon-adapter.js"),
      "an app with `.tabViewStyle(.sidebarAdaptable)` did not get the chrome icons, or the icon helper, without declaring any symbol of its own");
    const rawStyle = planFor("RawStyleTabs", "import SwiftUIWeb\nstruct V: View { var body: some View { TabView { Text(\"a\") }.tabViewStyle(SidebarAdaptableTabViewStyle()) } }\n");
    assert(rawStyle.icons.symbols.includes("sidebar.left"), "the raw `sidebar-adaptable` spelling did not get the chrome icons");
    const variableStyle = planFor("VariableStyleTabs", "import SwiftUIWeb\nstruct V: View { let style: SomeStyle\n var body: some View { TabView { Text(\"a\") }.tabViewStyle(style) } }\n");
    assert(sidebar.every((symbol) => variableStyle.icons.symbols.includes(symbol)), "a style the scan cannot read must keep the chrome icons: it may be .sidebarAdaptable");
    const plainTabs = planFor("PlainTabs", "import SwiftUIWeb\nstruct V: View { var body: some View { TabView { Text(\"a\").tabItem { Label(\"A\", systemImage: \"house\") } }.tabViewStyle(.automatic) } }\n");
    assert(!plainTabs.icons.symbols.includes("sidebar.left") && !plainTabs.icons.symbols.includes("line.3.horizontal"),
      "a TabView that cannot be adaptive shipped the sidebar chrome icons");
    const textOnly = planFor("TextOnly", "import SwiftUIWeb\nstruct V: View { var body: some View { Text(\"hello\") } }\n");
    assert(textOnly.icons.symbols.length === 0 && !textOnly.runtime.initial.includes("icon-adapter.js"),
      "chrome symbols made a text-only app ship the icon adapter");
    // Optional framework targets join only through their feature, not through `--framework-source`.
    for (const target of ["SwiftUIWebCharts", "SwiftUIWebMapKit", "SwiftUIWebAVFoundation", "SwiftUIWebPhotosUI"]) {
      assert(!textOnly.frameworkRoots.some((value) => value.endsWith(target)), `${target} sources were scanned for a text-only app`);
    }
    assert(textOnly.frameworkRoots.some((value) => value.endsWith("SwiftUIWebCore")) && textOnly.frameworkRoots.some((value) => value.endsWith("SwiftUIWebBrowser")),
      "Core and Browser stopped being framework vocabulary");
    const charts = planFor("Charts", "import SwiftUIWeb\nimport SwiftUIWebCharts\nstruct V: View { var body: some View { Chart { BarMark(x: .value(\"a\", 1), y: .value(\"b\", 2)) } } }\n");
    assert(charts.frameworkRoots.some((value) => value.endsWith("SwiftUIWebCharts")), "Charts sources were not added for an app that uses Chart");

    console.log(JSON.stringify({
      status: "pass",
      staticManifest: {
        features: manifest.features,
        runtime: manifest.runtime,
        icons: manifest.icons,
        assets: manifest.assets,
        proof: manifest.proof
      },
      pruning: { before, after, rawSaved: before.raw - after.raw, gzipSaved: before.gzip - after.gzip, brotliSaved: before.brotli - after.brotli },
      dynamicAssetsRetained: true
    }, null, 2));
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

try { main(); }
catch (error) { console.error(`Release reachability regression failed: ${error.stack || error}`); process.exitCode = 1; }
