// Tests Tools/wasm-split-release.mjs without a browser: the cache key, the cache hit that runs no browser, --check on a
// machine without wasm-split, and --fallback, which leaves an unsplit bundle as it was and exits 3 so the launcher builds the
// runtime scripts again without the split loader. Also the choice of layout: the target_features reader, the copy without that
// section and the flags that keep reference types out of the split. The split itself runs in Tools/test-wasm-split-browser.mjs.
// Run with: bun test ./Tools/test-wasm-split-release.mjs
import { expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { cacheKey, dataHook, FELL_BACK, FEATURE_FLAGS, instrumentation, planLayout, readTargetFeatures, splitBundle, whyNotOwnTable, withoutTargetFeatures } from "./wasm-split-release.mjs";

const SCRIPT = resolve(dirname(fileURLToPath(import.meta.url)), "wasm-split-release.mjs");
const VIEWPORTS = [{ width: 1280, height: 800 }];

function bundle(files = {}) {
  const directory = mkdtempSync(join(tmpdir(), "wasm-split-release-test-"));
  const all = { "app.wasm": "module bytes", "index.html": "<!doctype html>", "index.js": "page", "render-worker.js": "worker", "runtime-shared.js": "shared", ...files };
  for (const [name, text] of Object.entries(all)) writeFileSync(join(directory, name), text);
  return directory;
}

function run(args, env = process.env) {
  return spawnSync(process.execPath, [SCRIPT, ...args], { encoding: "utf8", env });
}

test("the cache key follows the module, the page's scripts and the profile settings", () => {
  const a = bundle();
  const key = cacheKey(a, { route: "/", viewports: VIEWPORTS });
  expect(cacheKey(bundle(), { route: "/", viewports: VIEWPORTS })).toBe(key);
  expect(cacheKey(bundle({ "app.wasm": "other module" }), { route: "/", viewports: VIEWPORTS })).not.toBe(key);
  expect(cacheKey(bundle({ "runtime-shared.js": "other shared" }), { route: "/", viewports: VIEWPORTS })).not.toBe(key);
  expect(cacheKey(a, { route: "/en", viewports: VIEWPORTS })).not.toBe(key);
  expect(cacheKey(a, { route: "/", viewports: [{ width: 390, height: 844 }] })).not.toBe(key);
});

test("a cached split is reused without a browser", async () => {
  const directory = bundle();
  const cacheDir = mkdtempSync(join(tmpdir(), "wasm-split-cache-test-"));
  const key = cacheKey(directory, { route: "/", viewports: VIEWPORTS });
  writeFileSync(join(cacheDir, `${key}.app.wasm`), "first screen");
  writeFileSync(join(cacheDir, `${key}.rest.wasm`), "the rest");
  writeFileSync(join(cacheDir, `${key}.prof`), "profile");
  const logDir = join(directory, "logs");
  const lines = [];
  const measured = await splitBundle(directory, { route: "/", viewports: VIEWPORTS, cacheDir, logDir, log: (line) => lines.push(line) });
  expect(readFileSync(join(directory, "app.wasm"), "utf8")).toBe("first screen");
  expect(readFileSync(join(directory, "app-rest.wasm"), "utf8")).toBe("the rest");
  expect(readFileSync(join(logDir, "first-screen.prof"), "utf8")).toBe("profile");
  expect(measured.before.raw).toBe("module bytes".length);
  expect(lines.join("\n")).toContain("earlier build");
  rmSync(cacheDir, { recursive: true, force: true });
});

test("--check says why a machine without wasm-split cannot split", () => {
  const empty = mkdtempSync(join(tmpdir(), "wasm-split-no-path-"));
  const result = run(["--check"], { ...process.env, PATH: empty });
  expect(result.status).toBe(1);
  expect(result.stderr).toContain("wasm-split is not installed");
});

test("--fallback leaves the bundle unsplit and exits 3; without it the failure is an error", () => {
  // Not a WebAssembly module: whatever this machine has, the split fails.
  const fallback = bundle({ "app.wasm": "not a module" });
  const result = run([fallback, "--fallback", "--viewports", "1280x800"]);
  expect(result.status).toBe(FELL_BACK);
  expect(result.stderr).toContain("is NOT split");
  expect(readFileSync(join(fallback, "app.wasm"), "utf8")).toBe("not a module");
  expect(existsSync(join(fallback, "app-rest.wasm"))).toBe(false);

  const strict = bundle({ "app.wasm": "not a module" });
  const failed = run([strict, "--viewports", "1280x800"]);
  expect(failed.status).not.toBe(0);
  expect(failed.status).not.toBe(FELL_BACK);
  expect(existsSync(join(strict, "app-rest.wasm"))).toBe(false);
});

test("a bundle that is split already is refused", async () => {
  const directory = bundle({ "app-rest.wasm": "rest" });
  mkdirSync(join(directory, "logs"));
  await expect(splitBundle(directory, { viewports: VIEWPORTS, log: () => {} })).rejects.toThrow("split already");
});

// A module's bytes: the header, a type section, and a target_features section (entries are [prefix, name]) in the middle, as
// the toolchain writes it, or none.
function moduleWith(features, tail = [0x03, 0x02, 0x01, 0x00]) {
  const leb = (value) => (value < 0x80 ? [value] : [(value & 0x7f) | 0x80, ...leb(value >> 7)]);
  const text = (name) => [name.length, ...new TextEncoder().encode(name)];
  const payload = features === null ? null : [...text("target_features"), features.length, ...features.flatMap(([prefix, name]) => [prefix.charCodeAt(0), ...text(name)])];
  return Uint8Array.from([0, 0x61, 0x73, 0x6d, 1, 0, 0, 0, 0x01, 0x04, 0x01, 0x60, 0x00, 0x00, ...(payload ? [0, ...leb(payload.length), ...payload] : []), ...tail]);
}
const TOOLCHAIN = ["mutable-globals", "nontrapping-fptoint", "reference-types", "bulk-memory", "sign-ext", "multivalue", "bulk-memory-opt", "call-indirect-overlong"];

test("the target_features section is read with its position and the features it enables", () => {
  const bytes = moduleWith(TOOLCHAIN.map((name) => ["+", name]));
  const section = readTargetFeatures(bytes);
  expect(section.features).toEqual(TOOLCHAIN);
  expect(bytes[section.start]).toBe(0);
  expect(section.end).toBe(bytes.length - 4);
  expect(readTargetFeatures(moduleWith([["+", "simd128"], ["-", "atomics"]])).features).toEqual(["simd128"]);
  expect(readTargetFeatures(moduleWith(null))).toBeNull();
  expect(readTargetFeatures(new TextEncoder().encode("module bytes"))).toBeNull();
  expect(readTargetFeatures(bytes.subarray(0, bytes.length - 20))).toBeNull();
});

test("removing the section leaves every other byte as it was", () => {
  const bytes = moduleWith(TOOLCHAIN.map((name) => ["+", name]));
  expect(Array.from(withoutTargetFeatures(bytes))).toEqual(Array.from(moduleWith(null)));
  const bare = moduleWith(null);
  expect(withoutTargetFeatures(bare)).toBe(bare);
  const text = new TextEncoder().encode("not a module");
  expect(withoutTargetFeatures(text)).toBe(text);
});

test("the toolchain's features give the flags of a split in the module's own table", () => {
  const plan = planLayout(moduleWith(TOOLCHAIN.map((name) => ["+", name])));
  expect(plan.flags).toEqual(["--mvp-features", "--enable-mutable-globals", "--enable-nontrapping-float-to-int", "--enable-bulk-memory",
    "--enable-sign-ext", "--enable-multivalue", "--enable-bulk-memory-opt", "--enable-call-indirect-overlong"]);
  expect(plan.flags).not.toContain("--enable-reference-types");
});

test("a module keeps the two-table layout when a feature has no flag or reference types are not listed", () => {
  expect(planLayout(moduleWith([["+", "reference-types"], ["+", "shared-everything"]])).reason).toContain("shared-everything");
  expect(planLayout(moduleWith([["+", "sign-ext"]])).reason).toContain("reference types");
  expect(planLayout(moduleWith(null)).reason).toContain("no target_features");
  expect(planLayout(new TextEncoder().encode("not a module")).reason).toBeTruthy();
  for (const flag of Object.values(FEATURE_FLAGS)) expect(flag).toMatch(/^--enable-[a-z0-9-]+$/);
});

test("the layout is part of the cache key", () => {
  const withFeatures = (features) => bundle({ "app.wasm": moduleWith(features.map((name) => ["+", name])) });
  const key = (directory) => cacheKey(directory, { route: "/", viewports: VIEWPORTS });
  expect(key(withFeatures(["reference-types", "sign-ext"]))).not.toBe(key(withFeatures(["reference-types", "shared-everything"])));
});

const hasBinaryen = ["wasm-as", "wasm-opt"].every((tool) => !spawnSync(tool, ["--version"]).error);

test.skipIf(!hasBinaryen)("a module takes the placeholders into its own table unless it needs reference types or writes that table", () => {
  const directory = mkdtempSync(join(tmpdir(), "wasm-split-validate-test-"));
  const assemble = (name, wat) => {
    writeFileSync(join(directory, `${name}.wat`), wat);
    const plain = join(directory, `${name}-plain.wasm`), tagged = join(directory, `${name}.wasm`);
    expect(spawnSync("wasm-as", [join(directory, `${name}.wat`), "--enable-reference-types", "--enable-bulk-memory", "-o", plain]).status).toBe(0);
    expect(spawnSync("wasm-opt", [plain, "--enable-reference-types", "--enable-bulk-memory", "--emit-target-features", "-o", tagged]).status).toBe(0);
    return tagged;
  };
  const table = `(memory 1) (table 4 funcref) (elem $e (i32.const 0) $a $a) (func $a (result i32) (i32.const 1)) (func (export "b") (result i32) (call_indirect (result i32) (i32.const 0)))`;
  const cases = [
    // A table that is only read: the layout applies.
    ["table", `(module ${table})`, null],
    ["needs", `(module (func (export "f") (param externref) (result externref) (local.get 0)))`, "does not validate without reference types"],
    // `table.copy` and `table.init` validate with bulk memory alone, and either could replace a placeholder's slot.
    ["copies", `(module ${table} (func (export "move") (table.copy (i32.const 2) (i32.const 0) (i32.const 1))))`, "writes its function table (table.copy)"],
    ["inits", `(module ${table} (func (export "fill") (table.init $e (i32.const 2) (i32.const 0) (i32.const 0))))`, "writes its function table (table.init)"],
  ];
  for (const [name, wat, refusal] of cases) {
    const bytes = new Uint8Array(readFileSync(assemble(name, wat)));
    const plan = planLayout(bytes);
    expect(plan.flags).toBeTruthy();
    const stripped = join(directory, `${name}-stripped.wasm`);
    writeFileSync(stripped, withoutTargetFeatures(bytes));
    const why = whyNotOwnTable(stripped, plan.flags);
    if (refusal === null) expect(why).toBeNull();
    else expect(why).toContain(refusal);
  }
  rmSync(directory, { recursive: true, force: true });
});

test("the cache key follows what the link map says about the data, not the paths of the build that wrote it", () => {
  const map = (directory, size) => `    Addr      Off     Size Out     In      Symbol
       -   275cf4    25c0e DATA
    1000   275cf5    185b0 .rodata
    1000   275cfd ${size}         ${directory}/Site.o:(.rodata..L.str.4.name)
    1000   275cfd ${size}                 .L.str.4.name
`;
  const keyOf = (text) => {
    const file = join(mkdtempSync(join(tmpdir(), "wasm-split-map-test-")), "app.map");
    writeFileSync(file, text);
    return cacheKey(bundle(), { route: "/", viewports: VIEWPORTS, linkMap: file });
  };
  const key = keyOf(map("/work/.embedded-browser.AAAAAA/scratch", "      14"));
  expect(keyOf(map("/work/.embedded-browser.BBBBBB/scratch", "      14"))).toBe(key);
  expect(keyOf(map("/work/.embedded-browser.AAAAAA/scratch", "      18"))).not.toBe(key);
  expect(cacheKey(bundle(), { route: "/", viewports: VIEWPORTS })).not.toBe(key);
});

test("the check of a data move notes an access that touches a moved range, wherever the access starts and ends", () => {
  // The hook wraps WebAssembly.instantiate; run it against a stand-in that hands back the imports it adds.
  const marks = [];
  class Module {}
  Module.imports = () => [{ module: "env", name: "load_ptr" }];
  let added = null;
  const stand = { Module, instantiate: (module, imports) => { added = imports; } };
  const scope = {};
  new Function("WebAssembly", "performance", "globalThis", dataHook([[4096, 4100], [8192, 8200]]))(stand, { getEntriesByName: () => marks }, scope);
  stand.instantiate(new Module(), {});
  const { load_ptr: read, store_ptr: write } = added.env;
  // An eight-byte access from 4094 covers the four moved bytes although neither of its ends is inside them.
  expect(read(1, 8, 0, 4094)).toBe(4094);
  expect(write(2, 4, 1, 8195)).toBe(8195);
  expect(scope.__swiftuiwebDataReads).toEqual(["read 4094", "write 8196"]);
  // Next to a range, not inside it; and after the second module is instantiated, anything goes.
  read(3, 4, 0, 4100); read(4, 2, 0, 4094); read(5, 4, 0, 8200); read(6, 4, 0, 8188);
  expect(scope.__swiftuiwebDataReads.length).toBe(2);
  marks.push({});
  read(7, 4, 0, 4096);
  expect(scope.__swiftuiwebDataReads.length).toBe(2);
});

test("the module is instrumented after its bulk copies and fills became loops the instrumentation can see", () => {
  expect(instrumentation(["--mvp-features", "--enable-bulk-memory"])).toEqual(["--mvp-features", "--enable-bulk-memory", "--llvm-memory-copy-fill-lowering", "--instrument-memory"]);
});
