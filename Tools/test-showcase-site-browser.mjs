#!/usr/bin/env bun
// The project site (Examples/ShowcaseSite) in a real browser, in the Worker and on the main thread.
//
//   * the language follows the browser (Portuguese for pt-BR, English otherwise); the Language and appearance menu switches it,
//     the menu's chip shows the language's code, and the choice is kept after a reload;
//   * the chip follows the address: a page opened at an address that names the other language shows that language's code;
//   * the appearance can be forced dark on a light system;
//   * the home page has a hero and a live counter ("Tap me" counts taps); `/pt` alone opens the Portuguese Purpose page;
//   * the six pages (Purpose, Get started, Benefits, Performance, Components, Animations) open from the header: a row of pills on a wide
//     screen, a Menu on a narrow one; each page's address (`/en/start`) follows, and a reload and Back keep it;
//   * addresses: the language first and the catalog entry last, a deep link opens the page it names, an entry or a language
//     replaces the address instead of adding a history entry, and the document title follows the page;
//   * the hero's actions fit a phone: at 320 to 600 px each keeps its label on one line and none passes the edge, stacked when narrow,
//     the two buttons side by side from 390 px and all three in a row from 430 px;
//   * the header fits a phone: at 320, 360 and 375 px nothing overflows sideways and the brand, the Menu and the settings
//     menu do not overlap and stay inside the screen;
//   * a component's live view and its code follow the knobs: the Text entry gains `.fontWeight(.bold)` when Bold is
//     switched on, the list follows the search, and the code is monospaced with its indentation kept;
//   * on a phone-width screen nothing scrolls sideways, the Language and appearance menu is reachable, the Components page
//     shows its entry within the first screen under a native select of entries, and choosing another entry there changes the
//     entry and the address; on a wide screen (>= 720 px) the list stays beside the entry;
//   * the Performance page leads with "At a glance", shows its measurements behind a header button, and a segmented CPU
//     picker switches the rate;
//   * the Get started page opens from its pill at /en/start with its four steps;
//   * the Animations page plays each of its eight demos live and answers their controls (the digits roll to the new number, a
//     view leaves and comes back, a symbol effect starts, a ring fills) without the page jumping, opens a card's code over the page, speaks Portuguese at
//     /pt/animations, and on a phone nothing scrolls sideways;
//   * the catalog's controls behave: a Toggle's knob is centred in its track, a DisclosureGroup keeps its width open or closed, a
//     Menu opens in the top layer over what follows it, a List with more rows than its height scrolls without overlapping its rows,
//     and on a wide screen the component list and the entry scroll on their own while the page stays still;
//   * every catalog entry opens, beside the list on a wide screen, and the Stepper draws its label and buttons but not its value;
//   * every page shares one frame: at 1440, 1024, 768 and 390 px each page's title starts at the left edge of one centered column
//     (1040 px at most, 20 px from the screen's edge below that), where the header's brand starts too;
//   * the cards of a grid row end together: on Benefits, Get started and Performance at 1440 px, the cards that share a row are as tall
//     as each other, whatever their text.
// Engine: SWIFTUIWEB_BROWSER_ENGINE. Bundle: SHOWCASE_SITE_BUNDLE (default .build/browser/ShowcaseSite).
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { engineName, freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

const BUNDLE = resolve(process.env.SHOWCASE_SITE_BUNDLE ?? join(ROOT, ".build/browser/ShowcaseSite"));
const RECIPES = join(ROOT, "Examples/ShowcaseSite/Features/Components/Recipes");
// The names of every catalog entry, read from the recipes, so a new entry is opened by this test without editing it.
const recipeNames = () =>
  readdirSync(RECIPES)
    .filter((file) => file.endsWith("CatalogRecipe.swift"))
    .map((file) => /^\s+name: "([^"]+)"/m.exec(readFileSync(join(RECIPES, file), "utf8"))?.[1])
    .filter(Boolean);

// The header's preference menu (language and appearance) in either language.
const SETTINGS = 'details[aria-label="Language and appearance"], details[aria-label="Idioma e aparência"]';

async function open(browser, base, { query = "", path = "/", locale = "en-US", width = 1280, scheme = "light" } = {}) {
  const context = await browser.newContext({ viewport: { width, height: 900 }, locale, colorScheme: scheme });
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error)));
  await page.goto(`${base}${path}${query}`, { waitUntil: "domcontentloaded" });
  await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 60_000 });
  await page.waitForSelector("h1, [role=heading]", { state: "attached", timeout: 60_000 });
  return { context, page, errors };
}

async function text(page, expected, what, timeout = 15_000) {
  await page.waitForFunction((value) => document.body.innerText.includes(value), expected, { timeout }).catch(async () => {
    const seen = await page.evaluate(() => `${location.search.slice(0, 60)} :: ${document.body.innerText.replace(/\s+/g, " ").slice(0, 160)}`).catch(() => "(page gone)");
    throw new Error(`${what}: "${expected}" never appeared; the page shows ${seen}`);
  });
}

// Opens a page from the header. On a wide screen its pill is in the header; on a narrow one the header's Menu button opens a list of page links.
// The pill is looked for by the Benefits pill, which only the wide header draws (the Menu's items are hidden until it opens).
async function goTo(page, label) {
  // The pills and the menu's items are links to the page's address (a real `<a href>`), not buttons.
  const wide = await page.getByRole("link", { name: "Benefits", exact: true }).first().isVisible();
  if (wide) {
    await page.getByRole("link", { name: label, exact: true }).first().click();
    return;
  }
  // On a narrow screen the pages are a list of links under the header, opened by its Menu button.
  await page.locator('button[aria-label="Menu"]:visible').first().click();
  await page.getByRole("link", { name: new RegExp(`${label}$`) }).locator("visible=true").first().click();
}

// The menu of a selector that is drawn: the header draws its preference menu twice (one per layout), and only one is shown.
async function visibleMenu(page, selector) {
  const all = page.locator(selector);
  for (let index = 0; index < (await all.count()); index += 1) {
    if (await all.nth(index).locator("summary").first().isVisible()) return all.nth(index);
  }
  throw new Error(`no visible menu matches ${selector}`);
}

// Chooses an item of the Language and appearance menu (or of the page menu) by its name. The menu is open when its panel
// is in the top layer, so the item is clicked only then.
async function choose(page, menu, item, role = "button") {
  const popup = await visibleMenu(page, menu);
  await popup.locator("summary").first().click();
  await popup.locator('[role="menu"]').first().waitFor({ state: "visible", timeout: 10_000 });
  // A page item's accessible name also carries its SF symbol's name ("sparkles Purpose"), so the item is matched by its text.
  await popup.locator('[role="menu"]').getByRole(role, { name: item }).click();
}

// The menu's chip shows the code of the language on screen: "EN" or "PT".
async function chip(page, code) {
  await page.waitForFunction(
    (expected) => {
      const summary = document.querySelector(
        'details[aria-label="Language and appearance"] > summary, details[aria-label="Idioma e aparência"] > summary',
      );
      return summary !== null && summary.textContent.replace(/\s+/g, " ").includes(expected);
    },
    code,
    { timeout: 15_000 },
  ).catch(async () => {
    const shown = await page.evaluate(() => document.querySelector('details[aria-label="Language and appearance"] > summary, details[aria-label="Idioma e aparência"] > summary')?.textContent ?? "(no chip)");
    throw new Error(`the language chip never showed ${code}; it shows ${JSON.stringify(shown)}`);
  });
}

async function checkLanguage(browser, base, query) {
  const pt = await open(browser, base, { query, locale: "pt-BR" });
  await text(pt.page, "Prévia", "a pt-BR browser opens in Portuguese");
  await chip(pt.page, "PT");
  await choose(pt.page, SETTINGS, "English");
  await text(pt.page, "Swift compiled to WebAssembly", "the menu switches to English");
  await chip(pt.page, "EN");
  await pt.page.reload({ waitUntil: "domcontentloaded" });
  await text(pt.page, "Swift compiled to WebAssembly", "the choice survives a reload");
  await chip(pt.page, "EN");
  assert.deepEqual(pt.errors, [], "language: page errors");
  await pt.context.close();

  const en = await open(browser, base, { query, locale: "fr-FR" });
  await text(en.page, "Swift compiled to WebAssembly", "any other browser opens in English");
  await chip(en.page, "EN");
  await en.context.close();
  return "language";
}

// The chip shows the language of the address, not the stored choice: an address that names the other language wins.
async function checkChipFollowsAddress(browser, base, query) {
  // A reader who chose Portuguese opens an English address.
  const english = await open(browser, base, { query, path: "/en/purpose", locale: "en-US" });
  await choose(english.page, SETTINGS, "Português");
  await settled(english.page, "/pt/purpose", "the language choice");
  await english.page.goto(`${base}/en/purpose${query}`, { waitUntil: "domcontentloaded" });
  await english.page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 60_000 });
  await text(english.page, "Swift compiled to WebAssembly", "an English address with a stored Portuguese choice");
  await chip(english.page, "EN");
  await settled(english.page, "/en/purpose", "the English address");
  assert.deepEqual(english.errors, [], "chip: page errors (English address)");
  await english.context.close();

  // A reader who chose English opens a Portuguese address.
  const portuguese = await open(browser, base, { query, path: "/pt/purpose", locale: "pt-BR" });
  await choose(portuguese.page, SETTINGS, "English");
  await settled(portuguese.page, "/en/purpose", "the language choice");
  await portuguese.page.goto(`${base}/pt/purpose${query}`, { waitUntil: "domcontentloaded" });
  await portuguese.page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 60_000 });
  await text(portuguese.page, "compilado para WebAssembly", "a Portuguese address with a stored English choice");
  await chip(portuguese.page, "PT");
  assert.deepEqual(portuguese.errors, [], "chip: page errors (Portuguese address)");
  await portuguese.context.close();
  return "chip";
}

async function checkAppearance(browser, base, query) {
  const { context, page, errors } = await open(browser, base, { query, scheme: "light" });
  const lightBackground = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
  await choose(page, SETTINGS, "Dark");
  await page.waitForFunction(
    (before) => getComputedStyle(document.body).backgroundColor !== before,
    lightBackground,
    { timeout: 15_000 },
  );
  assert.deepEqual(errors, [], "appearance: page errors");
  await context.close();
  return "appearance";
}

// The home page: the hero, the live counter, and `/pt` alone, which opens the Portuguese Purpose page.
async function checkHome(browser, base, query) {
  const { context, page, errors } = await open(browser, base, { query });
  await text(page, "on the web.", "the hero headline");
  await text(page, "Tapped 0 times", "the live counter starts at zero");
  await page.getByRole("button", { name: "Tap me", exact: true }).click();
  await page.getByRole("button", { name: "Tap me", exact: true }).click();
  await text(page, "Tapped 2 times", "the live counter counts the taps");
  assert.deepEqual(errors, [], "home: page errors");
  await context.close();

  const pt = await open(browser, base, { query, path: "/pt" });
  await settled(pt.page, "/pt/purpose", "an address with only the language");
  await text(pt.page, "Swift compilado para WebAssembly", "/pt opens the Portuguese Purpose page");
  assert.deepEqual(pt.errors, [], "/pt: page errors");
  await pt.context.close();
  return "home";
}

// The Get started page opens from its pill and has its address, title and the four steps.
async function checkStart(browser, base, query) {
  const { context, page, errors } = await open(browser, base, { query });
  await goTo(page, "Get started");
  await text(page, "From zero to your first app", "the Get started page");
  await settled(page, "/en/start", "the Get started page");
  assert.equal((await where(page)).title, "Get started · SwiftUIWeb");
  await text(page, "1. Create the package", "the first step");
  await text(page, "4. Ship it", "the fourth step");
  // A link to a place on the page is not another address: the host scrolls to it (under <base href="/"> the link would
  // resolve to the root and be taken for a page change), so the address and the history stay as they were.
  const before = await page.evaluate(() => {
    const link = document.createElement("a");
    link.href = "#here-on-the-page";
    link.textContent = "a place on the page";
    const target = document.createElement("div");
    target.id = "here-on-the-page";
    document.querySelector("#embedded-app-root").append(link, target);
    return { path: location.pathname, length: history.length };
  });
  await page.evaluate(() => document.querySelector('a[href="#here-on-the-page"]').click());
  await page.waitForTimeout(500);
  const after = await page.evaluate(() => ({ path: location.pathname, length: history.length }));
  assert.equal(after.path, before.path, "a link to a place on the page changed the address");
  assert.equal(after.length, before.length, "a link to a place on the page added a history entry");
  // The same place written with the page's path (`/en/start#here-on-the-page`) is left to the browser too: the address gains the
  // fragment, and the page is not handed to the app as another address.
  await page.evaluate(() => {
    const link = document.createElement("a");
    link.href = "/en/start#here-on-the-page";
    link.textContent = "a place on this page, with its path";
    document.querySelector("#embedded-app-root").append(link);
    link.click();
  });
  await page.waitForTimeout(500);
  const withPath = await page.evaluate(() => ({ path: location.pathname, hash: location.hash }));
  assert.deepEqual(withPath, { path: before.path, hash: "#here-on-the-page" }, "a link with the page's own path and a fragment was not left to the browser");
  // A link to a file of the site that is not a screen (a sitemap) opens in the browser: the app would ignore it.
  await Promise.all([
    page.waitForURL(/\/sitemap\.xml$/, { timeout: 15_000 }),
    page.evaluate(() => {
      const link = document.createElement("a");
      link.href = "/sitemap.xml";
      link.textContent = "the sitemap";
      document.querySelector("#embedded-app-root").append(link);
      link.click();
    }),
  ]);
  assert.deepEqual(errors, [], "start: page errors");
  await context.close();
  return "start";
}

// settledAddress: the address follows the selection a moment after the screen does, so it is read once it has stopped changing.
async function settledAddress(page) {
  let last = page.url();
  for (let stable = 0; stable < 6; ) {
    await page.waitForTimeout(100);
    const now = page.url();
    stable = now === last ? stable + 1 : 0;
    last = now;
  }
  return last;
}

// The page frame (SitePageFrame): one centered column, at most 1040 px wide with 20 px margins, for the header and every page.
async function checkFrame(browser, base, query) {
  for (const width of [1440, 1024, 768, 390]) {
    const left = Math.round((width - Math.min(1040, width - 40)) / 2);
    const { context, page, errors } = await open(browser, base, { query, path: "/en/purpose", width });
    for (const slug of ["purpose", "start", "benefits", "performance", "components", "animations"]) {
      if (slug !== "purpose") {
        await page.goto(`${base}/en/${slug}${query}`, { waitUntil: "domcontentloaded" });
        await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 60_000 });
      }
      // The first heading under the header (the header ends at its divider) and the brand's name in the header.
      const frame = () =>
        page.evaluate(() => {
          const divider = [...document.querySelectorAll("body *")].find((line) => {
            const box = line.getBoundingClientRect();
            return box.height > 0 && box.height <= 2 && box.width >= innerWidth - 2 && box.top < 200;
          });
          const top = divider ? divider.getBoundingClientRect().bottom : 0;
          const heading = [...document.querySelectorAll("h1, h2, [role=heading]")].find((element) => {
            const box = element.getBoundingClientRect();
            return box.width > 0 && box.top > top && box.top < innerHeight && getComputedStyle(element).visibility !== "hidden";
          });
          const brand = [...document.querySelectorAll("*")].find((element) => element.childElementCount === 0 && element.textContent.trim() === "SwiftUIWeb" && element.getBoundingClientRect().width > 0 && element.getBoundingClientRect().top < top &&
            // The header draws both of its arrangements (a ViewThatFits); only the chosen one is visible.
            element.checkVisibility({ opacityProperty: true, visibilityProperty: true }));
          return heading ? { title: Math.round(heading.getBoundingClientRect().left), brand: brand ? Math.round(brand.getBoundingClientRect().left) : null } : null;
        });
      await page.waitForFunction(() => document.querySelector("h1, h2, [role=heading]") !== null, null, { timeout: 15_000 });
      await page.waitForTimeout(400);
      const seen = await frame();
      assert.ok(seen, `${slug} at ${width}px: no heading under the header`);
      assert.ok(Math.abs(seen.title - left) <= 1, `${slug} at ${width}px: the title starts at ${seen.title}px, not at the column's edge (${left}px)`);
      // The brand's name sits after its 30 px mark and a 10 px gap.
      assert.ok(seen.brand !== null && Math.abs(seen.brand - 40 - left) <= 1, `${slug} at ${width}px: the header's brand starts at ${seen.brand}px, not at the column's edge (${left}px)`);
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
      assert.ok(overflow <= 1, `${slug} at ${width}px: the page scrolls ${overflow}px sideways`);
    }
    assert.deepEqual(errors, [], `frame at ${width}px: page errors`);
    await context.close();
  }
  return "frame";
}

// The cards of a row of a grid (SiteCard with fillsHeight) are as tall as the row: a card with less text is not shorter.
async function checkCardRows(browser, base, query) {
  const { context, page, errors } = await open(browser, base, { query, path: "/en/benefits", width: 1440 });
  for (const slug of ["benefits", "start", "performance"]) {
    if (slug !== "benefits") {
      await page.goto(`${base}/en/${slug}${query}`, { waitUntil: "domcontentloaded" });
      await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 60_000 });
    }
    await page.waitForTimeout(600);
    // A card: a surface with a background and a border, a grid cell wide (180 to 400 px) and taller than a badge.
    const rows = await page.evaluate(() => {
      const byTop = new Map();
      for (const element of document.querySelectorAll("body *")) {
        const box = element.getBoundingClientRect(), style = getComputedStyle(element);
        if (box.width < 180 || box.width > 400 || box.height < 100 || box.top > innerHeight || box.bottom < 0) continue;
        const background = style.backgroundColor !== "rgba(0, 0, 0, 0)" && style.backgroundColor !== "transparent";
        if (!background || style.visibility === "hidden") continue;
        const top = Math.round(box.top);
        byTop.set(top, [...(byTop.get(top) ?? []), Math.round(box.height)]);
      }
      return [...byTop.entries()].filter(([, heights]) => heights.length > 1);
    });
    assert.ok(rows.length > 0, `${slug}: no row of cards on the first screen`);
    for (const [top, heights] of rows) {
      assert.ok(Math.max(...heights) - Math.min(...heights) <= 1, `${slug}: the cards of the row at ${top}px end at different heights (${heights})`);
    }
  }
  assert.deepEqual(errors, [], "card rows: page errors");
  await context.close();
  return "card rows";
}

async function checkPages(browser, base, query) {
  const { context, page, errors } = await open(browser, base, { query });
  for (const [tab, heading] of [
    ["Purpose", "Swift compiled to WebAssembly"],
    ["Get started", "From zero to your first app"],
    ["Benefits", "Small updates"],
    ["Components", "Adjust"],
  ]) {
    await goTo(page, tab);
    await text(page, heading, `the ${tab} page`);
  }
  await goTo(page, "Benefits");
  await text(page, "Small updates", "Benefits again");
  const address = await settledAddress(page);
  assert.equal(new URL(address).pathname, "/en/benefits", `the selected page is not in the address as a path: ${address}`);
  await page.reload({ waitUntil: "domcontentloaded" });
  await text(page, "Small updates", "a reload keeps the page");
  if (HEADER_PUSHES_HISTORY) {
    await goBack(page);
    await text(page, "Adjust", "Back returns to the page before", BACK_TIMEOUT);
  }
  assert.deepEqual(errors, [], "pages: page errors");
  await context.close();
  return "pages";
}

// Choosing a page in the header is a link to its address: the browser host pushes a history entry for it, so Back returns to the
// page before (and, from a deep link, never leaves the site). Both Back assertions below depend on that.
const HEADER_PUSHES_HISTORY = true;
// When the screen does not follow Back by itself, the host reloads the page at the entry's address after 600 ms and the app boots
// again: a page change and a boot, so Back is given longer than the 15 s of an ordinary screen.
const BACK_TIMEOUT = 45_000;

// Back, asked again when the browser did not move. Right after a reload, WebKit (under Playwright) sometimes does not take the
// first Back at all: no pop, the address untouched for seconds. That is the engine's timing, not the page's, so the same Back is
// asked again, a few times, only while the address has not changed.
async function goBack(page) {
  // The address is read from the page: `page.url()` can lag behind a same-document pop, and a second Back would then go too far.
  const href = () => page.evaluate(() => location.href).catch(() => null);
  const start = await href();
  for (let attempt = 0; attempt < 4; attempt += 1) {
    await page.goBack().catch(() => {});
    await page.waitForTimeout(1500);
    if ((await href()) !== start) return;
  }
}

const codeOf = (page) =>
  page.evaluate(() => [...document.querySelectorAll("span")].find((e) => !e.children.length && /^(Text|Button|Slider)\(/.test(e.textContent))?.textContent ?? "");

async function checkComponents(browser, base, query) {
  const { context, page, errors } = await open(browser, base, { query });
  await goTo(page, "Components");
  await text(page, "Adjust", "the components page");
  await page.waitForFunction(() => document.body.innerText.includes("Hello, SwiftUIWeb"));
  assert.equal((await codeOf(page)).includes("fontWeight"), false, "bold is off at the start");
  // The Text entry's only toggle is Bold.
  await page.locator('[role="switch"], input[type="checkbox"]').first().click({ force: true });
  await page.waitForFunction(() => document.body.innerText.includes(".fontWeight(.bold)"), null, { timeout: 15_000 });

  const style = await page.evaluate(() => {
    const element = [...document.querySelectorAll("span")].find((e) => !e.children.length && /^Text\(/.test(e.textContent));
    const computed = getComputedStyle(element);
    return { family: computed.fontFamily, space: computed.whiteSpace, text: element.textContent };
  });
  assert.match(style.family, /monospace/, `the code is not monospaced: ${style.family}`);
  assert.equal(style.space, "pre-wrap", "the code loses its spaces");
  assert.match(style.text, /\n {2}\.font\(\.title\)/, `the code lost its indentation: ${JSON.stringify(style.text)}`);

  await page.getByRole("button", { name: "Button", exact: true }).click();
  await page.waitForFunction(() => document.body.innerText.includes('Button("Save")'), null, { timeout: 15_000 });
  await page.fill('input[placeholder="Search components"]', "slid");
  await page.waitForFunction(() => !document.body.innerText.includes("Stepper"), null, { timeout: 15_000 });
  assert.equal(await page.getByRole("button", { name: "Slider", exact: true }).count(), 1);
  await page.fill('input[placeholder="Search components"]', "");
  await page.waitForFunction(() => document.body.innerText.includes("Stepper"), null, { timeout: 15_000 });
  // Every entry of the catalog opens: its name is the title, and it draws a live view and its code.
  for (const name of recipeNames()) {
    await page.getByRole("button", { name, exact: true }).click();
    await page.waitForFunction(
      (expected) => [...document.querySelectorAll("h1, h2, [role=heading]")].some((heading) => heading.textContent.trim() === expected),
      name,
      { timeout: 15_000 },
    ).catch(() => {
      throw new Error(`the ${name} entry never became the title`);
    });
    const shown = await page.evaluate(() => document.body.innerText.includes("Live") && document.body.innerText.includes("Code"));
    assert.ok(shown, `${name}: the live view or the code is missing`);
    // On a wide screen the list stays beside the entry whatever the entry draws: the entry's title starts to the right of
    // the list's column (a 220px column in ComponentsWideLayout), not below it.
    const beside = await page.evaluate((expected) => {
      const heading = [...document.querySelectorAll("h1, h2, [role=heading]")].find(
        (element) => element.textContent.trim() === expected && element.getBoundingClientRect().width > 0,
      );
      // The list is the leftmost column; the entry's own scrollers sit to its right or inside it.
      const list = [...document.querySelectorAll(".scroll-view.scroll-vertical")]
        .filter((view) => view.getBoundingClientRect().width > 100)
        .reduce((left, view) => (left === null || view.getBoundingClientRect().left < left.getBoundingClientRect().left ? view : left), null);
      return heading && list ? { title: heading.getBoundingClientRect().left, listRight: list.getBoundingClientRect().right } : null;
    }, name);
    assert.ok(beside, `${name}: the entry or the list column is missing`);
    assert.ok(beside.title >= beside.listRight, `${name}: the entry fell below the list (its title starts at ${Math.round(beside.title)}px, the list ends at ${Math.round(beside.listRight)}px)`);
  }
  assert.deepEqual(errors, [], "components: page errors");
  await context.close();
  return "components";
}

// On a phone the Components page has one native select of entries under its title; the entry it names is on the first screen.
async function checkPhone(browser, base, query) {
  const { context, page, errors } = await open(browser, base, { query, width: 390 });
  for (const tab of ["Purpose", "Get started", "Components"]) {
    await goTo(page, tab);
    await page.waitForTimeout(400);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    assert.ok(overflow <= 1, `${tab}: the page scrolls ${overflow}px sideways at 390px`);
  }
  assert.ok(await visibleMenu(page, SETTINGS), "the Language and appearance menu is not reachable on a phone");

  // The entry picker: a native select whose options are the catalog entries.
  const picker = page.locator("select").filter({ has: page.locator("option", { hasText: "Stepper" }) }).first();
  // It is a field (border and indicator), not bare text: nothing else tells a visitor it opens a list of components.
  const field = await picker.evaluate((select) => ({
    plain: select.getAttribute("data-field-chrome") === "plain",
    border: Number.parseFloat(getComputedStyle(select).borderTopWidth),
    indicator: getComputedStyle(select).backgroundImage !== "none",
  }));
  assert.ok(!field.plain && field.border > 0 && field.indicator, `the entry picker does not look like a control: ${JSON.stringify(field)}`);
  // The menu of pages gives every page the same highlight width, whatever its label.
  const pageLinkWidths = () =>
    page.evaluate(() =>
      [...document.querySelectorAll("a")]
        .filter((a) => a.getBoundingClientRect().width > 0 && /^(Purpose|Get started|Benefits|Performance|Components|Animations)$/.test(a.textContent.trim()))
        .map((a) => Math.round(a.getBoundingClientRect().width)),
    );
  const menuButton = page.locator('button[aria-label="Menu"]:visible').first();
  if ((await pageLinkWidths()).length === 0) {
    await menuButton.click();
    await page.waitForTimeout(400);
  }
  const rows = await pageLinkWidths();
  assert.ok(rows.length >= 5, `the menu of pages shows ${rows.length} links`);
  assert.equal(new Set(rows).size, 1, `the highlights of the menu of pages have different widths: ${rows}`);
  // The highlight does not touch its icon: the row has padding before the label.
  const inset = await page.evaluate(() => {
    const link = [...document.querySelectorAll("a")].find((a) => a.getBoundingClientRect().width > 0 && a.textContent.trim() === "Components");
    return Math.round(link.querySelector("svg").getBoundingClientRect().left - link.getBoundingClientRect().left);
  });
  assert.ok(inset >= 8, `the icon of a row of the menu of pages is ${inset}px from the edge of its highlight`);
  await menuButton.click();
  const entryName = await picker.locator("option:checked").textContent();
  const onFirstScreen = (name) =>
    page.evaluate((expected) => {
      const heading = [...document.querySelectorAll("h1, h2, [role=heading]")].find(
        (element) => element.textContent.trim() === expected && element.getBoundingClientRect().width > 0,
      );
      if (!heading) return null;
      const box = heading.getBoundingClientRect();
      return { top: Math.round(box.top), left: Math.round(box.left), visible: box.top < innerHeight && box.bottom > 0 };
    }, name);
  const first = await onFirstScreen(entryName.trim());
  assert.ok(first && first.visible, `the entry ${entryName} is not on the first screen of a phone: ${JSON.stringify(first)}`);
  assert.ok(first.left < 60, `the entry is not under the picker on a phone (its title starts at ${first.left}px)`);

  await picker.selectOption({ label: "Slider" });
  await settled(page, "/en/components/slider", "the entry picked on a phone");
  const slider = await onFirstScreen("Slider");
  assert.ok(slider && slider.visible, `the Slider entry did not show on the first screen: ${JSON.stringify(slider)}`);
  assert.deepEqual(errors, [], "phone: page errors");
  await context.close();
  return "phone";
}

const where = (page) => page.evaluate(() => ({ path: location.pathname, search: location.search, title: document.title, entries: history.length }));
const settled = async (page, expected, what) => {
  await page.waitForFunction((path) => location.pathname === path && !location.search.includes("tab-selection"), expected, { timeout: 15_000 }).catch(async () => {
    throw new Error(`${what}: the address never became ${expected}; it is ${JSON.stringify(await where(page))}`);
  });
};

// The address, the title and the history follow the page: readable paths from `.path`, the language first, the catalog entry last.
async function checkAddresses(browser, base, query) {
  const { context, page, errors } = await open(browser, base, { query });
  await settled(page, "/en/purpose", "the start page");
  assert.equal((await where(page)).title, "Purpose · SwiftUIWeb");

  await goTo(page, "Benefits");
  await settled(page, "/en/benefits", "the Benefits page");
  await goTo(page, "Components");
  await settled(page, "/en/components/text", "the Components page");
  const entriesBefore = (await where(page)).entries;

  // Another entry or another language changes the address of the page that is shown, and adds nothing to the history.
  await page.getByRole("button", { name: "Slider", exact: true }).click();
  await settled(page, "/en/components/slider", "the Slider entry");
  assert.equal((await where(page)).title, "Slider · Components · SwiftUIWeb");
  await choose(page, SETTINGS, "Português");
  await settled(page, "/pt/components/slider", "the language");
  assert.equal((await where(page)).title, "Slider · Componentes · SwiftUIWeb");
  assert.equal((await where(page)).entries, entriesBefore, "an entry or a language was added to the history");

  await page.reload({ waitUntil: "domcontentloaded" });
  await text(page, "Ao vivo", "a reload keeps the Portuguese Components page");
  await settled(page, "/pt/components/slider", "after a reload");

  // Back shows the page before in the language the reader has now: choosing Portuguese is not undone by going back.
  if (HEADER_PUSHES_HISTORY) {
    await goBack(page);
    await settled(page, "/pt/benefits", "Back");
    await text(page, "Benefícios", "Back returns to Benefits, in Portuguese", BACK_TIMEOUT);
  }
  await context.close();

  // An address typed or shared opens the page it names, before anything else is drawn.
  const deep = await open(browser, base, { query, path: "/pt/components/stepper", locale: "en-US" });
  await text(deep.page, "Ao vivo", "a deep link opens in the language it names");
  await settled(deep.page, "/pt/components/stepper", "the deep link");
  assert.equal((await where(deep.page)).title, "Stepper · Componentes · SwiftUIWeb");
  assert.ok(await deep.page.evaluate(() => document.querySelector(".stepper-control") !== null), "the deep link did not open the Stepper entry");
  assert.equal((await where(deep.page)).entries, 2, "opening a deep link added history entries");
  assert.deepEqual(deep.errors, [], "deep link: page errors");
  await deep.context.close();

  const withoutLanguage = await open(browser, base, { query, path: "/benefits" });
  await text(withoutLanguage.page, "Small updates", "an address without a language opens the page");
  await settled(withoutLanguage.page, "/en/benefits", "the language is added");
  await withoutLanguage.context.close();

  // The Get started page's address and title.
  const start = await open(browser, base, { query, path: "/pt/start" });
  await settled(start.page, "/pt/start", "the Portuguese Get started address");
  assert.equal((await where(start.page)).title, "Começar · SwiftUIWeb");
  assert.deepEqual(start.errors, [], "start address: page errors");
  await start.context.close();
  assert.deepEqual(errors, [], "addresses: page errors");
  await context.close();
  return "addresses";
}

// The Animations page. The cards sit in plain stacks, not a lazy grid, because a lazy cell does not redraw when a state of its own changes.
// The page draws each arrangement of the cards once to measure it, so a control is looked for among the visible ones.
async function checkAnimations(browser, base, query) {
  const { context, page, errors } = await open(browser, base, { query });
  await goTo(page, "Animations");
  await settled(page, "/en/animations", "the Animations page");
  await text(page, "Numbers that roll", "the first animation");
  assert.equal((await where(page)).title, "Animations · SwiftUIWeb");
  const press = (name) => page.getByRole("button", { name, exact: true }).locator("visible=true").first().click();

  // Numbers that roll: the number changes by what is pressed, whatever the roll shows on the way.
  await press("+100");
  await text(page, "228", "128 + 100");
  await press("+7");
  await text(page, "235", "228 + 7");
  await press("−7");
  await text(page, "228", "235 - 7");

  // Transitions: a view leaves and comes back, the button naming what it does next. The picker and the button sit on one line, and
  // the button keeps its size and place when its label changes.
  // The kind of transition is a menu drawn like a button: the same height as Hide, on the same line.
  const kindMenu = page.locator(".menu-popup > summary:visible", { hasText: "Opacity" }).first();
  const hideButton = page.getByRole("button", { name: "Hide", exact: true }).locator("visible=true").first();
  const [menuBox, hideBox] = [await kindMenu.boundingBox(), await hideButton.boundingBox()];
  assert.ok(Math.abs(menuBox.y + menuBox.height / 2 - (hideBox.y + hideBox.height / 2)) <= 1, "the kind menu and the Hide button are not on one line");
  assert.ok(Math.abs(menuBox.height - hideBox.height) <= 1, `the kind menu is ${menuBox.height} tall and the Hide button ${hideBox.height}`);
  // Choosing a kind changes the menu's label and nothing else on the line moves.
  await kindMenu.click();
  await page.locator('.menu-popup [role="menu"]:popover-open').first().getByRole("button", { name: "Scale", exact: true }).click();
  await text(page, "Scale", "the chosen kind");
  const afterChoice = [await page.locator(".menu-popup > summary:visible", { hasText: "Scale" }).first().boundingBox(), await hideButton.boundingBox()];
  assert.ok(Math.abs(afterChoice[0].width - menuBox.width) <= 0.5 && Math.abs(afterChoice[1].x - hideBox.x) <= 0.5, "choosing a kind resized the menu or moved Hide");
  await press("Hide");
  await text(page, "Show", "the Hide button after hiding");
  await press("Show");
  await text(page, "Hide", "the Show button after showing");
  const hideAgain = await page.getByRole("button", { name: "Hide", exact: true }).locator("visible=true").first().boundingBox();
  assert.ok(Math.abs(hideAgain.x - hideBox.x) <= 0.5 && Math.abs(hideAgain.width - hideBox.width) <= 0.5, "the button moved or changed size");
  const showWidth = await (async () => { await press("Hide"); await text(page, "Show", "the Hide button after hiding"); const box = await page.getByRole("button", { name: "Show", exact: true }).locator("visible=true").first().boundingBox(); await press("Show"); await text(page, "Hide", "the Show button after showing"); return box.width; })();
  assert.ok(Math.abs(showWidth - hideBox.width) <= 0.5, `Show is ${showWidth} wide and Hide ${hideBox.width}`);
  // The open menu stays under its label when the card commits behind it: the page places the panel (a fixed popover in the
  // top layer), and a publication that does not carry that place must not take it away (the panel jumped to the window's
  // corner). The view is hidden through the DOM, without a press, so the menu stays open.
  await page.locator(".menu-popup > summary:visible", { hasText: "Scale" }).first().click();
  await page.locator('.menu-popup [role="menu"]:popover-open').first().waitFor();
  await page.evaluate(() => [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "Hide" && b.getBoundingClientRect().width > 0).click());
  await text(page, "Show", "the Hide button after hiding with the menu open");
  await page.waitForTimeout(400);
  const menuPlace = await page.evaluate(() => {
    const menu = [...document.querySelectorAll(".menu-popup")].find((m) => m.open);
    const panel = menu?.querySelector(':scope > [role="menu"]'), summary = menu?.querySelector(":scope > summary");
    if (!panel || !summary) return null;
    const [p, s] = [panel.getBoundingClientRect(), summary.getBoundingClientRect()];
    return { left: p.left, top: p.top, summaryLeft: s.left, summaryBottom: s.bottom };
  });
  assert.ok(menuPlace, "the menu closed when the card committed");
  assert.ok(menuPlace.top >= menuPlace.summaryBottom - 1 && Math.abs(menuPlace.left - menuPlace.summaryLeft) <= 8, `after a commit the open menu's panel is at ${menuPlace.left},${menuPlace.top}, not under its label (${menuPlace.summaryLeft},${menuPlace.summaryBottom})`);
  await page.keyboard.press("Escape");
  await page.evaluate(() => { for (const m of document.querySelectorAll(".menu-popup")) m.open = false; });
  await press("Show");
  await text(page, "Hide", "the Show button after showing");

  // Symbol effects: Listen starts the pulse and offers to stop it. Progress ring: the value is the number beside it.
  await press("Listen");
  await text(page, "Stop", "the Listen button after starting");
  await press("100%");
  await text(page, "100%", "the ring at 100%");
  await press("60%");
  await text(page, "60%", "the ring at 60%");

  // The page keeps its place when a card's content changes size: the star swaps for another glyph and the ring's number rolls. A grid that
  // measured its choices again whenever a card changed (a ViewThatFits of stacks did) put the page back at the top.
  const scrollTop = () => page.evaluate(() => Math.max(window.scrollY, ...[...document.querySelectorAll("*")].map((element) => element.scrollTop)));
  await page.mouse.move(640, 500);
  await page.mouse.wheel(0, 900);
  await page.waitForFunction(() => Math.max(window.scrollY, ...[...document.querySelectorAll("*")].map((element) => element.scrollTop)) > 100, null, { timeout: 15_000 });
  const placed = await scrollTop();
  for (const control of ["Star", "100%", "60%"]) {
    await press(control);
    await page.waitForTimeout(900);
    assert.ok(Math.abs((await scrollTop()) - placed) <= 2, `pressing ${control} moved the page from ${placed} to ${await scrollTop()}`);
  }
  await page.mouse.wheel(0, -3000);
  await page.waitForFunction(() => Math.max(window.scrollY, ...[...document.querySelectorAll("*")].map((element) => element.scrollTop)) < 5, null, { timeout: 15_000 });

  // A card's code opens over the page and closes with Done.
  await page.getByRole("button", { name: /Code$/ }).locator("visible=true").first().click();
  await text(page, "contentTransition(.numericText(value: Double(count)))", "the numeric text code");
  // The sheet is over the whole page, not under the cards drawn after the one it opened from: at its corners and its middle the
  // element on top belongs to it. It is looked at once it has come in (it scales and fades in), so the points are tried until they hold.
  const coveredPoints = () => page.evaluate(() => {
    const sheet = document.querySelector(".sheet-panel, [role=dialog], [aria-modal]");
    const rect = sheet.getBoundingClientRect();
    return [[0.1, 0.1], [0.5, 0.5], [0.9, 0.1], [0.1, 0.9], [0.9, 0.9]].map(([fx, fy]) => sheet.contains(document.elementFromPoint(rect.x + rect.width * fx, rect.y + rect.height * fy)));
  });
  let onTop = await coveredPoints();
  for (let attempt = 0; attempt < 30 && onTop.includes(false); attempt += 1) {
    await page.waitForTimeout(100);
    onTop = await coveredPoints();
  }
  assert.deepEqual(onTop, [true, true, true, true, true], "the code sheet is under part of the page");
  await press("Done");
  await page.waitForFunction(() => !document.body.innerText.includes("Double(count)"), null, { timeout: 15_000 });
  assert.deepEqual(errors, [], "animations: page errors");
  await context.close();

  // Portuguese, from its own address.
  const pt = await open(browser, base, { query, path: "/pt/animations", locale: "pt-BR" });
  await text(pt.page, "Números que rolam", "the Portuguese Animations page");
  assert.equal((await where(pt.page)).title, "Animações · SwiftUIWeb");
  assert.deepEqual(pt.errors, [], "animations (pt): page errors");
  await pt.context.close();

  // A phone: the cards stack in one column and nothing scrolls sideways.
  const phone = await open(browser, base, { query, path: "/en/animations", width: 390 });
  await text(phone.page, "Numbers that roll", "the Animations page on a phone");
  const overflow = await phone.page.evaluate(() => Math.max(...[...document.querySelectorAll("*")].map((element) => element.getBoundingClientRect().right)) - innerWidth);
  assert.ok(overflow <= 1, `the Animations page overflows a phone by ${overflow}px`);
  assert.deepEqual(phone.errors, [], "animations (phone): page errors");
  await phone.context.close();
  return "animations";
}

// The Performance page: the headline numbers first, the measurements behind a header button, and a segmented CPU picker.
async function checkPerformance(browser, base, query) {
  const { context, page, errors } = await open(browser, base, { query });
  await goTo(page, "Performance");
  await settled(page, "/en/performance", "the Performance page");
  await text(page, "Performance against React", "the Performance page");
  await text(page, "At a glance", "the headline numbers");
  assert.equal((await where(page)).title, "Performance · SwiftUIWeb");

  // The bars are behind a header button: none is made until it is opened (a `<details>` would have laid them out closed, with no
  // padding and no width), and then every card has its padding and its bars the width of the card.
  assert.equal(await page.locator("progress").count(), 0, "the measurements were made before they were asked for");
  await page.getByRole("button", { name: /^All \d+ measurements/ }).click();
  await page.waitForFunction(() => document.querySelectorAll("progress").length >= 54, null, { timeout: 15_000 });
  const firstCard = await page.evaluate(() => {
    const bar = document.querySelector("progress");
    let card = bar;
    while (card && getComputedStyle(card).borderTopLeftRadius !== "12px") card = card.parentElement;
    const box = card.getBoundingClientRect();
    const barBox = bar.getBoundingClientRect();
    return { padding: getComputedStyle(card).paddingLeft, barToCard: Math.round(barBox.width / box.width * 100) };
  });
  assert.equal(firstCard.padding, "16px", "a measurement card has no padding");
  assert.ok(firstCard.barToCard >= 85, `a bar is only ${firstCard.barToCard}% of its card`);
  const rows = () => page.evaluate(() => ({ bars: document.querySelectorAll("progress").length, text: document.body.innerText }));
  const normal = await rows();
  assert.ok(normal.bars >= 54, `a bar for each of the three sides of each metric: found ${normal.bars}`);
  assert.match(normal.text, /Measured on \d{4}-\d{2}-\d{2}, \d+ alternating rounds per metric, Chromium/, "the conditions are not shown");
  assert.match(normal.text, /In this set, React took more than SwiftUIWeb on \d+ measures, less on \d+/, "the summary is not shown");
  assert.match(normal.text, /Cold load, to the board on screen/);

  // The CPU rate is a segmented picker, not a select.
  const cpu = page.locator('[data-picker-style="segmented"]');
  assert.equal(await cpu.getAttribute("role"), "radiogroup", "the CPU rate is not a segmented picker");
  assert.equal(await page.locator('select[aria-label="CPU"]').count(), 0, "the CPU rate is still a select");
  const slower = cpu.locator('[role="radio"]', { hasText: "4x slower" });
  await slower.click();
  await page.waitForFunction(
    () => document.querySelector('[data-picker-style="segmented"] [role="radio"][aria-checked="true"]')?.textContent.includes("4x slower") === true,
    null,
    { timeout: 15_000 },
  ).catch(async () => {
    const checked = await page.evaluate(() => [...document.querySelectorAll('[data-picker-style="segmented"] [role="radio"]')].map((radio) => `${radio.textContent.trim()}=${radio.getAttribute("aria-checked")}`));
    throw new Error(`the 4x slower rate is not chosen; the segments are ${checked.join(", ")}`);
  });
  // Another CPU rate shows that rate's measurements.
  await page.waitForFunction((before) => document.body.innerText !== before, normal.text, { timeout: 15_000 });
  assert.ok((await rows()).bars >= 54, "the 4x rate shows no bars");
  assert.deepEqual(errors, [], "performance: page errors");
  await context.close();
  return "performance";
}

// The header fits a phone: at 320, 360 and 375 px nothing overflows sideways, and the brand, the page Menu and the settings
// menu sit inside the screen without overlapping.
async function checkHeader(browser, base, query) {
  for (const width of [320, 360, 375]) {
    const { context, page, errors } = await open(browser, base, { query, width, locale: "pt-BR" });
    const result = await page.evaluate(() => {
      const box = (elements) => {
        const rects = elements.filter(Boolean).map((element) => element.getBoundingClientRect()).filter((rect) => rect.width > 0);
        if (rects.length === 0) return null;
        return {
          left: Math.min(...rects.map((rect) => rect.left)),
          right: Math.max(...rects.map((rect) => rect.right)),
          top: Math.min(...rects.map((rect) => rect.top)),
          bottom: Math.max(...rects.map((rect) => rect.bottom)),
        };
      };
      // The header draws each of its items for both layouts and shows one: the drawn copy is the one with a box.
      const drawn = (elements) => elements.find((element) => element.getBoundingClientRect().width > 0);
      const leaf = (label) => drawn([...document.querySelectorAll("span, p, div")].filter((element) => !element.children.length && element.textContent.trim() === label));
      const menu = drawn([...document.querySelectorAll('button[aria-label="Menu"]')]);
      const settings = drawn([...document.querySelectorAll('details[aria-label="Language and appearance"] > summary, details[aria-label="Idioma e aparência"] > summary')]);
      return {
        brand: box([leaf("SwiftUIWeb"), leaf("SwiftUI na web")]),
        menu: box([menu]),
        settings: box([settings]),
        overflow: document.documentElement.scrollWidth - window.innerWidth,
        viewport: window.innerWidth,
      };
    });
    assert.ok(result.overflow <= 1, `${width}px: the header scrolls ${result.overflow}px sideways`);
    for (const part of ["brand", "menu", "settings"]) {
      assert.ok(result[part], `${width}px: the header's ${part} is not drawn`);
      assert.ok(result[part].left >= 0 && result[part].right <= result.viewport, `${width}px: the ${part} is outside the screen: ${JSON.stringify(result[part])}`);
    }
    const overlap = (a, b) => a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;
    for (const [a, b] of [["brand", "menu"], ["brand", "settings"], ["menu", "settings"]]) {
      assert.ok(!overlap(result[a], result[b]), `${width}px: the ${a} and the ${b} overlap: ${JSON.stringify([result[a], result[b]])}`);
    }
    assert.deepEqual(errors, [], `${width}px header: page errors`);
    await context.close();
  }
  return "header";
}

// SwiftUI's Stepper draws its label and two buttons, never its value; the value stays for assistive technology.
// The hero's actions on a phone: each keeps its label on one line (a squeezed button wraps it and grows a second line), none passes the
// edge of the screen, and the row takes the arrangement that fits: stacked when narrow, the two buttons side by side from 390 px,
// all three in a row from 430 px. The page draws each arrangement once to measure it, so the actions are looked for among the visible ones.
async function checkHeroActions(browser, base, query) {
  for (const width of [320, 360, 390, 430, 600]) {
    const { context, page, errors } = await open(browser, base, { query, path: "/en/purpose", width });
    await text(page, "Browse components", `the hero's actions at ${width}`);
    const action = (name) => page.getByRole("link", { name, exact: true }).locator("visible=true").last();
    const boxes = {};
    for (const name of ["Get started", "Browse components", "GitHub"]) boxes[name] = await action(name).boundingBox();
    for (const [name, box] of Object.entries(boxes)) {
      assert.ok(box, `${name} is not on the page at ${width}`);
      assert.ok(box.height <= (name === "GitHub" ? 30 : 48), `${name} wraps onto a second line at ${width} (${box.height} tall)`);
      assert.ok(box.x >= 0 && box.x + box.width <= width + 0.5, `${name} passes the edge of a ${width} px screen (${box.x + box.width})`);
    }
    const [start, components, source] = [boxes["Get started"], boxes["Browse components"], boxes["GitHub"]];
    const sameRow = (a, b) => Math.abs(a.y + a.height / 2 - (b.y + b.height / 2)) < 4;
    if (width < 390) {
      assert.ok(components.y > start.y + start.height - 1 && source.y > components.y + components.height - 1, `the actions are not stacked at ${width}`);
    } else if (width < 430) {
      assert.ok(sameRow(start, components) && source.y > start.y + start.height - 1, `the buttons are not side by side with the source under them at ${width}`);
    } else {
      assert.ok(sameRow(start, components) && sameRow(components, source), `the actions are not in one row at ${width}`);
    }
    assert.deepEqual(errors, [], `hero actions at ${width}: page errors`);
    await context.close();
  }
  return "hero";
}

async function checkStepper(browser, base, query) {
  const { context, page } = await open(browser, base, { query });
  await goTo(page, "Components");
  await page.getByRole("button", { name: "Stepper", exact: true }).click();
  await page.waitForFunction(() => document.querySelector(".stepper-control"), null, { timeout: 15_000 });
  const stepper = await page.evaluate(() => {
    const control = document.querySelector(".stepper-control");
    const value = control.querySelector('[role="spinbutton"]');
    const box = value.getBoundingClientRect();
    return { text: value.textContent, valuenow: value.getAttribute("aria-valuenow"), width: box.width, drawn: control.innerText };
  });
  assert.equal(stepper.text, "", "the stepper draws its value");
  assert.ok(stepper.width <= 1, `the stepper's value takes room: ${stepper.width}px`);
  assert.ok(stepper.valuenow !== null, "the stepper lost aria-valuenow");
  assert.equal(stepper.drawn.replace(/[−+\s]/g, "").trim(), "Guests:2", `the stepper draws ${JSON.stringify(stepper.drawn)}`);
  await context.close();
  return "stepper";
}

// What the catalog showed wrongly and no longer does: a Toggle's knob low in its track, a DisclosureGroup resizing to its content,
// a Menu clipped or covered, a List with squeezed rows that could not scroll, and one scroller for the whole catalog.
async function checkControls(browser, base, query) {
  // The catalog draws once the page has measured its width, a moment after the runtime mounts: wait for the entry's "Live" card.
  const entry = async (name) => {
    const opened = await open(browser, base, { query, path: `/en/components/${name}` });
    await opened.page.waitForFunction(() => document.body.innerText.includes("Live"), undefined, { timeout: 15_000 });
    return opened;
  };

  const toggle = await entry("toggle");
  const knob = await toggle.page.evaluate(() => {
    const input = document.querySelector("input.check-input");
    const box = input.getBoundingClientRect();
    const border = parseFloat(getComputedStyle(input).borderLeftWidth);
    const after = getComputedStyle(input, "::after");
    const size = parseFloat(after.width);
    const shift = after.transform === "none" ? 0 : new DOMMatrix(after.transform).m41;
    const inner = { width: box.width - 2 * border, height: box.height - 2 * border };
    return { top: parseFloat(after.top), bottom: inner.height - parseFloat(after.top) - size, left: parseFloat(after.left) + shift, right: inner.width - parseFloat(after.left) - shift - size, on: input.checked };
  });
  assert.equal(knob.on, true, "the Toggle entry starts on");
  assert.equal(knob.top, knob.bottom, `the knob is not centred in its track: ${JSON.stringify(knob)}`);
  assert.equal(knob.right, knob.top, `the knob does not sit as far from the end of its track as from its sides: ${JSON.stringify(knob)}`);
  assert.deepEqual(toggle.errors, [], "toggle: page errors");
  await toggle.context.close();

  const group = await entry("disclosuregroup");
  // The catalog keeps the Performance page's disclosure in the DOM while that page is hidden: the entry's own one is the visible one.
  await group.page.waitForSelector("details.disclosure-group:visible");
  // The page first lays out the narrow column and then switches to the wide one (the list's 220px column): measure after that.
  await group.page.waitForFunction(() => [...document.querySelectorAll(".scroll-view.scroll-vertical")].some((view) => Math.round(view.getBoundingClientRect().width) === 220), null, { timeout: 15_000 });
  const widths = [];
  for (let step = 0; step < 3; step += 1) {
    widths.push(await group.page.evaluate(() => Math.round([...document.querySelectorAll("details.disclosure-group")].find((d) => d.getBoundingClientRect().width > 0).getBoundingClientRect().width)));
    await group.page.locator("details.disclosure-group:visible > summary").click();
    await group.page.waitForTimeout(400);
  }
  assert.equal(new Set(widths).size, 1, `a DisclosureGroup changes width when it opens or closes: ${widths}`);
  await group.context.close();

  // The catalog's Menu is the last menu drawn on the page: the header's menus come before it, and a page that is hidden draws none of its own.
  const menu = await entry("menu");
  await menu.page.locator(".menu-popup:visible").last().locator("summary").click();
  // The browser reports a `<details>` opening in a task of its own, then the host moves the panel to the top layer.
  await menu.page.waitForFunction(() => [...document.querySelectorAll(".menu-popup")].filter((popup) => popup.getBoundingClientRect().width > 0).at(-1)?.querySelector(":scope > [role=menu]")?.matches(":popover-open"), undefined, { timeout: 5000 });
  const shown = await menu.page.evaluate(() => {
    const popup = [...document.querySelectorAll(".menu-popup")].filter((popup) => popup.getBoundingClientRect().width > 0).at(-1);
    const panel = popup.querySelector(":scope > [role=menu]");
    const box = panel.getBoundingClientRect();
    const middle = document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2);
    const summary = popup.querySelector(":scope > summary").getBoundingClientRect();
    return { topLayer: panel.matches(":popover-open"), onTop: panel.contains(middle), below: box.top >= summary.bottom - 1, items: panel.querySelectorAll("button").length };
  });
  assert.equal(shown.topLayer, true, "the Menu's panel is not in the top layer");
  assert.equal(shown.onTop, true, "something covers the Menu's panel");
  assert.equal(shown.below, true, "the Menu's panel is not under its label");
  await menu.page.locator(".menu-popup:visible").last().locator('[role="menu"] button').first().click();
  await menu.page.waitForFunction(() => ![...document.querySelectorAll(".menu-popup")].filter((popup) => popup.getBoundingClientRect().width > 0).at(-1).open, undefined, { timeout: 5000 });
  assert.equal(
    await menu.page.evaluate(() => [...document.querySelectorAll(".menu-popup")].filter((popup) => popup.getBoundingClientRect().width > 0).at(-1).querySelector(":scope > [role=menu]").matches(":popover-open")),
    false,
    "choosing an item leaves the panel open",
  );
  assert.deepEqual(menu.errors, [], "menu: page errors");
  await menu.context.close();

  const list = await entry("list");
  await list.page.waitForSelector(".list-view");
  await list.page.locator("input[type=range]").fill("8");
  await list.page.waitForFunction(() => document.querySelector(".list-view")?.children.length === 8, undefined, { timeout: 10_000 });
  const rows = await list.page.evaluate(() => {
    const view = document.querySelector(".list-view");
    const boxes = [...view.children].map((row) => row.getBoundingClientRect());
    return { overflowY: getComputedStyle(view).overflowY, scrolls: view.scrollHeight > view.clientHeight, overlap: boxes.slice(1).some((box, index) => box.top < boxes[index].bottom - 0.5) };
  });
  assert.equal(rows.overflowY, "auto", "a List with more rows than its height does not scroll");
  assert.equal(rows.scrolls, true, "the List has nothing to scroll");
  assert.equal(rows.overlap, false, "the rows of a List overlap each other");
  await list.context.close();

  const wide = await entry("text");
  const scrollers = await wide.page.evaluate(() => {
    const [listColumn, entryColumn] = [...document.querySelectorAll(".scroll-view.scroll-vertical")].filter((view) => view.getBoundingClientRect().width > 100).slice(-2);
    return { page: document.documentElement.scrollHeight - innerHeight, listScrolls: listColumn.scrollHeight > listColumn.clientHeight, distinct: listColumn !== entryColumn, listWidth: Math.round(listColumn.getBoundingClientRect().width) };
  });
  assert.ok(scrollers.page <= 1, `the page itself scrolls (${scrollers.page}px)`);
  assert.equal(scrollers.distinct, true, "the list and the entry share one scroller");
  assert.equal(scrollers.listScrolls, true, "the component list does not scroll on its own");
  await wide.context.close();
  return "controls";
}

async function main() {
  const server = await serveBundle({ bundle: BUNDLE, port: await freePort(), logName: "showcase-site-server" });
  const browser = await launch();
  try {
    for (const [mode, query] of [["Worker", ""], ["main thread", "?render-in-worker=0"]]) {
      const done = [];
      for (const check of [
        checkLanguage,
        checkChipFollowsAddress,
        checkAppearance,
        checkHome,
        checkStart,
        checkPages,
        checkFrame,
        checkCardRows,
        checkComponents,
        checkPhone,
        checkHeader,
        checkHeroActions,
        checkStepper,
        checkAddresses,
        checkPerformance,
        checkAnimations,
        checkControls,
      ]) {
        done.push(await check(browser, server.base, query));
      }
      console.log(`[${engineName()}/${mode}] ${done.join(", ")}`);
    }
    console.log("Showcase site browser test passed.");
  } finally {
    await browser.close();
    await server.stop();
  }
}

await runSuite(main);
