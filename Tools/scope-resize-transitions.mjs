#!/usr/bin/env bun
/*
 * Scopes the rule that holds CSS transitions off while a window resize settles.
 *
 * The layout host sets `data-layout-resizing` on the document element for RESIZE_SETTLE_MS after each resize step
 * (Tools/layout-host.js). While it is set, geometry the host writes must snap instead of running a transition: an
 * element with an `.animation` modifier carries an inline transition, and a stylesheet rule can declare one on a button,
 * an input or a hover state. Toggling the attribute makes the browser restyle the whole document, so the rule names only
 * the elements that can have a transition: a stylesheet selector that declares one, the `data-animation` and
 * `data-layout-animation` markers of the armed transitions, and any element whose inline style holds a transition (the
 * `.transition(_:)` modifier writes one). Measured on a large production app's board: the universal `*` rule cost 18-25 ms
 * per toggle, the scoped one about 2 ms.
 *
 * Not covered: the hover rules Swift adds at run time (HoverAssign, `#hover-effect-rules`). They target every node by
 * `data-embedded-node-id`, a prefix all nodes carry, so no scoped selector names them; a transition they start can run during
 * a resize. Their declarations are colour and effect styles, not the geometry the layout host writes.
 *
 * The selectors come from the stylesheets the bundle ships (styles.css and the application's own CSS, which the bundle
 * links after it), so the rule is generated when the bundle is assembled. A selector this scanner cannot read falls back
 * to the universal rule: a transition left running is slower, never wrong.
 *
 * usage: bun Tools/scope-resize-transitions.mjs <bundle-directory>
 */
"use strict";

import { appendFileSync, existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

/** The attribute the layout host sets on the document element while a resize settles. */
export const RESIZING_ATTRIBUTE = "data-layout-resizing";

/** Elements that can carry a transition the stylesheet does not declare: armed `.animation` and `.transition` ones. */
const RUNTIME_TRANSITION_SELECTORS = ["[data-animation]", "[data-layout-animation]", '[style*="transition"]'];

/** At-rules whose blocks hold style rules. Others (@keyframes, @font-face, @property, ...) are skipped. */
const GROUPING_AT_RULES = new Set(["media", "supports", "layer", "container", "scope", "document", "starting-style"]);

/** Pseudo-elements written with the one-colon legacy syntax. */
const LEGACY_PSEUDO_ELEMENTS = new Set(["before", "after", "first-line", "first-letter"]);

/** Removes comments, copying strings verbatim. */
function stripComments(css) {
  let out = "";
  for (let i = 0; i < css.length;) {
    const char = css[i];
    if (char === "/" && css[i + 1] === "*") {
      const end = css.indexOf("*/", i + 2);
      if (end < 0) throw new Error("unterminated comment in stylesheet");
      out += " ";
      i = end + 2;
    } else if (char === '"' || char === "'") {
      let j = i + 1;
      while (j < css.length && css[j] !== char) j += css[j] === "\\" ? 2 : 1;
      if (j >= css.length) throw new Error("unterminated string in stylesheet");
      out += css.slice(i, j + 1);
      i = j + 1;
    } else {
      out += char;
      i += 1;
    }
  }
  return out;
}

/** Index of the `}` that closes the `{` at `open`, skipping strings. */
function closingBrace(text, open) {
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    const char = text[i];
    if (char === '"' || char === "'") {
      i += 1;
      while (i < text.length && text[i] !== char) i += text[i] === "\\" ? 2 : 1;
    } else if (char === "{") {
      depth += 1;
    } else if (char === "}") {
      depth -= 1;
      if (depth === 0) return i;
    }
  }
  throw new Error("unbalanced block in stylesheet");
}

/** Splits at the commas that are outside parentheses, brackets and strings. */
function splitTopLevel(text, separator) {
  const parts = [];
  let depth = 0;
  let start = 0;
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (char === '"' || char === "'") {
      i += 1;
      while (i < text.length && text[i] !== char) i += text[i] === "\\" ? 2 : 1;
    } else if (char === "(" || char === "[") {
      depth += 1;
    } else if (char === ")" || char === "]") {
      depth -= 1;
    } else if (char === separator && depth === 0) {
      parts.push(text.slice(start, i));
      start = i + 1;
    }
  }
  parts.push(text.slice(start));
  return parts.map((part) => part.trim()).filter(Boolean);
}

/**
 * Whether a declaration block starts a visible transition: a `transition` or `transition-duration` with a duration of a
 * millisecond or more, or a `transition-property` that is not `none` (its duration may come from another rule). A
 * duration under a millisecond (the reduced-motion rules use 0.01ms) is not visible, and neither is a `none` value.
 */
function declaresTransition(body) {
  return body.split(";").some((declaration) => {
    const colon = declaration.indexOf(":");
    if (colon < 0) return false;
    const name = declaration.slice(0, colon).trim().toLowerCase();
    const value = declaration.slice(colon + 1).replace(/!\s*important\s*$/i, "").trim().toLowerCase();
    if (!value || value === "none") return false;
    if (name === "transition-property") return true;
    if (name !== "transition" && name !== "transition-duration") return false;
    if (/var\(|calc\(/.test(value)) return true;
    return [...value.matchAll(/(\d*\.?\d+)(ms|s)\b/g)].some((match) => parseFloat(match[1]) * (match[2] === "s" ? 1000 : 1) >= 1);
  });
}

/**
 * Splits a selector into the part that picks the element and the pseudo-element it styles (`.a:hover::before` gives
 * `.a:hover` and `::before`). A selector without one has an empty tail.
 */
export function splitPseudoElement(selector) {
  let depth = 0;
  for (let i = 0; i < selector.length; i++) {
    const char = selector[i];
    if (char === '"' || char === "'") {
      i += 1;
      while (i < selector.length && selector[i] !== char) i += selector[i] === "\\" ? 2 : 1;
    } else if (char === "(" || char === "[") {
      depth += 1;
    } else if (char === ")" || char === "]") {
      depth -= 1;
    } else if (char === ":" && depth === 0) {
      if (selector[i + 1] === ":") return [selector.slice(0, i).trim(), selector.slice(i)];
      const legacy = /^:([a-z-]+)/i.exec(selector.slice(i));
      if (legacy && LEGACY_PSEUDO_ELEMENTS.has(legacy[1].toLowerCase())) {
        return [selector.slice(0, i).trim(), selector.slice(i)];
      }
    }
  }
  return [selector.trim(), ""];
}

/** Splits a declaration block into its declarations and its nested rules (CSS nesting), skipping strings. */
function splitBody(body) {
  let declarations = "";
  const nested = [];
  let i = 0;
  while (i < body.length) {
    let j = i;
    while (j < body.length && body[j] !== "{" && body[j] !== ";" && body[j] !== "}") {
      if (body[j] === '"' || body[j] === "'") {
        const quote = body[j];
        j += 1;
        while (j < body.length && body[j] !== quote) j += body[j] === "\\" ? 2 : 1;
      }
      j += 1;
    }
    if (j >= body.length) {
      declarations += body.slice(i);
      break;
    }
    if (body[j] === "{") {
      const close = closingBrace(body, j);
      nested.push({ prelude: body.slice(i, j).trim(), body: body.slice(j + 1, close) });
      i = close + 1;
    } else {
      declarations += body.slice(i, j + 1);
      i = j + 1;
    }
  }
  return { declarations, nested };
}

/** The selectors a rule's prelude names, resolved against the selectors of the rule it is nested in. */
function resolveSelectors(prelude, parents) {
  const selectors = splitTopLevel(prelude, ",").map((selector) => selector.replace(/\s+/g, " "));
  if (!parents) return selectors;
  return parents.flatMap((parent) => selectors.map((selector) => (selector.includes("&") ? selector.replace(/&/g, parent) : `${parent} ${selector}`)));
}

/** Reads one rule (or grouping at-rule) of the stylesheet into `found`. `parents` are the selectors it is nested in. */
function visitRule(prelude, body, parents, found) {
  if (prelude.startsWith("@")) {
    const name = /^@([a-z-]+)/i.exec(prelude)?.[1]?.toLowerCase();
    if (!GROUPING_AT_RULES.has(name)) return;
    // Declarations directly inside a nested grouping rule belong to the rule they are nested in.
    if (parents && declaresTransition(splitBody(body).declarations)) for (const parent of parents) found.add(parent);
    visitItems(body, parents, found);
    return;
  }
  const { declarations, nested } = splitBody(body);
  const selectors = resolveSelectors(prelude, parents);
  if (declaresTransition(declarations)) for (const selector of selectors) found.add(selector);
  for (const child of nested) visitRule(child.prelude, child.body, selectors, found);
}

/** Reads every rule of a stylesheet (or of a block) into `found`. */
function visitItems(text, parents, found) {
  let i = 0;
  while (i < text.length) {
    let j = i;
    while (j < text.length && text[j] !== "{" && text[j] !== ";" && text[j] !== "}") {
      if (text[j] === '"' || text[j] === "'") {
        const quote = text[j];
        j += 1;
        while (j < text.length && text[j] !== quote) j += text[j] === "\\" ? 2 : 1;
      }
      j += 1;
    }
    if (j >= text.length) break;
    if (text[j] !== "{") {
      i = j + 1;
      continue;
    }
    const prelude = text.slice(i, j).trim();
    const close = closingBrace(text, j);
    visitRule(prelude, text.slice(j + 1, close), parents, found);
    i = close + 1;
  }
}

/**
 * The selectors of the style rules that declare a transition, in the order they first appear. `@media` and the other
 * grouping at-rules are read through, nested rules are resolved against their parents, and `@keyframes` and the rest are
 * not style rules. Throws on CSS it cannot read.
 */
export function collectTransitionSelectors(css) {
  const found = new Set();
  visitItems(stripComments(css), null, found);
  return [...found];
}

/**
 * The rule that turns transitions off under the resizing attribute. Selectors that style a pseudo-element are grouped by
 * that pseudo-element; the rest share one `:where()` list, which keeps the rule at the specificity of the universal one
 * it replaces. Returns "" when there is nothing to scope.
 */
export function resizeTransitionRule(selectors) {
  const prefix = `[${RESIZING_ATTRIBUTE}] `;
  const plain = new Set(RUNTIME_TRANSITION_SELECTORS);
  const pseudo = new Map();
  for (const selector of selectors) {
    const [base, tail] = splitPseudoElement(selector);
    // A pseudo-element can be followed by pseudo-classes only; a combinator after it cannot be placed in the rule.
    if (/[\s>+~]/.test(tail.replace(/\([^)]*\)/g, ""))) throw new Error(`cannot scope the selector ${selector}`);
    if (!tail) {
      plain.add(base);
      continue;
    }
    const element = base || "*";
    if (!pseudo.has(tail)) pseudo.set(tail, new Set());
    pseudo.get(tail).add(element);
  }
  const rules = [];
  rules.push(`${prefix}:where(${[...plain].join(", ")}) { transition: none !important; }`);
  for (const [tail, elements] of pseudo) {
    rules.push(`${prefix}:where(${[...elements].join(", ")})${tail} { transition: none !important; }`);
  }
  return `/* Generated by Tools/scope-resize-transitions.mjs: transitions the stylesheets declare, held off while a resize settles. */\n${rules.join("\n")}\n`;
}

/** The universal rule the scoped one replaces, used when the stylesheets cannot be read. */
const UNIVERSAL_RULE = `[${RESIZING_ATTRIBUTE}] *, [${RESIZING_ATTRIBUTE}] *::before, [${RESIZING_ATTRIBUTE}] *::after { transition: none !important; }\n`;

/** The rule for a bundle: the selectors of every stylesheet it ships, or the universal rule when one cannot be read. */
export function bundleResizeTransitionRule(stylesheets) {
  try {
    const selectors = [];
    for (const css of stylesheets) selectors.push(...collectTransitionSelectors(css));
    return { rule: resizeTransitionRule(selectors), selectors: selectors.length, fallback: false };
  } catch (error) {
    return { rule: UNIVERSAL_RULE, selectors: 0, fallback: true, reason: error.message };
  }
}

function stylesheetPaths(directory) {
  const paths = [];
  for (const entry of readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) paths.push(...stylesheetPaths(path));
    else if (entry.name.endsWith(".css")) paths.push(path);
  }
  return paths;
}

if (import.meta.main) {
  const directory = process.argv[2];
  if (!directory) {
    console.error("usage: bun Tools/scope-resize-transitions.mjs <bundle-directory>");
    process.exit(2);
  }
  const styles = join(directory, "styles.css");
  if (!existsSync(styles)) throw new Error(`no styles.css in ${directory}`);
  const paths = stylesheetPaths(directory);
  const result = bundleResizeTransitionRule(paths.map((path) => readFileSync(path, "utf8")));
  if (result.fallback) console.error(`warning: resize transitions use the universal rule: ${result.reason}`);
  if (!result.rule) {
    console.log("No stylesheet declares a transition; no resize rule written.");
  } else {
    appendFileSync(styles, result.rule);
    console.log(`Scoped the resize transition rule: ${result.selectors} selector(s) from ${paths.length} stylesheet(s).`);
  }
}
