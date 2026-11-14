#!/usr/bin/env bun
// Tests for the development API proxy in Tools/bun-server.ts: a request under SWIFTUIWEB_API_PATH is proxied only to
// SWIFTUIWEB_API_ORIGIN. A remainder such as `//host/path` (scheme-relative) must not move the proxied request to
// another host. Both backends are loopback fixtures, so nothing leaves the machine. The requests are sent with node:http,
// which keeps the request target exactly as written (no URL normalisation on the client side).
// Run: bun test ./Tools/test-bun-server-api-proxy.mjs
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import http from "node:http";
import net from "node:net";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { after, before, beforeEach, describe, test } from "node:test";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

let proxyPort;
let proxy;
let root;
let backend;
let attacker;

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

// A loopback fixture that records every request it receives and answers with its name and the path it saw.
function fixture(name) {
  const hits = [];
  const server = http.createServer((request, response) => {
    hits.push({ url: request.url, cookie: request.headers.cookie });
    response.writeHead(200, { "Content-Type": "text/plain" });
    response.end(`${name} ${request.url}`);
  });
  return new Promise((resolveFixture) => {
    server.listen(0, "127.0.0.1", () => resolveFixture({ server, hits, port: server.address().port }));
  });
}

// Sends `target` exactly as written on the request line.
function raw(target, headers = {}) {
  return new Promise((resolveRequest, reject) => {
    const request = http.request(
      { host: "127.0.0.1", port: proxyPort, path: target, method: "GET", headers, agent: false },
      (response) => {
        const chunks = [];
        response.on("data", (chunk) => chunks.push(chunk));
        response.on("end", () =>
          resolveRequest({ status: response.statusCode, body: Buffer.concat(chunks).toString("utf8") }),
        );
      },
    );
    request.on("error", reject);
    request.end();
  });
}

async function waitUntilServing() {
  const deadline = Date.now() + 15000;
  for (;;) {
    try {
      await raw("/");
      return;
    } catch (error) {
      if (Date.now() > deadline) throw error;
      await new Promise((done) => setTimeout(done, 100));
    }
  }
}

before(async () => {
  root = mkdtempSync(join(tmpdir(), "server-api-proxy-"));
  writeFileSync(join(root, "index.html"), "<!doctype html><title>App</title>");
  backend = await fixture("backend");
  attacker = await fixture("attacker");
  proxyPort = await freePort();
  proxy = spawn(process.execPath, [join(ROOT, "Tools", "bun-server.ts"), root, String(proxyPort)], {
    env: {
      ...process.env,
      SWIFTUIWEB_API_ORIGIN: `http://127.0.0.1:${backend.port}`,
      SWIFTUIWEB_API_PATH: "/api",
    },
    stdio: ["ignore", "ignore", "pipe"],
  });
  await waitUntilServing();
});

after(() => {
  proxy?.kill("SIGTERM");
  backend?.server.close();
  attacker?.server.close();
  rmSync(root, { recursive: true, force: true });
});

beforeEach(() => {
  backend.hits.length = 0;
  attacker.hits.length = 0;
});

describe("development API proxy stays on the configured backend", () => {
  test("a normal API path reaches the backend with its query and the browser's cookie", async () => {
    const response = await raw("/api/ping?x=1", { Cookie: "session=dummy" });
    assert.equal(response.status, 200);
    assert.equal(response.body, `backend /ping?x=1`);
    assert.deepEqual(
      backend.hits.map((hit) => [hit.url, hit.cookie]),
      [["/ping?x=1", "session=dummy"]],
    );
  });

  test("the bare API path reaches the backend root", async () => {
    const response = await raw("/api");
    assert.equal(response.status, 200);
    assert.equal(response.body, "backend /");
  });

  test("encoded characters are passed to the backend unchanged", async () => {
    const response = await raw("/api/a%20b/%2Fx");
    assert.equal(response.status, 200);
    assert.equal(response.body, "backend /a%20b/%2Fx");
    assert.deepEqual(attacker.hits, []);
  });

  test("a percent-encoded double slash stays a path on the backend", async () => {
    const response = await raw(`/api/%2f%2f127.0.0.1:${attacker.port}/hit`);
    assert.deepEqual(attacker.hits.map((hit) => hit.url), []);
    assert.equal(response.status, 200);
    assert.equal(response.body, `backend /%2f%2f127.0.0.1:${attacker.port}/hit`);
  });

  test("a scheme-relative remainder (//host/path) is refused and no other host is contacted", async () => {
    const response = await raw(`/api//127.0.0.1:${attacker.port}/hit`, { Cookie: "session=dummy" });
    assert.deepEqual(attacker.hits.map((hit) => hit.url), [], "the attacker fixture was contacted");
    assert.deepEqual(backend.hits.map((hit) => hit.url), [], "the backend was contacted for a refused request");
    assert.equal(response.status, 403);
  });

  test("a backslash form that the URL parser turns into //host is refused", async () => {
    const response = await raw(`/api/\\127.0.0.1:${attacker.port}/hit`, { Cookie: "session=dummy" });
    assert.deepEqual(attacker.hits.map((hit) => hit.url), [], "the attacker fixture was contacted");
    assert.deepEqual(backend.hits.map((hit) => hit.url), [], "the backend was contacted for a refused request");
    assert.equal(response.status, 403);
  });

  test("a dot segment that collapses to //host is refused", async () => {
    const response = await raw(`/api/.//127.0.0.1:${attacker.port}/hit`);
    assert.deepEqual(attacker.hits.map((hit) => hit.url), [], "the attacker fixture was contacted");
    assert.equal(response.status, 403);
  });
});
