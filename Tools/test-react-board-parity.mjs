#!/usr/bin/env bun
// The two boards of the SwiftUIWeb/React comparison answer alike: before anything is measured, both are driven through the
// same steps and must show the same counts, rows, favorites, detail, stats and added work. A comparison of two apps that do
// different things measures nothing.
//
//   make react-board-parity-test      (builds the SwiftUIWeb board and the React board first)
// Bundles: BOARD_SWIFT_BUNDLE (.build/browser/BoardBenchmarkApp) and BOARD_REACT_BUNDLE (Benchmarks/ReactComparison/react-board/dist).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";
import { makeWorks, matches } from "../Benchmarks/ReactComparison/shared/data.mjs";

const BUNDLES = {
  SwiftUIWeb: resolve(process.env.BOARD_SWIFT_BUNDLE ?? join(ROOT, ".build/browser/BoardBenchmarkApp")),
  React: resolve(process.env.BOARD_REACT_BUNDLE ?? join(ROOT, "Benchmarks/ReactComparison/react-board/dist")),
};
const QUERIES = ["w", "wi", "ledger", "iron g", "zzz"];

async function drive(browser, base, path = "/") {
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error)));
  await page.goto(`${base}${path}`);
  await page.waitForSelector('[data-testid="row"]', { timeout: 30_000 });
  const text = (testid) => page.evaluate((id) => document.querySelector(`[data-testid="${id}"]`)?.textContent.trim() ?? null, testid);
  const settled = async (testid, expected) => {
    await page.waitForFunction(([id, value]) => document.querySelector(`[data-testid="${id}"]`)?.textContent.trim() === value, [testid, expected], { timeout: 10_000 });
    return expected;
  };
  const seen = {};
  seen.first = await page.evaluate(() => [...document.querySelectorAll('[data-testid^="title-"]')].slice(0, 3).map((e) => e.textContent.trim()));
  const search = page.locator('input[data-testid="search"], [data-testid="search"] input').first();
  for (const query of QUERIES) {
    const expected = `${makeWorks().filter((work) => matches(work, query)).length} results`;
    await search.fill(query);
    seen[`search ${query}`] = await settled("result-count", expected);
  }
  await search.fill("");
  await settled("result-count", "2000 results");
  await page.click('[data-testid="fav-3"]');
  seen.favorites = await settled("fav-count", "1 favorites");
  seen.star = await settled("fav-3", "★");
  const shaded = (testid) => page.evaluate((id) => {
    const color = getComputedStyle(document.querySelector(`[data-testid="${id}"]`).closest('[data-testid="row"]')).backgroundColor;
    return color !== "rgba(0, 0, 0, 0)" && color !== "transparent";
  }, testid);
  await page.click('[data-testid="title-5"]');
  seen.detail = await settled("detail-title", makeWorks()[4].title);
  await page.waitForFunction((id) => {
    const color = getComputedStyle(document.querySelector(`[data-testid="${id}"]`).closest('[data-testid="row"]')).backgroundColor;
    return color !== "rgba(0, 0, 0, 0)" && color !== "transparent";
  }, "title-5", { timeout: 10_000 });
  seen.selectedShaded = await shaded("title-5");
  seen.otherShaded = await shaded("title-6");
  await page.click('[data-testid="add-button"]');
  seen.added = await settled("result-count", "2001 results");
  seen.firstAfterAdd = await page.evaluate(() => document.querySelector('[data-testid^="title-"]').textContent.trim());
  await page.click('[data-testid="view-stats"]');
  await page.waitForFunction(() => document.querySelectorAll('[data-testid="stats-cell"]').length === 200, null, { timeout: 10_000 });
  seen.stats = await page.evaluate(() => [...document.querySelectorAll('[data-testid="stats-cell"]')].slice(0, 5).map((e) => e.textContent.trim()).join(","));
  await page.click('[data-testid="view-board"]');
  seen.back = await settled("result-count", "2001 results");
  assert.deepEqual(errors, [], "page errors");
  await context.close();
  return seen;
}

async function main() {
  const servers = [];
  const browser = await launch();
  try {
    const seen = {};
    // The virtualized React side is the React bundle at another address (?virtual=1), served once with the plain one.
    const served = {};
    for (const [name, bundle] of Object.entries(BUNDLES)) {
      const server = await serveBundle({ bundle, port: await freePort(), logName: `board-parity-${name}`, required: ["index.html"] });
      servers.push(server);
      served[name] = server.base;
    }
    seen.SwiftUIWeb = await drive(browser, served.SwiftUIWeb);
    seen.React = await drive(browser, served.React);
    seen["React (virtualized)"] = await drive(browser, served.React, "/?virtual=1");
    assert.deepEqual(seen.React, seen.SwiftUIWeb, "the two boards answer differently");
    assert.deepEqual(seen["React (virtualized)"], seen.SwiftUIWeb, "the virtualized React board answers differently");
    assert.equal(seen.SwiftUIWeb.first[0], "Crimson Lantern 1");
    console.log(`Board parity passed (${Object.keys(seen.SwiftUIWeb).length} observations, identical on all three sides).`);
  } finally {
    await browser.close();
    for (const server of servers) await server.stop();
  }
}

await runSuite(main);
