#!/usr/bin/env bun
// Lumio (Examples/Lumio) in a real browser against the mock API (Tools/mock-jsonplaceholder.mjs), in the Worker and on the main thread:
//
//   * the feed shows the stories and posts by different authors, with pictures the mock draws;
//   * liking adds one to the likes and unliking takes it back;
//   * the comments of a post open in a sheet, a new comment is posted, appears and is kept by the service;
//   * Explore shows a grid of pictures, a search that matches nothing says so, and Show more adds the next page;
//   * the profile shows the person, their highlights and their pictures;
//   * nothing reaches the network but the page's own origin, and no page errors.
// Engine: SWIFTUIWEB_BROWSER_ENGINE. Bundle: LUMIO_BUNDLE (default .build/browser/Lumio).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { engineName, freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";
import { createMockApi } from "./mock-api/server.mjs";

const BUNDLE = resolve(process.env.LUMIO_BUNDLE ?? join(ROOT, ".build/browser/Lumio"));

async function open(browser, base, query) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, locale: "en-US" });
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

const likesOfFirstPost = (page) => page.evaluate(() => Number(/([\d,]+) likes?/.exec(document.body.innerText)?.[1].replace(",", "")));

async function checkFeed(page) {
  await page.waitForFunction(() => document.querySelectorAll("img").length > 6 && document.body.innerText.includes("likes"), undefined, { timeout: 30_000 });
  const authors = await page.evaluate(() => new Set([...document.body.innerText.matchAll(/\b(AnaAlves|BrunoBarr|CarlaCamp)\b/g)].map((match) => match[1])).size);
  assert.ok(authors >= 2, `the feed shows posts by ${authors} author(s)`);
  const before = await likesOfFirstPost(page);
  await page.locator('button[aria-label="Like"]').first().click();
  await page.waitForFunction((count) => document.body.innerText.includes(`${count + 1} likes`) || document.body.innerText.includes(`${(count + 1).toLocaleString("en-US")} likes`), before, { timeout: 10_000 });
  await page.locator('button[aria-label="Unlike"]').first().click();
  await page.waitForFunction((count) => document.body.innerText.includes(`${count} likes`) || document.body.innerText.includes(`${count.toLocaleString("en-US")} likes`), before, { timeout: 10_000 });
}

async function checkComments(page, base) {
  await page.getByText("View all 5 comments").first().click();
  await page.getByText("Comments", { exact: true }).waitFor({ timeout: 15_000 });
  // `textContent`, not `innerText`: WebKit reports an empty `innerText` for the sheet while its panel is still being laid out.
  await page.waitForFunction(() => /[a-z]+\.[a-z]+/.test(document.querySelector(".sheet-content")?.textContent ?? ""), undefined, { timeout: 15_000 });
  const before = Number((await fetch(`${base}/api/comments?_limit=1`).then((response) => response.headers.get("x-total-count"))));
  await page.getByPlaceholder("Add a comment…").fill("The light here is lovely");
  await page.getByPlaceholder("Add a comment…").press("Enter");
  await page.waitForFunction(() => document.querySelector(".sheet-content")?.textContent.includes("The light here is lovely"), undefined, { timeout: 15_000 });
  // The draft is cleared by the same call that adds the comment; the field follows in the frame after the list.
  await page.waitForFunction(() => document.querySelector(".sheet-content input")?.value === "", undefined, { timeout: 5000 }).catch(() => { throw new Error("the draft is not cleared after sending"); });
  const after = Number((await fetch(`${base}/api/comments?_limit=1`).then((response) => response.headers.get("x-total-count"))));
  assert.equal(after, before + 1, "the service did not keep the comment");
  await page.getByRole("button", { name: "Close" }).click();
  await page.waitForFunction(() => !document.querySelector(".sheet-content"), undefined, { timeout: 10_000 });
}

// The pictures on screen, and how tall the screen's scroll view is: a lazy grid builds only what is near the screen, and the other tabs keep
// their pictures in the page, so the number of images in the document says little.
const visibleImages = (page) => page.evaluate(() => [...document.querySelectorAll("img")].filter((image) => image.getBoundingClientRect().width > 0).length);
const scrollHeight = (page) => page.evaluate(() => Math.max(0, ...[...document.querySelectorAll(".scroll-view")].filter((view) => view.getBoundingClientRect().width > 300).map((view) => view.scrollHeight)));

async function checkExplore(page) {
  await page.locator(".tab-sidebar-list > [role=tab]").nth(1).click();
  await page.waitForFunction(() => [...document.querySelectorAll("img")].filter((image) => image.getBoundingClientRect().width > 0).length >= 8, undefined, { timeout: 30_000 });
  await page.getByPlaceholder("Search pictures").fill("zzzzqqqq");
  await page.getByPlaceholder("Search pictures").press("Enter");
  await page.getByText("No pictures match your search").waitFor({ timeout: 15_000 });
  await page.getByPlaceholder("Search pictures").fill("");
  await page.getByPlaceholder("Search pictures").press("Enter");
  await page.waitForFunction(() => [...document.querySelectorAll("img")].filter((image) => image.getBoundingClientRect().width > 0).length >= 8, undefined, { timeout: 15_000 });
  assert.ok((await visibleImages(page)) >= 8, "clearing the search brings the grid back");
  const before = await scrollHeight(page);
  await page.getByRole("button", { name: "Show more" }).click();
  await page.waitForFunction((height) => Math.max(0, ...[...document.querySelectorAll(".scroll-view")].filter((view) => view.getBoundingClientRect().width > 300).map((view) => view.scrollHeight)) > height, before, { timeout: 15_000 });
}

async function checkProfile(page) {
  await page.locator(".tab-sidebar-list > [role=tab]").nth(2).click();
  await page.waitForFunction(() => document.body.innerText.includes("From Lisbon"), undefined, { timeout: 30_000 });
  const text = await page.evaluate(() => document.body.innerText);
  assert.match(text, /AnaAlves/);
  assert.match(text, /posts/);
  assert.match(text, /albums/);
  assert.ok((await visibleImages(page)) >= 8, "the profile shows no pictures");
}

async function main() {
  const mock = Bun.serve({ port: 0, hostname: "127.0.0.1", fetch: createMockApi({ persist: true }) });
  process.env.SWIFTUIWEB_API_ORIGIN = `http://127.0.0.1:${mock.port}`;
  process.env.SWIFTUIWEB_API_PATH = "/api";
  const server = await serveBundle({ bundle: BUNDLE, port: await freePort(), logName: "lumio-server" });
  const browser = await launch();
  try {
    for (const [mode, query] of [["Worker", ""], ["main thread", "?render-in-worker=0"]]) {
      const { context, page, errors, foreign } = await open(browser, server.base, query);
      await checkFeed(page);
      await checkComments(page, server.base);
      await checkExplore(page);
      await checkProfile(page);
      assert.deepEqual(errors, [], `${mode}: page errors`);
      assert.deepEqual(foreign, [], `${mode}: requests that left the page's origin`);
      await context.close();
      console.log(`[${engineName()}/${mode}] feed, comments, explore, profile`);
    }
    console.log("Lumio browser test passed.");
  } finally {
    await browser.close();
    await server.stop();
    mock.stop(true);
  }
}

await runSuite(main);
