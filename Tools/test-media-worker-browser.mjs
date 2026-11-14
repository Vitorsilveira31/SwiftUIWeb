#!/usr/bin/env bun
// AVPlayer reads are synchronous and right in the Worker, as on the main thread.
//
// Swift runs in a Worker by default and cannot touch the page's <audio>/<video>. The host sends the element's state as deltas
// and Swift keeps a mirror that extrapolates the time with the playback rate, so `currentTime()`, `rate`, `timeControlStatus`
// and the observers behave as AVFoundation's. The fixture is Tests/Apps/MediaProbeApp over media this script generates (a silent WAV,
// and a silent WebM/MP4 when ffmpeg is there); every result is one line of its `log` text, so the test sees what the app's Swift code
// read. Each scenario runs with the Worker and with the main thread (`?render-in-worker=0`) on Chromium and WebKit (MEDIA_WORKER_ENGINES),
// and both must meet the same bounds.
//
// Covered: MainActor.assumeIsolated inside the actions and each AV callback; a player with no VideoPlayer (audio and video) and the
// view mounting and unmounting mid-playback; a refused play; play (reads advance continuously, never run backwards, stay within tolerance of the element), pause, seek with its
// completion, an interrupted seek finishing false, rate, volume and mute, the 0.5 s periodic observer, the 50 ms one (and the
// sample stream it asks for), boundary observers, the end, a load error, a video, and the move from the Worker to the main thread
// in the middle of playback.
// Bundle: MEDIA_WORKER_BUNDLE (.build/browser/MediaProbeApp). Port: MEDIA_WORKER_PORT.
import { spawnSync } from "node:child_process";
import { cpSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { launch, ROOT, runSuite, serveBundle } from "./browser-test-support.mjs";

const BUNDLE = resolve(process.env.MEDIA_WORKER_BUNDLE ?? join(ROOT, ".build/browser/MediaProbeApp"));
const PORT = Number(process.env.MEDIA_WORKER_PORT ?? "8131");
const ENGINES = (process.env.MEDIA_WORKER_ENGINES ?? "chromium,webkit").split(",").filter(Boolean);
// Long enough for the scenarios' wall-clock steps (100 reads, two 80-sample bursts, the mounts) to end before the clip does: a
// clip that ends mid-scenario made the unmount check read the end of the media, not a continued playback.
const DURATION = 15.0;
// What a read may differ from the element by: the host drops samples it predicts within 50 ms, the sample is aged by the thread
// delay, and the browsers quantise `currentTime` (WebKit by about 20 ms).
const TOLERANCE_MS = 130;
const failures = [];

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const mean = (values) => values.reduce((sum, value) => sum + value, 0) / values.length;

function check(condition, message) {
  if (!condition) {
    failures.push(message);
    console.log(`  FAIL ${message}`);
  }
  return Boolean(condition);
}

/** A silent 8 kHz mono 16-bit WAV of DURATION seconds. */
function wavBytes(seconds) {
  const samples = 8000 * seconds;
  const data = samples * 2;
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + data, 4);
  header.write("WAVE", 8);
  header.write("fmt ", 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(8000, 24);
  header.writeUInt32LE(16000, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write("data", 36);
  header.writeUInt32LE(data, 40);
  return Buffer.concat([header, Buffer.alloc(data)]);
}

function makeMedia(directory) {
  writeFileSync(join(directory, "probe.wav"), wavBytes(Math.trunc(DURATION)));
  const videos = {};
  if (spawnSync("which", ["ffmpeg"]).status === 0) {
    const common = ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=black:s=64x64:r=10", "-t", String(DURATION), "-an", "-y"];
    for (const [name, args] of [
      ["webm", ["-c:v", "libvpx", "-b:v", "50k"]],
      ["mp4", ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart"]],
    ]) {
      if (spawnSync("ffmpeg", [...common, ...args, join(directory, `probe.${name}`)], { stdio: "inherit" }).status === 0) videos[name] = true;
    }
  }
  return videos;
}

class Probe {
  constructor(page) {
    this.page = page;
  }

  async click(name) {
    // A DOM `click`, not a pointer click: WebKit can hit-test a scroller that was just scrolled with its old
    // offset, so a pointer click Playwright aims at a button it scrolled into view may land beside it
    // Playwright's engines allow media playback without a gesture.
    await this.page.locator(`[data-testid="${name}"]`).dispatchEvent("click");
  }

  async lines() {
    const text = (await this.page.locator('[data-testid="log"]').textContent()) || "";
    return text.split("\n").filter(Boolean);
  }

  async waitLine(prefix, { count = 1, timeout = 15000, after = 0 } = {}) {
    const deadline = Date.now() + timeout;
    while (Date.now() < deadline) {
      const found = (await this.lines()).slice(after).filter((line) => line.startsWith(prefix));
      if (found.length >= count) return found;
      await this.page.waitForTimeout(25);
    }
    throw new Error(`no ${count} x '${prefix}' in ${JSON.stringify((await this.lines()).slice(after).slice(-8))}`);
  }

  /** One read by the app's Swift code: (wall ms, time ms, rate, status, item status, time control, duration ms, volume, muted). */
  async read() {
    const before = (await this.lines()).length;
    await this.click("read");
    const line = (await this.waitLine("R|", { after: before }))[0].split("|");
    const int = (index) => Number.parseInt(line[index], 10);
    return { wall: int(1), t: int(2), rate: int(3) / 1000, status: int(4), item: int(5), tcs: int(6), duration: int(7), volume: int(8) / 1000, muted: line[9] === "1" };
  }

  async element(expression = "a.currentTime") {
    return this.page.evaluate(`(() => { const a = document.querySelector('audio,video'); return ${expression}; })()`);
  }

  async mark() {
    return (await this.lines()).length;
  }
}

async function openPage(browser, base, worker, diagnostics = false) {
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(String(e)));
  page.on("console", (m) => {
    if (m.type() === "error" && !m.text().includes("Failed to load resource")) errors.push(m.text());
  });
  if (diagnostics) await page.addInitScript("window.__performanceDiagnostics = true");
  await page.goto(`${base}/?render-in-worker=${worker ? 1 : 0}`, { waitUntil: "domcontentloaded" });
  await page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30000 });
  if ((await page.evaluate("window.__embeddedSession.worker")) !== Boolean(worker)) throw new Error("wrong mode");
  await page.waitForSelector("audio[data-player-id]", { state: "attached", timeout: 15000 });
  const probe = new Probe(page);
  // Metadata loaded: Swift knows the duration.
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) {
    const reads = await probe.read();
    if (reads.item === 1 && reads.duration > 0) break;
    await page.waitForTimeout(100);
  }
  return { page, probe, errors };
}

/** The app reads every 20 ms for 2 s while the page samples the element every 4 ms; returns (errors in ms, reads). */
async function sampleBurst(page, probe) {
  await page.evaluate(`() => { window.__samples = []; const grab = () => { const a = document.querySelector('audio,video'); window.__samples.push([Date.now(), a.currentTime * 1000]); };
      window.__sampler = setInterval(grab, 4); }`.replace(/^/, "(") + ")()");
  const mark = await probe.mark();
  await probe.click("burst");
  await probe.waitLine("burst-done", { after: mark, timeout: 20000 });
  await page.evaluate("clearInterval(window.__sampler)");
  const samples = await page.evaluate("window.__samples");
  const reads = (await probe.lines()).slice(mark).filter((line) => line.startsWith("R|")).map((line) => line.split("|"));
  const pairs = reads.map((r) => [Number.parseInt(r[1], 10), Number.parseInt(r[2], 10), Number.parseInt(r[3], 10) / 1000, Number.parseInt(r[6], 10)]);
  const errors = [];
  for (const [wall, t] of pairs) {
    const below = samples.filter((s) => s[0] <= wall);
    const above = samples.filter((s) => s[0] >= wall);
    if (below.length === 0 || above.length === 0) continue;
    const a = below[below.length - 1];
    const b = above[0];
    const expected = b[0] === a[0] ? a[1] : a[1] + ((b[1] - a[1]) * (wall - a[0])) / (b[0] - a[0]);
    errors.push(t - expected);
  }
  return { errors, pairs };
}

const pairwise = (values) => values.slice(1).map((value, index) => [values[index], value]);
const maxAbs = (values, fallback) => (values.length ? Math.max(...values.map(Math.abs)) : fallback);

async function playableVideo(page, videos) {
  for (const name of ["webm", "mp4"]) {
    if (videos[name] && (await page.evaluate(`document.createElement('video').canPlayType('video/${name}') !== ''`))) return name;
  }
  return null;
}

async function scenario(browser, base, worker, videos, results) {
  const mode = worker ? "worker" : "main";
  const engine = browser.browserType().name();
  const tag = `[${engine}/${mode}]`;
  console.log(`${tag} scenario`);
  const { page, probe, errors } = await openPage(browser, base, worker);
  const initial = await probe.read();
  check(initial.status === 1 && initial.item === 1, `${tag} AVPlayer and its item are readyToPlay once the metadata is in: ${JSON.stringify(initial)}`);
  check(Math.abs(initial.duration - DURATION * 1000) < 100, `${tag} the duration is ${DURATION}s: ${initial.duration}`);
  check(initial.t === 0 && initial.rate === 0 && initial.tcs === 0, `${tag} idle: time 0, rate 0, paused: ${JSON.stringify(initial)}`);

  // --- play: reads advance continuously and stay accurate between the host's samples.
  await probe.click("play");
  let deadline = Date.now() + 10000;
  while (Date.now() < deadline && (await probe.read()).tcs !== 2) await page.waitForTimeout(50);
  const playing = await probe.read();
  if (!check(playing.tcs === 2 && playing.rate === 1, `${tag} playing: time control playing, rate 1: ${JSON.stringify(playing)}`)) {
    await page.close();
    return;
  }
  let { errors: errs, pairs } = await sampleBurst(page, probe);
  let times = pairs.map((p) => p[1]);
  const distinct = new Set(times).size;
  const gaps = pairwise(times).map(([a, b]) => b - a).filter((gap) => gap !== 0);
  check(pairwise(times).every(([a, b]) => b >= a), `${tag} reads never run backwards: ${JSON.stringify(pairwise(times).filter(([a, b]) => b < a).slice(0, 3))}`);
  check(distinct >= 80, `${tag} reads advance continuously, not in host-sized steps (${distinct} distinct of ${times.length})`);
  check(gaps.length === 0 || Math.max(...gaps) <= 120, `${tag} no step bigger than 120 ms between reads: ${gaps.length ? Math.max(...gaps) : null}`);
  if (process.env.MEDIA_DEBUG) console.log(errs.map(Math.round));
  let worst = maxAbs(errs, 0);
  check(errs.length > 0 && worst <= TOLERANCE_MS, `${tag} reads within ${TOLERANCE_MS} ms of the element: worst ${worst.toFixed(0)} ms over ${errs.length}`);
  results.set(`${engine}|${mode}|play-error-ms`, [worst, errs.length ? mean(errs.map(Math.abs)) : null]);
  check(pairs.every((p) => p[2] === 1.0 && p[3] === 2), `${tag} rate 1 and time control playing throughout`);

  // --- pause: rate 0, the time stands still and matches the element.
  await probe.click("pause");
  await page.waitForFunction("document.querySelector('audio,video').paused === true");
  const first = await probe.read();
  await page.waitForTimeout(400);
  const second = await probe.read();
  check(first.tcs === 0 && first.rate === 0, `${tag} paused: time control paused, rate 0: ${JSON.stringify(first)}`);
  check(first.t === second.t, `${tag} a paused player's time stands still: ${first.t} vs ${second.t}`);
  check(Math.abs(first.t - (await probe.element()) * 1000) <= 60, `${tag} the paused time matches the element: ${first.t} vs ${(await probe.element()) * 1000}`);

  // --- seek: the completion hears the landing time; reads follow.
  let mark = await probe.mark();
  await probe.click("seek2");
  let done = (await probe.waitLine("S|two|", { after: mark }))[0].split("|");
  check(done[2] === "1" && Math.abs(Number.parseInt(done[3], 10) - 2000) <= 60, `${tag} seek completion: finished with the target time: ${JSON.stringify(done)}`);
  check(Math.abs((await probe.read()).t - 2000) <= 60, `${tag} a read after the seek is the target`);

  // --- an interrupted seek finishes false at once, the newer one true.
  mark = await probe.mark();
  await probe.click("race");
  let got = await probe.waitLine("S|", { count: 2, after: mark });
  check(JSON.stringify(got.map((g) => g.split("|").slice(1, 3))) === JSON.stringify([["A", "0"], ["B", "1"]]), `${tag} interrupted seek finishes false, the last true: ${JSON.stringify(got)}`);
  check(Math.abs(Number.parseInt(got[1].split("|")[3], 10) - 1000) <= 60, `${tag} the race ends at B's target: ${got[1]}`);

  // --- rate: twice the speed moves twice as fast.
  await probe.click("rate2");
  await page.waitForFunction("document.querySelector('audio,video').playbackRate === 2");
  await probe.read();
  const e0 = await probe.element("[Date.now(), a.currentTime * 1000]");
  const a = await probe.read();
  await page.waitForTimeout(1000);
  const b = await probe.read();
  const e1 = await probe.element("[Date.now(), a.currentTime * 1000]");
  check(b.rate === 2, `${tag} AVPlayer.rate reads 2: ${JSON.stringify(b)}`);
  const slope = (b.t - a.t) / Math.max(1, b.wall - a.wall);
  // The browser may start late or stall (WebKit's audio does), so the reference is the element's own progress.
  const elementSlope = (e1[1] - e0[1]) / Math.max(1, e1[0] - e0[0]);
  check(Math.abs(slope - elementSlope) <= 0.3 && slope > 0.5, `${tag} time advances as the element does at rate 2 (Swift ${slope.toFixed(2)}, element ${elementSlope.toFixed(2)})`);
  await probe.click("rate1");
  await page.waitForFunction("document.querySelector('audio,video').playbackRate === 1");
  await probe.click("pause");
  await page.waitForFunction("document.querySelector('audio,video').paused === true");

  // --- volume and mute.
  await probe.click("unmute");
  await page.waitForFunction("document.querySelector('audio,video').muted === false");
  let r = await probe.read();
  check(!r.muted, `${tag} isMuted reads false after unmute`);
  await probe.click("volume");
  await page.waitForFunction("Math.abs(document.querySelector('audio,video').volume - 0.5) < 0.01");
  r = await probe.read();
  check(Math.abs(r.volume - 0.5) < 0.01, `${tag} volume reads 0.5`);
  await probe.click("mute");
  await page.waitForFunction("document.querySelector('audio,video').muted === true");
  check((await probe.read()).muted, `${tag} isMuted reads true after mute`);

  // --- periodic observer: every 0.5 s of media time, plus the start.
  mark = await probe.mark();
  await probe.click("seekStart");
  await probe.waitLine("S|start|", { after: mark });
  mark = await probe.mark();
  await probe.click("periodic");
  await probe.click("play");
  await probe.waitLine("P|", { count: 7, after: mark, timeout: 12000 });
  const ps = (await probe.lines()).slice(mark).filter((l) => l.startsWith("P|")).map((l) => l.split("|"));
  const ts = ps.map((p) => Number.parseInt(p[2], 10));
  const walls = ps.map((p) => Number.parseInt(p[1], 10));
  check(ps.length >= 7, `${tag} the 0.5 s observer keeps firing while it plays: ${JSON.stringify(ts)}`);
  const steady = pairwise(ts).map(([x, y]) => y - x).filter((s) => s > 100);
  check(steady.length > 0 && steady.every((s) => Math.abs(s - 500) <= 60), `${tag} periodic observer cadence is 500 ms of media time: ${JSON.stringify(steady)}`);
  const wallSteps = pairwise(walls).map(([x, y]) => y - x).filter((s) => s > 100);
  check(wallSteps.filter((s) => Math.abs(s - 500) <= 120).length >= wallSteps.length - 2, `${tag} ... and mostly 500 ms of wall time at rate 1 (an element may stall): ${JSON.stringify(wallSteps)}`);
  results.set(`${engine}|${mode}|periodic-media-step`, steady.length ? mean(steady) : null);
  await probe.click("unobserve");
  await probe.click("pause");
  await page.waitForFunction("document.querySelector('audio,video').paused === true");

  // --- boundary observers: when playback passes 1.2 s and 2.5 s, once each.
  mark = await probe.mark();
  await probe.click("seekStart");
  await probe.waitLine("S|start|", { after: mark });
  mark = await probe.mark();
  await probe.click("boundary");
  await probe.click("play");
  await probe.waitLine("B|", { count: 2, after: mark, timeout: 8000 });
  await page.waitForTimeout(600);
  const bs = (await probe.lines()).slice(mark).filter((l) => l.startsWith("B|")).map((l) => l.split("|"));
  check(bs.length === 2, `${tag} two boundaries, once each: ${JSON.stringify(bs)}`);
  if (bs.length >= 2) {
    check(Math.abs(Number.parseInt(bs[0][2], 10) - 1200) <= 90 && Math.abs(Number.parseInt(bs[1][2], 10) - 2500) <= 90, `${tag} boundaries fire at 1.2 s and 2.5 s: ${JSON.stringify(bs.map((x) => x[2]))}`);
  }
  await probe.click("unobserve");

  // --- the 50 ms observer asks the host for a stream of samples.
  await probe.click("fast");
  await page.waitForFunction("document.querySelector('audio,video').hasAttribute('data-media-observe')", undefined, { timeout: 5000 });
  const fastCount = async () => Number.parseInt(((await page.locator('[data-testid="fast-count"]').textContent()) || "fast 0").split(/\s+/)[1], 10);
  const before = await fastCount();
  await page.waitForTimeout(1000);
  const after = await fastCount();
  check(after - before >= 10, `${tag} the 50 ms observer fires about 20 times a second: ${after - before}`);
  await probe.click("unobserve");
  await page.waitForFunction("!document.querySelector('audio,video').hasAttribute('data-media-observe')", undefined, { timeout: 5000 });

  // --- the end: the player stops by itself, the time is the duration, the rate 0.
  await probe.click("pause");
  await page.waitForFunction("document.querySelector('audio,video').paused === true");
  mark = await probe.mark();
  await probe.click("seekEnd");
  await probe.waitLine("S|end|", { after: mark });
  await probe.click("play");
  await page.waitForFunction("document.querySelector('audio,video').ended === true", undefined, { timeout: 10000 });
  deadline = Date.now() + 6000;
  let end = await probe.read();
  while (end.tcs !== 0 && Date.now() < deadline) {
    await page.waitForTimeout(100);
    end = await probe.read();
  }
  check(end.tcs === 0 && end.rate === 0 && Math.abs(end.t - DURATION * 1000) <= 60, `${tag} after the end: paused, rate 0, time = duration: ${JSON.stringify(end)}`);
  mark = await probe.mark();
  await probe.click("seekBeyond");
  got = (await probe.waitLine("S|beyond|", { after: mark }))[0].split("|");
  check(got[2] === "1" && Math.abs(Number.parseInt(got[3], 10) - DURATION * 1000) <= 60, `${tag} a seek past the end lands on the duration: ${JSON.stringify(got)}`);

  // --- an error: a missing file fails the player and its item; a good one recovers.
  await probe.click("bad");
  deadline = Date.now() + 10000;
  let failed = null;
  while (Date.now() < deadline) {
    failed = await probe.read();
    if (failed.item === 2) break;
    await page.waitForTimeout(100);
  }
  check(failed && failed.item === 2 && failed.status === 2, `${tag} a missing file fails the item and the player: ${JSON.stringify(failed)}`);
  await probe.click("wav");
  deadline = Date.now() + 10000;
  let recovered;
  while (Date.now() < deadline) {
    recovered = await probe.read();
    if (recovered.item === 1 && recovered.duration > 0) break;
    await page.waitForTimeout(100);
  }
  check(recovered.item === 1, `${tag} a new item recovers: ${JSON.stringify(recovered)}`);

  // --- a video element works the same.
  const name = await playableVideo(page, videos);
  if (name) {
    await probe.click(name);
    await page.waitForSelector("video[data-player-id]", { state: "attached", timeout: 10000 });
    deadline = Date.now() + 10000;
    while (Date.now() < deadline) {
      const loaded = await probe.read();
      if (loaded.item === 1 && loaded.duration > 0) break;
      await page.waitForTimeout(100);
    }
    await probe.click("play");
    await page.waitForFunction("document.querySelector('video').paused === false", undefined, { timeout: 10000 });
    ({ errors: errs, pairs } = await sampleBurst(page, probe));
    worst = maxAbs(errs, 9999);
    check(errs.length > 0 && worst <= TOLERANCE_MS, `${tag} video reads within ${TOLERANCE_MS} ms of the element: worst ${worst.toFixed(0)}`);
  } else {
    console.log(`${tag} no playable video here: the video check is skipped`);
  }

  check(errors.length === 0, `${tag} page errors: ${JSON.stringify(errors.slice(0, 3))}`);
  await page.close();
}

/** (holder, tag, paused, time) of every media element: 'view' inside the app root, 'host' in the media host's container. */
function mediaElements(page) {
  return page.evaluate(`() => [...document.querySelectorAll('audio,video')].map(v => [
      v.closest('[data-headless-media]') ? 'host' : 'view', v.tagName, v.paused, v.currentTime])`.replace(/^/, "(") + ")()");
}

async function headlessScenario(browser, base, worker, videos, results) {
  // A player no view shows plays on an element of the media host, and a view that mounts or unmounts mid-playback takes
  // the element over without a restart or a second sound (section 12.17).
  const mode = worker ? "worker" : "main";
  const engine = browser.browserType().name();
  const tag = `[${engine}/${mode}/headless]`;
  console.log(`${tag} scenario`);
  const { page, probe, errors } = await openPage(browser, base, worker);
  check(JSON.stringify((await mediaElements(page)).map((m) => m[0])) === JSON.stringify(["view"]), `${tag} a mounted VideoPlayer is the only element at first: ${JSON.stringify(await mediaElements(page))}`);
  await probe.click("hide-view");
  await page.waitForFunction("document.querySelectorAll('audio').length === 1 && !!document.querySelector('[data-headless-media] audio')", undefined, { timeout: 10000 });
  check((await mediaElements(page)).length === 1, `${tag} one element after the view left: ${JSON.stringify(await mediaElements(page))}`);
  await probe.click("play");
  let deadline = Date.now() + 10000;
  let playing = await probe.read();
  while (playing.tcs !== 2 && Date.now() < deadline) {
    await page.waitForTimeout(50);
    playing = await probe.read();
  }
  if (!check(playing.tcs === 2, `${tag} a player without a view plays: ${JSON.stringify(playing)}`)) {
    await page.close();
    return;
  }
  let els = await mediaElements(page);
  check(els[0][0] === "host" && els[0][2] === false, `${tag} the host's element is the one playing: ${JSON.stringify(els)}`);
  const { errors: errs, pairs } = await sampleBurst(page, probe);
  const worst = maxAbs(errs, 9999);
  const times = pairs.map((p) => p[1]);
  check(errs.length > 0 && worst <= TOLERANCE_MS, `${tag} reads within ${TOLERANCE_MS} ms of the host's element: worst ${worst.toFixed(0)}`);
  check(pairwise(times).every(([x, y]) => y >= x) && new Set(times).size >= 80, `${tag} reads advance without running backwards`);
  results.set(`${engine}|${mode}|headless-error-ms`, worst);

  // The view mounts mid-playback: its element takes over where the host's was, and only one thing plays at any time.
  const before = await probe.read();
  await probe.click("show-view");
  await page.waitForFunction(`!!document.querySelector('audio[data-player-id]:not([style*="opacity: 0"])') || document.querySelectorAll('audio').length >= 1`, undefined, { timeout: 10000 });
  let seenView = false;
  let worstLoud = 0;
  for (let index = 0; index < 80; index++) {
    els = await mediaElements(page);
    const loud = els.filter((e) => e[2] === false).length;
    worstLoud = Math.max(worstLoud, loud);
    seenView = seenView || els.some((e) => e[0] === "view");
    await page.waitForTimeout(25);
  }
  check(seenView && worstLoud <= 1, `${tag} the view took over and nothing played twice (loudest moment: ${worstLoud}): ${JSON.stringify(await mediaElements(page))}`);
  const after = await probe.read();
  els = await mediaElements(page);
  check(els.length === 1 && els[0][0] === "view", `${tag} only the view's element is left: ${JSON.stringify(els)}`);
  check(after.tcs === 2 && before.t <= after.t && after.t <= before.t + 4500, `${tag} playback continued across the mount without a restart: ${before.t} -> ${after.t} (${after.tcs})`);

  // The view goes away mid-playback: the host's element starts where the view's stopped.
  const mid = await probe.read();
  await probe.click("hide-view");
  await page.waitForFunction("!!document.querySelector('[data-headless-media] audio')", undefined, { timeout: 10000 });
  await page.waitForTimeout(500);
  const back = await probe.read();
  els = await mediaElements(page);
  check(els.length === 1 && els[0][0] === "host" && els[0][2] === false, `${tag} the host plays again after the view left: ${JSON.stringify(els)}`);
  check(back.tcs === 2 && mid.t <= back.t && back.t <= mid.t + 4500, `${tag} playback continued across the unmount: ${mid.t} -> ${back.t} (${back.tcs})`);
  await probe.click("pause");
  await page.waitForFunction("document.querySelector('audio,video').paused === true");
  const paused = await probe.read();
  check(paused.tcs === 0 && paused.rate === 0, `${tag} paused without a view: ${JSON.stringify(paused)}`);

  // A new item of another kind: a video without a layer plays on a hidden <video>, then audio again.
  const name = await playableVideo(page, videos);
  if (name) {
    await probe.click(name);
    await page.waitForSelector("[data-headless-media] video", { state: "attached", timeout: 10000 });
    await probe.click("play");
    await page.waitForFunction("document.querySelector('video').paused === false && document.querySelector('video').currentTime > 0.2", undefined, { timeout: 15000 });
    deadline = Date.now() + 10000;
    let r = await probe.read();
    while (r.tcs !== 2 && Date.now() < deadline) {
      await page.waitForTimeout(100);
      r = await probe.read();
    }
    check(r.tcs === 2 && r.t > 100, `${tag} a video with no layer plays headlessly: ${JSON.stringify(r)}`);
    await probe.click("pause");
  }
  check(errors.length === 0, `${tag} page errors: ${JSON.stringify(errors.slice(0, 3))}`);
  await page.close();
}

async function autoplayScenario(browser, base, worker) {
  // A play() the browser refuses (no user gesture, sound on: NotAllowedError) leaves the player paused: no crash, no
  // waiting forever, and what Swift reads is what the element does. The refusal is simulated, so every engine takes the same
  // path (headless Chromium and WebKit allow the play); a real refusal rejects play() the same way.
  const mode = worker ? "worker" : "main";
  const tag = `[${browser.browserType().name()}/${mode}/autoplay]`;
  console.log(`${tag} scenario`);
  const { page, probe, errors } = await openPage(browser, base, worker);
  await probe.click("hide-view");
  await page.waitForSelector("[data-headless-media] audio", { state: "attached", timeout: 10000 });
  await page.evaluate(`(() => { const play = HTMLMediaElement.prototype.play; window.__plays = 0;
      HTMLMediaElement.prototype.play = function () { window.__plays++; return window.__refusePlay ? Promise.reject(new DOMException('play() failed because the user did not interact with the document first.', 'NotAllowedError')) : play.call(this); };
      window.__refusePlay = true; })()`);
  await probe.click("play");
  await page.waitForTimeout(1200);
  let r = await probe.read();
  check(await page.evaluate("document.querySelector('audio').paused"), `${tag} the element did not play`);
  check(r.tcs === 0 && r.rate === 0 && r.t === 0 && r.status !== 2, `${tag} a refused play leaves the player paused at the start, not failed: ${JSON.stringify(r)}`);
  const plays = await page.evaluate("window.__plays");
  await page.waitForTimeout(500);
  check((await page.evaluate("window.__plays")) === plays, `${tag} the host does not ask again on its own (${plays} tries)`);
  // A later play that the browser allows works.
  await page.evaluate("window.__refusePlay = false");
  await probe.click("play");
  const deadline = Date.now() + 10000;
  r = await probe.read();
  while (r.tcs !== 2 && Date.now() < deadline) {
    await page.waitForTimeout(100);
    r = await probe.read();
  }
  check(r.tcs === 2, `${tag} an allowed play afterwards plays: ${JSON.stringify(r)}`);
  check(errors.length === 0, `${tag} page errors: ${JSON.stringify(errors.slice(0, 3))}`);
  await page.close();
}

async function assumeScenario(browser, base, worker) {
  // MainActor.assumeIsolated works inside the app's actions and inside every kind of AV callback (it used to trap).
  const mode = worker ? "worker" : "main";
  const tag = `[${browser.browserType().name()}/${mode}/assumeIsolated]`;
  console.log(`${tag} scenario`);
  const { page, probe, errors } = await openPage(browser, base, worker);
  const mark = await probe.mark();
  await probe.click("ai-action");
  await probe.waitLine("AI|action", { after: mark });
  await probe.click("ai-seek");
  await probe.waitLine("AI|seek", { after: mark });
  await probe.click("seekStart");
  await probe.waitLine("S|start|", { after: mark });
  await probe.click("ai-observers");
  await probe.click("play");
  await probe.waitLine("AI|periodic", { after: mark, timeout: 10000 });
  await probe.waitLine("AI|boundary", { after: mark, timeout: 10000 });
  await probe.click("pause");
  check(errors.length === 0, `${tag} page errors: ${JSON.stringify(errors.slice(0, 3))}`);
  await page.close();
}

async function migration(browser, base, results) {
  const tag = `[${browser.browserType().name()}/migrate]`;
  console.log(`${tag} scenario`);
  const { page, probe, errors } = await openPage(browser, base, true, true);
  await probe.click("play");
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline && (await probe.read()).tcs !== 2) await page.waitForTimeout(50);
  const before = await probe.read();
  check(before.tcs === 2, `${tag} playing before the move: ${JSON.stringify(before)}`);
  await page.evaluate("window.__renderWorker.forceOverflow()");
  await page.setViewportSize({ width: 431, height: 900 });
  await page.waitForFunction("window.__embeddedSession.worker === false", undefined, { timeout: 15000 });
  await page.waitForTimeout(300);
  const after = await probe.read();
  check(after.tcs === 2 && after.rate === 1, `${tag} still playing after the move: ${JSON.stringify(after)}`);
  check(after.t >= before.t, `${tag} time did not run backwards across the move: ${before.t} -> ${after.t}`);
  const { errors: errs, pairs } = await sampleBurst(page, probe);
  const worst = maxAbs(errs, 9999);
  check(errs.length > 0 && worst <= TOLERANCE_MS, `${tag} reads on the main thread stay within ${TOLERANCE_MS} ms of the element: worst ${worst.toFixed(0)}`);
  const times = pairs.map((p) => p[1]);
  check(pairwise(times).every(([x, y]) => y >= x), `${tag} reads never run backwards after the move`);
  await probe.click("pause");
  check(errors.length === 0, `${tag} page errors: ${JSON.stringify(errors.slice(0, 3))}`);
  await page.close();
}

async function playRaceScenario(browser, base, worker) {
  // A play asked right after a seek, and a play asked right after the element paused on its own, both end playing.
  //
  // The second is the race of section 12.27: the element's `pause` event (queued by the browser when the page pauses it) reaches
  // Swift after Swift has asked to play again, and an element report used to overwrite that newer intent. Both calls go in one
  // task, the way a click on a native control followed by a click on the app's button arrives. Chromium and WebKit, the Worker
  // and the main thread.
  const mode = worker ? "worker" : "main";
  const tag = `[${browser.browserType().name()}/${mode}/race]`;
  console.log(`${tag} scenario`);
  const { page, probe, errors } = await openPage(browser, base, worker);
  await probe.click("play");
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline && (await page.evaluate("document.querySelector('audio,video').paused"))) await page.waitForTimeout(50);
  await page.waitForTimeout(300);
  // A seek, then a play before the seek has settled.
  await probe.click("seek2");
  await probe.click("play");
  await page.waitForTimeout(1200);
  let read = await probe.read();
  let paused = await page.evaluate("document.querySelector('audio,video').paused");
  check(!paused && read.rate === 1 && read.tcs === 2, `${tag} a play right after a seek plays: element paused=${paused}, ${JSON.stringify(read)}`);
  // The element pauses on its own, and Swift asks to play in the same task.
  await page.evaluate(`(() => { document.querySelector('audio,video').pause(); document.querySelector('[data-testid="play"]').click(); })()`);
  await page.waitForTimeout(1200);
  read = await probe.read();
  paused = await page.evaluate("document.querySelector('audio,video').paused");
  check(!paused && read.rate === 1 && read.tcs === 2, `${tag} a play that follows the element's own pause plays: element paused=${paused}, ${JSON.stringify(read)}`);
  check(errors.length === 0, `${tag} page errors: ${JSON.stringify(errors.slice(0, 3))}`);
  await page.close();
}

await runSuite(async () => {
  const temp = mkdtempSync(join(tmpdir(), "swui-media-"));
  const served = join(temp, "bundle");
  cpSync(BUNDLE, served, { recursive: true });
  const videos = makeMedia(served);
  const server = await serveBundle({ bundle: served, port: PORT, logName: "media-worker-server" });
  const results = new Map();
  try {
    for (const engine of ENGINES) {
      process.env.SWIFTUIWEB_BROWSER_ENGINE = engine;
      const browser = await launch(engine === "chromium" ? { args: ["--autoplay-policy=no-user-gesture-required"] } : {});
      try {
        for (const worker of [true, false]) {
          await scenario(browser, server.base, worker, videos, results);
          await headlessScenario(browser, server.base, worker, videos, results);
          await autoplayScenario(browser, server.base, worker);
          await playRaceScenario(browser, server.base, worker);
          await assumeScenario(browser, server.base, worker);
        }
        await migration(browser, server.base, results);
      } finally {
        await browser.close();
      }
    }
  } finally {
    await server.stop();
    rmSync(temp, { recursive: true, force: true });
  }
  for (const [key, value] of [...results.entries()].sort(([x], [y]) => (x < y ? -1 : x > y ? 1 : 0))) console.log("  ", key, JSON.stringify(value));
  if (failures.length > 0) {
    console.log(`${failures.length} FAILED`);
    process.exitCode = 1;
    return;
  }
  console.log("PASS media reads are synchronous and accurate in the Worker and on the main thread");
});
