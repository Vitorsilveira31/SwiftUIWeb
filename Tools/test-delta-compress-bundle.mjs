#!/usr/bin/env bun
// Tests for Tools/delta-compress-bundle.mjs. Run: bun test ./Tools/test-delta-compress-bundle.mjs
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { brotliCompressSync } from "node:zlib";
import {
  assertDictionarySupport, decodeDifference, deltaCompressBundle, describe as describeDecision, differenceFor, KEEP_AT_MOST, listModules, main, parseArguments,
} from "./delta-compress-bundle.mjs";
import { differenceName, isHashHex, readDcbHeader, sha256Hex } from "./dictionary-transport.mjs";

// Bytes with some structure (so Brotli finds matches) that differ a little between versions.
function make(seed, length = 64 * 1024) {
  const bytes = Buffer.alloc(length);
  let state = seed;
  for (let index = 0; index < length; index++) {
    state = (state * 1103515245 + 12345) >>> 0;
    bytes[index] = index % 5 === 0 ? state >>> 24 : (index * 7) % 241;
  }
  return bytes;
}
const changed = (bytes, from = 3000, count = 80) => {
  const copy = Buffer.from(bytes);
  for (let index = from; index < from + count; index++) copy[index] ^= 0xa5;
  return copy;
};

function scratch(files) {
  const root = mkdtempSync(join(tmpdir(), "delta-compress-"));
  for (const [name, bytes] of Object.entries(files)) {
    mkdirSync(dirname(join(root, name)), { recursive: true });
    writeFileSync(join(root, name), bytes);
  }
  return root;
}

const dcbFiles = (root) => readdirSync(root, { recursive: true }).filter((name) => name.endsWith(".dcb")).sort();

async function capture(run) {
  const lines = [];
  const log = console.log;
  const error = console.error;
  console.log = (...parts) => lines.push(parts.join(" "));
  console.error = (...parts) => lines.push(parts.join(" "));
  try {
    return { status: await run(), lines };
  } finally {
    console.log = log;
    console.error = error;
  }
}

const hasCliDictionary = (() => {
  const probe = spawnSync("brotli", ["--help"], { encoding: "utf8" });
  return probe.status === 0 && /--dictionary/.test(`${probe.stdout}${probe.stderr}`);
})();

describe("delta-compress-bundle", () => {
  test("this runtime's Brotli takes a dictionary", () => {
    assertDictionarySupport();
  });

  test("writes <module>.<previous hash>.dcb that decodes to the module with the previous module as the dictionary", async () => {
    const previous = make(1);
    const current = changed(previous);
    const bundle = scratch({ "app.22222222.wasm": current, "index.html": "<!doctype html>" });
    const earlier = scratch({ "app.11111111.wasm": previous });
    try {
      const { decisions, previous: found, removed } = await deltaCompressBundle(bundle, [earlier]);
      const hash = await sha256Hex(previous);
      assert.equal(found, 1);
      assert.deepEqual(removed, []);
      assert.equal(decisions.length, 1);
      assert.equal(decisions[0].kept, true);
      assert.equal(decisions[0].hash, hash);
      assert.deepEqual(dcbFiles(bundle), [differenceName("app.22222222.wasm", hash)]);

      const body = readFileSync(join(bundle, differenceName("app.22222222.wasm", hash)));
      assert.equal(readDcbHeader(body), hash);
      assert.deepEqual([...body.subarray(0, 4)], [0xff, 0x44, 0x43, 0x42]);
      assert.deepEqual(decodeDifference(body, previous, hash), current);
      assert.equal(body.length, decisions[0].bytes);
      assert.ok(body.length < current.length / 10);
      assert.throws(() => decodeDifference(body, previous, "0".repeat(64)));
      assert.throws(() => decodeDifference(body.subarray(0, 20), previous, hash));
    } finally {
      rmSync(bundle, { recursive: true, force: true });
      rmSync(earlier, { recursive: true, force: true });
    }
  });

  test("the file decodes with the brotli program too", { skip: hasCliDictionary ? false : "brotli with --dictionary is not installed" }, async () => {
    const previous = make(4);
    const current = changed(previous, 9000, 200);
    const bundle = scratch({ "app.22222222.wasm": current });
    const earlier = scratch({ "app.11111111.wasm": previous });
    try {
      await deltaCompressBundle(bundle, [earlier]);
      const [name] = dcbFiles(bundle);
      const stream = join(earlier, "stream.br");
      writeFileSync(stream, readFileSync(join(bundle, name)).subarray(36));
      const decoded = spawnSync("brotli", ["-d", "-D", join(earlier, "app.11111111.wasm"), "-c", stream], { maxBuffer: 1 << 28 });
      assert.equal(decoded.status, 0, String(decoded.stderr));
      assert.deepEqual(decoded.stdout, current);
    } finally {
      rmSync(bundle, { recursive: true, force: true });
      rmSync(earlier, { recursive: true, force: true });
    }
  });

  test("keeps a file only when it is at least 10 % smaller than the .br copy", async () => {
    const previous = make(5);
    const current = changed(previous);
    const { body } = await differenceFor(current, previous);
    assert.equal(KEEP_AT_MOST, 0.9);
    for (const [reference, kept] of [[Math.ceil(body.length / 0.9), true], [Math.ceil(body.length / 0.9) - 1, false]]) {
      const bundle = scratch({ "app.22222222.wasm": current, "app.22222222.wasm.br": Buffer.alloc(reference, 1) });
      const earlier = scratch({ "app.11111111.wasm": previous });
      try {
        const { decisions } = await deltaCompressBundle(bundle, [earlier]);
        assert.equal(decisions[0].reference, reference, "the reference is the .br copy's size");
        assert.equal(decisions[0].kept, kept, `reference ${reference}`);
        assert.equal(dcbFiles(bundle).length, kept ? 1 : 0);
        assert.match(describeDecision(decisions[0]), kept ? /, kept$/ : /, dropped: less than 10 % smaller than the \.br copy$/);
      } finally {
        rmSync(bundle, { recursive: true, force: true });
        rmSync(earlier, { recursive: true, force: true });
      }
    }
  });

  test("without a .br copy the reference is Brotli quality 11 of the module", async () => {
    const previous = make(6);
    const unrelated = randomBytes(40 * 1024);
    const bundle = scratch({ "app.22222222.wasm": unrelated });
    const earlier = scratch({ "app.11111111.wasm": previous });
    try {
      const { decisions } = await deltaCompressBundle(bundle, [earlier]);
      assert.equal(decisions.length, 1);
      assert.equal(decisions[0].kept, false);
      assert.ok(decisions[0].reference >= brotliCompressSync(unrelated).length - 64, "about the size of the module, which does not compress");
      assert.match(describeDecision(decisions[0]), /dropped: less than 10 % smaller than the Brotli copy/);
      assert.deepEqual(dcbFiles(bundle), []);
    } finally {
      rmSync(bundle, { recursive: true, force: true });
      rmSync(earlier, { recursive: true, force: true });
    }
  });

  test("removes the difference files an earlier run left, and only those", async () => {
    const previous = make(7);
    const current = changed(previous);
    const staleName = differenceName("app.22222222.wasm", "c".repeat(64));
    const bundle = scratch({
      "app.22222222.wasm": current, [staleName]: "old", [`sub/${differenceName("x.aaaaaaaa.wasm", "d".repeat(64))}`]: "old",
      "app.22222222.wasm.gz": "gz", "notes.dcb": "keep", "app.wasm.dcb": "keep",
    });
    const earlier = scratch({ "app.11111111.wasm": previous });
    try {
      const { removed } = await deltaCompressBundle(bundle, [earlier]);
      assert.deepEqual(removed.sort(), [staleName, `sub/${differenceName("x.aaaaaaaa.wasm", "d".repeat(64))}`].sort());
      assert.ok(!existsSync(join(bundle, staleName)));
      assert.ok(existsSync(join(bundle, "notes.dcb")) && existsSync(join(bundle, "app.wasm.dcb")) && existsSync(join(bundle, "app.22222222.wasm.gz")));
      assert.equal(dcbFiles(bundle).filter((name) => isHashHex(name.slice(-68, -4))).length, 1);
    } finally {
      rmSync(bundle, { recursive: true, force: true });
      rmSync(earlier, { recursive: true, force: true });
    }
  });

  test("a run with nothing earlier says so, exits 0, and still clears the stale files", async () => {
    const staleName = differenceName("app.22222222.wasm", "c".repeat(64));
    const bundle = scratch({ "app.22222222.wasm": make(8), [staleName]: "old" });
    const empty = scratch({ "readme.txt": "no modules here", "app.wasm": make(9), "app.11111111.wasm.br": "x" });
    try {
      const result = await capture(() => main(["--bundle", bundle, "--previous", empty, "--previous", join(empty, "missing")]));
      assert.equal(result.status, 0);
      assert.ok(result.lines.some((line) => line.includes("missing does not exist")), result.lines.join("\n"));
      assert.ok(result.lines.some((line) => /no earlier module found/.test(line)), result.lines.join("\n"));
      assert.deepEqual(dcbFiles(bundle), []);
    } finally {
      rmSync(bundle, { recursive: true, force: true });
      rmSync(empty, { recursive: true, force: true });
    }
  });

  test("pairs a module with earlier modules of its own stem and directory, skips identical bytes, and handles several earlier versions", async () => {
    const first = make(10);
    const second = changed(first, 100, 50);
    const current = changed(second, 8000, 60);
    const rest = make(11);
    const bundle = scratch({ "app.33333333.wasm": current, "app-rest.33333333.wasm": changed(rest), "lib/app.33333333.wasm": current });
    const one = scratch({ "app.11111111.wasm": first, "app-rest.11111111.wasm": rest });
    // `first` is in both directories and counts once; `current` as an earlier module has the module's own bytes; a module in
    // another directory is not paired with the root's.
    const two = scratch({ "app.22222222.wasm": second, "app.11111111.wasm": first, "app.99999999.wasm": current, "old/app.55555555.wasm": second });
    try {
      const { decisions, previous } = await deltaCompressBundle(bundle, [one, two]);
      const names = decisions.map((decision) => `${decision.module} <- ${decision.from}`).sort();
      assert.equal(previous, 5);
      assert.deepEqual(names, [
        "app-rest.33333333.wasm <- app-rest.11111111.wasm",
        "app.33333333.wasm <- app.11111111.wasm",
        "app.33333333.wasm <- app.22222222.wasm",
      ]);
      assert.equal(dcbFiles(bundle).length, 3);
      for (const decision of decisions) assert.equal(decision.kept, true);
    } finally {
      rmSync(bundle, { recursive: true, force: true });
      rmSync(one, { recursive: true, force: true });
      rmSync(two, { recursive: true, force: true });
    }
  });

  test("an earlier bundle works as it is: its .br, .gz and .dcb files and other files are not modules", async () => {
    const previous = make(12);
    const current = changed(previous);
    const bundle = scratch({ "app.22222222.wasm": current });
    const earlier = scratch({
      "app.11111111.wasm": previous, "app.11111111.wasm.br": "x", "app.11111111.wasm.gz": "x", [differenceName("app.11111111.wasm", "e".repeat(64))]: "x", "index.html": "x",
    });
    try {
      assert.deepEqual(listModules(earlier), ["app.11111111.wasm"]);
      const { previous: found, decisions } = await deltaCompressBundle(bundle, [earlier]);
      assert.equal(found, 1);
      assert.equal(decisions.length, 1);
    } finally {
      rmSync(bundle, { recursive: true, force: true });
      rmSync(earlier, { recursive: true, force: true });
    }
  });

  test("main prints one line per decision and reads its arguments strictly", async () => {
    const previous = make(13);
    const bundle = scratch({ "app.22222222.wasm": changed(previous), "app-rest.22222222.wasm": randomBytes(30000) });
    const earlier = scratch({ "app.11111111.wasm": previous, "app-rest.11111111.wasm": randomBytes(30000) });
    try {
      const result = await capture(() => main(["--bundle", bundle, "--previous", earlier]));
      assert.equal(result.status, 0);
      assert.equal(result.lines.length, 2, result.lines.join("\n"));
      assert.match(result.lines.find((line) => line.startsWith("app.22222222.wasm")), /^app\.22222222\.wasm: difference from app\.11111111\.wasm \([0-9a-f]{12}\): \d+ bytes against \d+ \(\d+ %\), kept$/);
      assert.match(result.lines.find((line) => line.startsWith("app-rest.")), /, dropped: less than 10 % smaller than the Brotli copy$/);
      assert.equal((await capture(() => main([]))).status, 2);
      assert.equal((await capture(() => main(["--bundle", bundle]))).status, 2);
      assert.equal((await capture(() => main(["--previous", earlier]))).status, 2);
      assert.equal((await capture(() => main(["--bundle", bundle, "--previous"]))).status, 2);
      assert.equal((await capture(() => main(["--bundle", bundle, "--bogus", "x", "--previous", earlier]))).status, 2);
      assert.equal((await capture(() => main(["--bundle", join(bundle, "nope"), "--previous", earlier]))).status, 1);
      assert.deepEqual(parseArguments(["--bundle", "a", "--previous", "b", "--previous", "c"]), { bundle: "a", previous: ["b", "c"] });
    } finally {
      rmSync(bundle, { recursive: true, force: true });
      rmSync(earlier, { recursive: true, force: true });
    }
  });

  test("running twice gives the same files", async () => {
    const previous = make(14);
    const bundle = scratch({ "app.22222222.wasm": changed(previous) });
    const earlier = scratch({ "app.11111111.wasm": previous });
    try {
      await deltaCompressBundle(bundle, [earlier]);
      const [name] = dcbFiles(bundle);
      const before = readFileSync(join(bundle, name));
      const again = await deltaCompressBundle(bundle, [earlier]);
      assert.deepEqual(again.removed, [name]);
      assert.deepEqual(readFileSync(join(bundle, name)), before);
      assert.equal(statSync(join(bundle, name)).size, before.length);
    } finally {
      rmSync(bundle, { recursive: true, force: true });
      rmSync(earlier, { recursive: true, force: true });
    }
  });
});
