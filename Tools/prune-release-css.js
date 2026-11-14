#!/usr/bin/env bun
/*
 * Remove framework CSS rules for optional features that the reachability
 * manifest proves absent.  This pass only touches the small, semantic rules
 * authored by SwiftUIWeb for the optional feature class families listed in
 * `featurePrefixes`.
 * Unknown selectors and mixed selectors are retained, so an unresolved
 * dynamic view can never lose styling silently.
 */
"use strict";

const fs = require("fs");
const path = require("path");

function argument(name, fallback = null) {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : fallback;
}

const cssArgument = argument("--css");
const manifestArgument = argument("--manifest");
if (!cssArgument || !manifestArgument) {
  throw new Error("Usage: prune-release-css.js --css path/to/styles.css --manifest path/to/release-manifest.json");
}
const cssPath = path.resolve(cssArgument);
const manifestPath = path.resolve(manifestArgument);
if (!fs.existsSync(cssPath) || !fs.existsSync(manifestPath)) {
  throw new Error(`CSS or manifest path does not exist: ${cssPath}, ${manifestPath}`);
}
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const features = manifest.features || {};

// These are the only semantic rules removed by this pass.  Keep the list
// explicit: adding a class here requires a feature regression fixture.
// Each entry names a class family: the class itself and every `<name>-*` class.
const featurePrefixes = {
  datePickers: ["date-input", "date-picker", "multi-date-picker"],
  adaptiveMedia: ["video-surface"],
  maps: ["mapkit"],
  charts: ["data-chart", "chart-svg"],
  canvas: ["draw-canvas"],
  meshGradient: ["mesh-gradient"],
  photos: ["photos-picker"],
  webView: ["web-view"],
  paste: ["paste-button"]
};

function inFamily(value, family) {
  return value === family || value.startsWith(family + "-");
}

const unavailablePrefixes = [];
for (const [feature, prefixes] of Object.entries(featurePrefixes)) {
  if (features[feature] !== true) for (const prefix of prefixes) unavailablePrefixes.push({ feature, prefix });
}

if (manifest.css?.dynamic === true || manifest.css?.proof?.safeToPruneOptionalRules === false || manifest.proof?.safeToPruneOptionalCSS === false) {
  const bytes = fs.readFileSync(cssPath);
  console.log(JSON.stringify({
    css: cssPath,
    removedRules: 0,
    removedBytes: 0,
    originalBytes: bytes.length,
    finalBytes: bytes.length,
    skipped: "dynamic-css"
  }, null, 2));
  process.exit(0);
}

function featureForClass(value) {
  const match = unavailablePrefixes.find(({ prefix }) => inFamily(value, prefix));
  if (match) return match.feature;
  for (const [feature, prefixes] of Object.entries(featurePrefixes)) {
    if (prefixes.some(prefix => inFamily(value, prefix))) return feature;
  }
  return null;
}

// Offset of the next `.class` token that belongs to an optional-feature family, or -1.
function nextFeatureClass(css, from) {
  const token = /\.([A-Za-z_][\w-]*)/g;
  token.lastIndex = from;
  for (let match = token.exec(css); match; match = token.exec(css)) {
    if (featureForClass(match[1]) !== null) return match.index;
  }
  return -1;
}

function classes(selector) {
  return [...selector.matchAll(/\.([A-Za-z_][\w-]*)/g)].map(match => match[1]);
}

function removableSelector(selector) {
  const names = classes(selector);
  if (!names.length) return false;
  const mapped = names.map(featureForClass);
  // A selector containing an unrelated semantic class is retained. This is
  // intentionally conservative for grouped selectors and future CSS.
  if (mapped.some(value => value === null)) {
    const unknown = names.filter((name, index) => mapped[index] === null);
    const shared = new Set(["symbol-icon"]);
    if (unknown.some(name => !shared.has(name))) return false;
  }
  return mapped.filter(Boolean).every(feature => features[feature] !== true);
}

function selectorStart(css, opening) {
  let start = opening - 1;
  let depth = 0;
  // Find the beginning of this rule's selector. A nested rule starts after
  // the nearest closing/opening brace or declaration terminator at depth 0.
  while (start >= 0) {
    const value = css[start];
    if (value === "}") break;
    if (value === "{") break;
    if (value === ";" && depth === 0) break;
    start -= 1;
  }
  return start + 1;
}

function matchingBrace(css, opening) {
  let depth = 0;
  let quote = null;
  let escaped = false;
  for (let index = opening; index < css.length; index += 1) {
    const value = css[index];
    if (quote) {
      if (escaped) escaped = false;
      else if (value === "\\") escaped = true;
      else if (value === quote) quote = null;
      continue;
    }
    if (value === '"' || value === "'") { quote = value; continue; }
    if (value === "{") depth += 1;
    else if (value === "}" && --depth === 0) return index;
  }
  return -1;
}

function prune(css) {
  const removals = [];
  let search = 0;
  while (search < css.length) {
    const candidate = nextFeatureClass(css, search);
    if (candidate < 0) break;
    const opening = css.indexOf("{", candidate);
    if (opening < 0) break;
    const start = selectorStart(css, opening);
    const selector = css.slice(start, opening).trim();
    const end = matchingBrace(css, opening);
    if (end < 0) break;
    if (removableSelector(selector)) removals.push([start, end + 1]);
    search = opening + 1;
  }
  // Nested rules can be discovered more than once when grouped selectors are
  // present. Merge ranges before applying them from right to left.
  removals.sort((a, b) => a[0] - b[0]);
  const merged = [];
  for (const range of removals) {
    const previous = merged[merged.length - 1];
    if (previous && range[0] <= previous[1]) previous[1] = Math.max(previous[1], range[1]);
    else merged.push(range.slice());
  }
  let output = css;
  for (let index = merged.length - 1; index >= 0; index -= 1) {
    const [start, end] = merged[index];
    output = output.slice(0, start) + output.slice(end);
  }
  return { css: output, removedRules: merged.length, removedBytes: css.length - output.length };
}

const original = fs.readFileSync(cssPath, "utf8");
const result = prune(original);
fs.writeFileSync(cssPath, result.css);
console.log(JSON.stringify({
  css: cssPath,
  removedRules: result.removedRules,
  removedBytes: result.removedBytes,
  originalBytes: Buffer.byteLength(original),
  finalBytes: Buffer.byteLength(result.css),
  features
}, null, 2));

module.exports = { prune, removableSelector };
