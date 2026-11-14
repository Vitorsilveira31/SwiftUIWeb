#!/usr/bin/env bun
// Drives Tools/avfoundation.js with the Shaka Player pinned in package.json against a real HLS stream
// (Tests/Fixtures/AdaptiveMedia: 180p and 360p renditions, English and Portuguese audio, two subtitle tracks), in a
// browser. The unit tests fake the player; this one catches a Shaka release that renames or drops an API the helper calls.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { ROOT, launch, runSuite } from "./browser-test-support.mjs";

const FIXTURE = join(ROOT, "Tests", "Fixtures", "AdaptiveMedia");
const TYPES = { ".m3u8": "application/vnd.apple.mpegurl", ".mp4": "video/mp4", ".m4s": "video/iso.segment", ".vtt": "text/vtt" };

await runSuite(async () => {
  const built = await Bun.build({ entrypoints: [join(ROOT, "Tools", "shaka-loader.js")], format: "esm", minify: true });
  assert.ok(built.success, "the Shaka helper builds");
  const loader = await built.outputs[0].text();
  const helper = readFileSync(join(ROOT, "Tools", "avfoundation.js"));
  const server = Bun.serve({
    port: 0,
    hostname: "127.0.0.1",
    fetch(request) {
      const path = new URL(request.url).pathname;
      if (path === "/") return new Response('<video id="v" muted></video><script src="/avfoundation.js"></script>', { headers: { "content-type": "text/html" } });
      if (path === "/avfoundation.js") return new Response(helper, { headers: { "content-type": "text/javascript" } });
      if (path === "/shaka-loader.js") return new Response(loader, { headers: { "content-type": "text/javascript" } });
      const name = path.slice(1);
      if (!/^[\w.-]+$/.test(name)) return new Response("not found", { status: 404 });
      try {
        return new Response(readFileSync(join(FIXTURE, name)), { headers: { "content-type": TYPES[name.slice(name.lastIndexOf("."))] ?? "application/octet-stream" } });
      } catch {
        return new Response("not found", { status: 404 });
      }
    },
  });
  const browser = await launch();
  try {
    const page = await browser.newPage();
    const failures = [];
    page.on("pageerror", (error) => failures.push(error.message));
    page.on("console", (message) => { if (message.type() === "error") failures.push(message.text()); });
    await page.goto(`http://127.0.0.1:${server.port}/`);
    const tracks = (lines) => lines.split("\n").filter(Boolean).map((line) => line.split("\t"));
    const report = await page.evaluate(async () => {
      const video = document.getElementById("v");
      let failed = null;
      video.addEventListener("error", (event) => { failed = String(event.detail ?? "error"); });
      const settle = (ms = 400) => new Promise((resolve) => setTimeout(resolve, ms));
      await window.__attachAdaptiveMedia(video, "/master.m3u8");
      await video.play().catch(() => {});
      await settle();
      const loaded = window.__adaptiveMediaTracks(video);
      const text = loaded.split("\n").find((line) => line.startsWith("t\t") && line.split("\t")[2] === "pt");
      window.__selectAdaptiveMedia(video, { width: 320, height: 0, peakBitRate: 0, audio: "pt/", text: text.split("\t")[1] });
      await settle();
      const chosen = window.__adaptiveMediaTracks(video);
      window.__selectAdaptiveMedia(video, { width: 0, height: 0, peakBitRate: 0, audio: "en/", text: "off" });
      await settle();
      const off = window.__adaptiveMediaTracks(video);
      const time = video.currentTime;
      window.__detachAdaptiveMedia(video);
      return { failed, loaded, chosen, off, time, after: window.__adaptiveMediaTracks(video) };
    });
    assert.equal(report.failed, null, `the stream failed to load: ${report.failed}`);
    const loaded = tracks(report.loaded);
    assert.deepEqual(loaded.filter(([kind]) => kind === "v").map(([, width, height]) => `${width}x${height}`), ["320x180", "640x360"], "both renditions are listed");
    assert.deepEqual(loaded.filter(([kind]) => kind === "a").map(([, key, , , active]) => `${key}:${active}`), ["en/:1", "pt/:0"], "both audio languages, the default one in use");
    assert.deepEqual(loaded.filter(([kind]) => kind === "t").map(([, , language]) => language).sort(), ["en", "pt"], "both subtitle tracks are listed");
    const chosen = tracks(report.chosen);
    assert.deepEqual(chosen.filter(([kind]) => kind === "a").map(([, key, , , active]) => `${key}:${active}`), ["en/:0", "pt/:1"], "the Portuguese audio is selected");
    assert.deepEqual(chosen.filter(([kind, , , , shown]) => kind === "t" && shown === "1").map(([, , language]) => language), ["pt"], "the Portuguese subtitles are shown");
    const off = tracks(report.off);
    assert.equal(off.filter(([kind, , , , shown]) => kind === "t" && shown === "1").length, 0, "subtitles can be turned off");
    assert.deepEqual(off.filter(([kind]) => kind === "a").map(([, key, , , active]) => `${key}:${active}`), ["en/:1", "pt/:0"], "the English audio is selected again");
    assert.ok(report.time > 0, `the stream plays (currentTime ${report.time})`);
    assert.equal(report.after, "", "a detached element reports no tracks");
    assert.deepEqual(failures.filter((text) => !/play\(\)/.test(text)), [], "no page errors");
    const version = JSON.parse(readFileSync(join(ROOT, "package.json"), "utf8")).devDependencies["shaka-player"];
    console.log(`PASS adaptive media: Shaka ${version} lists and selects renditions, audio and subtitles of a real HLS stream`);
  } finally {
    await browser.close();
    server.stop();
  }
});
