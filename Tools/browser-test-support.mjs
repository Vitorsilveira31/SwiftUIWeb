// Shared support for the Playwright browser suites (Node/bun): the browser engine launch and the server start-up
// every suite needs.
//
// SWIFTUIWEB_BROWSER_ENGINE selects chromium (the default), webkit or firefox, so the same suite can run against
// Safari's engine; a suite that must pin an engine passes `{ engine }` to launch(). CHROMIUM_PATH, or a `chromium`
// on PATH, overrides the Chromium binary Playwright would download; WEBKIT_PATH (a Playwright `pw_run.sh`, for example one
// from another revision in ~/Library/Caches/ms-playwright) does the same for WebKit.
//
// Playwright for Node evaluates a STRING passed to page.evaluate / locator.evaluate / waitForFunction as an expression:
// a string that is an arrow function is not called (it is evaluated as an expression). Pass a real function, or wrap the string
// as `(${code})()`.
//
// waitForFunction is the exception to "same as Playwright": Playwright runs it through eval() inside the page, and a
// sealed bundle's Content-Security-Policy has no 'unsafe-eval', so on those pages it throws EvalError. Every page a
// launch() browser or context opens gets a waitForFunction that polls with page.evaluate (which goes through the
// debugging protocol, not through the page's policy) and keeps the signature: (function | expression, arg, { timeout,
// polling }). It resolves once the predicate is truthy; the returned handle of Playwright's version is not provided.
import { spawn, spawnSync } from "node:child_process";
import { closeSync, existsSync, mkdirSync, openSync } from "node:fs";
import { createServer } from "node:net";
import { bundleFilePath } from "./hash-release-bundle.mjs";
import { isLoopbackHost } from "./dev-server-policy.mjs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium, firefox, webkit } from "playwright";

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const ENGINES = { chromium, webkit, firefox };

export function engineName() {
  const name = (process.env.SWIFTUIWEB_BROWSER_ENGINE ?? "chromium").trim().toLowerCase() || "chromium";
  if (!(name in ENGINES)) {
    throw new Error(`SWIFTUIWEB_BROWSER_ENGINE must be one of ${Object.keys(ENGINES).join(", ")}, not '${name}'`);
  }
  return name;
}

function resolveLaunch(options) {
  const { engine = engineName(), ...rest } = options;
  if (!(engine in ENGINES)) throw new Error(`unknown browser engine '${engine}'`);
  let launchOptions = rest;
  if (engine === "chromium") {
    const which = spawnSync("which", ["chromium"], { encoding: "utf8" });
    const executable = process.env.CHROMIUM_PATH || (which.status === 0 ? which.stdout.trim() : "");
    if (executable && launchOptions.executablePath === undefined) launchOptions = { ...launchOptions, executablePath: executable };
    // A machine without a usable GPU (a sandbox, a CI runner) otherwise fails to create WebGL contexts; this lets Chromium
    // fall back to its software renderer, as a headless browser on a desktop does.
    launchOptions = { ...launchOptions, args: ["--enable-unsafe-swiftshader", ...(launchOptions.args ?? [])] };
  }
  if (engine === "webkit" && process.env.WEBKIT_PATH && launchOptions.executablePath === undefined) {
    launchOptions = { ...launchOptions, executablePath: process.env.WEBKIT_PATH };
  }
  return { type: ENGINES[engine], options: { headless: true, ...launchOptions } };
}

/** Polls `predicate` in the page until it is truthy; see the note at the top of this file. */
export async function waitForPage(page, predicate, arg, { timeout = 30_000, polling = 100 } = {}) {
  const deadline = timeout === 0 ? Infinity : Date.now() + timeout;
  for (;;) {
    if (await page.evaluate(predicate, arg)) return;
    if (Date.now() > deadline) {
      const error = new Error(`waitForFunction: Timeout ${timeout}ms exceeded.`);
      error.name = "TimeoutError";
      throw error;
    }
    await new Promise((done) => setTimeout(done, typeof polling === "number" ? Math.max(polling, 10) : 25));
  }
}

// SWIFTUIWEB_LAYOUT_VERIFY=1 turns on the CSS layout's equivalence checks (`window.__layoutVerify`: every incremental analysis
// is compared with one from scratch) in every page a suite opens, and prints each divergence the page reports, so the whole
// browser matrix doubles as a check of the incremental paths.
const VERIFY_LAYOUT = process.env.SWIFTUIWEB_LAYOUT_VERIFY === "1";
// SWIFTUIWEB_SYNC_VERIFY=1 runs every post-patch sync its gate skips anyway and prints what it would have written or sent
// (`window.__syncVerify`, Tools/embedded-dom.js); SWIFTUIWEB_SYNC_GATES=0 runs every sync after every commit, as before the gates.
const VERIFY_SYNCS = process.env.SWIFTUIWEB_SYNC_VERIFY === "1";
const SYNC_GATES = process.env.SWIFTUIWEB_SYNC_GATES !== "0";

// Publications are binary streams (Documentation/Architecture/BINARY_PATCHES.md). SWIFTUIWEB_BINARY=verify has the page compare
// the DOM it built with a reference encoding of the same tree (`window.__binaryVerify`) and prints each difference it reports. SWIFTUIWEB_BINARY=full
// does that for every publication: the page never acknowledges one (`window.__fullPublish`), so each is a full binary stream.
const BINARY = process.env.SWIFTUIWEB_BINARY ?? "";
// SWIFTUIWEB_BINARY_SHAPES=0 builds the subtrees of binary publications in full instead of as shapes.
const BINARY_SHAPES = process.env.SWIFTUIWEB_BINARY_SHAPES !== "0";
if (!["", "verify", "full"].includes(BINARY)) throw new Error("SWIFTUIWEB_BINARY must be verify or full (the HTML transport is gone)");

// The servers serveBundle started and has not stopped, which a renderer crash stops before the suite exits.
const runningServers = new Set();

function instrumentPage(page) {
  page.waitForFunction = (predicate, arg, options) => waitForPage(page, predicate, arg, options);
  // After a renderer crash every call on the page waits forever (waitForPage's evaluate included), so the suite would hang
  // instead of failing.
  page.on("crash", () => {
    console.error(`renderer crashed (${engineName()}) on ${page.url()}`);
    for (const server of runningServers) server.kill("SIGKILL");
    process.exit(1);
  });
  if (!BINARY_SHAPES) page.addInitScript(() => { window.__binaryShapes = false; }).catch(() => {});
  if (BINARY !== "") {
    page.addInitScript((mode) => { window.__binaryVerify = true; if (mode === "full") window.__fullPublish = true; }, BINARY).catch(() => {});
    // `page.__binaryExpected` is set by a check that makes the verification report on purpose: its difference is labelled as such.
    page.on("console", (message) => { if (message.text().startsWith("binary verify:")) console.error(page.__binaryExpected ? "BINARY-EXPECTED" : "BINARY-MISMATCH", message.text().slice(0, 400)); });
  }
  if (!SYNC_GATES) page.addInitScript(() => { window.__syncGates = false; }).catch(() => {});
  if (VERIFY_SYNCS && !page.__syncVerify) {
    page.__syncVerify = true;
    page.addInitScript(() => { window.__syncVerify = true; }).catch(() => {});
    page.on("console", (message) => { if (message.text().startsWith("sync verify:")) console.error("SYNC-MISMATCH", message.text().slice(0, 400)); });
  }
  if (VERIFY_LAYOUT && !page.__layoutVerify) {
    page.__layoutVerify = true;
    page.addInitScript(() => { window.__layoutVerify = true; }).catch(() => {});
    page.on("console", (message) => { if (message.text().includes("incremental layout")) console.error("LAYOUT-MISMATCH", message.text().slice(0, 300)); });
  }
  return page;
}

function instrumentContext(context) {
  for (const page of context.pages()) instrumentPage(page);
  context.on("page", instrumentPage);
  const newPage = context.newPage.bind(context);
  context.newPage = async (...args) => instrumentPage(await newPage(...args));
  return context;
}

function instrumentBrowser(browser) {
  const newContext = browser.newContext.bind(browser);
  browser.newContext = async (...args) => instrumentContext(await newContext(...args));
  const newPage = browser.newPage.bind(browser);
  browser.newPage = async (...args) => instrumentPage(await newPage(...args));
  return browser;
}

/** A browser of the selected engine (or of `options.engine`). */
export async function launch(options = {}) {
  const { type, options: launchOptions } = resolveLaunch(options);
  return instrumentBrowser(await type.launch(launchOptions));
}

/** A browser with a profile on disk, so a test can close it and start it again. */
export async function launchPersistent(userDataDir, options = {}) {
  const { type, options: launchOptions } = resolveLaunch(options);
  return instrumentContext(await type.launchPersistentContext(userDataDir, launchOptions));
}

/** A TCP port nothing is listening on right now. */
export function freePort() {
  return new Promise((resolvePort, reject) => {
    const probe = createServer();
    probe.once("error", reject);
    probe.listen(0, "127.0.0.1", () => {
      const { port } = probe.address();
      probe.close(() => resolvePort(port));
    });
  });
}

const answers = async (base) => {
  try {
    const response = await fetch(base, { signal: AbortSignal.timeout(400) });
    await response.arrayBuffer();
    return true;
  } catch {
    return false;
  }
};

/**
 * Serves a built bundle with Tools/bun-server.ts and resolves once it answers.
 * Returns { base, port, stop }. When something already answers on `port` (another suite running at the same time, or a
 * stale server, which would otherwise pass the readiness check) the server takes a free port instead. Throws when the
 * bundle lacks one of `required`, or when the server exits or never starts.
 * `logName: null` discards the server output.
 */
export async function serveBundle({ bundle, port, logName = "browser-test-server", required = ["app.wasm", "index.html", "index.js"] }) {
  const dir = resolve(bundle);
  // A release bundle names its framework files by content (app.3f9a1c2e.wasm); a name is present under either form.
  for (const name of required) {
    if (!bundleFilePath(dir, name)) throw new Error(`${name} missing from ${dir}`);
  }
  mkdirSync(join(ROOT, ".build"), { recursive: true });
  // Suites run side by side, and two can ask for the same fixed port: when it is taken, or the server loses the race
  // for it, the next try takes a free port (and its own log, so the other suite keeps its log).
  for (let tries = 0; tries < 3; tries++) {
    if (!port || (await answers(`http://127.0.0.1:${port}`))) {
      port = await freePort();
      if (logName !== null) logName = `${logName}-${port}`;
    }
    const started = await startServer(dir, port, logName);
    if (started) return started;
    port = 0;
  }
  throw new Error(`${logName ?? "browser test"} server exited`);
}

/** Starts Tools/bun-server.ts on `port`; null when the server exits before it answers (the port was taken). */
async function startServer(dir, port, logName) {
  const base = `http://127.0.0.1:${port}`;
  const log = logName === null ? null : openSync(join(ROOT, ".build", `${logName}.log`), "w");
  const server = spawn(process.execPath, [join(ROOT, "Tools/bun-server.ts"), dir, String(port)], { stdio: ["ignore", log ?? "ignore", log ?? "ignore"] });
  runningServers.add(server);
  let stopped = false;
  const stop = async () => {
    if (stopped) return;
    stopped = true;
    runningServers.delete(server);
    server.kill("SIGTERM");
    await Promise.race([new Promise((done) => server.once("exit", done)), new Promise((done) => setTimeout(done, 5000))]);
    if (server.exitCode === null) server.kill("SIGKILL");
    if (log !== null) closeSync(log);
  };
  for (let attempt = 0; attempt < 100; attempt++) {
    if (server.exitCode !== null) {
      await stop();
      return null;
    }
    if (await answers(base)) {
      if (server.exitCode !== null) {
        await stop();
        return null;
      }
      return { base, port, stop };
    }
    await new Promise((done) => setTimeout(done, 100));
  }
  await stop();
  throw new Error(`${logName ?? "browser test"} server did not start`);
}

/**
 * Serves a directory as static files. `port` 0 picks a free port.
 * Returns { base, port, stop, close }. `/` serves index.html, query strings are ignored.
 */
export function serveStatic(directory, { port = 0 } = {}) {
  const dir = resolve(directory);
  const server = Bun.serve({
    port,
    hostname: "127.0.0.1",
    async fetch(request) {
      // Same DNS-rebinding guard as the dev server: only loopback host names are served.
      if (!isLoopbackHost(request.url)) return new Response("forbidden", { status: 403 });
      let pathname;
      try { pathname = decodeURIComponent(new URL(request.url).pathname); } catch { return new Response("bad request", { status: 400 }); }
      const target = resolve(dir, "." + (pathname.endsWith("/") ? `${pathname}index.html` : pathname));
      if (target !== dir && !target.startsWith(dir + "/")) return new Response("forbidden", { status: 403 });
      const file = Bun.file(target);
      return (await file.exists()) ? new Response(file) : new Response("not found", { status: 404 });
    },
  });
  const stop = async () => { await server.stop(true); };
  return { base: `http://127.0.0.1:${server.port}`, port: server.port, stop, close: stop };
}

/** Same as serveStatic(directory, { port }), for suites written as `await serveDirectory(dir, port)`. */
export async function serveDirectory(directory, port = 0) {
  return serveStatic(directory, { port });
}

/** Runs a suite: prints the failure and sets a non-zero exit code instead of leaving an unhandled rejection. */
export async function runSuite(main) {
  try {
    await main();
  } catch (error) {
    console.error(error instanceof Error ? (error.stack ?? error.message) : error);
    process.exitCode = 1;
  }
}
