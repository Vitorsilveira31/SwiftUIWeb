#!/usr/bin/env bun
// Smoke-test the independent normal-syntax lowering fixture in Chromium.
import assert from "node:assert/strict";
import { bundleFilePath } from "./hash-release-bundle.mjs";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { isDeepStrictEqual, parseArgs } from "node:util";
import { launch, runSuite, serveStatic } from "./browser-test-support.mjs";

const PARITY_GEOMETRY = `() => {
  const q = id => document.querySelector(\`[data-testid="\${id}"]\`);
  const rect = el => { const r = el.getBoundingClientRect(); return {x: r.x, y: r.y, w: r.width, h: r.height}; };
  const style = el => getComputedStyle(el);
  const ring = q('parity-trim-ring').querySelector('path');
  return {
    bgColor: style(q('parity-bg-color')).backgroundColor,
    bgMember: style(q('parity-bg-member')).backgroundColor,
    bgGradient: style(q('parity-bg-gradient')).backgroundImage,
    base: rect(q('parity-overlay-base')), badge: rect(q('parity-badge')),
    dim: rect(q('parity-overlay-paint')), dimLayer: rect(q('parity-overlay-paint').querySelector(':scope > .shape-layer')),
    capsule: rect(q('parity-bg-capsule')), capsuleText: rect(q('parity-bg-capsule').querySelector('[data-layout-leaf="text"]')),
    unevenClip: ['borderTopLeftRadius', 'borderTopRightRadius', 'borderBottomRightRadius', 'borderBottomLeftRadius'].map(k => style(q('parity-uneven-clip'))[k]),
    unevenPath: q('parity-uneven-fill').querySelector('path')?.getAttribute('d') || '',
    ringDash: style(ring).strokeDasharray,
    combine: [q('parity-a11y-combine').getAttribute('role'), q('parity-a11y-combine').getAttribute('aria-label'),
      [...q('parity-a11y-combine').querySelectorAll('[data-layout-leaf="text"]')].every(e => e.getAttribute('aria-hidden') === 'true')],
    ignore: [q('parity-a11y-ignore').getAttribute('aria-label'), [...q('parity-a11y-ignore').children].every(e => e.getAttribute('aria-hidden') === 'true')],
    contain: [q('parity-a11y-contain').getAttribute('role'), q('parity-a11y-contain').querySelector('button')?.getAttribute('aria-hidden') ?? null],
    scroll: rect(q('parity-relative-scroll')),
    cards: [0, 1, 2].map(i => rect(q(\`parity-relative-card-\${i}\`))),
    dateFormat: q('parity-date-format').textContent, dateRange: q('parity-date-range').textContent,
    relative: q('parity-date-relative').textContent, timer: q('parity-date-timer').textContent,
    zIndex: style(q('parity-zindex')).zIndex,
    iconOnly: q('parity-label-icon-only').getAttribute('aria-label'),
    controlGroup: q('parity-control-group').getAttribute('role'),
    area: rect(q('parity-position-area')), dot: rect(q('parity-position-dot').querySelector('.shape-layer')),
  };
}`;

const MEASUREMENT_LINES = [
  "en_US: 11.023 lb | 68°F",
  "pt_BR: 5 kg | 20 °C",
  "en_US long: 11.023 pounds | 68 degrees Fahrenheit",
  "pt_BR long: 5 quilogramas | 20 graus Celsius",
  "en_US provided: 5 kg | 20°C",
  "unit equality: same different different same different same",
  "archive rejects NSObject: true",
];

// Produced by Apple's Foundation (macOS): the stream-based JSONSerialization fixture must print the same text.
const JSON_STREAM_LINES = [
  "json stream write: 55 no error 0 2 true 6 false",
  'json stream bytes: {"name":"stream","nested":{"ok":true},"values":[1,2,3]}',
  'json stream pretty: 30 {|  "a" : [|    1,|    2|  ]|}',
  "json stream read: stream 3 5 false",
  "json stream truncated: throws",
  "json stream fragment: throws",
  "json stream fragment allowed: 5",
  "json stream overflow: -1 NSCocoaErrorDomain 512 7 false",
  "stream reads: 0 -1 true 3 2 2 5 false 0 5",
  'json typed int: true {"a":1}',
  'json typed string: true {"a":"x"}',
  'json typed bool: true {"a":true}',
  'json typed double: true {"a":1.5,"b":2}',
  'json typed null: true {"a":null}',
  'json typed array: true {"a":[1,2]}',
  'json typed object: true {"a":{"b":1}}',
  "json typed ints: true [1,2]",
  'json typed strings: true ["a","b"]',
  "json typed doubles: true [1.5,2]",
  "json typed bools: true [true,false]",
  'json typed objects: true [{"a":1}]',
  'json typed string objects: true [{"a":"x"}]',
  'json typed optional fields: true {"a":1,"b":null}',
  "json typed optional items: true [1,null]",
  'json typed optional ints: true {"a":1,"b":null}',
  "json typed nan: false -",
  "json typed int keys: false -",
  "json typed date: false -",
  "json stream file: 13 true 5 remote nil: true",
  "stream missing file: 7 NSPOSIXErrorDomain 2",
];

const repr = (value) => JSON.stringify(value);
const bodyText = (page) => page.locator("body").innerText();

// Polls the body text until it contains the value: a fixed pause is too short on a slow runner.
async function bodyIncludes(page, value, timeout = PATIENCE) {
  const deadline = Date.now() + timeout;
  for (;;) {
    if ((await bodyText(page)).includes(value)) return true;
    if (Date.now() >= deadline) return false;
    await page.waitForTimeout(25);
  }
}

async function checkJsonStreamFixture(page, url, report) {
  // JSONSerialization over InputStream/OutputStream behaves like Apple's Foundation (memory, buffer and file streams).
  await page.goto(url, { waitUntil: "networkidle" });
  for (const line of JSON_STREAM_LINES) {
    try {
      await page.getByText(line, { exact: true }).first().waitFor({ timeout: PATIENCE });
    } catch {
      const actual = (await bodyText(page)).split(/\r?\n/).filter((text) => text.includes("json") || text.includes("stream"));
      throw new assert.AssertionError({ message: `missing ${repr(line)}; page shows ${repr(actual)}` });
    }
  }
  report.checks.push({ name: "json-serialization-streams", status: "PASS" });
}

async function checkMeasurementFixture(page, url, report) {
  // MeasurementFormatter converts to the locale's units and names them in the browser's locale (en_US and pt_BR).
  await page.goto(url, { waitUntil: "networkidle" });
  for (const line of MEASUREMENT_LINES) await page.getByText(line, { exact: true }).first().waitFor({ timeout: PATIENCE });
  report.checks.push({ name: "measurement-formatter-locales", status: "PASS" });
}

async function checkSwiftUIParityFixture(page, url, report) {
  // SwiftUI spellings added for iPad/iPhone parity render like SwiftUI.
  await page.goto(url, { waitUntil: "networkidle" });
  await page.getByRole("button", { name: "Open SwiftUI parity fixture", exact: true }).click();
  await page.getByRole("button", { name: "Return from parity fixture", exact: true }).waitFor({ timeout: PATIENCE });
  await page.waitForTimeout(200);
  const g = await page.evaluate(`(${PARITY_GEOMETRY})()`);

  const near = (a, b, tolerance = 1.0) => Math.abs(a - b) <= tolerance;
  const check = (name, condition, detail) => {
    if (!condition) throw new assert.AssertionError({ message: `parity fixture ${name}: ${repr(detail)}` });
    report.checks.push({ name: `parity-${name}`, status: "PASS" });
  };

  // Color.red and .blue are Apple's light-mode system colors (#FF3B30, #007AFF).
  check("background-color-value-and-member", g.bgColor === "rgb(255, 59, 48)" && g.bgMember === "rgb(0, 122, 255)", g);
  check("background-gradient-paint", g.bgGradient.startsWith("linear-gradient"), g.bgGradient);
  check("overlay-view-top-trailing", near(g.badge.x + g.badge.w, g.base.x + g.base.w) && near(g.badge.y, g.base.y), g);
  check("overlay-paint-covers-bounds", near(g.dimLayer.w, g.dim.w) && near(g.dimLayer.h, g.dim.h), g);
  check("padded-shape-background", g.capsule.w >= g.capsuleText.w + 15.5 && g.capsule.h >= g.capsuleText.h + 15.5, g);
  check("uneven-rounded-clip", isDeepStrictEqual(g.unevenClip, ["12px", "12px", "0px", "0px"]), g.unevenClip);
  check("uneven-rounded-fill-path", g.unevenPath.startsWith("M 16 0"), g.unevenPath);
  check("trim-dash-geometry", g.ringDash === "0.25px, 0.75px", g.ringDash);
  check("a11y-combine", isDeepStrictEqual(g.combine, ["group", "Rating, 4 stars", true]), g.combine);
  check("a11y-ignore", isDeepStrictEqual(g.ignore, ["Summary", true]), g.ignore);
  check("a11y-contain", isDeepStrictEqual(g.contain, ["group", null]), g.contain);
  const card = (g.scroll.w - 20) / 3;
  check("container-relative-count-spacing", g.cards.every((c) => near(c.w, card, 0.5)) && near(g.cards[1].x - g.cards[0].x, card + 10, 0.5), g.cards);
  check("date-format-and-range", g.dateFormat.includes("2027") && g.dateRange.includes("–"), g);
  check("date-relative", g.relative.includes("hour"), g.relative);
  check("z-index-integer", g.zIndex === "2", g.zIndex);
  check("label-icon-only-name", g.iconOnly === "Settings", g.iconOnly);
  check("control-group-role", g.controlGroup === "group", g.controlGroup);
  check("position-centers-child", near(g.dot.x - g.area.x, 25) && near(g.dot.y - g.area.y, 15) && near(g.dot.w, 10), g);

  await page.waitForTimeout(1100);
  const ticked = await page.evaluate(() => document.querySelector('[data-testid="parity-date-timer"]').textContent);
  check("timer-interval-ticks", ticked !== g.timer, [g.timer, ticked]);

  const dash = () => getComputedStyle(document.querySelector('[data-testid="parity-trim-ring"] path')).strokeDasharray;
  await page.getByRole("button", { name: "Advance progress", exact: true }).click();
  const samples = [];
  for (let index = 0; index < 12; index++) {
    samples.push(await page.evaluate(dash));
    await page.waitForTimeout(25);
  }
  await page.waitForTimeout(250);
  const final = await page.evaluate(dash);
  const intermediate = samples.filter((value) => value !== "0.25px, 0.75px" && value !== "0.75px, 0.25px");
  check("trim-progress-animates", final === "0.75px, 0.25px" && intermediate.length > 0, [samples, final]);

  const menu = page.locator('[data-testid="parity-context-menu"]');
  await menu.click({ button: "right" });
  await page.waitForFunction(() => document.querySelector(".context-menu-panel")?.matches(":popover-open"), undefined, { timeout: PATIENCE });
  await page.getByRole("button", { name: "Share", exact: true }).click();
  await page.waitForFunction(() => !document.querySelector(".context-menu-panel").matches(":popover-open"), undefined, { timeout: PATIENCE });
  await page.getByText("Menu: share", { exact: true }).waitFor({ timeout: PATIENCE });
  check("context-menu-open-choose-dismiss", true, null);
}

async function checkNetworkMediaFixture(page, report) {
  // The link and lowering surface of Tests/Apps/EmbeddedLoweringConformanceApp/EmbeddedNetworkMediaFixture.swift, opened from
  // the main page in its normal place in the sequence: a URLSession request answered by a globally registered URLProtocol, an
  // environment key set through a key path, `.task(id:)` over an optional String (its description is the DOM task marker) and
  // `AVURLAsset.load(.variants)`. The fixture creates an AVPlayer while it renders, and the player stays registered after the
  // fixture returns (section 12.22): the main page's buttons must still answer after the return.
  await page.getByRole("button", { name: "Open network media fixture", exact: true }).click();
  await page.getByText("Network: fixture", { exact: true }).waitFor({ timeout: PATIENCE });
  await page.getByText("Label: fixture", { exact: true }).waitFor({ timeout: PATIENCE });
  await page.getByText("Source: fixture", { exact: true }).waitFor({ timeout: PATIENCE });
  report.checks.push({ name: "network-protocol-and-environment-keypath", status: "PASS" });
  const taskMarkers = await page.evaluate(() => [...document.querySelectorAll("[data-task-id]")].map((e) => e.getAttribute("data-task-id")));
  if (!taskMarkers.includes("some(fixture)")) {
    throw new assert.AssertionError({ message: `.task(id: String?) did not describe its optional identity: ${repr(taskMarkers)}` });
  }
  report.checks.push({ name: "task-optional-string-identity", status: "PASS" });
  await page.getByRole("button", { name: "Return to conformance app", exact: true }).click();
  await page.getByRole("button", { name: "Update observer", exact: true }).waitFor({ timeout: PATIENCE });
  const observed = Number.parseInt((await page.getByText("Observed:", { exact: false }).first().innerText()).split(":")[1], 10);
  for (let count = observed + 1; count < observed + 4; count++) {
    await page.getByRole("button", { name: "Update observer", exact: true }).click();
    // A click after the fixture returned must show within a second (the page is not busy republishing).
    await page.getByText(`Observed: ${count}`, { exact: true }).waitFor({ timeout: PATIENCE });
  }
  report.checks.push({ name: "siblings-answer-after-network-media-fixture-returns", status: "PASS" });
}

// How long a wait for the page lasts before it fails. A wait that succeeds returns at once, so the limit only matters to a runner
// with few cores, where the app takes seconds to react to a click.
const PATIENCE = 20_000;

await runSuite(async () => {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: { output: { type: "string", default: ".build/embedded-ui/lowering" } },
  });
  if (positionals.length !== 1) throw new Error("usage: test-embedded-lowering-runtime.mjs <bundle> [--output <directory>]");
  const bundle = resolve(positionals[0]);
  const output = values.output;
  mkdirSync(output, { recursive: true });
  const report = { status: "RUNNING", runtime: "Embedded Swift + BrowserIO", checks: [] };
  writeFileSync(join(output, "result.json"), JSON.stringify(report, null, 2) + "\n");
  if (!bundleFilePath(bundle, "app.wasm") || !existsSync(join(bundle, "index.html"))) {
    throw new Error(`Embedded lowering fixture bundle is missing: ${bundle}`);
  }

  const server = serveStatic(bundle);
  let browser;
  try {
    browser = await launch();
    const page = await browser.newPage({ viewport: { width: 1000, height: 800 } });
    const errors = [];
    page.on("pageerror", (error) => errors.push(String(error)));
    await page.goto(`${server.base}/`, { waitUntil: "networkidle" });
    // The app draws once its WebAssembly has started, which a runner with few cores takes a while to do: the page is read when
    // it has mounted and shows its last row, not after a fixed pause.
    await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 60_000 });
    let body = await bodyText(page);
    for (const end = Date.now() + 30_000; !body.includes("builder child 100") && Date.now() < end; body = await bodyText(page)) await page.waitForTimeout(100);
    for (const value of [
      "alpha | beta",
      "One",
      "Two",
      "Animated",
      "Run",
      "Observed: 0",
      "Update observer",
      "Init-assigned: 4",
      "Update init-assigned",
      "ContentBuilder lowered",
      "ContentBuilder conditional",
      "codable-parity: PASS",
      "json-corpus: PASS",
      "predicate-parity: PASS",
      "builder child 1",
      "builder child 50",
      "builder child 100",
    ]) {
      if (!body.includes(value)) throw new assert.AssertionError({ message: `lowering fixture did not render ${repr(value)}: ${body.slice(0, 500)}` });
      report.checks.push({ name: `render-${value}`, status: "PASS" });
    }
    for (const identity of ["lowering-fiber-key", "42"]) {
      const count = await page.locator(`[data-view-id="${identity}"]`).count();
      if (count !== 1) {
        const ids = await page.$$eval("[data-view-id]", (nodes) => nodes.map((node) => node.getAttribute("data-view-id")));
        throw new assert.AssertionError({
          message: `a generic .id(${repr(identity)}) did not keep its scalar text as the DOM identity (${count} matches); ids=${repr(ids.slice(0, 20))}`,
        });
      }
    }
    report.checks.push({ name: "generic-scalar-ids-keep-their-text", status: "PASS" });
    const childPositions = [];
    for (let index = 1; index <= 100; index++) {
      const position = body.indexOf(`builder child ${index}`);
      if (position < 0) throw new Error(`substring not found: builder child ${index}`);
      childPositions.push(position);
    }
    if (!isDeepStrictEqual(childPositions, [...childPositions].sort((a, b) => a - b))) {
      throw new assert.AssertionError({ message: "100 direct result-builder children rendered out of order" });
    }
    report.checks.push({ name: "render-100-direct-builder-children-in-order", status: "PASS" });
    // An Int passed to the generic `.id(_:)` stays a scalar identity: ScrollViewProxy and tooling find it by value.
    const scalarIds = await page.evaluate(() =>
      [...document.querySelectorAll("[data-view-id]")]
        .filter((e) => /^generic id \d+$/.test(e.textContent.trim()))
        .map((e) => [e.getAttribute("data-view-id"), e.textContent.trim()]));
    if (!isDeepStrictEqual(scalarIds, [["3", "generic id 3"], ["8", "generic id 8"]])) {
      throw new assert.AssertionError({ message: `generic .id(Int) lost its scalar identity: ${repr(scalarIds)}` });
    }
    report.checks.push({ name: "generic-id-keeps-scalar-identity", status: "PASS" });
    // A real pointer click (no force): the switch must be the hit target, not what lies around it.
    await page.getByRole("switch", { name: "Lowering switch", exact: true }).click({ timeout: PATIENCE });
    await page.getByText("Lowering switch: on", { exact: true }).waitFor({ timeout: PATIENCE });
    report.checks.push({ name: "switch-toggle-takes-the-pointer", status: "PASS" });

    const clickButton = (name) => page.getByRole("button", { name, exact: true }).click();

    const expectButton = async (name) => {
      try {
        await page.getByRole("button", { name, exact: true }).waitFor({ timeout: PATIENCE });
      } catch {
        const rows = (await bodyText(page)).split(/\r?\n/).filter((line) => ["A:", "B:", "C:", "X:", "Y:"].some((prefix) => line.startsWith(prefix)));
        throw new assert.AssertionError({ message: `expected button ${repr(name)}; rows=${repr(rows)}; page_errors=${repr(errors)}` });
      }
    };

    const expectRowOrder = (expected) =>
      page.waitForFunction(
        (wanted) =>
          JSON.stringify([...document.querySelectorAll("button")]
            .map((button) => button.textContent.trim())
            .filter((label) => /^(A|B|C|X|Y):\d+$/.test(label))
            .map((label) => label.split(":")[0])) === JSON.stringify(wanted),
        expected,
        { timeout: PATIENCE },
      );

    await expectRowOrder(["A", "B", "C"]);

    await clickButton("B:0");
    await expectButton("B:1");
    if ((await page.getByRole("button", { name: "B:1", exact: true }).count()) !== 1) {
      throw new assert.AssertionError({
        message: `clicking the keyed B row did not update its @State; body=${repr(await bodyText(page))}; page_errors=${repr(errors)}`,
      });
    }
    await expectButton("B:1");
    await clickButton("Reorder IDs");
    await expectRowOrder(["C", "A", "B"]);
    await expectButton("B:1");
    await clickButton("Insert at beginning");
    await expectRowOrder(["X", "C", "A", "B"]);
    await expectButton("B:1");
    await expectButton("X:0");
    await clickButton("Insert in middle");
    await expectRowOrder(["X", "C", "Y", "A", "B"]);
    await expectButton("B:1");
    await expectButton("Y:0");
    await clickButton("Remove inserted IDs");
    await expectRowOrder(["C", "A", "B"]);
    await expectButton("B:1");
    await page.getByRole("button", { name: "X:0", exact: true }).waitFor({ state: "detached" });
    await page.getByRole("button", { name: "Y:0", exact: true }).waitFor({ state: "detached" });
    report.checks.push({ name: "embedded-conditional-and-keyed-state-identity", status: "PASS" });

    await clickButton("before branch:0");
    await clickButton("after branch:0");
    await clickButton("first branch:0");
    await expectButton("before branch:1");
    await expectButton("after branch:1");
    await expectButton("first branch:1");
    await clickButton("Toggle conditional branch");
    await expectButton("second branch:0");
    await expectButton("before branch:1");
    await expectButton("after branch:1");
    await clickButton("second branch:0");
    await expectButton("second branch:1");
    await clickButton("Toggle conditional branch");
    await expectButton("first branch:0");
    await expectButton("before branch:1");
    await expectButton("after branch:1");
    await page.getByRole("button", { name: "first branch:1", exact: true }).waitFor({ state: "detached" });
    await clickButton("Toggle conditional branch");
    await expectButton("second branch:0");
    await page.getByRole("button", { name: "second branch:1", exact: true }).waitFor({ state: "detached" });

    await page.getByRole("button", { name: "Update observer" }).click();
    if (!(await bodyIncludes(page, "Observed: 1"))) {
      throw new assert.AssertionError({ message: "@Observable lowering did not publish a model mutation" });
    }
    report.checks.push({ name: "observable-model-update", status: "PASS" });
    await page.getByRole("button", { name: "Update init-assigned" }).click();
    if (!(await bodyIncludes(page, "Init-assigned: 5"))) {
      throw new assert.AssertionError({ message: "init-assigned @Observable member did not publish a model mutation" });
    }
    report.checks.push({ name: "init-assigned-observable-model-update", status: "PASS" });
    // The network/media fixture opens from the main page in its place in the sequence (section 12.22): its player stays
    // registered after the fixture returns, and the main page keeps answering.
    await checkNetworkMediaFixture(page, report);
    await page.getByRole("button", { name: "Load previous version", exact: true }).click();
    await page.getByRole("button", { name: "Hide previous version", exact: true }).waitFor({ timeout: PATIENCE });
    await page.getByText("Previous version loaded", { exact: true }).waitFor({ timeout: PATIENCE });
    await page.getByRole("button", { name: "Open review", exact: true }).click();
    await page.getByRole("button", { name: "Load previous version", exact: true }).waitFor({ timeout: PATIENCE });
    await page.getByText("Previous version loaded", { exact: true }).waitFor({ state: "detached", timeout: PATIENCE });
    await page.getByRole("button", { name: "Load previous version", exact: true }).click();
    await page.getByRole("button", { name: "Hide previous version", exact: true }).waitFor({ timeout: PATIENCE });
    await page.getByText("Previous version loaded", { exact: true }).waitFor({ timeout: PATIENCE });
    await page.getByRole("button", { name: "Hide previous version", exact: true }).click();
    await page.getByText("Previous version loaded", { exact: true }).waitFor({ state: "detached", timeout: PATIENCE });
    report.checks.push({ name: "late-mounted-conditional-state-under-anyview-and-keyed-foreach", status: "PASS" });
    await page.getByRole("button", { name: "Open StateObject identity fixture", exact: true }).click();
    await page.getByRole("button", { name: "A:0", exact: true }).click();
    await page.getByRole("button", { name: "A:1", exact: true }).waitFor({ timeout: PATIENCE });
    await page.getByRole("button", { name: "Insert leading row", exact: true }).click();
    await page.getByRole("button", { name: "X:0", exact: true }).waitFor({ timeout: PATIENCE });
    await page.getByRole("button", { name: "A:1", exact: true }).waitFor({ timeout: PATIENCE });
    await page.getByRole("button", { name: "Remove leading row", exact: true }).click();
    await page.getByRole("button", { name: "A:1", exact: true }).waitFor({ timeout: PATIENCE });
    report.checks.push({ name: "stateobject-child-path-after-parent-conditional-insertion", status: "PASS" });
    await page.getByRole("button", { name: "Return to conformance app", exact: true }).click();
    await page.getByRole("button", { name: "Open deep review fixture", exact: true }).click();
    await page.getByRole("button", { name: "Enter Studio", exact: true }).click();
    await page.getByRole("button", { name: "Open review production", exact: true }).click();
    await page.getByRole("button", { name: "Open reviews", exact: true }).click();
    await page.getByText("Workflow reviews", { exact: true }).waitFor({ timeout: PATIENCE });
    await page.getByRole("button", { name: "Load previous version", exact: true }).click();
    await page.getByRole("button", { name: "Hide previous version", exact: true }).waitFor({ timeout: PATIENCE });
    await page.getByText("Previous version loaded", { exact: true }).waitFor({ timeout: PATIENCE });
    await page.getByRole("button", { name: "Hide previous version", exact: true }).click();
    await page.getByText("Previous version loaded", { exact: true }).waitFor({ state: "detached", timeout: PATIENCE });
    report.checks.push({ name: "deep-scrollview-tabs-foreach-anyview-observable-state", status: "PASS" });
    await checkMeasurementFixture(page, `${server.base}/`, report);
    await checkJsonStreamFixture(page, `${server.base}/`, report);
    await checkSwiftUIParityFixture(page, `${server.base}/`, report);
    if (errors.length > 0) throw new assert.AssertionError({ message: "browser runtime errors: " + errors.join("; ") });
    report.status = "PASS";
  } finally {
    await browser?.close();
    await server.stop();
  }
  writeFileSync(join(output, "result.json"), JSON.stringify(report, null, 2) + "\n");
  console.log(JSON.stringify(report, null, 2));
});
