#!/usr/bin/env bun
// Tests `swiftuiweb-tools strip-wasm` end to end: only name/DWARF sections go, the rest is byte-identical,
// the result still runs, and invalid input is never overwritten.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const TOOLS = join(ROOT, "Tools/swiftuiweb-tools.sh");
const MAGIC = Buffer.from("\0asm\x01\0\0\0", "binary");

function leb(value) {
  const bytes = [];
  do {
    let byte = value & 127;
    value >>= 7;
    bytes.push(value ? byte | 128 : byte);
  } while (value);
  return Buffer.from(bytes);
}

function custom(name, payload = Buffer.from("example")) {
  const encoded = Buffer.from(name);
  const body = Buffer.concat([leb(encoded.length), encoded, payload]);
  return Buffer.concat([Buffer.from([0]), leb(body.length), body]);
}

function strip(args) {
  return spawnSync(TOOLS, ["strip-wasm", ...args], { encoding: "utf8" });
}

function withDirectory(body) {
  const directory = mkdtempSync(join(tmpdir(), "strip-wasm-"));
  try { return body(directory); } finally { rmSync(directory, { recursive: true, force: true }); }
}

test("only debug metadata is removed, byte for byte", () => withDirectory((directory) => {
  const executable = Buffer.from([0x01, 0x01, 0x00]); // empty type section
  const retained = Buffer.concat([custom("target_features"), custom("producers"), custom("user-section")]);
  const raw = Buffer.concat([MAGIC, custom(".debug_info"), executable, custom("name"), retained, custom(".debug_line")]);
  const input = join(directory, "in.wasm");
  const output = join(directory, "nested/out.wasm");
  writeFileSync(input, raw);
  const result = strip([input, output]);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(readFileSync(output), Buffer.concat([MAGIC, executable, retained]));
  const report = JSON.parse(result.stdout);
  assert.deepEqual(report.removed.map((section) => section.name), [".debug_info", "name", ".debug_line"]);
  assert.equal(report.removed.reduce((sum, section) => sum + section.bytes, 0), raw.length - readFileSync(output).length);
  assert.equal(report.before, raw.length);
  assert.equal(report.after, readFileSync(output).length);
  // Compact layout: separators ", " and ": ".
  assert.match(result.stdout, /^\{"wasm": ".*", "before": \d+, "after": \d+, "removed": \[\{"name": ".debug_info", "bytes": \d+\}/);
  // Stripping again is a no-op that leaves the file untouched.
  const before = readFileSync(output);
  const again = strip([output]);
  assert.equal(again.status, 0, again.stderr);
  assert.deepEqual(JSON.parse(again.stdout).removed, []);
  assert.deepEqual(readFileSync(output), before);
}));

test("in-place rewrite keeps the file mode", () => withDirectory((directory) => {
  const path = join(directory, "app.wasm");
  writeFileSync(path, Buffer.concat([MAGIC, custom("name")]));
  chmodSync(path, 0o751);
  assert.equal(strip([path]).status, 0);
  assert.deepEqual(readFileSync(path), MAGIC);
  assert.equal(statSync(path).mode & 0o777, 0o751);
}));

test("missing, truncated and overflowing headers fail and preserve the input", () => withDirectory((directory) => {
  const cases = [
    Buffer.from("!<arch>\n"),
    Buffer.concat([MAGIC, Buffer.from([0x00, 0x80])]),
    Buffer.concat([MAGIC, Buffer.from([0x00, 0xff, 0xff, 0xff, 0xff, 0x1f])]),
    Buffer.concat([MAGIC, Buffer.from([0x00, 0x05, 0x01, 0x61])]),
    Buffer.concat([MAGIC, Buffer.from([0x00, 0x02, 0x05, 0x61])]), // custom name escapes its section
    Buffer.from("invalid, preserve me"),
  ];
  for (const data of cases) {
    const path = join(directory, "app.wasm");
    writeFileSync(path, data);
    const result = strip([path]);
    assert.notEqual(result.status, 0, `accepted ${data.toString("hex")}`);
    assert.match(result.stderr, /Wasm stripping failed/);
    assert.deepEqual(readFileSync(path), data);
  }
}));

test("an executable module still runs after stripping", async () => withDirectory(async (directory) => {
  const wasm = Buffer.concat([MAGIC, Buffer.from("0105016000017f030201000709010576616c756500000a0601040041070b", "hex")]);
  const input = join(directory, "test.wasm");
  writeFileSync(input, Buffer.concat([wasm, custom(".debug_info"), custom("name")]));
  assert.equal(strip([input]).status, 0);
  assert.deepEqual(readFileSync(input), wasm);
  const { instance } = await WebAssembly.instantiate(readFileSync(input));
  assert.equal(instance.exports.value(), 7);
}));

test("usage errors exit non-zero", () => {
  assert.notEqual(strip([]).status, 0);
});

// Tools/strip-wasm-release.sh keeps the result for a module in WASM_STRIP_CACHE_DIR and reuses it: an unchanged module
// skips the strip and Binaryen, a changed one, or other options, do not.
test("the release strip reuses its result for the same input and options", () => withDirectory((directory) => {
  const script = join(ROOT, "Tools/strip-wasm-release.sh");
  const cache = join(directory, "cache");
  const env = { ...process.env, WASM_STRIP_CACHE_DIR: cache, WASM_OPT: "0", WASM_SIZE_REPORT: "0" };
  const run = (input, output, extra = {}) => spawnSync(script, [input, output], { encoding: "utf8", env: { ...env, ...extra } });
  const raw = Buffer.concat([MAGIC, custom(".debug_info"), Buffer.from([0x01, 0x01, 0x00]), custom("name"), custom("producers")]);
  const input = join(directory, "in.wasm");
  writeFileSync(input, raw);

  const first = run(input, join(directory, "first.wasm"));
  assert.equal(first.status, 0, first.stderr);
  assert.doesNotMatch(first.stderr, /reused the earlier result/);
  const expected = readFileSync(join(directory, "first.wasm"));
  assert.ok(expected.length < raw.length);

  const second = run(input, join(directory, "second.wasm"));
  assert.equal(second.status, 0, second.stderr);
  assert.match(second.stderr, /reused the earlier result/);
  assert.deepEqual(readFileSync(join(directory, "second.wasm")), expected);

  // The same bytes with another option are a different entry.
  const otherOption = run(input, join(directory, "third.wasm"), { WASM_OPT_LEVEL: "O1" });
  assert.equal(otherOption.status, 0, otherOption.stderr);
  assert.doesNotMatch(otherOption.stderr, /reused the earlier result/);

  // Other bytes are a different entry too.
  const changed = join(directory, "changed.wasm");
  writeFileSync(changed, Buffer.concat([raw, custom("another-section")]));
  const fourth = run(changed, join(directory, "fourth.wasm"));
  assert.equal(fourth.status, 0, fourth.stderr);
  assert.doesNotMatch(fourth.stderr, /reused the earlier result/);

  // In place, the way the launcher calls it, still works from the cache.
  const inPlace = join(directory, "inplace.wasm");
  writeFileSync(inPlace, raw);
  const fifth = run(inPlace, inPlace);
  assert.equal(fifth.status, 0, fifth.stderr);
  assert.match(fifth.stderr, /reused the earlier result/);
  assert.deepEqual(readFileSync(inPlace), expected);
}));

// WASM_KEEP_NAMES=1 is the module as it ships, with its names, for a size attribution: nothing is stripped, and it is
// another cache entry than the stripped module of the same input. WASM_OPT_ROUNDS is checked before anything runs.
test("the release strip keeps the names when asked, and checks the round count", () => withDirectory((directory) => {
  const script = join(ROOT, "Tools/strip-wasm-release.sh");
  const cache = join(directory, "cache");
  const env = { ...process.env, WASM_STRIP_CACHE_DIR: cache, WASM_OPT: "0", WASM_SIZE_REPORT: "0" };
  const run = (input, output, extra = {}) => spawnSync(script, [input, output], { encoding: "utf8", env: { ...env, ...extra } });
  const raw = Buffer.concat([MAGIC, Buffer.from([0x01, 0x01, 0x00]), custom("name"), custom("producers")]);
  const input = join(directory, "in.wasm");
  writeFileSync(input, raw);

  const stripped = run(input, join(directory, "stripped.wasm"));
  assert.equal(stripped.status, 0, stripped.stderr);
  assert.ok(readFileSync(join(directory, "stripped.wasm")).length < raw.length);

  const named = run(input, join(directory, "named.wasm"), { WASM_KEEP_NAMES: "1" });
  assert.equal(named.status, 0, named.stderr);
  assert.doesNotMatch(named.stderr, /reused the earlier result/);
  assert.deepEqual(readFileSync(join(directory, "named.wasm")), raw);
  assert.deepEqual(readFileSync(input), raw);

  // In place, the names stay too.
  const inPlace = join(directory, "inplace.wasm");
  writeFileSync(inPlace, raw);
  assert.equal(run(inPlace, inPlace, { WASM_KEEP_NAMES: "1", WASM_STRIP_CACHE_DIR: "" }).status, 0);
  assert.deepEqual(readFileSync(inPlace), raw);

  // Another round count is another entry, and a count that is not 1 to 9 is refused.
  const oneRound = run(input, join(directory, "one.wasm"), { WASM_OPT_ROUNDS: "1" });
  assert.equal(oneRound.status, 0, oneRound.stderr);
  assert.doesNotMatch(oneRound.stderr, /reused the earlier result/);
  for (const rounds of ["0", "10", "two"]) {
    const refused = run(input, join(directory, "refused.wasm"), { WASM_OPT_ROUNDS: rounds });
    assert.equal(refused.status, 64, rounds);
    assert.match(refused.stderr, /WASM_OPT_ROUNDS is 1 to 9/);
  }
}));

// Without Binaryen the release strip still succeeds, but says so: an unoptimized app.wasm is a regression nobody should
// ship silently. WASM_OPT=0 is a deliberate choice and stays quiet. The check runs with a PATH that has no wasm-opt, so
// it is skipped on a machine where /usr/bin or /bin provides one.
const noBinaryenPath = "/usr/bin:/bin";
const binaryenOnSystemPath = spawnSync("sh", ["-c", "command -v wasm-opt"], { encoding: "utf8", env: { ...process.env, PATH: noBinaryenPath } }).status === 0;
test("the release strip warns when wasm-opt is missing and stays quiet when WASM_OPT=0", { skip: binaryenOnSystemPath && "wasm-opt is on the system PATH" }, () => withDirectory((directory) => {
  const script = join(ROOT, "Tools/strip-wasm-release.sh");
  const input = join(directory, "in.wasm");
  writeFileSync(input, Buffer.concat([MAGIC, custom("name")]));
  const base = { ...process.env, PATH: noBinaryenPath, WASM_SIZE_REPORT: "0", WASM_STRIP_CACHE_DIR: "" };
  const missing = spawnSync(script, [input, join(directory, "missing.wasm")], { encoding: "utf8", env: base });
  assert.equal(missing.status, 0, missing.stderr);
  assert.match(missing.stderr, /warning: wasm-opt \(Binaryen\) is not installed/);

  const off = spawnSync(script, [input, join(directory, "off.wasm")], { encoding: "utf8", env: { ...base, WASM_OPT: "0" } });
  assert.equal(off.status, 0, off.stderr);
  assert.doesNotMatch(off.stderr, /wasm-opt/);
}));
