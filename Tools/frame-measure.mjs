// Measures a scenario against one built SwiftUIWeb bundle for Tools/frame-budgets.mjs: per interaction the per-commit
// main-thread time, long tasks and frame times. The scenario module is the one Tools/perf-ab.mjs takes:
//   export default { name, viewport, path, warmupMs, quietMs, maxMs, prepare({context, base, env}), ready({page}),
//                    run({page, interact, cpu, viewport}) }
// where interact(name, action, { quietMs, maxMs }) is one measured interaction.
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";
import { engineName, launch, serveBundle } from "./browser-test-support.mjs";
import { percentile, pool } from "./frame-budgets.mjs";

// The 60 Hz and 120 Hz frame budgets, and the rounding a frame timestamp has (0.1 ms): an interval is late above these.
export const FRAME_60HZ_MS = 16.7;
export const FRAME_120HZ_MS = 8.3;
export const FRAME_TOLERANCE_MS = 0.1;
export const LATE_16_MS = Number((FRAME_60HZ_MS + FRAME_TOLERANCE_MS).toFixed(3)) + 1e-6;
export const LATE_8_MS = Number((FRAME_120HZ_MS + FRAME_TOLERANCE_MS).toFixed(3)) + 1e-6;
/** Chromium reports a long task above 50 ms. */
export const LONG_TASK_MS = 50;

const sum = (values) => values.reduce((total, value) => total + value, 0);
const round = (value, digits = 3) => (Number.isFinite(value) ? Number(value.toFixed(digits)) : null);

/** Runs in the page before any script. Records long tasks, frame timestamps and the duration of every commit. */
export function installRecorder() {
  const state = (window.__frameBudget = { longTasks: [], frames: [], durations: [], prevTotal: null, commitCount: 0, recording: false, t0: 0, lastCommit: 0, rafHandle: 0 });
  try {
    state.observer = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) state.longTasks.push([entry.startTime, entry.duration]);
    });
    state.observer.observe({ type: "longtask", buffered: true });
  } catch {
    state.observer = null;
  }
  const total = () => window.__embeddedSession?.metrics?.commitDurationMs ?? 0;
  // `commit-phase` is dispatched inside a commit, before the commit's own duration is added to the running total, so the
  // total seen by commit k is the sum of the commits before it: the difference between two events is the earlier commit.
  window.addEventListener("commit-phase", () => {
    if (!state.recording) return;
    const now = total();
    if (state.prevTotal !== null) state.durations.push(now - state.prevTotal);
    state.prevTotal = now;
    state.commitCount += 1;
    state.lastCommit = performance.now();
  });
  state.begin = () => {
    if (state.observer) for (const entry of state.observer.takeRecords()) state.longTasks.push([entry.startTime, entry.duration]);
    window.__performanceMetrics.reset();
    state.frames = [];
    state.durations = [];
    state.prevTotal = null;
    state.commitCount = 0;
    state.t0 = performance.now();
    state.lastCommit = state.t0;
    state.recording = true;
    const tick = (now) => {
      state.frames.push(now);
      state.rafHandle = requestAnimationFrame(tick);
    };
    state.rafHandle = requestAnimationFrame(tick);
    return state.t0;
  };
  // Waits for `quietMs` without a commit or a long task (at most `maxMs`), stops recording, returns the raw window.
  state.finish = async (quietMs, maxMs) => {
    const started = performance.now();
    for (;;) {
      await new Promise((done) => setTimeout(done, 20));
      const now = performance.now();
      if (state.observer) for (const entry of state.observer.takeRecords()) state.longTasks.push([entry.startTime, entry.duration]);
      const lastTask = state.longTasks.length ? Math.max(...state.longTasks.slice(-8).map(([start, duration]) => start + duration)) : 0;
      const activity = Math.max(started, state.lastCommit, lastTask <= state.t0 ? 0 : lastTask);
      if (now - activity >= quietMs || now - started >= maxMs) break;
    }
    state.recording = false;
    cancelAnimationFrame(state.rafHandle);
    if (state.prevTotal !== null) state.durations.push(total() - state.prevTotal);
    const t1 = performance.now();
    const snapshot = window.__performanceMetrics.snapshot();
    const tasks = state.longTasks.filter(([start]) => start >= state.t0 && start < t1);
    const lastTaskEnd = tasks.reduce((end, [start, duration]) => Math.max(end, start + duration), 0);
    return {
      t0: state.t0, t1, activeEnd: Math.max(state.lastCommit, lastTaskEnd, state.t0), tasks, frames: state.frames, commitDurations: state.durations,
      commits: state.commitCount, maxCommitMs: snapshot.maxCommitDurationMs ?? 0, layoutMs: snapshot.diagnostics?.layoutUpdateMs ?? 0, layoutPasses: snapshot.layout?.passes ?? 0,
    };
  };
}

/**
 * The metric record of one interaction from its raw window { t0, t1, activeEnd, tasks: [[start, duration]], frames: [time],
 * commitDurations: [ms], commits, maxCommitMs, layoutMs, layoutPasses }. Frames count only between the start and the last
 * activity (the last commit or long task), so the idle tail of the window does not dilute them.
 *
 * `frameTimeMs` is the time the active window spent in frame intervals and `lateMsN` the part of it spent in intervals
 * longer than N: the shares are time-weighted (`timeShare8`, `timeShare16`) because an uncapped requestAnimationFrame fires
 * far more often than a display refreshes, which would inflate a count of frames. The count-based `share8` and `share16`
 * are the metrics Tools/perf-ab.mjs reports.
 */
export function windowMetrics(raw) {
  const durations = raw.commitDurations ?? [];
  const active = (raw.frames ?? []).filter((time) => time >= raw.t0 && time <= raw.activeEnd + 1);
  const intervals = [];
  for (let index = 1; index < active.length; index += 1) intervals.push(active[index] - active[index - 1]);
  const tasks = (raw.tasks ?? []).map(([, duration]) => duration);
  const frameTimeMs = sum(intervals);
  const lateMs8 = sum(intervals.filter((value) => value > LATE_8_MS));
  const lateMs16 = sum(intervals.filter((value) => value > LATE_16_MS));
  const within = (limit) => (intervals.length ? (100 * intervals.filter((value) => value <= limit).length) / intervals.length : null);
  const record = {
    windowMs: round(raw.t1 - raw.t0),
    activeMs: round(raw.activeEnd - raw.t0),
    commits: raw.commits ?? durations.length,
    commitDurationsMs: durations.map((value) => round(value, 2)),
    commitMs: round(sum(durations)),
    commitMsPerCommit: durations.length ? round(sum(durations) / durations.length) : null,
    commitP95Ms: durations.length ? round(percentile(durations, 0.95)) : null,
    maxCommitMs: round(raw.maxCommitMs ?? Math.max(0, ...durations)),
    layoutMs: round(raw.layoutMs ?? 0),
    layoutPasses: raw.layoutPasses ?? 0,
    longTaskCount: tasks.length,
    longTaskSumMs: round(sum(tasks)),
    longTaskMaxMs: round(tasks.length ? Math.max(...tasks) : 0),
    blockingMs: round(sum(tasks.map((value) => Math.max(0, value - LONG_TASK_MS)))),
    frames: intervals.length,
    frameTimeMs: round(frameTimeMs),
    lateMs8: round(lateMs8),
    lateMs16: round(lateMs16),
    timeShare8: frameTimeMs > 0 ? round((100 * (frameTimeMs - lateMs8)) / frameTimeMs) : null,
    timeShare16: frameTimeMs > 0 ? round((100 * (frameTimeMs - lateMs16)) / frameTimeMs) : null,
    share8: round(within(LATE_8_MS)),
    share16: round(within(LATE_16_MS)),
    jankMs: round(sum(intervals.map((value) => Math.max(0, value - FRAME_60HZ_MS)))),
    slowFrames8: intervals.filter((value) => value > LATE_8_MS).length,
    slowFrames16: intervals.filter((value) => value > LATE_16_MS).length,
    frameP95: intervals.length ? round(percentile(intervals, 0.95)) : null,
    frameMax: intervals.length ? round(Math.max(...intervals)) : null,
  };
  return record;
}

/** Joins the runs of the same scenario: per interaction, the pooled record of its rounds (commit durations concatenate). */
export function mergeRounds(rounds) {
  const names = [];
  for (const run of rounds) for (const name of Object.keys(run)) if (!names.includes(name)) names.push(name);
  const merged = {};
  for (const name of names) {
    const records = rounds.map((run) => run[name]).filter(Boolean);
    const joined = pool(records);
    joined.rounds = records.length;
    joined.layoutPasses = sum(records.map((record) => record.layoutPasses ?? 0));
    joined.blockingMs = round(sum(records.map((record) => record.blockingMs ?? 0)));
    joined.windowMs = round(sum(records.map((record) => record.windowMs ?? 0)));
    joined.share8 = records.some((record) => record.frames) ? round((100 * sum(records.map((record) => ((record.share8 ?? 0) * record.frames) / 100))) / sum(records.map((record) => record.frames))) : null;
    joined.share16 = records.some((record) => record.frames) ? round((100 * sum(records.map((record) => ((record.share16 ?? 0) * record.frames) / 100))) / sum(records.map((record) => record.frames))) : null;
    joined.frameP95 = round(percentile(records.map((record) => record.frameP95).filter(Number.isFinite), 0.95));
    merged[name] = joined;
  }
  return merged;
}

async function loadScenario(path) {
  const module = await import(pathToFileURL(resolve(path)).href);
  const scenario = module.default ?? module;
  if (typeof scenario.run !== "function") throw new Error(`${path}: the scenario must export a run({ page, interact, ... }) function`);
  return { name: "scenario", path: "/", viewport: { width: 1280, height: 800 }, warmupMs: 1500, quietMs: 300, maxMs: 2500, ...scenario };
}

// Lifts the 60 Hz requestAnimationFrame cap of headless Chromium; the other flags keep a background run at full speed.
const FRAME_FLAGS = ["--disable-frame-rate-limit", "--disable-gpu-vsync"];
const STEADY_FLAGS = ["--disable-renderer-backgrounding", "--disable-background-timer-throttling", "--disable-backgrounding-occluded-windows"];

/** One run of the scenario in a fresh browser at CPU throttling rate `cpu`: { interaction: record }. */
export async function runOnce({ base, scenario, cpu, engine, frameRate }) {
  const args = engine === "chromium" ? [...STEADY_FLAGS, ...(frameRate === "uncapped" ? FRAME_FLAGS : [])] : [];
  const browser = await launch({ engine, args });
  try {
    const context = await browser.newContext({ viewport: scenario.viewport, baseURL: base, deviceScaleFactor: 1 });
    await scenario.prepare?.({ context, base, env: process.env });
    const page = await context.newPage();
    const problems = [];
    page.on("pageerror", (error) => problems.push(String(error)));
    await page.addInitScript(installRecorder);
    await page.goto(`${scenario.path}${scenario.path.includes("?") ? "&" : "?"}swuidiag`);
    await scenario.ready?.({ page, context, base });
    await page.waitForFunction(() => !!window.__performanceMetrics && !!window.__embeddedSession?.metrics, undefined, { timeout: 30_000 });
    if (cpu > 1) {
      if (engine !== "chromium") throw new Error("CPU throttling needs Chromium (Emulation.setCPUThrottlingRate)");
      const cdp = await context.newCDPSession(page);
      await cdp.send("Emulation.setCPUThrottlingRate", { rate: cpu });
    }
    await page.waitForTimeout(scenario.warmupMs);
    const results = {};
    const interact = async (name, action, { quietMs = scenario.quietMs, maxMs = scenario.maxMs } = {}) => {
      if (name in results) throw new Error(`interaction '${name}' runs twice`);
      await page.evaluate(() => window.__frameBudget.begin());
      await action();
      const raw = await page.evaluate(([quiet, max]) => window.__frameBudget.finish(quiet, max), [quietMs, maxMs]);
      results[name] = windowMetrics(raw);
    };
    await scenario.run({ page, context, base, interact, cpu, viewport: scenario.viewport });
    if (problems.length) throw new Error(`page errors: ${problems.slice(0, 3).join(" | ")}`);
    return results;
  } finally {
    await browser.close().catch(() => {});
  }
}

/** Serves the bundle and measures every selected profile of the budget file; returns the measurement file's content. */
export async function measureAll({ budgets, values }) {
  if (!values.bundle || !values.scenario) throw new Error("run needs --bundle <dir> and --scenario <module>");
  const rounds = Number(values.rounds);
  if (!Number.isInteger(rounds) || rounds < 1) throw new Error("--rounds must be a positive integer");
  if (!["uncapped", "default"].includes(values["frame-rate"])) throw new Error("--frame-rate is uncapped or default");
  const names = values.profiles ? values.profiles.split(",") : Object.keys(budgets.profiles);
  for (const name of names) if (!budgets.profiles[name]) throw new Error(`unknown profile '${name}' (the budget file has ${Object.keys(budgets.profiles).join(", ")})`);
  const engine = values.engine ?? engineName();
  const scenario = await loadScenario(values.scenario);
  if (values["api-origin"]) {
    process.env.SWIFTUIWEB_API_ORIGIN = values["api-origin"];
    process.env.SWIFTUIWEB_API_PATH = values["api-path"] ?? process.env.SWIFTUIWEB_API_PATH ?? "/api";
  } else if (values["api-path"]) process.env.SWIFTUIWEB_API_PATH = values["api-path"];
  const server = await serveBundle({ bundle: values.bundle, port: Number(values.port), logName: "frame-budgets" });
  try {
    const profiles = {};
    for (const name of names) {
      const cpu = budgets.profiles[name].cpu;
      const runs = [];
      for (let round = 0; round < rounds; round += 1) {
        process.stderr.write(`${name} (CPU ${cpu}x) round ${round + 1}/${rounds}\n`);
        let outcome = null;
        for (let attempt = 0; attempt < 2 && !outcome; attempt += 1) {
          try {
            outcome = await runOnce({ base: server.base, scenario, cpu, engine, frameRate: values["frame-rate"] });
          } catch (error) {
            process.stderr.write(`  failed (${error.message.split("\n")[0]})${attempt === 0 ? ", retrying once" : ""}\n`);
            if (attempt === 1) throw error;
          }
        }
        runs.push(outcome);
      }
      profiles[name] = { cpu, rounds, interactions: mergeRounds(runs) };
    }
    return {
      schemaVersion: 1,
      generatedAt: new Date().toISOString(),
      meta: { scenario: scenario.name, bundle: resolve(values.bundle), engine, frameRate: values["frame-rate"], rounds, viewport: scenario.viewport },
      profiles,
    };
  } finally {
    await server.stop();
  }
}
