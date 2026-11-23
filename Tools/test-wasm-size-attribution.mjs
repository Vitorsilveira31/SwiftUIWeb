#!/usr/bin/env bun
// Tests of Tools/wasm-size-attribution.mjs on hand-built modules and injected demangled names: no Swift toolchain needed.
// The sample checks (a real named module of a large application) are run by hand; their numbers are in the tool's report.
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { addressTaken, buildReport, classify, diffReports, owner, printDiff, readProfile, splitOverhead } from "./wasm-size-attribution.mjs";
import { parse } from "./wasm-function-sizes.mjs";
import { finish, ROOT, test, withTemporary } from "./measurement-test-support.mjs";

const EMPTY_WASM = Buffer.from("0061736d01000000", "hex");

function leb(value) {
  const bytes = [];
  let rest = value;
  do {
    let byte = rest & 0x7f;
    rest >>>= 7;
    if (rest) byte |= 0x80;
    bytes.push(byte);
  } while (rest);
  return Buffer.from(bytes);
}
const text = (value) => Buffer.concat([leb(Buffer.byteLength(value)), Buffer.from(value)]);
const section = (kind, payload) => Buffer.concat([Buffer.from([kind]), leb(payload.length), payload]);
/** A body payload of `size` bytes: no locals, filler, end. */
const filled = (size) => Buffer.concat([Buffer.from([0]), Buffer.alloc(size - 2, 1), Buffer.from([0x0b])]);
const entry = (payload) => Buffer.concat([leb(payload.length), payload]);

/** A module with one type, a function section for the bodies, the extra sections, and an optional name section. */
function wasmWith({ payloads, names = null, extra = [] }) {
  const parts = [
    EMPTY_WASM,
    section(1, Buffer.from([1, 0x60, 0, 0])),
    ...extra,
    section(3, Buffer.from([payloads.length, ...payloads.map(() => 0)])),
    section(10, Buffer.concat([leb(payloads.length), ...payloads.map(entry)])),
  ];
  if (names) {
    const entries = Buffer.concat([leb(names.length), ...names.map((name, index) => Buffer.concat([leb(index), text(name)]))]);
    parts.push(section(0, Buffer.concat([text("name"), Buffer.from([1]), leb(entries.length), entries])));
  }
  return Buffer.concat(parts);
}

/** Parse a module written to a temporary file, the way the tool does: parse() plus the bytes. */
function loadModule(directory, bytes) {
  const path = join(directory, "module.wasm");
  writeFileSync(path, bytes);
  return { ...parse(path), data: readFileSync(path) };
}

const u32 = (value) => {
  const bytes = Buffer.alloc(4);
  bytes.writeUInt32LE(value);
  return bytes;
};

const CLASSIFY = [
  ["generic specialization <Swift.Int> of Swift.Array.append(_:)", "generic-specialization", "Swift.Array.append(_:)"],
  ["function signature specialization <Arg[0] = Owned> of App.Model.update() -> ()", "signature-specialization", "App.Model.update() -> ()"],
  ["merged App.Helper.run() -> ()", "merged", "App.Helper.run() -> ()"],
  ["outlined copy of App.Pair", "outlined-copy", "App.Pair"],
  ["outlined destroy of App.Pair", "outlined-destroy", "App.Pair"],
  ["outlined init with copy of App.Pair", "outlined-init-copy", "App.Pair"],
  ["partial apply forwarder for closure #1 in App.Screen.body.getter", "partial-apply", "closure #1 in App.Screen.body.getter"],
  ["protocol witness for Swift.Hashable.hash(into:) in conformance App.Row", "protocol-witness", "Swift.Hashable.hash(into:) in conformance App.Row"],
  ["generic specialization <App.Row, Swift.Int> of generic specialization <App.Row> of App.Container.render<A>(_:)", "generic-specialization", "App.Container.render<A>(_:)"],
  ["generic specialization <App.Row> of closure #1 in App.List.render() -> ()", "generic-specialization", "closure #1 in App.List.render() -> ()"],
  ["outlined copy of generic specialization <App.Row> of App.Box.copy()", "generic-specialization", "App.Box.copy()"],
  ["App.Thing.make() -> App.Thing", "plain", "App.Thing.make() -> App.Thing"],
];

await test("classify names the kind and the function a specialization is a copy of", () => {
  for (const [name, kind, base] of CLASSIFY) {
    const result = classify(name);
    assert.equal(result.kind, kind, name);
    assert.equal(result.base, base, name);
  }
  assert.deepEqual(classify("memcpy", false), { kind: "non-swift", base: "memcpy" });
});

await test("owner folds closures and local bodies into the function they are in", () => {
  assert.equal(owner("closure #1 in closure #2 in App.Screen.make() -> ()"), "App.Screen.make() -> ()");
  assert.equal(owner("implicit closure #1 in App.Form.body.getter"), "App.Form.body.getter");
  assert.equal(owner("App.Plain.f()"), "App.Plain.f()");
});

await test("readProfile reads the module hash and whether each function ran", () => {
  const profile = Buffer.concat([Buffer.alloc(8, 0xab), u32(0), u32(7), u32(0)]);
  assert.deepEqual(readProfile(profile), { hash: "abababababababab", ran: [false, true, false] });
  assert.throws(() => readProfile(Buffer.alloc(10)), /an 8-byte module hash and one u32 per function/);
});

await test("addressTaken lists the defined functions in the element section, not the imports", () => {
  const extra = [
    section(2, Buffer.concat([Buffer.from([1]), text("env"), text("f"), Buffer.from([0, 0])])),
    // one segment at offset 0: functions 0 (imported) and 2 (the second defined function)
    section(9, Buffer.from([1, 0, 0x41, 0, 0x0b, 2, 0, 2])),
  ];
  const bytes = wasmWith({ payloads: [filled(2), filled(2), filled(2)], extra });
  assert.deepEqual([...addressTaken(bytes)], [1]);
  assert.deepEqual([...addressTaken(wasmWith({ payloads: [filled(2)] }))], []);
});

await test("splitOverhead counts a forwarding stub apart from a real function, with each entry's size prefix", () => {
  // Stub: no locals, local.get, i32.const, call_indirect, end (10 bytes with its size prefix). Real: i32.const, drop (6 bytes).
  const stub = Buffer.from([0, 0x20, 0, 0x41, 1, 0x11, 0, 0, 0x0b]);
  const real = Buffer.from([0, 0x41, 1, 0x1a, 0x0b]);
  const overhead = splitOverhead(wasmWith({ payloads: [stub, real] }));
  assert.deepEqual([overhead.stubs.count, overhead.stubs.raw], [1, 10]);
  assert.deepEqual([overhead.real.count, overhead.real.raw], [1, 6]);
  assert.ok(overhead.stubs.brotli > 0);
  assert.deepEqual(overhead.sections.map((row) => row.name), ["function"]);
});

await test("the copies of a generic are grouped by the function they copy, closures included", () =>
  withTemporary((directory) => {
    const names = ["$s4Core3GenV4makeyyF0", "$s4Core3GenV4makeyyF1", "$s4Core3GenV4makeyyF2", "$s4Core3GenV4makeyyF3", "$s4Shop3RowV4bodyyF"];
    const demangled = [
      "generic specialization <Shop.A> of Core.Gen.make() -> ()",
      "generic specialization <Shop.B> of Core.Gen.make() -> ()",
      "generic specialization <Shop.B> of closure #1 in Core.Gen.make() -> ()",
      "Core.Gen.make() -> ()",
      "Shop.Row.body.getter",
    ];
    const bytes = wasmWith({ payloads: [filled(10), filled(20), filled(30), filled(40), filled(5)], names });
    const report = buildReport(loadModule(directory, bytes), demangled, { appModules: ["Shop"], profile: null, splitPrimary: null });
    assert.deepEqual(report.copies, [{ name: "Core.Gen.make() -> ()", bytes: 60, count: 3 }]);
    assert.equal(report.codeBytes, 105);
  }));

await test("application code, framework code copied for application types and framework code are three rows", () =>
  withTemporary((directory) => {
    const names = ["$s4Core3GenV4makeyyF0", "$s4Core3GenV4makeyyF1", "$s4Core3GenV4makeyyF2", "$s4Core3GenV4makeyyF3", "$s4Shop3RowV4bodyyF"];
    const demangled = [
      "generic specialization <Shop.A> of Core.Gen.make() -> ()",
      "generic specialization <Shop.B> of Core.Gen.make() -> ()",
      "generic specialization <Shop.B> of closure #1 in Core.Gen.make() -> ()",
      "Core.Gen.make() -> ()",
      "Shop.Row.body.getter",
    ];
    const bytes = wasmWith({ payloads: [filled(10), filled(20), filled(30), filled(40), filled(5)], names });
    const report = buildReport(loadModule(directory, bytes), demangled, { appModules: ["Shop"], profile: null, splitPrimary: null });
    assert.deepEqual(report.origins, [
      { name: "framework code copied for application types", bytes: 60, count: 3 },
      { name: "framework and runtime, no application type", bytes: 40, count: 1 },
      { name: "application code", bytes: 5, count: 1 },
    ]);
  }));

await test("a profile of another build is refused with both function counts", () =>
  withTemporary((directory) => {
    const names = ["$s4Core1AV1fyyF", "$s4Core1AV1gyyF", "$s4Core1AV1hyyF"];
    const bytes = wasmWith({ payloads: [filled(2), filled(2), filled(2)], names });
    const profile = Buffer.concat([Buffer.alloc(8), u32(1), u32(0), u32(1), u32(0)]);
    assert.throws(
      () => buildReport(loadModule(directory, bytes), ["a", "b", "c"], { appModules: [], profile, splitPrimary: null }),
      /the profile has 4 functions, the module 3/,
    );
  }));

await test("the first screen is counted from the profile, and its address-taken functions that did not run", () =>
  withTemporary((directory) => {
    const names = ["$s4Core1AV1fyyF", "$s4Core1AV1gyyF", "$s4Core1AV1hyyF"];
    const extra = [section(9, Buffer.from([1, 0, 0x41, 0, 0x0b, 3, 0, 1, 2]))];
    const bytes = wasmWith({ payloads: [filled(2), filled(4), filled(8)], names, extra });
    const profile = Buffer.concat([Buffer.alloc(8), u32(3), u32(0), u32(1)]);
    const report = buildReport(loadModule(directory, bytes), ["Core.A.f()", "Core.A.g()", "Core.A.h()"], { appModules: [], profile, splitPrimary: null });
    assert.deepEqual([report.profile.functions, report.profile.bytes], [2, 10]);
    assert.deepEqual(report.profile.modules, [{ name: "Core", bytes: 10, count: 2 }]);
    assert.deepEqual(report.profile.largest.map((row) => row.name), ["Core.A.h()", "Core.A.f()"]);
    assert.deepEqual([report.addressTaken.count, report.addressTaken.notRun], [3, 1]);
  }));

await test("a module without a name section reports what needs no names", () =>
  withTemporary((directory) => {
    const bytes = wasmWith({ payloads: [filled(2), filled(4)] });
    const report = buildReport(loadModule(directory, bytes), null, { appModules: [], profile: null, splitPrimary: null });
    assert.equal(report.named, false);
    assert.equal(report.modules, undefined);
    assert.equal(report.copies, undefined);
    assert.equal(report.functions, 2);
    assert.equal(report.codeBytes, 6);
    assert.deepEqual(report.addressTaken, { count: 0, bytes: 0 });
    assert.ok(report.sections.some((row) => row.name === "code" && row.raw > 0));
  }));

await test("the difference of two reports lists the kinds and the generics that changed, largest change first", () => {
  const before = {
    bytes: 1000, functions: 10, codeBytes: 800,
    kinds: [{ name: "plain", bytes: 500, count: 5 }, { name: "generic-specialization", bytes: 300, count: 5 }],
    copies: [{ name: "Core.A.f()", bytes: 200, count: 4 }, { name: "Core.B.g()", bytes: 100, count: 1 }],
  };
  const after = {
    bytes: 900, functions: 8, codeBytes: 700,
    kinds: [{ name: "plain", bytes: 520, count: 5 }, { name: "generic-specialization", bytes: 180, count: 3 }],
    copies: [{ name: "Core.A.f()", bytes: 60, count: 1 }, { name: "Core.B.g()", bytes: 100, count: 1 }, { name: "Core.C.h()", bytes: 20, count: 1 }],
  };
  const diff = diffReports(before, after);
  assert.deepEqual([diff.codeBytes, diff.functions, diff.bytes], [-100, -2, -100]);
  assert.deepEqual(diff.copies.map((row) => [row.name, row.bytes, row.count]), [["Core.A.f()", -140, -3], ["Core.C.h()", 20, 1]]);
  assert.deepEqual(diff.kinds.map((row) => [row.name, row.bytes]), [["generic-specialization", -120], ["plain", 20]]);
  const lines = [];
  printDiff(diff, 5, (line) => lines.push(line));
  assert.match(lines[0], /code bytes 800 -> 700 \(-100\); functions 10 -> 8 \(-2\)/);
  assert.ok(lines.some((line) => /-140\s+4x -> 1x\s+200 -> 60\s+Core\.A\.f\(\)/.test(line)));
});

await test("make wasm-attribution runs the tool with the profile, split and application modules", () => {
  const text = Bun.spawnSync(["make", "-n", "wasm-attribution", "WASM=named.wasm", "PROFILE=first.prof", "SPLIT=app.wasm", "APP_MODULES=A,B"], { cwd: ROOT, stdout: "pipe", stderr: "pipe" }).stdout.toString();
  assert.match(text, /bun Tools\/wasm-size-attribution\.mjs "named\.wasm" --profile "first\.prof" --split-primary "app\.wasm" --app-modules "A,B"/);
});

finish();
