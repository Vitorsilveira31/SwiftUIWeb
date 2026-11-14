#!/usr/bin/env bun
// CSS layout of whole semantic roots (Tools/css-layout.js `claimRoot`): an application root holding a `.sidebarAdaptable`
// TabView takes the window and insets the selected tab by the sidebar the stylesheet lays out; a root CSS can no longer
// lay out is released with none of its blocks left behind; a semantic root the host lays out inside an island keeps its
// mutations; the rules of new blocks arrive as appended stylesheets and are merged without moving anything.
//   bun Tools/test-css-layout-roots.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { launch, ROOT, runSuite } from "./browser-test-support.mjs";

const mapper = readFileSync(join(ROOT, "Tools/css-layout.js"), "utf8").replace(/^export /gm, "");
const styles = readFileSync(join(ROOT, "Tools/styles.css"), "utf8");
const text = (value) => `<span data-layout-kind="intrinsic" data-layout-leaf="text" style="font:14px sans-serif">${value}</span>`;
const html = `<div id="embedded-app-root"><div id="app" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf" data-align-x="0.5" data-align-y="0.5">
  <div id="tabs" class="tab-view" data-layout-kind="inset" data-tab-style="sidebar-adaptable" data-tab-layout="sidebar" data-tab-sidebar-expanded="true">
    <div id="body" class="tab-body"><div id="panel" class="tab-panel">
      <div id="screen" class="vstack" data-layout-kind="vstack" data-layout-gap="8" data-align-x="0">
        <div id="bar" class="hstack" data-layout-kind="hstack" data-layout-gap="8">${text("Title")}<div id="spacer" class="flex-spacer" data-layout-kind="spacer" data-spacer-min="8"></div>${text("Action")}</div>
        <div id="fill" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf" data-align-x="0.5" data-align-y="0.5">${text("content")}</div>
      </div>
    </div><div class="tab-panel" data-tab-hidden="true">${text("hidden tab")}</div></div>
    <div id="sidebar" class="tab-sidebar"><div id="slot" data-tab-sidebar-content><div id="slot-root" class="hstack" data-layout-kind="hstack" data-layout-gap="4">${text("User")}</div></div></div>
  </div>
</div></div>`;

await runSuite(async () => {
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1000, height: 700 } });
    await page.setContent(`<style>${styles}</style><body style="margin:0">${html}</body>`);
    await page.addScriptTag({ content: mapper + "\nwindow.CssLayout = CssLayout;" });
    const rect = (id) => page.evaluate((id) => { const r = document.getElementById(id).getBoundingClientRect(); return [r.x, r.y, r.width, r.height].map((v) => Math.round(v * 10) / 10); }, id);
    const claimed = await page.evaluate(() => {
      const css = (window.css = new CssLayout(document));
      const app = document.getElementById("app");
      const ok = css.claimRoot(app, { def: { x: true, y: true }, ax: 0.5, height: "100dvh", key: "window" });
      css.flush();
      return { ok, sheets: css.ruleSheets.length, hidden: document.querySelector('[data-tab-hidden="true"]').hasAttribute("data-cl"), sidebar: document.getElementById("sidebar").hasAttribute("data-cl") };
    });
    assert.equal(claimed.ok, true, "a root of frames, a sidebarAdaptable TabView and stacks is CSS's");
    assert.equal(claimed.hidden, false, "a hidden tab takes no part");
    assert.equal(claimed.sidebar, false, "the sidebar is the stylesheet's");
    assert.deepEqual(await rect("app"), [0, 0, 1000, 700], "the root takes the window");
    const body = await rect("body");
    assert.deepEqual(body, [248, 0, 752, 700], "the selected tab is inset by the expanded sidebar's width");
    const bar = await rect("bar");
    assert.equal(bar[2], 752, "the bar fills the tab's width");
    assert.equal((await rect("spacer"))[3], 0, "a Spacer is flexible along its stack's axis only");
    assert.deepEqual((await rect("fill")).slice(1), [bar[3] + 8, 752, 700 - bar[3] - 8], "a filling frame takes the rest of the screen");
    // Another tab is selected and then the first again: the hidden one keeps its blocks (a global rule gives it its
    // `display: none` back), so showing it again writes nothing below it.
    const switched = await page.evaluate(() => {
      const [first, second] = document.querySelectorAll(".tab-panel"), app = document.getElementById("app"), css = window.css;
      const select = (shown, hidden) => { hidden.setAttribute("data-tab-hidden", "true"); shown.removeAttribute("data-tab-hidden"); css.mark(shown, app); css.mark(hidden, app); css.pending.add(app); css.flush(); };
      select(second, first);
      const hiddenDisplay = getComputedStyle(first).display, shown = second.hasAttribute("data-cl");
      const writes = []; const observer = new MutationObserver((records) => { for (const r of records) if (r.target !== first) writes.push(r.attributeName); });
      observer.observe(first, { subtree: true, attributes: true });
      select(first, second);
      observer.takeRecords().forEach((r) => { if (r.target !== first) writes.push(r.attributeName); }); observer.disconnect();
      return { hiddenDisplay, shown, writes: writes.length, secondDisplay: getComputedStyle(second).display };
    });
    assert.deepEqual(switched, { hiddenDisplay: "none", shown: true, writes: 0, secondDisplay: "none" }, "a hidden tab is not displayed, and showing it again writes nothing below it");
    assert.deepEqual(await rect("body"), body, "back on the first tab");
    // The sidebar collapses to a rail: the stylesheet's width, without the mapper analysing anything.
    await page.evaluate(() => document.getElementById("tabs").setAttribute("data-tab-sidebar-expanded", "false"));
    assert.deepEqual(await rect("body"), [72, 0, 928, 700], "the tab follows the rail's width");

    // A semantic root the host lays out inside the island keeps its mutations.
    const foreign = await page.evaluate(() => {
      const slot = document.getElementById("slot-root"), app = document.getElementById("app");
      const before = window.css.islandOf(slot) === app;
      window.css.setForeign([slot]);
      return { before, after: window.css.islandOf(slot.firstElementChild) };
    });
    assert.equal(foreign.before, true, "without it the island would take the slot's mutations");
    assert.equal(foreign.after, null, "a foreign root's mutations are the host's");

    // New blocks: one appended sheet per assign, merged into one without moving anything.
    const sheets = await page.evaluate(() => {
      const css = window.css, fill = document.getElementById("fill"), app = document.getElementById("app");
      const counts = [];
      for (let i = 0; i < 20; i++) {
        fill.setAttribute("data-frame-min-h", String(100 + i));
        css.mark(fill, app); css.pending.add(app); css.flush();
        counts.push(css.ruleSheets.length);
      }
      return { counts, adopted: document.adoptedStyleSheets.length };
    });
    assert.ok(sheets.counts.every((count, i) => i === 0 || count >= sheets.counts[i - 1]), `each new block appends a sheet (${sheets.counts})`);
    const beforeMerge = await rect("fill");
    const merged = await page.evaluate(() => { window.css.mergeRules(); return { rules: window.css.ruleSheets.length, adopted: document.adoptedStyleSheets.length }; });
    assert.equal(merged.rules, 1, "merged into one sheet");
    // Rules Swift sent (`.sl<n>`, see `_CSSLayoutEmitter`) survive the merge.
    const swift = await page.evaluate(() => {
      const css = window.css, probe = document.createElement("div");
      probe.className = "sl900"; document.body.append(probe);
      css.adoptSwiftRules(".sl900{width:123px!important}\n");
      const before = probe.getBoundingClientRect().width;
      css.mergeRules();
      const after = probe.getBoundingClientRect().width; probe.remove();
      return { before, after };
    });
    assert.deepEqual(swift, { before: 123, after: 123 }, "Swift's rules are kept when the sheets are merged");
    // A sidebar slot element's block in a collapsed rail (`.sr<n>`) applies only inside a collapsed tab view, and survives
    // the merge too.
    const railRule = await page.evaluate(() => {
      const css = window.css, shell = document.createElement("div"), probe = document.createElement("div");
      shell.className = "tab-view"; shell.setAttribute("data-tab-sidebar-expanded", "true");
      probe.className = "sl901 sr902"; shell.append(probe); document.body.append(shell);
      css.adoptSwiftRules(".sl901{width:50px!important}\n.sr902{width:20px!important}\n");
      const width = () => probe.getBoundingClientRect().width;
      const expanded = width();
      shell.setAttribute("data-tab-sidebar-expanded", "false");
      const collapsed = width();
      css.mergeRules();
      const merged = width(); shell.remove();
      return { expanded, collapsed, merged };
    });
    assert.deepEqual(railRule, { expanded: 50, collapsed: 20, merged: 20 }, "a rail rule applies in a collapsed rail only, and survives the merge");
    assert.equal(merged.adopted, 2, "the mapper's global rules and its blocks");
    assert.deepEqual(await rect("fill"), beforeMerge, "merging moves nothing");

    // Something CSS cannot express appears: the root is released, with no block left behind.
    const released = await page.evaluate(() => {
      // A modifier that holds several views (a vstack of its own on the host), which one grid cell does not express.
      const css = window.css, app = document.getElementById("app"), nested = document.createElement("div");
      nested.setAttribute("data-layout-kind", "padding"); nested.innerHTML = "<span>a</span><span>b</span>";
      document.getElementById("screen").append(nested);
      css.mark(nested.parentElement, app); css.pending.add(app); css.flush();
      return { released: css.released.includes(app), left: document.querySelectorAll("[data-cl]").length, island: css.islands.has(app) };
    });
    assert.deepEqual(released, { released: true, left: 0, island: false }, "a root CSS cannot lay out is the host's again, with no block left");
    // A NavigationStack: the stylesheet's title and the bar items share the bar row above the screen; a pushed screen
    // replaces the root (which the stylesheet hides); a hidden bar reserves no space.
    const stack = (attributes, items, pushed) => `<div id="nav-app" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf"><main id="stack" class="navigation-stack" ${attributes}>
      ${items}<div class="navigation-root"${pushed ? ' aria-hidden="true"' : ""}><div id="root-screen" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf">${text("Root")}</div></div>
      ${pushed ? `<div class="navigation-destination" data-navigation-depth="1"><div id="pushed" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf">${text("Pushed")}</div></div>` : ""}</main></div>`;
    const item = (id, placement, label) => `<div id="${id}" class="toolbar-item" data-toolbar-placement="${placement}"><button style="width:40px;height:40px">${label}</button></div>`;
    const navCase = async (markup) => page.evaluate((markup) => {
      document.body.innerHTML = markup;
      document.adoptedStyleSheets = []; // an earlier mapper's `[data-cl-n]` rules would style these elements
      const css = new CssLayout(document), app = document.getElementById("nav-app");
      const ok = css.claimRoot(app, { def: { x: true, y: true }, ax: 0.5, height: "100dvh", key: "window" }); css.flush();
      const box = (id) => { const e = document.getElementById(id); if (!e || !e.getClientRects().length) return null; const r = e.getBoundingClientRect(); return [r.x, r.y, r.width, r.height].map((v) => Math.round(v)); };
      const stack = document.getElementById("stack");
      return { ok, unsupported: css.stats.unsupported, title: Math.round(parseFloat(getComputedStyle(stack, "::before").height) || 0), before: getComputedStyle(stack, "::before").display, leading: box("leading"), trailing: box("trailing"), empty: box("empty"), root: box("root-screen"), pushed: box("pushed") };
    }, markup);
    const inline = await navCase(stack('data-navigation-depth="0" data-navigation-title="Inbox" data-navigation-title-display-mode="inline"', item("leading", "navigation-bar-leading", "L") + item("trailing", "navigation-bar-trailing", "T") + '<div id="empty" class="toolbar-item" data-toolbar-placement="navigation-bar-trailing"></div>', false));
    assert.equal(inline.ok, true, "a NavigationStack with a title and bar items is CSS's");
    const row = Math.max(inline.title, inline.leading[3]);
    assert.equal(inline.leading[0], 0, "a leading item starts the bar");
    assert.equal(inline.trailing[0] + inline.trailing[2], 1000, "a trailing item ends it");
    assert.equal(inline.leading[1], Math.round((row - inline.leading[3]) / 2), "items are centred in the title row");
    assert.equal(inline.empty, null, "an item with nothing to show is not shown");
    assert.deepEqual(inline.root.slice(1), [row, 1000, 700 - row], "the screen takes what the bar leaves");
    const pushed = await navCase(stack('data-navigation-depth="1" data-navigation-title="Detail" data-navigation-title-display-mode="inline"', item("leading", "navigation-bar-leading", "Back"), true));
    assert.equal(pushed.ok, true, "a pushed screen over a hidden root is CSS's");
    assert.equal(pushed.root, null, "the root screen is not shown under a pushed one");
    assert.deepEqual(pushed.pushed.slice(1), [Math.max(pushed.title, pushed.leading[3]), 1000, 700 - Math.max(pushed.title, pushed.leading[3])], "the pushed screen takes what the bar leaves");
    const hidden = await navCase(stack('data-navigation-depth="0" data-navigation-title="" data-navigation-bar-hidden="true" data-navigation-title-display-mode="automatic"', "", false));
    assert.deepEqual({ before: hidden.before, root: hidden.root }, { before: "none", root: [0, 0, 1000, 700] }, "a hidden bar reserves no space");
    // A pushed screen replaces its root whether or not the stylesheet hides it (the host's rule: the depth decides, and a
    // presentation's focus isolation can restore a root's `aria-hidden`): the root takes no part and is not shown, whether the
    // stack is a NavigationStack or a legacy NavigationView, in a `main` or not.
    for (const [tag, classes] of [["main", "navigation-stack"], ["main", "navigation-stack navigation-view"], ["div", "navigation-view"]]) {
      const shown = await page.evaluate(({ tag, classes }) => {
        document.body.innerHTML = `<div id="nav-app" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf"><${tag} id="stack" class="${classes}" data-navigation-depth="1" data-navigation-title="Detail" data-navigation-title-display-mode="inline">
          <div class="toolbar-item" data-toolbar-placement="navigation-bar-leading"><button style="width:40px;height:40px">Back</button></div>
          <div id="root" class="navigation-root"><div id="root-screen" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf"><span>Root</span></div></div>
          <div id="inactive" class="navigation-destination" data-navigation-depth="1" data-navigation-inactive="true"><span>Inactive</span></div>
          <div class="navigation-destination navigation-presented" data-navigation-depth="2"><div id="presented" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf"><span>Presented</span></div></div></${tag}></div>`;
        document.adoptedStyleSheets = []; // an earlier mapper's `[data-cl-n]` rules would style these elements
        const css = new CssLayout(document);
        const ok = css.claimRoot(document.getElementById("nav-app"), { def: { x: true, y: true }, ax: 0.5, height: "100dvh", key: "window" }); css.flush();
        const stack = document.getElementById("stack"), box = (id) => { const r = document.getElementById(id).getBoundingClientRect(), s = stack.getBoundingClientRect(); return [r.x - s.x, r.y - s.y, r.width, r.height].map(Math.round); };
        const bar = Math.max(parseFloat(getComputedStyle(stack, "::before").height) || 0, 40);
        return { ok, unsupported: css.stats.unsupported, root: document.getElementById("root").getClientRects().length, presented: box("presented"), bar, width: Math.round(stack.getBoundingClientRect().width), height: Math.round(stack.getBoundingClientRect().height) };
      }, { tag, classes });
      assert.deepEqual([shown.ok, shown.unsupported, shown.root], [true, {}, 0], `a pushed ${tag}.${classes} over a root the stylesheet shows is CSS's, and the root is not shown`);
      assert.deepEqual(shown.presented, [0, Math.round(shown.bar), shown.width, shown.height - Math.round(shown.bar)], `the presented screen takes what the bar of a ${tag}.${classes} leaves`);
    }
    // A collapsed rail's bottom bar keeps the first view of each stack, centred; a presentation's root takes its content box.
    const rail = await page.evaluate(() => {
      document.body.innerHTML = `<div class="tab-view" data-tab-style="sidebar-adaptable" data-tab-layout="sidebar" data-tab-sidebar-expanded="false"><div class="tab-sidebar"><div class="tab-sidebar-bottom-bar-content" data-tab-sidebar-content style="width:72px">
        <div id="rail-root" class="hstack" data-layout-kind="hstack" data-layout-gap="8"><div id="avatar" data-layout-kind="size" data-size-w="32" data-size-h="32"></div><span id="name" data-layout-kind="intrinsic" data-layout-leaf="text">Signed-in user</span></div></div></div></div>`;
      document.adoptedStyleSheets = []; // an earlier mapper's `[data-cl-n]` rules would style these elements
      const css = new CssLayout(document), root = document.getElementById("rail-root"), slot = root.parentElement;
      const ok = css.claimRoot(root, { def: { x: true, y: false }, ax: 0.5, height: "auto", key: "rail" }); css.flush();
      const r = (e) => { const b = e.getBoundingClientRect(); return [b.x - slot.getBoundingClientRect().x - parseFloat(getComputedStyle(slot).paddingLeft), b.width]; };
      return { ok, name: getComputedStyle(document.getElementById("name")).display, root: r(root), avatar: r(document.getElementById("avatar")), content: slot.clientWidth - parseFloat(getComputedStyle(slot).paddingLeft) - parseFloat(getComputedStyle(slot).paddingRight) };
    });
    assert.equal(rail.ok, true, "a collapsed rail's slot content is CSS's");
    assert.equal(rail.name, "none", "the rail keeps only the first view of the stack");
    assert.deepEqual(rail.root.map(Math.round), [Math.round((rail.content - 32) / 2), 32], "what is left is centred in the rail");
    const sheet = await page.evaluate(() => {
      document.body.innerHTML = `<div class="presentation-root"><div class="sheet-panel" style="display:flex;flex-direction:column;width:400px;height:500px"><div class="presentation-content" style="padding:20px 24px">
        <div id="sheet-root" class="vstack" data-layout-kind="vstack" data-layout-gap="8"><div data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf"><span data-layout-kind="intrinsic" data-layout-leaf="text">Sheet</span></div></div></div></div></div>`;
      document.adoptedStyleSheets = []; // an earlier mapper's `[data-cl-n]` rules would style these elements
      const css = new CssLayout(document), root = document.getElementById("sheet-root");
      const ok = css.claimRoot(root, { def: { x: true, y: true }, ax: 0.5, height: "cell", key: "presentation" }); css.flush();
      const b = root.getBoundingClientRect(), content = root.parentElement, c = content.getBoundingClientRect(), cs = getComputedStyle(content);
      const inner = [c.x + content.clientLeft + parseFloat(cs.paddingLeft), c.y + content.clientTop + parseFloat(cs.paddingTop),
        content.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight), content.clientHeight - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom)];
      return { ok, box: [b.x, b.y, b.width, b.height].map(Math.round), inner: inner.map(Math.round) };
    });
    assert.equal(sheet.ok, true, "a presentation's root is CSS's");
    assert.deepEqual(sheet.box, sheet.inner, "a presentation's root takes its content box");
    // The layout tree of a table cell is proposed nothing: it is as wide as its content, which the column cannot shrink. A view in a
    // chart's foreignObject is placed by the flex box Swift justified and aligned. An alert's message is as wide as the content it
    // shares with the actions and as tall as it needs.
    const hosted = await page.evaluate(() => {
      document.body.innerHTML = `<table style="width:100px"><tbody><tr><td><div id="cell-root" class="hstack" data-layout-kind="hstack" data-layout-gap="8"><span id="cell-text" data-layout-kind="intrinsic" data-layout-leaf="text" style="font:14px sans-serif">A cell wider than its column</span></div></td></tr></tbody></table>
        <svg width="300" height="100"><foreignObject width="300" height="100"><div id="fo-box" style="display:flex;justify-content:center;align-items:flex-end;width:100%;height:100%"><div id="fo-root" data-layout-kind="size" data-size-w="40" data-size-h="20"></div></div></foreignObject></svg>
        <div class="presentation-content" style="width:300px;padding:0"><div id="message" class="presentation-message"><span id="message-text" data-layout-kind="intrinsic" data-layout-leaf="text" style="font:14px sans-serif">A short message</span></div><div class="presentation-actions"><button>OK</button></div></div>`;
      document.adoptedStyleSheets = []; // an earlier mapper's `[data-cl-n]` rules would style these elements
      const css = new CssLayout(document), rect = (id) => { const r = document.getElementById(id).getBoundingClientRect(); return [r.x, r.y, r.width, r.height].map((v) => Math.round(v * 2) / 2); };
      const ok = [
        css.claimRoot(document.getElementById("cell-root"), { def: { x: false, y: false }, ax: 0, height: "auto", key: "cell", ideal: true }),
        css.claimRoot(document.getElementById("fo-root"), { def: { x: true, y: true }, ax: 0.5, height: "100%", key: "foreign", aligned: true }),
        css.claimRoot(document.getElementById("message"), { def: { x: true, y: false }, ax: 0.5, height: "auto", key: "message" })];
      css.flush();
      return { ok, cell: rect("cell-root"), text: rect("cell-text"), foreign: rect("fo-root"), box: rect("fo-box"), message: rect("message"), messageText: rect("message-text") };
    });
    assert.deepEqual(hosted.ok, [true, true, true], "a table cell's tree, a foreignObject's view and an alert's message are CSS's");
    assert.ok(hosted.cell[2] > 100 && hosted.cell[2] === hosted.text[2], "a table cell's tree keeps its ideal width in a column narrower than it");
    assert.deepEqual(hosted.foreign, [hosted.box[0] + (hosted.box[2] - 40) / 2, hosted.box[1] + hosted.box[3] - 20, 40, 20], "a foreignObject's view is centred and at the bottom, as its box aligns it");
    assert.deepEqual([hosted.message[0], hosted.message[2]], [0, 300], "an alert's message is as wide as the content it shares with the actions (the host measures a composite leaf at the width it is offered)");
    assert.equal(hosted.message[1] + hosted.message[3], hosted.messageText[1] + hosted.messageText[3], "and as tall as its text");
    // Several items on one side sit side by side, 8 px apart, in the order they were declared (as the host places them):
    // the bar row gets a column for each.
    const sides = await navCase(stack('data-navigation-depth="0" data-navigation-title="Orders" data-navigation-title-display-mode="inline"',
      item("leading", "navigation-bar-leading", "L") + item("t1", "automatic", "A") + item("t2", "automatic", "B"), false).replace('id="trailing"', ""));
    const sideBoxes = await page.evaluate(() => Object.fromEntries(["leading", "t1", "t2", "root-screen"].map((id) => { const r = document.getElementById(id).getBoundingClientRect(); return [id, [r.x, r.width].map(Math.round)]; })));
    assert.equal(sides.ok, true, "a bar with several items on one side is CSS's");
    assert.equal(sideBoxes.leading[0], 0, "the leading item at the start");
    assert.equal(sideBoxes.t2[0] + sideBoxes.t2[1], sideBoxes["root-screen"][0] + sideBoxes["root-screen"][1], "the last trailing item at the end");
    assert.equal(sideBoxes.t1[0] + sideBoxes.t1[1] + 8, sideBoxes.t2[0], "the one before it 8 px to its left");
    assert.equal(sideBoxes["root-screen"][0], 0, "the screen spans the whole row");
    // Principal items together with several items on a side: a track for each item on a side, 8 px apart, and the principals side
    // by side between two equal flexible tracks. With blocks of equal width on both sides, the host's placement: leading items
    // from the start, trailing items from the end, the principals as a group centred on the bar, after the leading items and 8 px
    // at the earliest. With unequal blocks the group is centred between them, not on the bar. The mapper refuses nothing.
    const wide = (id, placement, width) => `<div id="${id}" class="toolbar-item" data-toolbar-placement="${placement}"><button style="width:${width}px;height:40px">${id}</button></div>`;
    const crowded = async (widths) => {
      const [l1, l2, p1, p2, t1, t2] = widths;
      const result = await navCase(stack('data-navigation-depth="0" data-navigation-title="Orders" data-navigation-title-display-mode="inline"',
        wide("l1", "navigation-bar-leading", l1) + wide("l2", "navigation-bar-leading", l2) + wide("p1", "principal", p1) + wide("p2", "principal", p2) +
        wide("t1", "navigation-bar-trailing", t1) + wide("t2", "navigation-bar-trailing", t2), false));
      const x = await page.evaluate(() => Object.fromEntries(["l1", "l2", "p1", "p2", "t1", "t2"].map((id) => { const r = document.getElementById(id).getBoundingClientRect(); return [id, [r.x, r.width]]; })));
      return { result, x };
    };
    const at = (x, id) => x[id][0], right = (x, id) => x[id][0] + x[id][1];
    const equal = await crowded([60, 80, 70, 90, 80, 60]);
    assert.deepEqual([equal.result.ok, equal.result.unsupported], [true, {}], "a bar of principal items and several items on each side is CSS's");
    const group = Math.max(equal.x.l1[1] + equal.x.l2[1] + 16, 500 - (equal.x.p1[1] + equal.x.p2[1]) / 2);
    assert.deepEqual([at(equal.x, "l1"), at(equal.x, "l2"), at(equal.x, "p1"), at(equal.x, "p2")].map(Math.round), [0, equal.x.l1[1] + 8, group, group + equal.x.p1[1]].map(Math.round), "leading items from the start, 8 px apart, the principals centred on the bar and touching");
    assert.deepEqual([right(equal.x, "t2"), right(equal.x, "t1") + 8].map(Math.round), [1000, at(equal.x, "t2")].map(Math.round), "trailing items from the end, 8 px apart");
    const unequal = await crowded([60, 80, 70, 90, 120, 100]);
    const between = (1000 - (unequal.x.p1[1] + unequal.x.p2[1]) + (unequal.x.l1[1] + unequal.x.l2[1] + 16) - (unequal.x.t1[1] + unequal.x.t2[1] + 16)) / 2;
    assert.equal(Math.round(at(unequal.x, "p1")), Math.round(between), "unequal blocks: the group is centred between them");
    const long = await crowded([200, 180, 70, 90, 80, 60]);
    assert.ok(at(long.x, "p1") >= long.x.l1[1] + long.x.l2[1] + 16 && right(long.x, "t2") === 1000, "beside long leading items the group starts 8 px after them at the earliest, and the trailing items keep to the end");
    // A screen taller than its stack starts below the bar, as on the host, instead of being centred above it.
    const tall = await page.evaluate(() => {
      document.body.innerHTML = `<div id="nav-app" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf"><main id="stack" class="navigation-stack" data-navigation-depth="0" data-navigation-title="Orders" data-navigation-title-display-mode="inline">
        <div class="navigation-root"><div id="tall" data-layout-kind="size" data-size-w="200" data-size-h="2000"></div></div></main></div>`;
      document.adoptedStyleSheets = []; // an earlier mapper's `[data-cl-n]` rules would style these elements
      const css = new CssLayout(document);
      const ok = css.claimRoot(document.getElementById("nav-app"), { def: { x: true, y: true }, ax: 0.5, height: "100dvh", key: "window" }); css.flush();
      const stack = document.getElementById("stack"), r = document.getElementById("tall").getBoundingClientRect();
      return { ok, top: Math.round(r.y - stack.getBoundingClientRect().y), bar: Math.round(parseFloat(getComputedStyle(stack, "::before").height) || 0), left: Math.round(r.x) };
    });
    assert.equal(tall.ok, true);
    assert.equal(tall.top, tall.bar, "a screen taller than its stack starts below the bar");
    assert.equal(tall.left, 400, "and is still centred across");
    // A NavigationSplitView is a `flexible` leaf whose columns the stylesheet's grid lays out: the island keeps that display.
    const split = await page.evaluate(() => {
      document.body.innerHTML = `<div id="split-app" data-layout-kind="frame" data-frame-min-w="600" data-frame-min-h="450"><div id="split" class="navigation-split-view" data-layout-kind="flexible" data-column-count="2">
        <div id="sidebar-column" class="navigation-column navigation-sidebar" data-navigation-column="sidebar"><span>Sidebar</span></div>
        <div id="detail-column" class="navigation-column navigation-detail" data-navigation-column="detail"><span>Detail</span></div></div></div>`;
      document.adoptedStyleSheets = []; // an earlier mapper's `[data-cl-n]` rules would style these elements
      const css = new CssLayout(document), app = document.getElementById("split-app");
      const ok = css.claimRoot(app, { def: { x: true, y: true }, ax: 0.5, height: "100dvh", key: "window" }); css.flush();
      const x = (id) => Math.round(document.getElementById(id).getBoundingClientRect().x);
      return { ok, display: getComputedStyle(document.getElementById("split")).display, sidebar: x("sidebar-column") <= 1, detail: x("detail-column") > x("sidebar-column") };
    });
    assert.deepEqual(split, { ok: true, display: "grid", sidebar: true, detail: true }, "a split view keeps the stylesheet's grid of columns");
    // A List's ScrollView holds its rows, which the host stacks in a vstack of its own (spacing 0, leading): CSS makes
    // them the rows of the ScrollView's grid, from the top, each as tall as its view.
    const list = await page.evaluate(() => {
      document.body.innerHTML = `<div id="list" class="list-view scroll-view scroll-vertical" data-layout-kind="scroll" style="height:300px">
        <span id="r1" data-layout-kind="intrinsic" data-layout-leaf="text" style="font:14px sans-serif">One</span>
        <div id="r2" data-layout-kind="frame" data-frame-max-w="inf" data-frame-h="40" data-align-x="0.5" data-align-y="0.5"><span data-layout-kind="intrinsic" data-layout-leaf="text">Two</span></div>
        <span id="r3" data-layout-kind="intrinsic" data-layout-leaf="text" style="font:14px sans-serif">Three</span></div>`;
      document.adoptedStyleSheets = []; // an earlier mapper's `[data-cl-n]` rules would style these elements
      const css = new CssLayout(document), list = document.getElementById("list");
      const ok = css.claim(list); css.flush();
      const cs = getComputedStyle(list), inner = list.getBoundingClientRect();
      const left = inner.x + list.clientLeft + parseFloat(cs.paddingLeft), top = inner.y + list.clientTop + parseFloat(cs.paddingTop);
      const box = (id) => { const r = document.getElementById(id).getBoundingClientRect(); return [r.x - left, r.y - top, r.width, r.height].map(Math.round); };
      return { ok, r1: box("r1"), r2: box("r2"), r3: box("r3"), width: Math.round(list.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight)) };
    });
    assert.equal(list.ok, true, "a ScrollView holding several rows is CSS's");
    assert.deepEqual([list.r1[0], list.r1[1]], [0, 0], "the first row at the top leading corner");
    assert.deepEqual([list.r2[0], list.r2[1], list.r2[2], list.r2[3]], [0, list.r1[3], list.width, 40], "a filling row as wide as the list, below the first");
    assert.deepEqual([list.r3[0], list.r3[1]], [0, list.r1[3] + 40], "the next row below it, leading");
    // A Section's header of two views is a padding wrapper holding a vstack of its own (spacing 0, leading: what the host's
    // `@group` is, see `_semanticHeld`), and three fixed frames are two elements, not a chain (`_SemanticLayers.isFoldable`):
    // both are CSS's, with the rectangles the host gives the shapes it stacked.
    const held = await page.evaluate(() => {
      const label = (id, value) => `<span id="${id}" data-layout-kind="intrinsic" data-layout-leaf="text" style="font:14px sans-serif">${value}</span>`;
      document.body.innerHTML = `<div id="island" class="scroll-view scroll-vertical" data-layout-kind="scroll" style="width:300px;height:300px">
        <div id="heading" data-layout-kind="padding" data-padding-top="4" data-padding-bottom="4" data-padding-leading="16" data-padding-trailing="16">
          <div class="vstack" data-layout-kind="vstack" data-layout-gap="0" data-align-x="0" style="align-items:flex-start">${label("h1", "Header")}${label("h2", "A second, longer line")}</div></div>
        <div id="f100" data-layout-kind="frame" data-frame-w="100" data-align-x="0.5" data-align-y="0.5"><div id="f60" data-layout-kind="frame" data-frame-w="60" data-align-x="0.5" data-align-y="0.5" data-layout-wrap="frame;frame-w=30|padding;padding-leading=4">${label("t", "x")}</div></div></div>`;
      document.adoptedStyleSheets = [];
      const css = new CssLayout(document), island = document.getElementById("island");
      const ok = css.claim(island); css.flush();
      const rect = (id) => { const r = document.getElementById(id).getBoundingClientRect(), o = island.getBoundingClientRect(); return [r.x - o.x, r.y - o.y, r.width, r.height].map((v) => Math.round(v * 10) / 10); };
      return { ok, heading: rect("heading"), h1: rect("h1"), h2: rect("h2"), f100: rect("f100"), f60: rect("f60") };
    });
    assert.equal(held.ok, true, "a padding holding a vstack of two views, and the frames of a chain Swift keeps apart, are CSS's");
    assert.deepEqual([held.h1[0], held.h1[1]], [16, 4], "the first view at the padding's leading top corner");
    assert.deepEqual([held.h2[0], held.h2[1]], [16, 4 + held.h1[3]], "the second right below it, leading, with no spacing");
    assert.equal(held.heading[3], 8 + held.h1[3] + held.h2[3], "the padding is as tall as the two views and its insets");
    assert.deepEqual([held.f100[2], held.f60[2]], [100, 60], "each frame of the chain has its own width");
    // A user-defined Layout is a box of the size Swift wrote, whose subviews are roots of their own (`item`): proposed what the
    // Layout placed them with (nothing, a width, a width and a height), pinned by their anchors from the size they take. The
    // page tells Swift the proposal the Layout is offered and the sizes its subviews took (`reportLayouts`).
    const custom = await page.evaluate(() => {
      const label = (id, value, style = "") => `<span id="${id}" data-layout-kind="intrinsic" data-layout-leaf="text" style="font:14px sans-serif">${value}</span>`;
      const item = (id, proposal, point, anchor, content) => `<div id="${id}" class="layout-item" data-layout-child-proposal="${proposal}" style="position:absolute;left:${point[0]}px;top:${point[1]}px;--layout-anchor-x:${anchor[0]}%;--layout-anchor-y:${anchor[1]}%;width:1px;height:1px">${content}</div>`;
      document.body.innerHTML = `<div id="lay-app" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf" data-align-x="0" data-align-y="0"><div class="vstack" data-layout-kind="vstack" data-layout-gap="8" data-align-x="0">
        <div id="box" class="layout-box" data-layout-proposal="true" data-layout-content-width="200" data-layout-content-height="80" style="position:relative;width:200px;height:80px">
          ${item("ideal", ",", [100, 10], [-50, 0], label("t1", "Ideal"))}
          ${item("wrap", "60,", [0, 30], [0, 0], label("t2", "Wraps at sixty points"))}
          ${item("fill", "120,40", [200, 80], [-100, -100], `<div id="filled" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf" data-align-x="0.5" data-align-y="0.5"></div>`)}
        </div></div></div>`;
      document.adoptedStyleSheets = [];
      const reports = [], css = new CssLayout(document, { onProposal: (e, w, h) => reports.push(["proposal", e.id, w, h]), onLayoutSizes: (e, v) => reports.push(["sizes", e.id, v]) });
      const app = document.getElementById("lay-app"), box = document.getElementById("box");
      const ok = css.claimRoot(app, { def: { x: true, y: true }, ax: 0.5, height: "100dvh", key: "window" });
      const items = [...box.children].map((child) => css.claimRoot(child, { def: { x: !/^,/.test(child.getAttribute("data-layout-child-proposal")), y: !/,$/.test(child.getAttribute("data-layout-child-proposal")) }, ax: 0, height: "auto", key: "item", item: true }));
      css.flush();
      const rect = (id) => { const r = document.getElementById(id).getBoundingClientRect(), o = box.getBoundingClientRect(); return [r.x - o.x, r.y - o.y, r.width, r.height].map((v) => Math.round(v * 10) / 10); };
      const shown = { ok, items, refused: css.stats.unsupported, box: rect("box"), ideal: rect("ideal"), wrap: rect("wrap"), fill: rect("fill"), t1: rect("t1"), reports: [...reports] };
      // Swift changes what the page reads while the box is detached (a patch that moves a subtree): only its parent is noted.
      const parent = box.parentElement; box.remove(); box.setAttribute("data-layout-content-width", "150"); box.style.width = "150px"; parent.append(box);
      css.mark(parent, app); css.pending.add(app); css.flush();
      return { ...shown, moved: box.getBoundingClientRect().width };
    });
    assert.deepEqual([custom.ok, custom.items, custom.refused], [true, [true, true, true], {}], "a user-defined Layout and its subviews are CSS's");
    assert.deepEqual([custom.box[2], custom.box[3]], [200, 80], "the Layout is the size Swift gave it");
    assert.equal(custom.ideal[0], 100 - custom.ideal[2] / 2, "a subview anchored at its centre is pinned by the size it takes");
    assert.ok(custom.ideal[2] > 20 && custom.ideal[3] > 8, "offered nothing, a subview is as large as its content");
    assert.ok(custom.wrap[2] <= 60 && custom.wrap[3] > custom.ideal[3] * 1.5, "offered a width, a subview wraps at it");
    assert.deepEqual(custom.fill, [80, 40, 120, 40], "a subview that fills takes its proposal, pinned by its bottom trailing corner");
    assert.equal(custom.moved, 150, "a Layout whose size changed while it was detached is laid out again");
    assert.deepEqual(custom.reports.find((r) => r[0] === "proposal")?.slice(1), ["box", 1000, 700], "the Layout is told what it is offered: the window, through the stack that hugs its content");
    const sizes = custom.reports.find((r) => r[0] === "sizes")?.[2].split(";");
    assert.deepEqual([sizes.length, sizes[2]], [3, "120,40:120,40"], "and the size each subview took at its proposal");
    // A Layout is offered no height where SwiftUI asks for an ideal size along it: below a fixedSize, a Grid row that hugs its cells
    // and a frame with a minimum height pass that on (Food Truck's lattice). Where the Grid is proposed a height it passes that on.
    const asked = await page.evaluate(() => {
      const row = (id, hug) => `<div id="${id}-app" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf" data-align-x="0" data-align-y="0">
        <div data-layout-kind="fixed" data-fixed-x="false" data-fixed-y="${hug}"><div class="table-view" data-layout-kind="table" data-layout-gap="8" data-row-spacing="8" data-align-x="0.5" data-align-y="0.5">
        <div class="grid-row" data-layout-kind="gridrow"><div data-layout-kind="frame" data-frame-max-w="inf" data-frame-min-h="60" data-frame-max-h="inf" data-align-x="0.5" data-align-y="0.5">
        <div id="${id}" class="layout-box" data-layout-proposal="true" data-layout-content-width="100" data-layout-content-height="40" style="position:relative;width:100px;height:40px"></div></div></div></div></div></div>`;
      document.body.innerHTML = row("hug", "true") + row("free", "false");
      document.adoptedStyleSheets = [];
      const reports = [], css = new CssLayout(document, { onProposal: (e, w, h) => reports.push([e.id, w, h]) });
      const oks = ["hug-app", "free-app"].map((id) => css.claimRoot(document.getElementById(id), { def: { x: true, y: true }, ax: 0.5, height: "700px", key: "window-" + id }));
      css.flush();
      return { oks, hug: reports.find((r) => r[0] === "hug"), free: reports.find((r) => r[0] === "free") };
    });
    assert.deepEqual(asked.oks, [true, true], "a Layout in a Grid row in a fixedSize is CSS's");
    assert.equal(asked.hug[2], null, "a hugging Grid row asks a Layout for its ideal height: it is proposed none");
    assert.ok(asked.hug[1] > 0, "and its width");
    assert.notEqual(asked.free[2], null, "a Grid that is proposed a height proposes the Layout one");
    // An aspect box is no wider than the height its frame proposes allows, and follows the frame when it changes.
    const capped = await page.evaluate(() => {
      document.body.innerHTML = `<div id="island" class="scroll-view scroll-vertical" data-layout-kind="scroll" style="width:300px;height:300px">
        <div id="cap" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="80" data-align-x="0.5" data-align-y="0.5" data-layout-wrap="padding;padding-top=10;padding-bottom=10">
          <div id="box" data-layout-kind="aspect" data-aspect-ratio="2"><div class="shape-layer" style="background:red"></div></div></div></div>`;
      document.adoptedStyleSheets = [];
      const css = new CssLayout(document), island = document.getElementById("island"), cap = document.getElementById("cap");
      const ok = css.claim(island); css.flush();
      const size = () => { const r = document.getElementById("box").getBoundingClientRect(); return [r.width, r.height]; };
      const first = size();
      cap.setAttribute("data-frame-max-h", "40"); css.mark(cap, island); css.pending.add(island); css.flush();
      return { ok, first, second: size() };
    });
    assert.equal(capped.ok, true);
    assert.deepEqual(capped.first, [120, 60], "a 2:1 box in a frame of at most 80 with a padding of 10 above and below it is 60 tall");
    assert.deepEqual(capped.second, [40, 20], "and follows the frame's maximum when it changes");
    // A Divider runs along the stack around it, as SwiftUI runs it: across a VStack it is a point thick and as wide as the stack, in an
    // HStack a point wide and as tall as the row, also through a frame around it; a ZStack in the row starts over. One moved from the
    // VStack to the HStack (a patch that reorders a subtree notes only the parents) follows. A progress bar and a slider fill the row
    // that is left and a TextEditor its frame. (Apple's frames of the same trees: the oracle's `x-divider-*` and `x-editor-*`.)
    const rules = await page.evaluate(() => {
      const text = (value) => `<span data-layout-kind="intrinsic" data-layout-leaf="text" style="font:14px sans-serif">${value}</span>`;
      document.body.innerHTML = `<div id="rules-app" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf" data-align-x="0" data-align-y="0"><div class="vstack" data-layout-kind="vstack" data-layout-gap="8" data-align-x="0">
        <div id="col" class="vstack" data-layout-kind="vstack" data-layout-gap="8" data-align-x="0">${text("Above")}<hr id="rule">${text("Below")}</div>
        <div id="row-frame" data-layout-kind="frame" data-frame-w="200" data-frame-h="40" data-align-x="0" data-align-y="0"><div id="row" class="hstack" data-layout-kind="hstack" data-layout-gap="8">${text("Left")}<div data-layout-kind="frame" data-frame-h="20" data-align-x="0.5" data-align-y="0.5"><hr id="framed"></div>${text("Right")}<div class="zstack" data-layout-kind="zstack"><hr id="stacked"></div></div></div>
        <div id="bars-frame" data-layout-kind="frame" data-frame-w="300" data-frame-h="20" data-align-x="0" data-align-y="0"><div id="bars" class="hstack" data-layout-kind="hstack" data-layout-gap="8"><span id="volume" data-layout-kind="intrinsic" data-layout-leaf="text" style="font:14px sans-serif">Vol</span><input id="slider" type="range" class="slider-control" style="appearance:none"><progress id="bar" class="progress-bar" style="appearance:none" value="0.4" max="1"></progress></div></div>
        <div id="editor-frame" data-layout-kind="frame" data-frame-w="200" data-frame-h="90" data-align-x="0" data-align-y="0"><textarea id="editor" class="text-area">Notes</textarea></div></div></div>`;
      document.adoptedStyleSheets = [];
      const css = new CssLayout(document), app = document.getElementById("rules-app");
      const ok = css.claimRoot(app, { def: { x: true, y: true }, ax: 0, height: "700px", key: "window" });
      css.flush();
      const rect = (id) => { const r = document.getElementById(id).getBoundingClientRect(); return [r.width, r.height].map((v) => Math.round(v * 10) / 10); };
      const shown = { ok, refused: css.stats.unsupported, col: rect("col"), rule: rect("rule"), framed: rect("framed"), stacked: rect("stacked"), row: rect("row"), slider: rect("slider"), bar: rect("bar"), bars: rect("bars"), volume: rect("volume"), editor: rect("editor") };
      const col = document.getElementById("col"), row = document.getElementById("row"), rule = document.getElementById("rule");
      row.append(rule); css.mark(col, app); css.mark(row, app); css.pending.add(app); css.flush();
      return { ...shown, moved: rect("rule") };
    });
    assert.deepEqual([rules.ok, rules.refused], [true, {}], "a Divider, a slider, a progress bar and a TextEditor are CSS's");
    assert.deepEqual(rules.rule, [rules.col[0], 1], "a Divider in a VStack is a point thick and as wide as the stack");
    assert.ok(rules.col[0] > 20, "which is as wide as the widest of its other views");
    assert.deepEqual(rules.framed, [1, 20], "a Divider in a frame in an HStack is a vertical rule as tall as the frame");
    assert.equal(rules.row[1], 20, "a row whose only Divider is framed is as tall as that frame");
    assert.equal(rules.stacked[1], 1, "a Divider in a ZStack in a row is horizontal again");
    assert.deepEqual(rules.moved, [1, 40], "a Divider moved into the HStack is vertical, and the row, which a Divider makes flexible, takes the 40 it is offered");
    assert.equal(rules.bars[0], 300, "a row with a slider and a progress bar in it takes the width it is offered");
    assert.ok(Math.abs(rules.slider[0] - rules.bar[0]) < 0.5 && Math.abs(rules.volume[0] + rules.slider[0] + rules.bar[0] + 16 - 300) < 0.5,
      "and they share what its text leaves, not the browser's width for a slider (129) or a progress bar (none)");
    assert.equal(rules.bar[1], 8, "a progress bar is 8 tall");
    assert.deepEqual(rules.editor, [200, 90], "a TextEditor takes its frame");
    // The panes of an HSplitView are roots of their own too (`pane`): each is proposed the box Swift's split layout gave its item (a
    // one-cell grid), centred across and at the top where it hugs its content; a finite maximum takes min(offered, maximum) and
    // a minimum is kept; the split view is a box of the size Swift wrote, which the page tells the proposal it is offered.
    const splitIn = (claimApp) => page.evaluate((claimApp) => {
      const label = (id, value) => `<span id="${id}" data-layout-kind="intrinsic" data-layout-leaf="text" style="font:14px sans-serif">${value}</span>`;
      const item = (id, left, width, content) => `<div id="${id}" class="split-item" style="position:absolute;box-sizing:border-box;display:grid;left:${left}px;top:0;width:${width}px;height:80px">${content}</div>`;
      const frame = (id, attrs, content) => `<div id="${id}" data-layout-kind="frame" ${attrs} data-align-x="0.5" data-align-y="0.5">${content}</div>`;
      document.body.innerHTML = `<div id="split-app" data-layout-kind="frame" data-frame-max-w="inf" data-frame-max-h="inf" data-align-x="0" data-align-y="0">
        <div id="panes" class="layout-box split-pane" data-layout-proposal="true" data-layout-content-width="400" data-layout-content-height="80" data-split-axis="horizontal" style="position:relative;width:400px;height:80px">
          ${item("i0", 0, 150, frame("hug", "", label("t0", "Hugs")))}
          ${item("i1", 156, 100, frame("cap", 'data-frame-min-w="120" data-frame-max-w="220" data-frame-max-h="inf"', label("t1", "Capped")))}
          ${item("i2", 262, 138, frame("fill", 'data-frame-max-w="inf" data-frame-max-h="inf"', ""))}
        </div></div>`;
      document.adoptedStyleSheets = [];
      const reports = [], css = new CssLayout(document, { onProposal: (e, w, h) => reports.push([e.id, w, h]) });
      const app = document.getElementById("split-app"), panes = document.getElementById("panes");
      const ok = claimApp ? css.claimRoot(app, { def: { x: true, y: true }, ax: 0.5, height: "100dvh", key: "window" }) : true;
      const claimed = [...panes.children].map((child) => css.claimRoot(child.firstElementChild, { def: { x: true, y: true }, ax: 0.5, height: "cell", key: "pane" }));
      css.flush();
      const rect = (id) => { const r = document.getElementById(id).getBoundingClientRect(), o = panes.getBoundingClientRect(); return [r.x - o.x, r.y - o.y, r.width, r.height].map((v) => Math.round(v * 10) / 10); };
      return { ok, claimed, refused: css.stats.unsupported, panes: rect("panes"), hug: rect("hug"), cap: rect("cap"), fill: rect("fill"), reports };
    }, claimApp);
    const hsplit = await splitIn(true), hostedSplit = await splitIn(false);
    assert.deepEqual([hsplit.ok, hsplit.claimed, hsplit.refused], [true, [true, true, true], {}], "a split view and its panes are CSS's");
    assert.deepEqual([hsplit.panes[2], hsplit.panes[3]], [400, 80], "the split view is the size Swift gave it");
    assert.deepEqual([hsplit.hug[1], Math.round(hsplit.hug[0] + hsplit.hug[2] / 2)], [0, 75], "a pane that hugs its content is at the top, centred in its slot");
    assert.deepEqual([hsplit.cap[2], hsplit.cap[3]], [120, 80], "a frame with a finite maximum takes the slot (its height), never less than its minimum (its width, the slot being narrower)");
    assert.deepEqual(hsplit.fill, [262, 0, 138, 80], "a pane that fills takes its slot");
    assert.equal(hsplit.reports[0]?.[0], "panes", "the page reports the proposal the split view is offered");
    // Inside a root the host lays out (a native widget's), only the panes are CSS's, laid out the same.
    assert.deepEqual([hostedSplit.claimed, hostedSplit.refused, hostedSplit.hug, hostedSplit.cap, hostedSplit.fill], [[true, true, true], {}, hsplit.hug, hsplit.cap, hsplit.fill], "a pane is laid out alike whether or not the split view's own root is CSS's");
    console.log("PASS css layout roots: window root with a sidebarAdaptable TabView, NavigationStack bars, a collapsed rail, a sheet, a split view, foreign roots, appended rule sheets, release");
  } finally {
    await browser.close();
  }
});
