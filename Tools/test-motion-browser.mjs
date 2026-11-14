#!/usr/bin/env bun
// SwiftUI's motion in a real browser (Tests/Apps/MotionApp): insertion and removal transitions (every built-in kind, a
// custom `Transition`, one with its own animation), the default fade, the siblings that slide around an insertion, a
// numeric content transition, and a spring that overshoots. Animations are sampled by pausing them at a chosen time, so
// the checks do not depend on how fast the machine is.
// The bundle: MOTION_BUNDLE (.build/browser/MotionApp, built by `make motion-browser-test`).
// Engine: SWIFTUIWEB_BROWSER_ENGINE (chromium by default).
import assert from "node:assert/strict";
import fs from "node:fs";
import { join, resolve } from "node:path";
import { engineName, freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

const BUNDLE = resolve(process.env.MOTION_BUNDLE ?? join(ROOT, ".build/browser/MotionApp"));

async function openFixture(browser, server, { reducedMotion = "no-preference" } = {}) {
  const context = await browser.newContext({ viewport: { width: 800, height: 900 } });
  const page = await context.newPage();
  await page.emulateMedia({ reducedMotion });
  const problems = [];
  page.on("pageerror", (error) => problems.push(String(error)));
  page.on("console", (message) => { if (message.type() === "error") problems.push(message.text()); });
  await page.goto(`${server.base}/`);
  await page.waitForSelector('[data-testid="row-1"]');
  // The texts the page measures for Swift draw a moment after the first paint, and may resize: the checks start once
  // they have.
  await page.waitForFunction(() => document.querySelector('[data-testid="baseline"]') && document.querySelector('[data-testid="narrow"] canvas') && document.querySelector('[data-testid="styled"] canvas') && document.querySelector('[data-testid="around"] canvas'), null, { timeout: 10000 });
  await page.waitForTimeout(150);
  // Helpers in the page: the animations running on an element, sampled at a time, and finished at once.
  await page.evaluate(() => {
    window.__byId = (id) => document.querySelector(`[data-testid="${id}"]`);
    window.__transitionTarget = (id) => { const element = window.__byId(id); return element?.closest('[data-transition-insert],[data-transition-leaving]') ?? element; };
    window.__animationsOf = (element) => element ? element.getAnimations() : [];
    window.__sample = (element, time, property) => {
      for (const animation of window.__animationsOf(element)) { animation.pause(); animation.currentTime = time; }
      return getComputedStyle(element)[property];
    };
    window.__keyframes = (element) => window.__animationsOf(element).map((animation) => ({
      frames: animation.effect.getKeyframes().map(({ offset, computedOffset, easing, composite, ...rest }) => rest),
      timing: animation.effect.getTiming(), composite: animation.effect.composite,
    }));
    // A scroll transition is a paused animation the scroll position drives: it is not one to finish.
    window.__finishAll = () => { for (const animation of document.getAnimations()) { if (animation.id === "scroll-transition") continue; try { animation.finish(); } catch { animation.cancel(); } } };
  });
  return { page, problems };
}

const click = async (page, id) => { await page.click(`[data-testid="${id}"]`); await page.waitForTimeout(80); };
// Finishing an animation fires its `finish` event a few frames later, later still in a software-rendered WebKit: wait
// for the removed elements it releases instead of a fixed time.
const settle = async (page) => {
  await page.evaluate(() => window.__finishAll());
  for (let waited = 0; waited < 3000; waited += 40) {
    if (await page.evaluate(() => document.querySelectorAll("[data-transition-leaving]").length === 0)) break;
    await page.waitForTimeout(40);
  }
  await page.waitForTimeout(80);
};
const near = (actual, expected, tolerance, message) => assert.ok(Math.abs(actual - expected) <= tolerance, `${message}: ${actual} is not within ${tolerance} of ${expected}`);
const pixels = (value) => (value === "none" ? [0, 0] : value.split(" ").map((part) => parseFloat(part)));

async function insertionAndSiblings(page, label) {
  const before = await page.evaluate(() => window.__byId("row-1").getBoundingClientRect().top);
  await click(page, "add");
  const row = await page.evaluateHandle(() => window.__transitionTarget("row-4"));
  const frames = await row.evaluate((element) => window.__keyframes(element));
  assert.equal(frames.length, 1, `${label}: the inserted row plays one transition`);
  assert.equal(frames[0].timing.duration, 1000, `${label}: with the commit's animation`);
  assert.equal(frames[0].frames[0].opacity, "0", `${label}: the move+opacity insertion starts transparent`);
  assert.match(frames[0].frames[0].translate, /^-120px|^-100%/, `${label}: and off its leading edge`);
  near(Number(await row.evaluate((element) => window.__sample(element, 500, "opacity"))), 0.5, 0.02, `${label}: half way in, half opaque`);
  const halfWay = (await row.evaluate((element) => window.__sample(element, 500, "translate"))).split(" ")[0];
  if (halfWay.endsWith("%")) near(parseFloat(halfWay), -50, 1, `${label}: half way in, half its width off`);
  else near(parseFloat(halfWay), -60, 2, `${label}: half way in, half its width off`);
  // The row that was first moved down by one row and its spacing; it slides there instead of jumping.
  const sibling = await page.evaluateHandle(() => window.__byId("row-1"));
  const flip = await sibling.evaluate((element) => window.__keyframes(element));
  // Its place once the move is over.
  const after = await sibling.evaluate((element) => { for (const animation of element.getAnimations()) { animation.pause(); animation.currentTime = animation.effect.getTiming().duration; } return element.getBoundingClientRect().top; });
  assert.equal(flip.length, 1, `${label}: the sibling plays one move`);
  assert.equal(flip[0].composite, "add", `${label}: an additive move, so it composes with the sibling's own offset`);
  near(pixels(flip[0].frames[0].translate)[1], -(after - before), 1, `${label}: from its old place`);
  await settle(page);
  assert.equal(await page.evaluate(() => document.querySelectorAll("[data-transition-leaving]").length), 0, `${label}: nothing left over`);
}

async function removal(page, label) {
  await click(page, "remove");
  const leaving = await page.evaluate(() => {
    const element = document.querySelector("[data-transition-leaving]");
    return element && { text: element.textContent, position: element.style.position, inert: element.inert, hidden: element.getAttribute("aria-hidden"), frames: window.__keyframes(element) };
  });
  assert.ok(leaving, `${label}: the removed row stays to play its removal`);
  assert.equal(leaving.text, "Row 4", `${label}: the first row is the one leaving`);
  assert.equal(leaving.position, "absolute", `${label}: out of the layout, so the others take its place`);
  assert.ok(leaving.inert && leaving.hidden === "true", `${label}: and out of reach`);
  assert.equal(leaving.frames[0].frames[1].opacity, "0", `${label}: it fades out`);
  assert.equal(await page.evaluate(() => window.__byId("row-4")?.closest("[data-transition-leaving]") ? 1 : 0), 1, `${label}: the published rows no longer list it`);
  await settle(page);
  assert.equal(await page.evaluate(() => document.querySelectorAll("[data-transition-leaving]").length), 0, `${label}: it is gone once the removal ends`);
  assert.equal(await page.evaluate(() => window.__byId("row-4")), null, `${label}: and out of the page`);
}

// The removal end state and insertion start state each built-in kind publishes and plays.
const KINDS = {
  opacity: { remove: { opacity: "0" }, insert: { opacity: "0" } },
  scale: { remove: { scale: "0.00001" }, insert: { scale: "0.00001" } },
  slide: { remove: { translate: "100% 0px" }, insert: { translate: "-100% 0px" } },
  move: { remove: { translate: "0px 100%" }, insert: { translate: "0px 100%" } },
  offset: { remove: { translate: "40px 0px" }, insert: { translate: "40px 0px" } },
  push: { remove: { translate: "-100% 0px", opacity: "0" }, insert: { translate: "100% 0px", opacity: "0" } },
  asymmetric: { remove: { opacity: "0" }, insert: { scale: "0.5" } },
  combined: { remove: { translate: "-100% 0px", opacity: "0" }, insert: { translate: "-100% 0px", opacity: "0" } },
  blur: { remove: { opacity: "0", scale: "1.2", filter: "blur(10px)" }, insert: { opacity: "0", scale: "0.8", filter: "blur(10px)" } },
};
// Values compare token by token, numbers by value: engines serialize 0.00001 as 1e-05.
const sameValue = (actual, expected) => {
  // A translation's trailing zero is optional: engines serialize '100% 0px' as '100%'.
  const trim = (tokens) => { while (tokens.length > 1 && /^0(px)?$/.test(tokens[tokens.length - 1])) tokens.pop(); return tokens; };
  const a = trim((actual ?? "").trim().split(/\s+/)), b = trim(expected.split(" "));
  return a.length === b.length && a.every((token, index) => token === b[index] || (Number.isFinite(parseFloat(token)) && Math.abs(parseFloat(token) - parseFloat(b[index])) < 1e-6 && token.replace(/[\d.e+-]/g, "") === b[index].replace(/[\d.e+-]/g, "")));
};
const matches = (frame, expected) => Object.entries(expected).every(([key, value]) => sameValue(frame[key], value));

async function everyKind(page, label) {
  for (const [name, expected] of Object.entries(KINDS)) {
    while ((await page.textContent('[data-testid="kind-name"]')) !== name) await click(page, "kind");
    await click(page, "toggle-kind");
    const out = await page.evaluate(() => { const element = document.querySelector("[data-transition-leaving]"); return element ? window.__keyframes(element) : null; });
    assert.ok(out?.length, `${label} ${name}: the removal plays`);
    assert.ok(matches(out[0].frames[1], expected.remove), `${label} ${name}: removal ends at ${JSON.stringify(expected.remove)}, not ${JSON.stringify(out[0].frames[1])}`);
    await settle(page);
    await click(page, "toggle-kind");
    const enter = await page.evaluate(() => window.__keyframes(window.__transitionTarget("kind-box")));
    assert.ok(enter.length, `${label} ${name}: the insertion plays`);
    assert.ok(matches(enter[0].frames[0], expected.insert), `${label} ${name}: insertion starts at ${JSON.stringify(expected.insert)}, not ${JSON.stringify(enter[0].frames[0])}`);
    await settle(page);
  }
}

async function defaultFadeAndSnap(page, label) {
  await click(page, "toggle-plain");
  const fade = await page.evaluate(() => { const element = document.querySelector("[data-transition-leaving]"); return element ? { text: element.textContent, frames: window.__keyframes(element) } : null; });
  assert.equal(fade?.text, "Plain", `${label}: a view without a transition fades by default`);
  assert.equal(fade.frames[0].frames[1].opacity, "0", `${label}: to transparent`);
  await settle(page);
  await click(page, "toggle-snap");
  assert.ok(await page.evaluate(() => window.__byId("plain") !== null), `${label}: back without animation`);
  assert.equal(await page.evaluate(() => window.__animationsOf(window.__byId("plain")).length), 0, `${label}: an unanimated insertion does not play`);
  await click(page, "toggle-snap");
  assert.equal(await page.evaluate(() => window.__byId("plain")), null, `${label}: an unanimated removal takes the view out at once`);
  await click(page, "toggle-snap");
}

async function numericText(page, label) {
  await click(page, "up");
  const run = await page.evaluate(() => {
    const count = window.__byId("count"), run = count.querySelector("[data-content-run]");
    return run && { label: run.getAttribute("aria-label"), slots: run.querySelectorAll("span[aria-hidden]").length, animations: run.getAnimations({ subtree: true }).length,
      arriving: [...run.getAnimations({ subtree: true })].map((animation) => animation.effect.getKeyframes()[0].transform).filter(Boolean) };
  });
  assert.ok(run, `${label}: the changed number plays a numeric content transition`);
  assert.equal(run.label, "9", `${label}: it reads as the new number`);
  assert.equal(run.slots, 1, `${label}: one digit changes (8 to 9)`);
  // A commit that does not change the number leaves its transition playing.
  await page.click('[data-testid="kind"]');
  assert.ok(await page.evaluate(() => !!window.__byId("count").querySelector("[data-content-run]")), `${label}: an unrelated commit leaves the content transition playing`);
  assert.ok(run.arriving.some((transform) => /translateY\(0\.6em\)/.test(transform)), `${label}: counting up, the new digit rises from below`);
  await settle(page);
  assert.equal(await page.evaluate(() => window.__byId("count").querySelector("[data-content-run]")), null, `${label}: the text comes back when it ends`);
  assert.equal(await page.textContent('[data-testid="count"]'), "9", `${label}: with the new number`);
  await click(page, "down");
  const down = await page.evaluate(() => [...window.__byId("count").querySelector("[data-content-run]").getAnimations({ subtree: true })].map((animation) => animation.effect.getKeyframes()[0].transform).filter(Boolean));
  assert.ok(down.some((transform) => /translateY\(-0\.6em\)/.test(transform)), `${label}: counting down, the new digit falls from above`);
  await settle(page);
  await click(page, "up-100");
  const grown = await page.evaluate(() => { const run = window.__byId("count").querySelector("[data-content-run]"); return { text: run.getAttribute("data-content-run"), widths: run.getAnimations({ subtree: true }).filter((animation) => "width" in (animation.effect.getKeyframes()[0] ?? {})).length }; });
  assert.equal(grown.text, "108", `${label}: 8 + 100`);
  assert.ok(grown.widths >= 2, `${label}: the two new digits open up their room`);
  await settle(page);
  assert.equal(await page.textContent('[data-testid="count"]'), "108", `${label}: the final number`);
}

async function spring(page, label) {
  await click(page, "move");
  const element = await page.evaluateHandle(() => window.__byId("spring"));
  const timing = await element.evaluate((target) => window.__keyframes(target)[0]?.timing);
  assert.ok(timing && timing.duration > 1000, `${label}: a spring plays until it settles, longer than its one-second response (${timing?.duration})`);
  assert.match(await element.evaluate((target) => target.getAnimations()[0].effect.getTiming().easing), /^linear\(/, `${label}: along the spring's own curve`);
  let peak = 0;
  for (let time = 0; time <= timing.duration; time += 25) {
    const transform = await element.evaluate((target, at) => window.__sample(target, at, "transform"), time);
    const match = /matrix\(([^)]+)\)/.exec(transform);
    if (match) peak = Math.max(peak, Number(match[1].split(",")[4]));
  }
  // Bounce 0.3 is a damping ratio of 0.7: the first overshoot of such a step is exp(-0.7π / √(1 - 0.49)), 4.6% of 200px.
  near(peak, 200 * (1 + Math.exp(-0.7 * Math.PI / Math.sqrt(1 - 0.49))), 1.5, `${label}: the bouncy spring overshoots its 200px target as SwiftUI's does`);
  await settle(page);
}

async function customAndAttached(page, label) {
  await click(page, "toggle-custom");
  const custom = await page.evaluate(() => { const element = document.querySelector("[data-transition-leaving]"); return element ? window.__keyframes(element)[0].frames[1] : null; });
  assert.ok(custom, `${label}: a custom Transition plays its removal`);
  assert.equal(custom.opacity, "0.2", `${label}: with the opacity its body gives the phase, over the view's own 0.4`);
  assert.match(custom.transform ?? "", /rotate|matrix/, `${label}: and its rotation`);
  await settle(page);
  await click(page, "toggle-attached");
  const attached = await page.evaluate(() => { const element = document.querySelector("[data-transition-leaving]"); return element ? window.__keyframes(element)[0].timing.duration : null; });
  assert.equal(attached, 1000, `${label}: a transition with its own animation plays it outside withAnimation`);
  await settle(page);
}

/** Two `.animation(_:value:)` armed in the same commit: what is inserted below the inner one plays its animation. */
async function nestedAnimations(page, label) {
  await click(page, "nest");
  const duration = await page.evaluate(() => window.__keyframes(window.__transitionTarget("nested"))[0]?.timing.duration ?? null);
  assert.equal(duration, 1000, `${label}: an insertion plays the nearer animation, not the outer ten seconds`);
  await settle(page);
}

/** An `.animation(_:value:)` whose value changes inside `withAnimation`: the nearer animation times the insertion below it
 * and the styles that change below it. */
async function valueAnimationInsideWithAnimation(page, label) {
  await click(page, "override");
  const durations = await page.evaluate(() => {
    const dimmed = window.__byId("dimmed");
    const holder = dimmed.closest('[style*="opacity"]') ?? dimmed;
    return { inserted: window.__keyframes(window.__transitionTarget("overridden"))[0]?.timing.duration ?? null, changed: holder.getAnimations().map((animation) => animation.effect.getTiming().duration) };
  });
  assert.equal(durations.inserted, 1000, `${label}: inside withAnimation, an insertion plays the nearer value animation, not the transaction's ten seconds (${JSON.stringify(durations)})`);
  // The view moves down for the insertion and fades: both with the nearer animation.
  assert.ok(durations.changed.length > 0 && durations.changed.every((duration) => duration === 1000), `${label}: and so do a move and a style that changes below it (${JSON.stringify(durations)})`);
  await settle(page);
}

/** A commit without an animation that changes a property still animating from an earlier commit shows its value at once. */
async function plainCommitEndsARunningAnimation(page, label) {
  const state = () => page.evaluate(() => {
    const fader = window.__byId("fader"), holder = fader.closest('[style*="opacity"]') ?? fader;
    const style = getComputedStyle(holder);
    const shift = style.translate && style.translate !== "none" ? parseFloat(style.translate) : new DOMMatrix(style.transform === "none" ? "" : style.transform).m41;
    const running = holder.getAnimations().filter((animation) => animation.playState === "running");
    return { opacity: Number(style.opacity), shift, running: running.length, animated: running.flatMap((animation) => Object.keys(animation.effect.getKeyframes()[0]).filter((key) => !["offset", "easing", "composite", "computedOffset"].includes(key))) };
  });
  await click(page, "fade-slowly");
  await page.waitForTimeout(300);
  const during = await state();
  assert.ok(during.running >= 1 && during.opacity > 0.8 && during.opacity < 1, `${label}: the slow fade is under way (${JSON.stringify(during)})`);
  assert.ok(during.shift > 0 && during.shift < 50, `${label}: and so is the slide beside it (${JSON.stringify(during)})`);
  await click(page, "fade-now");
  await page.waitForTimeout(150);
  const after = await state();
  near(after.opacity, 0.8, 0.01, `${label}: a plain commit shows its value at once, over the animation that was running (${JSON.stringify(after)})`);
  assert.ok(!after.animated.includes("opacity"), `${label}: the opacity is no longer animated (${JSON.stringify(after)})`);
  // The slide was not changed by the plain commit: it goes on from where it was, and has not jumped to its end.
  assert.ok(after.running >= 1 && after.shift > during.shift && after.shift < 50, `${label}: the property the plain commit left alone goes on animating (${JSON.stringify({ during, after })})`);
  await settle(page);
}

/** A phase's animation is the one the view moves to that phase with: its delay holds the phase before, then its duration runs. */
async function phaseAnimationsLeadIntoTheirPhase(page, label) {
  await page.waitForFunction(() => window.__byId("phased") && (window.__byId("phased").closest("[data-phase-animator]") ?? window.__byId("phased")).getAnimations().length > 0, null, { timeout: 5000 });
  const played = await page.evaluate(() => {
    const element = window.__byId("phased").closest("[data-phase-animator]") ?? window.__byId("phased");
    const animation = element.getAnimations()[0];
    return { duration: animation.effect.getTiming().duration, frames: animation.effect.getKeyframes().map((frame) => ({ at: Math.round(frame.computedOffset * 1000) / 1000, opacity: Number(frame.opacity) })) };
  });
  assert.equal(played.duration, 1500, `${label}: the two phases take their durations and the delay, 1.5 s (${JSON.stringify(played)})`);
  // Phase false (opacity 1) holds for the one second delay of the animation into phase true, which then takes 0.3 s; the way
  // back into phase false takes its 0.2 s.
  assert.deepEqual(played.frames, [{ at: 0, opacity: 1 }, { at: 0.667, opacity: 1 }, { at: 0.867, opacity: 0.5 }, { at: 1, opacity: 1 }], `${label}: each phase's animation leads into that phase (${JSON.stringify(played.frames)})`);
}

/** An asymmetric transition keeps the animation of each side: one second in, three out. */
async function asymmetricTimings(page, label) {
  await click(page, "toggle-asymmetric");
  const removal = await page.evaluate(() => { const element = [...document.querySelectorAll("[data-transition-leaving]")].find((candidate) => candidate.textContent.includes("Asymmetric")); return element ? window.__keyframes(element)[0].timing.duration : null; });
  assert.equal(removal, 3000, `${label}: the removal plays its own animation`);
  await settle(page);
  await click(page, "toggle-asymmetric");
  const insertion = await page.evaluate(() => window.__keyframes(window.__transitionTarget("asymmetric"))[0]?.timing.duration ?? null);
  assert.equal(insertion, 1000, `${label}: and the insertion its own`);
  await settle(page);
}

async function symbolEffects(page, label) {
  assert.equal(await page.evaluate(() => window.__byId("bell").closest("[data-symbol-effect]").getAnimations().length), 0, `${label}: a discrete symbol effect does not play when the view appears`);
  await click(page, "ring");
  const wiggle = await page.evaluate(() => { const bell = window.__byId("bell").closest("[data-symbol-effect]"); return window.__keyframes(bell); });
  assert.equal(wiggle.length, 1, `${label}: the wiggle plays when its value changes`);
  assert.equal(wiggle[0].timing.iterations, 2, `${label}: as many times as options.repeat says`);
  assert.ok(wiggle[0].frames.some((frame) => frame.rotate === "14deg"), `${label}: swinging clockwise first`);
  const spinning = await page.evaluate(() => getComputedStyle(window.__byId("spinner").closest("[data-symbol-effect]")).animationName);
  assert.equal(spinning, "swu-symbol-rotate", `${label}: an active indefinite rotate keeps turning`);
  await settle(page);
}

/** A shape's stroke and trim change under an armed ancestor animation, below a transaction without animation: it jumps. */
async function disabledShapeTransaction(page, label) {
  const fill = () => page.evaluate(() => {
    const style = getComputedStyle(window.__byId("tinted").querySelector("svg path"));
    return [style.stroke, style.strokeDasharray, style.strokeDashoffset].join(" | ");
  });
  const before = await fill();
  await click(page, "tint");
  const immediate = await fill();
  await settle(page);
  const final = await fill();
  assert.notEqual(before, final, `${label}: the fill changed`);
  assert.equal(immediate, final, `${label}: a transaction without animation makes the fill jump, not ease (${immediate}, then ${final})`);
}

async function scrollTransitions(page, label) {
  const opacity = (index) => page.evaluate((id) => Number(getComputedStyle(window.__byId(id)).opacity), `card-${index}`);
  near(await opacity(0), 1, 0.01, `${label}: a card fully in its scroll view is at identity`);
  near(await opacity(10), 0.3, 0.01, `${label}: a card below the scroll view is at its trailing phase`);
  // The effect sits on what the view already has: a card with its own opacity keeps it at identity.
  near(await opacity(1), 0.4, 0.01, `${label}: a card with opacity 0.4 keeps it at identity`);
  // And follows it when the view's own opacity changes.
  await click(page, "card-opacity");
  await page.waitForFunction(() => Math.abs(Number(getComputedStyle(window.__byId("card-1")).opacity) - 0.8) < 0.02, null, { timeout: 3000 });
  // The phase follows where the card is laid out, not the box its own scale gives it: the same phase as with the effect off.
  const phase = await page.evaluate(() => {
    const card = window.__byId("card-3"), animation = card.getAnimations().find((candidate) => candidate.id === "scroll-transition");
    const view = (window.__byId("cards").querySelector(".scroll-view") ?? window.__byId("cards")).getBoundingClientRect();
    const time = animation.currentTime;
    animation.currentTime = 500;
    const box = card.getBoundingClientRect();
    animation.currentTime = time;
    const visible = Math.max(0, Math.min(box.bottom, view.bottom) - Math.max(box.top, view.top)) / box.height;
    return { time, expected: ((box.top + box.bottom) / 2 < (view.top + view.bottom) / 2 ? -1 : 1) * (1 - visible) * 500 + 500 };
  });
  near(phase.time, phase.expected, 2, `${label}: a scaled card's phase is measured from its layout box`);
  // Half of card 3 (40px, from 144px) shows in the 160px view: half way through its interactive transition.
  const partial = await opacity(3);
  assert.ok(partial > 0.3 && partial < 1, `${label}: a card that is partly visible is between phases (${partial})`);
  await page.evaluate(() => { const cards = window.__byId("cards"); (cards.querySelector(".scroll-view") ?? cards).scrollTop = 480; });
  await page.waitForTimeout(120);
  near(await opacity(0), 0.3, 0.01, `${label}: scrolled past, the first card is at its leading phase`);
  near(await opacity(11), 1, 0.01, `${label}: and a card scrolled into view is at identity`);
}

/** `scrollTransition(topLeading:bottomTrailing:)`: past the top the identity edge changes nothing; past the bottom the
 * animated edge plays to its phase with its own animation. */
async function edgeScrollTransitions(page, label) {
  const opacity = (index) => page.evaluate((id) => Number(getComputedStyle(window.__byId(id)).opacity), `edge-${index}`);
  near(await opacity(0), 1, 0.01, `${label}: an edge card in its scroll view is at identity`);
  near(await opacity(10), 0.3, 0.01, `${label}: one below the view is at the trailing edge's phase`);
  await page.evaluate(() => { const view = window.__byId("edges"); (view.querySelector(".scroll-view") ?? view).scrollTop = 480; });
  await page.waitForFunction(() => window.__byId("edge-11").getAnimations().some((animation) => animation.effect.getTiming().duration === 200), null, { timeout: 2000 });
  const easing = await page.evaluate(() => window.__byId("edge-11").getAnimations().find((animation) => animation.effect.getTiming().duration === 200).effect.getTiming().easing);
  assert.equal(easing, "linear", `${label}: a card coming in at the bottom plays the trailing edge's animation`);
  // Like every scroll transition, it is the scroll position's to end, not the test's.
  await page.waitForFunction(() => window.__byId("edge-11").getAnimations().every((animation) => animation.playState === "finished"), null, { timeout: 3000 });
  near(await opacity(11), 1, 0.01, `${label}: and ends at identity`);
  near(await opacity(0), 1, 0.01, `${label}: past the top, the identity edge changes nothing`);
}

/** An animated scroll transition on a snap target moves the target's children, not the target: the browser computes snap
 * positions from the targets' boxes. */
async function snapTargetScrollTransition(page, label) {
  const state = (index) => page.evaluate((id) => {
    const element = window.__byId(id), animations = element.getAnimations({ subtree: true }).filter((animation) => animation.id === "scroll-transition");
    return { own: animations.filter((animation) => animation.effect.target === element).length, moved: animations.filter((animation) => animation.effect.target !== element && element.contains(animation.effect.target)).length };
  }, `snap-${index}`);
  const snapping = await page.evaluate(() => getComputedStyle(window.__byId("snap-0")).scrollSnapAlign);
  assert.ok(snapping && snapping.split(" ").some((part) => part !== "none"), `${label}: the snap targets snap (${snapping})`);
  const below = await state(10);
  assert.ok(below.moved > 0, `${label}: a snap target below the view plays its animated effect on its children (${JSON.stringify(below)})`);
  assert.equal(below.own, 0, `${label}: and not on its own box (${JSON.stringify(below)})`);
  // A child whose own transform changes is composed with again: the effect sits on its new appearance.
  await click(page, "snap-rotate");
  await page.waitForFunction(() => {
    const child = [...window.__byId("snap-10").children].find((candidate) => candidate.textContent.includes("Snap 10"));
    return child && Math.abs(new DOMMatrix(getComputedStyle(child).transform).a - 0.433) < 0.03;
  }, null, { timeout: 3000 });
  // A child inserted into the snap target gets the effect too: the animations do not stay on the children it had.
  await click(page, "snap-extra");
  await page.waitForFunction(() => {
    const element = window.__byId("snap-10"), target = element.matches("[data-scroll-transition]") ? element : element.closest("[data-scroll-transition]") ?? element.querySelector("[data-scroll-transition]");
    return target && target.children.length > 1 && [...target.children].every((child) => child.getAnimations().some((animation) => animation.id === "scroll-transition"));
  }, null, { timeout: 3000 });
}

/** `.contentTransition(.symbolEffect(.replace))`: a copy of the old symbol leaves, inert and nameless, while the new one
 * arrives. */
async function symbolReplace(page, label) {
  await page.click('[data-testid="swap"]');
  await page.waitForTimeout(60);
  const state = await page.evaluate(() => {
    const star = window.__byId("star"), icon = star.matches("[data-symbol]") ? star : star.querySelector("[data-symbol]");
    const ghost = [...document.body.children].find((element) => element.hasAttribute("data-transition-leaving") && element.getAnimations().some((animation) => animation.id === "symbol-replace-out"));
    return {
      ghost: !!ghost, inert: !!ghost?.inert, named: !!(ghost?.matches("[data-testid]") || ghost?.querySelector("[data-testid]")),
      symbols: [ghost?.getAttribute("data-symbol"), icon.getAttribute("data-symbol")],
      arriving: icon.getAnimations().map((animation) => animation.effect.getTiming().delay),
    };
  });
  assert.ok(state.ghost, `${label}: the replaced symbol stays to play leaving`);
  assert.ok(state.inert && !state.named, `${label}: out of reach, with no identity of the view`);
  assert.notEqual(state.symbols[0], state.symbols[1], `${label}: the copy shows the old symbol (${state.symbols})`);
  assert.ok(state.arriving.includes(200), `${label}: the new symbol arrives as the old one goes (${state.arriving})`);
  await settle(page);
  assert.equal(await page.evaluate(() => [...document.body.children].some((element) => element.hasAttribute("data-transition-leaving"))), false, `${label}: the copy goes when it has left`);
}

/** `matchedGeometryEffect(isSource: false)`: the pill takes the selected tab's frame and moves to the next one with the
 * animation; the dot, matching only the position at its bottom anchor, keeps its size. */
async function matchedGeometry(page, label) {
  const boxes = () => page.evaluate(() => {
    const box = (element) => { const rect = element.getBoundingClientRect(); return { x: rect.left, y: rect.top, w: rect.width, h: rect.height }; };
    const matched = (id, kind) => { const element = window.__byId(id); return element.closest(`[data-matched-${kind}]`) ?? element.querySelector(`[data-matched-${kind}]`) ?? element; };
    return { pill: box(matched("pill", "target")), dot: box(matched("dot", "target")), tabs: [0, 1, 2].map((index) => box(matched(`tab-${index}`, "source"))) };
  });
  let at = await boxes();
  const onTab = (tab, message) => {
    near(at.pill.x, tab.x, 1, `${label}: ${message}: the pill's x`); near(at.pill.w, tab.w, 1, `${label}: ${message}: its width`);
    near(at.pill.y, tab.y, 1, `${label}: ${message}: its y`); near(at.pill.h, tab.h, 1, `${label}: ${message}: its height`);
    near(at.dot.w, 8, 0.5, `${label}: ${message}: the dot keeps its size`);
    near(at.dot.x + 4, tab.x + tab.w / 2, 1, `${label}: ${message}: the dot's bottom is under the tab's`);
    near(at.dot.y + 8, tab.y + tab.h, 1, `${label}: ${message}: at the tab's bottom`);
  };
  onTab(at.tabs[0], "the first tab");
  await page.click('[data-testid="tab-2"]');
  await page.waitForTimeout(60);
  // A commit that has nothing to do with the move leaves it playing, from where it was.
  const move = () => page.evaluate(() => {
    const pill = window.__byId("pill"), element = pill.closest("[data-matched-target]") ?? pill.querySelector("[data-matched-target]") ?? pill;
    const animation = element.getAnimations().find((candidate) => candidate.id === "matched-geometry");
    return animation ? { duration: animation.effect.getTiming().duration, time: animation.currentTime, state: animation.playState } : null;
  });
  const before = await move();
  assert.ok(before && before.duration > 0, `${label}: the pill's move is playing (${JSON.stringify(before)})`);
  await click(page, "kind");
  await page.waitForTimeout(40);
  const during = await move();
  assert.ok(during && during.duration > 0, `${label}: a commit that does not move it leaves the move playing (${JSON.stringify(during)})`);
  assert.ok(during.time >= before.time, `${label}: and it goes on from where it was (${before.time} to ${during.time})`);
  const halfWay = await page.evaluate(() => {
    const pill = window.__byId("pill"), element = pill.closest("[data-matched-target]") ?? pill.querySelector("[data-matched-target]") ?? pill;
    for (const animation of element.getAnimations()) { animation.pause(); animation.currentTime = 500; }
    return element.getBoundingClientRect().left;
  });
  assert.ok(halfWay > at.tabs[0].x + 2 && halfWay < at.tabs[2].x - 2, `${label}: the pill moves to the new tab with the animation (${halfWay})`);
  await settle(page);
  at = await boxes();
  onTab(at.tabs[2], "the third tab");
  // A size the layout publishes while the view follows a source is kept, not put back to the one before the match.
  await click(page, "dot-size");
  await page.waitForFunction(() => {
    const dot = window.__byId("dot"), element = dot.closest("[data-matched-target]") ?? dot.querySelector("[data-matched-target]") ?? dot;
    return Math.abs(element.getBoundingClientRect().width - 16) < 0.5;
  }, null, { timeout: 3000 });
}

/** A target follows a source in a scroll view of its own: scrolling the source moves the target with it, with no commit. */
async function matchedGeometryScroll(page, label) {
  const centers = () => page.evaluate(() => {
    const center = (element) => { const rect = element.getBoundingClientRect(); return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 }; };
    const matched = (id, kind) => { const element = window.__byId(id); return element.closest(`[data-matched-${kind}]`) ?? element.querySelector(`[data-matched-${kind}]`) ?? element; };
    return { source: center(matched("scroll-source", "source")), follower: center(matched("scroll-follower", "target")) };
  });
  const before = await centers();
  near(before.follower.y, before.source.y, 1.5, `${label}: the follower starts on the source`);
  await page.evaluate(() => {
    const box = window.__byId("scroll-box");
    const scroller = [box, ...box.querySelectorAll("*")].find((element) => element.scrollHeight > element.clientHeight + 1);
    scroller.scrollTop = 15;
  });
  await page.waitForFunction(() => {
    const matched = (id, kind) => { const element = window.__byId(id); return element.closest(`[data-matched-${kind}]`) ?? element.querySelector(`[data-matched-${kind}]`) ?? element; };
    const source = matched("scroll-source", "source").getBoundingClientRect(), follower = matched("scroll-follower", "target").getBoundingClientRect();
    return Math.abs((source.top + source.height / 2) - (follower.top + follower.height / 2)) < 1.5;
  }, null, { timeout: 3000 });
  const after = await centers();
  assert.ok(Math.abs(after.source.y - before.source.y) > 10, `${label}: the source moved with the scroll (${before.source.y} to ${after.source.y})`);
}

/** A target under a scaled ancestor lands on its source: the move is in the target's own coordinates, not the viewport's. */
async function matchedGeometryScaled(page, label) {
  await page.waitForFunction(() => {
    const matched = (id, kind) => { const element = window.__byId(id); return element.closest(`[data-matched-${kind}]`) ?? element.querySelector(`[data-matched-${kind}]`) ?? element; };
    const source = matched("scale-source", "source").getBoundingClientRect(), follower = matched("scale-follower", "target").getBoundingClientRect();
    return Math.abs((source.left + source.width / 2) - (follower.left + follower.width / 2)) < 1.5 && Math.abs((source.top + source.height / 2) - (follower.top + follower.height / 2)) < 1.5;
  }, null, { timeout: 3000 });
  const size = await page.evaluate(() => { const element = window.__byId("scale-follower"); const target = element.closest("[data-matched-target]") ?? element.querySelector("[data-matched-target]") ?? element; return target.getBoundingClientRect().width; });
  near(size, 16, 0.5, `${label}: the scaled follower keeps its size (8 points at 2x)`);
}

/** A view with a transition animation of its own, replaced by a taller one placed before it in a commit that animates nothing
 * else: its removal starts from where it was, not from where the replacement pushed it. The host is driven as the patcher
 * drives it (begin, noteChildren, the insertion, holdRemoval, finish), on a container of its own in a blank page (the
 * app's page does not let a script import a module from a blob). */
async function removalWithOwnTiming(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { TransitionHost } = await import(url);
    URL.revokeObjectURL(url);
    const container = document.createElement("div");
    container.style.cssText = "position:relative;width:100px;";
    const old = document.createElement("div");
    old.style.height = "10px";
    old.setAttribute("data-transition-timing", "opacity 1s linear");
    old.setAttribute("data-transition-remove", "opacity:0");
    old.setAttribute("data-key", "old");
    container.append(old);
    document.body.append(container);
    const host = new TransitionHost({
      window, root: document.body, reducedMotion: { matches: false }, armedTiming: () => null,
      motionTiming: () => ({ duration: 1000, delay: 0, easing: "linear" }), supportedTransition: (easing) => easing,
    });
    const replacement = document.createElement("div");
    replacement.style.height = "40px";
    replacement.setAttribute("data-key", "replacement");
    host.begin(null);
    host.noteChildren(container, [old], [replacement], (element) => element.getAttribute("data-key"));
    container.insertBefore(replacement, old);
    if (!host.holdRemoval(old, container)) old.remove();
    host.finish();
    const top = old.getBoundingClientRect().top - container.getBoundingClientRect().top;
    for (const animation of document.getAnimations()) animation.cancel();
    container.remove();
    return top;
  }, hostSource);
  await page.close();
  near(result, 0, 2, `${label}: the replaced view's removal starts where it was (${result})`);
}

/** A view removed under a scaled ancestor keeps its size and place while it leaves: its box is read in the viewport and written in
 * its own coordinates. Driven as the patcher drives the host, in a blank page. */
async function removalUnderTransform(appPage, label, hostSource, name, containerTransform) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async ({ source, containerTransform }) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { TransitionHost } = await import(url);
    URL.revokeObjectURL(url);
    const container = document.createElement("div");
    container.style.cssText = "position:relative;width:200px;margin:150px;transform:" + containerTransform + ";transform-origin:0 0;";
    const spacer = document.createElement("div");
    spacer.style.height = "15px";
    const old = document.createElement("div");
    old.style.cssText = "height:40px;width:100px;";
    old.setAttribute("data-transition-timing", "opacity 1s linear");
    old.setAttribute("data-transition-remove", "opacity:0");
    container.append(spacer, old);
    document.body.append(container);
    const host = new TransitionHost({
      window, root: document.body, reducedMotion: { matches: false }, armedTiming: () => null,
      motionTiming: () => ({ duration: 1000, delay: 0, easing: "linear" }), supportedTransition: (easing) => easing,
    });
    const before = old.getBoundingClientRect();
    host.begin(null);
    if (!host.holdRemoval(old, container)) old.remove();
    host.finish();
    const after = old.getBoundingClientRect();
    for (const animation of document.getAnimations()) animation.cancel();
    container.remove();
    return { before: { x: before.left, y: before.top, w: before.width, h: before.height }, after: { x: after.left, y: after.top, w: after.width, h: after.height } };
  }, { source: hostSource, containerTransform });
  await page.close();
  for (const key of ["x", "y", "w", "h"]) near(result.after[key], result.before[key], 1, `${label}: a removal under ${name} keeps its ${key} (${JSON.stringify(result)})`);
}

/** Siblings that make room for an insertion under a scaled ancestor start where they were: the displacement they play is in their
 * own coordinates. Driven as the patcher drives the host, in a blank page. */
async function siblingMovesUnderScale(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { TransitionHost } = await import(url);
    URL.revokeObjectURL(url);
    const container = document.createElement("div");
    container.style.cssText = "position:relative;width:100px;transform:scale(2);transform-origin:0 0;";
    const make = (key, height) => { const element = document.createElement("div"); element.style.height = height + "px"; element.setAttribute("data-key", key); return element; };
    const first = make("a", 10), second = make("b", 10);
    container.append(first, second);
    document.body.append(container);
    const host = new TransitionHost({
      window, root: document.body, reducedMotion: { matches: false }, armedTiming: () => null,
      motionTiming: () => ({ duration: 1000, delay: 0, easing: "linear" }), supportedTransition: (easing) => easing,
    });
    const inserted = make("n", 40);
    host.begin("all 1s linear");
    host.noteChildren(container, [first, second], [inserted, first, second], (element) => element.getAttribute("data-key"));
    container.insertBefore(inserted, first);
    host.finish();
    const start = first.getAnimations().map((animation) => animation.effect.getKeyframes()[0].translate).find(Boolean);
    for (const animation of document.getAnimations()) animation.cancel();
    container.remove();
    return start;
  }, hostSource);
  await page.close();
  // 40 points of room at 2x is 80 in the viewport, 40 in the sibling's own coordinates.
  const y = parseFloat(String(result).split(" ")[1]);
  near(y, -40, 1, `${label}: a sibling under a 2x ancestor starts 40 of its own points back (${result})`);
}

/** Under a rotated ancestor the siblings move by what the list changed in their own axes: none for a view added after them
 * (the parent's bounding box grows, they do not move), one row for a view added before them. */
async function siblingMovesUnderRotation(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { TransitionHost } = await import(url);
    URL.revokeObjectURL(url);
    const run = (transform, atEnd) => {
      const container = document.createElement("div");
      container.style.cssText = "position:absolute;left:300px;top:300px;width:100px;transform:" + transform + ";";
      const make = (key, height) => { const element = document.createElement("div"); element.style.height = height + "px"; element.setAttribute("data-key", key); return element; };
      const first = make("a", 10), second = make("b", 10);
      container.append(first, second);
      document.body.append(container);
      const host = new TransitionHost({
        window, root: document.body, reducedMotion: { matches: false }, armedTiming: () => null,
        motionTiming: () => ({ duration: 1000, delay: 0, easing: "linear" }), supportedTransition: (easing) => easing,
      });
      const inserted = make("n", 40);
      host.begin("all 1s linear");
      host.noteChildren(container, [first, second], atEnd ? [first, second, inserted] : [inserted, first, second], (element) => element.getAttribute("data-key"));
      if (atEnd) container.append(inserted); else container.insertBefore(inserted, first);
      host.finish();
      const moves = [first, second].map((element) => element.getAnimations().map((animation) => animation.effect.getKeyframes()[0].translate).find(Boolean) ?? null);
      for (const animation of document.getAnimations()) animation.cancel();
      container.remove();
      return moves;
    };
    return { after: run("rotate(90deg)", true), before: run("rotate(90deg)", false), tiltedAfter: run("rotate(30deg) scale(1.5)", true), tiltedBefore: run("rotate(30deg) scale(1.5)", false) };
  }, hostSource);
  await page.close();
  const text = JSON.stringify(result);
  for (const name of ["after", "tiltedAfter"]) assert.deepEqual(result[name], [null, null], `${label}: a view added after its siblings under a rotated ancestor moves none of them (${name}, ${text})`);
  for (const name of ["before", "tiltedBefore"]) {
    for (const move of result[name]) {
      const [x, y] = String(move).split(" ").map(parseFloat);
      near(x, 0, 1, `${label}: a view added before its siblings moves them along their own y only (${name}, ${text})`);
      near(y, -40, 1, `${label}: by the room it takes, 40 of their own points (${name}, ${text})`);
    }
  }
}

/** A view with a scale of its own keeps its look while it leaves: the size written back is the one without the scale. */
async function removalOfTransformedView(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { TransitionHost } = await import(url);
    URL.revokeObjectURL(url);
    const container = document.createElement("div");
    container.style.cssText = "position:relative;width:200px;margin:20px;";
    const old = document.createElement("div");
    old.style.cssText = "height:40px;width:100px;transform:scale(0.5);";
    old.setAttribute("data-transition-timing", "opacity 1s linear");
    old.setAttribute("data-transition-remove", "opacity:0");
    container.append(old);
    document.body.append(container);
    const host = new TransitionHost({
      window, root: document.body, reducedMotion: { matches: false }, armedTiming: () => null,
      motionTiming: () => ({ duration: 1000, delay: 0, easing: "linear" }), supportedTransition: (easing) => easing,
    });
    const before = old.getBoundingClientRect();
    host.begin(null);
    if (!host.holdRemoval(old, container)) old.remove();
    host.finish();
    const after = old.getBoundingClientRect();
    for (const animation of document.getAnimations()) animation.cancel();
    container.remove();
    return { before: { x: before.left, y: before.top, w: before.width, h: before.height }, after: { x: after.left, y: after.top, w: after.width, h: after.height } };
  }, hostSource);
  await page.close();
  for (const key of ["x", "y", "w", "h"]) near(result.after[key], result.before[key], 1, `${label}: a scaled view keeps its ${key} while it leaves (${JSON.stringify(result)})`);
}

/** A matched target with a scale of its own: a position-only match keeps its size, a frame match takes the source's. */
async function matchedGeometryOwnScale(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { MatchedGeometryHost } = await import(url);
    URL.revokeObjectURL(url);
    const run = (properties, transform = "scale(0.5)") => {
      const root = document.createElement("div");
      root.style.cssText = "position:relative;width:400px;height:100px;";
      const from = document.createElement("div");
      from.style.cssText = "position:absolute;left:200px;top:10px;width:20px;height:20px;";
      from.setAttribute("data-matched-source", "s");
      const target = document.createElement("div");
      target.style.cssText = "width:100px;height:40px;transform:" + transform + ";";
      target.setAttribute("data-matched-target", "s");
      target.setAttribute("data-matched-properties", properties);
      root.append(from, target);
      document.body.append(root);
      const host = new MatchedGeometryHost({ window, root, timingFor: () => null, supportedTransition: (easing) => easing });
      const before = target.getBoundingClientRect();
      host.sync(false);
      const after = target.getBoundingClientRect(), source = from.getBoundingClientRect();
      host.dispose();
      root.remove();
      const box = (rect) => ({ x: rect.left, y: rect.top, w: rect.width, h: rect.height });
      return { before: box(before), after: box(after), source: box(source) };
    };
    return { position: run("position"), frame: run("frame"), turnedPosition: run("position", "rotate(90deg)"), turnedFrame: run("frame", "rotate(90deg)") };
  }, hostSource);
  await page.close();
  const { position, frame, turnedPosition, turnedFrame } = result;
  near(position.after.w, position.before.w, 1, `${label}: a position-only match keeps the scaled target's width (${JSON.stringify(position)})`);
  near(position.after.h, position.before.h, 1, `${label}: and its height`);
  near(position.after.x + position.after.w / 2, position.source.x + position.source.w / 2, 1.5, `${label}: centred on the source's x`);
  near(frame.after.w, frame.source.w, 1, `${label}: a frame match gives the scaled target the source's width (${JSON.stringify(frame)})`);
  near(frame.after.h, frame.source.h, 1, `${label}: and its height`);
  near(frame.after.x, frame.source.x, 1.5, `${label}: at the source's x`);
  near(frame.after.y, frame.source.y, 1.5, `${label}: and y`);
  // A target turned a quarter: its two sides swap, and a frame match is still the source's frame.
  near(turnedPosition.after.w, turnedPosition.before.w, 1, `${label}: a position-only match keeps the turned target's width (${JSON.stringify(turnedPosition)})`);
  near(turnedPosition.after.h, turnedPosition.before.h, 1, `${label}: and its height`);
  near(turnedFrame.after.w, turnedFrame.source.w, 1, `${label}: a frame match gives the turned target the source's width (${JSON.stringify(turnedFrame)})`);
  near(turnedFrame.after.h, turnedFrame.source.h, 1, `${label}: and its height`);
  near(turnedFrame.after.x, turnedFrame.source.x, 1.5, `${label}: at the source's x`);
  near(turnedFrame.after.y, turnedFrame.source.y, 1.5, `${label}: and y`);
}

/** In an animated commit a matched target starts from the box it showed, under a rotated or scaled ancestor too, and ends on
 * the source's new frame. */
async function matchedGeometryStartsWhereItShowed(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { MatchedGeometryHost } = await import(url);
    URL.revokeObjectURL(url);
    const box = (rect) => ({ x: rect.left, y: rect.top, w: rect.width, h: rect.height });
    const run = (transform) => {
      const stage = document.createElement("div");
      stage.style.cssText = "position:absolute;left:300px;top:300px;width:200px;height:200px;" + (transform ? "transform:" + transform + ";" : "");
      const from = document.createElement("div");
      from.style.cssText = "position:absolute;left:20px;top:30px;width:20px;height:20px;";
      from.setAttribute("data-matched-source", "s");
      const target = document.createElement("div");
      target.style.cssText = "position:absolute;left:0;top:0;width:10px;height:10px;";
      target.setAttribute("data-matched-target", "s");
      stage.append(from, target);
      document.body.append(stage);
      const host = new MatchedGeometryHost({ window, root: stage, timingFor: () => ({ duration: 1000, delay: 0, easing: "linear" }), supportedTransition: (easing) => easing });
      host.sync(false);
      const shown = box(target.getBoundingClientRect());
      from.style.cssText = "position:absolute;left:60px;top:90px;width:80px;height:40px;";
      host.sync(true);
      const animation = target.getAnimations().find((candidate) => candidate.id === "matched-geometry");
      animation.pause();
      animation.currentTime = 0;
      const start = box(target.getBoundingClientRect());
      animation.currentTime = 1000;
      const end = box(target.getBoundingClientRect()), goal = box(from.getBoundingClientRect());
      host.dispose();
      stage.remove();
      return { shown, start, end, goal };
    };
    return { plain: run(null), turned: run("rotate(90deg)"), scaled: run("scale(2)"), tilted: run("rotate(30deg) scale(1.5)"), mirrored: run("scale(-1, 1)") };
  }, hostSource);
  await page.close();
  for (const [name, found] of Object.entries(result)) {
    for (const key of ["x", "y", "w", "h"]) {
      near(found.start[key], found.shown[key], 1.5, `${label}: a matched move starts from the box the view showed (${name}), its ${key} (${JSON.stringify(found)})`);
      near(found.end[key], found.goal[key], 1.5, `${label}: and ends on the source's new frame (${name}), its ${key} (${JSON.stringify(found)})`);
    }
  }
}

/** A scale transition on a view that has a transform of its own about another point leaves the view where it rests: its
 * identity frame is the view as it is, and its active frame is scaled about the transition's anchor. */
async function scaleTransitionKeepsTheViewsOwnOrigin(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { TransitionHost } = await import(url);
    URL.revokeObjectURL(url);
    const host = new TransitionHost({
      window, root: document.body, reducedMotion: { matches: false }, armedTiming: () => null,
      motionTiming: () => ({ duration: 1000, delay: 0, easing: "linear" }), supportedTransition: (easing) => easing,
    });
    const box = (rect) => ({ x: rect.left, y: rect.top, w: rect.width, h: rect.height });
    const run = (own, insert) => {
      const parent = document.createElement("div");
      parent.style.cssText = "position:absolute;left:100px;top:100px;width:300px;height:200px;";
      const view = document.createElement("div");
      view.style.cssText = "width:100px;height:40px;" + own;
      view.setAttribute("data-transition-insert", insert);
      document.body.append(parent);
      host.begin("all 1s linear");
      parent.append(view);
      const resting = box(view.getBoundingClientRect());
      host.noteInsertion(view, parent);
      host.finish();
      const animation = view.getAnimations()[0];
      animation.pause();
      animation.currentTime = 1000 - 1e-6;
      const identity = box(view.getBoundingClientRect());
      animation.currentTime = 0;
      const active = box(view.getBoundingClientRect());
      animation.cancel();
      parent.remove();
      return { resting, identity, active };
    };
    return {
      cornerScale: run("transform:scale(0.5);transform-origin:0 0;", "scale:0.5;transform-origin:50% 50%"),
      cornerScaleMoved: run("transform:scale(0.5);transform-origin:0 0;", "translate:10px 0px;scale:0.5;transform-origin:50% 50%"),
      plain: run("", "scale:0.5;transform-origin:50% 50%"),
    };
  }, hostSource);
  await page.close();
  const text = JSON.stringify(result);
  for (const [name, found] of Object.entries(result)) for (const key of ["x", "y", "w", "h"]) near(found.identity[key], found.resting[key], 0.5, `${label}: at identity the view is where it rests (${name}), its ${key} (${text})`);
  // The view shows 50 by 20 at its top-leading corner; scaled by half about the middle of its 100 by 40 layout box it shows 25 by
  // 10, a quarter of the layout box in from the corner.
  const corner = result.cornerScale;
  near(corner.active.w, 25, 0.5, `${label}: the active frame is half the view's width again (${text})`);
  near(corner.active.x, corner.resting.x + 25, 0.5, `${label}: scaled about the middle of its layout box, not about its own corner (${text})`);
  near(corner.active.y, corner.resting.y + 10, 0.5, `${label}: on both axes (${text})`);
  near(result.cornerScaleMoved.active.x, corner.active.x + 10, 0.5, `${label}: with the transition's own move added (${text})`);
  near(result.plain.active.x, result.plain.resting.x + 25, 0.5, `${label}: a view without a transform scales about the anchor as before (${text})`);
}

/** A flash of the scroll indicators moves the view a step and back along an axis it can scroll: a horizontal view horizontally. */
async function flashAlongTheScrollingAxis(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { TransitionHost } = await import(url);
    URL.revokeObjectURL(url);
    const host = new TransitionHost({
      window, root: document.body, reducedMotion: { matches: false }, armedTiming: () => null,
      motionTiming: () => ({ duration: 1000, delay: 0, easing: "linear" }), supportedTransition: (easing) => easing,
    });
    const run = (content, { direction = "ltr", left = 0, top = 0 } = {}) => {
      const view = document.createElement("div");
      view.className = "scroll-view";
      view.style.cssText = "width:100px;height:100px;overflow:auto;direction:" + direction + ";";
      const inner = document.createElement("div");
      inner.style.cssText = content;
      view.append(inner);
      document.body.append(view);
      view.scrollTo({ left, top, behavior: "instant" });
      const start = [view.scrollLeft, view.scrollTop], visited = [];
      const scrollTo = view.scrollTo.bind(view);
      view.scrollTo = (options) => { scrollTo(options); visited.push([view.scrollLeft, view.scrollTop]); };
      host.flashScrollIndicators(view);
      const end = [view.scrollLeft, view.scrollTop];
      view.remove();
      return { start, visited, end };
    };
    return {
      horizontal: run("width:400px;height:50px;"), vertical: run("width:50px;height:400px;"), both: run("width:400px;height:400px;"),
      atEnd: run("width:400px;height:50px;", { left: 300 }), rightToLeft: run("width:400px;height:50px;", { direction: "rtl" }), fits: run("width:50px;height:50px;"),
    };
  }, hostSource);
  await page.close();
  const text = JSON.stringify(result);
  for (const [name, found] of Object.entries(result)) assert.deepEqual(found.end, found.start, `${label}: a flash leaves the view where it was (${name}, ${text})`);
  const moved = (found) => found.visited.length > 0 && (found.visited[0][0] !== found.start[0] || found.visited[0][1] !== found.start[1]);
  for (const name of ["horizontal", "vertical", "both", "atEnd", "rightToLeft"]) assert.ok(moved(result[name]), `${label}: a flash moves a view that scrolls (${name}) a step and back (${text})`);
  assert.equal(result.horizontal.visited[0][1], 0, `${label}: a horizontal view steps horizontally (${text})`);
  assert.equal(result.fits.visited.length, 0, `${label}: a view whose content fits has nothing to flash (${text})`);
}

/** A scroll transition measures the box its view is laid out in, in the viewport, under a scaled ancestor too. */
async function scrollLayoutRectUnderScale(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { layoutRect } = await import(url);
    URL.revokeObjectURL(url);
    const container = document.createElement("div");
    container.style.cssText = "position:relative;width:200px;height:200px;transform:scale(2);transform-origin:0 0;";
    const make = (transform) => {
      const element = document.createElement("div");
      element.style.cssText = "position:absolute;left:10px;top:50px;width:100px;height:100px;" + (transform ? "transform:" + transform + ";" : "");
      container.append(element);
      return element;
    };
    const moved = make("translateY(20px) scale(0.5)"), reference = make(null);
    document.body.append(container);
    const laid = layoutRect(moved, window), expected = reference.getBoundingClientRect();
    container.remove();
    const box = (rect) => ({ x: rect.left, y: rect.top, w: rect.width, h: rect.height });
    return { laid: box(laid), expected: box(expected) };
  }, hostSource);
  await page.close();
  for (const key of ["x", "y", "w", "h"]) near(result.laid[key], result.expected[key], 1, `${label}: the scroll transition's layout box under a 2x ancestor keeps its ${key} (${JSON.stringify(result)})`);
}

/** A transition's own animation that repeats plays its repeats: the host reads them from the timing. */
async function transitionRepeats(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { TransitionHost } = await import(url);
    URL.revokeObjectURL(url);
    const container = document.createElement("div");
    document.body.append(container);
    const host = new TransitionHost({
      window, root: document.body, reducedMotion: { matches: false }, armedTiming: () => null,
      motionTiming: (value) => ({ duration: parseFloat(value), delay: 0, easing: "linear" }), supportedTransition: (easing) => easing,
    });
    const play = (timing) => {
      const old = document.createElement("div");
      old.style.height = "10px";
      old.setAttribute("data-transition-timing", timing);
      old.setAttribute("data-transition-remove", "opacity:0");
      container.append(old);
      host.begin(null);
      if (!host.holdRemoval(old, container)) old.remove();
      host.finish();
      const timingOf = old.getAnimations()[0]?.effect.getTiming();
      const out = timingOf && { iterations: timingOf.iterations, direction: timingOf.direction, duration: timingOf.duration };
      for (const animation of document.getAnimations()) animation.cancel();
      return out;
    };
    const result = { once: play("1000ms linear"), counted: play("1000ms linear repeat:3 normal"), endless: play("1000ms linear repeat:infinite alternate") };
    container.remove();
    return result;
  }, hostSource);
  await page.close();
  assert.equal(result.once.iterations, 1, `${label}: a transition animation that does not repeat plays once`);
  assert.equal(result.counted.iterations, 3, `${label}: repeatCount(3) plays three times (${JSON.stringify(result)})`);
  assert.equal(result.counted.direction, "normal", `${label}: without autoreversing`);
  assert.equal(result.endless.iterations, 1, `${label}: an endless removal plays once, so that the view can leave`);
  assert.equal(result.endless.direction, "alternate", `${label}: and it keeps the direction`);
}

/** Stacked colour multipliers: the view's filter keeps both references and the page defines both matrices. */
async function colorMultipliers(page, label) {
  const result = await page.evaluate(() => {
    const element = window.__byId("multiplied");
    const target = element.closest("[data-color-multiply]") ?? element.querySelector("[data-color-multiply]") ?? element;
    const references = [...(target.style.filter || getComputedStyle(target).filter).matchAll(/url\("?#([^")]+)"?\)/g)].map((match) => match[1]);
    const defined = new Set([...document.querySelectorAll("#swu-color-multiply-defs filter")].map((filter) => filter.id));
    return { attribute: target.getAttribute("data-color-multiply"), references, undefinedReferences: references.filter((id) => !defined.has(id)) };
  });
  assert.equal(result.attribute, "1 0 1 1;0 1 1 1", `${label}: the view lists both multipliers (${JSON.stringify(result)})`);
  assert.equal(result.references.length, 2, `${label}: its filter references both (${JSON.stringify(result)})`);
  assert.deepEqual(result.undefinedReferences, [], `${label}: and the page defines each of them`);
}

/** The ancestors' mapping is measured from the element's own place, whatever translation it has already. */
async function basisWithATranslation(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { localBasis } = await import(url);
    URL.revokeObjectURL(url);
    const container = document.createElement("div");
    container.style.cssText = "position:relative;width:200px;height:200px;transform:scale(2);transform-origin:0 0;";
    const child = document.createElement("div");
    child.style.cssText = "width:50px;height:20px;translate:20px 0;";
    container.append(child);
    document.body.append(container);
    const own = child.style.translate, basis = localBasis(window, child), kept = child.style.translate === own;
    container.remove();
    return { basis, kept };
  }, hostSource);
  await page.close();
  assert.ok(result.basis, `${label}: a 2x ancestor gives a basis`);
  for (const [key, expected] of [["a", 2], ["b", 0], ["c", 0], ["d", 2]]) near(result.basis[key], expected, 0.01, `${label}: the basis of a translated element under a 2x ancestor, ${key} (${JSON.stringify(result)})`);
  assert.equal(result.kept, true, `${label}: and the element's own translate is put back`);
}

/** A symbol replace plays at the speed and for the repeats its options ask: the host reads them from the content transition. */
async function symbolReplaceOptions(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { TransitionHost } = await import(url);
    URL.revokeObjectURL(url);
    const host = new TransitionHost({
      window, root: document.body, reducedMotion: { matches: false }, armedTiming: () => null,
      motionTiming: () => ({ duration: 1000, delay: 0, easing: "linear" }), supportedTransition: (easing) => easing,
    });
    const play = (attributes) => {
      const holder = document.createElement("div");
      holder.setAttribute("data-content-transition", "symbol-effect");
      holder.setAttribute("data-content-transition-direction", "replace-down-up");
      for (const [name, value] of Object.entries(attributes)) holder.setAttribute(name, value);
      const symbol = document.createElement("span");
      symbol.setAttribute("data-symbol", "star");
      symbol.textContent = "*";
      holder.append(symbol);
      document.body.append(holder);
      host.begin("all 1s linear");
      host.noteSymbolReplace(symbol, symbol.cloneNode(true));
      const timing = symbol.getAnimations()[0]?.effect.getTiming();
      const out = timing && { duration: timing.duration, delay: timing.delay, iterations: timing.iterations };
      for (const animation of document.getAnimations()) animation.cancel();
      document.querySelectorAll("[data-symbol]").forEach((element) => element.closest("div")?.remove());
      return out;
    };
    return { plain: play({}), tuned: play({ "data-content-transition-speed": "2", "data-content-transition-repeat": "3" }) };
  }, hostSource);
  await page.close();
  assert.deepEqual(result.plain, { duration: 300, delay: 200, iterations: 1 }, `${label}: a replace without options plays at its own speed, once (${JSON.stringify(result)})`);
  assert.deepEqual(result.tuned, { duration: 150, delay: 100, iterations: 3 }, `${label}: at twice the speed and three times with the options (${JSON.stringify(result)})`);
}

/** A symbol effect transition's speed and repeats play with its timing: the host reads them from the transition's attributes. */
async function symbolTransitionOptions(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { TransitionHost } = await import(url);
    URL.revokeObjectURL(url);
    const container = document.createElement("div");
    document.body.append(container);
    const host = new TransitionHost({
      window, root: document.body, reducedMotion: { matches: false }, armedTiming: () => null,
      motionTiming: () => ({ duration: 1000, delay: 0, easing: "linear" }), supportedTransition: (easing) => easing,
    });
    const timing = (attributes) => {
      const element = document.createElement("div");
      element.setAttribute("data-transition-remove", "opacity:0");
      for (const [name, value] of Object.entries(attributes)) element.setAttribute(name, value);
      container.append(element);
      host.begin("all 1s linear");
      const found = host.timingFor(element, container, "remove");
      return found && { duration: found.duration, iterations: found.iterations ?? 1 };
    };
    const result = { plain: timing({}), tuned: timing({ "data-transition-speed": "2", "data-transition-repeat": "3" }) };
    container.remove();
    return result;
  }, hostSource);
  await page.close();
  assert.deepEqual(result.plain, { duration: 1000, iterations: 1 }, `${label}: a symbol transition without options plays the commit's timing once (${JSON.stringify(result)})`);
  assert.deepEqual(result.tuned, { duration: 500, iterations: 3 }, `${label}: at twice the speed and three times with the options (${JSON.stringify(result)})`);
}

/** The gradient of a text under a scale: in the text's own coordinates, like the glyphs. */
async function gradientUnderScale(appPage, label) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const hostSource = await fs.promises.readFile(new URL("./geometry-host.js", import.meta.url), "utf8");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { textLayoutPayload } = await import(url);
    URL.revokeObjectURL(url);
    const wrapper = document.createElement("div");
    wrapper.style.cssText = "transform:scale(2);transform-origin:0 0;width:100px;";
    const text = document.createElement("span");
    text.setAttribute("data-text-layout", "");
    text.textContent = "Gradient";
    text.style.cssText = "display:inline-block;width:100px;font:16px sans-serif;background-image:linear-gradient(to right, red, blue);-webkit-background-clip:text;background-clip:text;color:transparent;";
    wrapper.append(text);
    document.body.append(wrapper);
    const payload = textLayoutPayload(text);
    wrapper.remove();
    const match = /"x1":(-?[\d.]+)/.exec(payload);
    return { x1: match ? Number(match[1]) : null, found: !!match };
  }, hostSource);
  await page.close();
  assert.ok(result.found, `${label}: the layout carries the text's gradient`);
  near(result.x1, 100, 1, `${label}: the gradient of a 100 point text under a 2x scale ends at 100, not 200 (${JSON.stringify(result)})`);
}

/** A geometry effect's size is the one its content lays out at, under a scaled ancestor too. */
async function effectSizeUnderScale(appPage, label) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const hostSource = await fs.promises.readFile(new URL("./geometry-host.js", import.meta.url), "utf8");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { measurementPayload } = await import(url);
    URL.revokeObjectURL(url);
    const wrapper = document.createElement("div");
    wrapper.style.cssText = "transform:scale(2);transform-origin:0 0;";
    const make = (marker) => {
      const element = document.createElement("div");
      element.style.cssText = "width:100px;height:20px;";
      element.setAttribute("data-geometry-untransformed", marker);
      wrapper.append(element);
      return element;
    };
    const effect = make("local"), other = make("true");
    document.body.append(wrapper);
    const size = (element) => measurementPayload(element, document.body).split("\u001e")[0].split(",").slice(2, 4).map(Number);
    const out = { effect: size(effect), other: size(other) };
    wrapper.remove();
    return out;
  }, hostSource);
  await page.close();
  assert.deepEqual(result.effect, [100, 20], `${label}: a geometry effect gets its content's layout size under a 2x ancestor (${JSON.stringify(result)})`);
  assert.deepEqual(result.other, [200, 40], `${label}: other measurements keep the viewport's frame (${JSON.stringify(result)})`);
}

/** A scroll transition with a centered threshold is in a phase as soon as the view is off center; `hidden` only fully out. */
async function centeredScrollPhase(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { discretePhase } = await import(url);
    URL.revokeObjectURL(url);
    return {
      centeredAbove: discretePhase(-0.6, { threshold: "centered" }), centeredBelow: discretePhase(0.6, { threshold: "centered" }), centeredAt: discretePhase(0, { threshold: "centered" }),
      partial: discretePhase(-0.6, { threshold: "0.5" }), hiddenPartly: discretePhase(-0.6, { threshold: "0" }), hiddenOut: discretePhase(-1, { threshold: "0" }),
    };
  }, hostSource);
  await page.close();
  assert.deepEqual(result, { centeredAbove: 0, centeredBelow: 2, centeredAt: 1, partial: 0, hiddenPartly: 1, hiddenOut: 0 }, `${label}: the discrete phase of an animated scroll transition (${JSON.stringify(result)})`);
}

/** Digits rolling in under a scaled ancestor: the slots' widths are in their own pixels, so they are the same as without it. */
async function numericWidthsUnderScale(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { TransitionHost } = await import(url);
    URL.revokeObjectURL(url);
    const host = new TransitionHost({
      window, root: document.body, reducedMotion: { matches: false }, armedTiming: () => null,
      motionTiming: () => ({ duration: 1000, delay: 0, easing: "linear" }), supportedTransition: (easing) => easing,
    });
    const widths = (transform) => {
      const wrapper = document.createElement("div");
      wrapper.style.cssText = "font:20px monospace;" + (transform ? "transform:" + transform + ";transform-origin:0 0;" : "");
      const holder = document.createElement("span");
      holder.setAttribute("data-content-transition", "numeric-text");
      const node = document.createTextNode("22");
      holder.append(node);
      wrapper.append(holder);
      document.body.append(wrapper);
      host.begin("all 1s linear");
      host.playText({ node, previous: "1", kind: "numeric-text", up: true, timing: { duration: 1000, delay: 0, easing: "linear" } });
      const frames = [...wrapper.querySelectorAll("[data-content-run] span")].flatMap((slot) => slot.getAnimations()).map((animation) => animation.effect.getKeyframes()).filter((keyframes) => keyframes[0].width !== undefined)
        .map((keyframes) => keyframes.map((keyframe) => parseFloat(keyframe.width)));
      for (const animation of document.getAnimations()) animation.cancel();
      wrapper.remove();
      return frames[0] ?? null;
    };
    // A cross-fade of one line under a rotation is still one line: it plays in character slots, not as a wrapped paragraph.
    const crossFade = (transform) => {
      const wrapper = document.createElement("div");
      wrapper.style.cssText = "font:20px monospace;width:400px;" + (transform ? "transform:" + transform + ";" : "");
      const holder = document.createElement("span");
      const node = document.createTextNode("one line of text");
      holder.append(node);
      wrapper.append(holder);
      document.body.append(wrapper);
      host.begin("all 1s linear");
      host.playText({ node, previous: "another line", kind: "opacity", up: true, timing: { duration: 1000, delay: 0, easing: "linear" } });
      const slots = wrapper.querySelectorAll("[data-content-run] > span > span").length;
      for (const animation of document.getAnimations()) animation.cancel();
      wrapper.remove();
      return slots;
    };
    return { plain: widths(null), scaled: widths("scale(2)"), turned: widths("rotate(90deg)"), tilted: widths("rotate(30deg) scale(1.5)"), fadePlain: crossFade(null), fadeTurned: crossFade("rotate(90deg)"), fadeTilted: crossFade("rotate(30deg)") };
  }, hostSource);
  await page.close();
  assert.ok(result.plain && result.scaled && result.turned && result.tilted, `${label}: the digits' slot animates its width (${JSON.stringify(result)})`);
  assert.ok(result.fadePlain > 0, `${label}: a one-line cross-fade plays the old text out and the new one in (${JSON.stringify(result)})`);
  assert.equal(result.fadeTurned, result.fadePlain, `${label}: under a quarter turn it is still one line (${JSON.stringify(result)})`);
  assert.equal(result.fadeTilted, result.fadePlain, `${label}: and under a tilt`);
  for (const name of ["turned", "tilted"]) {
    near(result[name][0], result.plain[0], 0.6, `${label}: its width starts the same under a rotated ancestor (${name}, ${JSON.stringify(result)})`);
    near(result[name][1], result.plain[1], 0.6, `${label}: and ends the same: the characters' height is not taken for their width`);
  }
  near(result.scaled[0], result.plain[0], 0.6, `${label}: its width starts the same under a 2x ancestor (${JSON.stringify(result)})`);
  near(result.scaled[1], result.plain[1], 0.6, `${label}: and ends the same`);
}

/** An insertion that a commit animates with a repeating animation plays the repeats, as the Swift-driven data does. */
async function transactionRepeats(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { TransitionHost } = await import(url);
    URL.revokeObjectURL(url);
    const container = document.createElement("div");
    document.body.append(container);
    const host = new TransitionHost({
      window, root: document.body, reducedMotion: { matches: false }, armedTiming: () => null,
      motionTiming: () => ({ duration: 1000, delay: 0, easing: "linear" }), supportedTransition: (easing) => easing,
    });
    const timing = (commit, side) => {
      const element = document.createElement("div");
      element.setAttribute("data-transition-" + side, "opacity:0");
      container.append(element);
      host.begin(commit);
      const found = host.timingFor(element, container, side);
      return found && { iterations: found.iterations ?? 1, direction: found.direction ?? "normal" };
    };
    const result = {
      once: timing("all 1000ms linear", "insert"),
      counted: timing("all 1000ms linear /* repeat 3 */", "insert"),
      reversing: timing("all 1000ms linear /* repeat 3 */ /* alternate */", "remove"),
      endless: timing("all 1000ms linear /* infinite */ /* alternate */", "insert"),
      // The siblings' move is not a view entering or leaving: no side, no repeats.
      sibling: host.timingFor(container, container),
    };
    container.remove();
    return result;
  }, hostSource);
  await page.close();
  assert.deepEqual(result.once, { iterations: 1, direction: "normal" }, `${label}: a commit without repeats plays once (${JSON.stringify(result)})`);
  assert.deepEqual(result.counted, { iterations: 3, direction: "normal" }, `${label}: repeatCount(3) plays an insertion three times`);
  assert.deepEqual(result.reversing, { iterations: 3, direction: "alternate" }, `${label}: and keeps the autoreverse for a removal`);
  assert.deepEqual(result.endless, { iterations: Infinity, direction: "alternate" }, `${label}: and an endless one repeats for ever`);
}

/** The transaction of a view that enters or leaves is the one closest to it: an `.animation(_:value:)` armed in the commit wins
 * over `withAnimation` and over a `.transaction` above it, and a `.transaction` below it still has the last word. */
async function nearestTransactionWins(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { TransitionHost } = await import(url);
    URL.revokeObjectURL(url);
    // outer > armed > inner > parent: `armed` is the element an `.animation(_:value:)` armed in this commit.
    const [outer, armed, inner, parent] = [0, 1, 2, 3].map(() => document.createElement("div"));
    outer.append(armed); armed.append(inner); inner.append(parent);
    document.body.append(outer);
    let armedTimingValue = "1000ms linear";
    const host = new TransitionHost({
      window, root: document.body, reducedMotion: { matches: false },
      armedTiming: (element, within = null) => armedTimingValue && armed.contains(element) && (!within || (within !== armed && within.contains(armed))) ? armedTimingValue : null,
      motionTiming: (css) => { const match = /(\d+)ms/.exec(css || ""); return match ? { duration: Number(match[1]), delay: 0, easing: "linear" } : null; },
      supportedTransition: (easing) => easing,
    });
    const timing = ({ commit = "all 10000ms linear", outerScope = null, innerScope = null, armedNow = "1000ms linear" }) => {
      armedTimingValue = armedNow;
      for (const [element, scope] of [[outer, outerScope], [inner, innerScope]]) {
        if (scope === null) element.removeAttribute("data-transaction-timing"); else element.setAttribute("data-transaction-timing", scope);
      }
      const element = document.createElement("div");
      element.setAttribute("data-transition-insert", "opacity:0");
      parent.append(element);
      host.begin(commit);
      const found = host.timingFor(element, parent, "insert");
      const moves = host.resolveTiming(host.scopedTiming(parent, parent));
      element.remove();
      return { duration: found ? found.duration : null, iterations: found ? found.iterations ?? 1 : null, moves: moves ? moves.duration : null };
    };
    const result = {
      overCommit: timing({}),
      commitOnly: timing({ armedNow: null }),
      overOuterScope: timing({ outerScope: "all 5000ms linear" }),
      overOuterOptOut: timing({ outerScope: "none" }),
      underInnerScope: timing({ innerScope: "all 5000ms linear" }),
      underInnerOptOut: timing({ innerScope: "none" }),
      aloneWithoutCommit: timing({ commit: null }),
      repeating: timing({ armedNow: "1000ms linear /* repeat 3 */" }),
    };
    outer.remove();
    return result;
  }, hostSource);
  await page.close();
  const text = JSON.stringify(result);
  assert.deepEqual(result.overCommit, { duration: 1000, iterations: 1, moves: 1000 }, `${label}: an armed value animation wins over the commit's ten seconds, for the insertion and the siblings (${text})`);
  assert.equal(result.commitOnly.duration, 10000, `${label}: without one the commit's timing plays (${text})`);
  assert.equal(result.overOuterScope.duration, 1000, `${label}: it wins over a .transaction above it (${text})`);
  assert.equal(result.overOuterOptOut.duration, 1000, `${label}: and over one that cleared the animation above it (${text})`);
  assert.equal(result.underInnerScope.duration, 5000, `${label}: a .transaction below it has the last word (${text})`);
  assert.deepEqual(result.underInnerOptOut, { duration: null, iterations: null, moves: null }, `${label}: and an opt-out below it is kept (${text})`);
  assert.equal(result.aloneWithoutCommit.duration, 1000, `${label}: it animates a commit without a transaction, as before (${text})`);
  assert.equal(result.repeating.iterations, 3, `${label}: and its repeats play on the view that enters (${text})`);
}

/** A scroll transition's layout box under a rotated ancestor: the rotation mixes the axes, and the box is still the one laid out. */
async function scrollLayoutRectUnderRotation(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { layoutRect } = await import(url);
    URL.revokeObjectURL(url);
    const box = (rect) => ({ x: rect.left, y: rect.top, w: rect.width, h: rect.height });
    const measure = (containerTransform, transform) => {
      const container = document.createElement("div");
      container.style.cssText = "position:absolute;left:150px;top:150px;width:100px;height:200px;" + containerTransform;
      const make = (own) => {
        const element = document.createElement("div");
        element.style.cssText = "position:absolute;left:10px;top:50px;width:20px;height:40px;" + (own ? own + ";" : "");
        container.append(element);
        return element;
      };
      const moved = make(transform), reference = make(null);
      document.body.append(container);
      const found = { laid: box(layoutRect(moved, window, new Map())), expected: box(reference.getBoundingClientRect()) };
      container.remove();
      return found;
    };
    return {
      quarter: measure("transform:rotate(90deg);", "transform:scale(0.5)"),
      skewed: measure("rotate:30deg;scale:1.5;", "translate:8px 12px;scale:0.5 0.25"),
      nested: measure("transform:rotate(90deg) scale(2);", "transform:translateY(20px) scale(0.5)"),
    };
  }, hostSource);
  await page.close();
  for (const [name, found] of Object.entries(result)) {
    for (const key of ["x", "y", "w", "h"]) near(found.laid[key], found.expected[key], 1, `${label}: the scroll transition's layout box under a rotated ancestor (${name}) keeps its ${key} (${JSON.stringify(found)})`);
  }
}

/** Under a scaled or rotated ancestor, the copy of a replaced symbol and a surface that leaves stay where the view showed. */
async function leavingCopiesUnderTransform(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { TransitionHost } = await import(url);
    URL.revokeObjectURL(url);
    const host = new TransitionHost({
      window, root: document.body, reducedMotion: { matches: false }, armedTiming: () => null,
      motionTiming: () => ({ duration: 1000, delay: 0, easing: "linear" }), supportedTransition: (easing) => easing,
    });
    const box = (rect) => ({ x: rect.left, y: rect.top, w: rect.width, h: rect.height });
    const stage = (transform) => {
      const container = document.createElement("div");
      container.style.cssText = "position:absolute;left:200px;top:200px;width:200px;height:120px;transform:" + transform + ";";
      document.body.append(container);
      return container;
    };
    const clear = () => { for (const animation of document.getAnimations()) animation.cancel(); document.body.replaceChildren(); };
    const ghost = (transform) => {
      const container = stage(transform);
      const holder = document.createElement("div");
      holder.setAttribute("data-content-transition", "symbol-effect");
      holder.setAttribute("data-content-transition-direction", "replace-off-up");
      const symbol = document.createElement("span");
      symbol.style.cssText = "display:inline-block;width:30px;height:20px;margin:15px 0 0 25px;";
      symbol.setAttribute("data-symbol", "star");
      holder.append(symbol);
      container.append(holder);
      host.begin("all 1s linear");
      const expected = box(symbol.getBoundingClientRect());
      host.noteSymbolReplace(symbol, symbol.cloneNode(true));
      const copy = document.body.querySelector("body > [data-transition-leaving]");
      const found = { expected, shown: copy ? box(copy.getBoundingClientRect()) : null };
      clear();
      return found;
    };
    const exit = (transform) => {
      const container = stage(transform);
      const surface = document.createElement("div");
      surface.className = "navigation-destination";
      surface.style.cssText = "width:120px;height:50px;margin:10px 0 0 20px;padding:4px;";
      container.append(surface);
      surface.animate([{ opacity: 1 }, { opacity: 0.5 }], { duration: 10000 });
      const expected = box(surface.getBoundingClientRect());
      host.playExit(surface);
      const found = { expected, shown: box(surface.getBoundingClientRect()), connected: surface.isConnected };
      clear();
      return found;
    };
    return { ghostScaled: ghost("scale(2)"), ghostTurned: ghost("rotate(90deg) scale(1.5)"), ghostPlain: ghost("none"), exitScaled: exit("scale(2)"), exitTurned: exit("rotate(90deg)"), exitPlain: exit("none") };
  }, hostSource);
  await page.close();
  for (const [name, found] of Object.entries(result)) {
    assert.ok(found.shown, `${label}: ${name} leaves a copy in the page (${JSON.stringify(found)})`);
    for (const key of ["x", "y", "w", "h"]) near(found.shown[key], found.expected[key], 1, `${label}: what leaves stays where the view showed (${name}), its ${key} (${JSON.stringify(found)})`);
  }
}

/** A cut line too narrow for its first glyph beside the ellipsis is the ellipsis alone: every glyph is replaced. */
async function loneEllipsis(appPage, label) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const hostSource = await fs.promises.readFile(new URL("./geometry-host.js", import.meta.url), "utf8");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { textLayoutPayload } = await import(url);
    URL.revokeObjectURL(url);
    const measure = (direction, width, content) => {
      const element = document.createElement("div");
      element.style.cssText = "font:20px monospace;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;direction:" + direction + ";width:" + width + "px;";
      element.textContent = content;
      document.body.append(element);
      const context = document.createElement("canvas").getContext("2d");
      context.font = getComputedStyle(element).font;
      const records = textLayoutPayload(element).split("\u001e").map((record) => record.split("\u001f"));
      element.remove();
      const glyphs = records.filter((record) => record[0] === "G").map((record) => ({ x: Number(record[1].split(",")[0]), text: record[2] }));
      return { glyphs, hidden: records.filter((record) => record[0] === "H").length, mark: context.measureText("\u2026").width, width };
    };
    // Narrower than a glyph and the ellipsis together, wider than the ellipsis.
    const probe = document.createElement("canvas").getContext("2d");
    probe.font = "20px monospace";
    const narrow = Math.ceil(probe.measureText("\u2026").width) + 3;
    return { ltr: measure("ltr", narrow, "MMMM"), rtl: measure("rtl", narrow, "\u05e9\u05dc\u05d5\u05dd"), room: measure("ltr", narrow * 3, "MMMMMMMM") };
  }, hostSource);
  await page.close();
  const text = JSON.stringify(result);
  assert.deepEqual(result.ltr.glyphs.map((glyph) => glyph.text), ["\u2026"], `${label}: a line too narrow for a glyph and the ellipsis is the ellipsis alone (${text})`);
  near(result.ltr.glyphs[0].x, 0, 1, `${label}: at the start of the line`);
  assert.equal(result.ltr.hidden, 4, `${label}: and every glyph is among the hidden ones (${text})`);
  assert.deepEqual(result.rtl.glyphs.map((glyph) => glyph.text), ["\u2026"], `${label}: so is a right-to-left one (${text})`);
  near(result.rtl.glyphs[0].x, result.rtl.width - result.rtl.mark, 1.5, `${label}: with the ellipsis at its right edge, where it starts (${text})`);
  assert.ok(result.room.glyphs.length > 1 && result.room.glyphs.at(-1).text === "\u2026", `${label}: with room, the glyphs that fit stay before the ellipsis (${text})`);
}

/** A reader and an anchor under a 2x scale are in the view's own points: the bars they size are as wide as the 100 point view. */
async function readersUnderScale(page, label) {
  const widths = () => page.evaluate(() => ["scaled-reader-bar", "scaled-anchor-bar"].map((id) => window.__byId(id)?.getBoundingClientRect().width ?? null));
  await page.waitForFunction(() => ["scaled-reader-bar", "scaled-anchor-bar"].every((id) => window.__byId(id) && window.__byId(id).getBoundingClientRect().width > 0), null, { timeout: 5000 });
  await page.waitForTimeout(150);
  const [reader, anchor] = await widths();
  near(reader, 200, 1.5, `${label}: a reader under a 2x scale sees 100 points, so its bar shows 200 (${reader})`);
  near(anchor, 200, 1.5, `${label}: and a bounds anchor under it is 100 points as well (${anchor})`);
  // The anchored view under the scale, its reader outside it: the anchor is the box the view shows in the reader's points.
  await page.waitForFunction(() => window.__byId("outer-anchor-bar")?.getBoundingClientRect().width > 0, null, { timeout: 5000 });
  await page.waitForTimeout(150);
  const outer = await page.evaluate(() => {
    const bar = window.__byId("outer-anchor-bar").getBoundingClientRect(), source = window.__byId("outer-anchor-source").getBoundingClientRect();
    return { bar: { x: bar.left, y: bar.top, w: bar.width }, source: { x: source.left, y: source.top, w: source.width } };
  });
  for (const key of ["x", "y", "w"]) near(outer.bar[key], outer.source[key], 1.5, `${label}: an anchor read outside the scale of its view keeps the view's ${key} (${JSON.stringify(outer)})`);
  // A visual effect whose closure reads state: the state changes, the geometry does not, and the effect follows.
  const effect = () => page.evaluate(() => { const style = getComputedStyle(window.__byId("state-effect")); return { opacity: Number(style.opacity), moved: style.transform !== "none" || style.translate !== "none" }; });
  await page.waitForFunction(() => { const style = getComputedStyle(window.__byId("state-effect")); return style.transform !== "none" || style.translate !== "none"; }, null, { timeout: 5000 });
  assert.equal((await effect()).opacity, 1, `${label}: a visual effect starts with the state it reads`);
  await click(page, "dim-effect");
  await page.waitForTimeout(150);
  const dimmed = await effect();
  near(dimmed.opacity, 0.3, 0.01, `${label}: a change of the state a visual effect reads shows without a change of geometry (${JSON.stringify(dimmed)})`);
  assert.ok(dimmed.moved, `${label}: and the part of the effect that reads the geometry stays`);
  await click(page, "dim-effect");
  await page.waitForTimeout(150);
  assert.equal((await effect()).opacity, 1, `${label}: and back`);
  // The anchored view turned a quarter, its reader not: the bounds are the turned box.
  await page.waitForFunction(() => window.__byId("turned-anchor-bar")?.getBoundingClientRect().height > 50, null, { timeout: 5000 });
  await page.waitForTimeout(150);
  const turned = await page.evaluate(() => {
    const box = (id) => { const rect = window.__byId(id).getBoundingClientRect(); return { x: rect.left, y: rect.top, w: rect.width, h: rect.height }; };
    return { bar: box("turned-anchor-bar"), source: box("turned-anchor-source") };
  });
  near(turned.source.w, 20, 1.5, `${label}: the 100 by 20 view turned a quarter shows 20 wide (${JSON.stringify(turned)})`);
  for (const key of ["x", "y", "w", "h"]) near(turned.bar[key], turned.source[key], 1.5, `${label}: an anchor read outside the rotation of its view covers the turned view, its ${key} (${JSON.stringify(turned)})`);
}

/** The payload of a view under a scaled ancestor carries the size it lays out at; without a scale it is the plain frame. */
async function payloadUnderScale(appPage, label) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const hostSource = await fs.promises.readFile(new URL("./geometry-host.js", import.meta.url), "utf8");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { measurementPayload } = await import(url);
    URL.revokeObjectURL(url);
    const make = (transform) => {
      const wrapper = document.createElement("div");
      wrapper.style.cssText = "margin:10px;" + (transform ? "transform:scale(2);transform-origin:0 0;" : "");
      wrapper.setAttribute("data-coordinate-space", "stage");
      const element = document.createElement("div");
      element.style.cssText = "width:100px;height:20px;";
      wrapper.append(element);
      document.body.append(wrapper);
      const payload = measurementPayload(element, document.body);
      wrapper.remove();
      return payload;
    };
    // A quarter turn, and a turn with a scale: the box's sides are not the view's, so the payload says the scale of its axes.
    const turned = (transform) => {
      const wrapper = document.createElement("div");
      wrapper.style.cssText = "position:absolute;left:200px;top:200px;transform:" + transform + ";";
      const element = document.createElement("div");
      element.style.cssText = "width:100px;height:20px;";
      wrapper.append(element);
      document.body.append(wrapper);
      const payload = measurementPayload(element, document.body);
      wrapper.remove();
      return payload.split("\u001e")[0].split(",").map(Number);
    };
    // A square turned a quarter and a mirrored view have the box they would have anyway: the axes are published all the same.
    const square = (transform) => {
      const wrapper = document.createElement("div");
      wrapper.style.cssText = "position:absolute;left:200px;top:200px;transform:" + transform + ";";
      const element = document.createElement("div");
      element.style.cssText = "width:40px;height:40px;";
      wrapper.append(element);
      document.body.append(wrapper);
      const payload = measurementPayload(element, document.body);
      wrapper.remove();
      return payload.split("\u001e")[0].split(",").map(Number).slice(2);
    };
    // A view in a scroll view turned a quarter: the scroll view's space carries its axes, as a view does.
    const scrolled = () => {
      const wrapper = document.createElement("div");
      wrapper.style.cssText = "position:absolute;left:300px;top:300px;transform:rotate(90deg);";
      const view = document.createElement("div");
      view.className = "scroll-view";
      view.style.cssText = "width:200px;height:100px;overflow:auto;";
      const element = document.createElement("div");
      element.style.cssText = "width:50px;height:20px;margin:10px 0 0 30px;";
      view.append(element);
      wrapper.append(view);
      document.body.append(wrapper);
      const record = measurementPayload(element, document.body).split("\u001e").map((part) => part.split("\u001f")).find((part) => part[0] === "s");
      const expected = view.getBoundingClientRect();
      wrapper.remove();
      return { numbers: record[2].split(",").map(Number), expected: [expected.left, expected.top, expected.width, expected.height] };
    };
    // The glyphs of a text under a transform, in the text's own coordinates: the same as without one.
    const { textLayoutPayload } = await import(URL.createObjectURL(new Blob([source], { type: "text/javascript" })));
    const glyphs = (transform) => {
      const wrapper = document.createElement("div");
      wrapper.style.cssText = "position:absolute;left:300px;top:300px;" + (transform ? "transform:" + transform + ";" : "");
      const element = document.createElement("div");
      element.style.cssText = "font:20px monospace;width:200px;white-space:nowrap;";
      element.textContent = "Hello wide";
      wrapper.append(element);
      document.body.append(wrapper);
      const records = textLayoutPayload(element).split("\u001e").map((record) => record.split("\u001f"));
      wrapper.remove();
      return {
        lines: records.filter((record) => record[0] === "L").map((record) => record[1].split(",").map(Number)),
        glyphs: records.filter((record) => record[0] === "G").map((record) => record[1].split(",").map(Number).slice(0, 2)),
      };
    };
    return {
      scaled: make(true), plain: make(false), quarter: turned("rotate(90deg)"), turnedTwice: turned("rotate(90deg) scale(2)"),
      scrolled: scrolled(), squareTurned: square("rotate(90deg)"), squareMirrored: square("scale(-1, 1)"), squarePlain: square("none"),
      text: { plain: glyphs(null), quarter: glyphs("rotate(90deg)"), tilted: glyphs("rotate(30deg) scale(1.5)"), eighth: glyphs("rotate(45deg)"), mirrored: glyphs("scale(-1, 1)") },
    };
  }, hostSource);
  await page.close();
  const [head, ...spaces] = result.scaled.split("\u001e");
  assert.equal(head, "10,10,200,40,100,20", `${label}: a view under a 2x scale reports its window box and its own size (${JSON.stringify(result)})`);
  assert.match(spaces[0] ?? "", /^n\u001fstage\u001f10,10,\d+,40,\d+,20$/, `${label}: and so does the named space around it, 40 window pixels high and 20 points (${JSON.stringify(spaces)})`);
  assert.equal(result.plain.split("\u001e")[0], "10,10,100,20", `${label}: without a scale the payload is the plain frame (${JSON.stringify(result)})`);
  assert.deepEqual(result.quarter.slice(2), [20, 100, 100, 20, 0, 1, -1, 0], `${label}: a view turned a quarter reports its turned box, its own size and where its axes go, not the sides' ratio (${JSON.stringify(result.quarter)})`);
  result.scrolled.expected.forEach((value, index) => near(result.scrolled.numbers[index], value, 1, `${label}: a scroll view turned a quarter reports the box its visible area shows (${JSON.stringify(result.scrolled)})`));
  assert.deepEqual(result.scrolled.numbers.slice(4), [200, 100, 0, 1, -1, 0], `${label}: with its own size and where its axes go (${JSON.stringify(result.scrolled)})`);
  assert.deepEqual(result.squareTurned, [40, 40, 40, 40, 0, 1, -1, 0], `${label}: a square turned a quarter has the same box and still says where its axes go (${JSON.stringify(result.squareTurned)})`);
  assert.deepEqual(result.squareMirrored, [40, 40, 40, 40, -1, 0, 0, 1], `${label}: and so does a mirrored view (${JSON.stringify(result.squareMirrored)})`);
  assert.deepEqual(result.squarePlain, [40, 40], `${label}: a view without a transform says neither (${JSON.stringify(result.squarePlain)})`);
  const { plain: flat, ...turnedTexts } = result.text;
  assert.equal(flat.lines.length, 1, `${label}: the text is one line (${JSON.stringify(flat.lines)})`);
  for (const [name, found] of Object.entries(turnedTexts)) {
    assert.equal(found.lines.length, 1, `${label}: a text under a transform (${name}) is still one line (${JSON.stringify(found.lines)})`);
    near(found.lines[0][1], flat.lines[0][1], 1, `${label}: with the same baseline (${name})`);
    assert.equal(found.glyphs.length, flat.glyphs.length, `${label}: and as many glyphs (${name})`);
    found.glyphs.forEach(([x, width], index) => {
      near(x, flat.glyphs[index][0], 1, `${label}: glyph ${index} under ${name} is at its own x (${JSON.stringify(found.glyphs)} against ${JSON.stringify(flat.glyphs)})`);
      near(width, flat.glyphs[index][1], 1, `${label}: with its own width (${name})`);
    });
  }
  assert.deepEqual(result.turnedTwice.slice(2), [40, 200, 100, 20, 0, 2, -2, 0], `${label}: turned and scaled, the axes at twice the length (${JSON.stringify(result.turnedTwice)})`);
}

/** A cross-fade of a paragraph keeps its lines while it plays, and the scroll position does not scrub the view with reduced motion. */
async function wrappingCrossFade(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  await page.setContent("<!doctype html><body style='margin:0'></body>");
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { TransitionHost, interactiveTime } = await import(url);
    URL.revokeObjectURL(url);
    const host = new TransitionHost({
      window, root: document.body, reducedMotion: { matches: false }, armedTiming: () => null,
      motionTiming: () => ({ duration: 1000, delay: 0, easing: "linear" }), supportedTransition: (easing) => easing,
    });
    const play = (text) => {
      const holder = document.createElement("div");
      holder.style.cssText = "width:120px;font:16px/20px sans-serif;";
      holder.setAttribute("data-content-transition", "opacity");
      const node = document.createTextNode(text);
      holder.append(node);
      document.body.append(holder);
      host.begin("all 1s linear");
      host.playText({ node, previous: "old", kind: "opacity", up: true, timing: { duration: 1000, delay: 0, easing: "linear" } });
      const height = holder.getBoundingClientRect().height;
      for (const animation of document.getAnimations()) animation.cancel();
      holder.remove();
      return height;
    };
    return {
      long: play("a long sentence that has to wrap onto several lines in a narrow box"), short: play("short"),
      times: [interactiveTime(-1, false), interactiveTime(0.5, false), interactiveTime(0.5, true)],
    };
  }, hostSource);
  await page.close();
  assert.ok(result.long >= 60, `${label}: a wrapping text keeps its lines while it cross-fades (${JSON.stringify(result)})`);
  assert.equal(result.short, 20, `${label}: a short text is one line`);
  assert.deepEqual(result.times, [0, 750, 500], `${label}: reduced motion keeps an interactive scroll transition at identity (${JSON.stringify(result)})`);
}

/** `Text.LayoutKey` and an anchor: a reader above a text draws a bar on its first line's baseline, from its layout. */
async function textLayoutPreference(page, label) {
  await page.waitForFunction(() => window.__byId("baseline"), null, { timeout: 5000 });
  const at = await page.evaluate(() => {
    const text = window.__byId("measured").querySelector("[data-text-layout]"), bar = window.__byId("baseline").getBoundingClientRect();
    const range = document.createRange(); range.selectNodeContents(text);
    const glyphs = range.getBoundingClientRect();
    return { barLeft: bar.left, barWidth: bar.width, barTop: bar.top, left: glyphs.left, width: glyphs.width, top: glyphs.top, bottom: glyphs.bottom };
  });
  near(at.barLeft, at.left, 1, `${label}: the layout's line starts where the page drew it`);
  near(at.barWidth, at.width, 1.5, `${label}: as wide as the line`);
  assert.ok(at.barTop > at.top + (at.bottom - at.top) / 2 && at.barTop < at.bottom, `${label}: on its baseline (${at.barTop} in ${at.top}...${at.bottom})`);
}

/** A renderer draws a run's underline and its gradient as the page painted them, and the page's own paint gives way. */
async function styledRenderer(page, label) {
  await page.waitForFunction(() => window.__byId("styled")?.querySelector("canvas[data-text-renderer-canvas]"), null, { timeout: 5000 });
  const drawn = await page.evaluate(() => {
    const host = window.__byId("styled"), canvas = host.querySelector("canvas[data-text-renderer-canvas]");
    const commands = JSON.parse(canvas.getAttribute("data-canvas-commands"));
    const data = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height).data;
    let red = 0, blue = 0;
    for (let index = 0; index < data.length; index += 4) {
      if (data[index + 3] < 200) continue;
      if (data[index] > 150 && data[index + 2] < 120) red++;
      if (data[index + 2] > 150 && data[index] < 120) blue++;
    }
    return {
      decorations: commands.filter((command) => command.o === "td").length,
      paints: commands.filter((command) => command.o === "gl" && command.p).map((command) => command.p.k),
      images: [...host.querySelectorAll("[data-text-run]")].map((run) => getComputedStyle(run).backgroundImage), red, blue,
    };
  });
  assert.equal(drawn.decorations, 1, `${label}: the underlined run draws its underline`);
  assert.deepEqual(drawn.paints, ["l"], `${label}: the gradient run draws with its linear gradient`);
  assert.ok(drawn.images.every((image) => image === "none"), `${label}: the page's gradient gives way to the drawing (${drawn.images})`);
  assert.ok(drawn.red > 20 && drawn.blue > 5, `${label}: the canvas shows the red underline and the gradient's blue (${drawn.red}, ${drawn.blue})`);
  // A gradient from the view around the text: the renderer draws with it, and the page's glyphs stay unpainted.
  await page.waitForFunction(() => window.__byId("around")?.querySelector("canvas[data-text-renderer-canvas]"), null, { timeout: 5000 });
  const around = await page.evaluate(() => {
    const canvas = window.__byId("around").querySelector("canvas[data-text-renderer-canvas]");
    return JSON.parse(canvas.getAttribute("data-canvas-commands")).filter((command) => command.o === "gl").map((command) => command.p?.k ?? "");
  });
  assert.deepEqual(around, ["l"], `${label}: a container's gradient paints the glyphs the renderer draws`);
  // The drawing is hidden by a rule of the page, not by its inline style: a render in between would write that again.
  const hideDrawing = await page.addStyleTag({ content: "canvas[data-text-renderer-canvas] { visibility: hidden !important; }" });
  const bare = await page.evaluate(async () => {
    const element = window.__byId("around");
    element.scrollIntoView({ block: "center", behavior: "instant" });
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const box = element.getBoundingClientRect();
    return { x: box.x, y: box.y, width: box.width, height: box.height };
  });
  // The text hides its glyphs under the gradient above: the page, not the element, is what shows.
  const shot = await page.screenshot({ clip: bare });
  await hideDrawing.evaluate((node) => node.remove());
  const painted = await page.evaluate(async (bytes) => {
    const image = await createImageBitmap(new Blob([new Uint8Array(bytes)], { type: "image/png" }));
    const canvas = new OffscreenCanvas(image.width, image.height), context = canvas.getContext("2d");
    context.drawImage(image, 0, 0);
    const data = context.getImageData(0, 0, image.width, image.height).data;
    let colored = 0;
    for (let index = 0; index < data.length; index += 4) if (Math.max(data[index], data[index + 1], data[index + 2]) - Math.min(data[index], data[index + 1], data[index + 2]) > 60) colored++;
    return colored;
  }, [...shot]);
  assert.ok(bare.width > 0, `${label}: the text keeps its box`);
  const reads = await page.evaluate(() => {
    const canvas = window.__byId("around").querySelector("canvas[data-text-renderer-canvas]");
    return { label: canvas.getAttribute("aria-label"), role: canvas.getAttribute("role"), visible: getComputedStyle(canvas).visibility };
  });
  assert.deepEqual(reads, { label: "Around", role: "img", visible: "visible" }, `${label}: under a gradient above, the drawing shows and reads the text`);
  assert.equal(painted, 0, `${label}: without the drawing, nothing of the gradient shows through the page's glyphs (${painted} colored pixels)`);
  // A color a view around the text sets changes what the renderer draws, though no style of the text changed.
  await page.evaluate(() => { window.__byId("styled").parentElement.style.color = "rgb(201, 11, 12)"; });
  await click(page, "kind");
  await page.waitForFunction(() => /201,\s*11,\s*12/.test(window.__byId("styled").querySelector("canvas[data-text-renderer-canvas]")?.getAttribute("data-canvas-commands") ?? ""), null, { timeout: 4000 });
  // And so does a font an ancestor sets.
  await page.evaluate(() => { window.__byId("styled").parentElement.style.fontWeight = "700"; });
  await click(page, "kind");
  await page.waitForFunction(() => / 700 /.test(window.__byId("styled").querySelector("canvas[data-text-renderer-canvas]")?.getAttribute("data-canvas-commands") ?? ""), null, { timeout: 4000 });
  // The parent is the page: its color and weight go back, or every text after this one is measured bold.
  await page.evaluate(() => { const parent = window.__byId("styled").parentElement; parent.style.removeProperty("font-weight"); parent.style.removeProperty("color"); });
  await click(page, "kind");
}

/** `TextProxy.sizeThatFits` lays the text out again at a width as the page does: the renderer's text, sized for 70
 * points, is as high as the same text the page lays out 70 points wide. */
async function textProxy(page, label) {
  await page.waitForFunction(() => window.__byId("narrow")?.querySelector("canvas[data-text-renderer-canvas]"), null, { timeout: 5000 });
  await page.waitForTimeout(100);
  const sizes = await page.evaluate(() => {
    const drawn = (window.__byId("narrow").querySelector("[data-text-layout]") ?? window.__byId("narrow")).getBoundingClientRect();
    const reference = window.__byId("narrow-reference").getBoundingClientRect();
    const limited = (window.__byId("limited").querySelector("[data-text-layout]") ?? window.__byId("limited")).getBoundingClientRect();
    const limitedReference = window.__byId("limited-reference").getBoundingClientRect();
    return { width: drawn.width, height: drawn.height, reference: reference.height, limited: limited.height, limitedReference: limitedReference.height };
  });
  assert.ok(sizes.width <= 70.5 && sizes.width > 30, `${label}: the renderer's text takes the width it was proposed (${sizes.width})`);
  near(sizes.height, sizes.reference, 1.5, `${label}: and as many lines as the page breaks it into`);
  assert.ok(sizes.limited < sizes.height - 5, `${label}: a line limit keeps fewer lines (${sizes.limited} against ${sizes.height})`);
  near(sizes.limited, sizes.limitedReference, 1.5, `${label}: as many as the page shows under the same limit`);
  // A text cut to one line is drawn with the ellipsis the browser draws, not clipped.
  await page.waitForFunction(() => window.__byId("ellipsized")?.querySelector("canvas[data-text-renderer-canvas]"), null, { timeout: 5000 });
  const drawnText = await page.evaluate(() => JSON.parse(window.__byId("ellipsized").querySelector("canvas[data-text-renderer-canvas]").getAttribute("data-canvas-commands")).filter((command) => command.o === "gl").map((command) => command.t).join(""));
  assert.ok(drawnText.endsWith("\u2026") && drawnText.length < "One long line that does not fit".length, `${label}: a cut text is drawn with its ellipsis (${drawnText})`);
  // Right-to-left text runs past its left edge, and its end is there: it is cut and drawn with the ellipsis too. (The element is
  // given the direction here; a right-to-left run in a left-to-right paragraph, as it first is, is cut at the right edge.)
  await page.waitForFunction(() => window.__byId("ellipsized-rtl")?.querySelector("canvas[data-text-renderer-canvas]"), null, { timeout: 5000 });
  const first = await page.evaluate(() => JSON.parse(window.__byId("ellipsized-rtl").querySelector("canvas[data-text-renderer-canvas]").getAttribute("data-canvas-commands")).filter((command) => command.o === "gl").map((command) => command.t).join(""));
  assert.ok(first.endsWith("\u2026") && first.length < "שלום עולם זה טקסט ארוך מאוד שלא נכנס".length, `${label}: a right-to-left run in a left-to-right paragraph is cut with its ellipsis (${first})`);
  await page.evaluate(() => { const root = window.__byId("ellipsized-rtl"); (root.matches("[data-text-layout]") ? root : root.querySelector("[data-text-layout]")).style.direction = "rtl"; });
  await click(page, "kind");
  await page.waitForTimeout(200);
  const rtlText = await page.evaluate(() => JSON.parse(window.__byId("ellipsized-rtl").querySelector("canvas[data-text-renderer-canvas]").getAttribute("data-canvas-commands")).filter((command) => command.o === "gl").map((command) => command.t).join(""));
  assert.ok(rtlText.endsWith("\u2026") && rtlText.length < "שלום עולם זה טקסט ארוך מאוד שלא נכנס".length, `${label}: a cut right-to-left text is drawn with its ellipsis (${rtlText})`);
}

async function completion(page, label) {
  await page.click('[data-testid="complete"]');
  await page.waitForTimeout(150);
  assert.equal(await page.textContent('[data-testid="completed"]'), "completed 0", `${label}: withAnimation's completion waits for the animation`);
  await page.waitForFunction(() => window.__byId("completed").textContent === "completed 1", null, { timeout: 3000 });
}

// What Swift animates itself, frame by frame (Sources/SwiftUIWebCore/Animator.swift): an Animatable view, a geometry
// effect and a shape take values between their old and new data while the page runs their timeline; a custom animation
// plays as an easing sampled from it; a `.transaction` that turns animations off makes its view jump; a dismissed sheet
// plays its exit before it leaves.
// The horizontal translation of a computed `transform` (`matrix(...)` or `matrix3d(...)`).
const translationX = (transform) => {
  const values = (/\(([^)]*)\)/.exec(transform)?.[1] ?? "").split(",").map(Number);
  return transform.startsWith("matrix3d") ? values[12] : transform.startsWith("matrix") ? values[4] : 0;
};

/** A TextRenderer: the page measures the text, Swift draws the glyphs where the page laid them out, every frame of its
 * animation, and the text stays in the page, transparent, for layout and accessibility. */
async function textRenderer(page, label) {
  const read = () => page.evaluate(() => {
    const text = window.__byId("typed"), canvas = text.querySelector("canvas[data-text-renderer-canvas]");
    if (!canvas) return null;
    const commands = JSON.parse(canvas.getAttribute("data-canvas-commands"));
    const glyphs = commands.filter((command) => command.o === "gl");
    // Where the page put the first glyph of each word, against where Swift draws it.
    const origin = text.getBoundingClientRect(), range = document.createRange();
    const first = text.querySelector("[data-text-run]").firstChild;
    range.setStart(first, 0); range.setEnd(first, 1);
    const box = range.getBoundingClientRect();
    const context = canvas.getContext("2d"), data = context.getImageData(0, 0, canvas.width, canvas.height).data;
    let painted = 0;
    for (let index = 3; index < data.length; index += 4) if (data[index] > 0) painted++;
    return {
      glyphs: glyphs.map((command) => command.t).join(""), firstX: glyphs[0]?.x, boxX: box.left - origin.left,
      firstY: glyphs[0]?.y, boxTop: box.top - origin.top, boxBottom: box.bottom - origin.top,
      fills: commands.filter((command) => command.o === "f").length, painted,
      fill: getComputedStyle(text).webkitTextFillColor, content: text.textContent,
    };
  });
  await page.waitForFunction(() => window.__byId("typed")?.querySelector("canvas[data-text-renderer-canvas]"), null, { timeout: 5000 });
  const idle = await read();
  assert.equal(idle.glyphs, "", `${label}: nothing is typed before the animation`);
  assert.equal(idle.painted, 0, `${label}: and the canvas is empty`);
  assert.equal(idle.content, "Hello renderer", `${label}: the text stays in the page`);
  assert.ok(/rgba\(0, 0, 0, 0\)|transparent/.test(idle.fill), `${label}: with its own glyphs transparent (${idle.fill})`);
  await page.click('[data-testid="type"]');
  await page.waitForTimeout(400);
  const halfWay = await read();
  assert.ok(halfWay.glyphs.length > 1 && halfWay.glyphs.length < 14, `${label}: the renderer types part of the text half way (${JSON.stringify(halfWay.glyphs)})`);
  await page.waitForFunction(() => !window.__byId("typed").closest('[data-timeline-view="animation"]'), null, { timeout: 3000 });
  const typed = await read();
  assert.equal(typed.glyphs, "Hello renderer", `${label}: every glyph is drawn at the end`);
  assert.ok(Math.abs(typed.firstX - typed.boxX) < 1, `${label}: where the page laid it out (${typed.firstX} against ${typed.boxX})`);
  assert.ok(typed.firstY > typed.boxTop && typed.firstY < typed.boxBottom, `${label}: on its baseline (${typed.firstY} in ${typed.boxTop}...${typed.boxBottom})`);
  assert.equal(typed.fills, 1, `${label}: the run with the custom attribute is underlined`);
  assert.ok(typed.painted > 100, `${label}: and the canvas shows it (${typed.painted} pixels)`);
}

/** A transition whose identity phase is turned 10 degrees: its active phase is 20, not 30. */
async function restingTransform(page, label) {
  await click(page, "toggle-tilt");
  const removal = await page.evaluate(() => { const element = [...document.querySelectorAll("[data-transition-leaving]")].find((candidate) => candidate.textContent.includes("Tilted")); const frame = element ? window.__keyframes(element)[0].frames[1] : null; return frame ? new DOMMatrix(frame.transform).a : null; });
  assert.ok(removal !== null && Math.abs(removal - Math.cos(Math.PI / 9)) < 0.02, `${label}: the active phase reaches its 20 degrees, not 30 (${removal})`);
  await settle(page);
  await click(page, "toggle-tilt");
  await settle(page);
}

/** A transition whose identity phase is half transparent: the view rests at that opacity, not at the content's own. */
async function restingLook(page, label) {
  const opacity = await page.evaluate(() => Number(getComputedStyle(window.__byId("resting")).opacity));
  assert.ok(Math.abs(opacity - 0.5) < 0.02, `${label}: a view rests in the identity phase of its transition (${opacity})`);
}

/** A geometry effect on content sized by itself gets the size the page measured: here it moves its content by its own width. */
async function measuredEffectSize(page, label) {
  await page.waitForFunction(() => {
    const element = window.__byId("measured-shift");
    return element && Math.abs(new DOMMatrix(getComputedStyle(element).transform).m41 - element.offsetWidth) < 1 && element.offsetWidth > 20;
  }, null, { timeout: 4000 });
}

async function swiftAnimations(page, label) {
  const sample = async (id, read) => page.evaluate(({ id, read }) => {
    const element = window.__byId(id);
    return read === "text" ? element.textContent : read === "path" ? element.querySelector("[data-shape-path]")?.getAttribute("data-shape-path") ?? element.getAttribute("data-shape-path") : read === "opacity" ? getComputedStyle(element).opacity : getComputedStyle(element).transform;
  }, { id, read });
  // Each one is sampled a little after its own click: a click waits for its target, so their times are not added up.
  const halfWay = async (id) => { await page.click(`[data-testid="${id}"]`); await page.waitForTimeout(400); };
  await halfWay("fill");
  const level = Number((await sample("meter", "text")).replace(/\D/g, ""));
  assert.ok(level > 10 && level < 90, `${label}: the animatable view shows a level on the way (${level})`);
  await halfWay("shake");
  const shaken = { m41: translationX(await sample("shaken", "transform")) };
  assert.ok(shaken.m41 > 4 && shaken.m41 < 36, `${label}: the geometry effect moves part of the way (${shaken.m41})`);
  const dimming = Number(await sample("shaken", "opacity"));
  assert.ok(dimming > 0.3 && dimming < 0.95, `${label}: an independent opacity on the same view eases with the transaction (${dimming})`);
  await halfWay("grow");
  const width = Number(/L ([\d.]+) 0/.exec(await sample("bar", "path"))?.[1]);
  assert.ok(width > 10 && width < 90, `${label}: the shape draws a path on the way (${width})`);
  await page.waitForFunction(() => window.__byId("meter").textContent === "level 100", null, { timeout: 3000 });
  assert.equal(await page.evaluate(() => window.__byId("meter").closest('[data-timeline-view="animation"]')), null, `${label}: the timeline goes once the animation ends`);
  await page.waitForFunction(() => !window.__byId("shaken").closest('[data-timeline-view="animation"]'), null, { timeout: 3000 });
  assert.ok(Math.abs(translationX(await sample("shaken", "transform")) - 40) < 0.5, `${label}: the geometry effect ends at its value`);

  await click(page, "step");
  const easings = await page.evaluate(() => window.__byId("stepped").getAnimations().map((animation) => animation.effect.getTiming().easing));
  assert.ok(easings.some((easing) => easing.startsWith("linear(")), `${label}: a custom animation plays as a sampled easing (${easings})`);
  // The marker is written for the commit only, and may already be there when its value does not change: it counts when it is
  // written or found, not only when it happens to be read at the end.
  await page.evaluate(() => {
    window.__sawNone = false;
    const check = () => { if (window.__byId("quiet-text")?.closest("[data-transaction-timing]")?.getAttribute("data-transaction-timing") === "none") window.__sawNone = true; };
    new MutationObserver(check).observe(document.body, { attributes: true, attributeFilter: ["data-transaction-timing"], subtree: true, childList: true });
    window.__checkQuiet = check;
  });
  await click(page, "quiet");
  await page.evaluate(() => window.__checkQuiet());
  assert.equal(await page.evaluate(() => window.__byId("quiet-text").getAnimations().length), 0, `${label}: a transaction without animation makes its view jump`);
  await page.waitForFunction(() => window.__sawNone, null, { timeout: 3000 }).catch(() => {});
  assert.ok(await page.evaluate(() => window.__sawNone), `${label}: and marks its subtree`);

  await click(page, "present");
  await page.waitForSelector('[data-testid="dismiss"]');
  await page.waitForTimeout(400);
  await click(page, "dismiss");
  const exiting = await page.evaluate(() => {
    const surface = document.querySelector('[data-exit-animation="true"]');
    return surface && { inert: !!surface.closest("[data-transition-leaving]")?.inert, animations: surface.getAnimations().length };
  });
  assert.ok(exiting, `${label}: the dismissed sheet plays its exit`);
  assert.ok(exiting.inert && exiting.animations > 0, `${label}: out of reach while it leaves`);
  await page.waitForFunction(() => !document.querySelector('[data-exit-animation="true"]') && !document.querySelector('[data-testid="sheet-text"]'), null, { timeout: 2000 });
}

/** Presentations and pushes move as UIKit moves them (styles.css, transition-host.js): a form sheet rises from below the
 * screen with the page dimming behind it, an alert settles from 1.15 times its size, a push slides the new screen in over
 * the one it covers, which moves a third of the way out behind it, and a pop plays that backwards. */
async function uikitPresentationMotion(page, label) {
  const curve = "cubic-bezier(0.32, 0.72, 0, 1)";
  const waitUntil = async (check, what) => {
    for (let waited = 0; waited < 3000; waited += 40) {
      if (await page.evaluate(check)) return;
      await page.waitForTimeout(40);
    }
    assert.fail(`${label}: ${what}`);
  };

  await click(page, "present");
  const sheet = await page.evaluate(() => {
    const panel = window.__byId("sheet-text")?.closest(".sheet-panel");
    const animation = panel?.getAnimations().find((each) => each.animationName === "swu-sheet-in");
    if (!animation) return { names: panel?.getAnimations().map((each) => each.animationName) };
    animation.pause(); animation.currentTime = 0;
    const start = { y: new DOMMatrix(getComputedStyle(panel).transform).m42, shadow: getComputedStyle(panel).boxShadow };
    animation.play();
    return { start, viewport: innerHeight, duration: animation.effect.getTiming().duration, easing: animation.effect.getKeyframes()[0].easing };
  });
  assert.ok(sheet.start, `${label}: a presented sheet rises (${JSON.stringify(sheet)})`);
  assert.equal(sheet.duration, 500, `${label}: for half a second, as UIKit presents`);
  assert.equal(sheet.easing, curve, `${label}: along UIKit's presentation curve`);
  near(sheet.start.y, sheet.viewport, 1, `${label}: a form sheet starts below the screen`);
  assert.ok(!/rgba\(0, 0, 0, 0\.45\)/.test(sheet.start.shadow), `${label}: and the page dims as it comes (${sheet.start.shadow})`);
  await settle(page);
  await click(page, "dismiss");
  const leaving = await page.evaluate(() => document.querySelector('.sheet-panel[data-exit-animation="true"]')?.getAnimations().map((each) => each.animationName));
  assert.deepEqual(leaving, ["swu-sheet-out"], `${label}: a dismissed sheet goes back down`);
  await settle(page);
  await waitUntil(() => !window.__byId("sheet-text"), "the dismissed sheet leaves");

  const rootBefore = await page.evaluate(() => {
    const root = window.__byId("nav-root-text").closest(".navigation-root");
    return [root.offsetLeft, root.offsetTop, root.offsetWidth];
  });
  await click(page, "push");
  const push = await page.evaluate(() => {
    const pushed = window.__byId("pushed-text")?.closest(".navigation-destination");
    const root = window.__byId("nav-root-text")?.closest(".navigation-root");
    const named = (element, name) => element?.getAnimations().find((each) => each.animationName === name);
    const slide = named(pushed, "swu-navigation-push"), cover = named(root, "swu-navigation-cover");
    const found = { motion: root?.getAttribute("data-navigation-motion"), display: root && getComputedStyle(root).display, pushed: pushed?.getAnimations().map((each) => each.animationName) };
    if (!slide || !cover) return found;
    for (const animation of [slide, cover]) { animation.pause(); animation.currentTime = 250; }
    const layout = (element) => [element.offsetLeft, element.offsetTop, element.offsetWidth];
    Object.assign(found, {
      width: pushed.offsetWidth, slid: new DOMMatrix(getComputedStyle(pushed).transform).m41, covered: new DOMMatrix(getComputedStyle(root).transform).m41,
      pushedBox: layout(pushed), rootBox: layout(root), duration: slide.effect.getTiming().duration, easing: slide.effect.getKeyframes()[0].easing,
    });
    for (const animation of [slide, cover]) animation.play();
    return found;
  });
  assert.equal(push.motion, "covered", `${label}: the screen a push covers stays in view under it (${JSON.stringify(push)})`);
  assert.notEqual(push.display, "none", `${label}: shown while the push plays`);
  assert.ok(push.width > 0, `${label}: the pushed screen slides in (${JSON.stringify(push)})`);
  assert.equal(push.duration, 500, `${label}: a push lasts half a second`);
  assert.equal(push.easing, curve, `${label}: along UIKit's curve`);
  assert.deepEqual(push.rootBox, rootBefore, `${label}: the covered screen stays where it was`);
  assert.ok(push.slid > 0 && push.slid < push.width, `${label}: half way through, the new screen is on its way in (${push.slid} of ${push.width})`);
  near(push.covered, -0.3 * (push.width - push.slid), 1, `${label}: and the covered one has moved a third as far, the other way`);
  await settle(page);
  await waitUntil(() => {
    const root = window.__byId("nav-root-text")?.closest(".navigation-root");
    return root && !root.hasAttribute("data-navigation-motion") && getComputedStyle(root).display === "none";
  }, "the covered screen is hidden once the push has played");

  await click(page, "pop");
  const pop = await page.evaluate(() => {
    const leaving = document.querySelector('.navigation-destination[data-exit-animation="true"]');
    const root = window.__byId("nav-root-text")?.closest(".navigation-root");
    return { leaving: leaving?.getAnimations().map((each) => each.animationName), motion: root?.getAttribute("data-navigation-motion"), revealed: root?.getAnimations().map((each) => each.animationName) };
  });
  assert.deepEqual(pop.leaving, ["swu-navigation-pop"], `${label}: a popped screen slides back out (${JSON.stringify(pop)})`);
  assert.equal(pop.motion, "revealed", `${label}: uncovering the screen under it`);
  assert.deepEqual(pop.revealed, ["swu-navigation-reveal"], `${label}: which comes back from a third of the way out`);
  await settle(page);
  await waitUntil(() => !window.__byId("pushed-text") && !window.__byId("nav-root-text")?.closest(".navigation-root")?.hasAttribute("data-navigation-motion"), "the pop ends");

  await click(page, "alert");
  const alert = await page.evaluate(() => {
    const panel = document.querySelector(".alert-panel");
    const animation = panel?.getAnimations().find((each) => each.animationName === "swu-alert-in");
    if (!animation) return { names: panel?.getAnimations().map((each) => each.animationName) };
    animation.pause(); animation.currentTime = 0;
    const style = getComputedStyle(panel);
    const start = { opacity: Number(style.opacity), scale: new DOMMatrix(style.transform).a };
    animation.play();
    return { start, duration: animation.effect.getTiming().duration };
  });
  assert.ok(alert.start, `${label}: an alert animates in (${JSON.stringify(alert)})`);
  assert.equal(alert.duration, 400, `${label}: for 0.4 s`);
  near(alert.start.scale, 1.15, 0.001, `${label}: from 1.15 times its size`);
  near(alert.start.opacity, 0, 0.001, `${label}: fading in`);
  await settle(page);
  await click(page, "alert-ok");
  const fading = await page.evaluate(() => document.querySelector('.alert-panel[data-exit-animation="true"]')?.getAnimations().map((each) => each.animationName));
  assert.deepEqual(fading, ["swu-fade-out"], `${label}: a dismissed alert fades out`);
  await settle(page);
  await waitUntil(() => !document.querySelector(".alert-panel"), "the dismissed alert leaves");
}

/** Pushes and pops that overlap: a push made while the previous one still slides in covers that screen, not the one under
 * it, and a pop made while a push still plays reveals the covered screen instead of snapping it into place (the end of the
 * cover animation it cancels clears nothing). Driven on the host and the stylesheet directly. */
async function overlappingNavigationMotion(appPage, label, hostSource) {
  const page = await appPage.context().newPage();
  const styles = await fs.promises.readFile(new URL("./styles.css", import.meta.url), "utf8");
  await page.setContent("<!doctype html><html data-embedded-mounted='true'><head><style></style></head><body style='margin:0'></body></html>");
  await page.evaluate((css) => { document.querySelector("style").textContent = css; }, styles);
  const result = await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { TransitionHost } = await import(url);
    URL.revokeObjectURL(url);
    const host = new TransitionHost({
      window, root: document.body, reducedMotion: { matches: false }, armedTiming: () => null,
      motionTiming: () => null, supportedTransition: (easing) => easing,
    });
    const frames = (count) => new Promise((resolve) => { const step = (left) => (left ? requestAnimationFrame(() => step(left - 1)) : resolve()); step(count); });
    const screen = (className, text) => { const element = document.createElement("div"); element.className = className; element.textContent = text; return element; };
    const stage = () => {
      document.body.replaceChildren();
      const stack = document.createElement("main");
      stack.className = "navigation-stack";
      stack.style.cssText = "width:300px;height:200px;position:relative;";
      const root = screen("navigation-root", "Root");
      stack.append(root);
      document.body.append(stack);
      return { stack, root };
    };
    const push = (stack, below) => {
      host.begin(null);
      if (below.classList.contains("navigation-root")) below.setAttribute("aria-hidden", "true");
      else below.setAttribute("data-navigation-inactive", "true");
      const next = screen("navigation-destination", "Pushed");
      stack.append(next);
      host.noteInsertion(next, stack);
      host.finish();
      return next;
    };
    const motion = (element) => ({ state: element.getAttribute("data-navigation-motion"), animations: element.getAnimations().map((animation) => animation.animationName), shift: element.style.getPropertyValue("--motion-shift") });

    let { stack, root } = stage();
    const button = document.createElement("button");
    button.textContent = "Root action";
    root.append(button);
    button.focus();
    const first = push(stack, root);
    const covering = { inert: root.inert, focused: document.activeElement === button };
    await frames(2);
    const second = push(stack, first);
    await frames(3);
    const overlapping = { first: motion(first), root: motion(root), second: motion(second) };
    for (const animation of document.getAnimations()) animation.finish();
    await frames(3);
    const uncovered = { inert: root.inert };

    ({ stack, root } = stage());
    const pushed = push(stack, root);
    await frames(2);
    host.begin(null);
    root.removeAttribute("aria-hidden");
    host.holdRemoval(pushed, stack);
    host.finish();
    await frames(3);
    const popped = { root: motion(root), leaving: pushed.getAnimations().map((animation) => animation.animationName) };
    for (const animation of document.getAnimations()) animation.cancel();

    // A path whose top is replaced in one commit (root, A to root, B): B arrives as a push, and nothing keeps a mark once
    // the motion has played.
    ({ stack, root } = stage());
    const replaced = push(stack, root);
    await frames(2);
    for (const animation of document.getAnimations()) animation.finish();
    await frames(3);
    host.begin(null);
    const replacement = screen("navigation-destination", "Replacement");
    stack.append(replacement);
    host.noteInsertion(replacement, stack);
    host.holdRemoval(replaced, stack);
    host.finish();
    await frames(2);
    const replacing = motion(replacement);
    for (const animation of document.getAnimations()) animation.finish();
    await frames(3);
    const settled = { marks: document.querySelectorAll("[data-navigation-motion]").length, clipped: getComputedStyle(stack).overflow };
    return { overlapping, popped, replacing, settled, covering, uncovered };
  }, hostSource);
  await page.close();
  assert.deepEqual(result.covering, { inert: true, focused: false }, `${label}: the covered screen is out of the keyboard's reach while it shows`);
  assert.equal(result.uncovered.inert, false, `${label}: and gets its own inert state back after`);
  assert.equal(result.overlapping.first.state, "covered", `${label}: a push over a screen still sliding in covers that screen (${JSON.stringify(result.overlapping)})`);
  assert.deepEqual(result.overlapping.first.animations, ["swu-navigation-cover"], `${label}: which moves out under the new one`);
  assert.deepEqual(result.overlapping.second.animations, ["swu-navigation-push"], `${label}: while the new one slides in`);
  assert.equal(result.popped.root.state, "revealed", `${label}: a pop during a push reveals the covered screen (${JSON.stringify(result.popped)})`);
  assert.deepEqual(result.popped.root.animations, ["swu-navigation-reveal"], `${label}: which comes back along its own animation`);
  assert.notEqual(result.popped.root.shift, "", `${label}: keeping the distance it comes back from`);
  assert.deepEqual(result.popped.leaving, ["swu-navigation-pop"], `${label}: while the popped screen slides out`);
  assert.equal(result.replacing.state, null, `${label}: a destination replacing the top one is not revealed (${JSON.stringify(result.replacing)})`);
  assert.deepEqual(result.replacing.animations, ["swu-navigation-push"], `${label}: it is pushed`);
  assert.equal(result.settled.marks, 0, `${label}: no screen keeps a motion mark once it has played (${JSON.stringify(result.settled)})`);
  assert.notEqual(result.settled.clipped, "clip", `${label}: and the stack is no longer clipped`);
}

async function reducedMotion(browser, server, label) {
  const { page, problems } = await openFixture(browser, server, { reducedMotion: "reduce" });
  await click(page, "add");
  // Scroll transitions still follow the scroll position: they move only as the person scrolls. A matched geometry holds
  // its view at the source's frame with an animation of no duration.
  const playing = await page.evaluate(() => document.getAnimations().filter((animation) => animation.id !== "scroll-transition" && !(animation.id === "matched-geometry" && animation.effect.getTiming().duration === 0)).map((animation) => [animation.id, animation.effect.target?.getAttribute("data-testid") ?? animation.effect.target?.localName, animation.effect.pseudoElement, animation.effect.getTiming().duration, animation.constructor.name]));
  assert.deepEqual(playing, [], `${label}: nothing plays with reduced motion`);
  await click(page, "remove");
  assert.equal(await page.evaluate(() => document.querySelectorAll("[data-transition-leaving]").length), 0, `${label}: a removal is immediate with reduced motion`);
  assert.deepEqual(problems, [], `${label}: no page errors with reduced motion`);
  await page.context().close();
}

async function main() {
  const label = engineName();
  const server = await serveBundle({ bundle: BUNDLE, port: await freePort(), logName: null, required: ["index.html"] });
  const browser = await launch();
  try {
    const { page, problems } = await openFixture(browser, server);
    // First: the steps below settle the page by cancelling what is animating, a repeating phase animator included.
    await phaseAnimationsLeadIntoTheirPhase(page, label);
    await insertionAndSiblings(page, label);
    await removal(page, label);
    await everyKind(page, label);
    await defaultFadeAndSnap(page, label);
    await numericText(page, label);
    await spring(page, label);
    await customAndAttached(page, label);
    await uikitPresentationMotion(page, label);
    await overlappingNavigationMotion(page, label, await fs.promises.readFile(new URL("./transition-host.js", import.meta.url), "utf8"));
    await asymmetricTimings(page, label);
    await nestedAnimations(page, label);
    await valueAnimationInsideWithAnimation(page, label);
    await plainCommitEndsARunningAnimation(page, label);
    await symbolEffects(page, label);
    await disabledShapeTransaction(page, label);
    await scrollTransitions(page, label);
    await completion(page, label);
    await measuredEffectSize(page, label);
    await restingLook(page, label);
    await restingTransform(page, label);
    await swiftAnimations(page, label);
    await textRenderer(page, label);
    await edgeScrollTransitions(page, label);
    await snapTargetScrollTransition(page, label);
    await symbolReplace(page, label);
    await matchedGeometry(page, label);
    await matchedGeometryScroll(page, label);
    await matchedGeometryScaled(page, label);
    const hostSource = await fs.promises.readFile(new URL("./transition-host.js", import.meta.url), "utf8");
    await removalWithOwnTiming(page, label, hostSource);
    await removalUnderTransform(page, label, hostSource, "a 2x ancestor", "scale(2)");
    await removalUnderTransform(page, label, hostSource, "a rotated ancestor", "rotate(90deg)");
    await siblingMovesUnderScale(page, label, hostSource);
    await siblingMovesUnderRotation(page, label, hostSource);
    await removalOfTransformedView(page, label, hostSource);
    await matchedGeometryOwnScale(page, label, hostSource);
    await matchedGeometryStartsWhereItShowed(page, label, hostSource);
    await scrollLayoutRectUnderScale(page, label, hostSource);
    await flashAlongTheScrollingAxis(page, label, hostSource);
    await scaleTransitionKeepsTheViewsOwnOrigin(page, label, hostSource);
    await scrollLayoutRectUnderRotation(page, label, hostSource);
    await transitionRepeats(page, label, hostSource);
    await colorMultipliers(page, label);
    await basisWithATranslation(page, label, hostSource);
    await symbolReplaceOptions(page, label, hostSource);
    await symbolTransitionOptions(page, label, hostSource);
    await gradientUnderScale(page, label);
    await effectSizeUnderScale(page, label);
    await centeredScrollPhase(page, label, hostSource);
    await numericWidthsUnderScale(page, label, hostSource);
    await transactionRepeats(page, label, hostSource);
    await nearestTransactionWins(page, label, hostSource);
    await loneEllipsis(page, label);
    await leavingCopiesUnderTransform(page, label, hostSource);
    await payloadUnderScale(page, label);
    await wrappingCrossFade(page, label, hostSource);
    await readersUnderScale(page, label);
    await textLayoutPreference(page, label);
    await styledRenderer(page, label);
    await textProxy(page, label);
    assert.deepEqual(problems, [], `${label}: no page errors`);
    await page.context().close();
    await reducedMotion(browser, server, label);
    console.log(`PASS ${label}: transitions in and out, the default fade, sliding siblings, numeric text, springs, custom transitions, Swift-driven animations, presentation exits, UIKit presentation and push motion, text renderers, per-edge scroll transitions, symbol replacement, matched geometry and text layout preferences`);
  } finally {
    await browser.close();
    await server.stop();
  }
}

await runSuite(main);
