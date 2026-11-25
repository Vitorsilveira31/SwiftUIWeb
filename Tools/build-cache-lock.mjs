#!/usr/bin/env bun
// One build at a time in a build cache folder (the lowered tree and SwiftPM's scratch folder that live between runs).
//
//   exec 9>>"<cache>/lock"
//   bun Tools/build-cache-lock.mjs acquire <cache> --fd 9 --pid <pid> [--timeout <seconds>]
//   ... build ...
//   exec 9>&-                     (or the shell exits)
//
// Tools/run-browser-embedded.sh keeps the lowered tree and the scratch folder of a build in one folder per product,
// configuration and profile, so the next build recompiles only what changed. Two builds writing that folder at once would
// mix their trees, so the launcher opens `<cache>/lock` on a descriptor of its own and this tool takes an exclusive
// `flock` on it. The lock belongs to the open file, which the launcher keeps: it lasts after this tool exits and ends when
// the launcher closes the descriptor or exits, however it exits, so there is never a stale lock to clean up. The holder
// writes its process id into the file, so a waiting build says which process it waits for, then once a minute; after the
// timeout (SWIFTUIWEB_BUILD_CACHE_LOCK_TIMEOUT, 3600 s by default) it fails.
import { dlopen, FFIType } from "bun:ffi";
import { fstatSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const LOCK_EX = 2;
const LOCK_NB = 4;

const libc = dlopen(process.platform === "darwin" ? "libSystem.B.dylib" : "libc.so.6", {
  flock: { args: [FFIType.i32, FFIType.i32], returns: FFIType.i32 },
});

/** Takes the exclusive lock on <fd> without waiting; true when this descriptor holds it now. */
export function tryLock(fd) {
  return libc.symbols.flock(fd, LOCK_EX | LOCK_NB) === 0;
}

function holder(cache) {
  try {
    return readFileSync(join(cache, "lock"), "utf8").trim() || "unknown";
  } catch {
    return "unknown";
  }
}

export async function acquire(cache, fd, pid, timeoutSeconds, log = (line) => console.error(line)) {
  // A descriptor that is not open would make every attempt fail, which reads as a lock someone holds.
  fstatSync(fd);
  const started = Date.now();
  let lastNotice = 0;
  while (!tryLock(fd)) {
    if ((Date.now() - started) / 1000 >= timeoutSeconds) {
      log(`error: the build cache ${cache} is still in use by process ${holder(cache)} after ${timeoutSeconds} s.`);
      log("       Wait for that build to finish, or set SWIFTUIWEB_STABLE_WORKSPACE=0 to build in a temporary folder.");
      return 75;
    }
    if (lastNotice === 0 || Date.now() - lastNotice >= 60_000) {
      log(`Waiting for process ${holder(cache)}, which is building in ${cache}.`);
      lastNotice = Date.now();
    }
    await Bun.sleep(250);
  }
  writeFileSync(join(cache, "lock"), `${pid}\n`);
  return 0;
}

if (import.meta.main) {
  const [command, cache, ...rest] = process.argv.slice(2);
  const option = (name) => {
    const index = rest.indexOf(name);
    return index === -1 ? undefined : rest[index + 1];
  };
  const fd = Number(option("--fd"));
  const pid = Number(option("--pid"));
  if (command !== "acquire" || !cache || !Number.isInteger(fd) || fd < 3 || !Number.isInteger(pid) || pid <= 0) {
    console.error("usage: bun Tools/build-cache-lock.mjs acquire <cache> --fd <descriptor> --pid <pid> [--timeout <seconds>]");
    process.exit(2);
  }
  const timeoutText = option("--timeout") ?? (process.env.SWIFTUIWEB_BUILD_CACHE_LOCK_TIMEOUT || "3600");
  const timeout = /^\d+(\.\d+)?$/.test(timeoutText) ? Number(timeoutText) : NaN;
  if (!Number.isFinite(timeout)) {
    console.error(`the lock timeout is a number of seconds, not "${timeoutText}" (--timeout or SWIFTUIWEB_BUILD_CACHE_LOCK_TIMEOUT)`);
    process.exit(2);
  }
  process.exit(await acquire(cache, fd, pid, timeout));
}
