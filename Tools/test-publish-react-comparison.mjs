// Run with: bun test ./Tools/test-publish-react-comparison.mjs
import { expect, test } from "bun:test";
import { render, workerThrottled } from "./publish-react-comparison.mjs";

const comparison = (verdict) => ({ medianA: 10.1234, medianB: 20.5, iqrA: 0.5, iqrB: 1, verdict });
const results = {
  meta: { date: "2026-10-28T12:00:00.000Z", machine: { cpu: "Test CPU", cores: 8, memoryGB: 16, os: "darwin 1" }, browser: "Chromium 1", rounds: 15 },
  cpu: {
    1: { type: { id: "type", unit: "ms", comparison: comparison("B higher") }, load: { id: "load", unit: "ms", comparison: comparison("B lower") } },
    4: { nodes: { id: "nodes", unit: "", comparison: comparison("no significant difference") } },
  },
};

test("the data names the conditions of the measurement", () => {
  const text = render(results);
  expect(text).toContain('date: "2026-10-28"');
  expect(text).toContain('machine: "Test CPU, 8 cores, 16 GB, darwin 1"');
  expect(text).toContain("rounds: 15");
  expect(text).toContain("Do not edit");
});

test("every rate and metric is written, with React's verdict", () => {
  const text = render(results);
  expect(text).toContain("PerformanceRateVO(cpu: 1");
  expect(text).toContain("PerformanceRateVO(cpu: 4");
  expect(text).toContain('id: "type"');
  expect(text).toContain("verdict: .reactHigher");
  expect(text).toContain("verdict: .reactLower");
  expect(text).toContain("verdict: .same");
});

test("the main-thread series is written beside the default one, and falls back to it when a result has none", () => {
  const withMain = { ...results, cpu: { 1: { type: { id: "type", unit: "ms", comparison: comparison("B higher"), comparisonMain: { medianA: 5.5, iqrA: 0.25, verdict: "B lower" } } } } };
  const text = render(withMain);
  expect(text).toContain("mainThread: 5.5");
  expect(text).toContain("mainThreadVerdict: .reactLower");
  expect(render(results)).toContain("mainThread: 10.123");
});

test("numbers are rounded to three decimals", () => {
  expect(render(results)).toContain("swiftUIWeb: 10.123");
});

test("the output does not depend on the order the runtime lists keys in", () => {
  expect(render(results)).toBe(render(JSON.parse(JSON.stringify(results))));
});

test("a rate above 1 says whether SwiftUIWeb's worker was throttled, and a rate of 1 always is", () => {
  const throttled = { ...results, meta: { ...results.meta, throttle: { 4: { a: "the page and its workers", c: "the page", b: "the page" } } } };
  const refused = { ...results, meta: { ...results.meta, throttle: { 4: { a: "the page only: Chromium refuses the throttle for a worker", c: "the page", b: "the page" } } } };
  expect(workerThrottled(results.meta, 1)).toBe(true);
  expect(workerThrottled(throttled.meta, 4)).toBe(true);
  expect(workerThrottled(refused.meta, 4)).toBe(false);
  expect(workerThrottled(results.meta, 4)).toBe(false);
  expect(render(refused)).toContain("PerformanceRateVO(cpu: 4, swiftUIWebThrottled: false");
  expect(render(throttled)).toContain("PerformanceRateVO(cpu: 1, swiftUIWebThrottled: true");
});

test("a network profile is written with its conditions, and a results file without one writes none", () => {
  const network = {
    slow4g: {
      label: "Slow 4G", latency: 150, downloadThroughput: 1.6e6 / 8, uploadThroughput: 0.75e6 / 8,
      report: { load: { id: "load", unit: "ms", comparison: comparison("B lower") } },
    },
  };
  const text = render({ ...results, network });
  expect(text).toContain('PerformanceNetworkVO(label: "Slow 4G", latency: 150, downloadMbps: 1.6, uploadKbps: 750, metrics: [');
  expect(text).toContain('id: "load"');
  expect(render(results)).toContain("networks: []");
});
