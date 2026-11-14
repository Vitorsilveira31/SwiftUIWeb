#!/usr/bin/env bun
// Collect and gate the SwiftUIWeb core coverage contract.
//
// This intentionally uses the toolchain's native coverage formats instead of a second coverage implementation.
// Swift is collected with LLVM's instrumentation; the browser host is collected with Bun/V8 and parsed
// from LCOV. The report is scoped to repository sources only, so dependency code can never inflate (or hide) a
// regression.
//
// The repository's long-term target is 100% line and semantic branch coverage for stable core/runtime code. The
// current toolchains do not emit branch maps for Swift source files, so the gate records that limitation
// and relies on the checked-in behavioral/property/E2E suites for semantic branch evidence. A gate run still
// prevents a drop below the last audited floor; --strict-target is available for the milestone where all target
// modules reach 100%.
import { spawnSync } from "node:child_process";
import {
  closeSync, existsSync, mkdirSync, openSync, readdirSync, readFileSync, rmSync, statSync, unlinkSync, writeFileSync,
} from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { dumps, fixed, parseArguments, readJson, resolveReal, roundTo } from "./format-compat.mjs";

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const DEFAULT_OUTPUT = join(ROOT, ".build", "coverage");
const SWIFT_EXECUTABLE_NAMES = ["SwiftUIWebTests", "SwiftUIWebCryptoTests", "SwiftUIWebUserNotificationsTests"];

const DESCRIPTION = `Collect and gate the SwiftUIWeb core coverage contract.

Swift is collected with LLVM's instrumentation; the browser host is collected with Bun/V8 and parsed from
LCOV. The report is scoped to repository sources only. The long-term target is 100% line and semantic branch
coverage; --gate fails on a drop below the audited floor in Tools/coverage-policy.json.`;

export function commandExists(command) {
  return Bun.which(command) !== null;
}

function run(command, env = process.env) {
  console.log("$", command.join(" "));
  const finished = spawnSync(command[0], command.slice(1), { cwd: ROOT, env, stdio: "inherit" });
  if (finished.status !== 0) {
    throw new Error(`Command '${command.join(" ")}' returned non-zero exit status ${finished.status ?? finished.signal}.`);
  }
}

function writeJson(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${dumps(value, { indent: 2, sortKeys: true })}\n`);
}

function isExecutable(path) {
  try {
    return statSync(path).isFile() && (statSync(path).mode & 0o111) !== 0;
  } catch {
    return false;
  }
}

export function exportLlvm(binaries, profile, destination) {
  if (!commandExists("llvm-cov")) throw new Error("llvm-cov is required for LLVM coverage");
  const command = ["llvm-cov", "export", "-format=text", binaries[0], ...binaries.slice(1).map((binary) => `-object=${binary}`), `-instr-profile=${profile}`];
  mkdirSync(dirname(destination), { recursive: true });
  const out = openSync(destination, "w");
  const finished = spawnSync(command[0], command.slice(1), { cwd: ROOT, stdio: ["ignore", out, "pipe"] });
  closeSync(out);
  if (finished.status !== 0) {
    rmSync(destination, { force: true });
    process.stderr.write(finished.stderr);
    throw new Error(`Command '${command.join(" ")}' returned non-zero exit status ${finished.status}.`);
  }
}

function swiftTest(output) {
  if (!commandExists("swift")) throw new Error("swift is required for Swift coverage");
  const env = { ...process.env };
  env.CLANG_MODULE_CACHE_PATH ??= "/tmp/swiftuiweb-clang-cache";
  env.SWIFT_MODULECACHE_PATH ??= "/tmp/swiftuiweb-module-cache";
  run([
    "swift", "test", "--disable-sandbox", "-c", "debug", "--enable-swift-testing", "--disable-xctest", "--no-parallel",
    "--enable-code-coverage",
  ], env);
  const products = join(ROOT, ".build", "out", "Products", "Debug");
  const profile = join(products, "codecov", "default.profdata");
  if (!existsSync(profile)) throw new Error(`Swift tests did not produce ${profile}`);
  const binaries = SWIFT_EXECUTABLE_NAMES.map((name) => join(products, `${name}.xctest`, "Contents", "MacOS", name)).filter((candidate) => existsSync(candidate));
  if (!binaries.length) throw new Error(`No Swift test executables found below ${products}`);
  return binaries.map((binary) => {
    const exportPath = join(output, `swift-${binary.split(sep).pop()}.json`);
    exportLlvm([binary], profile, exportPath);
    return exportPath;
  });
}

const matching = (directory, prefix, suffix) => (existsSync(directory) ? readdirSync(directory).filter((name) => name.startsWith(prefix) && name.endsWith(suffix)).sort() : []);

function browserHost(output) {
  if (!commandExists("bun")) throw new Error("bun is required for BrowserIO host coverage");
  const coverageDir = join(output, "browser");
  rmSync(coverageDir, { recursive: true, force: true });
  run(["bun", "test", "--coverage", "--coverage-reporter=lcov", `--coverage-dir=${coverageDir}`, "Tests/BrowserIO/host.test.mjs"]);
  const lcov = join(coverageDir, "lcov.info");
  if (!existsSync(lcov)) throw new Error(`Bun did not produce ${lcov}`);
  return lcov;
}

export function llvmFiles(path) {
  const document = readJson(path);
  return (document.data ?? []).flatMap((data) => data.files ?? []);
}

export function metricSummary(lineCount, lineCovered, functionCount, functionCovered, branchCount, branchCovered, { files }) {
  const percentage = (covered, count) => (count ? roundTo((covered * 100.0) / count, 2) : null);
  return {
    files,
    lines: { count: lineCount, covered: lineCovered, percent: percentage(lineCovered, lineCount) },
    functions: { count: functionCount, covered: functionCovered, percent: percentage(functionCovered, functionCount) },
    branches: { count: branchCount, covered: branchCovered, percent: percentage(branchCovered, branchCount) },
  };
}

export function summaryFromFiles(files, predicate) {
  const seen = new Map();
  for (const file of files) {
    const filename = String(file.filename ?? "");
    if (predicate(filename)) seen.set(filename, file);
  }
  const total = { lines: [0, 0], functions: [0, 0], branches: [0, 0] };
  for (const file of seen.values()) {
    const summary = file.summary ?? {};
    for (const kind of Object.keys(total)) {
      total[kind][0] += Math.trunc(Number(summary[kind]?.count ?? 0));
      total[kind][1] += Math.trunc(Number(summary[kind]?.covered ?? 0));
    }
  }
  return metricSummary(...total.lines, ...total.functions, ...total.branches, { files: seen.size });
}

export function parseLcov(path) {
  const records = {};
  let current = null;
  for (const raw of readFileSync(path, "utf8").split(/\r\n|\r|\n/)) {
    if (raw.startsWith("SF:")) {
      const filename = raw.slice(3);
      current = records[filename] ??= { count: 0, covered: 0, function_count: 0, function_covered: 0, branch_count: 0, branch_covered: 0 };
    } else if (raw.startsWith("FNF:") && current) current.function_count = Number.parseInt(raw.slice(4), 10);
    else if (raw.startsWith("FNH:") && current) current.function_covered = Number.parseInt(raw.slice(4), 10);
    else if (raw.startsWith("BRF:") && current) current.branch_count = Number.parseInt(raw.slice(4), 10);
    else if (raw.startsWith("BRH:") && current) current.branch_covered = Number.parseInt(raw.slice(4), 10);
    else if (raw.startsWith("DA:") && current) {
      const hits = raw.slice(3).split(",").slice(1).join(",");
      current.count += 1;
      current.covered += Number.parseInt(hits, 10) > 0 ? 1 : 0;
    } else if (raw === "end_of_record") current = null;
  }
  return records;
}

function browserSummary(path) {
  const records = parseLcov(path);
  // LCOV also contains the assertion harness itself. It is a test fixture, not shipped host code, so keep the
  // module metric scoped to production BrowserIO sources (the generated protocol and runtime adapter).
  const production = new Set(["Tools/BrowserIO/protocol.generated.mjs", "Tools/BrowserIO/browser-io.mjs"]);
  const files = Object.entries(records).filter(([filename]) => production.has(filename)).map(([, record]) => record);
  const sum = (key) => files.reduce((total, record) => total + record[key], 0);
  return metricSummary(sum("count"), sum("covered"), sum("function_count"), sum("function_covered"), sum("branch_count"), sum("branch_covered"), { files: files.length });
}

// A module of this package: a file under the repository's own `Sources/`. A dependency's sources (swift-crypto's `Crypto`,
// checked out under `.build/checkouts/`) are not the package's code and get no floor.
const moduleForSwift = (filename) => {
  if (!filename.includes("/Sources/") || filename.includes("/.build/")) return null;
  return filename.split("/Sources/").slice(1).join("/Sources/").split("/")[0];
};

export function buildReport(swiftPaths, browserPath) {
  const modules = {};
  if (swiftPaths.length) {
    const byModule = new Map();
    for (const file of swiftPaths.flatMap(llvmFiles)) {
      const module = moduleForSwift(String(file.filename ?? ""));
      if (module) byModule.set(module, [...(byModule.get(module) ?? []), file]);
    }
    for (const module of [...byModule.keys()].sort()) modules[module] = summaryFromFiles(byModule.get(module), () => true);
  }
  if (browserPath) modules["Tools/BrowserIO"] = browserSummary(browserPath);
  return { modules };
}

export function loadPolicy() {
  const policy = join(ROOT, "Tools", "coverage-policy.json");
  return existsSync(policy) ? readJson(policy) : { targetLine: 100, targetBranch: 100, minimumLine: {} };
}

export function gate(result, policy, strictTarget) {
  const failures = [];
  const minimums = policy.minimumLine ?? {};
  const minimumFunctions = policy.minimumFunction ?? {};
  const targetLine = Number(policy.targetLine ?? 100);
  for (const [module, summary] of Object.entries(result.modules)) {
    if (policy.requirePolicyForModules && !(module in minimums)) {
      failures.push(`${module}: no regression floor is defined in coverage-policy.json`);
      continue;
    }
    const actual = summary.lines.percent === null ? null : Number(summary.lines.percent);
    if (actual === null) {
      failures.push(`${module}: no instrumented lines were found`);
      continue;
    }
    const minimum = Number(minimums[module] ?? 0);
    if (actual + 1e-9 < minimum) failures.push(`${module}: ${fixed(actual, 2)}% is below regression floor ${fixed(minimum, 2)}%`);
    if (module in minimumFunctions) {
      const functionActual = summary.functions.percent === null ? null : Number(summary.functions.percent);
      const functionMinimum = Number(minimumFunctions[module]);
      if (functionActual === null) failures.push(`${module}: no instrumented functions were found`);
      else if (functionActual + 1e-9 < functionMinimum) {
        failures.push(`${module}: ${fixed(functionActual, 2)}% functions is below regression floor ${fixed(functionMinimum, 2)}%`);
      }
    }
    if (strictTarget && actual + 1e-9 < targetLine) failures.push(`${module}: ${fixed(actual, 2)}% is below target ${fixed(targetLine, 2)}%`);
    const branchPercent = summary.branches.percent === null ? null : Number(summary.branches.percent);
    if (strictTarget && branchPercent !== null && branchPercent + 1e-9 < Number(policy.targetBranch ?? 100)) {
      failures.push(`${module}: ${fixed(branchPercent, 2)}% branches is below target ${fixed(Number(policy.targetBranch ?? 100), 2)}%`);
    }
  }
  return failures;
}

export function markdown(result, policy) {
  const lines = [
    "# SwiftUIWeb coverage audit",
    "",
    `Long-term line target: **${policy.targetLine ?? 100}%**; semantic branch target: **${policy.targetBranch ?? 100}%**.`,
    "",
    "| Module | Files | Lines | Functions | Branch maps |",
    "|---|---:|---:|---:|---:|",
  ];
  const fmt = (metric) => (metric.percent === null ? "n/a" : `${fixed(metric.percent, 2)}% (${metric.covered}/${metric.count})`);
  for (const module of Object.keys(result.modules).sort()) {
    const summary = result.modules[module];
    const branchText = summary.branches.count === 0 ? "unsupported" : fmt(summary.branches);
    lines.push(`| \`${module}\` | ${summary.files} | ${fmt(summary.lines)} | ${fmt(summary.functions)} | ${branchText} |`);
  }
  lines.push(
    "",
    "LLVM 21 currently emits no branch maps for Swift source files; this is recorded as `unsupported`, not treated as 100%. C/host branch maps and BrowserIO line coverage remain observable separately. Semantic branch behavior is covered by the checked-in failure/fallback/cancellation/lifecycle/property and browser-host suites.",
    "",
    "The regression gate uses the floors in `Tools/coverage-policy.json`. Run `bun Tools/coverage.mjs --strict-target` when evaluating the 100% milestone.",
  );
  return `${lines.join("\n")}\n`;
}

export function main(argv) {
  const args = parseArguments({
    prog: "coverage.mjs",
    description: DESCRIPTION,
    options: [
      { names: ["--output-dir"], dest: "outputDir", type: "string", default: DEFAULT_OUTPUT },
      { names: ["--skip-swift"], dest: "skipSwift", type: "flag" },
      { names: ["--browserio"], dest: "browserio", type: "flag", help: "also run the Bun BrowserIO host contract" },
      { names: ["--gate"], dest: "gate", type: "flag", help: "fail on a regression below the audited floor" },
      { names: ["--strict-target"], dest: "strictTarget", type: "flag", help: "also fail until every measured module reaches 100% lines" },
    ],
  }, argv);
  const output = resolve(ROOT, args.outputDir);
  mkdirSync(output, { recursive: true });
  const swiftPaths = args.skipSwift ? [] : swiftTest(output);
  const browserPath = args.browserio ? browserHost(output) : null;
  const result = buildReport(swiftPaths, browserPath);
  result.policy = loadPolicy();
  result.branchInstrumentation = {
    swift: "unsupported-by-toolchain",
    semantic: "covered-by-behavioral-tests",
    note: "LLVM 21 reports zero branch records for Swift source maps; no source is excluded.",
  };
  writeJson(join(output, "report.json"), result);
  writeFileSync(join(output, "report.md"), markdown(result, result.policy));
  for (const module of Object.keys(result.modules).sort()) {
    const summary = result.modules[module];
    const branchText = summary.branches.percent === null ? "unsupported" : `${summary.branches.percent}%`;
    console.log(`${module}: lines ${summary.lines.percent === null ? "None" : summary.lines.percent}%, branches ${branchText}`);
  }
  const failures = args.gate || args.strictTarget ? gate(result, result.policy, args.strictTarget) : [];
  if (failures.length) {
    console.error("Coverage gate failed:");
    for (const failure of failures) console.error(`  - ${failure}`);
    return 1;
  }
  return 0;
}

if (import.meta.main) {
  try {
    process.exit(main(process.argv.slice(2)));
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  }
}
