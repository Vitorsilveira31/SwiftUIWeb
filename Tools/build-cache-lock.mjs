#!/usr/bin/env bun
// One build at a time in a build cache folder (the lowered tree and SwiftPM's scratch folder that live between runs).
//
//   bun Tools/build-cache-lock.mjs acquire <cache> --pid <pid> [--timeout <seconds>]
//   bun Tools/build-cache-lock.mjs release <cache> --pid <pid>
//
// Tools/run-browser-embedded.sh keeps the lowered tree and the scratch folder of a build in one folder per product,
// configuration and profile, so the next build recompiles only what changed. Two builds writing that folder at once would
// mix their trees, so the launcher takes this lock before it writes there and releases it when it exits. The lock is a
// directory (`<cache>/lock`, created atomically) holding the owner's process id and start time: a lock whose process has
// exited, or whose process id now belongs to another process, is stale and taken over. A waiting build says which process
// it waits for, then once a minute; after the timeout (SWIFTUIWEB_BUILD_CACHE_LOCK_TIMEOUT, 3600 s by default) it fails.
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const OWNER = "owner.json";
// A lock directory without an owner file is one whose creator has not written it yet, or died between the two steps.
const ORPHAN_SECONDS = 30;

/** The start time `ps` reports for <pid>, or "" when no such process exists. */
export function processStart(pid) {
  const result = spawnSync("ps", ["-o", "lstart=", "-p", String(pid)], { encoding: "utf8" });
  return result.status === 0 ? result.stdout.trim() : "";
}

function readOwner(lock) {
  try {
    return JSON.parse(readFileSync(join(lock, OWNER), "utf8"));
  } catch {
    return null;
  }
}

/** Whether the lock at <lock> belongs to no live process. */
export function isStale(lock, now = Date.now()) {
  const owner = readOwner(lock);
  if (owner === null) {
    try {
      return (now - statSync(lock).mtimeMs) / 1000 > ORPHAN_SECONDS;
    } catch {
      return true;
    }
  }
  const started = processStart(owner.pid);
  return started === "" || started !== owner.started;
}

/** Takes the lock of <cache> for <pid> once; returns null when taken, or the owner that holds it. */
export function tryAcquire(cache, pid) {
  const lock = join(cache, "lock");
  mkdirSync(cache, { recursive: true });
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      mkdirSync(lock);
      writeFileSync(join(lock, OWNER), JSON.stringify({ pid, started: processStart(pid) }));
      return null;
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      if (!isStale(lock)) return readOwner(lock) ?? { pid: "unknown" };
      rmSync(lock, { recursive: true, force: true });
    }
  }
  return readOwner(lock) ?? { pid: "unknown" };
}

/** Removes the lock of <cache> when <pid> holds it; a lock another process took over is left alone. */
export function release(cache, pid) {
  const lock = join(cache, "lock");
  const owner = readOwner(lock);
  if (owner !== null && owner.pid === pid) rmSync(lock, { recursive: true, force: true });
}

async function acquire(cache, pid, timeoutSeconds) {
  const started = Date.now();
  let lastNotice = 0;
  for (;;) {
    const holder = tryAcquire(cache, pid);
    if (holder === null) return 0;
    const waited = (Date.now() - started) / 1000;
    if (waited >= timeoutSeconds) {
      console.error(`error: the build cache ${cache} is still in use by process ${holder.pid} after ${timeoutSeconds} s.`);
      console.error("       Wait for that build to finish, or set SWIFTUIWEB_STABLE_WORKSPACE=0 to build in a temporary folder.");
      return 75;
    }
    if (lastNotice === 0 || Date.now() - lastNotice >= 60_000) {
      console.error(`Waiting for process ${holder.pid}, which is building in ${cache}.`);
      lastNotice = Date.now();
    }
    await Bun.sleep(500);
  }
}

if (import.meta.main) {
  const [command, cache, ...rest] = process.argv.slice(2);
  const option = (name) => {
    const index = rest.indexOf(name);
    return index === -1 ? undefined : rest[index + 1];
  };
  const pid = Number(option("--pid"));
  if (!["acquire", "release"].includes(command) || !cache || !Number.isInteger(pid) || pid <= 0) {
    console.error("usage: bun Tools/build-cache-lock.mjs acquire|release <cache> --pid <pid> [--timeout <seconds>]");
    process.exit(2);
  }
  if (command === "release") {
    release(cache, pid);
  } else {
    const timeout = Number(option("--timeout") ?? process.env.SWIFTUIWEB_BUILD_CACHE_LOCK_TIMEOUT ?? 3600);
    process.exit(await acquire(cache, pid, timeout));
  }
}
