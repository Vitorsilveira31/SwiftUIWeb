// Statistics for Tools/perf-ab.mjs: summaries of the per-round samples of one metric and the decision whether bundle B
// differs from bundle A by more than the noise of the runs. Pure functions, no I/O (tested by Tools/test-perf-ab-stats.mjs).
//
// Two independent tests have to agree before a difference is reported, because a benchmark that finds a "win" in noise
// costs more than one that misses a small win:
//   - a bootstrap confidence interval of the difference of the medians that excludes zero, and
//   - a two-sided rank test with p below `alpha` (Wilcoxon signed-rank on the per-round differences for `comparePaired`,
//     the default of the tool; Mann-Whitney U for independent samples, `compare`);
// and the difference must also be at least `minEffect` (relative) and `minAbsolute` (the metric's own unit), so a
// statistically visible but irrelevant change (0.3 ms on 40 ms) does not count.

/** Numbers of a sample, sorted ascending; NaN and non-numbers are dropped. */
export function sorted(values) {
  return values.filter((value) => typeof value === "number" && Number.isFinite(value)).sort((a, b) => a - b);
}

export function mean(values) {
  const xs = sorted(values);
  return xs.length === 0 ? NaN : xs.reduce((sum, value) => sum + value, 0) / xs.length;
}

/** Linear-interpolated quantile, `p` in [0, 1]; NaN for an empty sample. */
export function quantile(values, p) {
  const xs = sorted(values);
  if (xs.length === 0) return NaN;
  const position = Math.min(1, Math.max(0, p)) * (xs.length - 1);
  const low = Math.floor(position);
  const high = Math.ceil(position);
  return xs[low] + (xs[high] - xs[low]) * (position - low);
}

export function median(values) {
  return quantile(values, 0.5);
}

/** Interquartile range: the spread of the middle half of the runs. */
export function iqr(values) {
  return quantile(values, 0.75) - quantile(values, 0.25);
}

/** Median absolute deviation from the median. */
export function mad(values) {
  const center = median(values);
  return median(sorted(values).map((value) => Math.abs(value - center)));
}

/** Deterministic generator (mulberry32) so a report is reproducible from its samples. */
export function seededRandom(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Standard normal cumulative distribution (Abramowitz-Stegun 7.1.26 through erf; error below 1.5e-7). */
export function normalCdf(z) {
  const x = Math.abs(z) / Math.SQRT2;
  const t = 1 / (1 + 0.3275911 * x);
  const poly = t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))));
  const erf = 1 - poly * Math.exp(-x * x);
  return z >= 0 ? 0.5 * (1 + erf) : 0.5 * (1 - erf);
}

/**
 * Two-sided Mann-Whitney U test (normal approximation with tie and continuity corrections).
 * Returns `{ u, z, p }` where `u` is the U statistic of sample `a`. Identical samples give p = 1.
 */
export function mannWhitney(a, b) {
  const xs = sorted(a);
  const ys = sorted(b);
  const n = xs.length;
  const m = ys.length;
  if (n === 0 || m === 0) return { u: NaN, z: NaN, p: NaN };
  const pooled = [...xs.map((value) => ({ value, from: 0 })), ...ys.map((value) => ({ value, from: 1 }))].sort(
    (left, right) => left.value - right.value
  );
  let rankSumA = 0;
  let tieTerm = 0;
  for (let start = 0; start < pooled.length; ) {
    let end = start;
    while (end + 1 < pooled.length && pooled[end + 1].value === pooled[start].value) end += 1;
    const rank = (start + end) / 2 + 1;
    const size = end - start + 1;
    for (let index = start; index <= end; index += 1) if (pooled[index].from === 0) rankSumA += rank;
    tieTerm += size ** 3 - size;
    start = end + 1;
  }
  const u = rankSumA - (n * (n + 1)) / 2;
  const total = n + m;
  const mu = (n * m) / 2;
  const variance = ((n * m) / 12) * (total + 1 - tieTerm / (total * (total - 1)));
  if (variance <= 0) return { u, z: 0, p: 1 };
  const distance = Math.abs(u - mu);
  const z = (Math.max(0, distance - 0.5) / Math.sqrt(variance)) * Math.sign(u - mu);
  return { u, z, p: Math.min(1, 2 * (1 - normalCdf(Math.abs(z)))) };
}

/**
 * Percentile bootstrap interval of median(b) - median(a), resampling each side independently.
 * `confidence` is the two-sided level (0.99 leaves 0.5% in each tail).
 */
export function bootstrapMedianDifference(a, b, { iterations = 4000, confidence = 0.99, seed = 1 } = {}) {
  const xs = sorted(a);
  const ys = sorted(b);
  if (xs.length === 0 || ys.length === 0) return { low: NaN, high: NaN };
  const random = seededRandom(seed);
  const draw = (values) => {
    const sample = new Array(values.length);
    for (let index = 0; index < values.length; index += 1) sample[index] = values[Math.floor(random() * values.length)];
    return median(sample);
  };
  const differences = new Array(iterations);
  for (let index = 0; index < iterations; index += 1) differences[index] = draw(ys) - draw(xs);
  const tail = (1 - confidence) / 2;
  return { low: quantile(differences, tail), high: quantile(differences, 1 - tail) };
}

/**
 * Two-sided Wilcoxon signed-rank test of paired differences (normal approximation with tie and continuity corrections;
 * zero differences are dropped). Returns `{ w, z, p, n }`; no non-zero difference gives p = 1.
 */
export function wilcoxonSignedRank(differences) {
  const nonzero = sorted(differences).filter((value) => value !== 0);
  const n = nonzero.length;
  if (n === 0) return { w: 0, z: 0, p: differences.length ? 1 : NaN, n };
  const ordered = nonzero.map((value) => ({ value, size: Math.abs(value) })).sort((a, b) => a.size - b.size);
  let positive = 0;
  let tieTerm = 0;
  for (let start = 0; start < n; ) {
    let end = start;
    while (end + 1 < n && ordered[end + 1].size === ordered[start].size) end += 1;
    const rank = (start + end) / 2 + 1;
    for (let index = start; index <= end; index += 1) if (ordered[index].value > 0) positive += rank;
    const size = end - start + 1;
    tieTerm += size ** 3 - size;
    start = end + 1;
  }
  const mu = (n * (n + 1)) / 4;
  const variance = (n * (n + 1) * (2 * n + 1)) / 24 - tieTerm / 48;
  if (variance <= 0) return { w: positive, z: 0, p: 1, n };
  const z = (Math.max(0, Math.abs(positive - mu) - 0.5) / Math.sqrt(variance)) * Math.sign(positive - mu);
  return { w: positive, z, p: Math.min(1, 2 * (1 - normalCdf(Math.abs(z)))), n };
}

/** Percentile bootstrap interval of the median of `values`. */
export function bootstrapMedian(values, { iterations = 4000, confidence = 0.99, seed = 1 } = {}) {
  const xs = sorted(values);
  if (xs.length === 0) return { low: NaN, high: NaN };
  const random = seededRandom(seed);
  const medians = new Array(iterations);
  for (let index = 0; index < iterations; index += 1) {
    const sample = new Array(xs.length);
    for (let item = 0; item < xs.length; item += 1) sample[item] = xs[Math.floor(random() * xs.length)];
    medians[index] = median(sample);
  }
  const tail = (1 - confidence) / 2;
  return { low: quantile(medians, tail), high: quantile(medians, 1 - tail) };
}

/**
 * Compares A and B round by round: `a[i]` and `b[i]` were measured next to each other in time (one alternation
 * apart), so the load of the machine at that moment is shared and cancels in `b[i] - a[i]`. That removes the slow drift
 * an independent comparison has to treat as noise. The difference reported is the median of the paired differences,
 * its interval a bootstrap over pairs, the test a Wilcoxon signed-rank test; the thresholds are those of `compare`.
 * Pairs with a missing side must be removed by the caller (arrays of equal length, aligned by round).
 */
export function comparePaired(a, b, options = {}) {
  const { alpha = 0.01, confidence = 0.99, minEffect = 0.05, minAbsolute = 0, iterations = 4000, seed = 1 } = options;
  if (a.length !== b.length) throw new Error("comparePaired needs equally long, round-aligned samples");
  const pairs = a.map((value, index) => [value, b[index]]).filter(([x, y]) => Number.isFinite(x) && Number.isFinite(y));
  const xs = pairs.map(([x]) => x);
  const ys = pairs.map(([, y]) => y);
  const differences = pairs.map(([x, y]) => y - x);
  const medianA = median(xs);
  const medianB = median(ys);
  const difference = median(differences);
  const relative = medianA === 0 ? (difference === 0 ? 0 : Math.sign(difference) * Infinity) : difference / Math.abs(medianA);
  const result = {
    n: [xs.length, ys.length], medianA, medianB, difference, relative,
    iqrA: iqr(xs), iqrB: iqr(ys), madA: mad(xs), madB: mad(ys), iqrDifference: iqr(differences),
    ci: { low: NaN, high: NaN }, p: NaN, verdict: "too few samples", paired: true
  };
  if (pairs.length < 6) return result;
  result.ci = bootstrapMedian(differences, { iterations, confidence, seed });
  result.p = wilcoxonSignedRank(differences).p;
  const ciExcludesZero = result.ci.low > 0 || result.ci.high < 0;
  const large = Math.abs(relative) >= minEffect && Math.abs(difference) >= minAbsolute;
  if (ciExcludesZero && result.p < alpha && large) result.verdict = difference > 0 ? "B higher" : "B lower";
  else result.verdict = "no significant difference";
  return result;
}

/**
 * Compares the samples of one metric for bundle A and bundle B.
 *
 * Options: `alpha` (default 0.01), `confidence` (default 0.99, the bootstrap level), `minEffect` (relative change of the
 * median, default 0.05), `minAbsolute` (default 0, in the metric's unit), `iterations`, `seed`.
 * Verdicts: `"B higher"` / `"B lower"` when the difference is larger than the noise, else `"no significant difference"`;
 * `"too few samples"` below 4 runs per side (the Mann-Whitney test cannot reach `alpha` there).
 */
export function compare(a, b, options = {}) {
  const { alpha = 0.01, confidence = 0.99, minEffect = 0.05, minAbsolute = 0, iterations = 4000, seed = 1 } = options;
  const xs = sorted(a);
  const ys = sorted(b);
  const medianA = median(xs);
  const medianB = median(ys);
  const difference = medianB - medianA;
  const relative = medianA === 0 ? (difference === 0 ? 0 : Math.sign(difference) * Infinity) : difference / Math.abs(medianA);
  const result = {
    n: [xs.length, ys.length],
    medianA,
    medianB,
    difference,
    relative,
    iqrA: iqr(xs),
    iqrB: iqr(ys),
    madA: mad(xs),
    madB: mad(ys),
    ci: { low: NaN, high: NaN },
    p: NaN,
    verdict: "too few samples"
  };
  if (xs.length < 4 || ys.length < 4) return result;
  result.ci = bootstrapMedianDifference(xs, ys, { iterations, confidence, seed });
  result.p = mannWhitney(xs, ys).p;
  const ciExcludesZero = result.ci.low > 0 || result.ci.high < 0;
  const large = Math.abs(relative) >= minEffect && Math.abs(difference) >= minAbsolute;
  if (ciExcludesZero && result.p < alpha && large) result.verdict = difference > 0 ? "B higher" : "B lower";
  else result.verdict = "no significant difference";
  return result;
}
