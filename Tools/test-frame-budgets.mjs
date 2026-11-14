#!/usr/bin/env bun
// Tools/frame-budgets.mjs and Tools/frame-measure.mjs: the budget evaluation, pooling and the window metrics. No browser.
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { DEFAULT_BUDGETS, evaluate, formatReport, judge, main, percentile, POOLED, pool, pooledProfiles, summarize, validateBudgets, verdict } from "./frame-budgets.mjs";
import { mergeRounds, windowMetrics } from "./frame-measure.mjs";
import { finish,ROOT, test, withTemporary } from "./measurement-test-support.mjs";

const BUDGETS = JSON.parse(readFileSync(DEFAULT_BUDGETS, "utf8"));

/** A raw window: frames every `step` ms for `count` frames, with one stall of `stall` ms at frame `at`. */
function rawWindow({ step = 8.3, count = 100, stall = 0, at = 50, durations = [2, 3], tasks = [] } = {}) {
  const frames = [];
  let time = 1000;
  for (let index = 0; index < count; index += 1) {
    frames.push(time);
    time += index === at ? stall || step : step;
  }
  return { t0: 1000, t1: time + 100, activeEnd: time, tasks, frames, commitDurations: durations, commits: durations.length, maxCommitMs: Math.max(...durations), layoutMs: 1, layoutPasses: 2 };
}

const record = (overrides = {}) => ({ ...windowMetrics(rawWindow()), ...overrides });
const measurements = (desktop, phone = {}) => ({ schemaVersion: 1, profiles: { desktop: { cpu: 1, interactions: desktop }, phone: { cpu: 4, interactions: phone } } });
const find = (evaluation, budget, interaction) => evaluation.results.find((result) => result.budget === budget && result.interaction === interaction);

await test("the checked-in budget file is valid and every budget has a rationale and a unit", () => {
  assert.deepEqual(validateBudgets(BUDGETS), []);
  for (const budget of BUDGETS.budgets) {
    assert.ok(budget.rationale, budget.name);
    assert.ok(budget.unit, budget.name);
  }
  assert.equal(BUDGETS.profiles.desktop.cpu, 1);
  assert.equal(BUDGETS.profiles.phone.cpu, 4);
  // The targets of the program: 8.3 ms per commit, no long task, 99% within 16.7 ms, no slow frame on the phone profile.
  const byName = Object.fromEntries(BUDGETS.budgets.map((budget) => [budget.name, budget]));
  assert.equal(byName["desktop-commit-p95"].max, 8.3);
  assert.equal(byName["desktop-long-tasks"].max, 0);
  assert.equal(byName["desktop-frames-within-16ms"].min, 99);
  assert.equal(byName["phone-no-slow-frame"].max, 0);
});

await test("every budget starts in report mode", () => {
  assert.equal(BUDGETS.enforcement, "report");
  for (const budget of BUDGETS.budgets) assert.ok((budget.enforcement ?? BUDGETS.enforcement) === "report", budget.name);
});

await test("a broken budget file is rejected, not silently ignored", () => {
  assert.deepEqual(validateBudgets({}), ["budgets must be an array"]);
  const problems = validateBudgets({
    profiles: { a: { cpu: 1 } },
    budgets: [{ name: "x", profile: "b", scope: "some", metric: "m" }, { name: "x", profile: "a", scope: "each" }, { name: "y", profile: "a", scope: "each", metric: "m", enforcement: "maybe" }],
  });
  assert.deepEqual(problems, [
    "x: unknown profile b", "x: scope must be each or pooled", "x: duplicate name", "x: no metric", "y: enforcement must be report or enforce",
  ]);
});

await test("percentile is the nearest rank", () => {
  assert.equal(percentile([], 0.95), null);
  assert.equal(percentile([5], 0.95), 5);
  const hundred = Array.from({ length: 100 }, (_, index) => index + 1);
  assert.equal(percentile(hundred, 0.95), 95);
  assert.equal(percentile([...hundred].reverse(), 0.5), 50);
  assert.equal(percentile([1, 2, 3, 4], 0.95), 4);
  assert.equal(percentile([1, 2, 3, 4], 0.25), 1);
});

await test("judge compares with max and min and tells a missing value from a pass", () => {
  assert.equal(judge({ max: 8.3 }, 8.3), "pass");
  assert.equal(judge({ max: 8.3 }, 8.31), "over");
  assert.equal(judge({ min: 99 }, 99), "pass");
  assert.equal(judge({ min: 99 }, 98.9), "over");
  assert.equal(judge({ max: 0 }, 0), "pass");
  assert.equal(judge({ max: 0 }, 1), "over");
  assert.equal(judge({}, 12), "info");
  assert.equal(judge({ max: 1 }, null), "missing");
  assert.equal(judge({ max: 1 }, undefined), "missing");
  assert.equal(judge({ max: 1 }, Number.NaN), "missing");
});

await test("window metrics: commit percentile, long tasks and frame shares", () => {
  const smooth = windowMetrics(rawWindow({ durations: Array.from({ length: 20 }, (_, index) => index + 1) }));
  assert.equal(smooth.commits, 20);
  assert.equal(smooth.commitP95Ms, 19);
  assert.equal(smooth.maxCommitMs, 20);
  assert.equal(smooth.slowFrames16, 0);
  assert.equal(smooth.timeShare16, 100);
  assert.equal(smooth.timeShare8, 100);
  assert.equal(smooth.longTaskCount, 0);

  // One 60 ms stall among 99 frames of 8.3 ms: late by both limits, and a long task.
  const stalled = windowMetrics(rawWindow({ stall: 60, tasks: [[1400, 60]] }));
  assert.equal(stalled.slowFrames16, 1);
  assert.equal(stalled.slowFrames8, 1);
  assert.equal(stalled.longTaskCount, 1);
  assert.equal(stalled.longTaskMaxMs, 60);
  assert.equal(stalled.blockingMs, 10);
  const total = 98 * 8.3 + 60;
  assert.ok(Math.abs(stalled.frameTimeMs - total) < 0.01, String(stalled.frameTimeMs));
  assert.ok(Math.abs(stalled.timeShare16 - (100 * (total - 60)) / total) < 0.01);
  assert.ok(stalled.share16 > 98 && stalled.share16 < 100);
});

await test("a 60 Hz interval is on time for 60 fps and late for 120 fps", () => {
  const sixty = windowMetrics(rawWindow({ step: 16.7 }));
  assert.equal(sixty.slowFrames16, 0);
  assert.equal(sixty.timeShare16, 100);
  assert.equal(sixty.timeShare8, 0);
  assert.equal(windowMetrics(rawWindow({ step: 16.8 })).slowFrames16, 0, "timestamp rounding of 0.1 ms is tolerated");
  assert.equal(windowMetrics(rawWindow({ step: 17 })).slowFrames16, 99);
});

await test("an uncapped requestAnimationFrame does not inflate the time share", () => {
  const raw = rawWindow({ step: 1, count: 400, stall: 100, at: 200 });
  const metrics = windowMetrics(raw);
  assert.ok(metrics.share16 > 99.5, "count-based share is inflated by the many short intervals");
  assert.ok(metrics.timeShare16 < 80, `time-based share sees the stall: ${metrics.timeShare16}`);
});

await test("frames after the last activity and before the start are ignored", () => {
  const raw = rawWindow();
  raw.frames = [900, 950, ...raw.frames, raw.activeEnd + 500, raw.activeEnd + 1500];
  const metrics = windowMetrics(raw);
  assert.equal(metrics.frames, 99);
  assert.equal(metrics.slowFrames16, 0);
});

await test("an interaction without frames or commits has empty metrics, not NaN", () => {
  const metrics = windowMetrics({ t0: 0, t1: 10, activeEnd: 0, tasks: [], frames: [], commitDurations: [], commits: 0 });
  assert.equal(metrics.commitP95Ms, null);
  assert.equal(metrics.timeShare16, null);
  assert.equal(metrics.frames, 0);
  assert.equal(judge({ max: 8.3 }, metrics.commitP95Ms), "missing");
});

await test("pooling concatenates commits, adds counts and recomputes the shares", () => {
  const fast = windowMetrics(rawWindow({ durations: [1, 1, 1, 1] }));
  const slow = windowMetrics(rawWindow({ durations: [30], stall: 60, tasks: [[1400, 60]] }));
  const all = pool([fast, slow], { countInteractions: true });
  assert.equal(all.commits, 5);
  assert.equal(all.commitDurationsMs.length, 5);
  assert.equal(all.commitP95Ms, 30);
  assert.equal(all.longTaskCount, 1);
  assert.equal(all.slowFrames16, 1);
  assert.equal(all.interactions, 2);
  assert.equal(all.interactionsWithoutSlowFrame, 1);
  assert.equal(all.shareInteractionsWithoutSlowFrame, 50);
  const frameTime = fast.frameTimeMs + slow.frameTimeMs;
  assert.ok(Math.abs(all.timeShare16 - (100 * (frameTime - 60)) / frameTime) < 0.01);
});

await test("merging rounds pools the commits of the same interaction", () => {
  const roundOne = { open: windowMetrics(rawWindow({ durations: [1, 2] })), close: windowMetrics(rawWindow({ durations: [3] })) };
  const roundTwo = { open: windowMetrics(rawWindow({ durations: [9, 9] })) };
  const merged = mergeRounds([roundOne, roundTwo]);
  assert.deepEqual(Object.keys(merged), ["open", "close"]);
  assert.equal(merged.open.rounds, 2);
  assert.equal(merged.open.commits, 4);
  assert.deepEqual(merged.open.commitDurationsMs, [1, 2, 9, 9]);
  assert.equal(merged.open.commitP95Ms, 9);
  assert.equal(merged.close.rounds, 1);
});

await test("each-scope budgets give one result per interaction and pooled ones a single result", () => {
  const evaluation = evaluate(BUDGETS, measurements({ a: record(), b: record({ commitP95Ms: 25 }) }, { a: record() }));
  assert.equal(find(evaluation, "desktop-commit-p95", "a").status, "pass");
  assert.equal(find(evaluation, "desktop-commit-p95", "b").status, "over");
  assert.equal(find(evaluation, "desktop-commit-p95", "b").value, 25);
  const pooled = evaluation.results.filter((result) => result.budget === "desktop-commit-p95-all");
  assert.equal(pooled.length, 1);
  assert.equal(pooled[0].interaction, POOLED);
});

await test("an unlimited budget is reported as info and never counts as over", () => {
  const evaluation = evaluate(BUDGETS, measurements({ a: record() }));
  assert.equal(find(evaluation, "desktop-frames-within-8ms-each", "a").status, "info");
  assert.equal(find(evaluation, "desktop-frames-within-8ms", POOLED).status, "info");
});

await test("a profile that was not measured is missing, in every budget of it", () => {
  const evaluation = evaluate(BUDGETS, { profiles: { desktop: { cpu: 1, interactions: { a: record() } } } });
  const phone = evaluation.results.filter((result) => result.profile === "phone");
  assert.ok(phone.length > 0);
  assert.ok(phone.every((result) => result.status === "missing"));
});

await test("a metric a record lacks is missing, not zero", () => {
  const bare = { commits: 1 };
  const evaluation = evaluate(BUDGETS, measurements({ a: bare }));
  assert.equal(find(evaluation, "desktop-commit-p95", "a").status, "missing");
  assert.equal(find(evaluation, "desktop-long-tasks", "a").status, "missing");
});

await test("the budget's interactions list narrows an each-scope budget", () => {
  const file = { enforcement: "report", profiles: { desktop: { cpu: 1 } }, budgets: [{ name: "n", profile: "desktop", scope: "each", metric: "commitP95Ms", max: 1, interactions: ["b"] }] };
  const evaluation = evaluate(file, measurements({ a: record(), b: record() }));
  assert.deepEqual(evaluation.results.map((result) => result.interaction), ["b"]);
});

await test("report mode never fails and enforce mode fails on over and missing results", () => {
  const data = measurements({ a: record({ commitP95Ms: 25 }) });
  const report = evaluate(BUDGETS, data);
  assert.equal(report.verdict.exitCode, 0);
  assert.equal(report.verdict.failing, 0);
  assert.ok(report.verdict.reportedOver > 0);
  const enforce = evaluate(BUDGETS, data, { mode: "enforce" });
  assert.equal(enforce.verdict.exitCode, 1);
  assert.ok(enforce.verdict.failing >= report.verdict.reportedOver);
  assert.ok(enforce.results.every((result) => result.enforcement === "enforce"));
  const forcedReport = evaluate({ ...BUDGETS, enforcement: "enforce" }, data, { mode: "report" });
  assert.equal(forcedReport.verdict.exitCode, 0);
});

await test("one budget can be enforced while the others report", () => {
  const file = { ...BUDGETS, budgets: BUDGETS.budgets.map((budget) => (budget.name === "desktop-long-tasks" ? { ...budget, enforcement: "enforce" } : budget)) };
  const clean = evaluate(file, measurements({ a: record({ commitP95Ms: 25 }) }));
  assert.equal(clean.verdict.exitCode, 0, "an over commit budget in report mode does not fail");
  const stalled = evaluate(file, measurements({ a: record({ longTaskCount: 2 }) }));
  assert.equal(stalled.verdict.exitCode, 1);
  assert.equal(stalled.verdict.failing, 1);
});

await test("the summary counts results per budget and keeps the worst value", () => {
  const evaluation = evaluate(BUDGETS, measurements({ a: record({ commitP95Ms: 4 }), b: record({ commitP95Ms: 25 }), c: record({ commitP95Ms: 12 }) }));
  const entry = summarize(evaluation.results).find((item) => item.budget === "desktop-commit-p95");
  assert.equal(entry.total, 3);
  assert.equal(entry.over, 2);
  assert.equal(entry.pass, 1);
  assert.equal(entry.worst, 25);
  const share = summarize(evaluation.results).find((item) => item.budget === "desktop-frames-within-16ms");
  assert.equal(share.total, 1);
  assert.equal(verdict([]).exitCode, 0);
});

await test("pooled profiles feed the pooled budgets", () => {
  const data = measurements({ a: record({ slowFrames16: 0 }), b: record({ slowFrames16: 3 }) }, { a: record({ slowFrames16: 0 }), b: record({ slowFrames16: 3 }), c: record({ slowFrames16: 0 }) });
  const pooled = pooledProfiles(data);
  assert.equal(pooled.phone.shareInteractionsWithoutSlowFrame, round2((100 * 2) / 3));
  const evaluation = evaluate(BUDGETS, data);
  assert.equal(find(evaluation, "phone-interactions-without-slow-frame", POOLED).status, "pass");
  assert.equal(find(evaluation, "phone-no-slow-frame", "b").status, "over");
});

function round2(value) {
  return Number(value.toFixed(3));
}

await test("the report prints a row per result, a summary and the closing line", () => {
  const evaluation = evaluate(BUDGETS, measurements({ a: record({ commitP95Ms: 25 }) }));
  const output = formatReport(evaluation);
  assert.match(output, /desktop\s+a\s+desktop-commit-p95\s+25\.0 ms\s+<= 8\.3\s+OVER\s+report/);
  assert.match(output, /REPORT frame budgets: \d+ of \d+ results over budget or missing; nothing enforced/);
  const problems = formatReport(evaluation, { onlyProblems: true });
  assert.ok(!/\sinfo\s/.test(problems.split("\n\n")[0]));
  assert.match(formatReport(evaluate(BUDGETS, measurements({ a: record({ commitP95Ms: 25 }) }), { mode: "enforce" })), /FAIL frame budgets: \d+ enforced results over budget/);
});

await test("the evaluate command writes the JSON report and exits 0 in report mode and 1 when enforced", () =>
  withTemporary(async (directory) => {
    const input = join(directory, "measurements.json");
    writeFileSync(input, JSON.stringify(measurements({ a: record({ commitP95Ms: 25 }) }, { a: record() })));
    const out = join(directory, "report.json");
    assert.equal(await main(["evaluate", "--measurements", input, "--json", out, "--quiet"]), 0);
    const written = JSON.parse(readFileSync(out, "utf8"));
    assert.equal(written.schemaVersion, 1);
    assert.equal(written.verdict.failing, 0);
    assert.ok(written.results.some((result) => result.status === "over"));
    assert.ok(written.summary.length > 0);
    const enforced = await main(["evaluate", "--measurements", input, "--mode", "enforce", "--quiet"]);
    assert.equal(enforced, 1);
  }));

await test("the command line shows usage for an unknown command and rejects a bad mode", async () => {
  const bad = Bun.spawnSync(["bun", join(ROOT, "Tools/frame-budgets.mjs"), "nope"], { stdout: "pipe", stderr: "pipe" });
  assert.equal(bad.exitCode, 2);
  assert.match(bad.stderr.toString(), /usage: bun Tools\/frame-budgets\.mjs/);
  const mode = Bun.spawnSync(["bun", join(ROOT, "Tools/frame-budgets.mjs"), "evaluate", "--measurements", "x", "--mode", "loud"], { stdout: "pipe", stderr: "pipe" });
  assert.equal(mode.exitCode, 1);
  assert.match(mode.stderr.toString(), /--mode is default, report or enforce/);
});

await test("make targets run the Bun tool", () => {
  for (const target of ["perf-frames-check"]) {
    const make = Bun.spawnSync(["make", "-n", target, "FRAMES=x.json"], { cwd: ROOT, stdout: "pipe", stderr: "pipe" });
    assert.match(make.stdout.toString(), /bun Tools\/frame-budgets\.mjs evaluate/, target);
  }
});

await test("an each-scope budget over a profile with no interactions is missing, not passed", () => {
  const budgets = { budgets: [{ name: "fps", profile: "desktop", scope: "each", metric: "fps", min: 50 }] };
  const result = evaluate(budgets, measurements({}), { mode: "enforce" });
  assert.deepEqual(result.results.map((row) => row.status), ["missing"]);
  assert.equal(verdict(result.results).exitCode, 1);
});

finish();
