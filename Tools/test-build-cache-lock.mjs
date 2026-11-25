// Run: bun test ./Tools/test-build-cache-lock.mjs
// Tools/build-cache-lock.mjs: one shell at a time holds a build cache, the lock outlives the tool and ends with the shell's
// descriptor (a killed holder frees it at once), a waiting shell names the holder and fails after its timeout, and of many
// shells that start together exactly one holds the cache at any moment.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "build-cache-lock.mjs");

async function withCache(body) {
  const cache = mkdtempSync(join(tmpdir(), "build-cache-lock-"));
  try {
    return await body(cache);
  } finally {
    rmSync(cache, { recursive: true, force: true });
  }
}

/** A shell that takes the lock the way the launcher does, then runs <after>; resolves with its exit code and output. */
function shell(cache, after, timeout = 20) {
  const script = `exec 9>>"$1/lock"; bun "$2" acquire "$1" --fd 9 --pid $$ --timeout ${timeout} || exit $?; ${after}`;
  const child = spawn("bash", ["-c", script, "bash", cache, SCRIPT]);
  let output = "";
  child.stdout.on("data", (chunk) => (output += chunk));
  child.stderr.on("data", (chunk) => (output += chunk));
  const exited = new Promise((resolve) => child.on("exit", (code) => resolve({ code, output })));
  return { child, exited, output: () => output };
}

const until = async (condition) => {
  for (let i = 0; i < 200 && !condition(); i += 1) await Bun.sleep(50);
  assert.ok(condition());
};

test("the lock outlives the tool, names its holder, and makes a second shell wait", { timeout: 20_000 }, () =>
  withCache(async (cache) => {
    const first = shell(cache, "echo held; sleep 2");
    await until(() => first.output().includes("held"));
    assert.equal(readFileSync(join(cache, "lock"), "utf8").trim(), String(first.child.pid));
    const started = Date.now();
    const second = shell(cache, "echo second");
    const result = await second.exited;
    assert.equal(result.code, 0);
    assert.match(result.output, new RegExp(`Waiting for process ${first.child.pid}`));
    assert.ok(Date.now() - started >= 1000, "the second shell did not wait for the first");
    assert.equal((await first.exited).code, 0);
  }));

test("a killed holder frees the cache at once", { timeout: 20_000 }, () =>
  withCache(async (cache) => {
    const first = shell(cache, "echo held; sleep 30 9>&-");
    await until(() => first.output().includes("held"));
    const second = shell(cache, "echo second");
    await until(() => second.output().includes("Waiting"));
    first.child.kill("SIGKILL");
    const result = await second.exited;
    assert.equal(result.code, 0);
    assert.match(result.output, /second/);
  }));

test("a waiting shell fails after its timeout and says how to build without the cache", { timeout: 20_000 }, () =>
  withCache(async (cache) => {
    const first = shell(cache, "echo held; sleep 30 9>&-");
    await until(() => first.output().includes("held"));
    try {
      const result = await shell(cache, "echo second", 1).exited;
      assert.equal(result.code, 75);
      assert.match(result.output, /still in use by process/);
      assert.match(result.output, /SWIFTUIWEB_STABLE_WORKSPACE=0/);
    } finally {
      first.child.kill("SIGKILL");
    }
  }));

test("of shells that start together, one holds the cache at a time", { timeout: 20_000 }, () =>
  withCache(async (cache) => {
    // Each holder marks the folder while it holds the lock; a second mark while one exists is a double hold.
    const body = `if ! mkdir "${cache}/inside" 2>/dev/null; then echo DOUBLE; exit 1; fi; sleep 0.2; rmdir "${cache}/inside"`;
    const shells = Array.from({ length: 6 }, () => shell(cache, body));
    const results = await Promise.all(shells.map((s) => s.exited));
    for (const result of results) {
      assert.equal(result.code, 0, result.output);
      assert.doesNotMatch(result.output, /DOUBLE/);
    }
  }));

test("a descriptor that is not open is an error, not a lock to wait for", { timeout: 20_000 }, () =>
  withCache(async (cache) => {
    const child = spawn("bun", [SCRIPT, "acquire", cache, "--fd", "57", "--pid", String(process.pid), "--timeout", "5"]);
    const code = await new Promise((resolve) => child.on("exit", resolve));
    assert.notEqual(code, 0);
  }));

test("a process the holder started keeps the cache while it still runs", { timeout: 20_000 }, () =>
  withCache(async (cache) => {
    // A compiler the launcher started still writes the cache after the launcher is killed: the lock waits for it too.
    const first = shell(cache, "sleep 2 & echo held; wait");
    await until(() => first.output().includes("held"));
    const started = Date.now();
    const second = shell(cache, "echo second");
    await until(() => second.output().includes("Waiting"));
    first.child.kill("SIGKILL");
    const result = await second.exited;
    assert.equal(result.code, 0);
    assert.ok(Date.now() - started >= 1500, "the cache was free while the holder's child still ran");
  }));

test("a timeout that is not a number of seconds is refused", { timeout: 20_000 }, () =>
  withCache(async (cache) => {
    for (const timeout of ["abc", "-1", "1e3"]) {
      const result = await shell(cache, "echo held", timeout).exited;
      assert.equal(result.code, 2, timeout);
      assert.match(result.output, /number of seconds/);
    }
  }));

test("a launcher waiting for the cache stops at once on SIGTERM", { timeout: 20_000 }, () =>
  withCache(async (cache) => {
    const first = shell(cache, "echo held; sleep 30 9>&-");
    await until(() => first.output().includes("held"));
    // The launcher's pattern: the tool waits in the background, so the TERM trap runs without waiting for it.
    const script = `trap 'kill -TERM $waiter 2>/dev/null; exit 143' TERM; exec 9>>"$1/lock"; bun "$2" acquire "$1" --fd 9 --pid $$ & waiter=$!; wait $waiter; echo acquired`;
    const launcher = spawn("bash", ["-c", script, "bash", cache, SCRIPT]);
    let output = "";
    launcher.stderr.on("data", (chunk) => (output += chunk));
    launcher.stdout.on("data", (chunk) => (output += chunk));
    await until(() => output.includes("Waiting"));
    const started = Date.now();
    launcher.kill("SIGTERM");
    const code = await new Promise((resolve) => launcher.on("exit", resolve));
    first.child.kill("SIGKILL");
    assert.equal(code, 143);
    assert.ok(Date.now() - started < 3000);
    assert.doesNotMatch(output, /acquired/);
  }));
