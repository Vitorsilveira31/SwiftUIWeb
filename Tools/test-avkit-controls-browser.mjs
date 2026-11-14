#!/usr/bin/env bun
// VideoPlayer's AVKit-style controls, in Chromium and WebKit.
//
// The player draws its own controls over a control-less <video>: framework DOM (`.avkit-controls`) that app CSS can
// restyle or hide, with Swift deciding glyphs, labels and states from the AVPlayer and the page's media host handling the pointer,
// keyboard, auto-hide, fullscreen and Picture in Picture. The fixture is Tests/Apps/MediaProbeApp over a clip this script generates
// (ffmpeg), the same one the media worker test uses; each scenario runs with the Worker and with the main thread (?render-in-worker=0).
//
// Covered: no native `controls` attribute and no shadow-DOM chrome; play/pause from the centre button, the keyboard and the surface;
// the scrubber (drag preview that leaves the element alone, one seek on release, elapsed/remaining time, slider value and text);
// skip back/forward; mute and the volume slider; the speed menu; auto-hide after about 3 s of playback and the controls staying while
// paused; fullscreen asked of the player container (not of the bare video); Picture in Picture only where the page supports it;
// the buffering spinner and the error state; replay from the end; the accessibility tree (roles, labels, slider values and text, focus
// order); the app's overlay above the video and below the controls; app CSS hiding the controls; reduced motion; the touch layout;
// the move from the Worker to the main thread; the handover to a headless player and back; the subtitles menu (Off and the two
// `<track>`s of the fixture, the default checked, the choice showing that track and its cues, Off, persistence across pause and seek,
// the keyboard, one menu open at a time, no audio menu for a plain file).
// Bundle: AVKIT_CONTROLS_BUNDLE (.build/browser/MediaProbeApp). Port: AVKIT_CONTROLS_PORT. Screenshots: AVKIT_CONTROLS_SHOTS.
import { spawnSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { launch, ROOT, runSuite, serveBundle } from "./browser-test-support.mjs";

const BUNDLE = resolve(process.env.AVKIT_CONTROLS_BUNDLE ?? join(ROOT, ".build/browser/MediaProbeApp"));
const PORT = Number(process.env.AVKIT_CONTROLS_PORT ?? "8147");
const SHOTS = process.env.AVKIT_CONTROLS_SHOTS ?? join(tmpdir(), "avkit-controls-shots");
const ENGINES = (process.env.AVKIT_CONTROLS_ENGINES ?? "chromium,webkit").split(",").filter(Boolean);
const DURATION = 20.0;
const failures = [];

const json = (value) => JSON.stringify(value);

function check(condition, message) {
  if (!condition) {
    failures.push(message);
    console.log(`  FAIL ${message}`);
  }
  return Boolean(condition);
}

/** A silent 8 kHz mono 16-bit WAV of `seconds`. */
function wavBytes(seconds) {
  const data = 8000 * seconds * 2;
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
  if (spawnSync("which", ["ffmpeg"]).status !== 0) throw new Error("ffmpeg is needed to generate the test clip");
  const kinds = {};
  const video = ["-f", "lavfi", "-i", `testsrc=s=640x360:r=10:d=${DURATION}`, "-f", "lavfi", "-i", `sine=frequency=440:d=${DURATION}`, "-shortest", "-y"];
  for (const [name, args] of [
    ["mp4", ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-movflags", "+faststart"]],
    ["webm", ["-c:v", "libvpx", "-b:v", "200k", "-c:a", "libopus"]],
  ]) {
    if (spawnSync("ffmpeg", ["-hide_banner", "-loglevel", "error", ...video, ...args, join(directory, `probe.${name}`)], { stdio: "inherit" }).status === 0) kinds[name] = true;
  }
  writeFileSync(join(directory, "probe.wav"), wavBytes(Math.trunc(DURATION)));
  // The two subtitle tracks of the fixture: one cue over the whole clip each, so any time shows the track's line.
  for (const [language, line] of [["en", "English line"], ["pt", "Linha em português"]]) {
    writeFileSync(join(directory, `captions-${language}.vtt`), `WEBVTT\n\n00:00:00.000 --> 00:00:${String(Math.trunc(DURATION) - 1).padStart(2, "0")}.900\n${line}\n`, "utf8");
  }
  return kinds;
}

/** The page of one scenario. */
class Player {
  static async create(browser, base, worker, tag, kind, { contextOptions = {}, initScript = null } = {}) {
    const player = new Player();
    player.tag = tag;
    player.step = "start";
    player.context = await browser.newContext({ viewport: { width: 900, height: 760 }, ...contextOptions });
    if (initScript) await player.context.addInitScript(initScript);
    player.page = await player.context.newPage();
    player.errors = [];
    player.page.on("pageerror", (e) => player.errors.push(String(e)));
    player.page.on("console", (m) => {
      if (m.type() === "error" && !m.text().includes("Failed to load resource")) player.errors.push(m.text());
    });
    await player.page.goto(`${base}/?render-in-worker=${worker ? 1 : 0}`, { waitUntil: "domcontentloaded" });
    await player.page.waitForSelector('html[data-embedded-mounted="true"]', { timeout: 30000 });
    if ((await player.page.evaluate("window.__embeddedSession.worker")) !== Boolean(worker)) throw new Error("wrong mode");
    await player.clickProbe(kind);
    await player.page.waitForFunction("document.querySelector('video[data-player-id]')?.readyState >= 1", undefined, { timeout: 20000 });
    await player.page.waitForSelector(".avkit-controls", { state: "attached", timeout: 10000 });
    await player.settle();
    return player;
  }

  settle(ms = 400) {
    return this.page.waitForTimeout(ms);
  }

  async clickProbe(name) {
    // A DOM click, as the media worker test does (WebKit can hit-test a scroller with a stale offset).
    await this.page.locator(`[data-testid="${name}"]`).dispatchEvent("click");
  }

  async lines() {
    return ((await this.page.locator('[data-testid="log"]').textContent()) || "").split("\n").filter(Boolean);
  }

  /** What the app's Swift code reads for the player's time, in seconds. */
  async swiftTime() {
    const before = (await this.lines()).length;
    await this.clickProbe("read");
    const deadline = Date.now() + 10000;
    while (Date.now() < deadline) {
      const found = (await this.lines()).slice(before).filter((l) => l.startsWith("R|"));
      if (found.length) return Number.parseInt(found[0].split("|")[2], 10) / 1000;
      await this.page.waitForTimeout(25);
    }
    throw new assertionError("no read");
  }

  video(expression) {
    return this.page.evaluate(`(() => { const v = document.querySelector('video[data-player-id]'); return ${expression}; })()`);
  }

  controls(expression) {
    return this.page.evaluate(`(() => { const c = document.querySelector('.avkit-controls'); return ${expression}; })()`);
  }

  button(action) {
    return this.page.locator(`.avkit-controls [data-control-action="${action}"]`);
  }

  async wait(expression, timeout = 8000) {
    try {
      await this.page.waitForFunction(expression, undefined, { timeout });
      return true;
    } catch (error) {
      if (error?.name !== "TimeoutError") throw error;
      return check(false, `${this.tag} [${this.step}] timed out waiting for: ${expression.slice(0, 140)}`);
    }
  }

  async hidden() {
    return (await this.controls("c.getAttribute('data-ctl-hidden')")) === "1";
  }

  async shot(name) {
    mkdirSync(SHOTS, { recursive: true });
    const path = join(SHOTS, `${this.tag.replace(/^\[|\]$/g, "").replaceAll("/", "-")}-${name}.png`);
    await this.page.screenshot({ path, clip: { x: 0, y: 0, width: 900, height: 300 } });
    return path;
  }

  close() {
    return this.context.close();
  }
}

function assertionError(message) {
  return new Error(message);
}

const remaining = (p) => p.controls("c.querySelector('.avkit-remaining').textContent");

async function pauseAndRewind(p) {
  await p.clickProbe("pause");
  await p.clickProbe("seekStart");
  await p.wait("document.querySelector('video').currentTime < 0.5 && document.querySelector('video').paused");
  await p.settle(300);
}

const browserName = (browser) => browser.browserType().name();

async function scenario(browser, base, worker, kind) {
  const mode = worker ? "worker" : "main";
  const tag = `[${browserName(browser)}/${mode}]`;
  console.log(`${tag} controls`);
  const p = await Player.create(browser, base, worker, tag, kind);
  const page = p.page;

  // ---- Structure: framework DOM, no native chrome
  p.step = "Structure";
  check((await p.video("v.hasAttribute('controls')")) === false, `${tag} the <video> has no native controls attribute`);
  check((await p.video("v.controls")) === false, `${tag} video.controls is false`);
  check((await page.locator(".avkit-controls").count()) === 1, `${tag} one .avkit-controls`);
  for (const name of ["bar", "transport", "play-pause", "skip-back", "skip-forward", "scrubber", "mute", "volume", "speed", "fullscreen", "elapsed", "remaining"]) {
    check((await page.locator(`.avkit-controls .avkit-${name}`).count()) >= 1, `${tag} .avkit-${name} is drawn`);
  }
  check((await p.controls("c.getAttribute('data-player-state')")) === "paused", `${tag} idle state is paused`);
  check((await p.controls("c.querySelector('.avkit-remaining').textContent")) === `-0:${Math.trunc(DURATION)}`, `${tag} remaining time shows the duration: ${await remaining(p)}`);
  await p.shot("paused");

  // ---- Play / pause with the centre button; the glyph and label follow the AVPlayer
  p.step = "Play / pause with the centre button; the glyph and label follow the AVPlayer";
  await p.button("play-pause").click();
  await p.wait("!document.querySelector('video').paused");
  await p.wait("document.querySelector('.avkit-play-pause').getAttribute('aria-label') === 'Pause'");
  check(true, "play");
  const t0 = Date.now();
  check(["playing", "buffering"].includes(await p.controls("c.getAttribute('data-player-state')")), `${tag} state while playing`);
  await p.wait("document.querySelector('.avkit-play-pause [data-symbol]').getAttribute('data-symbol') === 'pause.fill'");
  check((await p.swiftTime()) >= 0, `${tag} Swift reads the time`);
  // Auto-hide: still shown after 1.5 s, hidden by about 3 s of playback without interaction.
  await page.mouse.move(450, 600);
  await page.waitForTimeout(1200);
  check(!(await p.hidden()), `${tag} controls are still shown 1.2 s into playback`);
  if (!(await p.wait("document.querySelector('.avkit-controls').getAttribute('data-ctl-hidden') === '1'", 6000))) {
    console.log("   diagnostic:", await p.video("[v.paused, v.readyState, v.ended, !!v.error]"), await page.evaluate("document.activeElement.className"), await page.evaluate("document.querySelector('.avkit-bar').matches(':hover')"));
  }
  const elapsed = (Date.now() - t0) / 1000;
  check(elapsed >= 2.4 && elapsed <= 5.0, `${tag} controls hide after about 3 s without interaction (${elapsed.toFixed(1)} s)`);
  await page.waitForTimeout(500);
  check(Number.parseFloat(await p.controls("getComputedStyle(c).opacity")) < 0.1, `${tag} hidden controls fade out`);
  await p.shot("hidden");
  // Mouse movement shows them again, and a keyboard focus does too.
  await page.mouse.move(460, 150);
  await page.waitForFunction("document.querySelector('.avkit-controls').getAttribute('data-ctl-hidden') === '0'", undefined, { timeout: 3000 });
  check(true, "mouse move shows the controls");
  await page.waitForFunction("document.querySelector('.avkit-controls').getAttribute('data-ctl-hidden') === '1'", undefined, { timeout: 7000 });
  await page.locator(".avkit-video-player").focus();
  for (let index = 0; index < 4; index++) {
    await page.keyboard.press("Tab");
    if (await page.evaluate("!!document.activeElement.closest('.avkit-controls')")) break;
  }
  await p.wait("document.querySelector('.avkit-controls').getAttribute('data-ctl-hidden') === '0'", 3000);
  check(true, "keyboard focus on a control shows the controls");
  await page.waitForTimeout(3600);
  check(!(await p.hidden()), `${tag} controls stay while a control has keyboard focus`);
  await page.evaluate("document.activeElement.blur()");
  // Pausing keeps them for good.
  await p.button("play-pause").click();
  await p.wait("document.querySelector('video').paused");
  await page.waitForTimeout(3500);
  check(!(await p.hidden()), `${tag} paused controls do not hide`);
  check((await p.controls("c.getAttribute('data-player-state')")) === "paused", `${tag} paused state`);
  await p.wait("document.querySelector('.avkit-play-pause').getAttribute('aria-label') === 'Play'");

  // ---- Scrubber: the drag previews without touching the element; release seeks once
  p.step = "Scrubber";
  await pauseAndRewind(p);
  const track = await page.locator(".avkit-scrubber .avkit-track").boundingBox();
  const y = track.y + track.height / 2;
  await page.mouse.move(track.x + track.width * 0.25, y);
  await page.mouse.down();
  await page.mouse.move(track.x + track.width * 0.55, y, { steps: 6 });
  await page.waitForTimeout(150);
  const preview = Number.parseFloat(await p.controls("c.querySelector('.avkit-scrubber').getAttribute('aria-valuenow')"));
  check(Math.abs(preview - DURATION * 0.55) <= 1.2, `${tag} the thumb previews the drag position (${preview} s)`);
  check((await p.video("v.currentTime")) < 0.5, `${tag} the element is not seeked while dragging (${await p.video("v.currentTime")})`);
  check((await p.controls("c.getAttribute('data-ctl-scrubbing')")) === "1", `${tag} scrubbing is marked`);
  const elapsedText = await p.controls("c.querySelector('.avkit-elapsed').textContent");
  check(elapsedText === `0:${String(Math.round(DURATION * 0.55)).padStart(2, "0")}` || Math.abs(Number.parseInt(elapsedText.split(":")[1], 10) - DURATION * 0.55) <= 1, `${tag} elapsed text previews the drag`);
  await page.mouse.up();
  await p.wait(`Math.abs(document.querySelector('video').currentTime - ${DURATION * 0.55}) < 1.2`, 6000);
  await page.waitForTimeout(300);
  check(Math.abs((await p.swiftTime()) - DURATION * 0.55) <= 1.3, `${tag} the seek went through AVPlayer.seek(to:) (Swift reads ${await p.swiftTime()})`);
  const value = Number.parseFloat(await p.controls("c.querySelector('.avkit-scrubber').getAttribute('aria-valuenow')"));
  check(Math.abs(value - DURATION * 0.55) <= 1.5, `${tag} the thumb stays where it landed (${value})`);
  const text = await p.controls("c.querySelector('.avkit-scrubber').getAttribute('aria-valuetext')");
  check(text.includes(" of 20 seconds") && text.includes("seconds"), `${tag} slider value text is spoken time: ${json(text)}`);
  check((await p.controls("c.querySelector('.avkit-remaining').textContent")).startsWith("-0:0"), `${tag} remaining text counts down: ${await remaining(p)}`);
  await p.shot("scrubbed");

  // ---- Skip back and forward by 10 s
  p.step = "Skip back and forward by 10 s";
  await p.clickProbe("seekStart");
  await p.wait("document.querySelector('video').currentTime < 0.5");
  await p.settle(300);
  let before = await p.video("v.currentTime");
  await p.button("skip-forward").click();
  await p.wait(`Math.abs(document.querySelector('video').currentTime - ${before + 10}) < 1`);
  await p.button("skip-back").click();
  await p.wait(`Math.abs(document.querySelector('video').currentTime - ${before}) < 1`);
  check(true, "skip");
  await p.clickProbe("seekStart");
  await p.wait("document.querySelector('video').currentTime < 0.5");
  await p.button("skip-back").click();
  await page.waitForTimeout(400);
  check((await p.video("v.currentTime")) < 0.5, `${tag} skipping back at the start stays at 0`);

  // ---- Mute and volume
  p.step = "Mute and volume";
  check((await p.video("v.muted")) === true, `${tag} the probe starts muted`);
  await p.button("mute").click();
  if (!(await p.wait("!document.querySelector('video').muted", 3000))) {
    console.log("   debug", await p.video("[v.muted, v.volume, v.paused]"), await p.controls("c.getAttribute('data-ctl-hidden')"), (await p.lines()).slice(-5));
  }
  await p.wait("document.querySelector('.avkit-mute').getAttribute('aria-label') === 'Mute'");
  await p.button("mute").click();
  await p.wait("document.querySelector('video').muted");
  await p.wait("document.querySelector('.avkit-mute').getAttribute('aria-label') === 'Unmute'");
  const vol = await page.locator(".avkit-volume .avkit-track").boundingBox();
  await page.mouse.click(vol.x + vol.width * 0.4, vol.y + vol.height / 2);
  await p.wait("Math.abs(document.querySelector('video').volume - 0.4) < 0.08");
  check((await p.video("v.muted")) === false, `${tag} raising the volume sounds a muted player`);
  check(Math.abs((await p.video("v.volume")) - 0.4) < 0.08, `${tag} the volume slider sets the volume (${await p.video("v.volume")})`);
  const vtext = await p.controls("c.querySelector('.avkit-volume').getAttribute('aria-valuetext')");
  check(vtext.includes("percent"), `${tag} volume slider text: ${json(vtext)}`);

  // ---- Speed menu
  p.step = "Speed menu";
  await p.button("speed").click();
  await p.wait("document.querySelector('.avkit-speed').getAttribute('aria-expanded') === 'true'");
  check(await page.locator(".avkit-speed-menu").isVisible(), `${tag} the speed menu opens`);
  check((await page.locator(".avkit-speed-menu .avkit-menu-item").count()) === 6, `${tag} six speeds`);
  await page.locator('.avkit-menu-item[data-control-argument="1.5"]').click();
  await p.clickProbe("play");
  await p.wait("!document.querySelector('video').paused");
  await p.wait("Math.abs(document.querySelector('video').playbackRate - 1.5) < 0.01");
  await p.wait("document.querySelector('.avkit-speed').textContent === '1.5x'");
  check(!(await page.locator(".avkit-speed-menu").isVisible()), `${tag} choosing a speed closes the menu`);
  check((await page.locator('.avkit-speed-menu .avkit-menu-item[aria-checked="true"]').textContent()) === "1.5x", `${tag} the chosen speed is checked`);
  await p.clickProbe("rate1");
  await p.wait("Math.abs(document.querySelector('video').playbackRate - 1) < 0.01");
  await p.clickProbe("pause");

  // ---- Keyboard on the focused player
  p.step = "Keyboard on the focused player";
  await pauseAndRewind(p);
  await page.locator(".avkit-video-player").focus();
  await page.keyboard.press("Space");
  await p.wait("!document.querySelector('video').paused");
  await page.keyboard.press("k");
  await p.wait("document.querySelector('video').paused");
  await page.keyboard.press("ArrowRight");
  await p.wait("document.querySelector('video').currentTime > 4.5");
  const t = await p.video("v.currentTime");
  await page.keyboard.press("ArrowLeft");
  await p.wait(`document.querySelector('video').currentTime < ${t - 3.5}`);
  const was = await p.video("v.muted");
  await page.keyboard.press("m");
  await p.wait(`document.querySelector('video').muted === ${String(!was)}`);
  await page.keyboard.press("m");
  if (!(await p.wait(`document.querySelector('video').muted === ${String(was)}`, 4000))) {
    console.log("   diagnostic:", await p.video("[v.muted, v.volume, v.paused, v.getAttribute('data-media-muted'), v.getAttribute('data-media-volume')]"), await page.evaluate("document.querySelector('.avkit-mute').getAttribute('aria-label')"), (await p.lines()).slice(-3));
  }
  await page.keyboard.press("ArrowUp");
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("ArrowDown");
  await p.wait("document.querySelector('video').volume < 0.35");
  check((await p.video("v.volume")) < 0.35, `${tag} arrow keys change the volume (${await p.video("v.volume")})`);
  check(true, "keyboard");

  // ---- Fullscreen is asked of the container, not of the bare video; the Fullscreen API is stubbed so the test sees the request
  p.step = "Fullscreen is asked of the container, not of the bare video; the Fullscreen API is stubbed so the test sees the request";
  await page.evaluate(() => {
    window.__fs = [];
    const log = function () { window.__fs.push(this.className); return Promise.resolve(); };
    Element.prototype.requestFullscreen = log;
    Element.prototype.webkitRequestFullscreen = log;
  });
  await p.button("fullscreen").click();
  await p.wait("window.__fs.length >= 1");
  check((await page.evaluate("window.__fs[0]")).includes("avkit-video-player"), `${tag} the player container goes fullscreen (${json(await page.evaluate("window.__fs"))})`);
  await page.keyboard.press("f");
  await p.wait("window.__fs.length >= 2");

  // ---- Picture in Picture follows what the page supports (the fixture's page decides)
  p.step = "Picture in Picture follows what the page supports (the fixture's page decides)";
  const supported = await page.evaluate("!!document.pictureInPictureEnabled");
  const pipVisible = await page.locator(".avkit-pip").isVisible();
  check(pipVisible === supported, `${tag} the PiP button is shown only where supported (supported=${supported}, shown=${pipVisible})`);

  // ---- Accessibility
  p.step = "Accessibility";
  const tree = await page.evaluate(() => {
    const c = document.querySelector(".avkit-controls");
    const player = c.parentElement;
    const named = [...c.querySelectorAll("button,[role=slider],[role=menuitemradio],[role=group],[role=status],[role=alert]")].filter((e) => getComputedStyle(e).display !== "none")
      .map((e) => ({ role: e.getAttribute("role") || e.localName, label: e.getAttribute("aria-label"), text: e.textContent.trim().slice(0, 20) }));
    const sliders = [...c.querySelectorAll("[role=slider]")].map((e) => ({ label: e.getAttribute("aria-label"), now: e.getAttribute("aria-valuenow"), min: e.getAttribute("aria-valuemin"), max: e.getAttribute("aria-valuemax"), text: e.getAttribute("aria-valuetext"), tab: e.tabIndex }));
    const stops = [...player.querySelectorAll("button,[role=slider],[tabindex]")].filter((e) => e.tabIndex >= 0 && getComputedStyle(e).display !== "none" && getComputedStyle(e).visibility !== "hidden")
      .map((e) => e.getAttribute("aria-label") || e.className);
    return { named, sliders, stops, playerRole: player.getAttribute("role"), playerLabel: player.getAttribute("aria-label"), playerTab: player.tabIndex, video: document.querySelector("video").getAttribute("aria-label") };
  });
  check(tree.named.filter((item) => ["button", "slider", "group"].includes(item.role)).every((item) => item.label), `${tag} every control is named: ${json(tree.named.filter((i) => !i.label))}`);
  check(tree.named.filter((item) => item.role === "menuitemradio").every((item) => item.text), `${tag} menu items are named by their text`);
  const labels = tree.named.filter((i) => i.role === "button").map((i) => i.label);
  for (const expected of ["Skip Back 10 Seconds", "Skip Forward 10 Seconds", "Enter Full Screen"]) {
    check(labels.some((l) => l === expected), `${tag} a button named ${json(expected)} (${json(labels)})`);
  }
  check(labels.some((l) => l && l.startsWith("Playback Speed")), `${tag} a speed button`);
  check(labels.includes("Mute") || labels.includes("Unmute"), `${tag} a mute button`);
  check(json(tree.sliders.map((s) => s.label)) === json(["Seek", "Volume"]), `${tag} two named sliders: ${json(tree.sliders)}`);
  for (const s of tree.sliders) {
    check(s.min === "0" && s.now !== null && s.max !== null && s.text, `${tag} slider ${s.label} carries min, max, now and text: ${json(s)}`);
  }
  const order = tree.stops;
  const expectedOrder = ["Skip Back 10 Seconds", "Play", "Skip Forward 10 Seconds", "Seek", "Mute", "Volume"];
  let controlsOrder = order.filter((o) => !o.startsWith("push-button"));
  controlsOrder = controlsOrder.map((o) => (o === "Unmute" ? "Mute" : o));
  check(order.length > controlsOrder.length && order.indexOf(controlsOrder[0]) > 0, `${tag} the app's overlay button comes before the controls in the focus order: ${json(order)}`);
  check(json(controlsOrder.slice(0, 6)) === json(expectedOrder) && json(controlsOrder.slice(-2)) === json(["Enter Picture in Picture", "Enter Full Screen"]), `${tag} focus order is transport, scrubber, volume, speed, PiP, fullscreen: ${json(order)}`);
  check(tree.playerRole === "group" && tree.playerTab === 0 && tree.video === "Video player", `${tag} the player is a focusable group`);
  check((await page.evaluate("document.querySelector('video').className")).includes("avkit-media") && (await page.evaluate("document.querySelector('video').getAttribute('aria-roledescription')")) === "video", `${tag} the video keeps its role description`);

  // ---- Overlay: the app's content is above the video, below the controls, and still clickable
  p.step = "Overlay";
  const children = await page.evaluate(() => { const player = document.querySelector(".avkit-video-player"); return [...player.children].map((e) => e.localName + "." + [...e.classList].join(".")); });
  check(children[0].startsWith("video") && children[1].includes("avkit-overlay") && children[2].includes("avkit-controls"), `${tag} DOM order is video, overlay, controls: ${json(children)}`);
  check((await page.evaluate("+getComputedStyle(document.querySelector('.avkit-controls')).zIndex")) > 0, `${tag} the controls are stacked`);
  await p.button("play-pause").focus();
  await page.keyboard.press("Tab");
  before = Number.parseInt(((await page.locator('[data-testid="overlay-taps"]').textContent()) || "0").split(/\s+/).at(-1), 10);
  await page.locator('[data-testid="overlay-button"]').click();
  await page.waitForFunction(`document.querySelector('[data-testid="overlay-taps"]').textContent.endsWith('${before + 1}')`, undefined, { timeout: 5000 });
  const barBox = await page.locator(".avkit-bar").boundingBox();
  const top = await page.evaluate(`document.elementFromPoint(${barBox.x + 30}, ${barBox.y + barBox.height / 2})?.closest('.avkit-bar') !== null`);
  check(top, `${tag} the controls cover the overlay where they overlap`);

  check(p.errors.length === 0, `${tag} no runtime errors: ${json(p.errors)}`);
  await p.close();
}

async function captionsScenario(browser, base, worker, kind) {
  // The subtitles menu of a plain file with two <track>s (section 12.24's menu, MediaSelection.swift): Off and the tracks, the
  // browser's default checked, a choice shows that track's cues and the element's text tracks follow Swift's state.
  const mode = worker ? "worker" : "main";
  const tag = `[${browserName(browser)}/${mode}]`;
  console.log(`${tag} subtitles`);
  const p = await Player.create(browser, base, worker, tag, kind);
  const page = p.page;
  const modes = "[...document.querySelector('video').textTracks].map(t => t.mode).join(',')";
  // activeCues is null on a disabled track.
  const cue = (index) => `(() => { const t = document.querySelector('video').textTracks[${index}]; return t.activeCues?.length ? t.activeCues[0].text : ''; })()`;
  const toggle = "document.querySelector('.avkit-captions')";
  const items = page.locator(".avkit-captions-menu [role=menuitemradio]");

  const checked = async () => {
    const count = await items.count();
    const marks = [];
    for (let index = 0; index < count; index++) marks.push(await items.nth(index).getAttribute("aria-checked"));
    return marks;
  };

  // ---- The menu lists Off and both tracks, and checks what the browser shows. Chromium shows the default track (English);
  // WebKit does not load a <track default> while the video is paused or playing (its readyState stays 0), so there it is Off.
  p.step = "Subtitles menu lists Off and the tracks";
  check((await page.locator(".avkit-captions").count()) === 1, `${tag} a subtitles button`);
  check((await page.locator(".avkit-audio").count()) === 0, `${tag} no audio button for a plain file`);
  check((await page.locator(".avkit-captions").getAttribute("aria-haspopup")) === "menu", `${tag} the button is a menu button`);
  const shown = await p.video(modes);
  const names = { "showing,disabled": "English", "disabled,showing": "Português", "disabled,disabled": "Off" };
  const marks = { "showing,disabled": ["false", "true", "false"], "disabled,showing": ["false", "false", "true"], "disabled,disabled": ["true", "false", "false"] };
  check(shown in names, `${tag} at most one caption track shows: ${shown}`);
  if (browserName(browser) === "chromium") check(shown === "showing,disabled", `${tag} Chromium shows the default track: ${shown}`);
  check((await page.locator(".avkit-captions").getAttribute("aria-label")) === "Subtitles and Captions, " + (names[shown] ?? "?"), `${tag} the button names what shows: ${json(await page.locator(".avkit-captions").getAttribute("aria-label"))}`);
  await p.button("captions").click();
  await p.wait(`${toggle}.getAttribute('aria-expanded') === 'true'`);
  check((await p.controls("c.getAttribute('data-ctl-menu')")) === "captions", `${tag} the captions menu is the open one`);
  check(await page.locator(".avkit-captions-menu").isVisible(), `${tag} the subtitles menu opens`);
  check((await page.locator(".avkit-captions-menu").getAttribute("role")) === "menu", `${tag} the menu has the menu role`);
  check(json(await items.allTextContents()) === json(["Off", "English", "Português"]), `${tag} menu items: ${json(await items.allTextContents())}`);
  check(json(await checked()) === json(marks[shown]), `${tag} the menu checks what shows: ${json(await checked())}`);
  await p.shot("captions-menu");
  await page.keyboard.press("Escape");
  await p.wait(`${toggle}.getAttribute('aria-expanded') === 'false'`);
  check(await page.evaluate("document.activeElement === document.querySelector('.avkit-captions')"), `${tag} Escape returns the focus to the button`);

  // ---- Choosing a track with the pointer: its cues show, the others are off, the element follows Swift's choice
  p.step = "Choosing a track with the pointer";
  await p.button("captions").click();
  await p.wait(`${toggle}.getAttribute('aria-expanded') === 'true'`);
  await items.nth(2).click();
  if (!(await p.wait("document.querySelector('.avkit-controls').getAttribute('data-ctl-menu') === ''", 4000))) {
    console.log("   diagnostic:", await p.controls("c.getAttribute('data-ctl-menu')"), await p.video(modes), await page.evaluate("document.activeElement.outerHTML.slice(0, 200)"));
  }
  await p.wait(`${modes} === 'disabled,showing'`, 6000);
  check(true, `${tag} the Português track is showing`);
  // The host shows the track at once; Swift's choice comes back with the next render (what the labels and checks show).
  await p.wait("document.querySelector('video').getAttribute('data-media-text') === '1'", 6000);
  check(true, `${tag} the element carries Swift's choice`);
  await p.wait("document.querySelector('.avkit-captions').getAttribute('aria-label') === 'Subtitles and Captions, Português'", 6000);
  check(true, `${tag} the button names the choice`);
  await p.wait("[...document.querySelectorAll('.avkit-captions-menu [role=menuitemradio]')].map(e => e.getAttribute('aria-checked')).join() === 'false,false,true'", 6000);
  check(json(await checked()) === json(["false", "false", "true"]), `${tag} the menu checks the choice: ${json(await checked())}`);
  await p.clickProbe("play");
  await p.wait("document.querySelector('video').currentTime > 1.5", 8000);
  await p.wait(`${cue(1)} === 'Linha em português'`, 6000);
  check((await p.video(cue(0))) === "", `${tag} the English track shows no cue`);
  await p.shot("captions-shown");

  // ---- The choice survives a pause, a seek and playing again
  p.step = "The choice survives a pause and a seek";
  await p.clickProbe("pause");
  await p.clickProbe("seek2");
  await p.wait("Math.abs(document.querySelector('video').currentTime - 2) < 0.5");
  await p.clickProbe("play");
  await p.wait("document.querySelector('video').currentTime > 3", 8000);
  check((await p.video(modes)) === "disabled,showing", `${tag} still showing after a pause and a seek: ${await p.video(modes)}`);
  await p.wait(`${cue(1)} === 'Linha em português'`, 6000);
  await p.clickProbe("pause");
  check((await p.video(modes)) === "disabled,showing", `${tag} still showing once paused`);

  // ---- Off: no track shows and the menu checks Off
  p.step = "Off";
  await p.button("captions").click();
  await p.wait(`${toggle}.getAttribute('aria-expanded') === 'true'`);
  await items.nth(0).click();
  await p.wait(`${modes} === 'disabled,disabled'`, 6000);
  check((await p.video(modes)) === "disabled,disabled", `${tag} Off disables every track`);
  await p.wait("document.querySelector('.avkit-captions').getAttribute('aria-label') === 'Subtitles and Captions, Off'", 6000);
  check(true, `${tag} the button says Off`);
  await p.clickProbe("play");
  await p.wait("document.querySelector('video').currentTime > 1", 8000);
  check((await p.video(cue(1))) === "" && (await p.video(cue(0))) === "", `${tag} no cue shows with Off`);
  await p.clickProbe("pause");
  await p.clickProbe("seek2");
  await p.wait("Math.abs(document.querySelector('video').currentTime - 2) < 0.5");
  check((await p.video(modes)) === "disabled,disabled", `${tag} Off survives a seek`);

  // ---- Keyboard: Enter opens with the choice focused, arrows move, Enter chooses and returns the focus to the button
  p.step = "Keyboard";
  await page.locator(".avkit-captions").focus();
  await page.keyboard.press("Enter");
  await p.wait(`${toggle}.getAttribute('aria-expanded') === 'true'`);
  await page.waitForTimeout(300);
  await p.wait("document.activeElement.getAttribute('role') === 'menuitemradio'", 3000);
  check((await page.evaluate("document.activeElement.textContent")) === "Off", `${tag} the checked item (Off) takes the focus`);
  await page.keyboard.press("ArrowDown");
  check((await page.evaluate("document.activeElement.textContent")) === "English", `${tag} ArrowDown moves to English`);
  await page.keyboard.press("Enter");
  await p.wait(`${modes} === 'showing,disabled'`, 6000);
  check(await page.evaluate("document.activeElement === document.querySelector('.avkit-captions')"), `${tag} choosing returns the focus to the button`);
  check((await page.locator(".avkit-captions").getAttribute("aria-expanded")) === "false", `${tag} the menu is closed again`);

  // ---- One menu at a time: the speed menu closes when the subtitles menu opens
  p.step = "One menu at a time";
  await p.button("speed").click();
  await p.wait("document.querySelector('.avkit-speed').getAttribute('aria-expanded') === 'true'");
  await p.button("captions").click();
  await p.wait(`${toggle}.getAttribute('aria-expanded') === 'true'`);
  check((await p.controls("c.getAttribute('data-ctl-menu')")) === "captions", `${tag} opening subtitles closes speed`);
  check((await page.locator(".avkit-speed-menu").isVisible()) === false, `${tag} the speed menu is hidden`);
  await page.mouse.click(10, 10);
  await p.wait("document.querySelector('.avkit-controls').getAttribute('data-ctl-menu') === ''");
  check(true, `${tag} a click outside closes the menu`);
  await p.shot("captions-after");

  // ---- Rapid switching: each menu keeps exactly one checked item, sampled while the menu updates (no second check appears
  // while the render catches up), and the checked item is the one chosen.
  p.step = "Rapid switching keeps one checked item per menu";
  const checkedNow = (menu) => page.evaluate((name) => document.querySelectorAll(".avkit-" + name + '-menu [aria-checked="true"]').length, menu);
  const peakChecked = (menu, ms) => page.evaluate(({ menu: name, ms: duration }) => new Promise((resolve) => {
    let peak = 0;
    const start = performance.now();
    const tick = () => {
      peak = Math.max(peak, document.querySelectorAll(".avkit-" + name + '-menu [aria-checked="true"]').length);
      if (performance.now() - start < duration) setTimeout(tick, 4); else resolve(peak);
    };
    tick();
  }), { menu, ms });
  for (const rate of ["0.5", "2.0", "1.0", "1.5", "0.75", "1.25", "2.0", "1.0"]) {
    await p.button("speed").click();
    await p.wait(`${toggle.replace("captions", "speed")}.getAttribute('aria-expanded') === 'true'`);
    await page.locator(`.avkit-speed-menu [data-control-argument="${rate}"]`).click();
    const peak = await peakChecked("speed", 120);
    check(peak <= 1, `${tag} at most one speed is checked while switching to ${rate} (peak ${peak})`);
    await p.wait(`document.querySelector('.avkit-speed-menu [data-control-argument=\\'${rate}\\']').getAttribute('aria-checked') === 'true'`, 4000);
    check((await checkedNow("speed")) === 1, `${tag} one checked speed after ${rate}: ${await checkedNow("speed")}`);
  }
  for (const choice of ["1", "off", "0", "1", "off", "0"]) {
    await p.button("captions").click();
    await p.wait(`${toggle}.getAttribute('aria-expanded') === 'true'`);
    await page.locator(`.avkit-captions-menu [data-control-argument="${choice}"]`).click();
    const peak = await peakChecked("captions", 120);
    check(peak <= 1, `${tag} at most one subtitle is checked while choosing ${choice} (peak ${peak})`);
    await p.wait(`document.querySelector('.avkit-captions-menu [data-control-argument=\\'${choice}\\']').getAttribute('aria-checked') === 'true'`, 4000);
    check((await checkedNow("captions")) === 1, `${tag} one checked subtitle after ${choice}: ${await checkedNow("captions")}`);
  }
  check((await p.controls("c.getAttribute('data-ctl-menu')")) === "", `${tag} the menus are closed after switching`);
  check(p.errors.length === 0, `${tag} no runtime errors: ${json(p.errors)}`);
  await p.close();
}

async function muteRaceScenario(browser, base, worker, kind) {
  // Two M presses in one task (a held key, or two presses before the page has taken the first): the element answers the first
  // with a toggle the page has not shown yet, so a toggle computed from the element undid it. Swift decides the toggle, and the
  // two presses end where they began, the label and the element agreeing (section 12.27).
  const mode = worker ? "worker" : "main";
  const tag = `[${browserName(browser)}/${mode}]`;
  console.log(`${tag} mute race`);
  const p = await Player.create(browser, base, worker, tag, kind);
  const page = p.page;
  p.step = "Two M presses in one task";
  const was = await p.video("v.muted");
  await page.evaluate(() => {
    const player = document.querySelector(".avkit-video-player");
    const press = () => player.dispatchEvent(new KeyboardEvent("keydown", { key: "m", bubbles: true, cancelable: true }));
    press();
    press();
  });
  await p.settle(1500);
  const now = await p.video("v.muted");
  check(now === was, `${tag} two M presses in one task end where they began: muted ${now}, was ${was}`);
  const label = await page.evaluate("document.querySelector('.avkit-mute').getAttribute('aria-label')");
  check((label === "Unmute") === now, `${tag} the mute label agrees with the element: ${json(label)}, muted ${now}`);
  check(p.errors.length === 0, `${tag} page errors: ${json(p.errors.slice(0, 3))}`);
  await page.close();
}

async function statesScenario(browser, base, worker, kind) {
  const mode = worker ? "worker" : "main";
  const tag = `[${browserName(browser)}/${mode}]`;
  console.log(`${tag} states`);
  const p = await Player.create(browser, base, worker, tag, kind);
  const page = p.page;

  // ---- Ended: replay
  p.step = "Ended";
  await p.clickProbe("seekEnd");
  await p.wait(`document.querySelector('video').currentTime > ${DURATION - 1}`);
  await p.clickProbe("play");
  await p.wait("document.querySelector('video').ended", 8000);
  await p.wait("document.querySelector('.avkit-play-pause').getAttribute('aria-label') === 'Replay'", 5000);
  check((await p.controls("c.getAttribute('data-player-state')")) === "ended", `${tag} ended state`);
  await page.waitForTimeout(3400);
  check(!(await p.hidden()), `${tag} the controls stay at the end`);
  check((await p.controls("c.querySelector('.avkit-remaining').textContent")) === "-0:00", `${tag} nothing remains at the end`);
  await p.shot("ended");
  await p.button("play-pause").click();
  await p.wait("!document.querySelector('video').paused && document.querySelector('video').currentTime < 3", 8000);
  check(true, "replay starts over");
  await p.clickProbe("pause");

  // ---- Error: a file that is not there
  p.step = "Error";
  await p.clickProbe("bad");
  await page.waitForSelector(".avkit-error", { timeout: 10000 });
  check((await page.locator(".avkit-error").getAttribute("role")) === "alert", `${tag} the error is announced`);
  check((await p.controls("c.getAttribute('data-player-state')")) === "failed", `${tag} failed state`);
  check(await page.locator(".avkit-error").isVisible(), `${tag} the error shows`);
  await p.shot("error");
  await p.clickProbe(kind);
  await page.waitForSelector(".avkit-error", { state: "detached", timeout: 10000 });
  check(true, "a new item recovers");

  // ---- Buffering: a file that never arrives, so the player waits for data.
  p.step = "Buffering";
  const held = [];
  await page.route("**/probe.wav", (route) => { held.push(route); });
  await p.clickProbe("wav");
  await page.waitForTimeout(300);
  await p.clickProbe("play");
  try {
    await page.waitForSelector(".avkit-spinner", { timeout: 6000 });
    check((await page.locator(".avkit-spinner").getAttribute("role")) === "status", `${tag} the buffering spinner is a status`);
    check((await p.controls("c.getAttribute('data-player-state')")) === "buffering", `${tag} buffering state`);
    await page.waitForTimeout(700);
    check(await page.locator(".avkit-spinner").isVisible(), `${tag} the spinner shows after a moment`);
    await p.shot("buffering");
  } catch (error) {
    check(false, `${tag} no buffering spinner while the file does not arrive: ${error}`);
  }
  for (const route of held) await route.continue();
  await page.unroute("**/probe.wav");
  await p.clickProbe("pause");
  await p.clickProbe(kind);
  await p.wait("document.querySelector('video[data-player-id]')?.readyState >= 1");
  await p.clickProbe("seekStart");
  await p.settle(500);

  // ---- App CSS hides the controls (the native ones were unreachable in WebKit)
  p.step = "App CSS hides the controls (the native ones were unreachable in WebKit)";
  await page.addStyleTag({ content: ".avkit-controls { display: none !important; }" });
  check((await p.controls("getComputedStyle(c).display")) === "none", `${tag} app CSS can hide the controls`);
  await page.evaluate("document.querySelectorAll('style').forEach(s => { if (s.textContent.includes('avkit-controls')) s.remove(); })");

  // ---- Reduced motion
  p.step = "Reduced motion";
  await page.emulateMedia({ reducedMotion: "reduce" });
  check(["0s", "0s, 0s"].includes(await p.controls("getComputedStyle(c).transitionDuration")), `${tag} reduced motion removes the fade (${await p.controls("getComputedStyle(c).transitionDuration")})`);
  await page.emulateMedia({ reducedMotion: "no-preference" });

  // ---- The view goes away and comes back: a headless player in between, the same controls after
  p.step = "The view goes away and comes back";
  await p.clickProbe("seekStart");
  await p.wait("document.querySelector('video').currentTime < 1");
  await p.clickProbe("play");
  await p.wait("!document.querySelector('video').paused");
  await p.clickProbe("hide-view");
  await page.waitForSelector(".avkit-controls", { state: "detached", timeout: 8000 });
  await page.waitForTimeout(600);
  await p.clickProbe("show-view");
  await page.waitForSelector(".avkit-controls", { state: "attached", timeout: 8000 });
  await p.wait("document.querySelector('video[data-player-id]') && !document.querySelector('video[data-player-id]').paused", 8000);
  await p.wait("document.querySelector('.avkit-play-pause').getAttribute('aria-label') === 'Pause'", 8000);
  check((await p.video("v.hasAttribute('controls')")) === false, `${tag} the handed-over element has no native controls`);
  await p.button("play-pause").click();
  await p.wait("document.querySelector('video').paused", 5000);
  check(true, "controls work after the headless handover");
  check(p.errors.length === 0, `${tag} no runtime errors: ${json(p.errors)}`);
  await p.close();
}

async function migrationScenario(browser, base, kind) {
  const tag = `[${browserName(browser)}/worker->main]`;
  console.log(`${tag} migration`);
  const p = await Player.create(browser, base, true, tag, kind, { initScript: "window.__performanceDiagnostics = true" });
  const page = p.page;
  await p.button("play-pause").click();
  await p.wait("!document.querySelector('video').paused");
  await page.evaluate("window.__renderWorker.forceOverflow()");
  await p.wait("window.__embeddedSession.worker === false", 30000);
  await page.waitForTimeout(800);
  check((await page.locator(".avkit-controls").count()) === 1, `${tag} the controls survive the move`);
  check(await p.video("!v.paused"), `${tag} playback continues`);
  await p.button("play-pause").click();
  await p.wait("document.querySelector('video').paused", 6000);
  await p.wait("document.querySelector('.avkit-play-pause').getAttribute('aria-label') === 'Play'", 6000);
  const track = await page.locator(".avkit-scrubber .avkit-track").boundingBox();
  const y = track.y + track.height / 2;
  await page.mouse.click(track.x + track.width * 0.7, y);
  await p.wait(`Math.abs(document.querySelector('video').currentTime - ${DURATION * 0.7}) < 1.5`, 8000);
  // The player holds its time until the element has taken the seek (`seeked`), as AVPlayer does: read it after.
  await p.wait("!document.querySelector('video').seeking", 8000);
  let migratedTime = await p.swiftTime();
  for (let tries = 0; tries < 10 && Math.abs(migratedTime - DURATION * 0.7) > 1.6; tries++) {
    await page.waitForTimeout(300);
    migratedTime = await p.swiftTime();
  }
  check(Math.abs(migratedTime - DURATION * 0.7) <= 1.6, `${tag} the scrubber seeks through the migrated Swift state (Swift reads ${migratedTime}, the element ${await p.video("v.currentTime")})`);
  check(p.errors.length === 0, `${tag} no runtime errors: ${json(p.errors)}`);
  await p.close();
}

async function pipScenarios(browser, base, kind) {
  const tag = `[${browserName(browser)}]`;
  console.log(`${tag} picture in picture`);
  const on = await Player.create(browser, base, true, tag + "-pip", kind, {
    initScript: `Object.defineProperty(document, 'pictureInPictureEnabled', { value: true, configurable: true });
      window.__pip = []; HTMLVideoElement.prototype.requestPictureInPicture = function () { window.__pip.push('enter'); return Promise.resolve({}); };`,
  });
  check(await on.page.locator(".avkit-pip").isVisible(), `${tag} the PiP button shows where the page supports it`);
  await on.page.locator(".avkit-pip").click();
  await on.wait("window.__pip.length === 1");
  check((await on.page.evaluate("window.__pip[0]")) === "enter", `${tag} the button asks the video for Picture in Picture`);
  await on.close();
  const off = await Player.create(browser, base, true, tag + "-nopip", kind, {
    initScript: "Object.defineProperty(document, 'pictureInPictureEnabled', { value: false, configurable: true });",
  });
  check(!(await off.page.locator(".avkit-pip").isVisible()), `${tag} the PiP button is hidden where it is not supported`);
  check((await off.page.locator(".avkit-pip").count()) === 1, `${tag} (it is in the DOM, hidden by CSS)`);
  await off.close();
}

async function touchScenario(browser, base, kind) {
  const tag = `[${browserName(browser)}/touch]`;
  console.log(`${tag} touch layout`);
  const p = await Player.create(browser, base, true, tag, kind, {
    contextOptions: { hasTouch: true, isMobile: true, viewport: { width: 430, height: 860 }, deviceScaleFactor: 2 },
  });
  const page = p.page;
  const coarse = await page.evaluate("matchMedia('(pointer: coarse)').matches");
  if (!coarse) {
    console.log(`${tag} (pointer: coarse) is not emulated by this engine; the touch layout is not checked`);
    await p.close();
    return;
  }
  const box = await page.locator(".avkit-play-pause").boundingBox();
  const player = await page.locator(".avkit-video-player").boundingBox();
  check(box.width >= 44 && box.height >= 44, `${tag} touch targets are at least 44 pt: ${box.width}x${box.height}`);
  check(Math.abs(box.x + box.width / 2 - (player.x + player.width / 2)) < 4 && Math.abs(box.y + box.height / 2 - (player.y + player.height / 2)) < 6, `${tag} the play button is centred on the video`);
  mkdirSync(SHOTS, { recursive: true });
  await p.page.screenshot({ path: join(SHOTS, `${tag.replace(/^\[|\]$/g, "").replaceAll("/", "-")}-paused.png`), clip: { x: 0, y: 0, width: 430, height: 330 } });
  await page.locator(".avkit-play-pause").tap();
  await p.wait("!document.querySelector('video').paused");
  await page.waitForFunction("document.querySelector('.avkit-controls').getAttribute('data-ctl-hidden') === '1'", undefined, { timeout: 7000 });
  await page.touchscreen.tap(player.x + player.width / 2, player.y + 60);
  await p.wait("document.querySelector('.avkit-controls').getAttribute('data-ctl-hidden') === '0'", 3000);
  check(true, "a tap shows the controls");
  await page.touchscreen.tap(player.x + player.width / 2, player.y + 60);
  await p.wait("document.querySelector('.avkit-controls').getAttribute('data-ctl-hidden') === '1'", 3000);
  check(true, "a tap hides them again while playing");
  check(p.errors.length === 0, `${tag} no runtime errors: ${json(p.errors)}`);
  await p.close();
}

await runSuite(async () => {
  mkdirSync(SHOTS, { recursive: true });
  const temp = mkdtempSync(join(tmpdir(), "swui-avkit-"));
  const served = join(temp, "bundle");
  cpSync(BUNDLE, served, { recursive: true });
  const kinds = makeMedia(served);
  const server = await serveBundle({ bundle: served, port: PORT, logName: "avkit-controls-server" });
  try {
    for (const engine of ENGINES) {
      process.env.SWIFTUIWEB_BROWSER_ENGINE = engine;
      const browser = await launch(engine === "chromium" ? { args: ["--autoplay-policy=no-user-gesture-required"] } : {});
      try {
        const probe = await browser.newPage();
        await probe.goto("about:blank");
        let kind = null;
        for (const name of ["mp4", "webm"]) {
          if (name in kinds && (await probe.evaluate(`!!document.createElement('video').canPlayType('video/${name}; codecs=${name === "mp4" ? "avc1.42E01E" : "vp8"}')`))) {
            kind = name;
            break;
          }
        }
        await probe.close();
        if (kind === null) {
          console.log(`[${engine}] no playable clip format`);
          failures.push(`${engine}: no playable clip`);
          continue;
        }
        for (const worker of (process.env.AVKIT_CONTROLS_MODES ?? "worker,main").split(",").map((m) => m === "worker")) {
          await scenario(browser, server.base, worker, kind);
          await statesScenario(browser, server.base, worker, kind);
          await captionsScenario(browser, server.base, worker, kind);
          await muteRaceScenario(browser, server.base, worker, kind);
        }
        await migrationScenario(browser, server.base, kind);
        await pipScenarios(browser, server.base, kind);
        await touchScenario(browser, server.base, kind);
      } finally {
        await browser.close();
      }
    }
  } finally {
    await server.stop();
    rmSync(temp, { recursive: true, force: true });
  }
  if (failures.length > 0) {
    console.log(`${failures.length} FAILED`);
    process.exitCode = 1;
    return;
  }
  console.log(`PASS VideoPlayer controls (screenshots in ${SHOTS})`);
});
