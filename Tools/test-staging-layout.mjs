// Run: bun test ./Tools/test-staging-layout.mjs
// Covers staging-layout.mjs: relative-framework (os.path.relpath of realpaths) and layout (the levelN/swiftuiweb prefix,
// PurePosixPath component handling, and the absolute-path error).
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { layout, relativeFramework } from "./staging-layout.mjs";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "staging-layout.mjs");
const run = (args) => spawnSync(process.execPath, [SCRIPT, ...args], { encoding: "utf8" });

test("layout places the consumer by the number of levels the relative path goes up", () => {
  assert.deepEqual(layout("/s", "../swiftuiweb"), ["/s/level0/consumer", "/s/level0/swiftuiweb"]);
  assert.deepEqual(layout("/s", "../../swiftuiweb"), ["/s/level0/level1/consumer", "/s/level0/swiftuiweb"]);
  assert.deepEqual(layout("/s", "../../../x"), ["/s/level0/level1/level2/consumer", "/s/level0/x"]);
});

test("a relative path that ends in .. starts with a swiftuiweb directory", () => {
  assert.deepEqual(layout("/s", "../.."), ["/s/swiftuiweb/level0/consumer", "/s/swiftuiweb"]);
});

test("empty and . components are dropped, repeated slashes collapse, trailing slashes do not matter", () => {
  assert.deepEqual(layout("/s", "./a//../../swiftuiweb/"), layout("/s", "a/../../swiftuiweb"));
  assert.deepEqual(layout("/s", "."), ["/s/consumer", "/s/consumer"]);
  assert.deepEqual(layout("/s/", "../x"), layout("/s", "../x"));
});

test("an absolute dependency path is refused with the launcher's message and exit status 1", () => {
  const result = run(["layout", "/s", "/abs/dep"]);
  assert.equal(result.status, 1);
  assert.equal(result.stdout, "");
  assert.equal(
    result.stderr,
    "absolute path dependencies cannot be staged; use a relative path to the SwiftUIWeb checkout or set SWIFTUIWEB_LOWER_IN_PLACE=1\n",
  );
});

test("relative-framework prints the relative path between the two real directories", () => {
  const base = mkdtempSync(join(tmpdir(), "swui-layout-"));
  try {
    mkdirSync(join(base, "fw/swiftuiweb"), { recursive: true });
    mkdirSync(join(base, "app/Examples/Consumer"), { recursive: true });
    symlinkSync(join(base, "app"), join(base, "app-link"), "dir");
    assert.equal(relativeFramework(join(base, "fw/swiftuiweb"), join(base, "app/Examples/Consumer")), "../../../fw/swiftuiweb");
    assert.equal(relativeFramework(join(base, "fw/swiftuiweb"), join(base, "app-link/Examples/Consumer")), "../../../fw/swiftuiweb");
    assert.equal(relativeFramework(join(base, "app"), join(base, "app")), ".");
    const result = run(["relative-framework", join(base, "fw/swiftuiweb"), join(base, "app/Examples/Consumer")]);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, "../../../fw/swiftuiweb\n");
    assert.equal(realpathSync(join(base, "app-link")), realpathSync(join(base, "app")));
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
});

test("wrong operand counts fail with exit status 1", () => {
  assert.equal(run(["layout", "only-one"]).status, 1);
  assert.equal(run(["relative-framework", "one", "two", "three"]).status, 1);
});
