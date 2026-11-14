#!/usr/bin/env bun
// Build and measure the one supported Embedded Showcase Wasm artifact.
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { dumps, fixed, isNumber, isoNow, parseArguments, parseJson } from "./format-compat.mjs";
import { bundleFilePath } from "./hash-release-bundle.mjs";

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

/** Paths a run works with; tests substitute a temporary root. */
export function defaultContext(root = ROOT) {
  return {
    root,
    // A release bundle names app.wasm by its content (app.3f9a1c2e.wasm); the file is looked up when it is read.
    get artifact() {
      const bundle = join(root, ".build/browser/ShowcaseApp");
      return bundleFilePath(bundle, "app.wasm") ?? join(bundle, "app.wasm");
    },
    baseline: join(root, "Documentation/Performance/EMBEDDED_WASM_SIZE_BASELINE.json"),
    report: join(root, ".build/wasm-size/report.json"),
    build: () => buildShowcase(root),
  };
}

export class SizeError extends Error {}

function commandOutput(command, root) {
  const finished = spawnSync("/bin/sh", ["-c", '"$@" 2>&1', "sh", ...command], { cwd: root, encoding: "utf8" });
  if (finished.status !== 0) throw new SizeError(`Command '${command.join(" ")}' returned non-zero exit status ${finished.status}.`);
  return finished.stdout.trim();
}

function compressedBytes(command, artifact, root) {
  const finished = spawnSync(command[0], [...command.slice(1), artifact], { cwd: root, stdio: ["ignore", "pipe", "inherit"], maxBuffer: 1 << 30 });
  if (finished.status !== 0) throw new SizeError(`Command '${[...command, artifact].join(" ")}' returned non-zero exit status ${finished.status}.`);
  return finished.stdout.length;
}

function requireTools(root) {
  const tools = {};
  const missing = [];
  for (const name of ["gzip", "brotli", "zstd"]) {
    const path = Bun.which(name);
    if (path === null) missing.push(name);
    else tools[name] = path;
  }
  if (missing.length) throw new SizeError(`Missing compressor(s): ${missing.join(", ")}. Run \`make setup\` and install them.`);
  return Object.fromEntries(Object.entries(tools).map(([name, path]) => [name, commandOutput([path, "--version"], root).split(/\r\n|\r|\n/)[0]]));
}

function buildShowcase(root) {
  const finished = spawnSync(join(root, "Tools/run-browser.sh"), ["showcase"], { cwd: root, env: { ...process.env, BUILD_ONLY: "1", CONFIGURATION: "release" }, stdio: "inherit" });
  if (finished.status !== 0) throw new SizeError(`Command '${join(root, "Tools/run-browser.sh")} showcase' returned non-zero exit status ${finished.status}.`);
}

export function measure(ctx) {
  const versions = requireTools(ctx.root);
  ctx.build();
  if (!existsSync(ctx.artifact) || !statSync(ctx.artifact).isFile()) throw new SizeError(`Embedded artifact was not produced: ${ctx.artifact}`);
  const directory = mkdtempSync(join(tmpdir(), "swiftuiweb-wasm-size-"));
  let sections;
  try {
    const sectionReport = join(directory, "sections.json");
    const finished = spawnSync("bun", ["Tools/analyze-wasm-size.js", "--wasm", ctx.artifact, "--output", sectionReport], { cwd: ctx.root, stdio: ["inherit", "ignore", "inherit"] });
    if (finished.status !== 0) throw new SizeError(`Command 'bun Tools/analyze-wasm-size.js' returned non-zero exit status ${finished.status}.`);
    sections = parseJson(readFileSync(sectionReport, "utf8"));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
  const metrics = {
    raw: statSync(ctx.artifact).size,
    gzip9: compressedBytes(["gzip", "-9", "-n", "-c"], ctx.artifact, ctx.root),
    brotli11: compressedBytes(["brotli", "-q", "11", "-c"], ctx.artifact, ctx.root),
    zstd19: compressedBytes(["zstd", "-q", "-19", "-c"], ctx.artifact, ctx.root),
    zstd22: compressedBytes(["zstd", "-q", "--ultra", "-22", "-c"], ctx.artifact, ctx.root),
  };
  const sectionSizes = Object.fromEntries(sections.sections.map((section) => [section.name, section.raw]));
  return {
    schemaVersion: 1,
    artifact: ctx.artifact,
    runtime: "Embedded Swift + BrowserIO",
    configuration: "release",
    timestamp: isoNow(),
    metrics,
    sections: sections.sections,
    code: sectionSizes.code ?? 0,
    data: sectionSizes.data ?? 0,
    tools: versions,
  };
}

const own = (object, key) => object !== null && typeof object === "object" && !Array.isArray(object) && Object.hasOwn(object, key);
const pad = (value, width) => String(value).padStart(width);

export function check(ctx, report, out = (line) => console.log(line), err = (line) => console.error(line)) {
  if (!existsSync(ctx.baseline)) {
    err(`Missing checked-in baseline: ${ctx.baseline}`);
    return 1;
  }
  const baseline = parseJson(readFileSync(ctx.baseline, "utf8"));
  const baselineMetrics = own(baseline, "metrics") ? baseline.metrics : baseline;
  const baselineSections = own(baseline, "sections") ? baseline.sections : {};
  const tolerance = Number(own(baseline, "maxPercentRegression") ? baseline.maxPercentRegression : 5.0);
  let failed = false;
  for (const key of ["raw", "gzip9", "brotli11", "zstd19", "zstd22", "code", "data"]) {
    const before = own(baselineMetrics, key) ? baselineMetrics[key] : own(baselineSections, key) ? baselineSections[key] : undefined;
    const after = own(report.metrics, key) ? report.metrics[key] : own(report, key) ? report[key] : undefined;
    if (!isNumber(before) || !isNumber(after)) continue;
    const delta = after - before;
    const percent = before ? (delta / before) * 100 : 0;
    const limit = before * (1 + tolerance / 100);
    const status = after > limit ? "ABOVE" : "OK";
    failed ||= status === "ABOVE";
    const sign = delta >= 0 ? "+" : "";
    const percentText = fixed(percent, 2);
    out(`${key.padEnd(8)} previous=${pad(before, 10)} current=${pad(after, 10)} delta=${sign}${delta} (${percentText.startsWith("-") ? "" : "+"}${percentText}%) limit=+${fixed(tolerance, 2)}% ${status}`);
  }
  // Size is a target, not a gate: the goal is the smallest artifact, so growth beyond the tolerance is reported
  // and never fails the run.
  if (failed) out(`REPORT Embedded Wasm size grew more than +${fixed(tolerance, 2)}% over the baseline.`);
  return 0;
}

export function main(argv, ctx = defaultContext()) {
  const args = parseArguments({
    prog: "wasm-size.mjs",
    description: "Build and measure the one supported Embedded Showcase Wasm artifact.",
    options: [{ names: ["--check"], dest: "check", type: "flag", help: "compare against the checked-in baseline" }],
  }, argv);
  const report = measure(ctx);
  mkdirSync(dirname(ctx.report), { recursive: true });
  writeFileSync(ctx.report, `${dumps(report, { indent: 2 })}\n`);
  console.log(`Embedded artifact: ${report.artifact}`);
  console.log("encoding    bytes");
  for (const [key, value] of Object.entries(report.metrics)) console.log(`${key.padEnd(10)} ${value}`);
  console.log(`sections: code=${report.code} data=${report.data}`);
  console.log(`report: ${ctx.report}`);
  return args.check ? check(ctx, report) : 0;
}

if (import.meta.main) {
  try {
    process.exit(main(process.argv.slice(2)));
  } catch (error) {
    if (error instanceof SizeError) {
      console.error(error.message);
      process.exit(1);
    }
    throw error;
  }
}
