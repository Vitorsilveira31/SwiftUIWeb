#!/usr/bin/env bun
// Development loop for `swiftuiweb-run --watch`: build the app, serve it, and when a source file is saved rebuild
// and tell every open page to reload.
//
//   bun Tools/dev-watch.mjs --package-root <dir> --product <name> [--configuration debug] [--port N]
//
// What it does, in order:
//   1. builds once with the normal Embedded pipeline (Tools/run-browser.sh) into a build cache that lives between runs
//      (SWIFTUIWEB_DEV_CACHE), so the next build recompiles only what changed;
//   2. starts Tools/bun-server.ts with live reload on and serves the bundle;
//   3. watches the package and the framework sources; after a quiet moment it rebuilds and, on success, sends
//      "reload" (or "css" when only stylesheets changed, which swaps them in place); on failure the page keeps the last
//      good bundle and shows the compiler output over it.
//
// Page state is not kept across a Swift rebuild (the Embedded app is a new WebAssembly module); the URL is, so the
// page comes back on the same screen.
//
// A save that changes only .css files skips the build when the bundle exists: Tools/dev-refresh-styles.mjs rewrites the
// bundle's stylesheets in place, and the page gets "build-ok" and "css" as after a build. When that script declines
// (exit 3: a file that is not a stylesheet source, a release configuration) or fails, the normal build runs.
// SWIFTUIWEB_WATCH_STYLES_FAST_PATH=0 turns this off, =1 turns it on.
//
// Test hooks: SWIFTUIWEB_WATCH_BUILD_COMMAND replaces the build (run with `sh -c`, `SWIFTUIWEB_WATCH_BUNDLE` names the
// bundle folder it must fill), SWIFTUIWEB_WATCH_ROOTS (":"-separated) replaces the watched folders. While the build command
// is set the stylesheet fast path is off unless SWIFTUIWEB_WATCH_STYLES_FAST_PATH=1 turns it on.
import { spawn, spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, watch, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { basename, dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { LITERALS_LIMIT } from "./live-reload.mjs";

const FRAMEWORK_ROOT = resolve(process.env.SWIFTUIWEB_ROOT ?? join(dirname(fileURLToPath(import.meta.url)), ".."));
const { values } = parseArgs({
  options: {
    "package-root": { type: "string" }, product: { type: "string" }, configuration: { type: "string" },
    port: { type: "string" }, debounce: { type: "string" },
  },
});
const packageRoot = resolve(values["package-root"] ?? process.env.SWIFTUIWEB_PACKAGE_ROOT ?? process.cwd());
const product = values.product ?? process.env.SWIFTUIWEB_PRODUCT;
if (!product) {
  console.error("dev-watch: pass --product <name>");
  process.exit(2);
}
const configuration = values.configuration ?? process.env.CONFIGURATION ?? "debug";
const debounceMs = Number(values.debounce ?? process.env.SWIFTUIWEB_WATCH_DEBOUNCE_MS ?? 300);
const buildRoot = resolve(process.env.SWIFTUIWEB_BUILD_ROOT ?? join(packageRoot, ".build"));
const bundleDir = resolve(process.env.SWIFTUIWEB_WATCH_BUNDLE ?? join(process.env.SWIFTUIWEB_BUNDLE_ROOT ?? join(buildRoot, "browser"), product));
const devCache = join(buildRoot, "dev-cache", `${product}-${configuration}`);
const token = randomBytes(16).toString("hex");
// The development profile (Documentation/DEVELOPMENT_WORKFLOW.md). A debug loop defaults to `fast`: full Swift for regular
// WebAssembly, where a save recompiles the files it changed. SWIFTUIWEB_DEV_PROFILE (or --dev-profile on swiftuiweb-run)
// chooses; `embedded` is the module that ships. A default `fast` falls back to `embedded` when the toolchain has no
// regular WebAssembly SDK: the launcher says so and resolves the Embedded SDK, which is read below.
const devProfileGiven = process.env.SWIFTUIWEB_DEV_PROFILE;
let devProfile = devProfileGiven ?? (configuration === "debug" ? "fast" : "embedded");

// Not build inputs: generated output and caches, editor files, and the documentation and tests next to the sources.
const IGNORED_DIRECTORIES = new Set([".build", ".git", ".swiftpm", "node_modules", "DerivedData", "target", "xcuserdata", "__pycache__", ".idea", ".vscode", ".github", ".agents", ".claude", "Documentation", "Tests"]);
const IGNORED_FILES = /(^|\/)(\.DS_Store|4913)$|~$|\.(swp|swo|tmp|xcuserstate|orig|rej|md)$|(^|\/)\.#|(^|\/)#.*#$/;
const watchRoots = process.env.SWIFTUIWEB_WATCH_ROOTS
  ? process.env.SWIFTUIWEB_WATCH_ROOTS.split(":").filter(Boolean).map((p) => resolve(p))
  // A product of this repository keeps its sources under Tests/Apps/<product> (the Showcase), which the Tests filter hides.
  : [...new Set([packageRoot, join(packageRoot, "Tests/Apps", product), join(FRAMEWORK_ROOT, "Sources"), join(FRAMEWORK_ROOT, "Tools")])].filter(existsSync);

function interesting(root, filename) {
  if (!filename) return false;
  const parts = filename.split("/");
  if (parts.some((part) => IGNORED_DIRECTORIES.has(part))) return false;
  return !IGNORED_FILES.test(filename);
}

async function freePort(start) {
  for (let port = start; port < 65535; port++) {
    const free = await new Promise((done) => {
      const probe = createServer();
      probe.once("error", () => done(false));
      probe.listen(port, "127.0.0.1", () => probe.close(() => done(true)));
    });
    if (free) return port;
  }
  throw new Error("no free port");
}

const port = values.port ?? process.env.PORT ? Number(values.port ?? process.env.PORT) : await freePort(8080);
const base = `http://127.0.0.1:${port}`;

async function notify(type, message) {
  try {
    await fetch(`${base}/__livereload/notify?token=${token}`, { method: "POST", body: JSON.stringify({ type, message }), headers: { "Content-Type": "application/json" } });
  } catch { /* the server is not up yet, or is stopping */ }
}

const stripAnsi = (text) => text.replace(/\x1b\[[0-9;]*m/g, "");

/**
 * The lowering names a located declaration `<path>|<key>` (Sources/LoweringCore/StableSourceLocations.swift), so an error in
 * it reads `<path>|<key>:L:C`, with L counted from the declaration's first line. The reports under
 * `<build root>/embedded-source-lowering` give the original line of that first line (`virtualFiles`); the error is
 * rewritten to `<path>:<start+L-1>:C`. A key no report knows, or a line without one, is left as it is.
 */
function originalLocator() {
  const reportRoot = join(buildRoot, "embedded-source-lowering");
  const starts = new Map();
  const sources = [];
  if (existsSync(reportRoot)) {
    for (const name of readdirSync(reportRoot)) {
      if (!name.endsWith(".json")) continue;
      let report;
      try { report = JSON.parse(readFileSync(join(reportRoot, name), "utf8")); } catch { continue; }
      for (const entry of Array.isArray(report.sourceMap) ? report.sourceMap : []) {
        if (typeof entry?.source !== "string") continue;
        sources.push(entry.source);
        for (const [file, line] of Object.entries(entry.virtualFiles ?? {})) starts.set(file, line);
      }
    }
  }
  sources.sort((a, b) => b.length - a.length);
  if (starts.size === 0) return (line) => line;
  return (line) => line.replace(/([^\s|]+)\|(\S+?):(\d+):(\d+)/g, (match, candidate, key, lineNumber, column) => {
    const source = sources.find((known) => candidate === known || candidate.endsWith(`/${known}`));
    const start = source === undefined ? undefined : starts.get(`${source}|${key}`);
    return start === undefined ? match : `${source}:${start + Number(lineNumber) - 1}:${column}`;
  });
}

/**
 * What to show over the page when a build fails: the compiler's `file:line:col: error:` lines (each is printed twice
 * by SwiftPM, and the generic "SwiftCompile failed ... Command line: ..." line says nothing), with the build cache's
 * path in front of each file removed. Falls back to the last lines of the log.
 */
function summarizeFailure(output) {
  const locate = originalLocator();
  const lines = stripAnsi(output).split("\n").map((line) => locate(line.replaceAll(`${devCache}/full-swift/tree/`, "").replaceAll(`${devCache}/tree/`, "")).trimEnd());
  const compiler = [...new Set(lines.filter((line) => /\.swift:\d+:\d+: error:/.test(line)))];
  const others = [...new Set(lines.filter((line) => /(^|\s)error:/.test(line) && !/Command line:|SwiftCompile/.test(line)))];
  const picked = compiler.length ? compiler : others.length ? others : lines.slice(-40);
  return picked.slice(0, 15).join("\n").trim();
}

// The stylesheet fast path. On by default; off while the test build command is set, unless SWIFTUIWEB_WATCH_STYLES_FAST_PATH
// says otherwise ("1" turns it on, "0" turns it off).
const stylesFastPath = (process.env.SWIFTUIWEB_WATCH_STYLES_FAST_PATH ?? (process.env.SWIFTUIWEB_WATCH_BUILD_COMMAND ? "0" : "1")) === "1";

/**
 * Refreshes the bundle's stylesheets for `files` (relative to the package root, as the watcher names them) with
 * Tools/dev-refresh-styles.mjs. Resolves { ok, seconds } or { ok: false, reason }; a failed refresh changes nothing the
 * build would not rewrite.
 */
function refreshStyles(files) {
  return new Promise((done) => {
    const started = performance.now();
    const absolute = files.map((file) => resolve(packageRoot, file)).join(",");
    const child = spawn(process.execPath, [join(FRAMEWORK_ROOT, "Tools/dev-refresh-styles.mjs"), "--bundle", bundleDir, "--package-root", packageRoot, "--product", product, "--framework-root", FRAMEWORK_ROOT, "--files", absolute],
      { cwd: FRAMEWORK_ROOT, env: { ...process.env, CONFIGURATION: configuration }, stdio: ["ignore", "pipe", "pipe"] });
    let output = "";
    const collect = (chunk) => { output += chunk; };
    child.stdout.on("data", collect);
    child.stderr.on("data", collect);
    child.on("error", (error) => done({ ok: false, reason: error.message }));
    child.on("close", (code) => done(code === 0
      ? { ok: true, seconds: (performance.now() - started) / 1000 }
      : { ok: false, reason: `exit ${code}: ${stripAnsi(output).trim().split("\n").pop() || "no output"}` }));
  });
}

let toolchainChecked = false;
// The build that is running, which a stop ends with the watcher.
let runningBuild = null;
// The compiler and Embedded SDK the first build resolved (its "Resolved toolchain:" line). Later builds reuse them and skip
// `swift sdk list` and the selection, about 0.6 s per save. A pair the user set in the environment always wins.
let resolvedToolchain = null;
const RESOLVED_TOOLCHAIN = /^Resolved toolchain: swift=(\S+) sdk=(\S+)$/m;

/** One build, for the saved `files` (none for the first build). Resolves { ok, seconds, tail }. */
function build(files = []) {
  return new Promise((done) => {
    const started = performance.now();
    const env = { ...process.env, SWIFTUIWEB_PACKAGE_ROOT: packageRoot, SWIFTUIWEB_PRODUCT: product, CONFIGURATION: configuration, BUILD_ONLY: "1", ...(liveLiterals ? { SWIFTUIWEB_LIVE_LITERALS: "1" } : {}), SWIFTUIWEB_DEV_CACHE: devCache, SWIFTUIWEB_WATCH_BUNDLE: bundleDir, SWIFTUIWEB_DEV_PROFILE: devProfile };
    if (!devProfileGiven && devProfile === "fast") env.SWIFTUIWEB_DEV_PROFILE_DEFAULTED = "1";
    // Only Swift sources were saved: when the launcher's direct build compiles them, it replaces app.wasm in the bundle and
    // skips the steps that would write the other files again (Tools/run-browser-embedded.sh).
    if (files.length > 0 && files.every((file) => file.endsWith(".swift"))) env.SWIFTUIWEB_WATCH_SWIFT_ONLY = "1"; else delete env.SWIFTUIWEB_WATCH_SWIFT_ONLY;
    // The toolchain does not change between saves: the first build checks it, the others skip the 0.5 to 1 s report.
    if (toolchainChecked) env.SWIFTUIWEB_SKIP_TOOLCHAIN_REPORT = "1";
    if (resolvedToolchain && !process.env.SWIFTUIWEB_SWIFT && !process.env.WASM_SDK) {
      Object.assign(env, { SWIFTUIWEB_SWIFT: resolvedToolchain.swift, WASM_SDK: resolvedToolchain.sdk, SWIFTUIWEB_TOOLCHAIN_RESOLVED: "1" });
    }
    const command = process.env.SWIFTUIWEB_WATCH_BUILD_COMMAND;
    const child = command
      ? spawn("/bin/sh", ["-c", command], { cwd: packageRoot, env })
      : spawn("/bin/bash", [join(FRAMEWORK_ROOT, "Tools/run-browser.sh"), product], { cwd: FRAMEWORK_ROOT, env });
    let output = "";
    // The line comes first and the log can outgrow the kept tail, so it is read as the output arrives.
    let resolvedPair = null;
    const collect = (chunk) => {
      output += chunk;
      if (!resolvedPair) { const match = stripAnsi(output.slice(-4096)).match(RESOLVED_TOOLCHAIN); if (match) resolvedPair = { swift: match[1], sdk: match[2] }; }
      // The launcher fell back to the Embedded profile (no regular SDK): the later builds ask for it directly.
      if (resolvedPair && !devProfileGiven && devProfile === "fast" && resolvedPair.sdk.endsWith("-embedded")) {
        devProfile = "embedded";
        console.log("[watch] the toolchain has no regular WebAssembly SDK, so this loop builds the Embedded profile (slower saves); install swift-<version>-RELEASE_wasm for the profile fast");
      }
      if (output.length > 200_000) output = output.slice(-100_000);
    };
    runningBuild = child;
    child.stdout.on("data", collect);
    child.stderr.on("data", collect);
    child.on("error", (error) => done({ ok: false, seconds: 0, tail: `could not start the build: ${error.message}` }));
    child.on("close", (code) => {
      runningBuild = null;
      if (code === 0) {
        toolchainChecked = true;
        if (resolvedPair && !resolvedToolchain) resolvedToolchain = resolvedPair;
      }
      // A hot build that changed only the application says so (Tools/run-browser-embedded.sh): the pages swap it in.
      done({ ok: code === 0, seconds: (performance.now() - started) / 1000, tail: summarizeFailure(output), swap: code === 0 && output.includes("(app-side.wasm replaced)") });
    });
  });
}

// --- the server ---------------------------------------------------------------------------------------------------
mkdirSync(bundleDir, { recursive: true });
if (!existsSync(join(bundleDir, "index.html"))) {
  writeFileSync(join(bundleDir, "index.html"), "<!doctype html><html><head><meta charset=\"utf-8\"><title>Building…</title></head><body><p style=\"font:16px system-ui;padding:2rem\">Building the first bundle…</p></body></html>");
}
const server = spawn(process.execPath, [join(FRAMEWORK_ROOT, "Tools/bun-server.ts"), bundleDir, String(port)], {
  env: { ...process.env, PORT: String(port), SWIFTUIWEB_LIVE_RELOAD_TOKEN: token }, stdio: ["ignore", "inherit", "inherit"],
});
let stopping = false;
const stop = (code = 0) => {
  if (stopping) return;
  stopping = true;
  // The watcher takes its server and a running build with it: neither is left holding the port or the processor when the
  // watcher is stopped by a signal that did not reach them (a kill of the watcher alone, not a Ctrl-C in the terminal).
  server.kill("SIGTERM");
  runningBuild?.kill("SIGTERM");
  setTimeout(() => { server.kill("SIGKILL"); process.exit(code); }, 100);
};
process.on("SIGINT", () => stop(130));
process.on("SIGTERM", () => stop(143));
server.on("exit", (code) => { if (!stopping) { console.error(`dev-watch: the server stopped (${code})`); stop(1); } });

for (let attempt = 0; attempt < 100; attempt++) {
  try { await fetch(base, { signal: AbortSignal.timeout(300) }).then((r) => r.arrayBuffer()); break; } catch { await new Promise((r) => setTimeout(r, 100)); }
}

// --- the loop -----------------------------------------------------------------------------------------------------
let running = false;
let pending = null; // the files changed while a build was running
let timer = null;
let changed = new Set();
// The fast path only stands for a build when the last build succeeded: after a failure the Swift sources are still broken,
// and a stylesheet save must build again and keep reporting the error instead of sending "build-ok".
let lastBuildOk = false;

/** "Foo.swift" or "Foo.swift, Bar.swift and 3 more": which saves started a build. */
function describe(files) {
  const shown = files.slice(0, 3).join(", ");
  return files.length > 3 ? `${shown} and ${files.length - 3} more` : shown;
}

// Live literals (a debug loop, unless SWIFTUIWEB_LIVE_LITERALS=0): a save that only changes the values of literals is sent to the
// open pages at once, and the build that follows does not reload them (Documentation/DEVELOPMENT_WORKFLOW.md).
const liveLiterals = configuration === "debug" && process.env.SWIFTUIWEB_LIVE_LITERALS !== "0";
/** Each Swift source as the pages last had it (built, or sent as replacements). */
const sources = new Map();
/** False after a failed build: the pages then show an older source than `sources` holds, so nothing is replaced in them. */
let pagesCurrent = true;
const readSource = (path) => { try { return readFileSync(path, "utf8"); } catch { return null; } };

/**
 * Whether the build wraps the literals of `file` (a path relative to the package): the lowering does it for application
 * sources only (`lowersAsApplication` in Tools/SwiftUIWebLowering). In the framework's own checkout those are the product's
 * folders; a consumer package is application code throughout. A literal of any other file has no `_live` call in the page,
 * so a replacement would be counted and change nothing.
 */
function hasLiveLiterals(file) {
  if (packageRoot !== FRAMEWORK_ROOT) return true;
  return [`Examples/${product}/`, `Tests/Apps/${product}/`, "Examples/CloneKit/"].some((folder) => file.startsWith(folder));
}

/** The replacements for `files` (paths relative to the package), or null when one of them needs a build. */
function literalReplacements(files) {
  if (!liveLiterals || !pagesCurrent || files.length === 0 || !files.every((file) => file.endsWith(".swift") && hasLiveLiterals(file))) return null;
  const started = performance.now();
  const lines = [];
  const taken = [];
  mkdirSync(devCache, { recursive: true });
  const previousPath = join(devCache, "live-literals-previous.swift");
  for (const file of files) {
    const path = join(packageRoot, file);
    const previous = sources.get(path), current = readSource(path);
    if (previous == null || current == null) return null;
    writeFileSync(previousPath, previous);
    const result = spawnSync("/bin/bash", [join(FRAMEWORK_ROOT, "Tools/swiftuiweb-lowering.sh"), "--literal-diff", previousPath, path, file], { encoding: "utf8" });
    if (result.status !== 0) return null;
    lines.push(...result.stdout.split("\n").filter(Boolean));
    taken.push([path, current]);
  }
  if (lines.length === 0) return null;
  // The channel refuses a longer text (Tools/live-reload.mjs), and part of a save is not the save.
  if (lines.join("\n").length > LITERALS_LIMIT) return null;
  for (const [path, current] of taken) sources.set(path, current);
  return { text: lines.join("\n"), count: lines.length, ms: performance.now() - started };
}

let quietBuilding = false, quietAgain = false;

async function rebuild(reason, files, alreadyReplaced = null) {
  running = true;
  const replaced = alreadyReplaced ?? literalReplacements(files);
  if (replaced) {
    const sent = performance.now();
    if (!alreadyReplaced) await notify("literals", replaced.text);
    console.log(`\n[watch] ${replaced.count} literal${replaced.count === 1 ? "" : "s"} replaced in the page (${replaced.ms.toFixed(0)} ms to compare, ${(performance.now() - sent).toFixed(0)} ms to send); building behind it…`);
    // A save during this build that again only changes literals is sent at once (`schedule`), and the build runs again.
    let result;
    quietBuilding = true;
    do { quietAgain = false; result = await build(files); } while (quietAgain && result.ok);
    quietBuilding = false;
    lastBuildOk = result.ok;
    if (result.ok) {
      console.log(`[watch] built in ${result.seconds.toFixed(1)} s; the page already shows it`);
      await notify("literals-built");
    } else {
      pagesCurrent = false;
      console.error(`[watch] build failed after ${result.seconds.toFixed(1)} s\n${result.tail}`);
      await notify("build-error", result.tail);
    }
    running = false;
    if (pending) { const next = pending; pending = null; await rebuild(describe([...next]), [...next]); }
    return;
  }
  for (const file of files) if (file.endsWith(".swift")) { const path = join(packageRoot, file); const text = readSource(path); if (text == null) sources.delete(path); else sources.set(path, text); }
  await notify("build-start");
  const cssOnly = files.length > 0 && files.every((file) => file.endsWith(".css"));
  const refreshed = cssOnly && stylesFastPath && lastBuildOk && existsSync(join(bundleDir, "styles.css")) ? await refreshStyles(files) : null;
  if (refreshed?.ok) {
    console.log(`[watch] refreshed stylesheets in ${refreshed.seconds.toFixed(2)} s`);
    await notify("build-ok");
    await notify("css");
  } else {
    if (refreshed) console.log(`[watch] stylesheet fast path not used (${refreshed.reason}); building`);
    console.log(`\n[watch] building (${reason})…`);
    const result = await build(files);
    lastBuildOk = result.ok;
    pagesCurrent = result.ok;
    if (result.ok) {
      console.log(`[watch] built in ${result.seconds.toFixed(1)} s; ${cssOnly ? "swapping stylesheets" : result.swap ? "swapping the application into the page" : "reloading the page"}`);
      await notify("build-ok");
      await notify(cssOnly ? "css" : result.swap ? "swap" : "reload");
    } else {
      console.error(`[watch] build failed after ${result.seconds.toFixed(1)} s; the page keeps the last good bundle\n${result.tail}`);
      await notify("build-error", result.tail);
    }
  }
  running = false;
  if (pending) {
    const next = pending;
    pending = null;
    await rebuild(describe([...next]), [...next]);
  }
}

/** A save that only changes literals does not wait for the quiet moment: it is compared and sent as the event arrives.
 * True when the save was taken here. A file caught half written does not compare, and waits like any other save. */
function replaceNow(filename) {
  if (!liveLiterals || pending || changed.size > 0 || (running && !quietBuilding)) return false;
  const replaced = literalReplacements([filename]);
  if (!replaced) return false;
  notify("literals", replaced.text);
  if (running) {
    quietAgain = true;
    console.log(`[watch] ${replaced.count} literal${replaced.count === 1 ? "" : "s"} replaced in the page (${replaced.ms.toFixed(0)} ms to compare) while building`);
  } else {
    rebuild(filename, [filename], replaced);
  }
  return true;
}

function schedule(filename) {
  changed.add(filename);
  clearTimeout(timer);
  timer = setTimeout(() => {
    const files = [...changed];
    changed = new Set();
    if (running) {
      if (quietBuilding && !pending) {
        const replaced = literalReplacements(files);
        if (replaced) {
          quietAgain = true;
          notify("literals", replaced.text);
          console.log(`[watch] ${replaced.count} literal${replaced.count === 1 ? "" : "s"} replaced in the page (${replaced.ms.toFixed(0)} ms to compare) while building`);
          return;
        }
      }
      console.log(`[watch] saved ${describe(files)} while building; it is built next`);
      pending = new Set([...(pending ?? []), ...files]);
      return;
    }
    rebuild(describe(files), files);
  }, debounceMs);
}

// The operating system reports a "change" for a file that was only read or copied (the lowerer copies the whole
// package; on macOS that touches the metadata of every source file), so an event alone is not a save. Remember each
// file's modification time and size and react only when one of them differs.
const known = new Map();
const signatureOf = (path) => {
  try {
    const info = statSync(path);
    return info.isDirectory() ? "directory" : `${info.mtimeMs}:${info.size}`;
  } catch {
    return null;
  }
};
function scan(directory) {
  let entries = [];
  try { entries = readdirSync(directory, { withFileTypes: true }); } catch { return; }
  for (const entry of entries) {
    if (IGNORED_DIRECTORIES.has(entry.name)) continue;
    const path = join(directory, entry.name);
    if (entry.isDirectory()) scan(path);
    else { known.set(path, signatureOf(path)); if (liveLiterals && entry.name.endsWith(".swift")) { const text = readSource(path); if (text != null) sources.set(path, text); } }
  }
}
function changedSinceLastSeen(path) {
  const signature = signatureOf(path);
  if (signature === "directory") return false;
  if (signature === null) return known.delete(path); // a removed file counts once, an unknown one never
  if (known.get(path) === signature) return false;
  known.set(path, signature);
  return true;
}

const watchers = [];
for (const root of watchRoots) {
  scan(root);
  try {
    watchers.push(watch(root, { recursive: true }, (event, filename) => {
      if (!filename || !interesting(root, String(filename))) return;
      const path = join(root, String(filename));
      if (changedSinceLastSeen(path)) { const name = relative(packageRoot, path); if (!replaceNow(name)) schedule(name); }
    }));
  } catch (error) {
    console.error(`dev-watch: cannot watch ${root}: ${error.message}`);
  }
}
console.log(`[watch] watching ${watchRoots.map((root) => basename(root)).join(", ")} (${watchers.length} folders)`);

const first = await (async () => {
  running = true;
  console.log(`[watch] first build of ${product} (${configuration}, development profile ${devProfile}); later builds reuse ${relative(packageRoot, devCache) || devCache}`);
  console.log(`[watch] NOT READY YET: the page is served when this build ends (about a minute the first time). Saves made now are built right after.`);
  const started = performance.now();
  const ticker = setInterval(() => console.log(`[watch] still building… ${Math.round((performance.now() - started) / 1000)} s`), 10_000);
  const result = await build();
  clearInterval(ticker);
  lastBuildOk = result.ok;
  running = false;
  return result;
})();
pagesCurrent = first.ok;
if (first.ok) {
  console.log(`[watch] built in ${first.seconds.toFixed(1)} s`);
  await notify("reload");
} else {
  console.error(`[watch] the first build failed; fix it and save again\n${first.tail}`);
  await notify("build-error", first.tail);
}
console.log(`\n[watch] READY. SwiftUIWeb is running at ${base}   (Ctrl-C to stop)`);
if (process.env.SWIFTUIWEB_OPEN_BROWSER === "1" && process.platform === "darwin") spawn("open", [base], { stdio: "ignore" }).unref();
if (pending) { const next = pending; pending = null; rebuild(describe([...next]), [...next]); }
