// Tests for Tools/fetch-live-modules.mjs against a local Bun.serve site: a page, two scripts in a chain and two modules.
// Run: bun test ./Tools/test-fetch-live-modules.mjs
import { afterAll, describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { sha256Hex } from "./dictionary-transport.mjs";
import { fetchLiveModules, main, moduleReferences, scriptReferences } from "./fetch-live-modules.mjs";

const bytes = (text) => new TextEncoder().encode(text.repeat(50));
const named = async (stem, content) => `${stem}.${(await sha256Hex(content)).slice(0, 8)}.wasm`;

const appBytes = bytes("first module ");
const restBytes = bytes("second module ");
const appName = await named("app", appBytes);
const restName = await named("app-rest", restBytes);

const servers = [];
function serve(routes) {
  const server = Bun.serve({
    port: 0,
    fetch(request) {
      const route = routes[new URL(request.url).pathname];
      if (route === undefined) return new Response("not found", { status: 404 });
      return typeof route === "function" ? route(request) : new Response(route);
    },
  });
  servers.push(server);
  return `http://127.0.0.1:${server.port}`;
}
afterAll(() => servers.forEach((server) => server.stop(true)));

const scratch = () => mkdtempSync(join(tmpdir(), "fetch-live-modules-"));
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

// The page names the first module and a script; that script names a second script; the second names the other module.
const site = (extra = {}) =>
  serve({
    "/": `<html><script src="/index.11111111.js"></script><link rel="preload" href="${appName}"></html>`,
    "/index.11111111.js": `import("./chunk.22222222.js"); fetch("https://cdn.example/other.12345678.wasm")`,
    "/chunk.22222222.js": `fetch("./${restName}")`,
    [`/${appName}`]: appBytes,
    [`/${restName}`]: restBytes,
    ...extra,
  });

describe("reading names", () => {
  test("finds modules and scripts as written, and not the ones of another origin or longer names", () => {
    const text = `a "app.0123abcd.wasm" b './x/app-rest.0123abcd.wasm' c /m/app.0123abcd.wasm d https://cdn.example/app.0123abcd.wasm e app.0123abcdef.wasm g "./index.0123abcd.js" "/c.0123abcd.js" "https://cdn.example/d.0123abcd.js"`;
    expect(moduleReferences(text)).toEqual(["app.0123abcd.wasm", "./x/app-rest.0123abcd.wasm", "/m/app.0123abcd.wasm"]);
    expect(scriptReferences(text)).toEqual(["./index.0123abcd.js", "/c.0123abcd.js"]);
  });
});

describe("fetch-live-modules", () => {
  test("downloads both modules, the second named inside a script of a chain, and prints one line each", async () => {
    const origin = site();
    const directory = scratch();
    const { result, lines } = await quiet(() => main([origin, directory]));
    expect(result).toBe(0);
    expect(readdirSync(directory).sort()).toEqual([restName, appName].sort());
    expect(readFileSync(join(directory, appName))).toEqual(Buffer.from(appBytes));
    expect(lines.filter((line) => line.startsWith("live module ") && !line.includes("dropped"))).toHaveLength(2);
    expect(lines.join("\n")).toContain(`live module ${appName} (${appBytes.length} bytes)`);
  });

  test("drops a module whose bytes do not match its name, and says so", async () => {
    const origin = site({ [`/${appName}`]: bytes("other bytes ") });
    const directory = scratch();
    const outcome = await fetchLiveModules(origin, directory);
    expect(outcome.kept.map((item) => item.path)).toEqual([restName]);
    expect(outcome.dropped[0].path).toBe(appName);
    expect(outcome.dropped[0].reason).toContain("SHA-256");
    expect(existsSync(join(directory, appName))).toBe(false);
  });

  test("removes the module files a previous run left, and nothing else", async () => {
    const directory = scratch();
    writeFileSync(join(directory, "app.deadbeef.wasm"), "old");
    writeFileSync(join(directory, "notes.txt"), "keep");
    await fetchLiveModules(site(), directory);
    expect(existsSync(join(directory, "app.deadbeef.wasm"))).toBe(false);
    expect(readFileSync(join(directory, "notes.txt"), "utf8")).toBe("keep");
    expect(existsSync(join(directory, appName))).toBe(true);
  });

  test("a root-relative module is requested at the site's origin, though the page's address has a path", async () => {
    const origin = serve({
      "/en/purpose": `<html><link rel="preload" href="/${appName}"></html>`,
      [`/${appName}`]: appBytes,
    });
    const directory = scratch();
    const outcome = await fetchLiveModules(`${origin}/en/purpose`, directory);
    expect(outcome.dropped).toEqual([]);
    expect(outcome.kept.map((item) => item.path)).toEqual([appName]);
    expect(readFileSync(join(directory, appName))).toEqual(Buffer.from(appBytes));
  });

  test("the page's <base href> is the base its references resolve against, as in a browser", async () => {
    // Quoted with either mark, or unquoted, as HTML allows.
    for (const base of [`<base href="/">`, `<base href='/'>`, `<base href=/>`, `<base target=_self href=/ >`]) {
      const origin = serve({
        "/en/purpose": `<html>${base}<link rel="preload" href="./${appName}"></html>`,
        [`/${appName}`]: appBytes,
      });
      const outcome = await fetchLiveModules(`${origin}/en/purpose`, scratch());
      expect(outcome.dropped).toEqual([]);
      expect(outcome.kept.map((item) => item.path)).toEqual([appName]);
    }
  });

  test("a module named in a script is resolved against the script's address, and kept under its path from the origin root", async () => {
    const origin = serve({
      "/": `<script src="/js/index.11111111.js"></script>`,
      "/js/index.11111111.js": `import("./chunk.22222222.js")`,
      "/js/chunk.22222222.js": `fetch("./${restName}")`,
      [`/js/${restName}`]: restBytes,
    });
    const directory = scratch();
    const outcome = await fetchLiveModules(origin, directory);
    expect(outcome.dropped).toEqual([]);
    expect(outcome.kept.map((item) => item.path)).toEqual([`js/${restName}`]);
    expect(readFileSync(join(directory, "js", restName))).toEqual(Buffer.from(restBytes));
  });

  test("a page with no module gives a message, exit 0 and nothing written", async () => {
    const origin = serve({ "/": "<html>nothing here</html>" });
    const directory = join(scratch(), "live");
    const { result, lines } = await quiet(() => main([origin, directory]));
    expect(result).toBe(0);
    expect(lines.join("\n")).toContain("no content-hashed module");
    expect(existsSync(directory)).toBe(false);
  });

  test("an error status and an unreachable origin give a message and exit 0 with the directory untouched", async () => {
    const directory = scratch();
    writeFileSync(join(directory, "app.deadbeef.wasm"), "old");
    const failing = serve({ "/": () => new Response("down", { status: 503 }) });
    const first = await quiet(() => main([failing, directory]));
    expect(first.result).toBe(0);
    expect(first.lines.join("\n")).toContain("503");
    const probe = Bun.serve({ port: 0, fetch: () => new Response("") });
    const closed = `http://127.0.0.1:${probe.port}`;
    probe.stop(true);
    const second = await quiet(() => main([closed, directory]));
    expect(second.result).toBe(0);
    expect(second.lines.join("\n")).toContain("cannot be reached");
    expect(readdirSync(directory)).toEqual(["app.deadbeef.wasm"]);
  });

  test("a request that takes longer than the timeout is a message, not a failure", async () => {
    const origin = serve({ "/": () => new Promise((resolve) => setTimeout(() => resolve(new Response("late")), 1500)) });
    const outcome = await fetchLiveModules(origin, scratch(), { timeoutMs: 100 });
    expect(outcome.kept).toEqual([]);
    expect(outcome.message).toContain("no module fetched");
  });

  test("caps the files read", async () => {
    const seen = [];
    const origin = serve({
      "/": `<script src="/a.00000001.js"></script><script src="/b.00000002.js"></script><script src="/c.00000003.js"></script>`,
      "/a.00000001.js": () => (seen.push("a"), new Response("")),
      "/b.00000002.js": () => (seen.push("b"), new Response("")),
      "/c.00000003.js": () => (seen.push("c"), new Response("")),
    });
    await fetchLiveModules(origin, scratch(), { maxFiles: 3 });
    expect(seen).toEqual(["a", "b"]);
  });

  test("wrong arguments exit 2, and only http and https URLs are taken", async () => {
    const errors = [];
    const original = console.error;
    console.error = (line) => errors.push(line);
    try {
      expect(await main([])).toBe(2);
      expect(await main(["https://example.com"])).toBe(2);
      expect(await main(["file:///etc/passwd", scratch()])).toBe(2);
      expect(await main(["ftp://example.com", scratch()])).toBe(2);
      expect(await main(["not a url", scratch()])).toBe(2);
      expect(await main(["http://a.example", "dir", "extra"])).toBe(2);
    } finally {
      console.error = original;
    }
    expect(errors[0]).toContain("usage");
  });
});
