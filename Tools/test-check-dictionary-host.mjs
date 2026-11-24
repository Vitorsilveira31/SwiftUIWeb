// Tests for Tools/check-dictionary-host.mjs: against Tools/bun-server.ts serving a bundle that Tools/delta-compress-bundle.mjs
// wrote difference files for, and against local servers that answer wrongly. Run: bun test ./Tools/test-check-dictionary-host.mjs
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawn } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import net from "node:net";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { brotliCompressSync, gzipSync } from "node:zlib";
import { checkHost, describeResult, main, parseArguments, parseHeaderLine } from "./check-dictionary-host.mjs";
import { dcbBody, parseAvailableDictionary, sha256Hex, useAsDictionary, VARY } from "./dictionary-transport.mjs";
import { deltaCompressBundle } from "./delta-compress-bundle.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

// Deterministic bytes that compress a little and differ a little between versions.
const make = (seed, length = 48 * 1024) => {
  const out = Buffer.alloc(length);
  let state = seed;
  for (let index = 0; index < length; index++) {
    state = (state * 1103515245 + 12345) >>> 0;
    out[index] = index % 7 === 0 ? state >>> 24 : index % 251;
  }
  return out;
};
const changed = (input) => {
  const copy = Buffer.from(input);
  for (let index = 5000; index < 5100; index++) copy[index] ^= 0x55;
  return copy;
};
const nameOf = async (stem, content) => `${stem}.${(await sha256Hex(content)).slice(0, 8)}.wasm`;

const oldApp = make(1);
const newApp = changed(oldApp);
const oldRest = make(2);
const newRest = changed(oldRest);
const onlyNew = make(3);

const names = {
  oldApp: await nameOf("app", oldApp),
  newApp: await nameOf("app", newApp),
  oldRest: await nameOf("app-rest", oldRest),
  newRest: await nameOf("app-rest", newRest),
  lonely: await nameOf("extra", onlyNew),
};
const page = `<!doctype html><title>Site</title><script>fetch("${names.newApp}");fetch("${names.newRest}");fetch("${names.lonely}")</script>`;

const cleanup = [];
const scratch = () => {
  const directory = mkdtempSync(join(tmpdir(), "check-dictionary-host-"));
  cleanup.push(directory);
  return directory;
};
const write = (root, name, content) => {
  mkdirSync(dirname(join(root, name)), { recursive: true });
  writeFileSync(join(root, name), content);
};
const freePort = () =>
  new Promise((done, fail) => {
    const probe = net.createServer();
    probe.on("error", fail);
    probe.listen(0, "127.0.0.1", () => {
      const { port } = probe.address();
      probe.close(() => done(port));
    });
  });

let earlier;
let reference;
let referenceServer;
const servers = [];

beforeAll(async () => {
  earlier = scratch();
  write(earlier, names.oldApp, oldApp);
  write(earlier, names.oldRest, oldRest);
  const bundle = scratch();
  write(bundle, "index.html", page);
  for (const [name, content] of [[names.newApp, newApp], [names.newRest, newRest], [names.lonely, onlyNew]]) {
    write(bundle, name, content);
    write(bundle, `${name}.br`, brotliCompressSync(content));
  }
  await deltaCompressBundle(bundle, [earlier]);
  const port = await freePort();
  reference = `http://127.0.0.1:${port}`;
  referenceServer = spawn(process.execPath, [join(ROOT, "Tools", "bun-server.ts"), bundle, String(port)], {
    env: { ...process.env, SWIFTUIWEB_API_ORIGIN: "", SWIFTUIWEB_API_PATH: "" },
    stdio: ["ignore", "ignore", "ignore"],
  });
  const deadline = Date.now() + 15000;
  for (;;) {
    try {
      await fetch(reference);
      break;
    } catch (error) {
      if (Date.now() > deadline) throw error;
      await new Promise((done) => setTimeout(done, 100));
    }
  }
});

afterAll(() => {
  referenceServer?.kill("SIGTERM");
  servers.forEach((server) => server.stop(true));
  cleanup.forEach((directory) => rmSync(directory, { recursive: true, force: true }));
});

const files = { [names.newApp]: newApp, [names.newRest]: newRest, [names.lonely]: onlyNew };

// A site that answers a difference request as `behaviour` says and everything else with the whole file.
function liar(behaviour) {
  const server = Bun.serve({
    port: 0,
    async fetch(request) {
      const path = new URL(request.url).pathname.slice(1);
      if (path === "") return new Response(page, { headers: { "Content-Type": "text/html" } });
      const content = files[path];
      if (!content) return new Response("not found", { status: 404 });
      const wanted = parseAvailableDictionary(request.headers.get("Available-Dictionary"));
      const headers = { "Content-Type": "application/wasm", Vary: VARY, "Use-As-Dictionary": useAsDictionary(`/${path}`) };
      const reply = wanted ? await behaviour(path, wanted, request, headers) : null;
      return reply ?? new Response(content, { headers });
    },
  });
  servers.push(server);
  return `http://127.0.0.1:${server.port}`;
}

const byModule = (results, module) => results.filter((result) => result.module === module);
const differenceResults = (results) => results.filter((result) => ["correct", "none", "wrong"].includes(result.status));
const quiet = async (action) => {
  const original = console.log;
  const lines = [];
  console.log = (line) => lines.push(line);
  try {
    return { result: await action(), lines };
  } finally {
    console.log = original;
  }
};

describe("arguments", () => {
  test("parses the site, the directory and any number of headers", () => {
    expect(parseArguments(["https://a.example", "dir", "--header", "X-A: 1", "--header", "SwiftUIWeb-Dictionary-Check: 1"])).toEqual({
      site: "https://a.example",
      directory: "dir",
      headers: [["X-A", "1"], ["SwiftUIWeb-Dictionary-Check", "1"]],
    });
    expect(parseArguments(["https://a.example"])).toBeNull();
    expect(parseArguments(["file:///x", "dir"])).toBeNull();
    expect(parseArguments(["https://a.example", "dir", "--header"])).toBeNull();
    expect(parseArguments(["https://a.example", "dir", "--header", "no colon"])).toBeNull();
    expect(parseArguments(["https://a.example", "dir", "--other"])).toBeNull();
    expect(parseHeaderLine("A-B:  v: w ")).toEqual(["A-B", "v: w"]);
  });

  test("wrong arguments exit 2", async () => {
    const original = console.error;
    console.error = () => {};
    try {
      expect(await main([])).toBe(2);
    } finally {
      console.error = original;
    }
  });
});

describe("check-dictionary-host", () => {
  test("against Tools/bun-server.ts: difference served and correct, the ordinary path correct, a module without an earlier one skipped", async () => {
    const { results, exitCode } = await checkHost(reference, earlier);
    expect(exitCode).toBe(0);
    expect(differenceResults(results).map((result) => [result.module, result.from, result.status])).toEqual([
      [names.newApp, names.oldApp, "correct"],
      [names.newRest, names.oldRest, "correct"],
    ]);
    expect(results.filter((result) => result.status === "plain-ok")).toHaveLength(3);
    expect(byModule(results, names.lonely).map((result) => result.status)).toEqual(["plain-ok", "skipped"]);
    expect(describeResult(differenceResults(results)[0])).toContain("difference served and correct");
  });

  test("main prints one line per result and exits 0", async () => {
    const { result, lines } = await quiet(() => main([reference, earlier]));
    expect(result).toBe(0);
    expect(lines.some((line) => line.includes("difference served and correct"))).toBe(true);
    expect(lines.some((line) => line.includes("skipped"))).toBe(true);
  });

  test("a host that says dcb and sends other bytes is WRONG, and the exit code is 1", async () => {
    const origin = liar((path, wanted, request, headers) => new Response(dcbBody(wanted, brotliCompressSync(Buffer.from("not the module"))), { headers: { ...headers, "Content-Encoding": "dcb" } }));
    const { results, exitCode } = await checkHost(origin, earlier);
    expect(exitCode).toBe(1);
    const wrong = differenceResults(results).filter((result) => result.status === "wrong");
    expect(wrong.map((result) => result.module).sort()).toEqual([names.newApp, names.newRest].sort());
    expect(wrong[0].detail).toContain("does not decode");
  });

  test("a dcb body that names another dictionary is WRONG", async () => {
    const origin = liar((path, wanted, request, headers) => new Response(dcbBody("00".repeat(32), brotliCompressSync(files[path])), { headers: { ...headers, "Content-Encoding": "dcb" } }));
    const { results, exitCode } = await checkHost(origin, earlier);
    expect(exitCode).toBe(1);
    expect(differenceResults(results)[0].detail).toContain("header does not name");
  });

  test("a dcb answer without Vary or Use-As-Dictionary is WRONG even when the body is right", async () => {
    const good = await checkHost(reference, earlier);
    const body = new Uint8Array(await (await fetch(`${reference}/${names.newApp}`, { headers: { "Accept-Encoding": "br, dcb", "Available-Dictionary": `:${Buffer.from(await sha256Hex(oldApp), "hex").toString("base64")}:` }, decompress: false })).arrayBuffer());
    expect(good.exitCode).toBe(0);
    const origin = liar((path, wanted) => (path === names.newApp ? new Response(body, { headers: { "Content-Encoding": "dcb", "Content-Type": "application/wasm" } }) : null));
    const { results, exitCode } = await checkHost(origin, earlier);
    expect(exitCode).toBe(1);
    const wrong = byModule(results, names.newApp).find((result) => result.status === "wrong");
    expect(wrong.detail).toContain("Vary does not list Available-Dictionary");
    expect(wrong.detail).toContain("Use-As-Dictionary is missing");
    expect(wrong.detail).not.toContain("decode");
  });

  test("a host that never answers dcb gives no difference served, with its headers, and exit 0", async () => {
    const origin = liar(() => null);
    const { results, exitCode } = await checkHost(origin, earlier);
    expect(exitCode).toBe(0);
    const none = differenceResults(results);
    expect(none.map((result) => result.status)).toEqual(["none", "none"]);
    expect(none[0].detail).toContain("Content-Encoding: (none)");
    expect(none[0].detail).toContain(`Vary: ${VARY}`);
    expect(none[0].detail).toContain('Use-As-Dictionary: match="/app.*.wasm"');
  });

  test("the extra headers go to the difference requests only", async () => {
    const seen = [];
    const origin = liar((path, wanted, request) => {
      seen.push(request.headers.get("SwiftUIWeb-Dictionary-Check"));
      return null;
    });
    await checkHost(origin, earlier, { headers: [["SwiftUIWeb-Dictionary-Check", "1"]] });
    expect(seen).toEqual(["1", "1"]);
  });

  test("a host that breaks the ordinary path is WRONG", async () => {
    const server = Bun.serve({
      port: 0,
      fetch: (request) => (new URL(request.url).pathname === "/" ? new Response(page) : new Response(Buffer.from("corrupted"))),
    });
    servers.push(server);
    const { results, exitCode } = await checkHost(`http://127.0.0.1:${server.port}`, earlier);
    expect(exitCode).toBe(1);
    expect(results.filter((result) => result.status === "plain-wrong")).toHaveLength(3);
  });

  test("a page whose address has a path is checked with the modules at the site's root", async () => {
    const rootPage = `<!doctype html><script>fetch("/${names.newApp}");fetch("/${names.newRest}");fetch("/${names.lonely}")</script>`;
    const server = Bun.serve({
      port: 0,
      fetch(request) {
        const path = new URL(request.url).pathname;
        if (path === "/en/purpose") return new Response(rootPage, { headers: { "Content-Type": "text/html" } });
        const content = files[path.slice(1)];
        return content ? new Response(content) : new Response("not found", { status: 404 });
      },
    });
    servers.push(server);
    const { results, exitCode } = await checkHost(`http://127.0.0.1:${server.port}/en/purpose`, earlier);
    expect(exitCode).toBe(0);
    expect(results.filter((result) => result.status === "plain-ok")).toHaveLength(3);
    expect(differenceResults(results).map((result) => [result.module, result.status])).toEqual([
      [names.newApp, "none"],
      [names.newRest, "none"],
    ]);
  });

  test("an answer in br or gzip that decodes to the module is no difference served, with its coding", async () => {
    for (const [coding, encode] of [["br", brotliCompressSync], ["gzip", gzipSync]]) {
      const origin = liar((path, wanted, request, headers) => new Response(encode(files[path]), { headers: { ...headers, "Content-Encoding": coding } }));
      const { results, exitCode } = await checkHost(origin, earlier);
      expect(exitCode).toBe(0);
      expect(differenceResults(results).map((result) => result.status)).toEqual(["none", "none"]);
      expect(differenceResults(results)[0].detail).toContain(`Content-Encoding: ${coding}`);
    }
  });

  test("an answer in br, gzip or an unknown coding whose bytes are not the module is WRONG, and the coding is named", async () => {
    const other = Buffer.from("not the module");
    const cases = [
      ["br", brotliCompressSync(other)],
      ["gzip", gzipSync(other)],
      ["zstd", files[names.newApp]],
    ];
    for (const [coding, body] of cases) {
      const origin = liar((path, wanted, request, headers) => (path === names.newApp ? new Response(body, { headers: { ...headers, "Content-Encoding": coding } }) : null));
      const { results, exitCode } = await checkHost(origin, earlier);
      expect(exitCode).toBe(1);
      const wrong = byModule(results, names.newApp).find((result) => result.status === "wrong");
      expect(wrong.detail).toContain(`Content-Encoding: ${coding}`);
    }
  });

  test("a dcb answer whose Vary lacks Accept-Encoding is WRONG, naming it, even when the body is right", async () => {
    const body = new Uint8Array(await (await fetch(`${reference}/${names.newApp}`, { headers: { "Accept-Encoding": "br, dcb", "Available-Dictionary": `:${Buffer.from(await sha256Hex(oldApp), "hex").toString("base64")}:` }, decompress: false })).arrayBuffer());
    const origin = liar((path) => (path === names.newApp ? new Response(body, { headers: { "Content-Encoding": "dcb", "Content-Type": "application/wasm", Vary: "Available-Dictionary", "Use-As-Dictionary": useAsDictionary(`/${path}`) } }) : null));
    const { results, exitCode } = await checkHost(origin, earlier);
    expect(exitCode).toBe(1);
    const wrong = byModule(results, names.newApp).find((result) => result.status === "wrong");
    expect(wrong.detail).toContain("Vary does not list Accept-Encoding");
    expect(wrong.detail).not.toContain("does not list Available-Dictionary");
  });

  test("an unreachable host or a page with no module checks nothing and exits 1", async () => {
    const probe = Bun.serve({ port: 0, fetch: () => new Response("") });
    const closed = `http://127.0.0.1:${probe.port}`;
    probe.stop(true);
    expect((await checkHost(closed, earlier)).exitCode).toBe(1);
    const empty = Bun.serve({ port: 0, fetch: () => new Response("<html></html>") });
    servers.push(empty);
    const outcome = await checkHost(`http://127.0.0.1:${empty.port}`, earlier);
    expect(outcome.exitCode).toBe(1);
    expect(outcome.message).toContain("nothing checked");
  });
});
