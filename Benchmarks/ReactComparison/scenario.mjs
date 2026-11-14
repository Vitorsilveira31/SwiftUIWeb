// What the comparison does to both boards, in the order a person would: wait for the board, type in the search, mark
// favorites, open works, add a work, look at the stats and come back, scroll the list. The same steps, the same selectors
// (data-testid) and the same data on both sides: `shared/data.mjs` is the data, and `Tools/test-react-board-parity.mjs`
// checks that both boards answer alike before anything is measured.
import { makeWorks, matches, WORK_COUNT } from "./shared/data.mjs";

export const READY = [{ text: ["result-count", `${WORK_COUNT} results`] }, { exists: '[data-testid="row"]' }];
const works = makeWorks();
const countFor = (query) => works.filter((work) => matches(work, query)).length;
const results = (count) => ({ text: ["result-count", `${count} results`] });

// Typing "led" and then deleting it changes the result count at every key (2000, 1125, 375, 125, 375, 1125, 2000), so each
// keystroke has a visible effect to wait for.
const KEYS = ["l", "e", "d", "Backspace", "Backspace", "Backspace"];

// "on screen" is what the eye sees (the frame that presents the change); "until the DOM is ready" is when the DOM and its layout
// hold the change (see recorder.mjs). `of` marks a metric that is the second reading of another.
export const METRICS = [
  { id: "load", label: "Cold load, to the board on screen", unit: "ms" },
  { id: "loadWork", label: "Cold load, to the DOM and layout of the board", unit: "ms", of: "load" },
  { id: "warmLoad", label: "Warm load, to the board on screen", unit: "ms" },
  { id: "warmLoadWork", label: "Warm load, to the DOM and layout of the board", unit: "ms", of: "warmLoad" },
  { id: "lcp", label: "Largest Contentful Paint, cold load (Chromium)", unit: "ms" },
  { id: "transfer", label: "Transferred to show the board", unit: "KB" },
  { id: "nodes", label: "DOM nodes with the board on screen", unit: "" },
  { id: "type", label: "Typing in the search (median of 6 keys)", unit: "ms" },
  { id: "typeWork", label: "Typing in the search, until the DOM is ready", unit: "ms", of: "type" },
  { id: "favorite", label: "Marking a favorite (median of 3)", unit: "ms" },
  { id: "favoriteWork", label: "Marking a favorite, until the DOM is ready", unit: "ms", of: "favorite" },
  { id: "detail", label: "Opening a work (median of 3)", unit: "ms" },
  { id: "detailWork", label: "Opening a work, until the DOM is ready", unit: "ms", of: "detail" },
  { id: "add", label: "Adding a work (median of 2)", unit: "ms" },
  { id: "addWork", label: "Adding a work, until the DOM is ready", unit: "ms", of: "add" },
  { id: "showStats", label: "Switching to the stats (200 cells)", unit: "ms" },
  { id: "showStatsWork", label: "Switching to the stats, until the DOM is ready", unit: "ms", of: "showStats" },
  { id: "backToBoard", label: "Switching back to the board", unit: "ms" },
  { id: "backToBoardWork", label: "Switching back to the board, until the DOM is ready", unit: "ms", of: "backToBoard" },
  { id: "scrollWorst", label: "Scrolling the list, longest frame", unit: "ms" },
  { id: "scrollSlow", label: "Scrolling the list, frames over 25 ms (a dropped frame)", unit: "" },
  { id: "cls", label: "Cumulative Layout Shift, the whole scenario, times 1000 (Chromium)", unit: "" },
  { id: "inp", label: "Interaction to Next Paint, the slowest input of the scenario (Chromium)", unit: "ms" },
  { id: "blocking", label: "Main thread blocked (long tasks over 50 ms)", unit: "ms" },
];

const median = (values) => [...values].sort((a, b) => a - b)[Math.floor((values.length - 1) / 2)];

/** The metrics of the first load alone: what a network profile measures (the interactions run on a local page either way). */
export const LOAD_METRICS = ["load", "loadWork", "transfer", "nodes", "lcp"];

/** Waits for the board of an opened page, and returns its cold-load metrics (the largest contentful paint is read by `readLcp`). */
export async function coldLoad(page, timeout = 20_000) {
  await page.waitForFunction(() => window.__bench.readyFrameAt !== null, undefined, { timeout });
  const ready = await page.evaluate(() => ({ at: window.__bench.readyFrameAt, work: window.__bench.readyAt, bytes: window.__bench.readyBytes, nodes: window.__bench.readyNodes }));
  return { load: ready.at, loadWork: ready.work, transfer: ready.bytes / 1024, nodes: ready.nodes };
}

/**
 * The largest contentful paint of the load, read a second after the board is on screen: the browser reports the entry with a
 * frame or more of delay, and under a CPU slowdown that is later than the board itself. Until the first input the largest
 * paint can still change, so it is read before the scenario's first interaction.
 */
export async function readLcp(page) {
  await page.waitForTimeout(1000);
  return page.evaluate(() => (window.__bench.vitals.supported.lcp ? window.__bench.vitals.lcp : null));
}

/** The cold load of a network profile: the metrics of coldLoad, with the largest contentful paint. */
export async function loadOnly(page, timeout = 20_000) {
  const cold = await coldLoad(page, timeout);
  return { ...cold, lcp: await readLcp(page) };
}

/** Runs the steps on an open page and returns one number per metric. */
export async function run(page, { timeout = 20_000 } = {}) {
  const out = {};
  let blocking = 0; // null once an engine without long-task entries is read: its blocking time is then not measured
  /** Runs `action` and returns the on-screen latency and the until the DOM is ready of what it caused. */
  const measure = async (conditions, action) => {
    // Armed before the action: a round trip to the page that is still on its way when the action lands would miss the change.
    await page.evaluate(([c, t]) => window.__bench.begin(c, t), [conditions, timeout]);
    await action();
    const sample = await page.evaluate(() => window.__bench.finish());
    blocking = blocking === null || sample.blocking === null ? null : blocking + sample.blocking;
    return { latency: sample.latency, work: sample.work };
  };
  const both = (id, samples) => {
    out[id] = median(samples.map((sample) => sample.latency));
    out[`${id}Work`] = median(samples.map((sample) => sample.work));
  };

  Object.assign(out, await coldLoad(page, timeout));
  out.lcp = await readLcp(page); // waits a second, which the first interaction below must not overtake

  const search = page.locator('input[data-testid="search"], [data-testid="search"] input').first();
  await search.click();
  let query = "";
  const typing = [];
  for (const key of KEYS) {
    query = key === "Backspace" ? query.slice(0, -1) : query + key;
    typing.push(await measure([results(countFor(query))], () => page.keyboard.press(key)));
  }
  both("type", typing);

  const favorites = [];
  for (const [index, id] of [10, 20, 30].entries()) {
    // The count and the clicked row's own star: the answer is complete when everything the click changes is on the page.
    favorites.push(await measure([{ text: ["fav-count", `${index + 1} favorites`] }, { text: [`fav-${id}`, "★"] }], () => page.click(`[data-testid="fav-${id}"]`)));
  }
  both("favorite", favorites);

  const details = [];
  for (const id of [5, 15, 25]) {
    // The detail and the selected row's highlight.
    details.push(await measure([{ text: ["detail-title", works[id - 1].title] }, { shaded: `title-${id}` }], () => page.click(`[data-testid="title-${id}"]`)));
  }
  both("detail", details);

  const adds = [];
  for (const added of [1, 2]) {
    adds.push(await measure([results(WORK_COUNT + added), { text: ["title-" + (2000 + added), `New work ${added}`] }], () => page.click('[data-testid="add-button"]')));
  }
  both("add", adds);

  both("showStats", [await measure([{ count: ['[data-testid="stats-cell"]', 200] }], () => page.click('[data-testid="view-stats"]'))]);
  both("backToBoard", [await measure([results(WORK_COUNT + 2), { exists: '[data-testid="row"]' }], () => page.click('[data-testid="view-board"]'))]);

  const box = await page.locator('[data-testid="list"]').boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  const scrolling = page.evaluate(() => window.__bench.frames(1800));
  for (let step = 0; step < 20; step += 1) {
    await page.mouse.wheel(0, 400);
    await page.waitForTimeout(40);
  }
  const frames = await scrolling;
  out.scrollWorst = frames.maxFrame;
  out.scrollSlow = frames.slowFrames;
  out.blocking = blocking === null || frames.blocking === null ? null : blocking + frames.blocking;

  // Core Web Vitals as the scenario leaves them. Event Timing reports each input with the frame that paints it, so they are read
  // after the scroll has had its frames. INP here is the slowest input, not the 98th percentile a visit reports.
  const vitals = await page.evaluate(() => ({
    cls: window.__bench.vitals.supported.layoutShift ? window.__bench.vitals.cls * 1000 : null,
    inputs: window.__bench.vitals.supported.event ? window.__bench.vitals.inputs : null,
  }));
  out.cls = vitals.cls;
  out.inp = vitals.inputs === null || vitals.inputs.length === 0 ? null : Math.max(...vitals.inputs);

  // A second visit: the same address loaded again in the same browser context, so the HTTP cache holds everything the first
  // visit fetched (SwiftUIWeb's hashed files and React's, the same way). It is read the way the first load is.
  await page.goto(page.url());
  await page.waitForFunction(() => window.__bench.readyFrameAt !== null, undefined, { timeout });
  const second = await page.evaluate(() => ({ at: window.__bench.readyFrameAt, work: window.__bench.readyAt }));
  out.warmLoad = second.at;
  out.warmLoadWork = second.work;
  return out;
}
