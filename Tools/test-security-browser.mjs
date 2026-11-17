#!/usr/bin/env bun
// The web keychain in a real browser, in the Embedded worker runtime.
//
// SecurityExample stores a secret with SecItemAdd on its first load. The test expects SecItemCopyMatching
// to find it again after a reload, in a new tab and after the browser restarts on the same profile;
// reads IndexedDB directly to prove it holds only a non-extractable AES-GCM key (encrypt/decrypt) and
// ciphertext; deletes the item; and loads the page from an insecure origin, where Web Crypto is
// missing and the calls answer errSecNotAvailable (-25291).
// SWIFTUIWEB_BROWSER_ENGINE selects chromium (default), webkit or firefox.
//
// Environment: SECURITY_BUNDLE (default .build/browser/SecurityExample), SECURITY_PORT (default 8104).
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { engineName, launch, launchPersistent, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

const BUNDLE = resolve(process.env.SECURITY_BUNDLE ?? join(ROOT, ".build/browser/SecurityExample"));
const PORT = Number(process.env.SECURITY_PORT ?? "8104");

const INSPECT_INDEXEDDB = `async () => {
  const db = await new Promise((resolve, reject) => {
    const request = indexedDB.open('swui:security:keychain');
    request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error);
  });
  const read = (method, arg) => new Promise((resolve) => {
    const request = db.transaction('records').objectStore('records')[method](arg);
    request.onsuccess = () => resolve(request.result);
  });
  const keys = await read('getAllKeys');
  const key = await read('get', 'key');
  const items = [], fields = [];
  for (const name of keys.filter(k => k.startsWith('item:'))) {
    const record = await read('get', name);
    items.push(new TextDecoder().decode(record.sealed));
    fields.push(Object.keys(record).sort().join(','));
  }
  db.close();
  return { extractable: key.extractable, algorithm: key.algorithm.name, length: key.algorithm.length,
           usages: [...key.usages].sort(), fields, items };
}`;

/**
 * Every page a context opens (tab B and the new tab included) reports into `errors`: an uncaught exception, and a
 * runtime failure the session reports on the console (a trap in a call the page made from an event, such as the
 * cookie-change export), with the page it came from.
 */
function collectErrors(context, errors) {
  context.on("page", (page) => {
    const where = () => { try { return new URL(page.url()).search || "/"; } catch { return "?"; } };
    page.on("pageerror", (error) => errors.push(`${where()}: ${error.message}`));
    page.on("console", (message) => {
      if (message.type() === "error" && message.text().startsWith("[SwiftUIWeb]")) errors.push(`${where()}: ${message.text()}`);
    });
  });
}

/**
 * Tab B writes and then expires a cookie; tab A (`page`, not reloaded) must show each change.
 *
 * Chromium reports each write through cookieStore; WebKit has no cookieStore, so tab A hears the BroadcastChannel
 * ping that the writing tab posts after a write, as the runtime does. Tab B writes with a plain script.
 */
async function crossTabRefresh(context, page, url) {
  await page.evaluate(() => { window.__tabA = "same page"; });
  const other = await context.newPage();
  await other.goto(url);
  await other.getByText("Found: s3cret-from-swift").waitFor({ timeout: 30_000 });
  await other.evaluate(() => { window.__cookieChannel = new BroadcastChannel("cookie-changes"); document.cookie = "swui_remote=from-tab-b; path=/"; window.__cookieChannel.postMessage("changed"); });
  await page.getByText("Cookies: swui_pref=compact; swui_remote=from-tab-b", { exact: true }).waitFor({ timeout: 30_000 });
  await other.evaluate(() => { document.cookie = "swui_remote=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT"; window.__cookieChannel.postMessage("changed"); });
  await page.getByText("Cookies: swui_pref=compact", { exact: true }).waitFor({ timeout: 30_000 });
  assert.equal(await page.evaluate(() => window.__tabA), "same page", "tab A must not have reloaded");
  await other.close();
}

await runSuite(async () => {
  if (!existsSync(join(BUNDLE, "index.html"))) {
    throw new Error(`index.html missing from ${BUNDLE}; build it with make security-browser-test`);
  }
  const { base, stop } = await serveBundle({
    bundle: BUNDLE,
    port: PORT,
    logName: "security-browser-server",
    required: ["index.html"],
  });
  const worker = `${base}/?render-in-worker=1`;
  const mainUrl = `${base}/?render-in-worker=0`;
  const profile = mkdtempSync(join(tmpdir(), "swui-security-profile-"));
  let context;
  let browser;
  const errors = [];
  try {
    // Counts the workers each page constructs, so the cross-tab check can tell the two modes apart.
    context = await launchPersistent(profile);
    collectErrors(context, errors);
    await context.addInitScript("window.__workers = 0; const NativeWorker = window.Worker; window.Worker = function (...args) { window.__workers++; return new NativeWorker(...args); };");
    let page = await context.newPage();
    // `render-in-worker=1` keeps the app in the worker on every engine: WebKit may otherwise fall back to the main
    // thread, which has no cookie mirror to refresh.
    await page.goto(worker);
    await page.getByText("Added").waitFor({ timeout: 30_000 });
    // HTTPCookieStorage writes the script-visible cookie to document.cookie and reads it back; the HttpOnly
    // cookie is refused by the jar, so neither script nor Swift can see it.
    await page.getByText("Cookies: swui_pref=compact", { exact: true }).waitFor({ timeout: 30_000 });
    assert.ok((await page.evaluate(() => document.cookie)).includes("swui_pref=compact"));
    assert.ok(!(await page.evaluate(() => document.cookie)).includes("swui_session"));

    // Two tabs, one profile: tab B writes and then expires a cookie; tab A (worker mode, the same page, not
    // reloaded) must read each change through HTTPCookieStorage without a reload.
    await crossTabRefresh(context, page, worker);
    assert.ok((await page.evaluate(() => window.__workers)) > 0, "worker mode must construct the worker");

    // The same two-tab check on the main thread (`render-in-worker=0`): the page reads its own jar and must not load
    // the worker at all.
    const mainPage = await context.newPage();
    await mainPage.goto(mainUrl);
    await mainPage.getByText("Cookies: swui_pref=compact", { exact: true }).waitFor({ timeout: 30_000 });
    await crossTabRefresh(context, mainPage, mainUrl);
    assert.equal(await mainPage.evaluate(() => window.__workers), 0, "main-thread mode must not construct a worker");
    await mainPage.close();

    await page.reload();
    await page.getByText("Found: s3cret-from-swift").waitFor({ timeout: 30_000 });

    const tab = await context.newPage();
    await tab.goto(base);
    await tab.getByText("Found: s3cret-from-swift").waitFor({ timeout: 30_000 });
    await tab.close();

    const stored = await page.evaluate(`(${INSPECT_INDEXEDDB})()`);
    assert.ok(stored.extractable === false && stored.algorithm === "AES-GCM" && stored.length === 256, JSON.stringify(stored));
    assert.deepEqual(stored.usages, ["decrypt", "encrypt"], JSON.stringify(stored));
    assert.deepEqual(stored.fields, ["iv,sealed,v"], JSON.stringify(stored));
    assert.ok(stored.items.every((item) => !item.includes("s3cret") && !item.includes("swiftuiweb.example")), JSON.stringify(stored));
    assert.ok(!(await page.evaluate(() => JSON.stringify({ ...localStorage }) + JSON.stringify({ ...sessionStorage }) + document.cookie)).includes("s3cret"));
    await context.close();
    context = undefined;

    // The browser restarts on the same profile.
    context = await launchPersistent(profile);
    collectErrors(context, errors);
    page = await context.newPage();
    await page.goto(base);
    await page.getByText("Found: s3cret-from-swift").waitFor({ timeout: 30_000 });
    await page.getByRole("button", { name: "Forget" }).click();
    await page.getByText("Forgotten").waitFor({ timeout: 10_000 });
    await page.reload();
    await page.getByText("Added").waitFor({ timeout: 30_000 });
    await context.close();
    context = undefined;

    // An insecure origin (plain HTTP, not localhost) has no Web Crypto.
    browser = await launch();
    const insecure = await browser.newContext();
    collectErrors(insecure, errors);
    await insecure.route("http://keychain.test/**", async (route) => {
      const response = await insecure.request.fetch(route.request().url().replace("http://keychain.test", base));
      await route.fulfill({ response });
    });
    page = await insecure.newPage();
    await page.goto("http://keychain.test/");
    assert.equal(await page.evaluate(() => window.isSecureContext), false);
    await page.getByText("Not available: -25291").waitFor({ timeout: 30_000 });
    await browser.close();
    browser = undefined;
    assert.deepEqual(errors, [], JSON.stringify(errors));
    console.log(`PASS web keychain: reload, new tab, browser restart, non-extractable AES-GCM at rest, delete, insecure origin (${engineName()})`);
  } finally {
    await context?.close().catch(() => {});
    await browser?.close().catch(() => {});
    await stop();
    rmSync(profile, { recursive: true, force: true });
  }
});
