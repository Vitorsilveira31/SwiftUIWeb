// How fast can the page build a new subtree? The same markup (a section a large app inserts on navigation) built
// (A) as today: template.innerHTML, then cloneNode(true) of its children;
// (B) from a binary op stream: one TextDecoder.decode + split for the strings, then createElement/setAttribute/append;
// (C) from shapes: a subtree whose structure (tags, attribute names, text positions) repeats is cloned from a cached
//     template, then (C1) every value is written, or (C2) only the values that differ from the template's.
// Every variant builds into a detached DocumentFragment; insertion and style are the same for all and are left out.
// Input: markup files, such as the `innerHTML` of a screen's visible panel saved from a running app. Numbers and how they
// were taken: Documentation/Architecture/BINARY_PATCHES.md.
// bun Tools/binary-build-bench.mjs <chromium|webkit> <file.html>...
import { chromium, webkit } from "playwright";
import { readFileSync } from "node:fs";
const [engine, ...files] = process.argv.slice(2);
const browser = await (engine === "webkit" ? webkit : chromium).launch({ headless: true });
const page = await browser.newPage();
await page.setContent("<!doctype html><html><body></body></html>");
for (const file of files) {
  const html = readFileSync(file, "utf8");
  const result = await page.evaluate((html) => {
    const SVG = "http://www.w3.org/2000/svg";
    const parsed = document.createElement("template"); parsed.innerHTML = html;
    const source = parsed.content;
    // Strings interned in first-use order; ops are u32 words.
    const strings = [], index = new Map();
    const intern = (s) => { let i = index.get(s); if (i === undefined) { i = strings.length; strings.push(s); index.set(s, i); } return i; };
    const OPEN = 1, OPEN_SVG = 2, TEXT = 3, CLOSE = 4, SHAPE = 5;
    const signature = new Map(), count = new Map();
    const sig = (node) => {
      if (node.nodeType === 3) return "#t";
      if (node.nodeType !== 1) return "";
      let s = node.localName + "(" + [...node.attributes].map((a) => a.name).join(",") + ")[";
      for (const c of node.childNodes) s += sig(c) + ";";
      s += "]";
      signature.set(node, s); count.set(s, (count.get(s) || 0) + 1);
      return s;
    };
    for (const c of source.childNodes) sig(c);
    // Shapes: the cached template of a structure is its first instance.
    const shapes = new Map(), shapeTemplates = [];
    const opsB = [], opsC = [], fillsC1 = [], fillsC2 = [];
    const encode = (node, ops, useShapes) => {
      if (node.nodeType === 3) { ops.push(TEXT, intern(node.nodeValue)); return; }
      if (node.nodeType !== 1) return;
      const s = signature.get(node);
      if (useShapes && count.get(s) >= 2 && node.childNodes.length) {
        let shape = shapes.get(s);
        if (shape === undefined) { shape = shapeTemplates.length; shapes.set(s, shape); shapeTemplates.push(node.cloneNode(true)); }
        const template = shapeTemplates[shape];
        // Values in walk order: every attribute value and text (C1), or only those differing from the template (C2).
        const all = [], diff = [];
        const a = [], b = [];
        const walk = (n, list) => { list.push(n); for (const c of n.childNodes) if (c.nodeType === 1 || c.nodeType === 3) walk(c, list); };
        walk(node, a); walk(template, b);
        for (let i = 0; i < a.length; i++) {
          if (a[i].nodeType === 3) { all.push(i, -1, intern(a[i].nodeValue)); if (a[i].nodeValue !== b[i].nodeValue) diff.push(i, -1, intern(a[i].nodeValue)); continue; }
          for (const attr of a[i].attributes) {
            const name = intern(attr.name), value = intern(attr.value);
            all.push(i, name, value);
            if (b[i].getAttribute(attr.name) !== attr.value) diff.push(i, name, value);
          }
        }
        ops.push(SHAPE, shape, fillsC1.length); fillsC1.push(all); fillsC2.push(diff);
        return;
      }
      ops.push(node.namespaceURI === SVG ? OPEN_SVG : OPEN, intern(node.localName), node.attributes.length);
      for (const attr of node.attributes) ops.push(intern(attr.name), intern(attr.value));
      for (const c of node.childNodes) encode(c, ops, useShapes);
      ops.push(CLOSE);
    };
    for (const c of source.childNodes) encode(c, opsB, false);
    for (const c of source.childNodes) encode(c, opsC, true);
    const stringBytes = new TextEncoder().encode(strings.join("\0"));
    const wordsB = Uint32Array.from(opsB), wordsC = Uint32Array.from(opsC);
    const decoder = new TextDecoder();

    const buildOps = (words, table, fills, allValues) => {
      const fragment = document.createDocumentFragment();
      const stack = [fragment];
      let parent = fragment;
      for (let i = 0; i < words.length;) {
        const op = words[i++];
        if (op === OPEN || op === OPEN_SVG) {
          const element = op === OPEN ? document.createElement(table[words[i++]]) : document.createElementNS(SVG, table[words[i++]]);
          for (let n = words[i++]; n > 0; n--) { element.setAttribute(table[words[i]], table[words[i + 1]]); i += 2; }
          parent.appendChild(element); stack.push(element); parent = element;
        } else if (op === TEXT) parent.appendChild(document.createTextNode(table[words[i++]]));
        else if (op === CLOSE) { stack.pop(); parent = stack[stack.length - 1]; }
        else if (op === SHAPE) {
          const clone = shapeTemplates[words[i++]].cloneNode(true), fill = (allValues ? fillsC1 : fillsC2)[words[i++]];
          if (fill.length) {
            const nodes = []; const walk = (n) => { nodes.push(n); for (let c = n.firstChild; c; c = c.nextSibling) if (c.nodeType === 1 || c.nodeType === 3) walk(c); }; walk(clone);
            for (let f = 0; f < fill.length; f += 3) { const n = nodes[fill[f]]; if (fill[f + 1] < 0) n.nodeValue = table[fill[f + 2]]; else n.setAttribute(table[fill[f + 1]], table[fill[f + 2]]); }
          }
          parent.appendChild(clone);
        }
      }
      return fragment;
    };
    const variants = {
      A_parse: () => { const t = document.createElement("template"); t.innerHTML = html; return t.content; },
      A_parseClone: () => { const t = document.createElement("template"); t.innerHTML = html; const f = document.createDocumentFragment(); for (const c of t.content.childNodes) f.appendChild(c.cloneNode(true)); return f; },
      B_ops: () => buildOps(wordsB, decoder.decode(stringBytes).split("\0"), null, true),
      C1_shapesAll: () => buildOps(wordsC, decoder.decode(stringBytes).split("\0"), fillsC1, true),
      C2_shapesDiff: () => buildOps(wordsC, decoder.decode(stringBytes).split("\0"), fillsC2, false),
    };
    // Same tree from every variant.
    const shape = (n) => n.nodeType === 1 ? n.localName + [...n.attributes].map((a) => a.name + "=" + a.value).sort().join() + "[" + [...n.childNodes].map(shape).join() + "]" : n.nodeType === 3 ? n.nodeValue : "";
    const expected = [...variants.A_parse().childNodes].map(shape).join();
    const out = { elements: source.querySelectorAll("*").length, htmlKB: +(html.length / 1024).toFixed(0), stringKB: +(stringBytes.length / 1024).toFixed(0), opsKB: +(wordsB.length * 4 / 1024).toFixed(0), shapes: shapeTemplates.length, shapeRoots: fillsC1.length, valuesC1: fillsC1.reduce((s, f) => s + f.length / 3, 0), valuesC2: fillsC2.reduce((s, f) => s + f.length / 3, 0) };
    for (const [name, build] of Object.entries(variants)) {
      if ([...build().childNodes].map(shape).join() !== expected) out[name] = "MISMATCH";
      for (let w = 0; w < 5; w++) build();
      const times = [];
      for (let r = 0; r < 15; r++) { const t = performance.now(); for (let k = 0; k < 20; k++) build(); times.push((performance.now() - t) / 20); }
      times.sort((x, y) => x - y);
      out[name] ??= +times[7].toFixed(2);
    }
    return out;
  }, html);
  console.log(engine, file, JSON.stringify(result));
}
await browser.close();
