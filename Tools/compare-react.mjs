#!/usr/bin/env bun
// The same board app written for SwiftUIWeb and for React, measured in one browser on one machine.
//
//   bun Tools/compare-react.mjs --rounds 15 --cpu 1,4 --network slow4g --json Benchmarks/ReactComparison/results/latest.json
//
// How it keeps the comparison fair (the method is in Benchmarks/ReactComparison/README.md):
//   - both apps are production builds (SwiftUIWeb's release bundle, React's minified bundle), served by the same server with
//     the same precompressed files, at the same time;
//   - every round runs the scenario once on each side, alternating who goes first (A B, B A, A B, ...), each in a fresh
//     browser and context, so what the machine is doing at that moment is shared by both;
//   - what is measured is read from the page, the same way for both: from the input event to the DOM and layout showing the result
//     (the work) and to the frame that presents it (what the eye sees; see Benchmarks/ReactComparison/recorder.mjs);
//   - per metric it reports the median of each side, the spread, the change of B against A as the median of the per-round
//     differences, a bootstrap interval, and a Wilcoxon signed-rank test (Tools/perf-ab-stats.mjs). A difference counts only
//     when the interval excludes zero, p < 0.01 and the change is at least 5 percent;
//   - `--cpu 4` slows the CPU four times with the browser's own throttling (Chromium only). The throttle reaches the page's main
//     thread; Chromium refuses it for a dedicated worker, so SwiftUIWeb's default side (its Swift in a Worker) is recorded as
//     not throttled at that rate (see throttleCpu and throttleReach).
// A is SwiftUIWeb, C is SwiftUIWeb with its Swift on the main thread, B is React. Run `bun Tools/test-react-board-parity.mjs` first: it checks both apps answer alike.
import { mkdirSync, writeFileSync } from "node:fs";
import { cpus, totalmem, platform, release } from "node:os";
import { dirname, join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { engineName, freePort, launch, serveBundle, ROOT } from "./browser-test-support.mjs";
import { comparePaired, iqr, median } from "./perf-ab-stats.mjs";
import { installRecorder } from "../Benchmarks/ReactComparison/recorder.mjs";
import { loadOnly, LOAD_METRICS, METRICS, READY, run } from "../Benchmarks/ReactComparison/scenario.mjs";

// Frames stay at the display's 60 Hz: the flags that lift the cap in other browsers only slowed this one down, and a person sees
// 60 Hz anyway. The rest keep a background tab from being throttled.
const FLAGS = ["--disable-renderer-backgrounding", "--disable-background-timer-throttling", "--disable-backgrounding-occluded-windows"];
// Four sides: SwiftUIWeb as it runs by default (its Swift in a Web Worker), the same bundle with the Swift on the main thread
// (`?render-in-worker=0`), React, and React written with a virtualized list (`?virtual=1`, see react-board/src/VirtualRows.jsx).
// A, C and D are compared with B (React), never with each other, except that D is also set against A in its own column.
// The order of each round is a rotation of the four sides, or of their reverse: each side is first, second, third and last
// equally often over eight orders.
const BASE_ORDER = ["a", "c", "b", "d"];
const rotations = (list) => [0, 1, 2, 3].map((shift) => [...list.slice(shift), ...list.slice(0, shift)]);
export const ORDERS = [...rotations(BASE_ORDER), ...rotations([...BASE_ORDER].reverse())];
const SIDES = [
  { key: "a", label: "SwiftUIWeb", server: "a", path: "/" },
  { key: "c", label: "SwiftUIWeb (main thread)", server: "a", path: "/?render-in-worker=0" },
  { key: "b", label: "React", server: "b", path: "/" },
  { key: "d", label: "React (virtualized)", server: "b", path: "/?virtual=1" },
];

/**
 * Throttles the CPU at `rate` for the page and for every dedicated worker it starts (SwiftUIWeb's Swift runs in one by default).
 * Emulation.setCPUThrottlingRate applies to the target it is sent to, and a worker is a target of its own, so a throttle on the
 * page alone leaves the worker at full speed. The page's session auto-attaches the workers (Target.setAutoAttach), and each one
 * is sent the same command through Target.sendMessageToTarget. Chromium refuses it for a worker ("Operation is only supported
 * for pages, not workers"), and this records that refusal instead of assuming the worker was slowed.
 * `settled()` resolves, after the page has loaded, to { workers: [{ ok, error }] }, one entry per worker that started.
 */
export async function throttleCpu(context, page, rate) {
  const session = await context.newCDPSession(page);
  const replies = new Map();
  let nextId = 0;
  session.on("Target.receivedMessageFromTarget", ({ sessionId, message }) => {
    const reply = JSON.parse(message);
    const key = `${sessionId}:${reply.id}`;
    const pending = replies.get(key);
    if (pending === undefined) return;
    replies.delete(key);
    pending(reply.error ? { ok: false, error: reply.error.message } : { ok: true, error: null });
  });
  const sendTo = (sessionId, method, params) => new Promise((resolve, reject) => {
    nextId += 1;
    replies.set(`${sessionId}:${nextId}`, resolve);
    session.send("Target.sendMessageToTarget", { sessionId, message: JSON.stringify({ id: nextId, method, params }) }).catch(reject);
  });
  const workers = [];
  session.on("Target.attachedToTarget", ({ sessionId, targetInfo }) => {
    if (targetInfo.type === "worker") workers.push(sendTo(sessionId, "Emulation.setCPUThrottlingRate", { rate }));
  });
  await session.send("Target.setAutoAttach", { autoAttach: true, waitForDebuggerOnStart: false, flatten: false });
  await session.send("Emulation.setCPUThrottlingRate", { rate });
  return { settled: async () => ({ workers: await Promise.all(workers) }) };
}

/** What a run's throttle reached, in words for the report: the page alone, or the page and its workers. */
export function throttleReach(throttle) {
  if (throttle.workers.length === 0) return "the page";
  if (throttle.workers.every((worker) => worker.ok)) return "the page and its workers";
  return "the page only: Chromium refuses the throttle for a worker";
}

/**
 * Network profiles, applied to the page with Network.emulateNetworkConditions and measured for the cold load. Chromium applies
 * them to the page's workers as well (a 400 KB fetch made by a worker takes 2.16 s under slow4g, 2 ms without it), so the Swift
 * worker's own fetches are slowed too. The numbers: 1.6 Mbps down (Chromium's Fast 3G bandwidth), 750 kbps up, 150 ms round trip.
 */
export const NETWORKS = {
  slow4g: { label: "Slow 4G", offline: false, latency: 150, downloadThroughput: 1.6e6 / 8, uploadThroughput: 0.75e6 / 8 },
};

/** One run of the scenario on one side, in a fresh browser. `network` is a NETWORKS profile: then only the cold load is measured. */
async function runOnce({ base, path, cpu, network = null, viewport }) {
  const browser = await launch({ args: FLAGS });
  try {
    const context = await browser.newContext({ viewport, deviceScaleFactor: 1 });
    const page = await context.newPage();
    const problems = [];
    page.on("pageerror", (error) => problems.push(String(error)));
    await page.addInitScript(installRecorder, READY);
    const throttle = cpu > 1 ? await throttleCpu(context, page, cpu) : null;
    if (network !== null) {
      const { label, ...conditions } = network;
      const session = await context.newCDPSession(page);
      await session.send("Network.enable");
      await session.send("Network.emulateNetworkConditions", conditions);
    }
    await page.goto(`${base}${path}`);
    const sample = network === null ? await run(page) : await loadOnly(page);
    // Read after the run: the workers attach as the page starts them, and the run has finished with all of them by now.
    const reach = throttle === null ? null : throttleReach(await throttle.settled());
    if (problems.length > 0) throw new Error(`the page reported errors: ${problems.slice(0, 2).join(" | ")}`);
    return { sample, version: browser.version(), reach };
  } finally {
    await browser.close();
  }
}

/**
 * The report of one CPU rate: per metric the samples of each side. React against SwiftUIWeb (`comparison`), SwiftUIWeb on the main
 * thread against React (`comparisonMain`), and React with a virtualized list against SwiftUIWeb (`comparisonVirtual`).
 */
export function summarize(samples, { metricIds, ...options } = {}) {
  const report = {};
  for (const metric of METRICS.filter((candidate) => !metricIds || metricIds.includes(candidate.id))) {
    const a = samples.a.map((sample) => sample[metric.id]);
    const b = samples.b.map((sample) => sample[metric.id]);
    const c = (samples.c ?? []).map((sample) => sample[metric.id]);
    const d = (samples.d ?? []).map((sample) => sample[metric.id]);
    // A metric the engine cannot read (WebKit has no long-task entries) is null in every sample: its row is left out, not zero.
    if (a.every((value) => value === null)) continue;
    const settings = { minAbsolute: metric.unit === "ms" ? 0.5 : 0, ...options };
    report[metric.id] = {
      ...metric, a, b, c, d,
      comparison: comparePaired(a, b, settings),
      comparisonMain: c.length === b.length && c.length > 0 ? comparePaired(c, b, settings) : null,
      comparisonVirtual: d.length === a.length && d.length > 0 ? comparePaired(a, d, settings) : null,
    };
  }
  return report;
}

const fixed = (value, digits = 1) => (Number.isFinite(value) ? value.toFixed(digits) : "n/a");

/** Markdown of one CPU rate: React against SwiftUIWeb, and against SwiftUIWeb with its Swift on the main thread. */
export function markdown(report, cpu, reaches = {}, title = `CPU ${cpu}x`) {
  // The default SwiftUIWeb side is compared with React only when its throttle reached the worker that renders it.
  const unthrottled = cpu > 1 && reaches.a !== undefined && reaches.a !== "the page and its workers";
  const lines = [title, ""];
  if (unthrottled) lines.push(`SwiftUIWeb (worker) is not throttled: the throttle reached ${reaches.a}. Its numbers are not a ${cpu}x CPU and are not compared with React.`, "");
  lines.push(
    "| Metric | SwiftUIWeb | SwiftUIWeb (main thread) | React | React (virtualized) | React vs SwiftUIWeb | React vs main thread | React (virtualized) vs SwiftUIWeb |",
    "|---|---|---|---|---|---|---|---|",
  );
  const verdictOf = (c) => (c.verdict === "B higher" ? "React higher" : c.verdict === "B lower" ? "React lower" : c.verdict === "too few samples" ? "too few samples" : "no significant difference");
  const cell = (c) => `${Number.isFinite(c.relative) ? `${c.relative >= 0 ? "+" : ""}${fixed(c.relative * 100, 0)}%` : "n/a"} (${verdictOf(c)})`;
  for (const row of Object.values(report)) {
    const c = row.comparison;
    const unit = row.unit ? ` ${row.unit}` : "";
    const main = row.comparisonMain;
    const worker = `${fixed(c.medianA)}${unit} (±${fixed(c.iqrA)})${unthrottled ? ", not throttled" : ""}`;
    const versus = unthrottled ? "not comparable" : cell(c);
    const virtual = row.comparisonVirtual;
    const virtualMedian = virtual ? `${fixed(virtual.medianB)}${unit} (±${fixed(virtual.iqrB)})` : "n/a";
    const virtualVersus = !virtual ? "n/a" : unthrottled ? "not comparable" : cell(virtual);
    lines.push(`| ${row.label} | ${worker} | ${main ? `${fixed(main.medianA)}${unit} (±${fixed(main.iqrA)})` : "n/a"} | ${fixed(c.medianB)}${unit} (±${fixed(c.iqrB)}) | ${virtualMedian} | ${versus} | ${main ? cell(main) : "n/a"} | ${virtualVersus} |`);
  }
  return lines.join("\n");
}

/**
 * Runs every side once in each round, in the round's order, each in a fresh browser. Returns the samples of each side, round by
 * round, and what each throttle reached. A failed run is retried once.
 */
async function collect({ rounds, bases, cpu, network = null, viewport, meta }) {
  const samples = { a: [], b: [], c: [], d: [] };
  const reaches = {};
  for (let round = 0; round < rounds; round += 1) {
    // The orders cycle through ORDERS, so each side is first, second, third and last equally often.
    for (const key of ORDERS[round % ORDERS.length]) {
      const side = SIDES.find((candidate) => candidate.key === key);
      const options = { base: bases[side.server], path: side.path, cpu, network, viewport };
      let result;
      try { result = await runOnce(options); }
      catch (error) { console.error(`round ${round + 1} ${key}: ${error.message}; retrying once`); result = await runOnce(options); }
      samples[key][round] = result.sample;
      if (result.reach !== null) reaches[key] = result.reach;
      meta.browser = `${engineName() === "webkit" ? "WebKit" : "Chromium"} ${result.version}`;
    }
    process.stdout.write(`\r${network === null ? `CPU ${cpu}x` : network.label}: round ${round + 1}/${rounds}`);
  }
  process.stdout.write("\n");
  return { samples, reaches };
}

async function main() {
  const { values } = parseArgs({
    options: {
      a: { type: "string", default: ".build/browser/BoardBenchmarkApp" },
      b: { type: "string", default: "Benchmarks/ReactComparison/react-board/dist" },
      rounds: { type: "string", default: "15" },
      cpu: { type: "string", default: "1,4" },
      network: { type: "string" },
      json: { type: "string" },
      markdown: { type: "string" },
      width: { type: "string", default: "1280" },
      height: { type: "string", default: "800" },
    },
  });
  const rounds = Number(values.rounds);
  if (!(rounds >= 10)) throw new Error("--rounds must be at least 10: the signed-rank test cannot reach p < 0.01 with fewer");
  const viewport = { width: Number(values.width), height: Number(values.height) };
  const servers = {};
  const bases = {};
  for (const [side, dir] of [["a", values.a], ["b", values.b]]) {
    servers[side] = await serveBundle({ bundle: resolve(ROOT, dir), port: await freePort(), logName: `compare-react-${side}`, required: ["index.html"] });
    bases[side] = servers[side].base;
  }
  const meta = {
    date: new Date().toISOString(),
    machine: { cpu: cpus()[0]?.model, cores: cpus().length, memoryGB: Math.round(totalmem() / 2 ** 30), os: `${platform()} ${release()}` },
    viewport, rounds, order: "the eight rotations and reversed rotations of the four sides, in turn", sides: { a: "SwiftUIWeb (release, Embedded WebAssembly, Swift in a Web Worker)", c: "SwiftUIWeb, Swift on the main thread (?render-in-worker=0)", b: "React 19 (production, minified, content-hashed)", d: "React 19 with a hand-written virtualized list (?virtual=1)" },
    engine: engineName(),
    // Per CPU rate above 1: what each side's throttle reached (see throttleReach).
    throttle: {},
  };
  const network = values.network ? NETWORKS[values.network] : null;
  if (values.network && network === null) throw new Error(`--network must be one of ${Object.keys(NETWORKS).join(", ")}`);
  // The CPU throttle and the network profiles are Chromium's DevTools commands: another engine measures the machine as it is.
  const engine = engineName();
  if (engine !== "chromium" && network !== null) throw new Error(`--network needs Chromium (Network.emulateNetworkConditions), not ${engine}`);
  const cpuRates = (values.cpu ? values.cpu.split(",").map(Number) : []).filter((cpu) => {
    if (cpu === 1 || engine === "chromium") return true;
    console.error(`CPU ${cpu}x is not measured in ${engine}: Emulation.setCPUThrottlingRate is a Chromium command`);
    return false;
  });
  const out = { meta, cpu: {}, network: {} };
  try {
    for (const cpu of cpuRates) {
      const { samples, reaches } = await collect({ rounds, bases, cpu, viewport, meta });
      if (cpu > 1) meta.throttle[cpu] = reaches;
      out.cpu[cpu] = summarize(samples);
      console.log(markdown(out.cpu[cpu], cpu, reaches), "\n");
    }
    if (network !== null) {
      const { samples } = await collect({ rounds, bases, cpu: 1, network, viewport, meta });
      const report = summarize(samples, { metricIds: LOAD_METRICS });
      out.network[values.network] = { label: network.label, latency: network.latency, downloadThroughput: network.downloadThroughput, uploadThroughput: network.uploadThroughput, report };
      console.log(markdown(report, 1, {}, `${network.label} (cold load, ${rounds} rounds)`), "\n");
    }
  } finally {
    await servers.a.stop();
    await servers.b.stop();
  }
  if (values.json) {
    mkdirSync(dirname(resolve(values.json)), { recursive: true });
    writeFileSync(resolve(values.json), JSON.stringify(out, null, 1));
  }
  if (values.markdown) {
    const sections = Object.entries(out.cpu).map(([cpu, report]) => markdown(report, Number(cpu), meta.throttle[cpu] ?? {}));
    for (const { label, report } of Object.values(out.network)) sections.push(markdown(report, 1, {}, `${label} (cold load, ${rounds} rounds)`));
    writeFileSync(resolve(values.markdown), `${sections.join("\n\n")}\n`);
  }
}

if (import.meta.main) {
  main().catch((error) => { console.error(error.stack ?? error); process.exit(1); });
}
