#!/usr/bin/env bun
// Median table of the runs in a Tools/perf-ab.mjs --json report, one row per interaction: the baseline of a bundle.
//
//   bun Tools/perf-ab-summary.mjs report.json [--cpu 1] [--side A|B|both] [--metrics commits,commitMs,...]
//
// `--side both` pools the runs of both sides, which is right for an A/A report (both sides are the same bundle).
import { readFileSync } from "node:fs";
import { parseArgs } from "node:util";
import { iqr, median } from "./perf-ab-stats.mjs";

const DEFAULT = ["commits", "commitMs", "commitMsPerCommit", "layoutMs", "longTaskCount", "longTaskSumMs", "longTaskMaxMs", "blockingMs", "slowFrames16", "share16"];

/** Rows of [interaction, ...medians with IQR] for the pooled samples. Exported for the tests. */
export function summarize(samples, metrics) {
  const interactions = Object.keys(samples[0]);
  return interactions.map((interaction) => [
    interaction,
    ...metrics.map((metric) => {
      const values = samples.map((run) => run[interaction]?.[metric]).filter((value) => typeof value === "number");
      if (values.length === 0) return "-";
      const digits = Math.abs(median(values)) >= 100 ? 0 : 1;
      return `${median(values).toFixed(digits)} (${iqr(values).toFixed(digits)})`;
    })
  ]);
}

if (import.meta.main) {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: { cpu: { type: "string" }, side: { type: "string", default: "A" }, metrics: { type: "string", default: DEFAULT.join(",") } }
  });
  if (positionals.length === 0) {
    console.error("usage: bun Tools/perf-ab-summary.mjs report.json [--cpu 1] [--side A|B|both] [--metrics a,b]");
    process.exit(2);
  }
  const metrics = values.metrics.split(",");
  for (const file of positionals) {
    const report = JSON.parse(readFileSync(file, "utf8"));
    for (const result of report.results) {
      if (values.cpu && Number(values.cpu) !== result.cpu) continue;
      const samples = values.side === "both" ? [...result.samples.A, ...result.samples.B] : result.samples[values.side];
      console.log(`\nCPU ${result.cpu}x, ${samples.length} runs (median, IQR in parentheses), ${file}`);
      const rows = [["interaction", ...metrics], ...summarize(samples, metrics)];
      console.log([rows[0], rows[0].map(() => "---"), ...rows.slice(1)].map((row) => `| ${row.join(" | ")} |`).join("\n"));
    }
  }
}
