#!/usr/bin/env bun
// Seekr (Examples/Seekr) in a real browser against the mock API (Tools/mock-jsonplaceholder.mjs), in the Worker and on the main thread:
//
//   * the home page suggests post titles as the reader types, and a suggestion opens its results;
//   * the results show the count, the breadcrumb and the link of each result, and the query's words in bold in the snippet;
//   * the pager moves through the pages of a broad query;
//   * People also ask shows questions on All, and News has no questions;
//   * the Images tab shows a grid of pictures, a click opens the preview, and Close Preview closes it;
//   * a search that matches nothing says so;
//   * nothing reaches the network but the page's own origin, and no page errors.
// Engine: SWIFTUIWEB_BROWSER_ENGINE. Bundle: SEEKR_BUNDLE (default .build/browser/Seekr).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { engineName, freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";
import { createMockApi } from "./mock-api/server.mjs";

const BUNDLE = resolve(process.env.SEEKR_BUNDLE ?? join(ROOT, ".build/browser/Seekr"));

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

const get = (base, path) => fetch(`${base}${path}`).then((response) => response.json());
const matches = async (base, query) => (await get(base, `/api/posts?q=${encodeURIComponent(query)}`)).length;
const countText = (total) => (total === 1 ? "About 1 result" : `About ${total} results`);

// The facts the checks rely on, from the mock: the first post (the first result of a query that its text matches), a word of its
// first 180 characters (the snippet), and its title (a suggestion).
async function facts(base) {
  const [post] = await get(base, "/api/posts?_page=1&_limit=1");
  const word = post.body.slice(0, 180).split(/\s+/).map((part) => part.replace(/[^A-Za-z]/g, "")).find((part) => part.length >= 4);
  return { title: post.title, word, body: post.body };
}

const searchBox = (page) => page.getByPlaceholder("Search the web");
const searchFor = async (page, text) => {
  await searchBox(page).fill(text);
  await page.getByRole("button", { name: "Search", exact: true }).click();
};
const firstResultTitle = (page) => page.evaluate(() => document.querySelector("a.anchor-link")?.textContent ?? "");
// A run of text that is the word, in bold (the snippet's runs are bold `span`s, the title is 600 and not a run).
const boldRun = (wanted) => [...document.querySelectorAll("*")].some((element) => element.childElementCount === 0 && Number(getComputedStyle(element).fontWeight) >= 600 && element.textContent.toLowerCase().replace(/[^a-z]/g, "") === wanted.toLowerCase());

// The pictures on screen: a lazy grid builds only what is near the screen.
const visibleImages = (page) => page.evaluate(() => [...document.querySelectorAll("img")].filter((image) => image.getBoundingClientRect().width > 0).length);

async function checkHome(page, base, known) {
  await searchBox(page).fill(known.title.slice(0, 3));
  await page.getByRole("button", { name: known.title, exact: true }).waitFor({ timeout: 15_000 });
  await page.getByRole("button", { name: known.title, exact: true }).click();
  await page.getByText(countText(await matches(base, known.title)), { exact: true }).waitFor({ timeout: 15_000 });
  await page.getByRole("link", { name: known.title, exact: true }).first().waitFor({ timeout: 15_000 });
  const text = await page.evaluate(() => document.body.innerText);
  assert.match(text, /example\.test › posts › 1/, "the breadcrumb shows the site and the post");
}

async function checkSnippet(page, known) {
  await searchFor(page, known.word);
  // The results of the earlier search stay on screen until these arrive, so the check waits for the bold word itself.
  await page.waitForFunction(boldRun, known.word, { timeout: 15_000 }).catch(() => assert.fail(`the query word "${known.word}" is not bold in a snippet`));
}

async function checkPages(page, base) {
  await searchFor(page, "e");
  const total = await matches(base, "e");
  assert.ok(total > 10, "the mock has more than one page of matches for e");
  await page.getByText(countText(total), { exact: true }).waitFor({ timeout: 15_000 });
  const first = await firstResultTitle(page);
  await page.getByRole("button", { name: "2", exact: true }).click();
  await page.waitForFunction((title) => (document.querySelector("a.anchor-link")?.textContent ?? "") !== title, first, { timeout: 15_000 });
  await page.getByRole("button", { name: "Previous", exact: true }).click();
  await page.waitForFunction((title) => (document.querySelector("a.anchor-link")?.textContent ?? "") === title, first, { timeout: 15_000 });
}

async function checkQuestions(page) {
  await page.getByText("People also ask", { exact: true }).waitFor({ timeout: 15_000 });
  await page.getByRole("button", { name: "News", exact: true }).click();
  await page.waitForFunction(() => !document.body.innerText.includes("People also ask"), undefined, { timeout: 15_000 });
  await page.getByRole("button", { name: "All", exact: true }).click();
  await page.getByText("People also ask", { exact: true }).waitFor({ timeout: 15_000 });
}

async function checkImages(page) {
  await page.getByRole("button", { name: "Images", exact: true }).click();
  await page.waitForFunction(() => [...document.querySelectorAll("img")].filter((image) => image.getBoundingClientRect().width > 0).length >= 4, undefined, { timeout: 30_000 });
  assert.ok((await visibleImages(page)) >= 4, "the Images tab shows no pictures");
  await page.locator("img").nth(0).click();
  await page.getByText(/^Picture \d+$/).first().waitFor({ timeout: 15_000 });
  await page.getByRole("button", { name: "Close preview", exact: true }).click();
  await page.waitForFunction(() => !document.body.innerText.match(/^Picture \d+$/m), undefined, { timeout: 10_000 });
  await page.getByRole("button", { name: "All", exact: true }).click();
  await page.getByText("People also ask", { exact: true }).waitFor({ timeout: 15_000 });
}

async function checkNoResults(page) {
  await searchFor(page, "zzzzqqqq");
  await page.getByText("No results for “zzzzqqqq”. Try other words.", { exact: true }).waitFor({ timeout: 15_000 });
}

async function main() {
  const mock = Bun.serve({ port: 0, hostname: "127.0.0.1", fetch: createMockApi({ persist: true }) });
  process.env.SWIFTUIWEB_API_ORIGIN = `http://127.0.0.1:${mock.port}`;
  process.env.SWIFTUIWEB_API_PATH = "/api";
  const server = await serveBundle({ bundle: BUNDLE, port: await freePort(), logName: "seekr-server" });
  const browser = await launch();
  try {
    const known = await facts(server.base);
    for (const [mode, query] of [["Worker", ""], ["main thread", "?render-in-worker=0"]]) {
      const { context, page, errors, foreign } = await open(browser, server.base, query);
      await checkHome(page, server.base, known);
      await checkSnippet(page, known);
      await checkPages(page, server.base);
      await checkQuestions(page);
      await checkImages(page);
      await checkNoResults(page);
      assert.deepEqual(errors, [], `${mode}: page errors`);
      assert.deepEqual(foreign, [], `${mode}: requests that left the page's origin`);
      await context.close();
      console.log(`[${engineName()}/${mode}] suggestions, results, snippets, paging, questions, images, no results`);
    }
    console.log("Seekr browser test passed.");
  } finally {
    await browser.close();
    await server.stop();
    mock.stop(true);
  }
}

await runSuite(main);
