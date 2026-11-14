#!/usr/bin/env bun
// Browser frame-time budgets: evaluate a measurement file against Documentation/Performance/FRAME_BUDGETS.json, print a
// table and write a machine-readable report. See Documentation/Performance/FRAME_BUDGETS.md.
//
//   bun Tools/frame-budgets.mjs evaluate --measurements <file> [--mode report|enforce] [--json out] [--markdown out]
//   bun Tools/frame-budgets.mjs run --bundle <dir> --scenario <module.mjs> [--profiles desktop,phone] [--rounds 3] ...
//
// `evaluate` is pure (no browser). `run` measures (Tools/frame-measure.mjs), writes the measurement file and evaluates it.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
export const DEFAULT_BUDGETS = join(ROOT, "Documentation", "Performance", "FRAME_BUDGETS.json");
export const POOLED = "(all interactions)";

const sum = (values) => values.reduce((total, value) => total + value, 0);
const finite = (value) => typeof value === "number" && Number.isFinite(value);
const round = (value, digits = 3) => (finite(value) ? Number(value.toFixed(digits)) : null);

/** Nearest-rank percentile (`fraction` in 0..1) of unsorted `values`; null for an empty list. */
export function percentile(values, fraction) {
  if (!values.length) return null;
  const ordered = [...values].sort((a, b) => a - b);
  const rank = Math.min(ordered.length, Math.max(1, Math.ceil(fraction * ordered.length)));
  return ordered[rank - 1];
}

/**
 * Combines the records of several interactions (or of the same interaction over several rounds) into one record.
 * Additive fields add up, commit durations concatenate (so the percentile is over every commit), maxima take the maximum
 * and the frame shares are recomputed from the summed frame times.
 */
export function pool(records, { countInteractions = false } = {}) {
  const durations = records.flatMap((record) => record.commitDurationsMs ?? []);
  const frameTimeMs = sum(records.map((record) => record.frameTimeMs ?? 0));
  const lateMs8 = sum(records.map((record) => record.lateMs8 ?? 0));
  const lateMs16 = sum(records.map((record) => record.lateMs16 ?? 0));
  const frames = sum(records.map((record) => record.frames ?? 0));
  const pooled = {
    commits: sum(records.map((record) => record.commits ?? 0)),
    commitDurationsMs: durations,
    commitMs: round(sum(records.map((record) => record.commitMs ?? 0))),
    commitMsPerCommit: durations.length ? round(sum(durations) / durations.length) : null,
    commitP95Ms: durations.length ? round(percentile(durations, 0.95)) : null,
    maxCommitMs: round(Math.max(0, ...records.map((record) => record.maxCommitMs ?? 0))),
    layoutMs: round(sum(records.map((record) => record.layoutMs ?? 0))),
    longTaskCount: sum(records.map((record) => record.longTaskCount ?? 0)),
    longTaskSumMs: round(sum(records.map((record) => record.longTaskSumMs ?? 0))),
    longTaskMaxMs: round(Math.max(0, ...records.map((record) => record.longTaskMaxMs ?? 0))),
    frames,
    frameTimeMs: round(frameTimeMs),
    lateMs8: round(lateMs8),
    lateMs16: round(lateMs16),
    timeShare8: frameTimeMs > 0 ? round((100 * (frameTimeMs - lateMs8)) / frameTimeMs) : null,
    timeShare16: frameTimeMs > 0 ? round((100 * (frameTimeMs - lateMs16)) / frameTimeMs) : null,
    jankMs: round(sum(records.map((record) => record.jankMs ?? 0))),
    slowFrames8: sum(records.map((record) => record.slowFrames8 ?? 0)),
    slowFrames16: sum(records.map((record) => record.slowFrames16 ?? 0)),
    frameMax: round(Math.max(0, ...records.map((record) => record.frameMax ?? 0))),
  };
  if (countInteractions) {
    pooled.interactions = records.length;
    pooled.interactionsWithoutSlowFrame = records.filter((record) => (record.slowFrames16 ?? 0) === 0).length;
    pooled.shareInteractionsWithoutSlowFrame = records.length ? round((100 * pooled.interactionsWithoutSlowFrame) / records.length) : null;
  }
  return pooled;
}

/** The pooled record of every profile of a measurement file: { profile: record }. */
export function pooledProfiles(measurements) {
  const result = {};
  for (const [name, profile] of Object.entries(measurements.profiles ?? {})) {
    result[name] = pool(Object.values(profile.interactions ?? {}), { countInteractions: true });
  }
  return result;
}

const interactionsOf = (budget, profile) => {
  const names = Object.keys(profile.interactions ?? {});
  return Array.isArray(budget.interactions) ? names.filter((name) => budget.interactions.includes(name)) : names;
};

/** Compares one value with the limits of a budget: "pass", "over", "info" (no limit) or "missing" (no measurement). */
export function judge(budget, value) {
  if (!finite(value)) return "missing";
  const hasMax = finite(budget.max);
  const hasMin = finite(budget.min);
  if (!hasMax && !hasMin) return "info";
  if (hasMax && value > budget.max) return "over";
  if (hasMin && value < budget.min) return "over";
  return "pass";
}

/**
 * One result per budget and interaction (scope "each"), or one per budget over the pooled record (scope "pooled").
 * `mode` "report" never fails, "enforce" fails on every over/missing, "default" uses each budget's `enforcement`
 * (falling back to the file's).
 */
export function evaluate(budgetFile, measurements, { mode = "default" } = {}) {
  const pooled = pooledProfiles(measurements);
  const results = [];
  for (const budget of budgetFile.budgets) {
    const enforcement = mode === "default" ? (budget.enforcement ?? budgetFile.enforcement ?? "report") : mode;
    const profile = measurements.profiles?.[budget.profile];
    const base = { budget: budget.name, profile: budget.profile, metric: budget.metric, unit: budget.unit ?? "", enforcement, max: budget.max ?? null, min: budget.min ?? null };
    if (!profile) {
      results.push({ ...base, interaction: POOLED, value: null, status: "missing" });
      continue;
    }
    if (budget.scope === "pooled") {
      const value = pooled[budget.profile]?.[budget.metric];
      results.push({ ...base, interaction: POOLED, value: finite(value) ? value : null, status: judge(budget, value) });
      continue;
    }
    const names = interactionsOf(budget, profile);
    // A profile with no interactions measures nothing: report it as missing rather than passing with no results.
    if (names.length === 0) results.push({ ...base, interaction: POOLED, value: null, status: "missing" });
    for (const name of names) {
      const value = profile.interactions[name]?.[budget.metric];
      results.push({ ...base, interaction: name, value: finite(value) ? value : null, status: judge(budget, value) });
    }
  }
  return { results, pooled, summary: summarize(results), verdict: verdict(results) };
}

/** Per budget: how many results, how many over, how many missing, and the worst value. */
export function summarize(results) {
  const byBudget = new Map();
  for (const result of results) {
    if (!byBudget.has(result.budget)) {
      byBudget.set(result.budget, { budget: result.budget, profile: result.profile, metric: result.metric, enforcement: result.enforcement, total: 0, pass: 0, over: 0, missing: 0, info: 0, worst: null });
    }
    const entry = byBudget.get(result.budget);
    entry.total += 1;
    entry[result.status] += 1;
    if (finite(result.value)) {
      const direction = finite(result.min) && !finite(result.max) ? -1 : 1;
      if (entry.worst === null || direction * result.value > direction * entry.worst) entry.worst = result.value;
    }
  }
  return [...byBudget.values()];
}

/** `failing` are the over/missing results of budgets in enforce mode; the exit code is 1 when there are any. */
export function verdict(results) {
  const failing = results.filter((result) => result.enforcement === "enforce" && (result.status === "over" || result.status === "missing"));
  const reported = results.filter((result) => result.enforcement !== "enforce" && (result.status === "over" || result.status === "missing"));
  return { failing: failing.length, reportedOver: reported.length, total: results.length, exitCode: failing.length ? 1 : 0 };
}

const number = (value, unit) => {
  if (!finite(value)) return "-";
  if (unit === "count" || unit === "interactions") return String(Math.round(value));
  return Math.abs(value) >= 100 ? value.toFixed(0) : value.toFixed(1);
};
const limitText = (result) => {
  if (finite(result.max)) return `<= ${number(result.max, result.unit)}`;
  if (finite(result.min)) return `>= ${number(result.min, result.unit)}`;
  return "report";
};
const STATUS = { pass: "ok", over: "OVER", info: "info", missing: "MISSING" };

const text = (rows) => {
  const widths = rows[0].map((_, column) => Math.max(...rows.map((row) => String(row[column]).length)));
  return rows.map((row) => row.map((cell, column) => String(cell).padEnd(widths[column])).join("  ").trimEnd()).join("\n");
};

/** The result table as rows (first row is the header). `onlyProblems` keeps over and missing results. */
export function tableRows(results, { onlyProblems = false } = {}) {
  const rows = [["profile", "interaction", "budget", "value", "limit", "status", "mode"]];
  for (const result of results) {
    if (onlyProblems && result.status !== "over" && result.status !== "missing") continue;
    rows.push([result.profile, result.interaction, result.budget, `${number(result.value, result.unit)} ${result.unit}`.trim(), limitText(result), STATUS[result.status], result.enforcement]);
  }
  return rows;
}

export function summaryRows(summary) {
  const rows = [["budget", "profile", "results", "over", "missing", "worst", "mode"]];
  for (const entry of summary) {
    rows.push([entry.budget, entry.profile, entry.total, entry.over, entry.missing, number(entry.worst, ""), entry.enforcement]);
  }
  return rows;
}

export function formatReport(evaluation, { onlyProblems = false } = {}) {
  const { verdict: result } = evaluation;
  const lines = [text(tableRows(evaluation.results, { onlyProblems })), "", text(summaryRows(evaluation.summary)), ""];
  const fraction = `${result.reportedOver + result.failing} of ${result.total} results over budget or missing`;
  lines.push(result.failing ? `FAIL frame budgets: ${result.failing} enforced results over budget (${fraction})` : `REPORT frame budgets: ${fraction}; nothing enforced`);
  return lines.join("\n");
}

export function markdownReport(evaluation, meta = "") {
  const table = (rows) => [rows[0], rows[0].map(() => "---"), ...rows.slice(1)].map((row) => `| ${row.join(" | ")} |`).join("\n");
  return `# Frame budgets\n\n${meta}\n\n## Summary\n\n${table(summaryRows(evaluation.summary))}\n\n## Results\n\n${table(tableRows(evaluation.results))}\n`;
}

export function loadJson(path) {
  if (!existsSync(path)) throw new Error(`${path}: no such file`);
  return JSON.parse(readFileSync(path, "utf8"));
}

/** Rejects a budget file that cannot be evaluated: it must fail loudly instead of silently reporting nothing. */
export function validateBudgets(file) {
  const problems = [];
  const names = new Set();
  if (!file || !Array.isArray(file.budgets)) return ["budgets must be an array"];
  for (const budget of file.budgets) {
    if (names.has(budget.name)) problems.push(`${budget.name}: duplicate name`);
    names.add(budget.name);
    if (!budget.profile || !file.profiles?.[budget.profile]) problems.push(`${budget.name}: unknown profile ${budget.profile}`);
    if (!budget.metric) problems.push(`${budget.name}: no metric`);
    if (!["each", "pooled"].includes(budget.scope)) problems.push(`${budget.name}: scope must be each or pooled`);
    if (budget.enforcement !== undefined && !["report", "enforce"].includes(budget.enforcement)) problems.push(`${budget.name}: enforcement must be report or enforce`);
  }
  return problems;
}

const USAGE = `usage: bun Tools/frame-budgets.mjs <evaluate|run> [options]

  evaluate --measurements <file>   evaluate a measurement file (written by run) against the budgets
  run --bundle <dir> --scenario <module>
                                   serve a built bundle, measure the scenario per profile, evaluate
    --profiles <list>              profiles to measure (default: every profile of the budget file)
    --rounds <n>                   scenario runs per profile, pooled (default 3)
    --port <n>                     port of the bundle server (default 8230)
    --api-origin <url>             SWIFTUIWEB_API_ORIGIN for the server (proxy to a running API)
    --api-path <path>              SWIFTUIWEB_API_PATH (default /api with --api-origin)
    --frame-rate <uncapped|default>  lift the 60 Hz requestAnimationFrame cap of headless Chromium (default uncapped)
    --engine <name>                chromium (default; CPU throttling needs it)
    --measurements-out <file>      where run writes the measurements (default .build/performance/browser-frames.json)

  common options
    --budgets <file>               budget file (default Documentation/Performance/FRAME_BUDGETS.json)
    --mode <default|report|enforce>  default: each budget's own enforcement; report: never fail; enforce: fail on any over
    --json <file>                  machine-readable report
    --markdown <file>              report as Markdown
    --only-problems                print only results that are over or missing
    --quiet                        print nothing but the files written (the exit code still tells the verdict)
`;

export function parseCli(argv) {
  const { values, positionals } = parseArgs({
    args: argv,
    allowPositionals: true,
    options: {
      measurements: { type: "string" }, "measurements-out": { type: "string" }, budgets: { type: "string" }, mode: { type: "string", default: "default" },
      json: { type: "string" }, markdown: { type: "string" }, "only-problems": { type: "boolean", default: false }, quiet: { type: "boolean", default: false },
      bundle: { type: "string" }, scenario: { type: "string" }, profiles: { type: "string" }, rounds: { type: "string", default: "3" },
      port: { type: "string", default: "8230" }, "api-origin": { type: "string" }, "api-path": { type: "string" },
      "frame-rate": { type: "string", default: "uncapped" }, engine: { type: "string" }, help: { type: "boolean", short: "h", default: false },
    },
  });
  return { command: positionals[0], values };
}

function writeOutputs(values, evaluation, measurements, meta) {
  const write = (path, content) => {
    mkdirSync(dirname(resolve(path)), { recursive: true });
    writeFileSync(path, content);
    console.log(`wrote ${path}`);
  };
  if (values.json) {
    write(values.json, `${JSON.stringify({ schemaVersion: 1, generatedAt: new Date().toISOString(), mode: values.mode, meta: measurements.meta ?? null, verdict: evaluation.verdict, summary: evaluation.summary, pooled: evaluation.pooled, results: evaluation.results }, null, 2)}\n`);
  }
  if (values.markdown) write(values.markdown, markdownReport(evaluation, meta));
}

export async function main(argv) {
  const { command, values } = parseCli(argv);
  if (values.help || !["evaluate", "run"].includes(command)) {
    console.error(USAGE);
    return values.help ? 0 : 2;
  }
  if (!["default", "report", "enforce"].includes(values.mode)) throw new Error("--mode is default, report or enforce");
  const budgets = loadJson(values.budgets ?? DEFAULT_BUDGETS);
  const problems = validateBudgets(budgets);
  if (problems.length) throw new Error(`invalid budget file:\n  ${problems.join("\n  ")}`);
  let measurements;
  if (command === "evaluate") {
    if (!values.measurements) throw new Error("evaluate needs --measurements <file>");
    measurements = loadJson(values.measurements);
  } else {
    const { measureAll } = await import("./frame-measure.mjs");
    measurements = await measureAll({ budgets, values });
    const out = values["measurements-out"] ?? join(ROOT, ".build", "performance", "browser-frames.json");
    mkdirSync(dirname(resolve(out)), { recursive: true });
    writeFileSync(out, `${JSON.stringify(measurements)}\n`);
    console.log(`wrote ${out}`);
  }
  const evaluation = evaluate(budgets, measurements, { mode: values.mode });
  if (!values.quiet) console.log(`\n${formatReport(evaluation, { onlyProblems: values["only-problems"] })}`);
  writeOutputs(values, evaluation, measurements, `Mode: ${values.mode}. ${measurements.meta ? JSON.stringify(measurements.meta) : ""}`);
  return evaluation.verdict.exitCode;
}

if (import.meta.main) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (error) => {
      console.error(error instanceof Error ? error.message : error);
      process.exit(1);
    },
  );
}
