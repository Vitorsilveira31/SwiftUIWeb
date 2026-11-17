#!/usr/bin/env bun
// Tests Tools/wasm-audit.mjs: the strict module parser, the link-map attribution primitives and a whole run on a small bundle.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { Reader, bucket, cover, markdown, parseLinkMap, parseModule } from "./wasm-audit.mjs";

const AUDIT = join(dirname(fileURLToPath(import.meta.url)), "wasm-audit.mjs");
const MAGIC = Buffer.from("\0asm\x01\0\0\0", "latin1");
const section = (id, ...payload) => Buffer.from([id, payload.length, ...payload]);
const custom = (name, body = "") => section(0, name.length, ...Buffer.from(name + body));

/** (func (result i32) i32.const 7), exported as "value", with a name section and a producers section. */
const module = () => Buffer.concat([
  MAGIC,
  section(1, 1, 0x60, 0, 1, 0x7f),
  section(3, 1, 0),
  section(7, 1, 5, ...Buffer.from("value"), 0, 0),
  section(10, 1, 4, 0, 0x41, 7, 0x0b),
  custom("name", "\x01\x07\x01\x00\x04main"),
  custom("producers", "\x01\x08language\x01\x05Swift\x036.4"),
]);

function withDirectory(body) {
  const directory = mkdtempSync(join(tmpdir(), "wasm-audit-"));
  try { return body(directory); } finally { rmSync(directory, { recursive: true, force: true }); }
}

test("the section boundaries add up to the module", () => {
  const data = Buffer.concat([MAGIC, section(1, 1, 0x60, 0, 1, 0x7f)]);
  const report = parseModule(data);
  assert.equal(report.raw_bytes, data.length);
  assert.equal(report.sections[0].raw_bytes, 7);
  const full = parseModule(module());
  assert.equal(8 + full.sections.reduce((sum, entry) => sum + entry.raw_bytes, 0), full.raw_bytes);
  assert.deepEqual(full.sections.map((entry) => entry.name), ["type", "function", "export", "code", "name", "producers"]);
});

test("functions carry their index, size, name and exports; producers and warnings are collected", () => {
  const report = parseModule(module());
  assert.equal(report.functions.length, 1);
  assert.deepEqual(
    { index: report.functions[0].index, body_bytes: report.functions[0].body_bytes, name: report.functions[0].name, exports: report.functions[0].exports },
    { index: 0, body_bytes: 4, name: "main", exports: ["value"] },
  );
  assert.deepEqual(report.producers, { language: [{ name: "Swift", version: "6.4" }] });
  assert.deepEqual(report.warnings, []);
  assert.equal(report.data_parse_status, "ABSENT");
  assert.equal(report.relocatable, false);
  // The semantic hash ignores custom sections, the raw hash does not.
  assert.equal(parseModule(Buffer.concat([module(), custom("later", "x")])).semantic_sha256, report.semantic_sha256);
  assert.notEqual(parseModule(Buffer.concat([module(), custom("later", "x")])).sha256, report.sha256);
});

test("data segments are decoded with their constant address", () => {
  const data = Buffer.concat([MAGIC, section(11, 2, 0, 0x41, 0x80, 0x01, 0x0b, 3, 1, 2, 3, 1, 2, 9, 9)]);
  const report = parseModule(data);
  assert.equal(report.data_parse_status, "PARSED");
  assert.deepEqual(report.data_segments.map((segment) => [segment.passive, segment.memory_address, segment.bytes]), [[false, 128, 3], [true, null, 2]]);
});

test("a section the parser cannot decode becomes a warning, not a failure", () => {
  const report = parseModule(Buffer.concat([MAGIC, section(11, 1, 5, 0x0b, 0)]));
  assert.equal(report.data_parse_status, "UNSUPPORTED");
  assert.match(report.warnings[0], /^data: unsupported data segment flags 5/);
});

test("a module with a linking section is relocatable", () => {
  assert.equal(parseModule(Buffer.concat([MAGIC, custom("linking")])).relocatable, true);
});

test("invalid modules are rejected", () => {
  assert.throws(() => parseModule(Buffer.from("not wasm")), /expected a WebAssembly/);
  assert.throws(() => parseModule(Buffer.concat([MAGIC, section(1, 0), section(1, 0)])), /duplicate standard section 1/);
  assert.throws(() => parseModule(Buffer.concat([MAGIC, section(99)])), /unknown section id 99/);
  assert.throws(() => parseModule(Buffer.concat([MAGIC, Buffer.from([1, 5, 0])])), /truncated data/);
  assert.throws(() => parseModule(Buffer.concat([MAGIC, section(3, 2, 0, 0)])), /function\/code section counts differ/);
});

test("the reader rejects truncated and overlong LEB128 values", () => {
  assert.throws(() => new Reader(Buffer.from([0x80]), 0, 1).uint(32), /truncated data/);
  assert.throws(() => new Reader(Buffer.from([0xff, 0xff, 0xff, 0xff, 0x7f]), 0, 5).uint(32), /overflowing unsigned LEB128/);
  assert.equal(new Reader(Buffer.from([0x80, 0x01]), 0, 2).uint(32), 128);
  assert.equal(new Reader(Buffer.from([0x7f]), 0, 1).signed(32), -1n);
});

test("link-map rows keep their group and ignore child symbols; inputs are classified", () => {
  const rows = parseLinkMap("  Addr Off Size Out In Symbol\n - 30 10 CODE\n - 31 8 /tmp/source.o:(add)\n - 31 8 add\n - 40 20 DATA\n 400 42 c /tmp/lib_FoundationICU.a(data.o):(.data.data)\n");
  assert.equal(rows.length, 2);
  assert.deepEqual([rows[0].section_group, rows[0].bytes], ["CODE", 8]);
  assert.deepEqual([rows[1].address, rows[1].category], [0x400, "ICU"]);
  assert.throws(() => parseLinkMap("not a map"), /expected a wasm-ld Addr \/ Off \/ Size link map/);
  assert.equal(bucket("/b/SwiftUIWebCore.build/a.o"), "SwiftUIWebCore");
  assert.equal(bucket("/b/SwiftUIWeb.build/a.o"), "SwiftUIWeb");
  assert.equal(bucket("libswiftCore.a(x.o)"), "Swift support");
  assert.equal(bucket("somewhere/else.o"), "Other / unclassified");
});

test("overlapping attribution is counted once and conflicts are separate", () => {
  const [totals, ambiguous] = cover([[0, 10, "A"], [5, 15, "A"], [8, 12, "B"]]);
  assert.equal(totals.get("A"), 11);
  assert.equal(totals.has("B"), false);
  assert.equal(ambiguous, 4);
});

test("a whole run writes the JSON and Markdown reports and the size gate", () => withDirectory((directory) => {
  const bundle = join(directory, "bundle");
  mkdirSync(join(bundle, "sub"), { recursive: true });
  writeFileSync(join(bundle, "app.wasm"), module());
  const html = '<script src="https://cdn.example/a.js"></script>';
  writeFileSync(join(bundle, "sub/index.html"), html);
  writeFileSync(join(bundle, "notes.md"), "not a runtime asset");
  writeFileSync(join(bundle, ".hidden.js"), "ignored");
  const output = join(directory, "out/report.json");
  const run = (...args) => spawnSync("bun", [AUDIT, bundle, "--output", output, ...args], { encoding: "utf8" });
  const result = run("--brotli-quality", "5", "--max-brotli", "1000000");
  assert.equal(result.status, 0, result.stderr);
  const report = JSON.parse(readFileSync(output, "utf8"));
  assert.deepEqual(report.runtime_assets.map((asset) => asset.path), ["app.wasm", "sub/index.html"]);
  assert.deepEqual(report.external_url_candidates, ["https://cdn.example/a.js"]);
  assert.equal(report.local_runtime_total.raw, module().length + html.length);
  assert.equal(report.brotli_quality, 5);
  assert.equal(report.modules[0].path, "app.wasm");
  assert.equal(report.modules[0].link_attribution, null);
  assert.equal(report.size_gate.limit_exclusive_bytes, 1000000);
  assert.ok(["WITHIN_TARGET", "UNMEASURED"].includes(report.size_gate.status));
  // The report's layout: two-space indent, sorted keys, no trailing newline.
  const text = readFileSync(output, "utf8");
  assert.ok(text.startsWith('{\n  "brotli_quality": 5,\n  "compression_profiles": {\n    "7z_ultra": {\n      "delivery": false,'));
  assert.ok(!text.endsWith("\n"));
  const summary = readFileSync(join(directory, "out/report.md"), "utf8");
  assert.equal(summary, markdown(report));
  assert.match(summary, /^# WebAssembly audit\n\nInput: `.*bundle`\n/);
  assert.match(summary, /\| "type" \| 7 \| /);
  assert.match(summary, /\| 0 \| 4 \| main \|/);
  assert.equal(result.stdout, `${summary}\nJSON: ${output}\nMarkdown: ${join(directory, "out/report.md")}\n`);
}));

test("bad input fails with a message and status 1", () => withDirectory((directory) => {
  const run = (...args) => spawnSync("bun", [AUDIT, ...args], { encoding: "utf8" });
  assert.match(run().stderr, /usage: wasm-audit <bundle>/);
  assert.match(run(join(directory, "missing")).stderr, /input path does not exist/);
  writeFileSync(join(directory, "a.txt"), "x");
  assert.match(run(join(directory, "a.txt")).stderr, /a single-file input must be a final \.wasm/);
  writeFileSync(join(directory, "bad.wasm"), "nope");
  const bad = run(join(directory, "bad.wasm"), "--output", join(directory, "r.json"));
  assert.equal(bad.status, 1);
  assert.match(bad.stderr, /expected a WebAssembly/);
  writeFileSync(join(directory, "ok.wasm"), module());
  assert.match(run(join(directory, "ok.wasm"), "--bogus", "1").stderr, /unknown argument --bogus/);
  assert.match(run(join(directory, "ok.wasm"), "--max-brotli", "0").stderr, /max-brotli must be positive/);
  assert.match(run(join(directory, "ok.wasm"), "--map-reference", join(directory, "ok.wasm")).stderr, /map-reference requires link-map/);
  assert.match(run(join(directory, "ok.wasm"), "--link-map", join(directory, "none")).stderr, /link map does not exist/);
}));
