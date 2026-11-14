#!/usr/bin/env bun
// A/B performance benchmark for SwiftUIWeb browser apps. See Documentation/Performance/AB_BENCHMARK.md.
//
//   bun Tools/perf-ab.mjs --a <bundle dir> --b <bundle dir> --scenario <module.mjs> [--rounds 12] [--cpu 1,4]
//   bun Tools/perf-ab.mjs --a <bundle dir> --aa --scenario <module.mjs>          # A/A self-check
//
// Both bundles are served at the same time (Tools/bun-server.ts, two ports), and the same scenario runs alternately
// A, B, A, B, ... each time in a fresh browser and context, so drift of the machine hits both sides alike. Per
// interaction of the scenario it reports the median and spread of every metric on both sides and whether B differs
// from A by more than the run-to-run noise (Tools/perf-ab-stats.mjs: bootstrap interval and Mann-Whitney test agree).
// Numbers of two separately started servers or of different times drift by 15-30%; only compare what one run produced.
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { parseArgs } from "node:util";
import { pathToFileURL } from "node:url";
import { engineName, launch, serveBundle } from "./browser-test-support.mjs";
import { compare, comparePaired, median, iqr } from "./perf-ab-stats.mjs";

const USAGE = `usage: bun Tools/perf-ab.mjs --a <dir> (--b <dir> | --aa) --scenario <module> [options]

  --a, --b <dir>        built bundles to compare (a directory with index.html, app.wasm, ...)
  --aa                  A/A self-check: serve --a on both ports; every difference reported is noise
  --scenario <module>   scenario module exporting run({ page, context, base, interact, cpu, viewport }), and optionally path, viewport, name, prepare, ready
  --rounds <n>          runs per side and CPU rate (default 12; 20 or more to see a 20% change reliably)
  --cpu <rates>         CPU throttling rates, comma separated (default 1); Emulation.setCPUThrottlingRate, Chromium only
  --engine <name>       chromium (default), webkit or firefox; SWIFTUIWEB_BROWSER_ENGINE is the default
  --order <ab|abba>     ab: A, B, A, B ... (default); abba: A,B then B,A, to cancel a first-in-pair effect
  --port-a, --port-b    ports of the two servers (default 8190 and 8191)
  --api-origin <url>    SWIFTUIWEB_API_ORIGIN for both servers (proxy to a running API)
  --api-path <path>     SWIFTUIWEB_API_PATH for both servers (default /api when --api-origin is given)
  --frame-rate <mode>   uncapped (default: lifts the 60 Hz requestAnimationFrame cap) or default
  --viewport <WxH>      initial viewport (default: the scenario's, else 1280x800)
  --alpha <p>           significance level (default 0.01; the bootstrap interval uses 1 - alpha)
  --min-effect <r>      smallest relative change reported as a difference (default 0.05)
  --label-a, --label-b  names in the report (default A and B)
  --metrics <list>      metrics in the printed table (default: ${"commitMs,commitMsPerCommit,layoutMs,longTaskSumMs,longTaskMaxMs,blockingMs,share16"})
  --only <text>         print only interactions whose name contains this text
  --json <file>         write every sample and comparison as JSON
  --markdown <file>     write the report tables as Markdown
  --unpaired            compare the two samples as independent (default: paired by round, which cancels the drift of the machine)
  --keep-going          record a failed run and continue instead of stopping
  -h, --help
`;

const DEFAULT_METRICS = ["commitMs", "commitMsPerCommit", "layoutMs", "longTaskSumMs", "longTaskMaxMs", "blockingMs", "share16"];
// Metrics whose per-interaction values add up to a whole-scenario total; the others take the maximum.
const SUMMED = ["commits", "commitMs", "layoutMs", "layoutPasses", "longTaskCount", "longTaskSumMs", "blockingMs", "slowFrames16", "jankMs"];
const MAXIMUM = ["maxCommitMs", "longTaskMaxMs", "frameMax"];
const UNITS = { share8: "%", share16: "%", commits: "", layoutPasses: "", longTaskCount: "", frames: "", slowFrames16: "" };
const TOTAL = "(whole scenario)";

// ---------------------------------------------------------------------------------------------------- in-page recorder

/** Runs in the page before any script. Records long tasks and frame times, and owns the interaction window. */
function installRecorder() {
  const state = (window.__perfAb = { longTasks: [], frames: [], rafHandle: 0, t0: 0, lastCommit: 0, lastCommitCount: 0 });
  try {
    state.observer = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) state.longTasks.push([entry.startTime, entry.duration]);
    });
    state.observer.observe({ type: "longtask", buffered: true });
  } catch {
    state.observer = null;
  }
  const commits = () => window.__embeddedSession?.metrics?.commits ?? 0;
  const flatten = (value, prefix, out) => {
    for (const [key, item] of Object.entries(value ?? {})) {
      if (prefix === "" && /^(fiber|schemaVersion)$/.test(key)) continue; // fiber counters are cumulative: reset() does not clear them
      if (typeof item === "number" && Number.isFinite(item)) out[prefix + key] = item;
      else if (item && typeof item === "object" && !Array.isArray(item) && !/^(mutations|mutationClasses|mutationObserver)$/.test(key)) flatten(item, `${prefix}${key}.`, out);
    }
  };
  state.begin = () => {
    if (state.observer) for (const entry of state.observer.takeRecords()) state.longTasks.push([entry.startTime, entry.duration]);
    window.__performanceMetrics.reset();
    state.frames = [];
    state.t0 = performance.now();
    state.lastCommitCount = commits();
    state.lastCommit = state.t0;
    const tick = (now) => {
      state.frames.push(now);
      const count = commits();
      if (count !== state.lastCommitCount) {
        state.lastCommitCount = count;
        state.lastCommit = now;
      }
      state.rafHandle = requestAnimationFrame(tick);
    };
    state.rafHandle = requestAnimationFrame(tick);
    return state.t0;
  };
  // Waits for `quietMs` without a commit or a long task (at most `maxMs`), stops recording and returns the raw window.
  state.finish = async (quietMs, maxMs) => {
    const started = performance.now();
    let activity = started;
    for (;;) {
      await new Promise((resolve) => setTimeout(resolve, 20));
      const now = performance.now();
      if (state.observer) for (const entry of state.observer.takeRecords()) state.longTasks.push([entry.startTime, entry.duration]);
      const lastTask = state.longTasks.length ? Math.max(...state.longTasks.slice(-8).map(([start, duration]) => start + duration)) : 0;
      activity = Math.max(started, state.lastCommit, lastTask <= state.t0 ? 0 : lastTask);
      if (now - activity >= quietMs || now - started >= maxMs) break;
    }
    cancelAnimationFrame(state.rafHandle);
    const t1 = performance.now();
    const snapshot = {};
    flatten(window.__performanceMetrics.snapshot(), "", snapshot);
    const tasks = state.longTasks.filter(([start]) => start >= state.t0 && start < t1);
    const lastTaskEnd = tasks.reduce((end, [start, duration]) => Math.max(end, start + duration), 0);
    const activeEnd = Math.max(state.lastCommit, lastTaskEnd, state.t0);
    return { t0: state.t0, t1, activeEnd, tasks, frames: state.frames, snapshot };
  };
}

// ---------------------------------------------------------------------------------------------------- metrics

const finite = (value) => (typeof value === "number" ? value : NaN);
const round = (value, digits = 2) => (Number.isFinite(value) ? Number(value.toFixed(digits)) : null);

/** Turns the raw window of one interaction into the flat metric record that is compared between A and B. */
export function windowMetrics(raw) {
  const { snapshot, tasks } = raw;
  const durations = tasks.map(([, duration]) => duration);
  const commits = snapshot.commits ?? 0;
  const commitMs = snapshot.commitDurationMs ?? 0;
  const activeFrames = raw.frames.filter((time) => time >= raw.t0 && time <= raw.activeEnd + 1);
  const intervals = [];
  for (let index = 1; index < activeFrames.length; index += 1) intervals.push(activeFrames[index] - activeFrames[index - 1]);
  const ordered = [...intervals].sort((a, b) => a - b);
  const within = (limit) => (intervals.length ? (100 * intervals.filter((value) => value <= limit).length) / intervals.length : null);
  const metrics = {
    windowMs: raw.t1 - raw.t0,
    activeMs: raw.activeEnd - raw.t0,
    commits,
    commitMs,
    commitMsPerCommit: commits ? commitMs / commits : null,
    maxCommitMs: snapshot.maxCommitDurationMs ?? 0,
    layoutMs: snapshot["diagnostics.layoutUpdateMs"] ?? 0,
    layoutPasses: snapshot["layout.passes"] ?? 0,
    domPatchMs: snapshot["diagnostics.domPatchMs"] ?? 0,
    htmlParseMs: snapshot["diagnostics.htmlParseMs"] ?? 0,
    longTaskCount: durations.length,
    longTaskSumMs: durations.reduce((sum, value) => sum + value, 0),
    longTaskMaxMs: durations.length ? Math.max(...durations) : 0,
    blockingMs: durations.reduce((sum, value) => sum + Math.max(0, value - 50), 0),
    frames: intervals.length,
    // 8.4 and 16.8 ms: the 120 Hz and 60 Hz frame budgets with the rounding a frame timestamp has.
    share8: within(8.4),
    share16: within(16.8),
    slowFrames16: intervals.filter((value) => value > 16.8).length,
    jankMs: intervals.reduce((sum, value) => sum + Math.max(0, value - 16.7), 0),
    frameP95: ordered.length ? ordered[Math.min(ordered.length - 1, Math.floor(0.95 * ordered.length))] : null,
    frameMax: ordered.length ? ordered[ordered.length - 1] : null
  };
  for (const [key, value] of Object.entries(snapshot)) metrics[`snap.${key}`] = value;
  for (const key of Object.keys(metrics)) metrics[key] = metrics[key] === null ? null : round(metrics[key], 3);
  return metrics;
}

/** Adds the whole-scenario pseudo interaction: sums of the additive metrics and maxima of the others. */
export function withTotals(interactions) {
  const names = Object.keys(interactions);
  const total = {};
  for (const key of SUMMED) total[key] = round(names.reduce((sum, name) => sum + (interactions[name][key] ?? 0), 0), 3);
  for (const key of MAXIMUM) total[key] = round(Math.max(...names.map((name) => interactions[name][key] ?? 0)), 3);
  total.commitMsPerCommit = total.commits ? round(total.commitMs / total.commits, 3) : null;
  return { ...interactions, [TOTAL]: total };
}

// ---------------------------------------------------------------------------------------------------- one run

function parseViewport(text) {
  const match = /^(\d+)x(\d+)$/.exec(text ?? "");
  return match ? { width: Number(match[1]), height: Number(match[2]) } : null;
}

async function loadScenario(path) {
  const module = await import(pathToFileURL(resolve(path)).href);
  const scenario = module.default ?? module;
  if (typeof scenario.run !== "function") throw new Error(`${path}: the scenario must export a run({ page, interact, ... }) function`);
  return { name: "scenario", path: "/", viewport: { width: 1280, height: 800 }, warmupMs: 1500, quietMs: 300, maxMs: 2500, ...scenario };
}

const FRAME_FLAGS = ["--disable-frame-rate-limit", "--disable-gpu-vsync"];
const STEADY_FLAGS = ["--disable-renderer-backgrounding", "--disable-background-timer-throttling", "--disable-backgrounding-occluded-windows"];

async function runOnce({ base, scenario, cpu, engine, frameRate, viewport, label }) {
  const args = engine === "chromium" ? [...STEADY_FLAGS, ...(frameRate === "uncapped" ? FRAME_FLAGS : [])] : [];
  const browser = await launch({ engine, args });
  try {
    const context = await browser.newContext({ viewport, baseURL: base, deviceScaleFactor: 1 });
    await scenario.prepare?.({ context, base, env: process.env });
    const page = await context.newPage();
    const problems = [];
    page.on("pageerror", (error) => problems.push(String(error)));
    await page.addInitScript(installRecorder);
    await page.goto(`${scenario.path}${scenario.path.includes("?") ? "&" : "?"}swuidiag`);
    await scenario.ready?.({ page, context, base });
    await page.waitForFunction(() => !!window.__performanceMetrics && !!window.__embeddedSession?.metrics, undefined, { timeout: 30_000 });
    let cdp = null;
    if (cpu > 1) {
      if (engine !== "chromium") throw new Error("--cpu above 1 needs Chromium (Emulation.setCPUThrottlingRate)");
      cdp = await context.newCDPSession(page);
      await cdp.send("Emulation.setCPUThrottlingRate", { rate: cpu });
    }
    await page.waitForTimeout(scenario.warmupMs);
    const results = {};
    const interact = async (name, action, { quietMs = scenario.quietMs, maxMs = scenario.maxMs } = {}) => {
      if (name in results) throw new Error(`interaction '${name}' runs twice`);
      await page.evaluate(() => window.__perfAb.begin());
      await action();
      const raw = await page.evaluate(([quiet, max]) => window.__perfAb.finish(quiet, max), [quietMs, maxMs]);
      results[name] = windowMetrics(raw);
    };
    await scenario.run({ page, context, base, interact, cpu, viewport });
    if (problems.length) throw new Error(`page errors in ${label}: ${problems.slice(0, 3).join(" | ")}`);
    return results;
  } finally {
    await browser.close().catch(() => {});
  }
}

// ---------------------------------------------------------------------------------------------------- reporting

const format = (value, digits = 1) => (value === null || !Number.isFinite(value) ? "-" : Math.abs(value) >= 100 ? value.toFixed(0) : value.toFixed(digits));
const percent = (value) => (Number.isFinite(value) ? `${value >= 0 ? "+" : ""}${(100 * value).toFixed(0)}%` : value === Infinity ? "+inf" : "-");

/** The smallest change worth reporting, in the metric's unit: 2 points of a share, half a millisecond, one count. */
function minimumChange(metric) {
  if (metric.startsWith("share")) return 2;
  if (/Ms$|^frame/.test(metric)) return 0.5;
  return 0;
}

/** All comparisons of one CPU rate: { interaction: { metric: compare() result } } for every metric collected. */
export function compareSamples(samples, options) {
  const comparisons = {};
  for (const interaction of Object.keys(samples.A[0])) {
    comparisons[interaction] = {};
    for (const metric of Object.keys(samples.A[0][interaction])) {
      const settings = { iterations: 1500, ...options, minAbsolute: minimumChange(metric) };
      const value = (side, index) => samples[side][index][interaction]?.[metric];
      if (options.paired === false) {
        const pick = (side) => samples[side].map((_, index) => value(side, index)).filter((item) => typeof item === "number");
        comparisons[interaction][metric] = compare(pick("A"), pick("B"), settings);
        continue;
      }
      // Pairs: the A and B run of the same round, so a round where one side failed is left out.
      const a = [];
      const b = [];
      samples.roundsA.forEach((round, indexA) => {
        const indexB = samples.roundsB.indexOf(round);
        if (indexB < 0) return;
        a.push(value("A", indexA));
        b.push(value("B", indexB));
      });
      comparisons[interaction][metric] = comparePaired(a.map(finite), b.map(finite), settings);
    }
  }
  return comparisons;
}

function table(comparisons, { metrics, labelA, labelB, only }) {
  const rows = [["interaction", "metric", `${labelA} median [IQR]`, `${labelB} median [IQR]`, "delta", "99% CI of delta (paired)", "p", "verdict"]];
  for (const [interaction, byMetric] of Object.entries(comparisons)) {
    if (only && !interaction.includes(only) && interaction !== TOTAL) continue;
    for (const metric of metrics) {
      const result = byMetric[metric];
      if (!result || !Number.isFinite(result.medianA)) continue;
      const unit = UNITS[metric] ?? "ms";
      rows.push([
        interaction,
        metric + (unit ? ` (${unit})` : ""),
        `${format(result.medianA)} [${format(result.iqrA)}]`,
        `${format(result.medianB)} [${format(result.iqrB)}]`,
        percent(result.relative),
        Number.isFinite(result.ci.low) ? `${format(result.ci.low)} .. ${format(result.ci.high)}` : "-",
        Number.isFinite(result.p) ? (result.p < 0.001 ? "<0.001" : result.p.toFixed(3)) : "-",
        result.verdict === "no significant difference" ? "-" : result.verdict
      ]);
    }
  }
  return rows;
}

const text = (rows) => {
  const widths = rows[0].map((_, column) => Math.max(...rows.map((row) => String(row[column]).length)));
  return rows.map((row) => row.map((cell, column) => String(cell).padEnd(widths[column])).join("  ").trimEnd()).join("\n");
};
const markdown = (rows) => [rows[0], rows[0].map(() => "---"), ...rows.slice(1)].map((row) => `| ${row.join(" | ")} |`).join("\n");

/** Counts the comparisons that came out as a difference, over `metrics` (or every collected metric). */
export function countVerdicts(comparisons, metrics = null) {
  let total = 0;
  let flagged = 0;
  const list = [];
  for (const [interaction, byMetric] of Object.entries(comparisons)) {
    for (const [metric, result] of Object.entries(byMetric)) {
      if (metrics && !metrics.includes(metric)) continue;
      if (result.verdict === "too few samples") continue;
      total += 1;
      if (result.verdict !== "no significant difference") {
        flagged += 1;
        list.push(`${interaction} / ${metric}: ${result.verdict} (${percent(result.relative)}, p=${result.p.toFixed(4)})`);
      }
    }
  }
  return { total, flagged, list };
}

/** Typical run-to-run spread: the median over interactions of IQR / median, per metric. */
export function noiseBand(samples, metrics) {
  const band = {};
  for (const metric of metrics) {
    const spreads = [];
    for (const side of ["A", "B"]) {
      for (const interaction of Object.keys(samples[side][0])) {
        const values = samples[side].map((run) => run[interaction]?.[metric]).filter((value) => typeof value === "number");
        const center = median(values);
        if (values.length >= 4 && center > 0) spreads.push(iqr(values) / center);
      }
    }
    band[metric] = spreads.length ? median(spreads) : null;
  }
  return band;
}

// ---------------------------------------------------------------------------------------------------- main

async function main() {
  const { values } = parseArgs({
    options: {
      a: { type: "string" }, b: { type: "string" }, aa: { type: "boolean", default: false }, scenario: { type: "string" },
      rounds: { type: "string", default: "12" }, cpu: { type: "string", default: "1" }, engine: { type: "string" },
      order: { type: "string", default: "ab" }, "port-a": { type: "string", default: "8190" }, "port-b": { type: "string", default: "8191" },
      "api-origin": { type: "string" }, "api-path": { type: "string" }, "frame-rate": { type: "string", default: "uncapped" },
      viewport: { type: "string" }, alpha: { type: "string", default: "0.01" }, "min-effect": { type: "string", default: "0.05" },
      "label-a": { type: "string", default: "A" }, "label-b": { type: "string", default: "B" }, metrics: { type: "string", default: DEFAULT_METRICS.join(",") },
      only: { type: "string" }, json: { type: "string" }, markdown: { type: "string" }, "keep-going": { type: "boolean", default: false }, unpaired: { type: "boolean", default: false },
      help: { type: "boolean", short: "h", default: false }
    }
  });
  if (values.help || !values.a || !values.scenario || (!values.b && !values.aa)) {
    console.error(USAGE);
    process.exit(values.help ? 0 : 2);
  }
  if (values.aa && values.b) throw new Error("--aa serves --a on both ports; do not pass --b");
  if (!["ab", "abba"].includes(values.order)) throw new Error("--order is ab or abba");
  if (!["uncapped", "default"].includes(values["frame-rate"])) throw new Error("--frame-rate is uncapped or default");
  const rounds = Number(values.rounds);
  if (!Number.isInteger(rounds) || rounds < 1) throw new Error("--rounds must be a positive integer");
  const cpuRates = values.cpu.split(",").map(Number);
  if (cpuRates.some((rate) => !Number.isFinite(rate) || rate < 1)) throw new Error("--cpu is a comma separated list of rates of at least 1");
  const portA = Number(values["port-a"]);
  const portB = Number(values["port-b"]);
  const engine = values.engine ?? engineName();
  const scenario = await loadScenario(values.scenario);
  const viewport = parseViewport(values.viewport) ?? scenario.viewport;
  const stats = { alpha: Number(values.alpha), confidence: 1 - Number(values.alpha), minEffect: Number(values["min-effect"]), paired: !values.unpaired };
  const printed = values.metrics.split(",");
  const labelA = values["label-a"];
  const labelB = values.aa ? (values["label-b"] === "B" ? "A'" : values["label-b"]) : values["label-b"];
  const bundleB = values.aa ? values.a : values.b;

  if (values["api-origin"]) {
    process.env.SWIFTUIWEB_API_ORIGIN = values["api-origin"];
    process.env.SWIFTUIWEB_API_PATH = values["api-path"] ?? process.env.SWIFTUIWEB_API_PATH ?? "/api";
  } else if (values["api-path"]) process.env.SWIFTUIWEB_API_PATH = values["api-path"];

  const servers = [];
  const stopAll = () => Promise.all(servers.map((server) => server.stop().catch(() => {})));
  for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => stopAll().finally(() => process.exit(130)));
  const report = { engine, scenario: scenario.name, rounds, order: values.order, frameRate: values["frame-rate"], viewport, labels: { A: labelA, B: labelB }, bundles: { A: resolve(values.a), B: resolve(bundleB) }, stats, results: [] };
  try {
    const sideA = await serveBundle({ bundle: values.a, port: portA, logName: "perf-ab-a" });
    servers.push(sideA);
    const sideB = await serveBundle({ bundle: bundleB, port: portB, logName: "perf-ab-b" });
    servers.push(sideB);
    const sides = { A: sideA.base, B: sideB.base };
    const markdownParts = [];
    for (const cpu of cpuRates) {
      const samples = { A: [], B: [], roundsA: [], roundsB: [] };
      const failures = [];
      for (let round = 0; round < rounds; round += 1) {
        const pair = values.order === "abba" && round % 2 === 1 ? ["B", "A"] : ["A", "B"];
        for (const side of pair) {
          const label = `${side} round ${round + 1}/${rounds} cpu ${cpu}x`;
          process.stderr.write(`${label}\n`);
          let outcome = null;
          for (let attempt = 0; attempt < 2 && !outcome; attempt += 1) {
            try {
              outcome = await runOnce({ base: sides[side], scenario, cpu, engine, frameRate: values["frame-rate"], viewport, label });
            } catch (error) {
              process.stderr.write(`  failed (${error.message.split("\n")[0]})${attempt === 0 ? ", retrying once" : ""}\n`);
              if (attempt === 1) failures.push(`${label}: ${error.message}`);
            }
          }
          if (outcome) {
            samples[side].push(withTotals(outcome));
            samples[`rounds${side}`].push(round);
          } else if (!values["keep-going"]) throw new Error(`run failed twice: ${failures.at(-1)}`);
        }
      }
      if (samples.A.length === 0 || samples.B.length === 0) throw new Error("no successful run on one side");
      const comparisons = compareSamples(samples, stats);
      const noise = noiseBand(samples, printed);
      const headline = countVerdicts(comparisons, printed);
      const everything = countVerdicts(comparisons);
      const rows = table(comparisons, { metrics: printed, labelA, labelB, only: values.only });
      const title = `${scenario.name}: ${labelA} vs ${labelB}, CPU ${cpu}x, ${samples.A.length}+${samples.B.length} runs, ${engine}, ${values.aa ? "A/A self-check, " : ""}frame rate ${values["frame-rate"]}`;
      console.log(`\n== ${title}\n${text(rows)}`);
      console.log(`\nrun-to-run spread (median IQR/median): ${printed.map((metric) => `${metric} ${noise[metric] === null ? "-" : `${(100 * noise[metric]).toFixed(0)}%`}`).join(", ")}`);
      console.log(`differences beyond noise: ${headline.flagged} of ${headline.total} printed comparisons, ${everything.flagged} of ${everything.total} over all ${Object.keys(Object.values(comparisons)[0]).length} collected metrics`);
      for (const line of everything.list.slice(0, 40)) console.log(`  ${line}`);
      if (failures.length) console.log(`failed runs: ${failures.length}\n${failures.map((failure) => `  ${failure}`).join("\n")}`);
      markdownParts.push(`### ${title}\n\n${markdown(rows)}\n\nRun-to-run spread (median IQR/median): ${printed.map((metric) => `${metric} ${noise[metric] === null ? "-" : `${(100 * noise[metric]).toFixed(0)}%`}`).join(", ")}. Differences beyond noise: ${headline.flagged} of ${headline.total} printed comparisons, ${everything.flagged} of ${everything.total} over all collected metrics.\n`);
      report.results.push({ cpu, samples, comparisons, noise, flagged: { printed: headline, all: everything }, failures });
    }
    if (values.json) {
      mkdirSync(dirname(resolve(values.json)), { recursive: true });
      writeFileSync(values.json, JSON.stringify(report));
      console.log(`\nwrote ${values.json}`);
    }
    if (values.markdown) {
      mkdirSync(dirname(resolve(values.markdown)), { recursive: true });
      writeFileSync(values.markdown, markdownParts.join("\n"));
      console.log(`wrote ${values.markdown}`);
    }
  } finally {
    await stopAll();
  }
}

if (import.meta.main) {
  main().catch((error) => {
    console.error(error instanceof Error ? (error.stack ?? error.message) : error);
    process.exit(1);
  });
}
