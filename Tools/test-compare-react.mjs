// Run with: bun test ./Tools/test-compare-react.mjs
import { expect, test } from "bun:test";
import { markdown, summarize, throttleReach } from "./compare-react.mjs";
import { METRICS } from "../Benchmarks/ReactComparison/scenario.mjs";

const sample = (value) => Object.fromEntries(METRICS.map((metric) => [metric.id, value(metric)]));
const rounds = 14;
const withMain = (a) => ({ a, b: a, c: a });

test("a side that is clearly slower is reported, with the change of React against SwiftUIWeb", () => {
  const samples = {
    a: Array.from({ length: rounds }, (_, i) => sample(() => 10 + (i % 3) * 0.1)),
    b: Array.from({ length: rounds }, (_, i) => sample(() => 20 + (i % 3) * 0.1)),
  };
  const row = summarize(samples).type;
  expect(row.comparison.verdict).toBe("B higher");
  expect(row.comparison.relative).toBeGreaterThan(0.95);
  expect(row.comparison.relative).toBeLessThan(1.05);
  expect(markdown(summarize(samples), 1)).toContain("(React higher)");
});

test("equal sides are not reported as different", () => {
  const same = Array.from({ length: rounds }, (_, i) => sample(() => 10 + (i % 5) * 0.2));
  expect(summarize({ a: same, b: same }).type.comparison.verdict).toBe("no significant difference");
});

test("a change of less than five percent is not reported, however steady", () => {
  const a = Array.from({ length: rounds }, () => sample(() => 100));
  const b = Array.from({ length: rounds }, () => sample(() => 103));
  expect(summarize({ a, b }).type.comparison.verdict).toBe("no significant difference");
});

test("too few rounds say so instead of guessing", () => {
  const few = Array.from({ length: 3 }, () => sample(() => 10));
  expect(summarize({ a: few, b: few }).type.comparison.verdict).toBe("too few samples");
});

test("the markdown has a row for every metric and names the units", () => {
  const same = Array.from({ length: rounds }, () => sample(() => 10));
  const text = markdown(summarize({ a: same, b: same }), 4);
  expect(text.startsWith("CPU 4x")).toBe(true);
  for (const metric of METRICS) expect(text).toContain(metric.label);
  expect(text).toContain("10.0 ms");
});

test("a throttle that reached only the page is reported as such, and the worker's numbers are not compared with React", () => {
  expect(throttleReach({ workers: [] })).toBe("the page");
  expect(throttleReach({ workers: [{ ok: true, error: null }] })).toBe("the page and its workers");
  expect(throttleReach({ workers: [{ ok: false, error: "Operation is only supported for pages, not workers" }] })).toBe(
    "the page only: Chromium refuses the throttle for a worker",
  );
  const same = Array.from({ length: rounds }, () => sample(() => 10));
  const text = markdown(summarize({ a: same, b: same, c: same }), 4, { a: "the page only: Chromium refuses the throttle for a worker" });
  expect(text).toContain("SwiftUIWeb (worker) is not throttled");
  expect(text).toContain("not comparable");
  expect(text).toContain("10.0 ms (±0.0), not throttled");
});

test("the virtualized React is set against SwiftUIWeb in its own column, and the orders of a round put each side in every place", () => {
  const same = Array.from({ length: rounds }, () => sample(() => 10));
  const slower = Array.from({ length: rounds }, () => sample(() => 30));
  const report = summarize({ a: same, b: slower, c: same, d: same });
  expect(report.type.comparisonVirtual.verdict).toBe("no significant difference");
  const text = markdown(report, 1);
  expect(text).toContain("| React (virtualized) | React vs SwiftUIWeb |");
  expect(text).toContain("React (virtualized) vs SwiftUIWeb");
  expect(summarize({ a: same, b: slower, c: same }).type.comparisonVirtual).toBeNull();
});

test("a network profile reports the cold load only", () => {
  const same = Array.from({ length: rounds }, () => sample(() => 10));
  const report = summarize({ a: same, b: same }, { metricIds: ["load", "loadWork", "transfer", "nodes"] });
  expect(Object.keys(report).sort()).toEqual(["load", "loadWork", "nodes", "transfer"]);
});
