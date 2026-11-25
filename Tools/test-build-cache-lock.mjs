// Run: bun test ./Tools/test-build-cache-lock.mjs
// Tools/build-cache-lock.mjs: one build at a time in a build cache folder; a lock whose process is gone, or whose process id
// now names another process, is taken over; a release by a process that does not hold the lock changes nothing.
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { isStale, release, tryAcquire } from "./build-cache-lock.mjs";

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), "build-cache-lock.mjs");

async function withCache(body) {
  const cache = mkdtempSync(join(tmpdir(), "build-cache-lock-"));
  try {
    return await body(cache);
  } finally {
    rmSync(cache, { recursive: true, force: true });
  }
}

test("a free cache is taken, and a second live process is told who holds it", () =>
  withCache((cache) => {
    assert.equal(tryAcquire(cache, process.pid), null);
    const sleeper = spawn("sleep", ["30"]);
    try {
      assert.equal(tryAcquire(cache, sleeper.pid).pid, process.pid);
    } finally {
      sleeper.kill();
    }
    release(cache, process.pid);
    assert.equal(existsSync(join(cache, "lock")), false);
  }));

test("a lock whose process exited is taken over", () =>
  withCache((cache) => {
    const exited = spawnSync("true").pid;
    mkdirSync(join(cache, "lock"));
    writeFileSync(join(cache, "lock", "owner.json"), JSON.stringify({ pid: exited, started: "gone" }));
    assert.equal(tryAcquire(cache, process.pid), null);
    assert.equal(JSON.parse(readFileSync(join(cache, "lock", "owner.json"), "utf8")).pid, process.pid);
  }));

test("a reused process id is not the owner: the start time must match too", () =>
  withCache((cache) => {
    mkdirSync(join(cache, "lock"));
    writeFileSync(join(cache, "lock", "owner.json"), JSON.stringify({ pid: process.pid, started: "Thu Jan  1 00:00:00 1970" }));
    assert.equal(isStale(join(cache, "lock")), true);
  }));

test("a lock directory without an owner is stale only after a grace period", () =>
  withCache((cache) => {
    const lock = join(cache, "lock");
    mkdirSync(lock);
    assert.equal(isStale(lock), false);
    const old = new Date(Date.now() - 120_000);
    utimesSync(lock, old, old);
    assert.equal(isStale(lock), true);
  }));

test("a release by a process that does not hold the lock leaves it", () =>
  withCache((cache) => {
    assert.equal(tryAcquire(cache, process.pid), null);
    release(cache, process.pid + 1);
    assert.equal(existsSync(join(cache, "lock")), true);
  }));

test("the command waits for the holder and fails after the timeout", () =>
  withCache((cache) => {
    assert.equal(tryAcquire(cache, process.pid), null);
    const sleeper = spawn("sleep", ["30"]);
    try {
      const result = spawnSync("bun", [SCRIPT, "acquire", cache, "--pid", String(sleeper.pid), "--timeout", "1"], { encoding: "utf8" });
      assert.equal(result.status, 75);
      assert.match(result.stderr, new RegExp(`Waiting for process ${process.pid}`));
      assert.match(result.stderr, /SWIFTUIWEB_STABLE_WORKSPACE=0/);
    } finally {
      sleeper.kill();
    }
  }));

test("the command takes the lock once the holder releases it", () =>
  withCache(async (cache) => {
    assert.equal(tryAcquire(cache, process.pid), null);
    const sleeper = spawn("sleep", ["30"]);
    try {
      const waiting = spawn("bun", [SCRIPT, "acquire", cache, "--pid", String(sleeper.pid), "--timeout", "20"]);
      const done = new Promise((resolve) => waiting.on("exit", resolve));
      setTimeout(() => release(cache, process.pid), 800);
      assert.equal(await done, 0);
      assert.equal(JSON.parse(readFileSync(join(cache, "lock", "owner.json"), "utf8")).pid, sleeper.pid);
    } finally {
      sleeper.kill();
    }
  }));
