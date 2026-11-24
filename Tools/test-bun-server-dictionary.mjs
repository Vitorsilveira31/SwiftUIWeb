#!/usr/bin/env bun
// Tests for the dictionary-transport side of Tools/bun-server.ts: a content-hashed wasm module names itself as a dictionary,
// and a request that names an earlier module in Available-Dictionary and accepts dcb gets the difference file. The requests are
// read raw (node:http does not decompress), so the bytes and headers are the ones a browser would receive.
// Run: bun test ./Tools/test-bun-server-dictionary.mjs
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import http from "node:http";
import net from "node:net";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { after, before, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { brotliCompressSync } from "node:zlib";
import { decodeDifference, differenceFor } from "./delta-compress-bundle.mjs";
import { availableDictionaryValue, differenceName, readDcbHeader, sha256Hex } from "./dictionary-transport.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const OLD = "app.11111111.wasm";
const NEW = "app.22222222.wasm";
const REST = "app-rest.33333333.wasm";
const NESTED = "modules/app.44444444.wasm";
const FONT = "fonts/F.0c1d2e3f.woff2";

// Deterministic bytes that compress a little and differ a little between versions.
const make = (seed, length = 48 * 1024) => {
  const bytes = Buffer.alloc(length);
  let state = seed;
  for (let index = 0; index < length; index++) {
    state = (state * 1103515245 + 12345) >>> 0;
    bytes[index] = index % 7 === 0 ? state >>> 24 : index % 251;
  }
  return bytes;
};
const oldBytes = make(1);
const newBytes = Buffer.from(oldBytes);
for (let index = 5000; index < 5100; index++) newBytes[index] ^= 0x55;
const restBytes = make(2);
const nestedBytes = make(3);
const fontBytes = Buffer.alloc(2048, 9);

let server;
let base;
let bundle;
let outside;
let oldHash;
let difference;

function freePort() {
  return new Promise((resolvePort, reject) => {
    const probe = net.createServer();
    probe.on("error", reject);
    probe.listen(0, "127.0.0.1", () => {
      const { port } = probe.address();
      probe.close(() => resolvePort(port));
    });
  });
}

function get(path, headers = {}, method = "GET") {
  return new Promise((resolveRequest, reject) => {
    const request = http.request(new URL(path, base), { method, headers }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => resolveRequest({ status: response.statusCode, headers: response.headers, body: Buffer.concat(chunks) }));
    });
    request.on("error", reject);
    request.end();
  });
}

async function waitUntilServing() {
  const deadline = Date.now() + 15000;
  for (;;) {
    try {
      await get("/");
      return;
    } catch (error) {
      if (Date.now() > deadline) throw error;
      await new Promise((done) => setTimeout(done, 100));
    }
  }
}

const dcb = (extra = {}) => ({ "Accept-Encoding": "gzip, br, dcb, dcz", "Available-Dictionary": availableDictionaryValue(oldHash), ...extra });

before(async () => {
  bundle = mkdtempSync(join(tmpdir(), "server-dictionary-"));
  outside = mkdtempSync(join(tmpdir(), "server-dictionary-outside-"));
  const write = (name, bytes) => {
    mkdirSync(dirname(join(bundle, name)), { recursive: true });
    writeFileSync(join(bundle, name), bytes);
  };
  oldHash = await sha256Hex(oldBytes);
  difference = await differenceFor(newBytes, oldBytes);
  write(NEW, newBytes);
  write(`${NEW}.br`, brotliCompressSync(newBytes));
  write(differenceName(NEW, oldHash), difference.body);
  write(REST, restBytes);
  write(`${REST}.br`, brotliCompressSync(restBytes));
  write(NESTED, nestedBytes);
  write("app.wasm", newBytes);
  write(FONT, fontBytes);
  write("index.html", Buffer.from("<!doctype html><title>Page</title>"));
  // A difference file that is a link to a file outside the bundle must not be served.
  const linked = "a".repeat(64);
  writeFileSync(join(outside, "secret.dcb"), "secret");
  symlinkSync(join(outside, "secret.dcb"), join(bundle, differenceName(NEW, linked)));
  const port = await freePort();
  base = `http://127.0.0.1:${port}`;
  server = spawn(process.execPath, [join(ROOT, "Tools", "bun-server.ts"), bundle, String(port)], {
    env: { ...process.env, SWIFTUIWEB_API_ORIGIN: "", SWIFTUIWEB_API_PATH: "" },
    stdio: ["ignore", "ignore", "pipe"],
  });
  await waitUntilServing();
});

after(() => {
  server?.kill("SIGTERM");
  rmSync(bundle, { recursive: true, force: true });
  rmSync(outside, { recursive: true, force: true });
});

describe("bun-server dictionary transport", () => {
  test("a request that names the earlier module and accepts dcb gets the difference file", async () => {
    const response = await get(`/${NEW}`, dcb());
    assert.equal(response.status, 200);
    assert.equal(response.headers["content-encoding"], "dcb");
    assert.equal(response.headers["content-type"], "application/wasm");
    assert.equal(response.headers["cache-control"], "public, max-age=31536000, immutable");
    assert.equal(response.headers["vary"], "Accept-Encoding, Available-Dictionary");
    assert.equal(response.headers["use-as-dictionary"], 'match="/app.*.wasm"');
    assert.equal(Number(response.headers["content-length"]), response.body.length);
    assert.deepEqual(response.body, Buffer.from(difference.body));
    assert.equal(readDcbHeader(response.body), oldHash);
    assert.deepEqual(decodeDifference(response.body, oldBytes, oldHash), newBytes);
    assert.ok(response.body.length < newBytes.length / 10);
  });

  test("every response for a module carries Use-As-Dictionary and Vary, whole or compressed", async () => {
    for (const headers of [{}, { "Accept-Encoding": "br" }, { "Accept-Encoding": "identity" }, dcb()]) {
      const response = await get(`/${NEW}`, headers);
      assert.equal(response.status, 200);
      assert.equal(response.headers["use-as-dictionary"], 'match="/app.*.wasm"');
      assert.equal(response.headers["vary"], "Accept-Encoding, Available-Dictionary");
    }
    const rest = await get(`/${REST}`, { "Accept-Encoding": "br" });
    assert.equal(rest.headers["use-as-dictionary"], 'match="/app-rest.*.wasm"');
    assert.equal(rest.headers["vary"], "Accept-Encoding, Available-Dictionary");
    const nested = await get(`/${NESTED}`);
    assert.equal(nested.headers["use-as-dictionary"], 'match="/modules/app.*.wasm"');
  });

  test("without the request headers the module is served as before, brotli when accepted", async () => {
    const plain = await get(`/${NEW}`);
    assert.equal(plain.headers["content-encoding"], undefined);
    assert.deepEqual(plain.body, newBytes);
    const brotli = await get(`/${NEW}`, { "Accept-Encoding": "gzip, br" });
    assert.equal(brotli.headers["content-encoding"], "br");
    assert.match(brotli.headers["etag"], /^"[0-9a-f]+-[0-9a-f]+-br"$/);
  });

  test("the difference needs both headers: Available-Dictionary alone, or dcb alone, is not enough", async () => {
    const dictionaryOnly = await get(`/${NEW}`, { "Accept-Encoding": "br", "Available-Dictionary": availableDictionaryValue(oldHash) });
    assert.equal(dictionaryOnly.headers["content-encoding"], "br");
    const acceptOnly = await get(`/${NEW}`, { "Accept-Encoding": "br, dcb" });
    assert.equal(acceptOnly.headers["content-encoding"], "br");
    const refused = await get(`/${NEW}`, dcb({ "Accept-Encoding": "br, dcb;q=0" }));
    assert.equal(refused.headers["content-encoding"], "br");
  });

  test("a bad Available-Dictionary is ignored, and never becomes part of a path", async () => {
    const hostile = [
      "", ":", "::", oldHash, `:${oldHash}:`, ":../../../etc/passwd:", ":%2e%2e%2f:", `:${Buffer.alloc(31).toString("base64")}:`, `:${Buffer.alloc(33).toString("base64")}:`,
      `${availableDictionaryValue(oldHash)}, ${availableDictionaryValue(oldHash)}`, `:${"A".repeat(5000)}:`, "x".repeat(4000),
    ];
    for (const value of hostile) {
      const response = await get(`/${NEW}`, dcb({ "Available-Dictionary": value }));
      assert.equal(response.status, 200, value.slice(0, 40));
      assert.equal(response.headers["content-encoding"], "br", value.slice(0, 40));
      assert.equal(response.headers["use-as-dictionary"], 'match="/app.*.wasm"');
    }
  });

  test("a dictionary with no difference file gets the module as before", async () => {
    const unknown = await get(`/${NEW}`, dcb({ "Available-Dictionary": availableDictionaryValue("b".repeat(64)) }));
    assert.equal(unknown.headers["content-encoding"], "br");
    assert.equal(unknown.headers["vary"], "Accept-Encoding, Available-Dictionary");
    // The file written for another module is not offered for this one.
    const other = await get(`/${REST}`, dcb());
    assert.equal(other.headers["content-encoding"], "br");
  });

  test("a difference file that is a link out of the bundle is not served", async () => {
    const response = await get(`/${NEW}`, dcb({ "Available-Dictionary": availableDictionaryValue("a".repeat(64)) }));
    assert.equal(response.status, 200);
    assert.equal(response.headers["content-encoding"], "br");
    assert.ok(!response.body.includes("secret"));
  });

  test("a file that is not a content-hashed module gets neither header", async () => {
    for (const path of ["/app.wasm", `/${FONT}`, "/index.html"]) {
      const response = await get(path, dcb({ "Available-Dictionary": availableDictionaryValue(oldHash) }));
      assert.equal(response.headers["use-as-dictionary"], undefined, path);
      assert.equal(response.headers["vary"], "Accept-Encoding", path);
      assert.notEqual(response.headers["content-encoding"], "dcb", path);
    }
  });

  test("the difference file is revalidated by its own tag, apart from the whole file's", async () => {
    const first = await get(`/${NEW}`, dcb());
    const whole = await get(`/${NEW}`, { "Accept-Encoding": "br" });
    assert.notEqual(first.headers["etag"], whole.headers["etag"]);
    assert.match(first.headers["etag"], /^"[0-9a-f]+-[0-9a-f]+-dcb-[0-9a-f]{16}"$/);
    const revalidated = await get(`/${NEW}`, dcb({ "If-None-Match": first.headers["etag"] }));
    assert.equal(revalidated.status, 304);
    assert.equal(revalidated.headers["use-as-dictionary"], 'match="/app.*.wasm"');
    assert.equal(revalidated.headers["vary"], "Accept-Encoding, Available-Dictionary");
  });

  test("a HEAD request answers with the headers of the difference file and no body", async () => {
    const response = await get(`/${NEW}`, dcb(), "HEAD");
    assert.equal(response.status, 200);
    assert.equal(response.headers["content-encoding"], "dcb");
    assert.equal(Number(response.headers["content-length"]), difference.body.length);
    assert.equal(response.body.length, 0);
  });
});
