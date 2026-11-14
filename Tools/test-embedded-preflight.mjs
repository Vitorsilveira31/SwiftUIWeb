// Run: bun test ./Tools/test-embedded-preflight.mjs
// Tests of the embedded tools' inventory and preflight reporting (the two `make -n` cases live
// in Tools/test-size-tools.mjs). Fake compiler cases test reporting, not Swift support; no real swiftc is needed.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { GUARD, PROBES, REQUIRED, inventory, maskCommentsAndLiterals } from "./embedded-preflight.mjs";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "embedded-preflight.mjs");

function runScript(args, env = process.env) {
  return spawnSync(process.execPath, [SCRIPT, ...args], { encoding: "utf8", env, timeout: 40000 });
}

function withTemp(fn) {
  const directory = mkdtempSync(join(tmpdir(), "swui-preflight-"));
  try {
    return fn(directory);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function fakeCompiler(directory, body, name = "fake-swiftc") {
  const path = join(directory, name);
  writeFileSync(path, `#!/bin/sh\n${body}\n`);
  chmodSync(path, 0o755);
  return path;
}

function withoutSdk() {
  const env = { ...process.env };
  delete env.WASM_SDK;
  return env;
}

// --- InventoryTests --------------------------------------------------------------------------------------------

test("comment mask preserves line numbers and length", () => {
  const source = "// weak ignored\n/* outer\n/* weak */\n*/\nweak var owner: Owner?\n";
  const masked = maskCommentsAndLiterals(source);
  assert.equal(masked.split("\n").length, source.split("\n").length);
  assert.equal(masked.split("weak").length - 1, 1);
  assert.equal(masked.length, source.length);
});

test("literals are not reported as code, but key paths outside literals are kept", () => {
  const source = 'let x = "weak and \\"quoted\\""\nlet y = #"Codable \\"quoted\\""#\nlet z = """\nAnyHashable\n"""\nlet id: KeyPath<R,Int> = \\.id\n';
  const masked = maskCommentsAndLiterals(source);
  assert.ok(!masked.includes("weak"));
  assert.ok(!masked.includes("Codable"));
  assert.ok(!masked.includes("AnyHashable"));
  assert.ok(masked.includes("KeyPath<R,Int>"));
  assert.ok(masked.includes("\\.id"));
});

test("all probes enforce real Embedded mode", () => {
  assert.ok(GUARD.includes("!hasFeature(Embedded)"));
  assert.ok(GUARD.includes("#error"));
  assert.ok(Object.keys(PROBES).length >= 10);
  assert.ok(!REQUIRED.has("typed-throws"));
  for (const [name, [, source]] of Object.entries(PROBES)) {
    assert.ok(source.includes('@_cdecl("probe")'), `${name} exports the probe`);
  }
});

test("the source inventory states it is lexical, not reachability", () => {
  const result = inventory();
  assert.ok(result.scope.includes("ALL_CONDITIONAL_BRANCHES"));
  assert.ok(result.caveat.includes("not a linked dependency graph"));
  assert.ok(result.counts["keypath-type"] > 0);
});

test("the inventory reports paths relative to the root and 1-based lines, sorted by path parts", () => {
  withTemp((directory) => {
    mkdirSync(join(directory, "Sources/B/Nested"), { recursive: true });
    mkdirSync(join(directory, "Sources/A"), { recursive: true });
    writeFileSync(join(directory, "Sources/B/Nested/Deep.swift"), "// comment\nimport Foundation\n");
    writeFileSync(join(directory, "Sources/A/Zed.swift"), "let x = 1\r\nlet owner: weak Owner\r\n");
    writeFileSync(join(directory, "Sources/B/Top.swift"), "let y: KeyPath<A, Int>\n");
    const result = inventory(directory);
    // The erased comment leaves its newline behind, and the anchored `^\s*` of the pattern consumes it, so the
    // import is reported at line 1 as well.
    assert.deepEqual(result.matches["foundation-import"], [{ path: "Sources/B/Nested/Deep.swift", line: 1 }]);
    assert.deepEqual(result.matches["weak-unowned"], [{ path: "Sources/A/Zed.swift", line: 2 }]);
    assert.deepEqual(
      result.matches["keypath-type"].map((match) => match.path),
      ["Sources/B/Top.swift"],
    );
    assert.equal(result.counts["weak-unowned"], 1);
  });
});

// --- PreflightReportingTests -----------------------------------------------------------------------------------

test("a missing compiler is BLOCKED, not passed", () => {
  withTemp((directory) => {
    const out = join(directory, "out");
    const result = runScript(["--swiftc", "/missing/embedded-swiftc", "--output", out], withoutSdk());
    assert.notEqual(result.status, 0);
    const report = JSON.parse(readFileSync(join(out, "result.json"), "utf8"));
    assert.equal(report.full_framework_embedded, false);
    assert.equal(report.status, "BLOCKED");
    assert.ok(report.required_failures.includes("compiler"));
    assert.equal(result.stdout.includes('"status": "BLOCKED"'), true);
  });
});

test("a zero exit without an object does not count as a compile", () => {
  withTemp((directory) => {
    const compiler = fakeCompiler(directory, "exit 0");
    const out = join(directory, "out");
    const result = runScript(["--swiftc", compiler, "--output", out]);
    assert.notEqual(result.status, 0);
    const report = JSON.parse(readFileSync(join(out, "result.json"), "utf8"));
    assert.equal(report.probes.length, Object.keys(PROBES).length);
    for (const check of report.probes) {
      assert.equal(check.status, "UNSUPPORTED_OR_FAILED");
      assert.equal(check.object_sha256, null);
      assert.ok(check.command.includes("Embedded"));
      assert.ok(check.command.includes("-wmo"));
      assert.ok(!check.command.includes("-disable-embedded-restrictions"));
    }
  });
});

test("a failed probe cannot reuse an old object, and its stderr is kept", () => {
  withTemp((directory) => {
    const compiler = fakeCompiler(directory, "echo intentional compiler failure >&2\nexit 1");
    const out = join(directory, "out");
    mkdirSync(out, { recursive: true });
    writeFileSync(join(out, "embedded-mode.o"), "stale output");
    const result = runScript(["--swiftc", compiler, "--output", out]);
    assert.notEqual(result.status, 0);
    const report = JSON.parse(readFileSync(join(out, "result.json"), "utf8"));
    assert.equal(existsSync(join(out, "embedded-mode.o")), false);
    assert.equal(report.probes[0].object_sha256, null);
    assert.ok(report.probes[0].stderr.includes("intentional compiler failure"));
  });
});

test("probe sources are written with the Embedded guard prepended", () => {
  withTemp((directory) => {
    const compiler = fakeCompiler(directory, 'out=""; prev=""; for a in "$@"; do if [ "$prev" = "-o" ]; then out="$a"; fi; prev="$a"; done\nprintf object > "$out"\nexit 0');
    const out = join(directory, "out");
    runScript(["--swiftc", compiler, "--output", out]);
    const written = readFileSync(join(out, "embedded-mode.swift"), "utf8");
    assert.ok(written.startsWith(GUARD));
    assert.ok(written.includes('@_cdecl("probe")'));
  });
});

test("--compile-core requires an explicit SDK and does not guess one", () => {
  withTemp((directory) => {
    const out = join(directory, "out");
    const result = runScript(["--swiftc", "/missing/compiler", "--compile-core", "--output", out], withoutSdk());
    const report = JSON.parse(readFileSync(join(out, "result.json"), "utf8"));
    assert.notEqual(result.status, 0);
    assert.equal(report.core.status, "BLOCKED");
    assert.equal(report.full_framework_embedded, false);
  });
});

test("non-ASCII command output is escaped as in json.dumps (ensure_ascii)", () => {
  withTemp((directory) => {
    const compiler = fakeCompiler(directory, 'if [ "$1" = "--version" ]; then echo "Fake \u00fc 6.0"; exit 0; fi\nexit 1');
    const out = join(directory, "out");
    runScript(["--swiftc", compiler, "--output", out]);
    const raw = readFileSync(join(out, "result.json"), "utf8");
    assert.ok(raw.includes('"swiftc": "Fake \\u00fc 6.0"'));
    assert.equal(JSON.parse(raw).swiftc, "Fake \u00fc 6.0");
  });
});
