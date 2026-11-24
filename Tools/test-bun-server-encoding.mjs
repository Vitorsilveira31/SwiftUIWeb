#!/usr/bin/env bun
// Tests for the static side of Tools/bun-server.ts on a release bundle: precompressed siblings chosen by
// Accept-Encoding, immutable caching of hashed names, ETag revalidation of everything else. The requests are read raw
// (node:http does not decompress), so the bytes and headers are the ones a browser would receive.
// Run: bun test ./Tools/test-bun-server-encoding.mjs
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import http from "node:http";
import net from "node:net";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { after, before, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { brotliDecompressSync, brotliCompressSync, gunzipSync, gzipSync } from "node:zlib";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const WASM_HASHED = "app.3f9a1c2e.wasm";
const JS_HASHED = "index.5b2d7a90.js";
const FONT_HASHED = "fonts/F.0c1d2e3f.woff2";
const wasmBytes = Buffer.from(Array.from({ length: 64 * 1024 }, (_, index) => (index * 31) % 251));
const jsBytes = Buffer.from(`export const ready = true;\n`.repeat(200));
const fontBytes = Buffer.alloc(2048, 9);
const pageBytes = Buffer.from(`<!doctype html><title>Page</title>${"<p>x</p>".repeat(200)}`);

let server;
let base;
let bundle;

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

before(async () => {
  bundle = mkdtempSync(join(tmpdir(), "server-encoding-"));
  const write = (name, bytes) => {
    mkdirSync(dirname(join(bundle, name)), { recursive: true });
    writeFileSync(join(bundle, name), bytes);
  };
  write(WASM_HASHED, wasmBytes);
  write(`${WASM_HASHED}.br`, brotliCompressSync(wasmBytes));
  write(`${WASM_HASHED}.gz`, gzipSync(wasmBytes));
  write(JS_HASHED, jsBytes);
  write(`${JS_HASHED}.gz`, gzipSync(jsBytes));
  write(FONT_HASHED, fontBytes);
  write("index.html", pageBytes);
  write("index.html.br", brotliCompressSync(pageBytes));
  write("plain.js", jsBytes);
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
});

describe("bun-server encodings and caching", () => {
  test("serves the brotli sibling to a client that accepts br, with the wasm type and immutable caching", async () => {
    const response = await get(`/${WASM_HASHED}`, { "Accept-Encoding": "gzip, deflate, br, zstd" });
    assert.equal(response.status, 200);
    assert.equal(response.headers["content-encoding"], "br");
    assert.equal(response.headers["content-type"], "application/wasm");
    assert.equal(response.headers["cache-control"], "public, max-age=31536000, immutable");
    // A content-hashed module also varies by the dictionary the request names (Tools/test-bun-server-dictionary.mjs).
    assert.equal(response.headers["vary"], "Accept-Encoding, Available-Dictionary");
    assert.equal(Number(response.headers["content-length"]), response.body.length);
    assert.deepEqual(brotliDecompressSync(response.body), wasmBytes);
  });

  test("falls back to gzip when brotli is not accepted, and to the identity coding when neither is", async () => {
    const gzipped = await get(`/${WASM_HASHED}`, { "Accept-Encoding": "deflate, gzip;q=0.5" });
    assert.equal(gzipped.headers["content-encoding"], "gzip");
    assert.deepEqual(gunzipSync(gzipped.body), wasmBytes);

    const plain = await get(`/${WASM_HASHED}`, { "Accept-Encoding": "identity" });
    assert.equal(plain.headers["content-encoding"], undefined);
    assert.deepEqual(plain.body, wasmBytes);
    assert.equal(Number(plain.headers["content-length"]), wasmBytes.length);

    const none = await get(`/${WASM_HASHED}`);
    assert.equal(none.headers["content-encoding"], undefined);
    assert.deepEqual(none.body, wasmBytes);
  });

  test("a coding refused with q=0 is not sent", async () => {
    const response = await get(`/${WASM_HASHED}`, { "Accept-Encoding": "br;q=0, gzip" });
    assert.equal(response.headers["content-encoding"], "gzip");
  });

  test("a hashed name without a sibling is still immutable and served as it is", async () => {
    const response = await get(`/${FONT_HASHED}`, { "Accept-Encoding": "br, gzip" });
    assert.equal(response.headers["content-encoding"], undefined);
    assert.equal(response.headers["cache-control"], "public, max-age=31536000, immutable");
    assert.deepEqual(response.body, fontBytes);
  });

  test("index.html is revalidated: no-cache with an ETag, and 304 when the tag matches", async () => {
    const first = await get("/", { "Accept-Encoding": "br" });
    assert.equal(first.status, 200);
    assert.equal(first.headers["cache-control"], "no-cache");
    assert.equal(first.headers["content-encoding"], "br");
    assert.match(first.headers["etag"], /^"[0-9a-f]+-[0-9a-f]+-br"$/);
    assert.deepEqual(brotliDecompressSync(first.body), pageBytes);

    const revalidated = await get("/", { "Accept-Encoding": "br", "If-None-Match": first.headers["etag"] });
    assert.equal(revalidated.status, 304);
    assert.equal(revalidated.body.length, 0);
    assert.equal(revalidated.headers["etag"], first.headers["etag"]);

    const weak = await get("/", { "Accept-Encoding": "br", "If-None-Match": `W/${first.headers["etag"]}` });
    assert.equal(weak.status, 304);

    const other = await get("/", { "Accept-Encoding": "br", "If-None-Match": '"not-this-one"' });
    assert.equal(other.status, 200);
  });

  test("an unhashed script is revalidated, not cached as immutable", async () => {
    const response = await get("/plain.js");
    assert.equal(response.status, 200);
    assert.equal(response.headers["cache-control"], "no-cache");
    assert.match(response.headers["etag"], /^"[0-9a-f]+-[0-9a-f]+"$/);
    assert.deepEqual(response.body, jsBytes);
  });

  test("a HEAD request answers with the headers of the sibling and no body", async () => {
    const response = await get(`/${JS_HASHED}`, { "Accept-Encoding": "gzip" }, "HEAD");
    assert.equal(response.status, 200);
    assert.equal(response.headers["content-encoding"], "gzip");
    assert.equal(Number(response.headers["content-length"]), gzipSync(jsBytes).length);
    assert.equal(response.body.length, 0);
  });

  test("an application route still gets the page, revalidated", async () => {
    const response = await get("/works/42", { Accept: "text/html" });
    assert.equal(response.status, 200);
    assert.equal(response.headers["cache-control"], "no-cache");
    assert.deepEqual(response.body, pageBytes);
  });
});
