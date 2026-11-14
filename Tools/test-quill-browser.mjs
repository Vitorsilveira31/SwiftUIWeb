#!/usr/bin/env bun
// Quill (Examples/Quill) in a real browser against the mock API (Tools/mock-jsonplaceholder.mjs), in the Worker and on the main thread:
//
//   * a wide window shows the rail, the timeline and the people to follow; a phone shows the timeline and the bottom bar;
//   * the timeline shows posts by different authors, each with its line below its actions, and liking adds one to the count and unliking takes it back;
//   * a new post is written, shows at the top of the feed and is kept by the service;
//   * the feed keeps its place when "Show more" brings in the next posts and the reader goes on down;
//   * the thread of a post opens in a sheet with its replies, a reply is sent, counted on the post and kept by the service;
//   * the Following tab shows the posts of the people it follows, and says when there are no more;
//   * nothing reaches the network but the page's own origin, and no page errors.
// Engine: SWIFTUIWEB_BROWSER_ENGINE. Bundle: QUILL_BUNDLE (default .build/browser/Quill).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { engineName, freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";
import { createMockApi } from "./mock-api/server.mjs";

const BUNDLE = resolve(process.env.QUILL_BUNDLE ?? join(ROOT, ".build/browser/Quill"));
const WIDE = { width: 1280, height: 900 };
const PHONE = { width: 390, height: 844 };

async function open(browser, base, query, viewport) {
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

const count = (base, path) => fetch(`${base}${path}`).then((response) => Number(response.headers.get("x-total-count")));
const likeButtons = (page) => page.locator('button[aria-label="Like"], button[aria-label="Unlike"]');
const replyButtons = (page) => page.locator('button[aria-label="Reply"]');

// Each post's counts are plain numbers next to its icons; the first heart is the first post's.
async function firstCount(locator) {
  return Number((await locator.first().innerText()).trim());
}

// The count is rendered after the label changes, so the test waits for the number itself.
async function waitForFirstCount(page, expected) {
  await page.waitForFunction((value) => Number(document.querySelector('button[aria-label="Like"], button[aria-label="Unlike"]')?.innerText.trim()) === value, expected, { timeout: 10_000 });
}

async function checkWide(page, base) {
  await page.getByText("Who to follow").first().waitFor({ timeout: 30_000 });
  await page.waitForFunction(() => document.querySelectorAll('button[aria-label="Like"]').length >= 3, undefined, { timeout: 30_000 });
  const text = await page.evaluate(() => document.body.innerText);
  const authors = new Set([...text.matchAll(/@(AnaAlves|BrunoBarr|CarlaCamp)\b/g)].map((match) => match[1]));
  assert.ok(authors.size >= 2, `the timeline shows posts by ${authors.size} author(s)`);

  // The line under a post is below the post's last row, not across its text.
  const overlaps = await page.evaluate(() => [...document.querySelectorAll('button[aria-label="Like"]')].slice(0, 3).map((button) => {
    const line = button.closest('[data-lazy-cell]')?.querySelector('hr');
    return line ? line.getBoundingClientRect().top - button.getBoundingClientRect().bottom : null;
  }));
  assert.ok(overlaps.length >= 3 && overlaps.every((gap) => gap !== null && gap >= -1), `the line under a post is below its actions: ${JSON.stringify(overlaps)}`);

  const likesBefore = await firstCount(likeButtons(page));
  await likeButtons(page).first().click();
  await page.locator('button[aria-label="Unlike"]').first().waitFor({ timeout: 10_000 });
  await waitForFirstCount(page, likesBefore + 1);
  await page.locator('button[aria-label="Unlike"]').first().click();
  await page.locator('button[aria-label="Like"]').first().waitFor({ timeout: 10_000 });
  await waitForFirstCount(page, likesBefore);

  await checkMorePosts(page);
  await checkThread(page, base);
  await checkCompose(page, base, page.getByPlaceholder("What is happening?"));

  await page.getByRole("button", { name: "Following", exact: true }).click();
  await page.getByText("You are all caught up").first().waitFor({ timeout: 30_000 });
  assert.ok((await likeButtons(page).count()) >= 3, "the Following feed shows the posts of the people it follows");
}

// The feed keeps its place when more posts come in and the lazy window grows: the reader went down to "Show more", so asking for
// the next page must not send the feed back to its top, and the reader can go on down through the new posts.
async function checkMorePosts(page) {
  const feed = () => page.evaluate(() => {
    const view = [...document.querySelectorAll(".scroll-view")].find((e) => e.offsetParent && e.querySelector("[data-lazy-cell]"));
    return view ? { top: view.scrollTop, max: view.scrollHeight - view.clientHeight } : null;
  });
  const scrollTo = (top) => page.evaluate((value) => {
    const view = [...document.querySelectorAll(".scroll-view")].find((e) => e.offsetParent && e.querySelector("[data-lazy-cell]"));
    view.scrollTop = value;
  }, top);
  const more = page.locator("button:visible", { hasText: "Show more" });
  for (let step = 0; step < 40 && !(await more.count()); step++) {
    await scrollTo((await feed()).top + 300);
    await page.waitForTimeout(100);
  }
  await more.first().waitFor({ timeout: 10_000 });
  await scrollTo(1_000_000);
  await page.waitForTimeout(300);
  const before = await feed();
  assert.ok(before.top > 100, `the feed was scrolled down to "Show more": ${JSON.stringify(before)}`);
  await more.first().click();
  await page.waitForFunction(() => document.querySelectorAll("[data-lazy-cell] hr").length >= 20, undefined, { timeout: 15_000 });
  await page.waitForTimeout(500);
  const after = await feed();
  assert.ok(after.top >= before.top - 40, `the feed kept its place when more posts came in: ${before.top} before, ${after.top} after`);
  // Down through the new posts: the window grows again and the feed stays where the reader put it.
  for (const top of [after.top + 600, after.top + 1200]) {
    await scrollTo(top);
    await page.waitForTimeout(400);
    assert.ok((await feed()).top >= top - 40, `the feed stayed at ${top}`);
  }
  await scrollTo(0);
}

// A post is written in the field, appears first and is the service's too; the field is empty again afterwards.
async function checkCompose(page, base, field, sheet = false) {
  const text = `Quill test ${Date.now()}`;
  const before = await count(base, "/api/posts?_limit=1");
  await field.fill(text);
  await page.locator("button:visible", { hasText: /^Post$/ }).click();
  await page.locator("span:visible", { hasText: text }).first().waitFor({ timeout: 15_000 });
  if (sheet) {
    await page.waitForFunction(() => !document.querySelector(".sheet-content"), undefined, { timeout: 10_000 });
  } else {
    assert.equal(await field.inputValue(), "", "the field is cleared after posting");
  }
  assert.equal(await count(base, "/api/posts?_limit=1"), before + 1, "the service did not keep the post");
}

async function checkThread(page, base) {
  const repliesBefore = await firstCount(replyButtons(page));
  await replyButtons(page).first().click();
  await page.getByText("Thread", { exact: true }).waitFor({ timeout: 15_000 });
  // Replies have pictures; `textContent` is read for the sheet because WebKit reports an empty `innerText` while the panel is laid out.
  await page.waitForFunction(() => document.querySelectorAll(".sheet-content img").length >= 5, undefined, { timeout: 15_000 });
  const before = await count(base, "/api/comments?_limit=1");
  await page.getByPlaceholder("Write your reply…").fill("Lovely light here");
  await page.getByPlaceholder("Write your reply…").press("Enter");
  await page.waitForFunction(() => document.querySelector(".sheet-content")?.textContent.includes("Lovely light here"), undefined, { timeout: 15_000 });
  // The draft is cleared in the same step as the reply is added; the field follows in the frame after the list.
  await page.waitForFunction(() => document.querySelector('.sheet-content input')?.value === "", undefined, { timeout: 5000 }).catch(() => { throw new Error("the reply field is not cleared after sending"); });
  assert.equal(await count(base, "/api/comments?_limit=1"), before + 1, "the service did not keep the reply");
  await page.getByRole("button", { name: "Close", exact: true }).click();
  await page.waitForFunction(() => !document.querySelector(".sheet-content"), undefined, { timeout: 10_000 });
  await page.waitForFunction((value) => Number(document.querySelector('button[aria-label="Reply"]')?.innerText.trim()) === value, repliesBefore + 1, { timeout: 10_000 });
}

async function checkPhone(page, base) {
  await page.locator('button[aria-label="New post"]').waitFor({ timeout: 30_000 });
  await page.waitForFunction(() => document.querySelectorAll('button[aria-label="Like"]').length >= 3, undefined, { timeout: 30_000 });
  assert.equal(await page.getByText("Who to follow").first().isVisible().catch(() => false), false, "the people to follow are not on a phone");
  await page.locator('button[aria-label="New post"]').click();
  const field = page.locator('[placeholder="What is happening?"]:visible');
  await field.waitFor({ timeout: 10_000 });
  await checkCompose(page, base, field, true);
}

async function main() {
  const mock = Bun.serve({ port: 0, hostname: "127.0.0.1", fetch: createMockApi({ persist: true }) });
  process.env.SWIFTUIWEB_API_ORIGIN = `http://127.0.0.1:${mock.port}`;
  process.env.SWIFTUIWEB_API_PATH = "/api";
  const server = await serveBundle({ bundle: BUNDLE, port: await freePort(), logName: "quill-server" });
  const browser = await launch();
  try {
    for (const [mode, query] of [["Worker", ""], ["main thread", "?render-in-worker=0"]]) {
      const wide = await open(browser, server.base, query, WIDE);
      await checkWide(wide.page, server.base);
      assert.deepEqual(wide.errors, [], `${mode}, wide: page errors`);
      assert.deepEqual(wide.foreign, [], `${mode}, wide: requests that left the page's origin`);
      await wide.context.close();
      console.log(`[${engineName()}/${mode}] wide: timeline, like, compose, thread, following`);

      const phone = await open(browser, server.base, query, PHONE);
      await checkPhone(phone.page, server.base);
      assert.deepEqual(phone.errors, [], `${mode}, phone: page errors`);
      assert.deepEqual(phone.foreign, [], `${mode}, phone: requests that left the page's origin`);
      await phone.context.close();
      console.log(`[${engineName()}/${mode}] phone: bottom bar, compose sheet`);
    }
    console.log("Quill browser test passed.");
  } finally {
    await browser.close();
    await server.stop();
    mock.stop(true);
  }
}

await runSuite(main);
