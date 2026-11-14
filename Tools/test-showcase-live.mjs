#!/usr/bin/env bun
// Application gate against a freshly linked WASM bundle, not mocked ABI.
// Starts the actual Bun server. Requires Bun, Playwright and a built bundle.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { launch, ROOT, runSuite, serveBundle } from "./browser-test-support.mjs";
import { bundleFilePath } from "./hash-release-bundle.mjs";

const { values } = parseArgs({
  options: {
    bundle: { type: "string", default: join(ROOT, ".build/browser/ShowcaseApp") },
    port: { type: "string", default: "8097" },
  },
});

const SHOWCASE_FILES = ["app.wasm", "index.html", "index.js", "styles.css", "showcase-host.js"];
const checks = [];

async function check(name, fn) {
  try {
    await fn();
    checks.push({ name, status: "PASS" });
    console.log(`PASS ${name}`);
  } catch (error) {
    checks.push({ name, status: "FAIL", error: String(error?.message ?? error) });
    console.log(`FAIL ${name} ${error?.message ?? error}`);
  }
}

await runSuite(async () => {
  const bundle = resolve(values.bundle);
  const port = Number(values.port);
  for (const file of SHOWCASE_FILES) {
    if (!bundleFilePath(bundle, file)) throw new Error(`${file} missing. Run make browser-release EXAMPLE=showcase.`);
  }
  execFileSync(process.execPath, [join(ROOT, "Tools/check-wasm-exports.mjs"), bundleFilePath(bundle, "app.wasm")], { stdio: "inherit" });
  const out = join(ROOT, ".build/live-validation");
  mkdirSync(out, { recursive: true });
  // PORT is passed to the Bun server through its environment as well as its argument.
  process.env.PORT = String(port);
  const errors = [];
  let stop;
  let browser;
  try {
    const started = await serveBundle({ bundle, port, logName: "live-validation/server", required: SHOWCASE_FILES });
    stop = started.stop;
    const base = started.base;
    browser = await launch();
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    page.on("pageerror", (error) => errors.push(String(error)));

    async function load(path) {
      const response = await page.goto(base + path, { waitUntil: "domcontentloaded" });
      assert.ok(response && response.status() === 200);
      await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30000 });
      await page.waitForSelector('[data-docs-part="title"]');
      await page.waitForTimeout(250);
    }

    const routes = ["/", "/layout", "/state", "/themes", "/responsive", "/components", "/forms", "/collections", "/navigation", "/presentation", "/advanced"];
    for (const route of routes) {
      await check("fresh WASM direct load and refresh " + route, async () => {
        await load(route);
        const response = await page.reload({ waitUntil: "domcontentloaded" });
        assert.ok(response && response.status() === 200);
        await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30000 });
        assert.ok((await page.getByTestId("showcase-page-title").innerText()).trim());
        // The page's CSS mapper lays out every root (the previews, the table cells, the columns, the presentations): none is left without a layout.
        assert.equal(await page.evaluate("window.__embeddedSession.layoutMetrics.unlaid"), 0, "semantic roots without a layout on " + route);
      });
    }

    await check("GeometryReader receives nonzero browser measurement", async () => {
      await load("/layout");
      await page.waitForFunction("[...document.querySelectorAll('[data-geometry-reader]')].some(e=>e.getBoundingClientRect().width>0 && !e.textContent.includes('0.0 × 0.0'))");
    });

    await check("Swift state toggles authoritative appearance", async () => {
      await load("/themes");
      const before = await page.locator("html").getAttribute("data-color-scheme");
      await page.getByTestId("showcase-theme-toggle").click();
      await page.waitForFunction((old) => document.documentElement.dataset.colorScheme !== old, before);
    });

    for (const width of [1440, 1200, 1024, 800, 768, 430, 390, 320]) {
      await check("fresh WASM responsive " + String(width), async () => {
        await page.setViewportSize({ width, height: 900 });
        await load("/layout");
        await page.waitForTimeout(200);
        assert.ok(await page.evaluate("document.documentElement.scrollWidth <= innerWidth+1"));
        // The shell keeps side margins at wide viewports (design), so the header must fill
        // the shell, and the shell must fit the viewport.
        assert.ok(
          await page.locator('[data-docs-part="header"]').evaluate((e) => {
            const shell = document.querySelector('[data-testid="showcase-shell"]').getBoundingClientRect();
            const h = e.getBoundingClientRect();
            return Math.abs(h.width - shell.width) < 1 && shell.right <= innerWidth + 1 && shell.left >= -1;
          }),
        );
      });
    }

    await check("Swift ScrollViewReader and virtualized scroll position", async () => {
      await page.setViewportSize({ width: 390, height: 844 });
      await load("/collections");
      await page.getByRole("button", { name: "Scroll to row 8", exact: true }).click();
      await page.waitForTimeout(450);
      assert.ok(await page.locator(".scroll-horizontal").evaluateAll((els) => els.some((e) => e.scrollLeft > 0)));
      await page.getByRole("button", { name: "Jump to item 40", exact: true }).click();
      await page.waitForTimeout(500);
      assert.ok(await page.locator(".scroll-vertical").evaluateAll((els) => els.some((e) => e.scrollTop > 300)));
    });

    await check("Swift alert and confirmation binding dismissal", async () => {
      await load("/presentation");
      for (const label of ["Alert", "Confirmation"]) {
        await page.getByRole("button", { name: label, exact: true }).click();
        await page.waitForSelector(".presentation-root");
        await page.keyboard.press("Escape");
        await page.waitForSelector(".presentation-root", { state: "detached" });
      }
    });

    await check("browser history and Swift documentation state agree", async () => {
      await page.setViewportSize({ width: 1440, height: 900 });
      await load("/layout");
      await page.getByTestId("showcase-topic-components").click();
      await page.waitForURL("**/components");
      await page.goBack();
      await page.waitForURL("**/layout");
      await page.waitForTimeout(150);
      assert.equal(await page.getByTestId("showcase-page-title").innerText(), "Layout");
      await page.goForward();
      await page.waitForURL("**/components");
    });

    for (const [width, theme] of [[1440, "light"], [1440, "dark"], [390, "light"], [390, "dark"]]) {
      await page.emulateMedia({ colorScheme: theme });
      await page.setViewportSize({ width, height: 900 });
      await load("/layout");
      await page.screenshot({ path: join(out, `layout-${width}-${theme}.png`), fullPage: true });
    }

    await check("no application page exceptions", async () => {
      if (errors.length) throw new Error(JSON.stringify(errors));
    });
  } finally {
    await browser?.close();
    await stop?.();
    writeFileSync(join(out, "results.json"), JSON.stringify({ kind: "fresh linked WASM application gate", checks }, null, 2));
  }
});

if (!checks.length || checks.some((entry) => entry.status !== "PASS")) process.exitCode = 1;
