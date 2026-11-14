#!/usr/bin/env bun
// The first frame of a page opened at a deep link already shows the requested screen, never the start screen.
//
// An init script records the page after every DOM mutation batch (each batch is one committed frame) together with the
// mount marker. The suite loads, in the Worker (default) and on the main thread (`?render-in-worker=0`):
//   * the Showcase `/stackDepth` fixture (its 159 buttons come from the route in the URL), and a documentation route
//     with a query and a fragment: the start route (`/`) must never be on screen, and the first frame that carries
//     `data-embedded-mounted="true"` must be the requested screen;
//   * a typed NavigationStack path URL (`/Detail%20route`) after a reload: its history entry carries the typed snapshot,
//     which a reload cannot rebuild, so the start screen is the requested screen there and must not change under the page;
//   * (with `--universal`) a TabView selection URL (`?tab-selection=`): the default tab must never be selected.
// Back and forward keep working: documentation links, NavigationStack pushes and tab selections.
// Engine: SWIFTUIWEB_BROWSER_ENGINE. Showcase bundle: FIRST_ROUTE_BUNDLE or --showcase (.build/browser/ShowcaseApp).
import assert from "node:assert/strict";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { engineName, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

const MOUNTED = 'html[data-embedded-mounted="true"]';
const RECORDER = `
(() => {
  window.__frames = [];
  const snap = () => {
    const current = document.querySelector('[data-docs-route][aria-current="page"]');
    const tabView = document.querySelector('.tab-view');
    const selected = tabView && [...tabView.querySelectorAll('[role="tab"]')].find(tab => tab.getAttribute('aria-selected') === 'true');
    window.__frames.push({
      t: Math.round(performance.now()),
      shell: !!document.querySelector('[data-docs-part="main"]'),
      route: current ? current.getAttribute('data-docs-route') : null,
      depth: !!document.querySelector('[data-testid="depth-value"]'),
      tabView: !!tabView,
      tab: selected ? selected.getAttribute('data-tab-label') : null,
      destination: !!document.querySelector('[data-testid="showcase-destination"]'),
      mounted: document.documentElement.dataset.embeddedMounted === 'true',
    });
  };
  new MutationObserver(snap).observe(document, {subtree: true, childList: true, attributes: true, characterData: true});
})();
`;

async function record(context, url) {
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error)));
  await page.goto(url, { waitUntil: "domcontentloaded" });
  await page.waitForSelector(MOUNTED, { timeout: 60_000 });
  await page.waitForTimeout(400); // a late second frame (the old flash) would land in this window
  const frames = await page.evaluate("window.__frames");
  assert.ok(errors.length === 0, `${url}: ${JSON.stringify(errors.slice(0, 2))}`);
  return { page, frames };
}

function firstMounted(frames, url) {
  const index = frames.findIndex((frame) => frame.mounted);
  assert.ok(index !== -1, `${url}: no frame carried the mount marker: ${JSON.stringify(frames.slice(-3))}`);
  return index;
}

// `wanted(frame)` must hold for every frame that has the screen's shell and for the frame that carries the marker.
function checkScreen(frames, url, wanted, label) {
  const index = firstMounted(frames, url);
  assert.ok(
    wanted(frames[index]),
    `${label} (${url}): the first marked frame is not the requested screen: ${JSON.stringify(frames[index])}`,
  );
  const flashed = frames.filter((frame) => frame.shell && !wanted(frame));
  assert.ok(
    flashed.length === 0,
    `${label} (${url}): ${flashed.length} committed frames showed another screen: ${JSON.stringify(flashed.slice(0, 2))}`,
  );
  return index;
}

// Waits until the documentation route marked `aria-current` is `route`.
async function waitRoute(page, route, timeout = 30) {
  const deadline = Date.now() + timeout * 1000;
  while (Date.now() < deadline) {
    const current = await page.evaluate(
      `document.querySelector('[data-docs-route][aria-current="page"]')?.getAttribute('data-docs-route')`,
    );
    if (current === route) return;
    await page.waitForTimeout(50);
  }
  throw new Error(`the current route never became ${route}`);
}

async function checkShowcase(browser, base, query) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  await context.addInitScript(RECORDER);
  const checks = [];

  {
    const url = `${base}/stackDepth${query}`;
    const { page, frames } = await record(context, url);
    checkScreen(frames, url, (f) => f.depth && f.route !== "/", "stackDepth");
    assert.equal(await page.locator('[data-testid="depth-20"]').count(), 1);
    await page.close();
    checks.push("stackDepth");
  }

  for (const [path, route] of [
    ["/navigation", "/navigation"],
    ["/collections", "/collections"],
  ]) {
    const url = `${base}${path}${query}`;
    const { page, frames } = await record(context, url);
    checkScreen(frames, url, (f) => f.route === route, path);
    await page.close();
    checks.push(path);
  }

  {
    const url = `${base}/layout${query || "?q=1"}#frag`;
    const { page, frames } = await record(context, url);
    checkScreen(frames, url, (f) => f.route === "/layout", "route with query and fragment");
    await page.close();
    checks.push("query and fragment");
  }

  {
    const url = `${base}/${query}`;
    const { page, frames } = await record(context, url);
    checkScreen(frames, url, (f) => f.route === "/", "start route");
    await page.close();
    checks.push("start route");
  }

  // Back and forward across documentation links and a NavigationStack push.
  {
    const url = `${base}/components${query}`;
    const { page } = await record(context, url);
    const pathname = () => page.evaluate("location.pathname");
    const currentRoute = () =>
      page.evaluate(`document.querySelector('[data-docs-route][aria-current="page"]')?.getAttribute('data-docs-route')`);
    await page.locator('[data-docs-route="/navigation"]').first().click();
    await waitRoute(page, "/navigation");
    assert.equal(await pathname(), "/navigation");
    await page.getByText("Push a detail", { exact: true }).first().click();
    await page.waitForSelector('[data-testid="showcase-destination"]');
    const pushed = await pathname();
    assert.notEqual(pushed, "/navigation", pushed);
    await page.goBack();
    await page.waitForFunction(`!document.querySelector('[data-testid="showcase-destination"]')`);
    const atNavigation = await pathname();
    const routeAfterBack = await currentRoute();
    assert.ok(
      atNavigation === "/navigation" && routeAfterBack === "/navigation",
      `${atNavigation}, ${routeAfterBack}`,
    );
    await page.goForward();
    await page.waitForSelector('[data-testid="showcase-destination"]');
    assert.equal(await pathname(), pushed, `${await pathname()} != ${pushed}`);
    await page.goBack();
    await page.goBack();
    await waitRoute(page, "/components");
    assert.equal(await pathname(), "/components");
    // Forward onto the /navigation entry (it carries a depth-zero NavigationStack snapshot) switches the section back, and
    // the next forward restores the pushed destination.
    await page.waitForTimeout(400);
    await page.goForward();
    await waitRoute(page, "/navigation");
    const atNavigationAgain = await pathname();
    const destinations = await page.locator('[data-testid="showcase-destination"]').count();
    assert.ok(atNavigationAgain === "/navigation" && destinations === 0, atNavigationAgain);
    await page.waitForTimeout(400);
    await page.goForward();
    await page.waitForSelector('[data-testid="showcase-destination"]');
    assert.equal(await pathname(), pushed, `${await pathname()} != ${pushed}`);
    checks.push("docs links and NavigationStack back/forward");

    // A reload on the pushed entry: the typed snapshot is gone, the start screen is the requested screen and stays put.
    await page.reload({ waitUntil: "domcontentloaded" });
    await page.waitForSelector(MOUNTED, { timeout: 60_000 });
    await page.waitForTimeout(400);
    const reloaded = await page.evaluate("window.__frames");
    const routes = new Set(reloaded.filter((frame) => frame.shell).map((frame) => frame.route));
    assert.ok(
      routes.size === 1,
      `the screen changed under the page after a reload on a NavigationStack entry: ${JSON.stringify([...routes])}`,
    );
    checks.push("NavigationStack entry reload");

    // The depth-zero entry before it is a plain route: a reload there renders /navigation on the first frame.
    await page.goBack();
    await page.waitForTimeout(600);
    await page.reload({ waitUntil: "domcontentloaded" });
    await page.waitForSelector(MOUNTED, { timeout: 60_000 });
    await page.waitForTimeout(400);
    const again = await page.evaluate("window.__frames");
    const flashed = again.filter((frame) => frame.shell && frame.route !== "/navigation");
    const where = await pathname();
    assert.ok(where === "/navigation" && flashed.length === 0, `${where}, ${JSON.stringify(flashed.slice(0, 2))}`);
    checks.push("reload on a depth-zero NavigationStack entry");
    await page.close();
  }
  await context.close();
  return checks;
}

// The universal app's default tab is Settings; a URL naming General must never show Settings first.
async function checkTabs(browser, base, query) {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 } });
  await context.addInitScript(RECORDER);
  const selected = (page) =>
    page.evaluate(
      "[...document.querySelectorAll('[role=tab]')].find(t => t.getAttribute('aria-selected') === 'true')?.getAttribute('data-tab-label')",
    );

  const waitTab = async (page, label) => {
    const deadline = Date.now() + 30_000;
    while (Date.now() < deadline) {
      if ((await selected(page)) === label) return;
      await page.waitForTimeout(50);
    }
    throw new Error(`tab ${label} was never selected (selected: ${await selected(page)})`);
  };

  const choose = async (page, label) => {
    await page.locator("[data-tab-mobile-toggle]").click();
    await page.locator(`[role="tab"][data-tab-label="${label}"]`).click();
    await waitTab(page, label);
  };

  let page = await context.newPage();
  await page.goto(`${base}/${query}`, { waitUntil: "domcontentloaded" });
  await page.waitForSelector(MOUNTED, { timeout: 60_000 });
  await page.waitForSelector(".tab-view");
  assert.equal(await selected(page), "Settings");
  await choose(page, "General");
  await page.waitForURL("**/*tab-selection=*");
  const tabUrl = page.url();
  await page.close();

  const recorded = await record(context, tabUrl);
  page = recorded.page;
  const index = firstMounted(recorded.frames, tabUrl);
  assert.equal(recorded.frames[index].tab, "General", JSON.stringify(recorded.frames[index]));
  const flashed = recorded.frames.filter((frame) => frame.tabView && frame.tab !== "General");
  assert.ok(
    flashed.length === 0,
    `the default tab was committed before the requested one: ${JSON.stringify(flashed.slice(0, 2))}`,
  );
  await choose(page, "Wi-Fi");
  await choose(page, "Battery");
  const steps = [
    [() => page.goBack(), "Wi-Fi"],
    [() => page.goBack(), "General"],
    [() => page.goForward(), "Wi-Fi"],
    [() => page.goForward(), "Battery"],
  ];
  for (const [step, label] of steps) {
    await page.waitForTimeout(400); // a traversal started while the previous one is still being restored races in every build
    await step();
    await waitTab(page, label);
  }
  await page.close();
  await context.close();
  return ["TabView selection URL, back/forward"];
}

await runSuite(async () => {
  const { values } = parseArgs({
    options: { showcase: { type: "string" }, universal: { type: "string" } },
  });
  const showcaseBundle = resolve(
    values.showcase ?? process.env.FIRST_ROUTE_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseApp"),
  );
  const port = Number(process.env.FIRST_ROUTE_PORT ?? "8115");
  const servers = [];
  const done = [];
  let browser;
  try {
    const showcase = await serveBundle({ bundle: showcaseBundle, port, logName: "first-route-server" });
    servers.push(showcase);
    browser = await launch();
    for (const [mode, query] of [
      ["Worker", ""],
      ["main thread", "?render-in-worker=0"],
    ]) {
      const names = await checkShowcase(browser, showcase.base, query);
      done.push(...names.map((name) => `${mode}: ${name}`));
    }
    if (values.universal) {
      const universal = await serveBundle({
        bundle: resolve(values.universal),
        port: port + 1,
        logName: "first-route-universal-server",
      });
      servers.push(universal);
      for (const [mode, query] of [
        ["Worker", ""],
        ["main thread", "?render-in-worker=0"],
      ]) {
        const names = await checkTabs(browser, universal.base, query);
        done.push(...names.map((name) => `${mode}: ${name}`));
      }
    }
  } finally {
    await browser?.close();
    for (const server of servers) await server.stop();
  }
  console.log(`PASS ${engineName()} first route: ${done.join("; ")}`);
});
