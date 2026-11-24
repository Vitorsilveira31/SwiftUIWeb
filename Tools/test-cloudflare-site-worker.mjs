// Tests for Tools/cloudflare-site/worker.js with a fake assets binding: the brotli copies, the plain files, and the
// difference answers behind their switch. Run: bun test ./Tools/test-cloudflare-site-worker.mjs
import { describe, expect, test } from "bun:test";
import { availableDictionaryValue } from "./dictionary-transport.mjs";
import worker from "./cloudflare-site/worker.js";

const MODULE = "/app.0123abcd.wasm";
const HASH = "ab".repeat(32);
const DCB = `${MODULE}.${HASH}.dcb`;
const bytes = (text) => new TextEncoder().encode(text);

// The headers the real assets carry for the plain file (the _headers rules) and for a copy (its own type and ETag).
const plainHeaders = (type, etag) => ({
  "Content-Type": type,
  "Cache-Control": "public, max-age=31536000, immutable",
  "X-Content-Type-Options": "nosniff",
  ETag: etag,
  "Content-Length": "999",
});
const copyHeaders = (etag, body) => ({ "Content-Type": "application/octet-stream", ETag: etag, "Content-Length": String(body.length) });

// A map of path to { headers, body }. A request with the file's ETag in If-None-Match gets a 304; HEAD gets no body.
function assets(files) {
  const calls = [];
  return {
    calls,
    async fetch(request) {
      const path = new URL(request.url).pathname;
      calls.push(`${request.method} ${path}`);
      const file = files[path];
      if (!file) return new Response("not found", { status: 404 });
      if (request.headers.get("If-None-Match") === file.headers.ETag) return new Response(null, { status: 304, headers: file.headers });
      return new Response(request.method === "HEAD" ? null : file.body, { status: 200, headers: file.headers });
    },
  };
}

const site = () => ({
  [MODULE]: { headers: plainHeaders("application/wasm", '"plain-wasm"'), body: bytes("the module, whole") },
  [`${MODULE}.br`]: { headers: copyHeaders('"br-wasm"', bytes("brotli bytes")), body: bytes("brotli bytes") },
  [DCB]: { headers: copyHeaders('"dcb-wasm"', bytes("difference bytes")), body: bytes("difference bytes") },
  "/index.0123abcd.js": { headers: plainHeaders("text/javascript", '"plain-js"'), body: bytes("script") },
  "/index.0123abcd.js.br": { headers: copyHeaders('"br-js"', bytes("script br")), body: bytes("script br") },
  "/style.0123abcd.css": { headers: plainHeaders("text/css", '"plain-css"'), body: bytes("style") },
  "/index.html": { headers: plainHeaders("text/html", '"plain-html"'), body: bytes("<html>") },
});

// `cf.clientAcceptEncoding` is the reader's own value; the header is what Cloudflare rewrote it to.
function request(path, { method = "GET", headers = {}, reader = "br, gzip" } = {}) {
  const made = new Request(`https://site.example${path}`, { method, headers: { "Accept-Encoding": "br, gzip", ...headers } });
  made.cf = { clientAcceptEncoding: reader };
  return made;
}
const askingForDifference = { "Available-Dictionary": availableDictionaryValue(HASH) };
const text = async (response) => new TextDecoder().decode(await response.arrayBuffer());
const run = (req, env = {}, files = site()) => worker.fetch(req, { ASSETS: assets(files), ...env });

describe("worker.js before the difference path", () => {
  test("a reader that accepts brotli gets the copy's bytes, length and ETag with the plain file's other headers", async () => {
    const response = await run(request("/index.0123abcd.js"));
    expect(response.status).toBe(200);
    expect(await text(response)).toBe("script br");
    expect(response.headers.get("Content-Encoding")).toBe("br");
    expect(response.headers.get("ETag")).toBe('"br-js"');
    expect(response.headers.get("Content-Length")).toBe(String("script br".length));
    expect(response.headers.get("Content-Type")).toBe("text/javascript");
    expect(response.headers.get("Cache-Control")).toBe("public, max-age=31536000, immutable");
    expect(response.headers.get("Vary")).toBe("Accept-Encoding");
    expect(response.headers.get("Use-As-Dictionary")).toBeNull();
  });

  test("a reader without brotli (by cf.clientAcceptEncoding, not the rewritten header) gets the plain file", async () => {
    const response = await run(request("/index.0123abcd.js", { reader: "gzip" }));
    expect(await text(response)).toBe("script");
    expect(response.headers.get("Content-Encoding")).toBeNull();
    expect(response.headers.get("Vary")).toBe("Accept-Encoding");
  });

  test("without cf the Accept-Encoding header decides, and br;q=0 refuses brotli", async () => {
    const plain = new Request("https://site.example/index.0123abcd.js", { headers: { "Accept-Encoding": "gzip, br;q=0" } });
    expect(await text(await run(plain))).toBe("script");
    const accepted = new Request("https://site.example/index.0123abcd.js", { headers: { "Accept-Encoding": "gzip, br" } });
    expect(await text(await run(accepted))).toBe("script br");
  });

  test("a file with no brotli copy gets the plain file", async () => {
    const response = await run(request("/style.0123abcd.css"));
    expect(await text(response)).toBe("style");
    expect(response.headers.get("Content-Encoding")).toBeNull();
    expect(response.headers.get("Vary")).toBe("Accept-Encoding");
    expect(response.headers.get("Use-As-Dictionary")).toBeNull();
  });

  test("the reader's conditional headers go to the copy: its ETag answers 304 without a body or length", async () => {
    const response = await run(request("/index.0123abcd.js", { headers: { "If-None-Match": '"br-js"' } }));
    expect(response.status).toBe(304);
    expect(response.headers.get("ETag")).toBe('"br-js"');
    expect(response.headers.get("Content-Length")).toBeNull();
    expect(response.headers.get("Content-Encoding")).toBe("br");
    expect(await text(response)).toBe("");
  });

  test("HEAD answers the copy's headers and no body", async () => {
    const response = await run(request("/index.0123abcd.js", { method: "HEAD" }));
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Length")).toBe(String("script br".length));
    expect(response.headers.get("Content-Encoding")).toBe("br");
    expect(await text(response)).toBe("");
  });

  test("a request that is not a GET or HEAD, or not for .wasm, .js or .css, goes to the assets untouched", async () => {
    const files = site();
    const binding = assets(files);
    const post = await worker.fetch(request("/index.0123abcd.js", { method: "POST" }), { ASSETS: binding });
    expect(post.status).toBe(200);
    expect(binding.calls).toEqual(["POST /index.0123abcd.js"]);
    const page = await worker.fetch(request("/index.html"), { ASSETS: binding });
    expect(page.headers.get("Vary")).toBeNull();
    expect(binding.calls).toEqual(["POST /index.0123abcd.js", "GET /index.html"]);
  });

  test(".js and .css never get the dictionary headers, with the switch on and the check header sent", async () => {
    for (const path of ["/index.0123abcd.js", "/style.0123abcd.css"]) {
      const response = await run(request(path, { headers: { ...askingForDifference, "SwiftUIWeb-Dictionary-Check": "1" } }), { DICTIONARY_UPDATES: "on" });
      expect(response.headers.get("Use-As-Dictionary")).toBeNull();
      expect(response.headers.get("Vary")).toBe("Accept-Encoding");
      expect(response.headers.get("Content-Encoding")).not.toBe("dcb");
    }
  });

  test("a missing file passes the assets' answer through", async () => {
    const response = await run(request("/gone.0123abcd.js"));
    expect(response.status).toBe(404);
  });
});

describe("worker.js update by difference", () => {
  test("with the switch off a module never gets dcb, but still names itself as a dictionary", async () => {
    const response = await run(request(MODULE, { headers: askingForDifference, reader: "br, dcb, gzip" }), { DICTIONARY_UPDATES: "off" });
    expect(await text(response)).toBe("brotli bytes");
    expect(response.headers.get("Content-Encoding")).toBe("br");
    expect(response.headers.get("Use-As-Dictionary")).toBe('match="/app.*.wasm"');
    expect(response.headers.get("Vary")).toBe("Accept-Encoding, Available-Dictionary");
  });

  test("the plain module carries the dictionary headers too (a reader without brotli)", async () => {
    const response = await run(request(MODULE, { reader: "gzip" }));
    expect(await text(response)).toBe("the module, whole");
    expect(response.headers.get("Use-As-Dictionary")).toBe('match="/app.*.wasm"');
    expect(response.headers.get("Vary")).toBe("Accept-Encoding, Available-Dictionary");
  });

  test("a 304 for a module carries them as well", async () => {
    const response = await run(request(MODULE, { headers: { "If-None-Match": '"br-wasm"' } }));
    expect(response.status).toBe(304);
    expect(response.headers.get("Use-As-Dictionary")).toBe('match="/app.*.wasm"');
    expect(response.headers.get("Vary")).toBe("Accept-Encoding, Available-Dictionary");
  });

  test("a missing module has the Vary but no Use-As-Dictionary", async () => {
    const response = await run(request("/app.99999999.wasm"));
    expect(response.status).toBe(404);
    expect(response.headers.get("Use-As-Dictionary")).toBeNull();
  });

  for (const [name, request_, env] of [
    ["the check header", { headers: { ...askingForDifference, "SwiftUIWeb-Dictionary-Check": "1" }, reader: "br, dcb" }, {}],
    ["DICTIONARY_UPDATES on", { headers: askingForDifference, reader: "br, dcb" }, { DICTIONARY_UPDATES: "on" }],
  ]) {
    test(`${name} gets the difference file's bytes with its length and ETag and the module's other headers`, async () => {
      const response = await run(request(MODULE, request_), env);
      expect(response.status).toBe(200);
      expect(await text(response)).toBe("difference bytes");
      expect(response.headers.get("Content-Encoding")).toBe("dcb");
      expect(response.headers.get("Content-Length")).toBe(String("difference bytes".length));
      expect(response.headers.get("ETag")).toBe('"dcb-wasm"');
      expect(response.headers.get("Content-Type")).toBe("application/wasm");
      expect(response.headers.get("Cache-Control")).toBe("public, max-age=31536000, immutable");
      expect(response.headers.get("X-Content-Type-Options")).toBe("nosniff");
      expect(response.headers.get("Use-As-Dictionary")).toBe('match="/app.*.wasm"');
      expect(response.headers.get("Vary")).toBe("Accept-Encoding, Available-Dictionary");
    });
  }

  test("with no DICTIONARY_UPDATES in env the default is on: a valid request gets the difference", async () => {
    const response = await run(request(MODULE, { headers: askingForDifference, reader: "br, dcb" }));
    expect(await text(response)).toBe("difference bytes");
    expect(response.headers.get("Content-Encoding")).toBe("dcb");
  });

  test("the check header only counts as 1; the switch accepts only on", async () => {
    const headers = { ...askingForDifference, "SwiftUIWeb-Dictionary-Check": "0" };
    expect(await text(await run(request(MODULE, { headers, reader: "br, dcb" }), { DICTIONARY_UPDATES: "true" }))).toBe("brotli bytes");
  });

  test("a missing, malformed or other-length Available-Dictionary falls back to brotli", async () => {
    for (const value of [undefined, "", "sha-256", `:${btoa("short")}:`, availableDictionaryValue(HASH).slice(1), `${availableDictionaryValue(HASH)}, ${availableDictionaryValue(HASH)}`]) {
      const headers = { "SwiftUIWeb-Dictionary-Check": "1", ...(value === undefined ? {} : { "Available-Dictionary": value }) };
      const response = await run(request(MODULE, { headers, reader: "br, dcb" }));
      expect(await text(response)).toBe("brotli bytes");
      expect(response.headers.get("Content-Encoding")).toBe("br");
    }
  });

  test("a reader that does not accept dcb (by cf.clientAcceptEncoding) gets brotli", async () => {
    const headers = { ...askingForDifference, "SwiftUIWeb-Dictionary-Check": "1", "Accept-Encoding": "br, dcb" };
    const response = await run(request(MODULE, { headers, reader: "br, gzip" }));
    expect(await text(response)).toBe("brotli bytes");
    const refused = await run(request(MODULE, { headers, reader: "br, dcb;q=0" }));
    expect(await text(refused)).toBe("brotli bytes");
  });

  test("a hash with no difference file falls back to brotli, and the name is built from the parsed hash", async () => {
    const files = site();
    const other = availableDictionaryValue("cd".repeat(32));
    const binding = assets(files);
    const response = await worker.fetch(request(MODULE, { headers: { "Available-Dictionary": other, "SwiftUIWeb-Dictionary-Check": "1" }, reader: "br, dcb" }), { ASSETS: binding });
    expect(await text(response)).toBe("brotli bytes");
    expect(binding.calls).toContain(`GET ${MODULE}.${"cd".repeat(32)}.dcb`);
    expect(response.headers.get("Use-As-Dictionary")).toBe('match="/app.*.wasm"');
  });

  test("HEAD gets the difference file's headers and no body", async () => {
    const response = await run(request(MODULE, { method: "HEAD", headers: { ...askingForDifference, "SwiftUIWeb-Dictionary-Check": "1" }, reader: "br, dcb" }));
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Encoding")).toBe("dcb");
    expect(response.headers.get("Content-Length")).toBe(String("difference bytes".length));
    expect(await text(response)).toBe("");
  });

  test("a 304 from the difference file keeps its ETag, has no length or body, and names the dictionary", async () => {
    const headers = { ...askingForDifference, "SwiftUIWeb-Dictionary-Check": "1", "If-None-Match": '"dcb-wasm"' };
    const response = await run(request(MODULE, { headers, reader: "br, dcb" }));
    expect(response.status).toBe(304);
    expect(response.headers.get("Content-Encoding")).toBe("dcb");
    expect(response.headers.get("ETag")).toBe('"dcb-wasm"');
    expect(response.headers.get("Content-Length")).toBeNull();
    expect(response.headers.get("Use-As-Dictionary")).toBe('match="/app.*.wasm"');
    expect(await text(response)).toBe("");
  });

  test("a module under a directory the pattern cannot name gets no Use-As-Dictionary", async () => {
    const files = { "/v1.2/app.0123abcd.wasm": site()[MODULE] };
    const response = await run(request("/v1.2/app.0123abcd.wasm", { reader: "gzip" }), {}, files);
    expect(response.status).toBe(200);
    expect(response.headers.get("Use-As-Dictionary")).toBeNull();
  });
});
