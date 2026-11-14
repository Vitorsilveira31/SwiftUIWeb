#!/usr/bin/env bun
// Mailo (Examples/Mailo) in a real browser against the mock API (Tools/mock-jsonplaceholder.mjs), in the Worker and on the main thread:
//
//   * the inbox lists the received messages, newest first, with their senders and the unread count; the pages move on;
//   * a message opens in the reading pane with its thread of replies; a star shows in the Starred folder;
//   * a message written in the compose sheet goes to Sent and the service keeps it; a reply is posted and kept;
//   * a search asks the service and says when nothing matches;
//   * a deleted message goes to the Trash, and a message deleted from the Trash is gone for good;
//   * on a phone a message replaces the list, with a way back to it;
//   * nothing reaches the network but the page's own origin, and no page errors.
// Engine: SWIFTUIWEB_BROWSER_ENGINE. Bundle: MAILO_BUNDLE (default .build/browser/Mailo).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { engineName, freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";
import { createMockApi } from "./mock-api/server.mjs";

const BUNDLE = resolve(process.env.MAILO_BUNDLE ?? join(ROOT, ".build/browser/Mailo"));

async function open(browser, base, query, viewport = { width: 1280, height: 900 }) {
  const context = await browser.newContext({ viewport, locale: "en-US" });
  const page = await context.newPage();
  const errors = [];
  const foreign = [];
  page.on("pageerror", (error) => errors.push(String(error)));
  // The Worker's own script is a `blob:` of the page's origin.
  page.on("request", (request) => { if (!request.url().startsWith(base) && !request.url().startsWith(`blob:${base}`) && !request.url().startsWith("data:")) foreign.push(request.url()); });
  await page.goto(`${base}/${query}`, { waitUntil: "domcontentloaded" });
  await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 60_000 });
  return { context, page, errors, foreign };
}

const json = (base, path) => fetch(`${base}${path}`).then((response) => response.json());
const bodyText = (page) => page.evaluate(() => document.body.innerText);

async function waitForText(page, text, timeout = 15_000) {
  await page.waitForFunction((wanted) => document.body.innerText.includes(wanted), text, { timeout });
}

async function waitForAbsent(page, text, timeout = 15_000) {
  await page.waitForFunction((unwanted) => !document.body.innerText.includes(unwanted), text, { timeout });
}

/// Polls a condition from Node: the service is asked directly, not from the page.
async function waitUntil(condition, message, timeout = 15_000) {
  const deadline = Date.now() + timeout;
  while (!(await condition())) {
    if (Date.now() > deadline) throw new Error(message);
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}

/// The newest message of the inbox, and who wrote it, from the service itself.
async function newestReceived(base) {
  const [post] = await json(base, "/api/posts?userId_ne=1&_sort=id&_order=desc&_limit=1");
  const user = await json(base, `/api/users/${post.userId}`);
  return { post, user };
}

async function checkInbox(page, base) {
  const { post, user } = await newestReceived(base);
  await waitForText(page, user.name);
  await waitForText(page, post.title);
  await waitForText(page, "1-20 of 90");
  assert.ok(await page.evaluate(() => document.body.innerText.includes("Inbox")), "the sidebar has no Inbox");
}

async function checkReadAndStar(page, base) {
  const { post } = await newestReceived(base);
  await page.getByText(post.title).first().click();
  await waitForText(page, "Replies");
  await waitForAbsent(page, "Loading replies…");
  await page.locator('[aria-label="Star"]').first().click();
  await page.locator('[aria-label="Remove star"]').first().waitFor({ timeout: 10_000 });
  await page.getByRole("button", { name: "Starred", exact: true }).click();
  await waitForText(page, post.title);
  await waitForText(page, "1-1 of 1");
  await page.getByRole("button", { name: "Inbox", exact: false }).first().click();
  await waitForText(page, "1-20 of 90");
}

async function checkCompose(page, base) {
  const before = (await json(base, "/api/posts?userId=1")).length;
  await page.getByRole("button", { name: "Compose", exact: true }).first().click();
  await page.getByPlaceholder("Recipient address").fill("bruno.barros@example.test");
  await page.getByPlaceholder("Subject").fill("Hello from the browser test");
  await page.locator(".sheet-content textarea").fill("Sent by the browser test.");
  await page.getByRole("button", { name: "Send", exact: true }).click();
  await page.waitForFunction(() => !document.querySelector(".sheet-content"), undefined, { timeout: 15_000 });
  await waitUntil(async () => (await json(base, "/api/posts?userId=1")).length === before + 1, "the service did not keep the message");
  await page.getByRole("button", { name: "Sent", exact: true }).click();
  await waitForText(page, "Hello from the browser test");
  await page.getByRole("button", { name: "Inbox", exact: false }).first().click();
  await waitForText(page, "1-20 of 90");
}

async function checkReply(page, base) {
  const { post } = await newestReceived(base);
  const before = Number(await fetch(`${base}/api/comments?_limit=1`).then((response) => response.headers.get("x-total-count")));
  await page.getByText(post.title).first().click();
  await waitForAbsent(page, "Loading replies…");
  await page.getByPlaceholder("Write a reply…").fill("Thanks, see you there");
  await page.getByRole("button", { name: "Reply", exact: true }).click();
  await waitForText(page, "Thanks, see you there");
  const after = Number(await fetch(`${base}/api/comments?_limit=1`).then((response) => response.headers.get("x-total-count")));
  assert.equal(after, before + 1, "the service did not keep the reply");
}

async function checkDeleteAndTrash(page, base) {
  const { post } = await newestReceived(base);
  await page.getByRole("button", { name: "Inbox", exact: false }).first().click();
  await waitForText(page, "1-20 of 90");
  await page.locator('[aria-label="Select message"]').first().click();
  await page.getByRole("button", { name: "Delete", exact: true }).click();
  await waitForText(page, "1-20 of 89");
  await page.getByRole("button", { name: "Trash", exact: true }).click();
  await waitForText(page, post.title);
  await page.locator('[aria-label="Select message"]').first().click();
  await page.getByRole("button", { name: "Delete", exact: true }).click();
  await waitForText(page, "Nothing in Trash");
  const gone = await fetch(`${base}/api/posts/${post.id}`).then((response) => response.status);
  assert.equal(gone, 404, "the message was not deleted for good");
}

async function checkSearch(page) {
  await page.getByRole("button", { name: "Inbox", exact: false }).first().click();
  await waitForText(page, "1-20 of 89");
  await page.getByPlaceholder("Search mail").fill("zzzzqqqq");
  await page.getByPlaceholder("Search mail").press("Enter");
  await waitForText(page, "Nothing in Inbox");
  await page.getByPlaceholder("Search mail").fill("");
  await page.getByPlaceholder("Search mail").press("Enter");
  await waitForText(page, "1-20 of 89");
}

async function checkPaging(page) {
  await page.getByRole("button", { name: "Older", exact: true }).click();
  await waitForText(page, "21-40 of 89");
  await page.getByRole("button", { name: "Newer", exact: true }).click();
  await waitForText(page, "1-20 of 89");
}

async function checkPhone(browser, base, query) {
  const { context, page, errors, foreign } = await open(browser, base, query, { width: 390, height: 844 });
  const { post } = await newestReceived(base);
  await waitForText(page, post.title);
  await page.getByText(post.title).first().click();
  await page.getByRole("button", { name: "Back", exact: true }).waitFor({ timeout: 15_000 });
  await page.getByRole("button", { name: "Back", exact: true }).click();
  await waitForText(page, "1-20 of 89");
  assert.deepEqual(errors, [], "phone: page errors");
  assert.deepEqual(foreign, [], "phone: requests that left the page's origin");
  await context.close();
}

async function main() {
  process.env.SWIFTUIWEB_API_PATH = "/api";
  const browser = await launch();
  try {
    // Each mode starts from a fresh mock, so the counts the checks expect hold in both.
    for (const [mode, query] of [["Worker", ""], ["main thread", "?render-in-worker=0"]]) {
      const mock = Bun.serve({ port: 0, hostname: "127.0.0.1", fetch: createMockApi({ persist: true }) });
      process.env.SWIFTUIWEB_API_ORIGIN = `http://127.0.0.1:${mock.port}`;
      const server = await serveBundle({ bundle: BUNDLE, port: await freePort(), logName: "mailo-server" });
      try {
        const { context, page, errors, foreign } = await open(browser, server.base, query);
        await checkInbox(page, server.base);
        await checkReadAndStar(page, server.base);
        await checkCompose(page, server.base);
        await checkReply(page, server.base);
        await checkDeleteAndTrash(page, server.base);
        await checkSearch(page);
        await checkPaging(page);
        assert.deepEqual(errors, [], `${mode}: page errors`);
        assert.deepEqual(foreign, [], `${mode}: requests that left the page's origin`);
        await context.close();
        await checkPhone(browser, server.base, query);
        console.log(`[${engineName()}/${mode}] inbox, reading, star, compose, reply, trash, search, paging, phone`);
      } finally {
        await server.stop();
        mock.stop(true);
      }
    }
    console.log("Mailo browser test passed.");
  } finally {
    await browser.close();
  }
}

await runSuite(main);
