#!/usr/bin/env bun
// Opt-in render-commit benchmark for the real Embedded Showcase.
//
// Run through `Tools/test-performance-browser.mjs --render-commit` (or `make render-commit-benchmark`). It measures where the
// HTML commit path spends its time, frame by frame, and classifies what each commit actually changed in the DOM, so a
// "direct DOM operations for small updates" path can be evaluated against real numbers. It changes nothing about rendering:
// every page is loaded with `?swuidiag`, which turns on the diagnostics-only counters, per-commit samples and the mutation
// classifier in `embedded-dom.js`.
//
// Each scenario runs `--iterations` times in one browser. An iteration is
//   1. a fresh page load (cold startup: everything up to mount + settle), then
//   2. `reset()` and the scenario's interaction (incremental updates),
// each with its own frame recording (rAF deltas + long-animation-frame / longtask entries). The report keeps every iteration and,
// per scenario, the median and spread across iterations plus pooled per-commit distributions.
//
// Timings are only meaningful on a quiet machine: before each scenario the benchmark waits (up to `--quiet-timeout` seconds)
// until no compiler process runs, and records whether that happened and the 1-minute load average. It never fails because the
// machine is busy; it flags it.
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { loadavg } from "node:os";
import { parseArgs } from "node:util";
import { engineName, launch, ROOT, runSuite, serveBundle } from "./browser-test-support.mjs";
import { bundleFilePath } from "./hash-release-bundle.mjs";

const DEFAULT_OUTPUT = join(ROOT, ".build", "performance", "render-commit.json");
const BUSY_PROCESSES = ["swift-frontend", "swift-build", "clang"];
const SWIFT_PHASES = {
  reconcileUs: "publishReconcileUs",
  snapshotWalkUs: "publishSnapshotWalkUs",
  annotateUs: "publishAnnotateUs",
  serializeUs: "publishSerializeUs",
  bookkeepingUs: "publishBookkeepingUs",
};
const JS_PHASES = [
  "htmlReadMs", "htmlParseMs", "domPatchMs", "postPatchSyncMs", "layoutUpdateMs",
  "browserStateSyncMs", "swiftDispatchPublishMs", "patchNodeVisits", "patchSubtreesSkipped",
  "patchChildrenPasses", "htmlCodeUnits",
];
const SAMPLE_FIELDS = ["totalMs", "htmlReadMs", "htmlParseMs", "domPatchMs", "postPatchSyncMs", "layoutUpdateMs", "htmlCodeUnits", "patchNodeVisits"];

// Installed before any page script on every navigation: forces diagnostics on (so the worker also forwards the Swift fiber
// counters; `?swuidiag` alone only reaches the DOM host) and starts a frame recorder at document start, so the cold load is
// recorded from the first frame.
const RECORDER_JS = String.raw`
(() => {
  window.__performanceDiagnostics = true;
  if (window.__swuiBenchFrames) return;
  const supported = (typeof PerformanceObserver === 'function' && PerformanceObserver.supportedEntryTypes) || [];
  const entryType = supported.includes('long-animation-frame') ? 'long-animation-frame' : supported.includes('longtask') ? 'longtask' : null;
  const state = {frames: [], entries: [], running: false, last: 0, raf: 0, startedAt: 0, observer: null};
  const loop = time => {
    if (!state.running) return;
    if (state.last) state.frames.push(time - state.last);
    state.last = time;
    state.raf = requestAnimationFrame(loop);
  };
  const keep = entry => state.entries.push({
    start: entry.startTime, duration: entry.duration,
    blocking: entryType === 'long-animation-frame' ? (entry.blockingDuration || 0) : Math.max(0, entry.duration - 50),
    scripts: entry.scripts ? entry.scripts.length : 0,
  });
  function start() {
    stop();
    state.frames = []; state.entries = []; state.last = 0; state.running = true; state.startedAt = performance.now();
    if (entryType) {
      state.observer = new PerformanceObserver(list => { for (const entry of list.getEntries()) if (entry.startTime >= state.startedAt) keep(entry); });
      try { state.observer.observe({type: entryType, buffered: true}); } catch (_) { state.observer = null; }
    }
    state.raf = requestAnimationFrame(loop);
  }
  function stop() {
    if (!state.running) return null;
    state.running = false;
    cancelAnimationFrame(state.raf);
    if (state.observer) {
      for (const entry of state.observer.takeRecords()) if (entry.startTime >= state.startedAt) keep(entry);
      state.observer.disconnect(); state.observer = null;
    }
    return {entryType, frames: state.frames.slice(), entries: state.entries.slice(), durationMs: performance.now() - state.startedAt};
  }
  window.__swuiBenchFrames = {start, stop, entryType};
  start();
})();
`;

// The commit counter that also counts commits whose HTML was identical (diagnostics only).
const COMMIT_SEQUENCE_JS = "(() => { const s = window.__embeddedSession; return s ? (s.commitProfile ? s.commitProfile.sequence : s.metrics.commits) : -1; })()";

// Waits for at least `minCommits` new commits (up to `timeout`), then for `quietFrames` frames without one.
const SETTLE = async ({ since, minCommits, quietFrames, timeout }) => {
  const sequence = () => { const s = window.__embeddedSession; return s ? (s.commitProfile ? s.commitProfile.sequence : s.metrics.commits) : -1; };
  const frame = () => new Promise((resolve) => requestAnimationFrame(resolve));
  const started = performance.now();
  const base = since === null ? sequence() : since;
  let committed = minCommits <= 0;
  while (!committed && performance.now() - started < timeout) { await frame(); committed = sequence() - base >= minCommits; }
  let last = sequence(), stable = 0;
  while (performance.now() - started < timeout) {
    await frame();
    const value = sequence();
    if (value === last) { if (++stable >= quietFrames) return { settled: committed, ms: performance.now() - started, commits: value - base }; }
    else { last = value; stable = 0; }
  }
  return { settled: false, ms: performance.now() - started, commits: sequence() - base };
};

// Drives an interaction from inside the page so no CDP round trip sits between steps.
const DRIVE = async ({ selector, action, steps, gapFrames, values, settleEach, settleTimeout }) => {
  const find = () => {
    if (selector.startsWith("button-text:")) {
      const label = selector.slice(12);
      return [...document.querySelectorAll("#embedded-app-root button")].find((b) => b.textContent.trim() === label) || null;
    }
    const found = document.querySelector(selector);
    if (!found || found.matches("input,textarea,select,button")) return found;
    return found.querySelector("input,textarea,select,button") || found;
  };
  const selectors = selector.split("|");
  const frame = () => new Promise((resolve) => requestAnimationFrame(resolve));
  const sequence = () => { const s = window.__embeddedSession; return s.commitProfile ? s.commitProfile.sequence : s.metrics.commits; };
  let missing = 0, unsettled = 0;
  for (let step = 0; step < steps; step++) {
    const current = selectors[step % selectors.length];
    selector = current;
    const target = find();
    if (!target) { missing++; await frame(); continue; }
    const before = sequence();
    if (action === "click") target.click();
    else if (action === "input" || action === "range") {
      const value = values[step % values.length];
      // `range` values are fractions of the control's own min...max, so one sweep fits any slider.
      if (action === "range") { const min = Number(target.min || 0), max = Number(target.max || 100); target.value = String(min + (max - min) * value); }
      else target.value = String(value);
      target.dispatchEvent(new InputEvent("input", { bubbles: true }));
      if (step === steps - 1) target.dispatchEvent(new Event("change", { bubbles: true }));
    }
    if (settleEach) {
      const started = performance.now();
      while (sequence() === before && performance.now() - started < settleTimeout) await frame();
      if (sequence() === before) unsettled++;
      let last = sequence(), stable = 0;
      while (stable < 3 && performance.now() - started < settleTimeout) { await frame(); const v = sequence(); if (v === last) stable++; else { last = v; stable = 0; } }
    }
    for (let f = 0; f < gapFrames; f++) await frame();
  }
  return { missing, unsettled };
};

const scenario = (name, group, route, description, steps = [], { ready = null, prepare = [] } = {}) => ({ name, group, route, description, ready, prepare, steps });
const click = (selector, steps, { gap = 0, settleEach = true } = {}) => ({ kind: "drive", selector, action: "click", steps, gapFrames: gap, values: [], settleEach });
const slide = (selector, steps, values, { gap = 1 } = {}) => ({ kind: "drive", selector, action: "range", steps, gapFrames: gap, values, settleEach: false });
const setText = (selector, steps, values, { gap = 2 } = {}) => ({ kind: "drive", selector, action: "input", steps, gapFrames: gap, values, settleEach: false });
const typeText = (selector, text, delay) => ({ kind: "type", selector, text, delay });

// A back-and-forth drag between 5% and 95% of the slider's range.
const SLIDER_SWEEP = Array.from({ length: 80 }, (_, i) => 0.05 + 0.9 * (1 - Math.abs((i % 40) - 20) / 20));
const SMALL = "/renderBenchSmall";
const LIST = "/renderBenchList";
const LIST_READY = '[data-testid="bench-list-rows"]';
const SMALL_READY = '[data-testid="bench-counter-increment"]';

function buildScenarios() {
  const tid = (name) => `[data-testid="${name}"]`;
  const listOp = (name, testid, desc, steps = 5, prepare = null) => scenario(name, "largeList", LIST, desc, [click(tid(testid), steps)], { ready: LIST_READY, prepare: prepare ?? [] });
  const filter = 'input[aria-label^="Filter"]';
  return [
    // a. Frequent small updates.
    scenario("counter", "smallUpdates", SMALL, "30 counter increments, one every 2 frames (coalescing allowed)",
      [click(tid("bench-counter-increment"), 30, { gap: 2, settleEach: false })], { ready: SMALL_READY }),
    scenario("sliderDrag", "smallUpdates", SMALL, "slider drag: 80 input events, one per frame",
      [slide(tid("bench-slider"), 80, SLIDER_SWEEP)], { ready: SMALL_READY }),
    scenario("textTyping", "smallUpdates", SMALL, "type 40 characters with real key events, 16 ms apart",
      [typeText(tid("bench-text-field"), "the quick brown fox jumps over the lazy", 16)], { ready: SMALL_READY }),
    scenario("textReplace", "smallUpdates", SMALL, "20 programmatic whole-value text changes, one every 2 frames",
      [setText(tid("bench-text-field"), 20, Array.from({ length: 20 }, (_, i) => `value ${i} ` + "x".repeat(i % 7)))], { ready: SMALL_READY }),
    // b. Large keyed list (1000 rows).
    listOp("listInsertHead", "bench-list-insert-head", "insert one row at the head, x5"),
    listOp("listInsertMiddle", "bench-list-insert-middle", "insert one row in the middle, x5"),
    listOp("listInsertTail", "bench-list-insert-tail", "append one row, x5"),
    listOp("listRemoveHead", "bench-list-remove-head", "remove the first row, x5"),
    listOp("listRemoveMiddle", "bench-list-remove-middle", "remove the middle row, x5"),
    listOp("listRemoveTail", "bench-list-remove-tail", "remove the last row, x5"),
    listOp("listSwap", "bench-list-swap", "swap rows 1 and n-2, x5"),
    listOp("listReverse", "bench-list-reverse", "reverse all rows, x3", 3),
    listOp("listShuffle", "bench-list-shuffle", "deterministic shuffle of all rows, x3", 3),
    listOp("listUpdatePartial", "bench-list-update-partial", "update every 10th row, x5"),
    listOp("listUpdateAll", "bench-list-update-all", "update every row, x3", 3),
    listOp("listReplaceAll", "bench-list-replace-all", "replace all 1000 rows with new keys, x3", 3),
    listOp("listClear", "bench-list-clear", "remove all 1000 rows, x1", 1),
    listOp("listMount", "bench-list-mount", "mount 1000 rows into an empty list, x1", 1, [click(tid("bench-list-clear"), 1)]),
    // c. Complex existing screens.
    scenario("componentsSlider", "complexScreens", "/components", "Components screen: slider drag, 60 input events, one per frame",
      [slide('input[type="range"]', 60, SLIDER_SWEEP)], { ready: 'input[type="range"]' }),
    scenario("componentsToggle", "complexScreens", "/components", "Components screen: flip the Notifications toggle, x10",
      [click('[data-control-kind="toggle"] input', 10)], { ready: '[data-control-kind="toggle"] input' }),
    scenario("formsTyping", "complexScreens", "/forms", "Forms screen: type 30 characters into Name, 16 ms apart",
      [typeText('input[aria-label="Name"]', " and a much longer name here", 16)], { ready: 'input[aria-label="Name"]' }),
    scenario("collectionsInsertDelete", "complexScreens", "/collections", "Collections screen: Insert x5 then Delete last x5",
      [click("button-text:Insert", 5), click("button-text:Delete last", 5)], { ready: "#embedded-app-root button" }),
    scenario("shellFilterTyping", "complexScreens", "/components", "Shell sidebar filter: type 'co', clear it, x3 (navigation list re-filters)",
      [typeText(filter, "co", 30), { kind: "clear", selector: filter }, typeText(filter, "co", 30), { kind: "clear", selector: filter },
        typeText(filter, "co", 30), { kind: "clear", selector: filter }], { ready: filter }),
    scenario("routeSwitch", "complexScreens", "/components", "Switch Components <-> Collections <-> Forms through the sidebar, 6 switches",
      [click('[data-testid="showcase-topic-collections"]|[data-testid="showcase-topic-forms"]|[data-testid="showcase-topic-components"]', 6)],
      { ready: '[data-testid="showcase-topic-collections"]' }),
  ];
}

// ---------------------------------------------------------------------------- statistics

function percentile(values, q) {
  if (values.length === 0) return null;
  const ordered = [...values].sort((a, b) => a - b);
  if (ordered.length === 1) return ordered[0];
  const position = (ordered.length - 1) * q;
  const low = Math.floor(position);
  const high = Math.min(low + 1, ordered.length - 1);
  return ordered[low] + (ordered[high] - ordered[low]) * (position - low);
}

const numbers = (values) => values.filter((v) => typeof v === "number" && Number.isFinite(v));
const sum = (values) => values.reduce((total, value) => total + value, 0);
const median = (values) => percentile(values, 0.5);

function distribution(raw) {
  const values = numbers(raw);
  if (values.length === 0) return { n: 0 };
  return {
    n: values.length, mean: sum(values) / values.length, p50: percentile(values, 0.5), p95: percentile(values, 0.95),
    p99: percentile(values, 0.99), max: Math.max(...values), min: Math.min(...values),
  };
}

function spread(raw) {
  const values = numbers(raw);
  if (values.length === 0) return null;
  const mid = median(values);
  return { median: mid, min: Math.min(...values), max: Math.max(...values), relSpread: mid ? (Math.max(...values) - Math.min(...values)) / mid : null, n: values.length };
}

function frameSummary(recording) {
  if (!recording) return null;
  const frames = recording.frames ?? [];
  const entries = recording.entries ?? [];
  return {
    ...distribution(frames),
    count: frames.length,
    over16_7ms: frames.filter((f) => f > 16.7).length,
    over50ms: frames.filter((f) => f > 50).length,
    windowMs: recording.durationMs,
    longFrameEntryType: recording.entryType,
    longFrames: entries.length,
    longFrameTotalMs: sum(entries.map((e) => e.duration)),
    longFrameBlockingMs: sum(entries.map((e) => e.blocking)),
    longFrameMaxMs: entries.length ? Math.max(...entries.map((e) => e.duration)) : 0,
  };
}

// ---------------------------------------------------------------------------- machine state

function busyProcesses() {
  const out = spawnSync("ps", ["-Ao", "comm="], { encoding: "utf8", timeout: 10_000 });
  if (out.status !== 0) return [];
  const found = {};
  for (const line of out.stdout.split("\n")) {
    const name = basename(line.trim());
    if (BUSY_PROCESSES.some((busy) => name === busy || name.startsWith(`${busy}-`) || name.startsWith(`${busy}+`))) found[name] = (found[name] ?? 0) + 1;
  }
  return Object.entries(found).map(([name, count]) => `${name}x${count}`).sort();
}

const machineState = () => ({ loadAvg1m: loadavg()[0], busyProcesses: busyProcesses() });

async function waitQuiet(timeoutSeconds) {
  const started = performance.now();
  let busy = busyProcesses();
  while (busy.length > 0 && (performance.now() - started) / 1000 < timeoutSeconds) {
    await new Promise((done) => setTimeout(done, 2000));
    busy = busyProcesses();
  }
  return { ...machineState(), quiet: busy.length === 0, waitedS: Math.round(((performance.now() - started) / 1000) * 10) / 10, busyAtStart: busy };
}

// ---------------------------------------------------------------------------- page helpers

async function metricsSnapshot(page) {
  const value = await page.evaluate(() => globalThis.__performanceMetrics?.snapshot());
  if (!value || value.schemaVersion !== 1) throw new Error(`missing metrics snapshot: ${JSON.stringify(value)}`);
  return value;
}

const settle = (page, { since = null, minCommits = 0, quietFrames = 10, timeout = 10_000 } = {}) => page.evaluate(SETTLE, { since, minCommits, quietFrames, timeout });

async function runSteps(page, steps) {
  const problems = { missing: 0, unsettled: 0 };
  for (const step of steps) {
    if (step.kind === "drive") {
      const { selector, action, steps: count, gapFrames, values, settleEach } = step;
      const result = await page.evaluate(DRIVE, { selector, action, steps: count, gapFrames, values, settleEach, settleTimeout: 5_000 });
      problems.missing += result.missing;
      problems.unsettled += result.unsettled;
    } else if (step.kind === "type") {
      await page.focus(step.selector);
      await page.keyboard.type(step.text, { delay: step.delay });
    } else if (step.kind === "clear") {
      await page.focus(step.selector);
      await page.keyboard.press("ControlOrMeta+A");
      await page.keyboard.press("Backspace");
    } else {
      throw new Error(step.kind);
    }
  }
  return problems;
}

async function load(page, base, route, query, ready) {
  const started = performance.now();
  const response = await page.goto(`${base}${route}?${query}`, { waitUntil: "domcontentloaded" });
  if (!response || response.status() !== 200) throw new Error(`${route}: HTTP ${response ? response.status() : "no response"}`);
  await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30_000 });
  if (ready) await page.waitForSelector(ready, { state: "attached", timeout: 30_000 });
  const settled = await settle(page, { quietFrames: 15, timeout: 15_000 });
  const wall = performance.now() - started;
  const timing = await page.evaluate(() => {
    const nav = performance.getEntriesByType("navigation")[0];
    return {
      domContentLoadedMs: nav ? nav.domContentLoadedEventEnd : null, loadEventMs: nav ? nav.loadEventEnd : null,
      nowMs: performance.now(), firstContentfulPaintMs: performance.getEntriesByName("first-contentful-paint")[0]?.startTime ?? null,
    };
  });
  timing.wallMs = wall;
  timing.settled = settled ? settled.settled : null;
  return timing;
}

// ---------------------------------------------------------------------------- extraction

function fiberDelta(after, before) {
  const a = after.fiber ?? {};
  const b = before?.fiber ?? {};
  return Object.fromEntries(Object.keys(a).map((key) => [key, (a[key] ?? 0) - (b[key] ?? 0)]));
}

function extract(snapshot, fiber, recording, { keepSamples }) {
  const diagnostics = snapshot.diagnostics ?? {};
  const samples = diagnostics.commitSamples ?? [];
  const patched = samples.filter((s) => s.kind !== "identicalHtml");
  const result = {
    commits: snapshot.commits,
    commitCalls: samples.length + (diagnostics.commitSamplesDropped ?? 0),
    commitDurationMs: snapshot.commitDurationMs,
    maxCommitDurationMs: snapshot.maxCommitDurationMs,
    swift: Object.fromEntries(Object.entries(SWIFT_PHASES).map(([name, key]) => [name, fiber[key] ?? 0])),
    swiftCounters: Object.fromEntries(["bodyEvaluations", "reconciledNodes", "invalidatedNodes", "renderNodeAllocations"].map((key) => [key, fiber[key] ?? 0])),
    js: Object.fromEntries(JS_PHASES.map((key) => [key, diagnostics[key]])),
    layout: snapshot.layout,
    domNodeCount: snapshot.domNodeCount,
    errors: snapshot.errors,
    frames: frameSummary(recording),
    mutationClasses: diagnostics.mutationClasses,
    mutations: diagnostics.mutations,
    commitSamplesDropped: diagnostics.commitSamplesDropped,
    perCommit: Object.fromEntries(SAMPLE_FIELDS.map((field) => [field, distribution(patched.map((s) => s[field]))])),
  };
  result.swift.totalUs = sum(Object.values(result.swift));
  if (keepSamples) result.commitSamples = samples;
  result._samples = samples;
  result._frames = recording?.frames ?? [];
  return result;
}

const NUMERIC_PATHS = [
  ["commits"], ["commitCalls"], ["commitDurationMs"], ["maxCommitDurationMs"],
  ...[...Object.keys(SWIFT_PHASES), "totalUs"].map((key) => ["swift", key]),
  ...JS_PHASES.map((key) => ["js", key]),
  ...["count", "mean", "p50", "p95", "p99", "max", "over16_7ms", "over50ms", "longFrames", "longFrameTotalMs", "longFrameBlockingMs"].map((key) => ["frames", key]),
];

function dig(record, path) {
  for (const key of path) {
    if (record === null || typeof record !== "object" || Array.isArray(record)) return null;
    record = record[key];
  }
  return record ?? null;
}

function summarize(records) {
  const summary = {};
  for (const path of NUMERIC_PATHS) {
    const value = spread(records.map((record) => dig(record, path)));
    if (value === null) continue;
    if (path.length === 1) summary[path[0]] = value;
    else (summary[path[0]] ??= {})[path[1]] = value;
  }
  const samples = records.flatMap((record) => record._samples);
  const patched = samples.filter((s) => s.kind !== "identicalHtml");
  const pooled = Object.fromEntries(SAMPLE_FIELDS.map((field) => [field, distribution(patched.map((s) => s[field]))]));
  for (const name of Object.keys(SWIFT_PHASES)) {
    pooled[`swift.${name}`] = distribution(samples.filter((s) => s.swift).map((s) => s.swift?.[name]));
  }
  summary.perCommitPooled = pooled;
  summary.framesPooled = frameSummary({ frames: records.flatMap((record) => record._frames), entries: [] });
  const classes = {};
  for (const record of records) {
    for (const [key, value] of Object.entries(record.mutationClasses ?? {})) classes[key] = (classes[key] ?? 0) + value;
  }
  summary.mutationClassesTotal = classes;
  return summary;
}

const stripPrivate = (record) => Object.fromEntries(Object.entries(record).filter(([key]) => !key.startsWith("_")));

// ---------------------------------------------------------------------------- main

function parseOptions(argv) {
  const { values } = parseArgs({
    args: argv,
    options: {
      "render-commit": { type: "boolean", default: false },
      iterations: { type: "string", default: process.env.RENDER_COMMIT_ITERATIONS ?? "5" },
      // comma-separated scenario names or groups (smallUpdates, largeList, complexScreens)
      scenarios: { type: "string", default: process.env.RENDER_COMMIT_SCENARIOS ?? "" },
      // seconds to wait for compiler processes to finish before each scenario
      "quiet-timeout": { type: "string", default: process.env.RENDER_COMMIT_QUIET_TIMEOUT ?? "120" },
      // run Swift on the main thread (?render-in-worker=0)
      "no-worker": { type: "boolean", default: false },
      // keep timings, skip the MutationObserver classifier
      "no-mutation-observer": { type: "boolean", default: false },
      // store the raw per-commit samples of every iteration
      "keep-samples": { type: "boolean", default: false },
      output: { type: "string", default: DEFAULT_OUTPUT },
      port: { type: "string", default: process.env.RENDER_COMMIT_PORT ?? "8107" },
      bundle: { type: "string", default: process.env.PERF_EMBEDDED_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseApp") },
      list: { type: "boolean", default: false },
    },
  });
  return {
    iterations: Number.parseInt(values.iterations, 10), scenarios: values.scenarios, quietTimeout: Number(values["quiet-timeout"]),
    noWorker: values["no-worker"], noMutationObserver: values["no-mutation-observer"], keepSamples: values["keep-samples"],
    output: values.output, port: Number.parseInt(values.port, 10), bundle: values.bundle, list: values.list,
  };
}

const fmt = (value) => (value === null || value === undefined ? "-" : value.toFixed(2));
const medianOf = (summary, group, key) => {
  const value = (summary[group] ?? {})[key];
  return value !== null && typeof value === "object" ? value.median : value;
};
const timestamp = () => {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  const offset = -now.getTimezoneOffset();
  const sign = offset >= 0 ? "+" : "-";
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}${sign}${pad(Math.floor(Math.abs(offset) / 60))}${pad(Math.abs(offset) % 60)}`;
};

export async function main(argv = process.argv.slice(2)) {
  const args = parseOptions(argv);
  let scenarios = buildScenarios();
  if (args.list) {
    for (const item of scenarios) console.log(`${item.group.padEnd(15)} ${item.name.padEnd(24)} ${item.route.padEnd(18)} ${item.description}`);
    return;
  }
  if (args.scenarios) {
    const wanted = new Set(args.scenarios.split(",").map((name) => name.trim()).filter(Boolean));
    scenarios = scenarios.filter((item) => wanted.has(item.name) || wanted.has(item.group));
    if (scenarios.length === 0) throw new Error(`no scenario matches '${args.scenarios}'`);
  }
  if (args.iterations < 1) throw new Error("--iterations must be >= 1");
  const bundle = resolve(args.bundle);
  for (const name of ["app.wasm", "index.html", "index.js"]) {
    if (!bundleFilePath(bundle, name)) throw new Error(`${name} missing from ${bundle}; run make render-commit-benchmark (it builds the release Showcase)`);
  }

  let query = "swuidiag";
  if (args.noWorker) query += "&render-in-worker=0";
  if (args.noMutationObserver) query += "&swuinomutations";
  const server = await serveBundle({ bundle, port: args.port, logName: "render-commit-server" });
  const base = server.base;
  const report = {
    schemaVersion: 1, namespace: "swiftuiweb.render-commit-benchmark",
    startedAt: timestamp(),
    config: {
      iterations: args.iterations, worker: !args.noWorker, mutationObserver: !args.noMutationObserver,
      query, bundle, engine: engineName(), viewport: [1100, 800],
      quietTimeoutS: args.quietTimeout, busyProcesses: [...BUSY_PROCESSES],
    },
    scenarios: {},
  };
  const failures = [];
  let browser;
  try {
    browser = await launch();
    report.config.browserVersion = browser.version();
    const context = await browser.newContext({ viewport: { width: 1100, height: 800 } });
    await context.addInitScript(RECORDER_JS);
    const page = await context.newPage();
    const consoleErrors = [];
    page.on("pageerror", (error) => consoleErrors.push(String(error)));
    for (const item of scenarios) {
      const quiet = await waitQuiet(args.quietTimeout);
      const flag = quiet.quiet ? "" : ` (NOT QUIET: ${quiet.busyAtStart.join(", ")})`;
      console.log(`[render-commit] ${item.name}: ${args.iterations} iterations, load ${quiet.loadAvg1m.toFixed(2)}${flag}`);
      const coldRecords = [];
      const incrementalRecords = [];
      const iterations = [];
      for (let index = 0; index < args.iterations; index++) {
        try {
          consoleErrors.length = 0;
          const machine = machineState();
          const timing = await load(page, base, item.route, query, item.ready);
          const coldRecording = await page.evaluate(() => window.__swuiBenchFrames.stop());
          const coldSnapshot = await metricsSnapshot(page);
          const cold = extract(coldSnapshot, coldSnapshot.fiber ?? {}, coldRecording, { keepSamples: args.keepSamples });
          cold.timing = timing;
          const problems = item.prepare.length ? await runSteps(page, item.prepare) : { missing: 0, unsettled: 0 };
          if (item.prepare.length) await settle(page, { quietFrames: 10 });
          await page.evaluate(() => globalThis.__performanceMetrics.reset());
          const before = await metricsSnapshot(page);
          const since = await page.evaluate(COMMIT_SEQUENCE_JS);
          await page.evaluate(() => window.__swuiBenchFrames.start());
          const started = performance.now();
          const stepProblems = await runSteps(page, item.steps);
          const settled = await settle(page, { since, minCommits: 1, quietFrames: 10, timeout: 15_000 });
          const interactionMs = performance.now() - started;
          const recording = await page.evaluate(() => window.__swuiBenchFrames.stop());
          const after = await metricsSnapshot(page);
          const incremental = extract(after, fiberDelta(after, before), recording, { keepSamples: args.keepSamples });
          incremental.interactionWallMs = interactionMs;
          incremental.settled = settled;
          for (const key of Object.keys(problems)) stepProblems[key] += problems[key];
          const record = {
            iteration: index, machine, cold: stripPrivate(cold), incremental: stripPrivate(incremental),
            driveProblems: stepProblems, pageErrors: [...consoleErrors],
          };
          if (stepProblems.missing || !settled.settled || consoleErrors.length || after.errors) {
            failures.push(`${item.name}#${index}: problems=${JSON.stringify(stepProblems)} settled=${JSON.stringify(settled)} errors=${JSON.stringify(after.errors)} pageErrors=${JSON.stringify(consoleErrors.slice(0, 2))}`);
          }
          iterations.push(record);
          coldRecords.push(cold);
          incrementalRecords.push(incremental);
        } catch (error) { // one broken iteration must not lose the rest of the run
          const text = error instanceof Error ? error.message : String(error);
          failures.push(`${item.name}#${index}: ${error?.name ?? "Error"}: ${text ? text.split("\n")[0] : ""}`);
          iterations.push({ iteration: index, error: `${error?.name ?? "Error"}: ${text}`.slice(0, 2000) });
        }
      }
      report.scenarios[item.name] = {
        group: item.group, route: item.route, description: item.description, quiet,
        summary: { cold: summarize(coldRecords), incremental: summarize(incrementalRecords) },
        iterations,
      };
      const inc = report.scenarios[item.name].summary.incremental;
      const total = inc.perCommitPooled?.totalMs ?? {};
      console.log(`    commits~${typeof inc.commits === "object" && inc.commits !== null ? inc.commits.median : inc.commits}`
        + ` commit p50=${fmt(total.p50)} p95=${fmt(total.p95)} ms;`
        + ` frames>16.7ms~${medianOf(inc, "frames", "over16_7ms")} classes=${JSON.stringify(inc.mutationClassesTotal)}`);
    }
  } finally {
    await browser?.close();
    await server.stop();
  }
  report.finishedAt = timestamp();
  report.warnings = failures;
  report.quietScenarios = Object.values(report.scenarios).filter((value) => value.quiet.quiet).length;
  const output = resolve(args.output);
  mkdirSync(dirname(output), { recursive: true });
  writeFileSync(output, JSON.stringify(report, null, 2) + "\n");
  const noisy = Object.keys(report.scenarios).length - report.quietScenarios;
  console.log(`${failures.length === 0 ? "PASS" : "DONE with warnings"} render-commit benchmark: ${Object.keys(report.scenarios).length} scenarios`
    + `${noisy ? `, ${noisy} not run on a quiet machine` : ""}; report=${output}`);
  for (const failure of failures) console.log("  warning:", failure);
}

if (import.meta.main) await runSuite(() => main());
