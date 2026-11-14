#!/usr/bin/env bun
// Tests the statistics of Tools/perf-ab.mjs: summaries, the Mann-Whitney test, the bootstrap interval, and that
// `compare` calls a real shift a difference and equal-distribution noise "no significant difference".
import assert from "node:assert/strict";
import test from "node:test";
import {
  bootstrapMedianDifference,
  compare,
  comparePaired,
  iqr,
  mad,
  mannWhitney,
  mean,
  median,
  normalCdf,
  quantile,
  seededRandom,
  wilcoxonSignedRank
} from "./perf-ab-stats.mjs";

const near = (actual, expected, tolerance, label) =>
  assert.ok(Math.abs(actual - expected) <= tolerance, `${label ?? "value"}: ${actual} is not within ${tolerance} of ${expected}`);

/** A run-to-run noise model: a base cost times log-normal noise with the given relative sigma. */
function noisy(random, base, sigma, count) {
  return Array.from({ length: count }, () => {
    const gaussian = Math.sqrt(-2 * Math.log(1 - random())) * Math.cos(2 * Math.PI * random());
    return base * Math.exp(sigma * gaussian);
  });
}

test("summaries ignore non-numbers and interpolate quantiles", () => {
  assert.equal(median([3, 1, 2]), 2);
  assert.equal(median([4, 1, 3, 2]), 2.5);
  assert.equal(median([1, NaN, undefined, 5, "x"]), 3);
  assert.equal(quantile([10, 20, 30, 40, 50], 0.25), 20);
  assert.equal(iqr([1, 2, 3, 4, 5]), 2);
  assert.equal(mad([1, 2, 3, 4, 100]), 1);
  assert.equal(mean([2, 4]), 3);
  assert.ok(Number.isNaN(median([])));
});

test("seeded generator is deterministic and in [0, 1)", () => {
  const first = seededRandom(7);
  const second = seededRandom(7);
  for (let index = 0; index < 50; index += 1) {
    const value = first();
    assert.equal(value, second());
    assert.ok(value >= 0 && value < 1);
  }
  assert.notEqual(seededRandom(7)(), seededRandom(8)());
});

test("normal cumulative distribution matches known values", () => {
  near(normalCdf(0), 0.5, 1e-7);
  near(normalCdf(1.96), 0.975, 1e-4);
  near(normalCdf(-1.96), 0.025, 1e-4);
  near(normalCdf(3), 0.99865, 1e-4);
});

test("Mann-Whitney: separated samples are significant, identical ones are not", () => {
  const separated = mannWhitney([1, 2, 3, 4, 5], [6, 7, 8, 9, 10]);
  assert.equal(separated.u, 0);
  assert.ok(separated.z < 0);
  near(separated.p, 0.0122, 0.001, "normal approximation of the exact 0.0079");
  const same = mannWhitney([5, 5, 5, 5], [5, 5, 5, 5]);
  assert.equal(same.p, 1);
  const interleaved = mannWhitney([1, 3, 5, 7, 9], [2, 4, 6, 8, 10]);
  assert.ok(interleaved.p > 0.5);
  assert.ok(Number.isNaN(mannWhitney([], [1]).p));
});

test("Mann-Whitney handles ties across the samples", () => {
  const result = mannWhitney([1, 1, 2, 2, 3, 3], [3, 3, 4, 4, 5, 5]);
  assert.ok(result.p < 0.05 && result.p > 0);
  // Swapping the samples mirrors z and keeps p.
  const swapped = mannWhitney([3, 3, 4, 4, 5, 5], [1, 1, 2, 2, 3, 3]);
  near(swapped.p, result.p, 1e-12);
  near(swapped.z, -result.z, 1e-12);
});

test("bootstrap interval covers the observed difference and is reproducible", () => {
  const a = [10, 11, 12, 13, 14, 10.5, 11.5, 12.5];
  const b = a.map((value) => value + 5);
  const first = bootstrapMedianDifference(a, b, { seed: 3 });
  const second = bootstrapMedianDifference(a, b, { seed: 3 });
  assert.deepEqual(first, second);
  assert.ok(first.low <= 5 && first.high >= 5);
  assert.ok(first.low > 0, "a shift of 5 on a spread of 4 excludes zero");
  assert.ok(Number.isNaN(bootstrapMedianDifference([], [1]).low));
});

test("compare reports a clear shift in both directions", () => {
  const random = seededRandom(11);
  const a = noisy(random, 30, 0.08, 12);
  const slower = compare(a, noisy(random, 39, 0.08, 12));
  assert.equal(slower.verdict, "B higher");
  near(slower.relative, 0.3, 0.2);
  assert.ok(slower.ci.low > 0);
  assert.ok(slower.p < 0.01);
  const faster = compare(a, noisy(random, 21, 0.08, 12));
  assert.equal(faster.verdict, "B lower");
  assert.ok(faster.ci.high < 0);
});

test("compare requires the effect to exceed minEffect and minAbsolute", () => {
  const a = [100, 100.2, 99.9, 100.1, 100, 99.8, 100.3, 100.1];
  const b = a.map((value) => value * 1.02);
  assert.equal(compare(a, b).verdict, "no significant difference", "2% is below the default 5%");
  assert.equal(compare(a, b, { minEffect: 0.01 }).verdict, "B higher");
  assert.equal(compare(a, b, { minEffect: 0.01, minAbsolute: 5 }).verdict, "no significant difference");
});

test("compare needs enough runs", () => {
  assert.equal(compare([1, 2, 3], [4, 5, 6]).verdict, "too few samples");
});

test("compare handles constant and zero metrics", () => {
  assert.equal(compare([0, 0, 0, 0], [0, 0, 0, 0]).verdict, "no significant difference");
  assert.equal(compare([6, 6, 6, 6, 6], [6, 6, 6, 6, 6]).relative, 0);
  assert.equal(compare([6, 6, 6, 6, 6], [7, 7, 7, 7, 7]).verdict, "B higher");
  assert.equal(compare([0, 0, 0, 0, 0], [3, 3, 3, 3, 3]).relative, Infinity);
});

test("A/A noise: the same distribution on both sides is almost never a difference", { timeout: 60_000 }, () => {
  const random = seededRandom(2026);
  let flagged = 0;
  const trials = 300;
  for (let trial = 0; trial < trials; trial += 1) {
    // 10 runs per side at 15% run-to-run noise, the band measured on real pages.
    const result = compare(noisy(random, 30, 0.15, 10), noisy(random, 30, 0.15, 10), { iterations: 600, seed: trial + 1 });
    if (result.verdict !== "no significant difference") flagged += 1;
  }
  assert.ok(flagged / trials <= 0.02, `${flagged} of ${trials} A/A comparisons were reported as a difference`);
});

test("power: a 25% shift is found with 20 runs at 15% noise most of the time", { timeout: 60_000 }, () => {
  const random = seededRandom(99);
  let found = 0;
  const trials = 100;
  for (let trial = 0; trial < trials; trial += 1) {
    const result = compare(noisy(random, 30, 0.15, 20), noisy(random, 37.5, 0.15, 20), { iterations: 600, seed: trial + 1 });
    if (result.verdict === "B higher") found += 1;
  }
  assert.ok(found / trials >= 0.8, `only ${found} of ${trials} real 25% shifts were found`);
});

test("Wilcoxon signed-rank: one-sided differences are significant, balanced ones are not", () => {
  const all = wilcoxonSignedRank([1, 2, 3, 4, 5, 6, 7, 8]);
  assert.equal(all.w, 36);
  near(all.p, 0.0143, 0.002, "normal approximation of the exact 0.0078");
  assert.ok(wilcoxonSignedRank([-3, 2, -1, 4, -5, 6, 1, -2]).p > 0.5);
  assert.equal(wilcoxonSignedRank([0, 0, 0]).p, 1);
  assert.ok(Number.isNaN(wilcoxonSignedRank([]).p));
  near(wilcoxonSignedRank([-1, -2, -3, -4, -5, -6, -7, -8]).z, -all.z, 1e-12);
});

/** Runs with a slow common drift (the load of a busy machine, shared by the two runs of a round) plus own noise. */
function drifting(random, count, shift, driftSigma = 0.25, ownSigma = 0.05) {
  const a = [];
  const b = [];
  for (let round = 0; round < count; round += 1) {
    const drift = noisy(random, 1, driftSigma, 1)[0];
    a.push(30 * drift * noisy(random, 1, ownSigma, 1)[0]);
    b.push(30 * (1 + shift) * drift * noisy(random, 1, ownSigma, 1)[0]);
  }
  return [a, b];
}

test("paired comparison sees a change that the drift hides from the independent one", { timeout: 60_000 }, () => {
  const random = seededRandom(5);
  let paired = 0;
  let independent = 0;
  const trials = 60;
  for (let trial = 0; trial < trials; trial += 1) {
    const [a, b] = drifting(random, 12, 0.15);
    if (comparePaired(a, b, { iterations: 600, seed: trial + 1 }).verdict === "B higher") paired += 1;
    if (compare(a, b, { iterations: 600, seed: trial + 1 }).verdict === "B higher") independent += 1;
  }
  assert.ok(paired / trials >= 0.8, `paired found ${paired} of ${trials}`);
  assert.ok(independent < paired, `independent found ${independent}, paired ${paired}`);
});

test("paired A/A under drift is almost never a difference", { timeout: 60_000 }, () => {
  const random = seededRandom(77);
  let flagged = 0;
  const trials = 300;
  for (let trial = 0; trial < trials; trial += 1) {
    const [a, b] = drifting(random, 12, 0);
    if (comparePaired(a, b, { iterations: 600, seed: trial + 1 }).verdict !== "no significant difference") flagged += 1;
  }
  assert.ok(flagged / trials <= 0.02, `${flagged} of ${trials} paired A/A comparisons were reported as a difference`);
});

test("paired comparison validates and reports small inputs", () => {
  assert.throws(() => comparePaired([1, 2], [1]), /round-aligned/);
  assert.equal(comparePaired([1, 2, 3], [2, 3, 4]).verdict, "too few samples");
  const result = comparePaired([10, 11, 12, 13, 14, 15, 16, 17, 18, 19, NaN], [20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 5]);
  assert.equal(result.n[0], 10, "a pair with a missing side is left out");
  assert.equal(result.verdict, "B higher");
  assert.equal(result.difference, 10);
});

test("the summary pools runs into a median row per interaction", async () => {
  const { summarize } = await import("./perf-ab-summary.mjs");
  const runs = [1, 2, 3, 4, 5].map((n) => ({ open: { commitMs: n * 10, commits: 2 }, total: { commitMs: n * 100, commits: null } }));
  const rows = summarize(runs, ["commitMs", "commits"]);
  assert.deepEqual(rows[0], ["open", "30.0 (20.0)", "2.0 (0.0)"]);
  assert.deepEqual(rows[1], ["total", "300 (200)", "-"]);
});
