#!/usr/bin/env bun
// Measures how a release bundle paints, in a fresh Chromium context per run: first contentful paint, largest
// contentful paint, the time the app is mounted (`html[data-embedded-mounted]`), the time the first row of the board is
// on screen, and the cumulative layout shift of the whole load (which includes the handover from the prerendered
// markup to the runtime's).
//
//   bun Tools/first-paint-measure.mjs --bundle .build/browser/BoardBenchmarkApp --runs 15 --network slow --cpu 4
//
// --network fast (no throttling, the default) | slow (1.6 Mbps down, 750 Kbps up, 150 ms RTT, the "slow 4G" profile).
// --cpu 1 | 4 (CDP CPU throttling rate). --ready <selector> is what counts as "on screen" (default: the first board row).
// --json prints the summary as JSON. A bundle that was not built with first paint measures the baseline.
import { parseArgs } from "node:util";
import { launch, serveBundle } from "./browser-test-support.mjs";
import { claimPort } from "./first-paint-support.mjs";

const { values } = parseArgs({
  options: {
    bundle: { type: "string" }, runs: { type: "string", default: "15" }, network: { type: "string", default: "fast" },
    cpu: { type: "string", default: "1" }, ready: { type: "string", default: 'input[aria-label="Search works"]' },
    path: { type: "string", default: "/" }, json: { type: "boolean", default: false }, "block-wasm": { type: "boolean", default: false },
  },
});
if (!values.bundle) { console.error("usage: first-paint-measure.mjs --bundle <dir> [--runs 15] [--network fast|slow] [--cpu 1|4]"); process.exit(2); }

const PROFILES = { fast: null, slow: { offline: false, latency: 150, downloadThroughput: (1.6 * 1024 * 1024) / 8, uploadThroughput: (750 * 1024) / 8 } };
const RECORDER = (ready) => `
(() => {
  const m = window.__m = { fcp: null, lcp: null, shifts: [], mounted: null, ready: null, mountedFrame: null };
  new PerformanceObserver((list) => { for (const e of list.getEntries()) if (e.name === 'first-contentful-paint') m.fcp = e.startTime; }).observe({ type: 'paint', buffered: true });
  new PerformanceObserver((list) => { for (const e of list.getEntries()) m.lcp = e.startTime; }).observe({ type: 'largest-contentful-paint', buffered: true });
  new PerformanceObserver((list) => { for (const e of list.getEntries()) if (!e.hadRecentInput) m.shifts.push({ t: e.startTime, v: e.value }); }).observe({ type: 'layout-shift', buffered: true });
  const tick = () => {
    const html = document.documentElement;
    if (m.mounted === null && html.dataset.embeddedMounted === 'true') m.mounted = performance.now();
    if (m.ready === null && document.querySelector(${JSON.stringify(ready)}) && !document.querySelector('[data-first-paint]')) m.ready = performance.now();
    if (m.ready !== null && m.mounted !== null) return;
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
  // The first row on screen, prerendered or not: the first frame in which a row exists anywhere.
  const first = () => { if (m.firstRow == null && document.querySelector(${JSON.stringify(ready)})) { m.firstRow = performance.now(); } else if (m.firstRow == null) requestAnimationFrame(first); };
  requestAnimationFrame(first);
})();`;

const median = (a) => { const s = [...a].sort((x, y) => x - y); const n = s.length; return n ? (n % 2 ? s[(n - 1) / 2] : (s[n / 2 - 1] + s[n / 2]) / 2) : NaN; };
const percentile = (a, p) => { const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor(p * s.length))]; };

const port = await claimPort();
const server = await serveBundle({ bundle: values.bundle, port, logName: null });
const browser = await launch({ engine: "chromium" });
const rows = [];
try {
  const runs = Number(values.runs);
  for (let i = -1; i < runs; i++) { // run -1 warms the server and Chromium, and is dropped
    const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    const page = await context.newPage();
    const cdp = await context.newCDPSession(page);
    await cdp.send("Network.enable");
    await cdp.send("Network.setCacheDisabled", { cacheDisabled: true });
    const profile = PROFILES[values.network];
    if (profile) await cdp.send("Network.emulateNetworkConditions", profile);
    if (Number(values.cpu) > 1) await cdp.send("Emulation.setCPUThrottlingRate", { rate: Number(values.cpu) });
    if (values["block-wasm"]) await page.route(/\.wasm(\?|$)/, (route) => route.abort());
    await page.addInitScript(RECORDER(values.ready));
    const started = Date.now();
    await page.goto(`${server.base}${values.path}`, { waitUntil: "commit" });
    if (!values["block-wasm"]) await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 120_000, state: "attached" });
    else await page.waitForTimeout(3000);
    await page.waitForTimeout(1200); // a late shift or a late paint lands in this window
    const m = await page.evaluate(() => {
      const nav = performance.getEntriesByType("navigation")[0];
      return { ...window.__m, responseStart: nav.responseStart, domContentLoaded: nav.domContentLoadedEventEnd };
    });
    const wasm = await page.evaluate(() => performance.getEntriesByType("resource").filter((r) => r.name.includes(".wasm")).map((r) => ({ start: r.startTime, end: r.responseEnd, size: r.encodedBodySize })));
    await context.close();
    if (i < 0) continue;
    const cls = m.shifts.reduce((sum, s) => sum + s.v, 0);
    rows.push({ fcp: m.fcp, lcp: m.lcp, mounted: m.mounted, firstRow: m.firstRow, cls, shifts: m.shifts.length, wasmEnd: wasm[0]?.end ?? null, wall: Date.now() - started });
  }
} finally {
  await browser.close();
  await server.stop();
}
const summary = {};
for (const key of ["fcp", "lcp", "mounted", "firstRow", "wasmEnd", "cls"]) {
  const v = rows.map((r) => r[key]).filter((x) => x !== null && x !== undefined && !Number.isNaN(x));
  summary[key] = v.length ? { median: +median(v).toFixed(key === "cls" ? 4 : 1), min: +Math.min(...v).toFixed(key === "cls" ? 4 : 1), p90: +percentile(v, 0.9).toFixed(key === "cls" ? 4 : 1), max: +Math.max(...v).toFixed(key === "cls" ? 4 : 1), n: v.length } : null;
}
summary.config = { bundle: values.bundle, network: values.network, cpu: Number(values.cpu), runs: rows.length };
if (values.json) console.log(JSON.stringify(summary));
else {
  console.log(`bundle ${values.bundle}  network=${values.network} cpu=${values.cpu}x runs=${rows.length}`);
  for (const [k, v] of Object.entries(summary)) if (k !== "config") console.log(`  ${k.padEnd(9)} ${v ? `median ${v.median}  min ${v.min}  p90 ${v.p90}  max ${v.max}` : "n/a"}`);
}
