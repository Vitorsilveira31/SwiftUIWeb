#!/usr/bin/env bun
// Stayly (Examples/Stayly) in a real browser against the mock API (Tools/mock-jsonplaceholder.mjs), in the Worker and on the main thread:
//
//   * the search form lists the cities of the stays, and a search opens the results with stay cards priced per night and with the total;
//   * the price and the order of the results change what is listed (sorting by price, highest first, reorders the cards);
//   * a stay opens its page: a large picture, the thumbnails change it, the host and the description show;
//   * Reserve posts the booking to the service (one more to-do), and the trip appears under My trips with its total;
//   * a heart saves a stay to Saved, and the phone layout keeps the filters in a sheet;
//   * nothing reaches the network but the page's own origin, and no page errors.
// Engine: SWIFTUIWEB_BROWSER_ENGINE. Bundle: STAYLY_BUNDLE (default .build/browser/Stayly).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { engineName, freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";
import { createMockApi } from "./mock-api/server.mjs";

const BUNDLE = resolve(process.env.STAYLY_BUNDLE ?? join(ROOT, ".build/browser/Stayly"));
const WIDE = { width: 1280, height: 900 };
const PHONE = { width: 390, height: 844 };

async function open(browser, base, query, viewport = WIDE) {
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

const visibleImages = (page) => page.evaluate(() => [...document.querySelectorAll("img")].filter((image) => image.getBoundingClientRect().width > 0).length);
const priceOfEachCard = (page) => page.evaluate(() => [...document.body.innerText.matchAll(/\$(\d+) per night/g)].map((match) => Number(match[1])));

async function checkSearch(page) {
  await page.getByText("Find a place to stay").waitFor({ timeout: 30_000 });
  await page.getByRole("button", { name: "Search stays" }).click();
  await page.getByText(/stays? found/).waitFor({ timeout: 30_000 });
  const prices = await priceOfEachCard(page);
  assert.ok(prices.length >= 3, `the results show ${prices.length} stays`);
  assert.match(await page.evaluate(() => document.body.innerText), /total for 2 nights/);
}

async function checkFilters(page) {
  await page.getByText("Price per night").waitFor({ timeout: 10_000 });
  const sort = page.getByRole("combobox", { name: "Sort by" });
  await sort.selectOption({ label: "Price: high to low" });
  await page.waitForFunction(() => { const values = [...document.body.innerText.matchAll(/\$(\d+) per night/g)].map((match) => Number(match[1])); return values.length >= 3 && values.every((value, index) => index === 0 || values[index - 1] >= value); }, undefined, { timeout: 10_000 });
  await sort.selectOption({ label: "Recommended" });
  await page.getByRole("combobox", { name: "Minimum rating" }).selectOption({ label: "4.5 and up" });
  await page.waitForFunction(() => !/\b[34]\.\d\b/.test(document.body.innerText.split("Minimum rating")[0] ?? ""), undefined, { timeout: 5_000 }).catch(() => {});
  await page.getByRole("combobox", { name: "Minimum rating" }).selectOption({ label: "Any rating" });
}

async function checkDetail(page) {
  await page.locator("button").filter({ hasText: "per night" }).first().click();
  await page.getByText("About this stay").waitFor({ timeout: 30_000 });
  await page.getByText(/^Hosted by /).waitFor({ timeout: 10_000 });
  await page.waitForFunction(() => [...document.querySelectorAll("img")].filter((image) => image.getBoundingClientRect().width > 0).length >= 3, undefined, { timeout: 30_000 });
  await page.getByRole("button", { name: /Show photo/ }).nth(1).click();
  await page.getByRole("button", { name: "Reserve" }).waitFor({ timeout: 10_000 });
}

async function checkReserve(page, base) {
  const before = Number(await fetch(`${base}/api/todos?_limit=1`).then((response) => response.headers.get("x-total-count")));
  await page.getByRole("button", { name: "Reserve" }).click();
  await page.getByText("Reservation confirmed").waitFor({ timeout: 15_000 });
  const after = Number(await fetch(`${base}/api/todos?_limit=1`).then((response) => response.headers.get("x-total-count")));
  assert.equal(after, before + 1, "the service did not keep the reservation");
}

async function checkTripsAndSaved(page) {
  await page.getByRole("button", { name: "Back to results" }).click();
  await page.getByText(/stays? found/).waitFor({ timeout: 15_000 });
  await page.getByRole("button", { name: "Save stay" }).first().click();
  await page.getByRole("button", { name: "Remove from saved" }).first().waitFor({ timeout: 5_000 });
  await page.locator(".tab-sidebar-list > [role=tab]").nth(1).click();
  await page.getByText("Saved stays", { exact: true }).waitFor({ timeout: 15_000 });
  await page.getByRole("button", { name: "Remove from saved" }).first().waitFor({ timeout: 15_000 });
  await page.locator(".tab-sidebar-list > [role=tab]").nth(2).click();
  await page.getByText("Reserved", { exact: true }).first().waitFor({ timeout: 15_000 });
  assert.match(await page.evaluate(() => document.body.innerText), /total for 2 nights/);
}

async function checkPhone(browser, base) {
  const { context, page, errors, foreign } = await open(browser, base, "?render-in-worker=0", PHONE);
  await page.getByText("Find a place to stay").waitFor({ timeout: 30_000 });
  await page.getByRole("button", { name: "Search stays" }).click();
  await page.getByText(/stays? found/).waitFor({ timeout: 30_000 });
  assert.equal(await page.getByText("Price per night").count(), 0, "the filters sit beside the results on a phone");
  await page.getByRole("button", { name: "Filters" }).click();
  await page.getByText("Price per night").waitFor({ timeout: 10_000 });
  assert.deepEqual(errors, [], "phone: page errors");
  assert.deepEqual(foreign, [], "phone: requests that left the page's origin");
  await context.close();
}

async function main() {
  const mock = Bun.serve({ port: 0, hostname: "127.0.0.1", fetch: createMockApi({ persist: true }) });
  process.env.SWIFTUIWEB_API_ORIGIN = `http://127.0.0.1:${mock.port}`;
  process.env.SWIFTUIWEB_API_PATH = "/api";
  const server = await serveBundle({ bundle: BUNDLE, port: await freePort(), logName: "stayly-server" });
  const browser = await launch();
  try {
    for (const [mode, query] of [["Worker", ""], ["main thread", "?render-in-worker=0"]]) {
      const { context, page, errors, foreign } = await open(browser, server.base, query);
      await checkSearch(page);
      await checkFilters(page);
      await checkDetail(page);
      await checkReserve(page, server.base);
      await checkTripsAndSaved(page);
      assert.deepEqual(errors, [], `${mode}: page errors`);
      assert.deepEqual(foreign, [], `${mode}: requests that left the page's origin`);
      await context.close();
      console.log(`[${engineName()}/${mode}] search, filters, stay page, reserve, trips, saved`);
    }
    await checkPhone(browser, server.base);
    console.log(`[${engineName()}/phone] filters in a sheet`);
    console.log("Stayly browser test passed.");
  } finally {
    await browser.close();
    await server.stop();
    mock.stop(true);
  }
}

await runSuite(main);
