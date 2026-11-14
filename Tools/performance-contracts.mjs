#!/usr/bin/env bun
// Collect, report and enforce the checked-in performance contracts.
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { arithmetic, dumps, Float, fixed, isNumber, isoNow, parseArguments, parseJson, displayText } from "./format-compat.mjs";

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

/** A failure that ends the run: `SystemExit(message)` carries a message, `SystemExit(1)` only a status. */
export class ExitError extends Error {
  constructor(message, code = 1) {
    super(message);
    this.code = code;
  }
}

/** Run a command from the repository root with stdout and stderr merged, write the output to a log, return it. */
export function run(command, output, root = ROOT) {
  mkdirSync(dirname(output), { recursive: true });
  const finished = spawnSync("/bin/sh", ["-c", '"$@" 2>&1', "sh", ...command], { cwd: root, encoding: "utf8", maxBuffer: 1 << 30 });
  const text = finished.stdout ?? "";
  writeFileSync(output, text);
  if (finished.status !== 0) {
    process.stdout.write(text);
    throw new ExitError(`performance command failed (${finished.status}): ${command.join(" ")}`);
  }
  return text;
}

/** Paths and the command runner every phase works with; tests substitute a temporary root or a fake `run`. */
export function defaultContext(root = ROOT, env = process.env) {
  return {
    root,
    build: join(root, ".build", "performance"),
    budgets: join(root, "Documentation", "Performance", "PERFORMANCE_BUDGETS.json"),
    bundle: resolve(root, env.PERF_EMBEDDED_BUNDLE ?? ".build/browser/ShowcaseApp"),
    swift: env.SWIFT ?? "swift",
    run: (command, output) => run(command, output, root),
  };
}

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value) && !(value instanceof Float) && !(value instanceof Map);
const has = (object, key) => isObject(object) && Object.hasOwn(object, key);
const get = (object, key, fallback) => (has(object, key) ? object[key] : fallback);
// An object is truthy when it has entries.
const filled = (value) => (value instanceof Map ? value.size > 0 : isObject(value) ? Object.keys(value).length > 0 : Boolean(value));
const entries = (value) => (isObject(value) ? Object.entries(value) : []);
// The first argument when it is truthy, else the second.
const either = (a, b) => (a !== null && a !== undefined && (!isObject(a) || filled(a)) ? a : b);

export function parseKv(line) {
  if (!line.includes(",")) return null;
  const stripped = line.trim();
  const comma = stripped.indexOf(",");
  const prefix = comma < 0 ? stripped : stripped.slice(0, comma);
  const values = {};
  for (const pair of (comma < 0 ? "" : stripped.slice(comma + 1)).split(",")) {
    const equals = pair.indexOf("=");
    if (equals < 0) continue;
    const key = pair.slice(0, equals);
    const value = pair.slice(equals + 1);
    if (value.includes(".")) values[key] = /^\s*[+-]?(\d+\.\d*|\.\d+)([eE][+-]?\d+)?\s*$/.test(value) ? new Float(Number(value)) : value;
    else values[key] = /^\s*[+-]?\d+\s*$/.test(value) ? Number(value) : value;
  }
  return [prefix, values];
}

// `str.splitlines()` for the line endings tool output uses.
const lines = (text) => {
  const parts = text.split(/\r\n|\r|\n/);
  if (parts[parts.length - 1] === "") parts.pop();
  return parts;
};
const writeReport = (path, value) => writeFileSync(path, `${dumps(value, { indent: 2 })}\n`);

export function collectSwift(ctx) {
  const log = join(ctx.build, "swift-memory.log");
  const command = [
    ctx.swift, "test", "-c", "release",
    // Performance collection does not need a dSYM. Disabling debug symbols keeps the release benchmark
    // reproducible in locked-down runners where dsymutil cannot create a companion bundle.
    "-debug-info-format", "none", "--enable-swift-testing", "--disable-xctest", "--no-parallel", "--disable-sandbox", "--filter", "MemoryBenchmarks",
  ];
  const text = ctx.run(command, log);
  const listScale = new Map();
  const result = { schemaVersion: 1, namespace: "swift.runtime", scenarios: { listScale } };
  for (const line of lines(text)) {
    const parsed = parseKv(line);
    if (!parsed) continue;
    const [prefix, values] = parsed;
    if (prefix === "startup") result.startup = values;
    else if (prefix === "memory") result.mutation = values;
    else if (prefix === "release") result.release = values;
    else if (prefix === "list-removal") result.listRemoval = values;
    else if (prefix === "list-scale" && "count" in values) {
      const count = String(Math.trunc(Number(values.count)));
      delete values.count;
      listScale.set(count, values);
    }
  }
  if (!filled(result.release) || !filled(listScale.get("10000"))) {
    throw new ExitError(`Swift memory benchmark did not publish required metrics; see ${log}`);
  }
  result.listScale = listScale;
  writeReport(join(ctx.build, "swift-metrics.json"), result);
  return result;
}

export function collectArtifact(ctx) {
  // Normalize the real Showcase release bundle into the contract schema.
  const output = join(ctx.build, "showcase-size.json");
  ctx.run(["bun", "Tools/report-release-size.js", "--bundle", ctx.bundle, "--output", output], join(ctx.build, "artifact-size.log"));
  const size = loadJson(output);
  if (!size || !isObject(size.initial)) throw new ExitError(`release size report did not publish ShowcaseApp totals; see ${output}`);
  const initial = size.initial;
  const optional = get(size, "lazy", { raw: 0, gzip: 0, brotli: 0 });
  const all = {};
  for (const key of ["raw", "gzip", "brotli"]) all[key] = Math.trunc(Number(get(initial, key, 0))) + Math.trunc(Number(get(optional, key, 0)));
  const totals = { initial, optional, all };
  const result = {
    schemaVersion: 1,
    artifacts: [{ name: "ShowcaseApp", product: "ShowcaseApp", bundle: ctx.bundle, status: "ready", analysis: { totals } }],
  };
  writeReport(join(ctx.build, "artifact-size.json"), result);
  return result;
}

export function loadJson(path) {
  if (!existsSync(path) || !statSync(path).isFile()) return null;
  return parseJson(readFileSync(path, "utf8"));
}

const isFile = (path) => existsSync(path) && statSync(path).isFile();

export function mergeReport(ctx) {
  let artifact = loadJson(join(ctx.build, "artifact-size.json"));
  let artifactFromBuild = artifact !== null;
  // Older workspaces may retain a HelloWorld report from the pre-Showcase pipeline. Never let that stale artifact
  // silently satisfy the current product contract; fall back to the checked-in Showcase baseline until a fresh
  // release-size report is collected.
  const list = get(artifact ?? {}, "artifacts", []);
  if (!list.some((entry) => get(entry, "name") === "ShowcaseApp" || get(entry, "product") === "ShowcaseApp")) {
    artifact = null;
    artifactFromBuild = false;
  }
  const baselineArtifact = loadJson(join(ctx.root, "Documentation/Performance/BROWSER_ARTIFACT_SIZE_BASELINE.json"));
  artifact = either(artifact, baselineArtifact);
  const browser = loadJson(join(ctx.build, "browser.json"));
  const embedded = loadJson(join(ctx.build, "embedded-browser.json"));
  const swift = loadJson(join(ctx.build, "swift-metrics.json"));
  const artifacts = {};
  for (const entry of get(artifact ?? {}, "artifacts", [])) {
    if (get(entry, "status") !== "ready") continue;
    artifacts[entry.name] = get(get(entry, "analysis", {}), "totals", {});
  }
  const baselineArtifacts = {};
  for (const entry of get(baselineArtifact ?? {}, "artifacts", [])) {
    if (get(entry, "status") === "ready") baselineArtifacts[entry.name] = get(get(entry, "analysis", {}), "totals", {});
  }
  // Browser benchmark files retain samples for diagnostics, while the contract namespace exposes the stable
  // summary paths used by budgets.
  const browserSummary = {};
  for (const [name, fixture] of entries(get(browser ?? {}, "fixtures", {}))) browserSummary[name] = get(fixture, "summary", fixture);
  const report = {
    schemaVersion: 1,
    generatedAt: isoNow(),
    provenance: {
      artifact: artifactFromBuild ? "build" : "checked-in-baseline",
      browser: isFile(join(ctx.build, "browser.json")) ? "build" : "unavailable",
      embeddedBrowser: either(embedded, false) ? "build" : "unavailable",
      swift: either(swift, false) ? "build" : "unavailable",
    },
    artifacts,
    browser: { fixtures: browserSummary },
    embeddedBrowser: either(embedded, {}),
    swift: either(swift, {}),
    baseline: { artifacts: baselineArtifacts },
  };
  // Keep before/after deltas in the machine-readable report. These are diagnostics only; budgets remain the
  // checked-in contract and are never rewritten from a build.
  report.deltas = { artifacts: {} };
  const subtract = (a, b) => arithmetic(a, b, (x, y) => x - y);
  for (const [name, current] of Object.entries(artifacts)) {
    const before = baselineArtifacts[name];
    if (filled(before)) {
      const scopes = {};
      for (const scope of ["initial", "optional", "all"]) {
        if (!(has(current, scope) && has(before, scope))) continue;
        scopes[scope] = {};
        for (const metric of ["raw", "gzip", "brotli"]) scopes[scope][metric] = subtract(get(get(current, scope, {}), metric, 0), get(get(before, scope, {}), metric, 0));
      }
      report.deltas.artifacts[name] = scopes;
    }
  }
  writeReport(join(ctx.build, "report.json"), report);
  return report;
}

export function getPath(value, dotted) {
  if (!dotted) return value;
  if (!isObject(value)) return null;
  const parts = dotted.split(".");
  for (let count = parts.length; count > 0; count -= 1) {
    const key = parts.slice(0, count).join(".");
    if (has(value, key)) return getPath(value[key], parts.slice(count).join("."));
  }
  return null;
}

const sourceScope = (source) => (source === "swift-memory" || source === "swift" ? "swift" : "browser");
const signed = (value, digits) => {
  const text = fixed(value, digits);
  return text.startsWith("-") ? text : `+${text}`;
};
const budgetsOf = (ctx) => parseJson(readFileSync(ctx.budgets, "utf8")).budgets;

export function check(ctx, report, scope, out = (line) => console.log(line)) {
  const failures = [];
  let checked = 0;
  for (const budget of budgetsOf(ctx)) {
    if (scope !== "all" && sourceScope(budget.source) !== scope) continue;
    const value = getPath(report, budget.path);
    // Size budgets are targets, not gates: the goal is the smallest artifact, so a size above the target is
    // reported (with its baseline delta) and never fails the run.
    if (budget.enforcement === "report") {
      if (isNumber(value)) {
        const baseline = getPath(get(report, "baseline", {}), budget.path);
        const delta = isNumber(baseline) && Number(baseline) ? `, baseline ${displayText(baseline)} (${signed(((value - baseline) / baseline) * 100, 2)}%)` : "";
        const state = has(budget, "max") && value > budget.max ? "above target" : "within target";
        out(`REPORT ${budget.name}: ${displayText(value)} ${budget.unit}, target ${has(budget, "max") ? displayText(budget.max) : "—"} (${state})${delta}`);
      } else out(`REPORT ${budget.name}: no measurement at ${budget.path}`);
      continue;
    }
    if (!isNumber(value)) {
      failures.push(`${budget.name}: missing numeric metric at ${budget.path}`);
      continue;
    }
    checked += 1;
    if (has(budget, "max") && value > budget.max) failures.push(`${budget.name}: ${displayText(value)} > max ${displayText(budget.max)} ${budget.unit}`);
    if (has(budget, "min") && value < budget.min) failures.push(`${budget.name}: ${displayText(value)} < min ${displayText(budget.min)} ${budget.unit}`);
    const baseline = getPath(get(report, "baseline", {}), budget.path);
    const regression = budget.maxRegressionPercent;
    if (isNumber(regression) && isNumber(baseline)) {
      const limit = baseline * (1.0 + Number(regression) / 100.0);
      if (value > limit) failures.push(`${budget.name}: ${displayText(value)} > baseline + ${fixed(regression, 2)}% (${fixed(limit, 3)})`);
    }
  }
  if (failures.length) {
    for (const failure of failures) out(`FAIL ${failure}`);
    throw new ExitError("", 1);
  }
  if (!checked) throw new ExitError(`No ${scope} performance metrics were available`);
  out(`PASS performance contracts (${checked} budgets, scope=${scope})`);
}

export function markdown(ctx, report) {
  const rows = [
    "# SwiftUIWeb performance contract report", "", `Generated: ${report.generatedAt}`, "",
    "| Budget | Measured | Baseline | Limit | Delta to limit | Source |", "| --- | ---: | ---: | ---: | ---: | --- |",
  ];
  for (const budget of budgetsOf(ctx)) {
    const value = getPath(report, budget.path);
    const limit = has(budget, "max") ? budget.max : get(budget, "min", null);
    const baseline = getPath(get(report, "baseline", {}), budget.path);
    const baselineText = isNumber(baseline) ? fixed(baseline, 3) : "—";
    if (!isNumber(value)) {
      rows.push(`| ${budget.name} | missing | ${baselineText} | ${displayText(limit)} | — | ${budget.source} |`);
      continue;
    }
    const delta = has(budget, "max") ? limit - value : value - limit;
    rows.push(`| ${budget.name} | ${fixed(value, 3)} | ${baselineText} | ${displayText(limit)} | ${fixed(delta, 3)} | ${budget.source} |`);
  }
  rows.push(
    "", "## Before/after deltas", "",
    "The JSON report contains `baseline` and `deltas` for artifact metrics. A dash in the table means that a metric has no checked-in historical baseline; its budget is still enforced.",
    "", "The checked-in budget is the contract; this report is diagnostic and is never written back as a baseline.", "",
  );
  return rows.join("\n");
}

export function main(argv, ctx = defaultContext()) {
  const args = parseArguments({
    prog: "performance-contracts.mjs",
    description: "Collect, report and enforce the checked-in performance contracts.",
    options: [
      { names: ["--phase"], dest: "phase", type: "string", required: true, choices: ["swift", "memory", "browser", "report", "check"] },
      { names: ["--scope"], dest: "scope", type: "string", default: "all", choices: ["swift", "browser", "all"] },
    ],
  }, argv);
  mkdirSync(ctx.build, { recursive: true });
  if (args.phase === "swift" || args.phase === "memory") {
    collectSwift(ctx);
    check(ctx, mergeReport(ctx), "swift");
  } else if (args.phase === "browser") {
    collectArtifact(ctx);
    check(ctx, mergeReport(ctx), "browser");
  } else if (args.phase === "report") {
    const report = mergeReport(ctx);
    writeFileSync(join(ctx.build, "report.md"), markdown(ctx, report));
    console.log(`Wrote ${join(ctx.build, "report.json")}`);
    console.log(`Wrote ${join(ctx.build, "report.md")}`);
  } else check(ctx, mergeReport(ctx), args.scope);
}

if (import.meta.main) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    if (error instanceof ExitError) {
      if (error.message) console.error(error.message);
      process.exit(error.code);
    }
    throw error;
  }
}
