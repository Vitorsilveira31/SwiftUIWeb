#!/usr/bin/env bun
/* Generate the browser Lucide adapter from only the symbols reachable by an
 * application. The Swift catalog remains the compatibility source of truth;
 * it is not linked into the release browser hot path. */
"use strict";

const fs = require("fs");
const path = require("path");

function argument(name, fallback = null) {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : fallback;
}

const root = path.resolve(argument("--root", path.join(__dirname, "..")));
const catalogPath = path.resolve(argument("--catalog", path.join(root, "Sources", "SwiftUIWebBrowser", "LucideIcons.swift")));
const manifestPath = path.resolve(argument("--manifest", path.join(root, ".build", "release-manifest.json")));
const output = path.resolve(argument("--output", path.join(root, ".build", "icon-adapter.js")));
const catalog = fs.readFileSync(catalogPath, "utf8");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

function quotedValues(value) {
  return [...value.matchAll(/"((?:\\.|[^"])*)"/g)].map((match) => match[1]);
}

function decodeSwiftString(value) {
  try { return JSON.parse(`"${value}"`); } catch (_) { return value.replaceAll('\\"', '"').replaceAll('\\\\', '\\'); }
}

const iconMatch = /(?:private\s+)?static\s+func\s+iconName\s*\(/.exec(catalog);
const bodyMatch = /(?:private\s+)?static\s+func\s+body\s*\(/.exec(catalog);
const iconStart = iconMatch?.index ?? -1;
const bodyStart = bodyMatch?.index ?? -1;
if (iconStart < 0 || bodyStart < 0 || bodyStart <= iconStart) {
  throw new Error(`Lucide catalog functions were not found in ${catalogPath}`);
}

const nameMap = Object.create(null);
for (const match of catalog.slice(iconStart, bodyStart).matchAll(/case\s+((?:"(?:\\.|[^"])*"\s*,?\s*)+):\s*return\s*"([^"]+)"/g)) {
  for (const symbol of quotedValues(match[1])) nameMap[decodeSwiftString(symbol)] = match[2];
}

const bodyMap = Object.create(null);
for (const match of catalog.slice(bodyStart).matchAll(/case\s+((?:"(?:\\.|[^"])*"\s*,?\s*)+):\s*return\s*"((?:\\.|[^"])*)"/g)) {
  const body = decodeSwiftString(match[2]);
  for (const name of quotedValues(match[1])) bodyMap[name] = body;
}

function resolveName(symbol) {
  if (nameMap[symbol]) return nameMap[symbol];
  if (symbol.endsWith(".fill")) return resolveName(symbol.slice(0, -5));
  if (symbol.endsWith(".circle")) return resolveName(symbol.slice(0, -7));
  if (symbol.endsWith(".square")) return resolveName(symbol.slice(0, -7));
  if (symbol.endsWith(".slash")) return resolveName(symbol.slice(0, -6));
  return null;
}

const dynamic = manifest.icons && manifest.icons.dynamic === true;
const requested = dynamic ? Object.keys(nameMap) : (manifest.icons?.symbols || []);
const names = Object.create(null);
const bodies = Object.create(null);
for (const symbol of requested) {
  const name = resolveName(symbol);
  if (!name || !bodyMap[name]) continue;
  names[symbol] = name;
  bodies[name] = bodyMap[name];
}

if (Object.keys(names).length === 0) {
  try { fs.unlinkSync(output); } catch (_) {}
  console.log("No reachable SF Symbols; no icon asset emitted.");
  process.exit(0);
}

const source = `(function (global) {
  "use strict";
  var names = ${JSON.stringify(names)};
  var bodies = ${JSON.stringify(bodies)};
  function resolve(symbol) {
    if (names[symbol]) return names[symbol];
    if (symbol.slice(-5) === ".fill") return resolve(symbol.slice(0, -5));
    if (symbol.slice(-7) === ".circle") return resolve(symbol.slice(0, -7));
    if (symbol.slice(-7) === ".square") return resolve(symbol.slice(0, -7));
    if (symbol.slice(-6) === ".slash") return resolve(symbol.slice(0, -6));
    return null;
  }
  // Realizes the SVG of one [data-symbol] element (a no-op when it already shows the right icon).
  function realize(element) {
    var symbol = element.getAttribute("data-symbol");
    var name = resolve(symbol);
    var body = name && bodies[name];
    if (!body) {
      if (!element.getAttribute("data-lucide-fallback")) element.setAttribute("data-lucide-fallback", "true");
      if (element.hasAttribute("data-lucide")) element.removeAttribute("data-lucide");
      return;
    }
    if (element.getAttribute("data-lucide") === name && element.querySelector("svg")) return;
    element.innerHTML = "<svg class=\\"lucide-glyph lucide-" + name + "\\" xmlns=\\"http://www.w3.org/2000/svg\\" width=\\"24\\" height=\\"24\\" viewBox=\\"0 0 24 24\\" fill=\\"none\\" stroke=\\"currentColor\\" stroke-width=\\"2\\" stroke-linecap=\\"round\\" stroke-linejoin=\\"round\\" aria-hidden=\\"true\\" focusable=\\"false\\">" + body + "</svg>";
    element.setAttribute("data-lucide", name);
    element.removeAttribute("data-lucide-fallback");
  }
  // Full scan: every [data-symbol] element under scope (the document, or a mounted root).
  global.__applyIcons = function (scope) {
    var elements = scope.querySelectorAll("[data-symbol]");
    for (var i = 0; i < elements.length; i += 1) realize(elements[i]);
  };
  // One element and the icons inside it, connected or not. The DOM patch calls this on a node it is about to insert and on an
  // icon whose symbol changed, so the SVG is written together with the rest of the patch (and, for a detached node, with no
  // style work at all) instead of by the observer below, after the commit has already had its style and layout flushes.
  global.__realizeIcons = function (node) {
    if (node.nodeType !== 1) return;
    if (node.hasAttribute("data-symbol")) realize(node);
    var inner = node.querySelectorAll("[data-symbol]");
    for (var i = 0; i < inner.length; i += 1) realize(inner[i]);
  };
  // Only what a mutation touched: the added element itself and the icons inside it.
  function realizeWithin(node) {
    if (!node.isConnected) return;
    if (node.hasAttribute("data-symbol")) realize(node);
    var inner = node.querySelectorAll("[data-symbol]");
    for (var i = 0; i < inner.length; i += 1) realize(inner[i]);
  }
  // SwiftUIWeb publishes its initial tree and later reconciliations through
  // DOM mutations. Keep icon realization in the browser host so Swift views
  // only need to emit the stable data-symbol contract. After the first full
  // scan, each batch of mutations realizes only the nodes it added and the
  // elements whose data-symbol changed in place, instead of re-querying the
  // whole document; the observer watches the app root once it exists.
  if (typeof document !== "undefined") {
    var ROOT_ID = "embedded-app-root";
    var pending = [];
    var fullScan = true;
    var scheduled = false;
    var observedRoot = null;
    var apply = function () {
      scheduled = false;
      if (fullScan) {
        fullScan = false;
        pending.length = 0;
        global.__applyIcons(observedRoot || document);
        return;
      }
      var nodes = pending;
      pending = [];
      for (var i = 0; i < nodes.length; i += 1) realizeWithin(nodes[i]);
    };
    var schedule = function () {
      if (scheduled) return;
      scheduled = true;
      if (typeof queueMicrotask === "function") queueMicrotask(apply);
      else setTimeout(apply, 0);
    };
    var options = { childList: true, subtree: true, attributes: true, attributeFilter: ["data-symbol"] };
    var observer = null;
    apply();
    if (typeof MutationObserver === "function" && document.documentElement) {
      observer = new MutationObserver(function (records) {
        // The root is created after this script runs: once it exists, watch it
        // alone and scan it once, since the first subtree arrived before we could.
        if (!observedRoot) {
          var root = document.getElementById(ROOT_ID);
          if (root) {
            observedRoot = root;
            observer.disconnect();
            observer.observe(root, options);
            fullScan = true;
            schedule();
            return;
          }
        }
        for (var r = 0; r < records.length; r += 1) {
          var record = records[r];
          if (record.type === "attributes") { pending.push(record.target); continue; }
          for (var a = 0; a < record.addedNodes.length; a += 1) {
            if (record.addedNodes[a].nodeType === 1) pending.push(record.addedNodes[a]);
          }
        }
        if (pending.length) schedule();
      });
      observer.observe(document.documentElement, options);
    }
  }
})(typeof globalThis !== "undefined" ? globalThis : window);
`;
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, source);
console.log(`Generated ${Object.keys(names).length} reachable SF Symbols (${Object.keys(bodies).length} Lucide bodies): ${output}`);
