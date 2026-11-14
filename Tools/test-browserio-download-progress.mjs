#!/usr/bin/env bun
// BrowserIO download progress in a real browser, on the main thread and in a worker.
//
// One same-origin test server serves Tools/BrowserIO (the page and the host) and /progress/{sized,chunked,gzip}: a
// 256 KiB body written in 16 KiB pieces, with Content-Length (sized), without it (chunked), and gzip-encoded (gzip).
// The same origin keeps Content-Length and Content-Encoding visible to the page, as they are for the app. The probe
// runs the host and returns each body's progress reports, which must be monotonic, throttled (fewer reports than
// writes), end at the whole decoded body, and carry the length headers that Swift applies Foundation's rule to.
// SWIFTUIWEB_BROWSER_ENGINE selects chromium (default), webkit or firefox.
import assert from "node:assert/strict";
import { readFile, stat } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, join, normalize, resolve } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import { gzipSync } from "node:zlib";
import { engineName, launch, ROOT, runSuite } from "./browser-test-support.mjs";

const BROWSERIO = join(ROOT, "Tools/BrowserIO");
const BODY = Buffer.alloc(256 * 1024, 7);
const PIECE = 16 * 1024;
const GZIP = gzipSync(BODY, { level: 9 });
const KINDS = ["sized", "chunked", "gzip"];

const MIME_TYPES = {
  ".css": "text/css",
  ".html": "text/html",
  ".js": "text/javascript",
  ".mjs": "text/javascript",
  ".json": "application/json",
  ".wasm": "application/wasm",
  ".png": "image/png",
  ".svg": "image/svg+xml",
};

async function serveStatic(response, pathname) {
  try {
    let file = join(BROWSERIO, normalize(pathname));
    if ((await stat(file)).isDirectory()) file = join(file, "index.html");
    const body = await readFile(file);
    response.writeHead(200, {
      "Content-Type": MIME_TYPES[extname(file)] ?? "application/octet-stream",
      "Content-Length": body.length,
    });
    response.end(body);
  } catch {
    response.writeHead(404, { "Content-Type": "text/plain" }).end("File not found");
  }
}

// Mirrors the test server's handler: /progress/<kind> writes the body in pieces with a short pause between them,
// everything else is served from Tools/BrowserIO.
async function handle(request, response) {
  const url = new URL(request.url ?? "/", "http://127.0.0.1");
  if (!url.pathname.startsWith("/progress/")) return serveStatic(response, decodeURIComponent(url.pathname));
  const kind = url.pathname.slice("/progress/".length);
  if (!KINDS.includes(kind)) return void response.writeHead(404, { "Content-Type": "text/plain" }).end("File not found");
  const payload = kind === "gzip" ? GZIP : BODY;
  const headers = { "Content-Type": "application/octet-stream" };
  if (kind === "gzip") headers["Content-Encoding"] = "gzip";
  // Node frames the chunks itself once Transfer-Encoding: chunked is set, so the pieces are written raw.
  if (kind === "chunked") headers["Transfer-Encoding"] = "chunked";
  else headers["Content-Length"] = String(payload.length);
  response.writeHead(200, headers);
  for (let offset = 0; offset < payload.length; offset += PIECE) {
    if (response.destroyed) return;
    response.write(payload.subarray(offset, offset + PIECE));
    await sleep(2);
  }
  response.end();
}

function checkReports(mode, kind, result) {
  const where = `${mode}/${kind}`;
  assert.ok(result.finalStatus === 0 && result.httpStatus === 200, `${where}: ${JSON.stringify(result)}`);
  assert.equal(result.bodyLength, BODY.length, `${where}: bodyLength`);
  const reports = result.reports;
  assert.ok(
    reports.length >= 2 && reports.length < PIECE && reports.length < Math.floor(BODY.length / PIECE),
    `${where}: ${reports.length} reports`,
  );
  const received = reports.map((report) => report.received);
  assert.ok(received.slice(1).every((later, i) => later >= received[i]), `${where}: ${JSON.stringify(received)}`);
  assert.equal(received.at(-1), BODY.length, `${where}: ${received.at(-1)}`);
  const last = reports.at(-1);
  if (kind === "sized") {
    assert.ok(last.contentLength === String(BODY.length) && last.contentEncoding === "", `${where}: ${JSON.stringify(last)}`);
  } else if (kind === "chunked") {
    assert.ok(last.contentLength === "" && last.contentEncoding === "", `${where}: ${JSON.stringify(last)}`);
  } else {
    assert.ok(
      last.contentEncoding === "gzip" && last.contentLength === String(GZIP.length),
      `${where}: ${JSON.stringify(last)}`,
    );
  }
}

await runSuite(async () => {
  const server = createServer((request, response) => {
    handle(request, response).catch(() => response.destroy());
  });
  await new Promise((done, fail) => {
    server.once("error", fail);
    server.listen(0, "127.0.0.1", done);
  });
  const base = `http://127.0.0.1:${server.address().port}`;
  const results = {};
  let browser;
  try {
    browser = await launch();
    const context = await browser.newContext();
    const page = await context.newPage();
    for (const mode of ["main", "worker"]) {
      await page.goto(`${base}/download-progress.html?origin=${base}&mode=${mode}`);
      await page.waitForFunction("document.documentElement.dataset.result !== undefined", undefined, { timeout: 120_000 });
      if ((await page.evaluate("document.documentElement.dataset.result")) !== "pass") {
        throw new Error(`${mode}: ${await page.evaluate("window.__downloadProgressError")}`);
      }
      results[mode] = await page.evaluate("window.__downloadProgress");
    }
  } finally {
    await browser?.close();
    server.closeAllConnections();
    server.close();
  }
  for (const [mode, bodies] of Object.entries(results)) {
    for (const kind of KINDS) {
      checkReports(mode, kind, bodies[kind]);
    }
  }
  const counts = KINDS.map((kind) => `${kind} ${results.main[kind].reports.length}`).join(", ");
  console.log(
    "PASS BrowserIO download progress: monotonic, throttled, ends at the body on the main thread and in a worker " +
      `(${counts} reports; ${engineName()})`,
  );
});
