#!/usr/bin/env bun
// The development loop without a Swift build: the live-reload channel in Tools/bun-server.ts and the watcher in
// Tools/dev-watch.mjs, driven by a stand-in build command, in a real browser.
import assert from "node:assert/strict";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { freePort, launch, ROOT, runSuite } from "./browser-test-support.mjs";
import { syncTree } from "./sync-tree.mjs";

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const until = async (check, what, timeout = 15000) => {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await check()) return;
    await sleep(50);
  }
  throw new Error(`timed out waiting for ${what}`);
};
const html = (body, extra = "") => `<!doctype html><html><head><meta charset="utf-8"><title>t</title>${extra}</head><body>${body}</body></html>`;

await runSuite(async () => {
  const work = mkdtempSync(join(tmpdir(), "live-reload-"));
  const children = [];
  const browser = await launch();
  try {
    // ---- sync-tree keeps the modification time of a file whose bytes did not change.
    {
      const from = join(work, "from"), to = join(work, "to");
      mkdirSync(join(from, "a"), { recursive: true });
      writeFileSync(join(from, "a/one.swift"), "one");
      writeFileSync(join(from, "two.swift"), "two");
      assert.deepEqual(syncTree(from, to), { changed: 2, removed: 0, unchanged: 0 });
      const before = Bun.file(join(to, "a/one.swift")).lastModified;
      await sleep(30);
      writeFileSync(join(from, "two.swift"), "two changed");
      writeFileSync(join(from, "three.swift"), "three");
      assert.deepEqual(syncTree(from, to), { changed: 2, removed: 0, unchanged: 1 });
      assert.equal(Bun.file(join(to, "a/one.swift")).lastModified, before, "an unchanged file keeps its modification time");
      rmSync(join(from, "a"), { recursive: true });
      assert.deepEqual(syncTree(from, to), { changed: 0, removed: 1, unchanged: 2 });
      assert.equal(readFileSync(join(to, "two.swift"), "utf8"), "two changed");
    }

    // ---- The channel: the server with a token injects the script, reloads, swaps css, shows and clears build errors.
    {
      const bundle = join(work, "bundle");
      mkdirSync(bundle);
      writeFileSync(join(bundle, "index.html"), html("<p id=v>v1</p>", '<link rel="stylesheet" href="/s.css">'));
      writeFileSync(join(bundle, "s.css"), "body{color:rgb(1, 2, 3)}");
      const port = await freePort();
      const token = "secret-token";
      const server = Bun.spawn([process.execPath, join(ROOT, "Tools/bun-server.ts"), bundle, String(port)], {
        env: { ...process.env, PORT: String(port), SWIFTUIWEB_LIVE_RELOAD_TOKEN: token }, stdout: "ignore", stderr: "ignore",
      });
      children.push(server);
      const base = `http://127.0.0.1:${port}`;
      await until(async () => (await fetch(base).then((r) => r.ok).catch(() => false)), "the server");
      const notify = (type, message, withToken = token) => fetch(`${base}/__livereload/notify?token=${withToken}`, { method: "POST", body: JSON.stringify({ type, message }) });

      assert.match(await (await fetch(base)).text(), /<script src="\/__livereload\.js"><\/script><\/head>/, "the page script is injected");
      assert.equal((await notify("reload", undefined, "wrong")).status, 403, "a wrong token is refused");
      assert.equal((await notify("explode")).status, 400, "an unknown event is refused");

      const page = await browser.newPage();
      const reloads = [];
      page.on("framenavigated", (frame) => { if (frame === page.mainFrame()) reloads.push(frame.url()); });
      await page.goto(base);
      await page.evaluate(() => { window.__marker = "kept"; });
      await until(async () => (await (await notify("build-ok")).json()).listeners >= 1, "the page to connect to the stream");

      // reload
      writeFileSync(join(bundle, "index.html"), html("<p id=v>v2</p>", '<link rel="stylesheet" href="/s.css">'));
      await notify("reload");
      await until(async () => (await page.locator("#v").textContent().catch(() => "")) === "v2", "the page to reload with v2");
      assert.equal(await page.evaluate(() => window.__marker), undefined, "a reload starts a new page");

      // css swap: no navigation, the page keeps its state
      await until(async () => (await (await notify("build-ok")).json()).listeners >= 1, "the reloaded page to reconnect");
      await page.evaluate(() => { window.__marker = "kept"; });
      writeFileSync(join(bundle, "s.css"), "body{color:rgb(9, 8, 7)}");
      await notify("css");
      await until(async () => (await page.evaluate(() => getComputedStyle(document.body).color)) === "rgb(9, 8, 7)", "the stylesheet to swap");
      assert.equal(await page.evaluate(() => window.__marker), "kept", "a css swap keeps the page state");

      // The overlay is one box for two states: "Building..." while a build runs, the compiler output when it fails.
      // Visible is not enough to tell them apart, so a test that waits for the error waits for its text.
      const overlayText = () => page.locator("#live-reload-overlay").textContent({ timeout: 1000 }).catch(() => "");
      await notify("build-start");
      await until(async () => (await overlayText()) === "Building\u2026", "the building overlay");
      await notify("build-error", "error: cannot find 'Foo' in scope");
      await until(async () => (await overlayText()).includes("cannot find 'Foo' in scope"), "the error overlay");
      assert.match(await page.locator("#live-reload-overlay").textContent(), /cannot find 'Foo' in scope/);
      assert.match(await page.locator("#v").textContent(), /v2/, "the last good page stays underneath");
      await notify("build-ok");
      await until(async () => !(await page.locator("#live-reload-overlay").count()), "the overlay to clear");

      // Literal replacements. The page has no module, so it takes none and reloads when the build ends: "missed".
      // A page that connects between the replacements and the end of the build loaded the bundle from before them, so the
      // channel sends them to it again; after the build nothing is pending.
      const received = async (opened) => { await opened.evaluate(() => { window.__taken = []; globalThis.__swiftuiwebLiveLiterals = (text) => { window.__taken.push(text); return 1; }; }); };
      await received(page);
      assert.equal((await notify("literals", "7\ts\tfirst")).status, 200);
      await until(async () => (await page.evaluate(() => window.__taken.length)) === 1, "the open page to get the replacement");
      const late = await browser.newPage();
      await late.addInitScript(() => { window.__taken = []; globalThis.__swiftuiwebLiveLiterals = (text) => { window.__taken.push(text); return 1; }; });
      await late.goto(base);
      await until(async () => (await late.evaluate(() => window.__taken.join("|"))) === "7\ts\tfirst", "a page that connects during the build to get it too");
      await notify("literals-built");
      const afterBuild = await browser.newPage();
      await afterBuild.addInitScript(() => { window.__taken = []; globalThis.__swiftuiwebLiveLiterals = (text) => { window.__taken.push(text); return 1; }; });
      await afterBuild.goto(base);
      await until(async () => (await (await notify("build-ok")).json()).listeners >= 3, "the third page to connect");
      assert.deepEqual(await afterBuild.evaluate(() => window.__taken), [], "a page that loads the built bundle gets nothing again");
      // A replacement text is sent whole or not at all.
      assert.equal((await notify("literals", "7\ts\t" + "x".repeat(60_000))).status, 200, "a long text is not cut");
      await until(async () => (await page.evaluate(() => window.__taken.at(-1)?.length)) === 60_004, "the long replacement to arrive whole");
      assert.equal((await notify("literals", "x".repeat(200_001))).status, 413, "a text over the limit is refused");
      await notify("literals-built");
      // A module that could not use a replacement leaves a mark in the session's storage; the page reloads when the build ends.
      await page.evaluate(() => { window.__marker = "kept"; sessionStorage.setItem("swui:14:swiftuiweb.dev:literals-stale", "1"); });
      await notify("literals-built");
      await until(async () => (await page.evaluate(() => window.__marker).catch(() => "navigating")) === undefined, "the page with an unusable replacement to reload");
      await until(async () => (await page.evaluate(() => sessionStorage.getItem("swui:14:swiftuiweb.dev:literals-stale")).catch(() => "navigating")) === null, "the reloaded page, with the mark taken");
      // The mark can arrive after the build ended (the worker's write is mirrored a moment later): the page still reloads.
      await until(async () => (await (await notify("build-ok")).json()).listeners >= 3, "the reloaded page to reconnect");
      await page.evaluate(() => { window.__marker = "kept"; });
      await notify("literals-built");
      await new Promise((done) => setTimeout(done, 400));
      assert.equal(await page.evaluate(() => window.__marker), "kept", "nothing to reload for yet");
      await page.evaluate(() => { sessionStorage.setItem("swui:14:swiftuiweb.dev:literals-stale", "1"); });
      await until(async () => (await page.evaluate(() => window.__marker).catch(() => "navigating")) === undefined, "a mark that arrives after the build to reload the page");
      await late.close();
      await afterBuild.close();
      await page.close();
    }

    // ---- A server without a token serves the page untouched and has no live-reload routes.
    {
      const bundle = join(work, "plain");
      mkdirSync(bundle);
      writeFileSync(join(bundle, "index.html"), html("<p>plain</p>"));
      const port = await freePort();
      const server = Bun.spawn([process.execPath, join(ROOT, "Tools/bun-server.ts"), bundle, String(port)], { env: { ...process.env, PORT: String(port) }, stdout: "ignore", stderr: "ignore" });
      children.push(server);
      const base = `http://127.0.0.1:${port}`;
      await until(async () => (await fetch(base).then((r) => r.ok).catch(() => false)), "the plain server");
      assert.doesNotMatch(await (await fetch(base)).text(), /__livereload/);
      assert.notEqual((await fetch(`${base}/__livereload.js`)).headers.get("content-type")?.startsWith("text/javascript"), true);
    }

    // ---- The watcher: edit a file, the page reloads; break the build, the overlay shows; fix it, it recovers.
    {
      const pkg = join(work, "pkg");
      mkdirSync(join(pkg, "Sources"), { recursive: true });
      writeFileSync(join(pkg, "Sources/page.txt"), "first");
      writeFileSync(join(pkg, "Sources/style.css"), "body{color:rgb(1, 1, 1)}");
      const bundle = join(work, "watch-bundle");
      const port = await freePort();
      // The stand-in build: fails when the page text says BREAK, otherwise renders the page from the sources.
      const buildCommand = [
        // The failing build also writes a lowering report that locates the text's declaration at original line 10, and
        // prints an error in that declaration (line 2 of it): the watcher must show it at line 11.
        `if grep -q BREAK "${pkg}/Sources/page.txt"; then mkdir -p "${pkg}/.build/embedded-source-lowering" && printf '%s' '{"sourceMap":[{"source":"Sources/page.txt","virtualFiles":{"Sources/page.txt|S.func.m()":10}}]}' > "${pkg}/.build/embedded-source-lowering/app-report.json" && echo "Sources/page.txt|S.func.m():2:5: error: located boom" >&2; echo "error: boom in page.txt" >&2; exit 1; fi`,
        `mkdir -p "$SWIFTUIWEB_WATCH_BUNDLE"`,
        `printf '<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="/style.css"></head><body><p id=v>%s</p></body></html>' "$(cat "${pkg}/Sources/page.txt")" > "$SWIFTUIWEB_WATCH_BUNDLE/index.html"`,
        `cp "${pkg}/Sources/style.css" "$SWIFTUIWEB_WATCH_BUNDLE/style.css"`,
        // What each successful build saw of the toolchain-report switch: only the first one may run the report.
        `printf 'x%s\n' "\${SWIFTUIWEB_SKIP_TOOLCHAIN_REPORT:-}" >> "${pkg}/toolchain-report.log"`,
      ].join(" && ");
      const output = [];
      const watcher = Bun.spawn([process.execPath, join(ROOT, "Tools/dev-watch.mjs"), "--package-root", pkg, "--product", "Fake", "--port", String(port), "--debounce", "100"], {
        env: {
          ...process.env, SWIFTUIWEB_WATCH_BUILD_COMMAND: buildCommand, SWIFTUIWEB_WATCH_BUNDLE: bundle,
          SWIFTUIWEB_WATCH_ROOTS: join(pkg, "Sources"), SWIFTUIWEB_BUILD_ROOT: join(pkg, ".build"),
        },
        stdout: "pipe", stderr: "pipe",
      });
      children.push(watcher);
      const drain = async (stream) => { for await (const chunk of stream) output.push(new TextDecoder().decode(chunk)); };
      drain(watcher.stdout);
      drain(watcher.stderr);
      const base = `http://127.0.0.1:${port}`;
      try {
        await until(async () => (await fetch(base).then((r) => r.text()).catch(() => "")).includes(">first<"), "the first build to be served", 20000);
        const page = await browser.newPage();
        await page.goto(base);
        assert.equal(await page.locator("#v").textContent(), "first");
        await page.evaluate(() => { window.__marker = "kept"; });
        await until(async () => (await page.evaluate(() => performance.now())) > 0, "the page");
        await sleep(400); // let the page connect to the stream

        writeFileSync(join(pkg, "Sources/page.txt"), "second");
        await until(async () => (await page.locator("#v").textContent().catch(() => "")) === "second", "the page to reload after a save");

        writeFileSync(join(pkg, "Sources/page.txt"), "BREAK");
        // The watcher shows "Building..." in the same box before the error arrives: wait for the error text.
        await until(async () => /boom in page\.txt/.test(await page.locator("#live-reload-overlay").textContent({ timeout: 1000 }).catch(() => "")), "the build error overlay");
        assert.match(await page.locator("#live-reload-overlay").textContent(), /Sources\/page\.txt:11:5: error: located boom/, "a located error shows at its original line");
        assert.equal(await page.locator("#v").textContent(), "second", "the last good bundle stays on screen");

        writeFileSync(join(pkg, "Sources/page.txt"), "third");
        await until(async () => (await page.locator("#v").textContent().catch(() => "")) === "third", "the page to recover after the fix");
        await until(async () => !(await page.locator("#live-reload-overlay").count()), "the overlay to clear");

        await page.evaluate(() => { window.__marker = "kept"; });
        writeFileSync(join(pkg, "Sources/style.css"), "body{color:rgb(5, 6, 7)}");
        await until(async () => (await page.evaluate(() => getComputedStyle(document.body).color)) === "rgb(5, 6, 7)", "a css-only save to swap the stylesheet");
        assert.equal(await page.evaluate(() => window.__marker), "kept", "a css-only save does not reload the page");
        const reportLog = readFileSync(join(pkg, "toolchain-report.log"), "utf8").trim().split("\n");
        assert.ok(reportLog.length >= 3, `expected several builds, saw ${reportLog}`);
        assert.equal(reportLog[0], "x", "the first build checks the toolchain");
        assert.deepEqual([...new Set(reportLog.slice(1))], ["x1"], "later builds skip the toolchain report");
        await page.close();
      } catch (error) {
        console.error(output.join("").slice(-3000));
        throw error;
      }
    }
    // ---- dev-refresh-styles: the sources it takes, what it refuses (3) without writing, and its failures (1).
    {
      const fw = join(work, "refresh-framework"), pkg = join(work, "refresh-package"), bundle = join(work, "refresh-bundle");
      mkdirSync(join(fw, "Tools"), { recursive: true });
      for (const script of ["build-styles.mjs", "scope-resize-transitions.mjs"]) copyFileSync(join(ROOT, "Tools", script), join(fw, "Tools", script));
      writeFileSync(join(fw, "Tools/styles.css"), "body{margin:0}\n");
      writeFileSync(join(fw, "Tools/showcase.css"), "h1{color:rgb(1, 2, 3)}\n");
      mkdirSync(join(pkg, "Resources"), { recursive: true });
      mkdirSync(join(pkg, "Sources"), { recursive: true });
      writeFileSync(join(pkg, "Resources/app.css"), "p{color:rgb(4, 5, 6)}\n");
      writeFileSync(join(pkg, "Sources/extra.css"), "i{}\n");
      writeFileSync(join(pkg, "Sources/page.swift"), "let x = 1\n");
      mkdirSync(bundle);
      writeFileSync(join(bundle, "index.html"), "<p>page</p>");
      writeFileSync(join(bundle, "styles.css"), "stale styles");
      writeFileSync(join(bundle, "app.css"), "stale app");
      const read = (name) => readFileSync(join(bundle, name), "utf8");
      const refresh = (files, { product = "Fake", bundleDir = bundle, configuration = "debug", extra = [] } = {}) => {
        const env = { ...process.env, CONFIGURATION: configuration };
        delete env.SWIFTUIWEB_RESOURCES;
        const args = [join(ROOT, "Tools/dev-refresh-styles.mjs"), "--bundle", bundleDir, "--package-root", pkg, "--product", product, "--framework-root", fw, ...extra];
        if (files) args.push("--files", files.join(","));
        const result = Bun.spawnSync([process.execPath, ...args], { env, stdout: "pipe", stderr: "pipe" });
        return { code: result.exitCode, text: result.stdout.toString() + result.stderr.toString() };
      };

      // The framework stylesheet: styles.css is rebuilt; the application's copy is not touched.
      writeFileSync(join(fw, "Tools/styles.css"), "body{margin:7px}\n");
      let result = refresh([join(fw, "Tools/styles.css")]);
      assert.equal(result.code, 0, result.text);
      assert.match(read("styles.css"), /body\{margin:7px\}/);
      assert.equal(read("app.css"), "stale app");

      // The application's stylesheet in the resources directory is copied to the bundle.
      writeFileSync(join(pkg, "Resources/app.css"), "p{color:rgb(9, 9, 9)}\n");
      result = refresh([join(pkg, "Resources/app.css")]);
      assert.equal(result.code, 0, result.text);
      assert.equal(read("app.css"), "p{color:rgb(9, 9, 9)}\n");
      assert.match(read("styles.css"), /body\{margin:7px\}/);

      // A stylesheet the bundle does not have yet (an app.css added after the first build) needs the link the launcher
      // writes into index.html, so the fast path declines it: exit 3, nothing copied.
      rmSync(join(bundle, "app.css"));
      assert.equal(refresh([join(pkg, "Resources/app.css")]).code, 3, "a new app.css goes to the build");
      assert.equal(existsSync(join(bundle, "app.css")), false, "a declined new stylesheet is not copied");
      writeFileSync(join(bundle, "app.css"), "p{color:rgb(9, 9, 9)}\n");

      // Anything that is not a stylesheet source makes it stand down: exit 3, and no file changes, even the good one.
      const before = { styles: read("styles.css"), app: read("app.css") };
      writeFileSync(join(pkg, "Resources/app.css"), "p{color:rgb(8, 8, 8)}\n");
      for (const files of [
        [join(pkg, "Sources/extra.css")],
        [join(pkg, "Resources/app.css"), join(pkg, "Sources/extra.css")],
        [join(pkg, "Sources/page.swift")],
        [join(fw, "Tools/showcase.css")],
      ]) {
        result = refresh(files);
        assert.equal(result.code, 3, `${files.join(", ")}: ${result.text}`);
        assert.equal(read("styles.css"), before.styles, "a refused save writes no styles.css");
        assert.equal(read("app.css"), before.app, "a refused save writes no app.css");
      }

      // ShowcaseApp copies its own stylesheet; any other product refuses it.
      writeFileSync(join(fw, "Tools/showcase.css"), "h1{color:rgb(3, 2, 1)}\n");
      assert.equal(refresh([join(fw, "Tools/showcase.css")]).code, 3);
      result = refresh([join(fw, "Tools/showcase.css")], { product: "ShowcaseApp" });
      assert.equal(result.code, 0, result.text);
      assert.equal(read("showcase.css"), "h1{color:rgb(3, 2, 1)}\n");

      // No bundle yet, or a release configuration (its stylesheets are pruned against the build manifest): exit 3.
      assert.equal(refresh([join(pkg, "Resources/app.css")], { bundleDir: join(work, "no-bundle") }).code, 3);
      assert.equal(refresh([join(pkg, "Resources/app.css")], { configuration: "release" }).code, 3);

      // Usage errors are 2; a broken source is a failure (1), not a refusal.
      assert.equal(refresh(null).code, 2, "--files is required");
      writeFileSync(join(fw, "Tools/styles.css"), "body{/*\n");
      const kept = read("styles.css");
      result = refresh([join(fw, "Tools/styles.css")]);
      assert.equal(result.code, 1, result.text);
      assert.match(result.text, /build-styles\.mjs failed/);
      assert.equal(read("styles.css"), kept, "a failed refresh leaves styles.css as the build left it");
    }

    // ---- The stylesheet fast path: a save that changes only .css files refreshes the bundle without the build command.
    {
      const pkg = join(work, "fast-pkg");
      mkdirSync(join(pkg, "Sources"), { recursive: true });
      mkdirSync(join(pkg, "Resources"), { recursive: true });
      writeFileSync(join(pkg, "Sources/page.txt"), "first");
      writeFileSync(join(pkg, "Resources/app.css"), "#v{color:rgb(1, 1, 1)}\n");
      const bundle = join(work, "fast-bundle");
      const counter = join(pkg, "builds.log");
      const builds = () => { try { return readFileSync(counter, "utf8").trim().split("\n").length; } catch { return 0; } };
      const port = await freePort();
      // The stand-in build: counts its runs and renders the page, its app.css and a placeholder styles.css.
      const buildCommand = [
        `echo build >> "${counter}"`,
        `{ ! grep -q BREAK "${pkg}/Sources/page.txt" || { echo "error: boom" >&2; exit 1; }; }`,
        `mkdir -p "$SWIFTUIWEB_WATCH_BUNDLE"`,
        `printf '<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="/styles.css"><link rel="stylesheet" href="/app.css"></head><body><p id=v>%s</p></body></html>' "$(cat "${pkg}/Sources/page.txt")" > "$SWIFTUIWEB_WATCH_BUNDLE/index.html"`,
        `cp "${pkg}/Resources/app.css" "$SWIFTUIWEB_WATCH_BUNDLE/app.css"`,
        `echo "/* stand-in */" > "$SWIFTUIWEB_WATCH_BUNDLE/styles.css"`,
      ].join(" && ");
      const env = {
        ...process.env, SWIFTUIWEB_WATCH_BUILD_COMMAND: buildCommand, SWIFTUIWEB_WATCH_STYLES_FAST_PATH: "1", SWIFTUIWEB_WATCH_BUNDLE: bundle,
        SWIFTUIWEB_WATCH_ROOTS: `${join(pkg, "Sources")}:${join(pkg, "Resources")}`, SWIFTUIWEB_BUILD_ROOT: join(pkg, ".build"),
      };
      delete env.SWIFTUIWEB_RESOURCES;
      const output = [];
      const watcher = Bun.spawn([process.execPath, join(ROOT, "Tools/dev-watch.mjs"), "--package-root", pkg, "--product", "Fake", "--port", String(port), "--debounce", "100"], {
        env, stdout: "pipe", stderr: "pipe",
      });
      children.push(watcher);
      const drain = async (stream) => { for await (const chunk of stream) output.push(new TextDecoder().decode(chunk)); };
      drain(watcher.stdout);
      drain(watcher.stderr);
      const base = `http://127.0.0.1:${port}`;
      try {
        await until(async () => (await fetch(base).then((r) => r.text()).catch(() => "")).includes(">first<"), "the first build to be served", 20000);
        assert.equal(builds(), 1);
        const page = await browser.newPage();
        await page.goto(base);
        await page.evaluate(() => { window.__marker = "kept"; });
        await sleep(400); // let the page connect to the stream
        const color = () => page.evaluate(() => getComputedStyle(document.getElementById("v")).color);
        assert.equal(await color(), "rgb(1, 1, 1)");

        // A stylesheet-only save: the bundle is refreshed, the build command does not run, the page swaps the css.
        writeFileSync(join(pkg, "Resources/app.css"), "#v{color:rgb(9, 9, 9)}\n");
        await until(async () => (await color()) === "rgb(9, 9, 9)", "the fast path to swap the stylesheet");
        await until(() => /\[watch\] refreshed stylesheets in [\d.]+ s/.test(output.join("")), "the refresh log line");
        assert.equal(await page.evaluate(() => window.__marker), "kept", "a css swap keeps the page state");
        assert.equal(builds(), 1, "the build command did not run");
        assert.equal(readFileSync(join(bundle, "app.css"), "utf8"), "#v{color:rgb(9, 9, 9)}\n");

        // A stylesheet outside the known sources falls back to the build, which the page still gets as a css save.
        writeFileSync(join(pkg, "Sources/extra.css"), "p{}\n");
        await until(() => builds() === 2, "the build command to run for an unknown stylesheet");
        await until(async () => (await page.evaluate(() => window.__marker)) === "kept", "the fallback to keep the page");
        assert.match(output.join(""), /stylesheet fast path not used/);

        // After a failed build a stylesheet save builds again and keeps the error: it must not report "build-ok" over
        // Swift sources that are still broken.
        writeFileSync(join(pkg, "Sources/page.txt"), "BREAK");
        await until(() => builds() === 3, "the build to run for the broken source");
        await until(() => (output.join("").match(/build failed/g) ?? []).length === 1, "the failure to be reported");
        writeFileSync(join(pkg, "Resources/app.css"), "#v{color:rgb(7, 7, 7)}\n");
        await until(() => builds() === 4, "a stylesheet save after a failure to run the build");
        await until(() => (output.join("").match(/build failed/g) ?? []).length === 2, "the failure to be reported again");
        assert.equal((output.join("").match(/refreshed stylesheets/g) ?? []).length, 1, "no fast path after a failure");
        // Fixed: the next stylesheet save takes the fast path again.
        writeFileSync(join(pkg, "Sources/page.txt"), "fixed");
        await until(() => builds() === 5, "the build for the fixed source");
        await until(async () => (await fetch(base).then((r) => r.text()).catch(() => "")).includes(">fixed<"), "the fixed page");
        writeFileSync(join(pkg, "Resources/app.css"), "#v{color:rgb(6, 6, 6)}\n");
        await until(() => (output.join("").match(/refreshed stylesheets/g) ?? []).length === 2, "the fast path after a good build");
        assert.equal(builds(), 5, "the fast path is back after a good build");
        await page.close();
      } catch (error) {
        console.error(output.join("").slice(-3000));
        throw error;
      }
    }

    console.log("PASS live reload: sync keeps mtimes, the channel reloads and swaps css, the watcher rebuilds on save, shows build errors and recovers, stylesheet-only saves refresh without the build, dev-refresh-styles exit codes");
  } finally {
    for (const child of children) child.kill();
    await browser.close();
    rmSync(work, { recursive: true, force: true });
  }
});
