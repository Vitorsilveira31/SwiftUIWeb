#!/usr/bin/env bun
// Offline Chromium contract tests for the real browser adapters and docs CSS.
// These do NOT pretend to recompile Swift or test the CSS layout mapper's mathematics (test-css-layout-*.mjs).
// Use test-showcase-live.mjs after a complete build for application verification.
import assert from "node:assert/strict";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const OUT = resolve(process.env.TEST_RESULTS_DIR ?? join(ROOT, ".build/integration-tests"));
mkdirSync(OUT, { recursive: true });
const checks = [];

async function result(name, fn) {
  try {
    const detail = await fn();
    checks.push({ test: name, status: "PASS", detail });
    console.log("PASS", name);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    checks.push({ test: name, status: "FAIL", detail: message });
    console.log("FAIL", name, message.slice(0, 500));
  }
}

async function module(page, path, names, globalName, prefix = "", edit = (code) => code) {
  let code = readFileSync(join(ROOT, path), "utf8");
  code = code.replace(/^import .*?;\s*$/gm, "");
  code = edit(code.replace(/\bexport\s+(?=(?:async\s+)?(?:function|class)\b|(?:const|let|var)\b)/g, ""));
  await page.addScriptTag({ content: `globalThis.${globalName}=(()=>{\n${prefix}\n${code}\nreturn {${names.join(",")}};\n})();` });
}

const STYLE = `*{box-sizing:border-box}html,body{margin:0;padding:0;font-family:system-ui,sans-serif}body{background:var(--color-swu-background);color:var(--color-swu-foreground)}:root{--color-swu-background:white;--color-swu-foreground:#181818;--color-swu-card:white;--color-swu-muted:#f5f5f5;--color-swu-muted-foreground:#606060;--color-swu-border:#ddd;--color-swu-ring:#1670d0}:root[data-color-scheme=dark]{--color-swu-background:#181818;--color-swu-foreground:#fafafa;--color-swu-card:#222;--color-swu-muted:#292929;--color-swu-muted-foreground:#aaa;--color-swu-border:#444}button{font:inherit;color:inherit;border:0;background:transparent;cursor:pointer}h1,h2,p{margin:0}#embedded-app-root{width:100%;min-height:100dvh}.vstack{display:flex;flex-direction:column}.hstack{display:flex;flex-direction:row}.flex-spacer{flex:1}.scroll-view{overflow:auto}.scroll-horizontal{overflow-y:hidden}.presentation-root{position:fixed;z-index:100;left:20px;top:20px;padding:20px;background:white}[data-layout-hidden]{display:none}`;
const SHELL = (topics, cards) => `<div id="embedded-app-root"><div data-native-layout="document" data-docs-part="shell" data-open-url-handler data-embedded-event-id="1"><header data-docs-part="header"><button data-docs-part="menu-toggle" aria-controls="topics">Menu</button><button data-docs-part="brand" data-docs-route="/">SwiftUIWeb</button><div class="flex-spacer"></div><button data-docs-part="header-link" data-docs-route="/layout">Layout</button><button data-docs-part="theme-toggle">Appearance</button></header><div data-docs-part="workspace"><nav id="topics" data-docs-part="sidebar" data-docs-drawer="closed"><button data-docs-part="drawer-close">Close menu</button><input aria-label="Filter" placeholder="Filter topics"><div data-docs-part="group">${topics}</div><div class="flex-spacer"></div><span>Swift Embedded</span></nav><main data-docs-part="main"><article data-docs-part="article"><header data-docs-part="intro"><div data-docs-part="breadcrumb">SwiftUIWeb / Layout</div><h1 data-docs-part="title">Layout</h1><p data-docs-part="summary">Proposal-driven layouts, browser measurement and retained geometry.</p></header><div data-docs-part="examples">${cards}</div><footer data-docs-part="footer">SwiftUIWeb runtime</footer></article></main><aside data-docs-part="toc">On this page</aside></div></div></div>`;

const capitalize = (name) => name.charAt(0).toUpperCase() + name.slice(1).toLowerCase();

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    const errors = [];
    page.on("pageerror", (error) => errors.push(String(error)));
    await page.setContent('<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body></body></html>');
    await page.addStyleTag({ content: STYLE });
    await page.addStyleTag({ content: readFileSync(join(ROOT, "Tools/showcase.css"), "utf8") });
    await module(page, "Tools/showcase-host.js", ["mountShowcaseHost"], "Docs");
    await module(page, "Tools/css-layout.js", ["CssLayout"], "CssLayoutModule");
    // layout-host.js imports the document scroll (a touch screen's page scroll view); the module is handed to it by name.
    await module(page, "Tools/document-scroll.js", ["DocumentScroll"], "DocumentScrollModule");
    await module(page, "Tools/layout-host.js", ["SemanticLayoutHost", "ownsLayoutStyle", "ownsLayoutAttribute"], "Layout", "const {DocumentScroll}=globalThis.DocumentScrollModule;");
    await module(page, "Tools/host-interactions.js", ["FocusCoordinator", "ScrollCoordinator", "KeyboardShortcutCoordinator", "HistoryCoordinator"], "Interactions");
    // The coordinators embedded-dom.js loads after the first screen (deferred-hosts.js), under the same global.
    await module(page, "Tools/presentation-host.js", ["PresentationCoordinator"], "InteractionsPresentation");
    await module(page, "Tools/transfer-host.js", ["NativeDragDropCoordinator", "shareContent", "moveFiles", "reopenMovedFile"], "InteractionsTransfer");
    await page.evaluate(() => Object.assign(Interactions, InteractionsPresentation, InteractionsTransfer));
    const topics = ["", "layout", "state", "themes", "responsive", "components", "forms", "collections", "navigation", "presentation", "advanced"]
      .map((name) => `<button data-docs-part="topic" data-docs-route="/${name}"` + (name === "layout" ? ' aria-current="page"' : "") + `>${capitalize(name)}</button>`).join("");
    const cards = Array.from({ length: 12 }, (_, i) => `<section data-docs-part="example"><h2 data-docs-part="example-title">Example ${i}</h2><div data-docs-part="preview"><p>Real documentation host CSS, without changing demo layout.</p></div></section>`).join("");
    await page.locator("body").evaluate((e, html) => { e.innerHTML = html; }, SHELL(topics, cards));
    for (const width of [1440, 1200, 1024, 800, 768, 430, 390, 320]) {
      await page.setViewportSize({ width, height: 900 });
      for (const theme of ["light", "dark"]) {
        await page.evaluate((value) => { document.documentElement.dataset.colorScheme = value; }, theme);
        await result(`docs ${width}px ${theme}: full width and one document scroll`, async () => {
          const data = await page.evaluate(() => {
            const q = (role) => document.querySelector('[data-docs-part="' + role + '"]');
            const r = q("header").getBoundingClientRect();
            const s = q("sidebar");
            return {
              viewport: innerWidth, header: r.width, overflow: document.documentElement.scrollWidth - innerWidth,
              sidebarVisible: getComputedStyle(s).display !== "none", sidebarHeight: s.getBoundingClientRect().height,
              menuVisible: getComputedStyle(q("menu-toggle")).display !== "none", mainOverflow: getComputedStyle(q("main")).overflowY,
              bg: getComputedStyle(q("header")).backgroundColor,
            };
          });
          const info = JSON.stringify(data);
          assert.ok(Math.abs(data.header - width) < 1, info);
          assert.ok(data.overflow <= 1, info);
          assert.equal(data.sidebarVisible, width >= 1000, info);
          assert.equal(data.menuVisible, width < 1000, info);
          assert.equal(data.mainOverflow, "visible", info);
          if (width >= 1000) assert.ok(data.sidebarHeight <= 836.1, info);
          return data;
        });
      }
    }
    await page.setViewportSize({ width: 390, height: 844 });
    await page.evaluate(() => {
      globalThis.docsEvents = [];
      let location = new URL("https://fixture.test/layout");
      const history = { state: null, replaceState(s, _, url) { this.state = s; location = new URL(url, location); }, pushState(s, _, url) { this.state = s; location = new URL(url, location); } };
      const hostWindow = new Proxy(window, { get(t, k) { if (k === "history") return history; if (k === "location") return location; const v = t[k]; return typeof v === "function" && !/^[A-Z]/.test(k) ? v.bind(t) : v; } });
      globalThis.docsHost = Docs.mountShowcaseHost(document.querySelector("#embedded-app-root"), { window: hostWindow, document, dispatchNamed: (...args) => docsEvents.push(args.slice(1)) });
      document.querySelector('[data-docs-part="menu-toggle"]').onclick = () => { document.querySelector('[data-docs-part="sidebar"]').dataset.docsDrawer = "open"; docsHost.sync(); };
      document.querySelector('[data-docs-part="drawer-close"]').onclick = () => { document.querySelector('[data-docs-part="sidebar"]').dataset.docsDrawer = "closed"; docsHost.sync(); };
      docsHost.sync();
    });
    await result("mobile drawer lifecycle", async () => {
      await page.locator('[data-docs-part="menu-toggle"]').click(); await page.waitForTimeout(80);
      assert.equal(await page.locator('[data-docs-part="sidebar"]').getAttribute("aria-modal"), "true");
      assert.ok(await page.locator('[data-docs-part="main"]').evaluate((e) => e.inert));
      assert.equal(await page.locator('[data-docs-part="backdrop"]').count(), 1);
      await page.keyboard.press("Escape"); await page.waitForTimeout(50);
      assert.equal(await page.locator('[data-docs-part="backdrop"]').count(), 0);
      assert.ok(!(await page.locator('[data-docs-part="main"]').evaluate((e) => e.inert)));
      assert.ok(await page.locator('[data-docs-part="menu-toggle"]').evaluate((e) => document.activeElement === e));
      return "Drawer opens, inerts main, Escape closes and restores focus";
    });
    await page.screenshot({ path: join(OUT, "docs-contract-mobile.png") });
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.screenshot({ path: join(OUT, "docs-contract-desktop.png") });
    await page.evaluate(() => { docsHost.dispose(); document.body.innerHTML = ""; });
    await result("application presentations are semantic roots, proposed their content box", () => page.evaluate(() => {
      const root = document.createElement("div");
      root.innerHTML = '<main data-layout-kind="zstack" data-embedded-node-id="app"><span aria-hidden="true" data-layout-leaf="text" data-embedded-node-id="background">Background</span><div class="presentation-root"><div class="presentation-content" style="width:400px;height:600px;padding:20px"><div data-layout-kind="vstack" data-embedded-node-id="sheet-content"></div></div></div></main>';
      document.body.append(root);
      const host = new Layout.SemanticLayoutHost(root, { cssLayout: (document, reports) => new CssLayoutModule.CssLayout(document, reports) });
      const roots = host.roots();
      if (roots.length !== 2 || roots[1].getAttribute("data-embedded-node-id") !== "sheet-content") throw Error("Application presentation content omitted");
      const proposal = host.cssRootProposal(roots[1]);
      if (proposal?.key !== "presentation" || !proposal.def.x || !proposal.def.y) throw Error("Presentation content is proposed its content box: " + JSON.stringify(proposal));
      host.dispose(); root.remove(); return { roots: roots.length, proposal };
    }));
    await result("scrollTo: correct owner, repeated request, pending virtual target", () => page.evaluate(() => {
      const root = document.createElement("div");
      root.innerHTML = '<div data-embedded-scroll-id="9" data-embedded-scroll-sequence="1"></div><div class="scroll-view scroll-vertical" style="height:160px;width:240px;border:2px solid"><div style="height:1200px;position:relative"><button data-view-id="9" style="position:absolute;top:900px">Target</button></div></div>';
      document.body.append(root);
      const ack = [], prepared = [];
      const s = new Interactions.ScrollCoordinator(root, { dispatch: () => {}, ack: (x) => ack.push(x), prepare: (x) => prepared.push(x) });
      const y = scrollY; s.sync();
      const host = root.querySelector(".scroll-view");
      if (host.scrollTop < 700 || scrollY !== y || ack[0] !== 1) throw Error("Wrong scroll owner/ack");
      const request = root.firstElementChild;
      request.setAttribute("data-embedded-scroll-sequence", "2"); s.sync();
      if (ack.length !== 2) throw Error("Repeated request lost");
      request.setAttribute("data-embedded-scroll-sequence", "3"); request.setAttribute("data-embedded-scroll-id", "missing"); s.sync();
      if (ack.length !== 2 || prepared[0] !== "missing") throw Error("Missing target acknowledged");
      const target = host.querySelector("button"); target.setAttribute("data-view-id", "missing"); s.sync();
      if (ack.at(-1) !== 3) throw Error("Pending target not retried");
      s.dispose(); root.remove(); return { ack, prepared, documentScrollUnchanged: true };
    }));
    await result("focus requests wait for a publication that reflects the last focus change", () => page.evaluate(() => {
      const root = document.createElement("div");
      root.innerHTML = '<input id="email" data-focused="true" data-focus-request="true"><input id="password">';
      document.body.append(root);
      const email = root.querySelector("#email"), password = root.querySelector("#password");
      let awaiting = false; const focus = new Interactions.FocusCoordinator(root, { awaiting: () => awaiting });
      // The person moved to the password field; Swift still reports the e-mail field focused. Until a
      // publication reflects the move, the stale request must not pull focus back.
      password.focus(); awaiting = true;
      if (focus.sync() || document.activeElement !== password) throw Error("A stale focus request stole focus");
      if (focus.trace.deferred !== 1) throw Error("Deferral not traced");
      // Once Swift has seen the move it reports the password field and no move is needed.
      awaiting = false; email.removeAttribute("data-focused"); email.removeAttribute("data-focus-request");
      password.setAttribute("data-focused", "true"); password.setAttribute("data-focus-request", "true");
      if (focus.sync() || document.activeElement !== password) throw Error("A reflected focus moved focus");
      // A genuine request for another field is honored once nothing is outstanding.
      password.removeAttribute("data-focused"); password.removeAttribute("data-focus-request");
      email.setAttribute("data-focused", "true"); email.setAttribute("data-focus-request", "true");
      if (!focus.sync() || document.activeElement !== email) throw Error("A programmatic focus request was ignored");
      focus.dispose(); root.remove(); return focus.trace;
    }));
    await result("presentation lifecycle and focus", async () => {
      await page.evaluate(() => {
        document.body.innerHTML = '<button id="opener">Open</button><div id="modal-root"><button id="background">Background</button><div class="presentation-root alert-panel" data-embedded-event-id="1"><h2>Alert</h2><button id="cancel">Cancel</button><button id="ok">OK</button></div></div>';
        document.querySelector("#opener").focus();
        globalThis.modalEvents = [];
        globalThis.modal = new Interactions.PresentationCoordinator(document.querySelector("#modal-root"), (e, name) => { modalEvents.push(name); e.remove(); modal.sync(); });
        modal.sync();
      });
      assert.ok(await page.locator("#background").evaluate((e) => e.inert));
      await page.keyboard.press("Shift+Tab");
      assert.ok(await page.locator("#ok").evaluate((e) => document.activeElement === e));
      // The alert re-renders while focus is inside it; focus must still return to the opener, not to a control of the alert.
      await page.evaluate(() => modal.sync());
      await page.keyboard.press("Escape"); await page.waitForTimeout(30);
      assert.equal(await page.locator(".presentation-root").count(), 0);
      assert.deepEqual(await page.evaluate("modalEvents"), ["presentation-dismiss"]);
      assert.ok(await page.locator("#opener").evaluate((e) => document.activeElement === e));
      await page.evaluate(() => modal.dispose());
      return "Escape, trap, binding event and focus restoration";
    });
    await result("presentation returns focus to a pressed control that never took focus", async () => {
      // Safari does not focus a button on click: the document stays on the body, so the control that was
      // pressed to present is the one focus returns to.
      await page.evaluate(() => {
        document.body.innerHTML = '<div id="modal-root"><button id="opener">Open</button><div id="slot"></div></div>';
        globalThis.modal = new Interactions.PresentationCoordinator(document.querySelector("#modal-root"), (e) => { e.remove(); modal.sync(); });
        document.activeElement?.blur();
        document.querySelector("#opener").dispatchEvent(new PointerEvent("pointerdown", { bubbles: true }));
        document.querySelector("#slot").innerHTML = '<div class="presentation-root alert-panel" data-embedded-event-id="1"><button id="cancel">Cancel</button></div>';
        modal.sync();
      });
      assert.ok(await page.locator("#cancel").evaluate((e) => document.activeElement === e));
      await page.keyboard.press("Escape"); await page.waitForTimeout(30);
      assert.equal(await page.locator(".presentation-root").count(), 0);
      assert.ok(await page.locator("#opener").evaluate((e) => document.activeElement === e));
      await page.evaluate(() => modal.dispose());
      return "focus returns to the pressed control when the body had focus";
    });
    await result("ShareLink capability, URL, cancellation and fallback", () => page.evaluate(async () => {
      const b = document.createElement("button");
      b.setAttribute("data-share-item", "https://example.test/article"); b.setAttribute("data-share-subject", "Read");
      let data;
      const a = await Interactions.shareContent(b, { share: async (x) => data = x });
      if (data.url !== "https://example.test/article" || a.status !== "shared") throw Error("URL lost");
      const c = await Interactions.shareContent(b, { share: async () => { throw new DOMException("Cancelled", "AbortError"); } });
      if (c.status !== "cancelled") throw Error("Cancellation became error");
      let copied;
      const d = await Interactions.shareContent(b, { clipboard: { writeText: async (s) => copied = s } });
      if (d.status !== "copied" || copied !== data.url) throw Error("Clipboard fallback failed");
      return [a, c, d];
    }));
    await result("native drag/drop MIME, child transitions and typed transfer wire", () => page.evaluate(async () => {
      document.body.innerHTML = '<div id="drop-root"><div data-drop-target="true" data-drop-types="public.text" data-embedded-event-id="7">Target <span>Child</span></div></div>';
      const root = document.querySelector("#drop-root"), target = root.firstElementChild, events = [];
      const d = new Interactions.NativeDragDropCoordinator(root, (e, n, v) => events.push([n, v]));
      const data = new DataTransfer();
      data.setData("text/plain", "A: B\nC");
      const over = new DragEvent("dragover", { bubbles: true, cancelable: true, dataTransfer: data });
      target.dispatchEvent(over);
      if (!over.defaultPrevented) throw Error("Accepted drag did not prevent browser default");
      target.dispatchEvent(new DragEvent("dragover", { bubbles: true, cancelable: true, dataTransfer: data }));
      target.querySelector("span").dispatchEvent(new DragEvent("dragleave", { bubbles: true, relatedTarget: target, dataTransfer: data }));
      if (events.filter((x) => x[0] === "embeddedDropTargeted").length !== 1) throw Error("Targeted state flickers on child transition");
      target.dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: data, clientX: 10, clientY: 20 }));
      await new Promise((r) => setTimeout(r, 30));
      const raw = events.find((x) => x[0] === "embeddedDrop")?.[1];
      if (!raw?.startsWith("v2:") || !raw.includes(btoa("text/plain"))) throw Error("Typed payload missing");
      const bad = new DataTransfer();
      bad.setData("application/json", "{}");
      const denied = new DragEvent("dragover", { bubbles: true, cancelable: true, dataTransfer: bad });
      target.dispatchEvent(denied);
      if (denied.defaultPrevented) throw Error("Rejected type captured drop");
      d.dispose(); root.remove();
      return { targetedEvents: events.filter((x) => x[0] === "embeddedDropTargeted"), wire: raw };
    }));
    await module(page, "Tools/tab-shell.js", ["AdaptiveTabShell"], "TabShell");
    await module(page, "Tools/first-paint-host.js", ["takeFirstPaint"], "FirstPaint");
    await module(page, "Tools/geometry-host.js", ["GeometryHost", "measurementPayload"], "Geometry");
    await module(page, "Tools/text-layout-host.js", ["textLayoutPayload", "paintKey", "clearFontMetrics"], "TextLayout");
    await module(page, "Tools/event-value.js", ["writeEventValue", "readSecureBytes", "readSecureIDs", "concatBytes"], "EventValue");
    await module(page, "Tools/media-host.js", ["MediaHost"], "Media");
    await module(page, "Tools/split-view-host.js", ["SplitViewHost"], "SplitView"); await module(page, "Tools/lottie-host.js", ["LottieHost", "loadLottie", "parseLoop", "readConfig"], "Lottie");
    await module(page, "Tools/transition-host.js", ["TransitionHost", "ScrollTransitionHost", "MatchedGeometryHost", "matchViewTransitionGeometry", "SCROLL_TRANSITION_ATTRIBUTES"], "Transitions");
    await module(page, "Tools/binary-atoms.generated.js", ["BINARY_VERSION", "BINARY_ATOMS_HASH", "BINARY_OPS", "BINARY_NAMESPACES", "BINARY_ATOMS"], "BinaryAtoms");
    await module(page, "Tools/binary-publication.js", ["BinaryBuffer", "BinaryFormatError", "isBinary", "isEmptyUpdate", "sameBinary", "readPublication", "rootHoverRules", "scanRecords", "Builder", "Handles", "compareDom"], "BinaryPublication",
      "const {BINARY_VERSION,BINARY_ATOMS_HASH,BINARY_OPS,BINARY_NAMESPACES,BINARY_ATOMS}=BinaryAtoms;");
    // The fake hosts below publish the trees their markup describes as binary ROOT publications, as Swift does.
    await module(page, "Tests/EmbeddedUI/binary-root.js", ["binaryRoot"], "BinaryRoot",
      "const {BINARY_VERSION,BINARY_ATOMS_HASH,BINARY_OPS,BINARY_NAMESPACES,BINARY_ATOMS}=BinaryAtoms;");
    await module(page, "Tools/embedded-dom.js", ["mountEmbeddedBrowser"], "DOM",
      "const {BINARY_OPS}=BinaryAtoms;const {CssLayout}=CssLayoutModule;const {writeEventValue,readSecureBytes,concatBytes}=EventValue;const {MediaHost}=Media;const {SplitViewHost}=SplitView;const {LottieHost}=Lottie;const {TransitionHost,ScrollTransitionHost,MatchedGeometryHost,matchViewTransitionGeometry}=Transitions;const {GeometryHost}=Geometry;const {SemanticLayoutHost,ownsLayoutStyle,ownsLayoutAttribute}=Layout;const {FocusCoordinator,ScrollCoordinator,PresentationCoordinator,KeyboardShortcutCoordinator,HistoryCoordinator,NativeDragDropCoordinator,shareContent,moveFiles}=Interactions;const {AdaptiveTabShell}=TabShell;const {takeFirstPaint}=FirstPaint;const {BinaryBuffer,BinaryFormatError,Builder,Handles,isEmptyUpdate,sameBinary,readPublication,rootHoverRules,scanRecords,compareDom}=BinaryPublication;",
      // The import() of the hosts the first screen does not run resolves to the modules loaded above.
      (code) => code.replace("import(new URL('./deferred-hosts.js', import.meta.url).href)", "Promise.resolve({...Interactions, ...TextLayout})"));
    await result("geometry host: coordinate-space records, scroll-driven position updates and resize changes", () => page.evaluate(async () => {
      document.body.innerHTML = '<div id="groot"><div id="scroller" class="scroll-view scroll-vertical" data-coordinate-space="scroll" style="height:100px;overflow:auto;border:2px solid"><div style="height:40px"></div><div id="reader" data-geometry-reader="true" data-geometry-position="true" data-embedded-event-id="7" data-embedded-events="geometry" style="height:30px"></div><div id="size" data-geometry-reader="true" data-embedded-event-id="8" data-embedded-events="geometry" style="height:20px"></div><div id="change" data-geometry-change="1" data-embedded-event-id="9" data-embedded-events="geometryChange" style="height:10px"></div><div style="height:600px"></div></div></div>';
      const frames = (n) => new Promise((r) => { const step = () => --n <= 0 ? r() : requestAnimationFrame(step); requestAnimationFrame(step); });
      const root = document.querySelector("#groot"), scroller = document.querySelector("#scroller"), calls = [];
      const host = new Geometry.GeometryHost(root, { dispatch: (el, name, value) => calls.push({ id: el.id, name, value }), eventIdAttribute: "data-embedded-event-id", eventsAttribute: "data-embedded-events" });
      const parse = (value) => { const [head, ...records] = value.split("\u001e"); const n = (s) => s.split(",").map(Number); return { box: n(head), spaces: records.map((r) => { const [kind, name, b] = r.split("\u001f"); return { kind, name, box: n(b) }; }) }; };
      const inSpace = (value, kind, name) => { const m = parse(value), s = m.spaces.find((x) => x.kind === kind && x.name === name); if (!s) throw Error(`missing ${kind}:${name} in ${JSON.stringify(m)}`); return m.box[1] - s.box[1]; };
      host.sync(); await frames(2);
      const first = Object.fromEntries(calls.map((c) => [c.id + ":" + c.name, c.value]));
      if (!first["reader:geometry"] || !first["size:geometry"] || !first["change:geometryChange"]) throw Error(`initial measurement missing: ${JSON.stringify(calls)}`);
      if (calls.length !== 3) throw Error(`duplicate initial measurements: ${JSON.stringify(calls)}`);
      const namedBefore = inSpace(first["reader:geometry"], "n", "scroll"), scrollBefore = inSpace(first["reader:geometry"], "s", "vertical");
      if (Math.abs(namedBefore - 42) > 0.5 || Math.abs(scrollBefore - 40) > 0.5) throw Error(`wrong initial space offsets ${namedBefore} ${scrollBefore}`);
      calls.length = 0; scroller.scrollTop = 25; await frames(3);
      if (calls.length !== 1 || calls[0].id !== "reader") throw Error(`scroll must re-measure only position readers: ${JSON.stringify(calls)}`);
      const namedAfter = inSpace(calls[0].value, "n", "scroll"), scrollAfter = inSpace(calls[0].value, "s", "vertical");
      if (Math.abs(namedAfter - 17) > 0.5 || Math.abs(scrollAfter - 15) > 0.5) throw Error(`scroll offsets did not follow scrollTop: ${namedAfter} ${scrollAfter}`);
      calls.length = 0; document.querySelector("#change").style.height = "24px"; await frames(3);
      if (calls.length !== 1 || calls[0].id !== "change" || calls[0].name !== "geometryChange" || parse(calls[0].value).box[3] !== 24) throw Error(`resize did not report onGeometryChange: ${JSON.stringify(calls)}`);
      // A sync measures after the next layout (in a ResizeObserver delivery), not inside the commit.
      calls.length = 0; host.sync(); if (calls.length) throw Error(`sync measured synchronously: ${JSON.stringify(calls)}`);
      await frames(2); if (calls.length) throw Error(`unchanged sync re-dispatched: ${JSON.stringify(calls)}`);
      document.querySelector("#size").setAttribute("data-embedded-event-id", "80"); host.sync(); await frames(2);
      if (calls.length !== 1 || calls[0].id !== "size") throw Error(`a new event owner must receive the current measurement: ${JSON.stringify(calls)}`);
      host.dispose(); return { namedBefore, namedAfter, scrollBefore, scrollAfter };
    }));
    await result("integrated DOM adapter: retained identity, controlled input and disabled events", () => page.evaluate(async () => {
      document.body.innerHTML = "";
      let count = 0, html = "", buffer = [];
      const memory = new WebAssembly.Memory({ initial: 8 });
      let bytes;
      const draw = () => { html = '<div data-embedded-node-id="root" data-layout-kind="vstack" data-color-scheme="light"><button data-embedded-node-id="button" data-embedded-event-id="42" data-embedded-events="click" type="button">Count ' + count + '</button><input data-embedded-node-id="input" value="retained"></div>'; bytes = BinaryRoot.binaryRoot(html); new Uint8Array(memory.buffer, 1024, bytes.length).set(bytes); };
      draw();
      const exports = { memory };
      for (const [name, f] of Object.entries({ start: () => {}, html_pointer: () => 1024, html_length: () => bytes.length, html_byte: (i) => bytes[i], event_value_reset: () => buffer = [], event_value_push: (b) => buffer.push(b), dispatch: (id) => { if (id === 42) { count++; draw(); } }, dispatch_named: () => {}, viewport: () => {}, scroll_ack: () => {}, history_ack: () => {} })) exports["embedded_browser_" + name] = f;
      const session = DOM.mountEmbeddedBrowser({ exports }, {});
      const button = session.root.querySelector("button"), input = session.root.querySelector("input");
      input.focus(); input.setSelectionRange(2, 4);
      button.dispatchEvent(new MouseEvent("click", { bubbles: true, button: 0 })); session.flush();
      if (count !== 1 || button !== session.root.querySelector("button") || button.textContent !== "Count 1") throw Error("Retained event identity failed");
      if (input !== document.activeElement || input.selectionStart !== 2 || input.selectionEnd !== 4) throw Error("Input focus/selection lost");
      button.setAttribute("disabled", "");
      button.dispatchEvent(new MouseEvent("click", { bubbles: true, button: 0 }));
      if (count !== 1) throw Error("Disabled button dispatched");
      const metrics = { ...session.metrics }; session.dispose(); return { count, metrics };
    }));
    await result("identical HTML still reconciles DOMView updates", () => page.evaluate(() => {
      document.body.innerHTML = ""; let count = 0, html = "", buffer = [], reconciliations = 0;
      const memory = new WebAssembly.Memory({ initial: 8 });
      let bytes;
      const draw = () => { html = '<div data-embedded-node-id="root"><button data-embedded-node-id="button" data-embedded-event-id="42" data-embedded-events="click" type="button">Stable</button></div>'; bytes = BinaryRoot.binaryRoot(html); new Uint8Array(memory.buffer, 1024, bytes.length).set(bytes); };
      draw();
      const exports = { memory };
      for (const [name, f] of Object.entries({ start: () => {}, html_pointer: () => 1024, html_length: () => bytes.length, html_byte: (i) => bytes[i], event_value_reset: () => buffer = [], event_value_push: (b) => buffer.push(b), dispatch: (id) => { if (id === 42) { count++; draw(); } }, dispatch_named: () => {}, webmount_reconcile: () => { reconciliations++; }, viewport: () => {}, scroll_ack: () => {}, history_ack: () => {} })) exports["embedded_browser_" + name] = f;
      const session = DOM.mountEmbeddedBrowser({ exports }, {});
      const initialReconciliations = reconciliations;
      session.root.querySelector("button").dispatchEvent(new MouseEvent("click", { bubbles: true, button: 0 })); session.flush();
      const result = { count, reconciliations, commits: session.metrics.commits, events: session.metrics.events };
      session.dispose();
      if (count !== 1 || reconciliations !== initialReconciliations + 1 || result.commits !== 1 || result.events !== 1) throw Error(`identical HTML skipped web mount update: ${JSON.stringify({ initialReconciliations, ...result })}`);
      return result;
    }));
    const performanceDiagnostics = () => page.evaluate(() => {
      document.body.innerHTML = ""; let count = 0, html = "", buffer = [];
      const memory = new WebAssembly.Memory({ initial: 8 });
      let bytes;
      const draw = () => { html = '<div data-embedded-node-id="root"><button data-embedded-node-id="button" data-embedded-event-id="42" data-embedded-events="click" type="button">Count ' + count + "</button></div>"; bytes = BinaryRoot.binaryRoot(html); new Uint8Array(memory.buffer, 1024, bytes.length).set(bytes); };
      draw();
      const exports = { memory };
      for (const [name, f] of Object.entries({ start: () => {}, html_pointer: () => 1024, html_length: () => bytes.length, html_byte: (i) => bytes[i], event_value_reset: () => buffer = [], event_value_push: (b) => buffer.push(b), dispatch: (id) => { if (id === 42) { count++; draw(); } }, dispatch_named: () => {}, viewport: () => {}, scroll_ack: () => {}, history_ack: () => {}, fiber_metric: (index) => index })) exports["embedded_browser_" + name] = f;
      const session = DOM.mountEmbeddedBrowser({ exports }, { performanceDiagnostics: true });
      session.performanceMetrics.reset();
      session.root.querySelector("button").dispatchEvent(new MouseEvent("click", { bubbles: true, button: 0 })); session.flush();
      const sample = session.performanceMetrics.snapshot(); session.dispose(); return sample;
    });
    await result("performance diagnostics isolate publish, HTML, DOM patch and post-sync phases", async () => {
      const sample = await performanceDiagnostics();
      const info = JSON.stringify(sample);
      const diagnostics = sample.diagnostics;
      assert.ok(diagnostics != null, info);
      assert.ok(diagnostics.htmlCodeUnits > 0, info);
      assert.ok(diagnostics.patchNodeVisits > 0 && diagnostics.patchChildrenPasses > 0, info);
      assert.ok(sample.eventDispatches === 1 && sample.commits === 1, info);
      assert.ok(diagnostics.htmlReadMs >= 0 && diagnostics.htmlParseMs >= 0 && diagnostics.domPatchMs >= 0, info);
      const isNonNegativeNumber = (value) => typeof value === "number" && value >= 0;
      const phases = ["postPatchSyncMs", "browserStateSyncMs", "layoutUpdateMs", "webMountReconcileMs", "geometrySyncMs", "focusSyncMs", "scrollSyncMs", "presentationSyncMs", "historySyncMs", "inputHostSyncMs", "motionSyncMs", "meshSyncMs", "lazySyncMs", "timelineSyncMs", "themeSyncMs", "platformSyncMs", "pluginSyncMs", "commitNotificationMs"];
      assert.ok(phases.every((key) => key in diagnostics && isNonNegativeNumber(diagnostics[key])), info);
      const layoutPhases = ["passes", "passesSkipped", "unlaid", "cssMs"];
      assert.ok(layoutPhases.every((key) => key in sample.layout && isNonNegativeNumber(sample.layout[key])), info);
      const fiber = [["publishedObservationGroupsUnavailable", 28], ["publishedObservationSourceCountMismatches", 29], ["publishedObservationGroupsWithoutActiveOwners", 30], ["publishedObservationUnresolvedOwnerTokens", 31], ["publishedObservationOwnerPathsUnavailable", 32], ["publishedObservationOwnerPathsNotMounted", 33], ["publishedObservationOwnerPathRemaps", 34]];
      for (const [key, expected] of fiber) assert.equal(sample.fiber[key], expected, info);
      return diagnostics;
    });
    await result("performance diagnostics count gesture input, descriptors and RAF flushes", async () => {
      const sample = await page.evaluate(async () => {
        document.body.innerHTML = ""; let dispatches = 0, html = "", buffer = [];
        const memory = new WebAssembly.Memory({ initial: 8 });
        let bytes;
        const draw = () => { html = '<div data-embedded-node-id="root"><div id="drag" data-embedded-node-id="drag" data-embedded-event-id="7" data-embedded-events="drag-0-changed,drag-0-ended" data-gesture-count="1" data-gesture-descriptors="kind=drag;minDistance=1;space=global" data-gesture-event-prefix-0="drag-0">Drag</div></div>'; bytes = BinaryRoot.binaryRoot(html); new Uint8Array(memory.buffer, 1024, bytes.length).set(bytes); };
        draw();
        const exports = { memory };
        for (const [name, f] of Object.entries({ start: () => {}, html_pointer: () => 1024, html_length: () => bytes.length, html_byte: (i) => bytes[i], event_value_reset: () => buffer = [], event_value_push: (b) => buffer.push(b), dispatch: () => {}, dispatch_named: () => { dispatches++; }, viewport: () => {}, scroll_ack: () => {}, history_ack: () => {} })) exports["embedded_browser_" + name] = f;
        const session = DOM.mountEmbeddedBrowser({ exports }, { performanceDiagnostics: true });
        session.performanceMetrics.reset();
        const drag = session.root.querySelector("#drag");
        drag.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, pointerId: 4, button: 0, clientX: 0, clientY: 0 }));
        drag.dispatchEvent(new PointerEvent("pointermove", { bubbles: true, pointerId: 4, button: 0, clientX: 20, clientY: 10 }));
        await new Promise((resolve) => requestAnimationFrame(resolve));
        drag.dispatchEvent(new PointerEvent("pointerup", { bubbles: true, pointerId: 4, button: 0, clientX: 20, clientY: 10 }));
        await new Promise((resolve) => requestAnimationFrame(resolve)); session.flush();
        const result = session.performanceMetrics.snapshot(); result.testDispatches = dispatches; session.dispose(); return result;
      });
      const info = JSON.stringify(sample);
      const diagnostics = sample.diagnostics;
      assert.equal(diagnostics.gesturePointerMoves, 1, info);
      assert.equal(diagnostics.gestureDescriptorIterations, 1, info);
      assert.ok(diagnostics.gestureQueuedValues === 1 && diagnostics.gestureFlushedValues === 1, info);
      assert.ok(diagnostics.gestureFlushFrames === 1 && diagnostics.gestureWasmDispatches === 1, info);
      assert.equal(diagnostics.gestureMaxValuesPerFrame, 1, info);
      assert.ok(diagnostics.gesturePointerMoveMs >= 0 && diagnostics.gestureFrameFlushMs >= 0, info);
      assert.equal(sample.testDispatches, 2, info);
      return diagnostics;
    });
    await result("transient drag stays in browser until one terminal Swift commit; cancel restores", () => page.evaluate(async () => {
      document.body.innerHTML = ""; let position = 0, buffer = [], bytes, dispatches = [];
      const memory = new WebAssembly.Memory({ initial: 8 }), decoder = new TextDecoder();
      const draw = () => { const html = `<div data-embedded-node-id="root"><div id="transient-drag" data-embedded-node-id="drag" data-embedded-event-id="7" data-embedded-events="gesture-drag-0-changed,gesture-drag-0-ended,gesture-drag-0-cancelled" data-gesture-count="1" data-gesture-descriptors="kind=drag;minDistance=1;space=local;transient=true" data-gesture-event-prefix-0="gesture-drag-0" style="position:absolute;left:${position}px;top:0;width:100px;height:40px">Drag</div></div>`; bytes = BinaryRoot.binaryRoot(html); new Uint8Array(memory.buffer, 1024, bytes.length).set(bytes); };
      draw();
      const named = (id, nameLength) => { const raw = decoder.decode(Uint8Array.from(buffer)), name = raw.slice(0, nameLength), value = raw.slice(nameLength); dispatches.push({ id, name, value }); if (name.endsWith("-ended")) { const fields = value.split(",").map(Number), dx = fields[0] - fields[2]; position += dx; draw(); } };
      const exports = { memory };
      for (const [name, f] of Object.entries({ start: () => {}, html_pointer: () => 1024, html_length: () => bytes.length, html_byte: (i) => bytes[i], event_value_reset: () => buffer = [], event_value_push: (b) => buffer.push(b), dispatch: () => {}, dispatch_named: named, viewport: () => {}, scroll_ack: () => {}, history_ack: () => {} })) exports["embedded_browser_" + name] = f;
      const session = DOM.mountEmbeddedBrowser({ exports }, { performanceDiagnostics: true });
      session.performanceMetrics.reset();
      const drag = session.root.querySelector("#transient-drag"), nextFrame = () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      const pointer = (type, id, pointerType, x, y) => drag.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, pointerId: id, pointerType, button: 0, clientX: x, clientY: y }));
      let bounds = drag.getBoundingClientRect(); pointer("pointerdown", 1, "mouse", bounds.left + 10, bounds.top + 10); pointer("pointermove", 1, "mouse", bounds.left + 30, bounds.top + 25); await nextFrame();
      const moved = drag.getBoundingClientRect(); if (Math.abs(moved.left - bounds.left - 20) > 1 || Math.abs(moved.top - bounds.top - 15) > 1) throw Error(`mouse transient translation mismatch: ${JSON.stringify({ before: bounds.toJSON(), after: moved.toJSON(), style: drag.style.translate })}`);
      if (dispatches.length !== 0) throw Error("transient pointermove invoked Swift before gesture ended"); pointer("pointerup", 1, "mouse", bounds.left + 30, bounds.top + 25); await nextFrame(); session.flush(); await nextFrame();
      if (dispatches.length !== 1 || !dispatches[0].name.endsWith("-ended")) throw Error(`expected one terminal Swift event: ${JSON.stringify(dispatches)}`);
      let fields = dispatches[0].value.split(",").map(Number); if (Math.abs(fields[0] - fields[2] - 20) > 0.01 || Math.abs(fields[1] - fields[3] - 15) > 0.01) throw Error(`terminal translation changed after transient transform: ${dispatches[0].value}`);
      if (Math.abs(Number.parseFloat(drag.style.left) - 20) > 0.01 || drag.style.translate) throw Error(`final model position not restored cleanly: ${drag.getAttribute("style")}`);
      bounds = drag.getBoundingClientRect(); pointer("pointerdown", 2, "touch", bounds.left + 10, bounds.top + 10); pointer("pointermove", 2, "touch", bounds.left + 22, bounds.top + 18); await nextFrame();
      if (dispatches.length !== 1) throw Error("touch move invoked Swift before gesture ended"); pointer("pointerup", 2, "touch", bounds.left + 22, bounds.top + 18); await nextFrame(); session.flush(); await nextFrame();
      if (dispatches.length !== 2 || Math.abs(Number.parseFloat(drag.style.left) - 32) > 0.01 || drag.style.translate) throw Error(`touch terminal position failed: ${JSON.stringify({ dispatches, style: drag.getAttribute("style") })}`);
      const positionBeforeCancel = position; bounds = drag.getBoundingClientRect(); pointer("pointerdown", 3, "pen", bounds.left + 10, bounds.top + 10); pointer("pointermove", 3, "pen", bounds.left - 5, bounds.top + 14); await nextFrame();
      if (!drag.style.translate) throw Error("pen transient visual was not applied"); pointer("pointercancel", 3, "pen", bounds.left - 5, bounds.top + 14);
      if (position !== positionBeforeCancel || drag.style.translate) throw Error("cancel persisted partial position or retained transient CSS");
      const sample = session.performanceMetrics.snapshot(), diagnostics = sample.diagnostics;
      if (dispatches.filter((item) => item.name.endsWith("-ended")).length !== 2 || dispatches.filter((item) => item.name.endsWith("-cancelled")).length !== 1) throw Error(`wrong terminal/cancel event count: ${JSON.stringify(dispatches)}`);
      if (diagnostics.gestureQueuedValues !== 0 || diagnostics.gestureWasmDispatches !== 0 || diagnostics.gestureTransientStyleWrites < 3) throw Error(`transient path still dispatches movement events: ${JSON.stringify(diagnostics)}`);
      session.dispose(); return { dispatches: dispatches.map(({ name, value }) => ({ name, translation: value.split(",").slice(0, 4) })), diagnostics };
    }));
    // All expected capability failures are returned as values, never console errors.
    await result("contract console contains no uncaught runtime errors", () => {
      if (errors.length) throw new assert.AssertionError({ message: JSON.stringify(errors) });
      return "clean";
    });
  } finally {
    await browser.close();
  }
  const report = {
    kind: "browser contract verification (not a rebuilt Swift application)", checks,
    passed: checks.filter((c) => c.status === "PASS").length, failed: checks.filter((c) => c.status === "FAIL").length,
    browser: "Chromium", images: "Documentation fixture screenshots, not the rebuilt Showcase WASM",
  };
  writeFileSync(join(OUT, "browser-contract-results.json"), JSON.stringify(report, null, 2));
  if (report.failed) process.exitCode = 1;
});
