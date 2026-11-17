// Tests Tools/wasm-split-release.mjs without a browser: the cache key, the cache hit that runs no browser, --check on a
// machine without wasm-split, and --fallback, which leaves an unsplit bundle as it was and exits 3 so the launcher builds the
// runtime scripts again without the split loader. The split itself runs in Tools/test-wasm-split-browser.mjs.
// Run with: bun test ./Tools/test-wasm-split-release.mjs
import { expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { cacheKey, FELL_BACK, splitBundle } from "./wasm-split-release.mjs";

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
