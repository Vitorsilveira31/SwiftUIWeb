#!/usr/bin/env bun
// Neighborly (Examples/Neighborly) in a real browser against the mock API (Tools/mock-jsonplaceholder.mjs), in the Worker and on the main thread:
//
//   * the feed shows posts with their reactions and comment counts;
//   * liking adds one to the reactions and unliking takes it back;
//   * Comment opens the comments under a post, a new comment is written there and kept by the service, and closing hides them;
//   * the composer shares a post: it goes first in the feed and the service keeps it;
//   * Photos: the albums of a person, an album's grid, a picture larger, and back;
//   * the profile: the cover picture, the person, their friends;
//   * a phone-sized window shows one column and the bottom bar;
//   * nothing reaches the network but the page's own origin, and no page errors.
// Engine: SWIFTUIWEB_BROWSER_ENGINE. Bundle: NEIGHBORLY_BUNDLE (default .build/browser/Neighborly).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { engineName, freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";
import { createMockApi } from "./mock-api/server.mjs";

const BUNDLE = resolve(process.env.NEIGHBORLY_BUNDLE ?? join(ROOT, ".build/browser/Neighborly"));

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

// The number a post shows first (the first "N likes" on the page belongs to the first post in the feed).
const firstReactions = (page) => page.evaluate(() => Number(/(\d+) likes?/.exec(document.body.innerText)?.[1]));
const total = (base, resource) => fetch(`${base}/api/${resource}?_limit=1`).then((response) => Number(response.headers.get("x-total-count")));

// The service keeps what was written: its count reaches the expected one once the request is done.
async function waitForTotal(base, resource, expected) {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    if ((await total(base, resource)) === expected) return;
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  assert.equal(await total(base, resource), expected, `the service did not keep the ${resource}`);
}

async function checkFeed(page) {
  await page.waitForFunction(() => /\d+ comments?/.test(document.body.innerText) && /\d+ likes?/.test(document.body.innerText), undefined, { timeout: 30_000 });
  const before = await firstReactions(page);
  await page.getByRole("button", { name: "Like", exact: true }).first().click();
  await page.waitForFunction((count) => new RegExp(`${count + 1} likes?`).test(document.body.innerText), before, { timeout: 10_000 });
  await page.getByRole("button", { name: "Unlike", exact: true }).first().click();
  await page.waitForFunction((count) => new RegExp(`${count} likes?`).test(document.body.innerText), before, { timeout: 10_000 });
}

async function checkComments(page, base) {
  await page.getByRole("button", { name: "Comment", exact: true }).first().click();
  await page.locator('input[placeholder="Write a comment…"]:visible').waitFor({ timeout: 15_000 });
  // The comments of the mock arrive with their authors' names (the people of the service).
  await page.waitForFunction(() => /[A-Z][a-z]+ [A-Z][a-z]+/.test(document.body.innerText), undefined, { timeout: 15_000 });
  // Each run writes a note of its own, so a comment from an earlier run cannot stand in for this one.
  const note = `The light here is lovely ${Date.now()}`;
  const before = await total(base, "comments");
  await page.locator('input[placeholder="Write a comment…"]:visible').fill(note);
  await page.locator('input[placeholder="Write a comment…"]:visible').press("Enter");
  await page.waitForFunction((text) => document.body.innerText.includes(text), note, { timeout: 15_000 });
  await waitForTotal(base, "comments", before + 1);
  await page.getByRole("button", { name: "Comment", exact: true }).first().click();
  await page.waitForFunction((text) => !document.body.innerText.includes(text), note, { timeout: 10_000 });
}

async function checkComposer(page, base) {
  const note = `Hello from the browser test ${Date.now()}`;
  const before = await total(base, "posts");
  const prompt = page.locator('input[placeholder="What is on your mind?"]:visible');
  await prompt.fill(note);
  await prompt.press("Enter");
  await page.waitForFunction((text) => document.body.innerText.includes(text), note, { timeout: 15_000 });
  await page.waitForFunction(() => document.querySelector('input[placeholder="What is on your mind?"]')?.value === "", undefined, { timeout: 5000 })
    .catch(() => { throw new Error("the composer is not cleared after sharing"); });
  await waitForTotal(base, "posts", before + 1);
}

async function checkPhotos(page) {
  await page.getByRole("button", { name: "Albums", exact: true }).first().click();
  await page.getByRole("button", { name: /^Open / }).first().waitFor({ timeout: 30_000 });
  await page.getByRole("button", { name: /^Open / }).first().click();
  await page.getByRole("button", { name: /^Show / }).first().waitFor({ timeout: 30_000 });
  assert.ok((await page.getByRole("button", { name: /^Show / }).count()) >= 8, "the album shows no pictures");
  await page.getByRole("button", { name: /^Show / }).first().click();
  await page.getByRole("button", { name: "Next picture" }).waitFor({ timeout: 15_000 });
  await page.getByRole("button", { name: "Next picture" }).click();
  await page.getByRole("button", { name: "All pictures" }).click();
  await page.getByRole("button", { name: /^Show / }).first().waitFor({ timeout: 15_000 });
  await page.getByRole("button", { name: "Albums", exact: true }).first().click();
  await page.getByRole("button", { name: /^Open / }).first().waitFor({ timeout: 15_000 });
}

async function checkProfile(page) {
  await page.getByRole("button", { name: "Your profile" }).click();
  await page.waitForFunction(() => document.body.innerText.includes("From "), undefined, { timeout: 30_000 });
  assert.match(await page.evaluate(() => document.body.innerText), /Friends/);
  assert.ok((await page.locator("img").count()) >= 3, "the profile shows no pictures");
}

async function checkPhone(browser, base) {
  const { context, page, errors, foreign } = await open(browser, base, "", { width: 390, height: 844 });
  await page.getByRole("button", { name: "Photos", exact: true }).waitFor({ timeout: 30_000 });
  const sideColumn = await page.evaluate(() => [...document.querySelectorAll("*")].some((element) => element.childElementCount === 0 && element.textContent === "Shortcuts" && element.getBoundingClientRect().width > 0));
  assert.equal(sideColumn, false, "the phone shows the left column");
  await page.getByRole("button", { name: "Photos", exact: true }).click();
  await page.getByRole("button", { name: /^Open / }).first().waitFor({ timeout: 30_000 });
  assert.deepEqual(errors, [], "phone: page errors");
  assert.deepEqual(foreign, [], "phone: requests that left the page's origin");
  await context.close();
  console.log(`[${engineName()}/phone] one column with the bottom bar`);
}

async function main() {
  const mock = Bun.serve({ port: 0, hostname: "127.0.0.1", fetch: createMockApi({ persist: true }) });
  process.env.SWIFTUIWEB_API_ORIGIN = `http://127.0.0.1:${mock.port}`;
  process.env.SWIFTUIWEB_API_PATH = "/api";
  const server = await serveBundle({ bundle: BUNDLE, port: await freePort(), logName: "neighborly-server" });
  const browser = await launch();
  try {
    for (const [mode, query] of [["Worker", ""], ["main thread", "?render-in-worker=0"]]) {
      const { context, page, errors, foreign } = await open(browser, server.base, query);
      await checkFeed(page);
      await checkComments(page, server.base);
      await checkComposer(page, server.base);
      await checkPhotos(page);
      await checkProfile(page);
      assert.deepEqual(errors, [], `${mode}: page errors`);
      assert.deepEqual(foreign, [], `${mode}: requests that left the page's origin`);
      await context.close();
      console.log(`[${engineName()}/${mode}] feed, reactions, comments, composer, photos, profile`);
    }
    await checkPhone(browser, server.base);
    console.log("Neighborly browser test passed.");
  } finally {
    await browser.close();
    await server.stop();
    mock.stop(true);
  }
}

await runSuite(main);
