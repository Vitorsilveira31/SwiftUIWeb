#!/usr/bin/env bun
// Updates by difference (Tools/dictionary-transport.mjs, Documentation/DEPLOYMENT.md) in a real browser, on a small fixture and
// without a Swift build.
//
// Two versions of a wasm module of a few hundred KB (a large data segment and an export that returns the version) are written as
// two release bundles; Tools/delta-compress-bundle.mjs writes the difference file of the second against the first. Tools/bun-server.ts
// serves version 1, the browser loads it and keeps it as the dictionary, and the same origin then serves version 2. The page loads
// version 2 three ways: the page's fetch with WebAssembly.instantiateStreaming, a Worker's fetch with WebAssembly.compileStreaming, and a
// Worker's synchronous XMLHttpRequest with new WebAssembly.Module. Each way gets its own browser context, so each one starts with only
// version 1 in its cache.
//
// In Chromium the request for version 2 must carry Available-Dictionary, the response must be dcb, the bytes on the wire must be about the
// size of the difference file, and the module must work. In an engine that does not send the header (WebKit, Firefox) the module
// must work and the whole file must be served.
// Run: bun Tools/test-dictionary-update-browser.mjs   (SWIFTUIWEB_BROWSER_ENGINE=webkit for the other engines)
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { brotliCompressSync } from "node:zlib";
import { deltaCompressBundle } from "./delta-compress-bundle.mjs";
import { engineName, freePort, launch, runSuite, serveBundle } from "./browser-test-support.mjs";

const DATA_BYTES = 300 * 1024;
const PROBE = 1234;
const WAYS = ["page fetch + instantiateStreaming", "Worker fetch + compileStreaming", "Worker XMLHttpRequest + new WebAssembly.Module"];

const leb = (value) => {
  const bytes = [];
  do {
    let byte = value & 0x7f;
    value >>>= 7;
    if (value !== 0) byte |= 0x80;
    bytes.push(byte);
  } while (value !== 0);
  return bytes;
};
const signed = (value) => {
  const bytes = [];
  for (;;) {
    const byte = value & 0x7f;
    value >>= 7;
    if ((value === 0 && !(byte & 0x40)) || (value === -1 && byte & 0x40)) return [...bytes, byte];
    bytes.push(byte | 0x80);
  }
};
const section = (id, body) => [id, ...leb(body.length), ...body];
const text = (value) => [...leb(value.length), ...new TextEncoder().encode(value)];

/** A valid module: `version()` returns `version`, `peek(i)` reads byte i of a data segment holding `data`, `memory` is exported. */
function fixtureModule(version, data) {
  const pages = Math.ceil(data.length / 65536);
  const versionBody = [0x00, 0x41, ...signed(version), 0x0b];
  const peekBody = [0x00, 0x20, 0x00, 0x2d, 0x00, 0x00, 0x0b];
  const header = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00];
  const sections = [
    ...section(1, [2, 0x60, 0, 1, 0x7f, 0x60, 1, 0x7f, 1, 0x7f]),
    ...section(3, [2, 0, 1]),
    ...section(5, [1, 0, ...leb(pages)]),
    ...section(7, [3, ...text("version"), 0, 0, ...text("peek"), 0, 1, ...text("memory"), 2, 0]),
    ...section(10, [2, ...leb(versionBody.length), ...versionBody, ...leb(peekBody.length), ...peekBody]),
  ];
  const segment = [1, 0, 0x41, 0, 0x0b, ...leb(data.length)];
  return Buffer.concat([Buffer.from([...header, ...sections, 11, ...leb(segment.length + data.length), ...segment]), Buffer.from(data)]);
}

/** Deterministic bytes that do not compress, so a whole-file download costs about the file's size. */
function randomData(length) {
  const out = Buffer.alloc(length);
  let state = 0x9e3779b9;
  for (let index = 0; index < length; index++) {
    state ^= state << 13;
    state >>>= 0;
    state ^= state >>> 17;
    state ^= state << 5;
    state >>>= 0;
    out[index] = state & 0xff;
  }
  return out;
}

const PAGE = (moduleName) => `<!doctype html><meta charset="utf-8"><title>Update by difference</title><script>
const url = "/${moduleName}";
const read = (instance) => ({ version: instance.exports.version(), peek: instance.exports.peek(${PROBE}) });
window.loadModule = async (way) => {
  if (way === 0) return read((await WebAssembly.instantiateStreaming(fetch(url))).instance);
  return new Promise((done, fail) => {
    const worker = new Worker("/worker.js");
    worker.onmessage = (event) => { worker.terminate(); event.data.error ? fail(new Error(event.data.error)) : done(event.data); };
    worker.onerror = (event) => fail(new Error(event.message));
    worker.postMessage({ way, url });
  });
};
window.ready = true;
</script>`;

const WORKER = `self.onmessage = async ({ data }) => {
  try {
    let module;
    if (data.way === 1) module = await WebAssembly.compileStreaming(fetch(data.url));
    else {
      const request = new XMLHttpRequest();
      request.open("GET", data.url, false);
      request.responseType = "arraybuffer";
      request.send();
      if (request.status !== 200) throw new Error("status " + request.status);
      module = new WebAssembly.Module(request.response);
    }
    const instance = await WebAssembly.instantiate(module, {});
    self.postMessage({ version: instance.exports.version(), peek: instance.exports.peek(${PROBE}) });
  } catch (error) { self.postMessage({ error: String(error) }); }
};`;

/** A release bundle holding one hashed module and its .br copy. Returns its directory and the module's file name. */
function writeBundle(root, name, bytes) {
  const hash = createHash("sha256").update(bytes).digest("hex").slice(0, 8);
  const file = `app.${hash}.wasm`;
  const directory = join(root, name);
  mkdirSync(directory, { recursive: true });
  writeFileSync(join(directory, file), bytes);
  writeFileSync(join(directory, `${file}.br`), brotliCompressSync(bytes));
  writeFileSync(join(directory, "index.html"), PAGE(file));
  writeFileSync(join(directory, "worker.js"), WORKER);
  return { directory, file };
}

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

/** One way of loading, in its own context: version 1, then version 2 at the same origin. Returns what the version 2 request showed. */
async function update(browser, way, versions, waitMs) {
  const port = await freePort();
  let server = await serveBundle({ bundle: versions[0].directory, port, required: ["index.html"], logName: null });
  const context = await browser.newContext();
  const seen = [];
  context.on("response", (response) => {
    if (!response.url().endsWith(".wasm")) return;
    seen.push((async () => {
      const request = response.request();
      return { url: response.url(), requestHeaders: await request.allHeaders(), responseHeaders: await response.allHeaders(), sizes: await request.sizes().catch(() => null) };
    })());
  });
  try {
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (error) => errors.push(String(error)));
    await page.goto(`${server.base}/`);
    await page.waitForFunction(() => window.ready === true);
    const first = await page.evaluate((index) => window.loadModule(index), way);
    assert.deepEqual(first, { version: 1, peek: first.peek }, "version 1 loads");
    // The browser keeps the dictionary after the response; give it time to write it.
    await sleep(waitMs);
    const before = seen.length;
    await server.stop();
    server = await serveBundle({ bundle: versions[1].directory, port, required: ["index.html"], logName: null });
    assert.equal(server.port, port, "version 2 is served from the same origin");
    await page.goto(`${server.base}/`);
    await page.waitForFunction(() => window.ready === true);
    const second = await page.evaluate((index) => window.loadModule(index), way);
    assert.deepEqual(errors, [], "no page error");
    const responses = (await Promise.all(seen.slice(before))).filter((entry) => entry.url.endsWith(versions[1].file));
    return { second, responses };
  } finally {
    await context.close();
    await server.stop();
  }
}

await runSuite(async () => {
  const engine = engineName();
  const work = mkdtempSync(join(tmpdir(), "dictionary-update-"));
  const browser = await launch();
  try {
    const data = randomData(DATA_BYTES);
    const next = Buffer.from(data);
    for (let index = 20_000; index < 20_200; index++) next[index] ^= 0x5a;
    const versions = [writeBundle(work, "v1", fixtureModule(1, data)), writeBundle(work, "v2", fixtureModule(2, next))];
    const { decisions } = await deltaCompressBundle(versions[1].directory, [versions[0].directory]);
    assert.equal(decisions.length, 1);
    assert.equal(decisions[0].kept, true, "the difference file is kept");
    const wholeBytes = statSync(join(versions[1].directory, `${versions[1].file}.br`)).size;
    const differenceBytes = decisions[0].bytes;
    assert.ok(differenceBytes < wholeBytes, "the difference file is smaller than the whole file");
    console.log(`fixture: module ${statSync(join(versions[1].directory, versions[1].file)).size} bytes, .br ${wholeBytes}, difference file ${differenceBytes}`);

    for (let way = 0; way < WAYS.length; way++) {
      // The dictionary is stored asynchronously: when the request for version 2 goes without it, try again with a longer wait.
      let result, waited = 0;
      for (const waitMs of [1000, 3000, 8000]) {
        result = await update(browser, way, versions, waitMs);
        waited = waitMs;
        if (engine !== "chromium" || result.responses.some((entry) => entry.requestHeaders["available-dictionary"])) break;
      }
      assert.equal(result.second.version, 2, `${WAYS[way]}: the module is version 2`);
      assert.equal(result.second.peek, next[PROBE], `${WAYS[way]}: the module's data is version 2's`);
      assert.ok(result.responses.length >= 1, `${WAYS[way]}: the module was requested`);
      const response = result.responses[0];
      const encoding = response.responseHeaders["content-encoding"];
      const sent = response.requestHeaders["available-dictionary"];
      const wire = response.sizes?.responseBodySize ?? null;
      if (sent) {
        assert.equal(encoding, "dcb", `${WAYS[way]}: the response is dcb`);
        assert.match(response.requestHeaders["accept-encoding"], /\bdcb\b/, `${WAYS[way]}: the request accepts dcb`);
        assert.ok(wire !== null && Math.abs(wire - differenceBytes) <= 64, `${WAYS[way]}: ${wire} bytes on the wire, the difference file is ${differenceBytes}`);
        assert.ok(wire < wholeBytes / 2, `${WAYS[way]}: far fewer bytes than the whole file`);
      } else {
        assert.equal(engine === "chromium", false, `${WAYS[way]}: Chromium sent no Available-Dictionary`);
        assert.notEqual(encoding, "dcb", `${WAYS[way]}: no dictionary, no dcb`);
        assert.ok(wire === null || wire >= wholeBytes - 64, `${WAYS[way]}: the whole file was served (${wire} bytes)`);
      }
      assert.match(response.responseHeaders["vary"] ?? "", /Available-Dictionary/);
      console.log(`ok: ${engine}, ${WAYS[way]}: version 2 works; ${sent ? `dcb, ${wire} bytes on the wire (whole file ${wholeBytes}, after a wait of ${waited} ms)` : `whole file, ${wire} bytes (the engine sent no Available-Dictionary)`}`);
    }
  } finally {
    await browser.close();
    rmSync(work, { recursive: true, force: true });
  }
});
