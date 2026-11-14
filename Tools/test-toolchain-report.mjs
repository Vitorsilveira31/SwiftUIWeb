#!/usr/bin/env bun
// Tools/toolchain-report.sh lists every missing tool at once. The test runs it with a PATH that holds only the basic
// utilities plus the stubs a case chooses, so it does not depend on what is installed on the machine.
import assert from "node:assert/strict";
import { chmodSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ROOT } from "./browser-test-support.mjs";

const SCRIPT = join(ROOT, "Tools/toolchain-report.sh");
const BASICS = ["uname", "dirname", "head", "awk", "grep", "sed", "tr", "cat", "mktemp", "rm", "basename", "env"];

function whichOnSystem(name) {
  for (const directory of ["/usr/bin", "/bin", "/usr/local/bin", "/opt/homebrew/bin"]) {
    const path = join(directory, name);
    if (Bun.file(path).size > 0) return path;
  }
  throw new Error(`${name} not found on this machine`);
}

function sandbox(stubs) {
  const dir = mkdtempSync(join(tmpdir(), "toolchain-report-"));
  const bin = join(dir, "bin");
  mkdirSync(bin);
  for (const name of BASICS) symlinkSync(whichOnSystem(name), join(bin, name));
  for (const [name, body] of Object.entries(stubs)) {
    writeFileSync(join(bin, name), `#!/bin/sh\n${body}\n`);
    chmodSync(join(bin, name), 0o755);
  }
  return { dir, bin };
}

function report(stubs, args = [], environment = {}) {
  const { dir, bin } = sandbox(stubs);
  try {
    const result = Bun.spawnSync(["/bin/bash", SCRIPT, ...args], { env: { PATH: bin, HOME: dir, ...environment }, stdout: "pipe", stderr: "pipe" });
    return { status: result.exitCode, out: result.stdout.toString(), err: result.stderr.toString() };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const missingLines = (text) => text.split("\n").filter((line) => line.includes("MISSING")).map((line) => line.trim().split(/\s{2,}/)[1]?.trim());

// 1. Nothing installed: every required tool is named in one report, each with a fix.
{
  const { status, err } = report({});
  assert.equal(status, 1);
  assert.match(err, /2 required tool\(s\) are missing/);
  assert.deepEqual(missingLines(err).sort(), ["bun", "swift"]);
  assert.equal((err.match(/fix: /g) ?? []).length, 3, "two required tools and the optional wasm-opt each carry a fix");
  assert.match(err, /bun\.sh\/install|oven-sh\/bun/);
}

// 2. Some tools present: only the rest is reported.
{
  const { status, err } = report({
    bun: 'echo 1.2.3',
  });
  assert.equal(status, 1);
  assert.deepEqual(missingLines(err).sort(), ["swift"]);
  assert.doesNotMatch(err, /MISSING\s+bun/);
}

// 3. Everything present: quiet by default, a summary with --verbose, exit 0.
{
  const stubs = {
    bun: "echo 1.2.3",
    swift: 'if [ "$1" = "sdk" ]; then echo "swift-6.4.0-RELEASE_wasm-embedded"; else echo "Apple Swift version 6.4 (swift-6.4-RELEASE)"; fi',
  };
  const quiet = report(stubs, ["--quiet"]);
  assert.equal(quiet.status, 0, quiet.err);
  assert.equal(quiet.out + quiet.err, "");
  const verbose = report(stubs, ["--verbose"]);
  assert.equal(verbose.status, 0, verbose.err);
  assert.match(verbose.out, /everything required is installed/);
  assert.match(verbose.out, /ok\s+swift/);
  assert.match(verbose.out, /optional\s+wasm-opt/);
  // An older Swift is reported as such even though it runs.
  const old = report({ ...stubs, swift: 'if [ "$1" = "sdk" ]; then echo "swift-6.1.0-RELEASE_wasm-embedded"; else echo "Apple Swift version 6.1 (swift-6.1-RELEASE)"; fi' });
  assert.equal(old.status, 1);
  assert.match(old.err, /older than 6\.4/);
}

// 4. The development profile `fast` needs the toolchain's regular WebAssembly SDK, not the Embedded one.
{
  const swift = (sdks) => `if [ "$1" = "sdk" ]; then printf '%s\\n' ${sdks}; else echo "Apple Swift version 6.4 (swift-6.4-RELEASE)"; fi`;
  const fast = { SWIFTUIWEB_DEV_PROFILE: "fast" };
  const embeddedOnly = report({ bun: "echo 1.2.3", swift: swift("swift-6.4.0-RELEASE_wasm-embedded") }, [], fast);
  assert.equal(embeddedOnly.status, 1);
  assert.deepEqual(missingLines(embeddedOnly.err), ["wasm sdk"]);
  assert.match(embeddedOnly.err, /SWIFTUIWEB_DEV_PROFILE=fast/);
  const both = report({ bun: "echo 1.2.3", swift: swift("swift-6.4.0-RELEASE_wasm swift-6.4.0-RELEASE_wasm-embedded") }, ["--verbose"], fast);
  assert.equal(both.status, 0, both.err);
  assert.match(both.out, /ok\s+wasm sdk\s+swift-6\.4\.0-RELEASE_wasm\n/);
}

console.log("PASS toolchain report lists every missing tool at once, with a fix for each");
