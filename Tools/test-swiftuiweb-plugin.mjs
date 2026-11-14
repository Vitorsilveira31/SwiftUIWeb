#!/usr/bin/env bun
// Exercise the consumer-facing SwiftPM plugin without mutating the checkout.
import { spawnSync } from "node:child_process";
import { mkdirSync, realpathSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { bundleFilePath } from "./hash-release-bundle.mjs";

const DESCRIPTION = "Exercise the consumer-facing SwiftPM plugin without mutating the checkout.";
const USAGE = "usage: test-swiftuiweb-plugin.mjs [-h] [--skip-build]";
const HELP = `${USAGE}

${DESCRIPTION}

options:
  -h, --help    show this help message and exit
  --skip-build  only validate plugin help
`;

const ROOT = resolve(dirname(realpathSync(fileURLToPath(import.meta.url))), "..");
const BUNDLE_LINE = /^Bundle ready: (?<path>.+)$/m;
// Its own scratch folder: SwiftPM locks the one it uses, and the native build or another suite may hold .build.
const SWIFT_PACKAGE_PLUGIN = ["swift", "package", "--disable-sandbox", "--scratch-path", ".build/plugin-test-scratch", "plugin"];

function parseArguments(argv) {
  const options = { skipBuild: false, help: false };
  const unknown = [];
  for (const argument of argv) {
    if (argument === "-h" || argument === "--help") options.help = true;
    else if (argument === "--skip-build") options.skipBuild = true;
    else unknown.push(argument);
  }
  if (unknown.length > 0) {
    console.error(USAGE);
    console.error(`test-swiftuiweb-plugin.mjs: error: unrecognized arguments: ${unknown.join(" ")}`);
    process.exit(2);
  }
  return options;
}

function run(command, env) {
  console.log("$", command.join(" "));
  const result = spawnSync(command[0], command.slice(1), { cwd: ROOT, env, encoding: "utf8" });
  if (result.error) throw result.error;
  const output = result.stdout + result.stderr;
  process.stdout.write(output);
  if (result.status !== 0) {
    throw new Error(
      `command exited with status ${result.status ?? result.signal}: ${command.join(" ")}`,
    );
  }
  return output;
}

function main(options) {
  const env = { ...process.env };
  if (!("SWIFTUIWEB_OPEN_BROWSER" in env)) env.SWIFTUIWEB_OPEN_BROWSER = "0";
  // SwiftPM compiles the manifest before the command plugin starts. Keep
  // that host-side compilation reproducible even when the user's global
  // Clang/Swift module cache is read-only (for example in CI sandboxes).
  const cacheRoot = join(ROOT, ".build", "plugin-test-cache");
  mkdirSync(cacheRoot, { recursive: true });
  if (!("CLANG_MODULE_CACHE_PATH" in env)) env.CLANG_MODULE_CACHE_PATH = join(cacheRoot, "clang");
  if (!("SWIFT_MODULECACHE_PATH" in env)) env.SWIFT_MODULECACHE_PATH = join(cacheRoot, "swift");
  mkdirSync(env.CLANG_MODULE_CACHE_PATH, { recursive: true });
  mkdirSync(env.SWIFT_MODULECACHE_PATH, { recursive: true });
  try {
    const helpOutput = run([...SWIFT_PACKAGE_PLUGIN, "swiftuiweb", "--help"], env);
    if (!helpOutput.includes("Usage: swift Tools/swiftuiweb-run.swift")) {
      throw new Error("plugin help did not expose the SwiftUIWeb launcher usage");
    }
    for (const serverArguments of [["--serve"], ["--port", "8080"]]) {
      const probe = spawnSync(
        SWIFT_PACKAGE_PLUGIN[0],
        [
          ...SWIFT_PACKAGE_PLUGIN.slice(1),
          "swiftuiweb",
          "--path",
          ".",
          "--product",
          "ShowcaseApp",
          ...serverArguments,
        ],
        { cwd: ROOT, env, encoding: "utf8" },
      );
      if (probe.error) throw probe.error;
      const serverOutput = probe.stdout + probe.stderr;
      if (probe.status === 0 || !serverOutput.includes("cannot bind a localhost server")) {
        const option = serverArguments.join(" ");
        throw new Error(
          `plugin ${option} must fail with the standalone-launcher diagnostic; ` +
            `status=${probe.status ?? probe.signal}\n${serverOutput}`,
        );
      }
    }
    if (!options.skipBuild) {
      const output = run(
        [
          ...SWIFT_PACKAGE_PLUGIN,
          "swiftuiweb",
          "--path",
          ".",
          "--product",
          "ShowcaseApp",
          "--build-only",
        ],
        env,
      );
      const match = BUNDLE_LINE.exec(output);
      if (!match) throw new Error("plugin build did not report a bundle path");
      const bundle = match.groups.path.trim();
      const required = ["app.wasm", "index.html", "styles.css"];
      const missing = required.filter((name) => !bundleFilePath(bundle, name)).map((name) => join(bundle, name));
      if (missing.length > 0) {
        throw new Error(`plugin bundle is incomplete: ${missing.join(", ")}`);
      }
      console.log(`Plugin bundle contract: ${bundle}`);
    }
    return 0;
  } catch (error) {
    console.error(`plugin-test: ${error.message}`);
    return 1;
  }
}

const options = parseArguments(process.argv.slice(2));
if (options.help) {
  console.log(HELP);
  process.exitCode = 0;
} else {
  process.exitCode = main(options);
}
