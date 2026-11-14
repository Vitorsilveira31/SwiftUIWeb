#!/usr/bin/env bun
// Lints Tools/styles.css for declarations that can never apply.
//
// A declaration is dead when a LATER rule in the same cascade layer and at-rule context lists every selector of the earlier
// rule (so every element the earlier rule styles is styled by the later one too, with the same specificity) and sets a
// property that fully overrides it. Typical cause: a second set of rules for the same component written under new aliases.
// Keep each component's base rule in one place and put what differs in a variant rule instead.
//
// Nested rules are resolved first. `&` means :is(parent), whose specificity is that of the parent's most specific selector,
// so a nested rule is only analysed when the parent's selectors all have the same specificity; otherwise it is left alone.
// Declarations with !important are never reported.
//
// usage: bun Tools/lint-styles.mjs [--fix-report] [path]      (exit status 1 when something is dead)
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { compareTuples, isMain, SPACE_CLASS, readText, rx } from "./audit-support.mjs";

const GROUPS = ["@media", "@supports", "@container", "@layer"];
// Longhands a later shorthand fully overrides. Explicit on purpose: `border` does not reset `border-radius`, `outline` does
// not reset `outline-offset`, and `font` resets more than its name suggests.
const SIDES = ["top", "right", "bottom", "left"];
const COVER = new Map(Object.entries({
  border: new Set([
    ...SIDES.flatMap((side) => ["width", "style", "color"].map((kind) => `border-${side}-${kind}`)),
    "border-width", "border-style", "border-color", ...SIDES.map((side) => `border-${side}`),
  ]),
  "border-width": new Set(SIDES.map((side) => `border-${side}-width`)),
  "border-style": new Set(SIDES.map((side) => `border-${side}-style`)),
  "border-color": new Set(SIDES.map((side) => `border-${side}-color`)),
  ...Object.fromEntries(SIDES.map((side) => [`border-${side}`, new Set([`border-${side}-width`, `border-${side}-style`, `border-${side}-color`])])),
  "border-radius": new Set(["border-top-left-radius", "border-top-right-radius", "border-bottom-left-radius", "border-bottom-right-radius"]),
  margin: new Set(["margin-top", "margin-right", "margin-bottom", "margin-left", "margin-inline", "margin-block", "margin-inline-start", "margin-inline-end", "margin-block-start", "margin-block-end"]),
  padding: new Set(["padding-top", "padding-right", "padding-bottom", "padding-left", "padding-inline", "padding-block", "padding-inline-start", "padding-inline-end", "padding-block-start", "padding-block-end"]),
  "margin-inline": new Set(["margin-left", "margin-right", "margin-inline-start", "margin-inline-end"]),
  "margin-block": new Set(["margin-top", "margin-bottom", "margin-block-start", "margin-block-end"]),
  "padding-inline": new Set(["padding-left", "padding-right", "padding-inline-start", "padding-inline-end"]),
  "padding-block": new Set(["padding-top", "padding-bottom", "padding-block-start", "padding-block-end"]),
  background: new Set(["background-color", "background-image", "background-position", "background-size", "background-repeat", "background-origin", "background-clip", "background-attachment"]),
  outline: new Set(["outline-color", "outline-style", "outline-width"]),
  transition: new Set(["transition-property", "transition-duration", "transition-timing-function", "transition-delay"]),
  inset: new Set(["top", "right", "bottom", "left"]),
  gap: new Set(["row-gap", "column-gap"]),
  overflow: new Set(["overflow-x", "overflow-y"]),
  flex: new Set(["flex-grow", "flex-shrink", "flex-basis"]),
  "flex-flow": new Set(["flex-direction", "flex-wrap"]),
  "place-items": new Set(["align-items", "justify-items"]),
  "place-content": new Set(["align-content", "justify-content"]),
  "text-decoration": new Set(["text-decoration-line", "text-decoration-style", "text-decoration-color", "text-decoration-thickness"]),
  "list-style": new Set(["list-style-type", "list-style-position", "list-style-image"]),
}));
// A winner using a function newer than the supported browsers could be dropped by an older engine, which would then fall back
// to the earlier declaration. Such a winner shadows nothing.
const NEWER_THAN_BASELINE = ["light-dark("];

const SPACE = rx(String.raw`^\s$`);
const SPACES = new RegExp(`${SPACE_CLASS}+`, "u");
const strip = (text) => text.replace(new RegExp(`^${SPACE_CLASS}+|${SPACE_CLASS}+$`, "gu"), "");
const collapse = (text) => text.split(SPACES).filter(Boolean).join(" ");

/** Raw property names only: a vendor alias such as -webkit-backdrop-filter is never assumed to be the same property. */
function covers(winner, loser) {
  const w = strip(winner).toLowerCase();
  const l = strip(loser).toLowerCase();
  return w === l || (COVER.get(w)?.has(l) ?? false);
}

// ---- tokenising ---------------------------------------------------------------------------------------------------------
function indexAfter(text, needle, from) {
  const index = text.indexOf(needle, from);
  if (index < 0) throw new Error(`substring not found: ${needle}`);
  return index;
}

function skipString(text, i) {
  const quote = text[i];
  let j = i + 1;
  while (j < text.length && text[j] !== quote) j += text[j] === "\\" ? 2 : 1;
  return j + 1;
}

/** Index just after the } closing the { at text[i]. */
function matchBrace(text, i) {
  let depth = 0;
  const n = text.length;
  while (i < n) {
    const c = text[i];
    if (text.startsWith("/*", i)) {
      i = indexAfter(text, "*/", i) + 2;
      continue;
    }
    if (c === '"' || c === "'") {
      i = skipString(text, i);
      continue;
    }
    if (c === "\\") {
      i += 2;
      continue;
    }
    if (c === "{") depth += 1;
    else if (c === "}") {
      depth -= 1;
      if (depth === 0) return i + 1;
    }
    i += 1;
  }
  throw new Error("unbalanced braces");
}

/** [[prelude, body or null, start, end]] for the statements of a block; `;` statements have body null. */
function splitChildren(text, base = 0) {
  const out = [];
  let i = 0;
  const n = text.length;
  while (i < n) {
    while (i < n && (SPACE.test(text[i]) || text.startsWith("/*", i))) {
      i = text.startsWith("/*", i) ? indexAfter(text, "*/", i) + 2 : i + 1;
    }
    if (i >= n) break;
    const start = i;
    let j = i;
    let paren = 0;
    let found = false;
    while (j < n) {
      const c = text[j];
      if (text.startsWith("/*", j)) {
        j = indexAfter(text, "*/", j) + 2;
        continue;
      }
      if (c === '"' || c === "'") {
        j = skipString(text, j);
        continue;
      }
      if (c === "\\") {
        j += 2;
        continue;
      }
      if (c === "(") paren += 1;
      else if (c === ")") paren -= 1;
      else if (c === ";" && paren === 0) {
        out.push([strip(text.slice(start, j)), null, base + start, base + j + 1]);
        i = j + 1;
        found = true;
        break;
      } else if (c === "{" && paren === 0) {
        const end = matchBrace(text, j);
        out.push([strip(text.slice(start, j)), text.slice(j + 1, end - 1), base + start, base + end]);
        i = end;
        found = true;
        break;
      }
      j += 1;
    }
    if (!found) break;
  }
  return out;
}

function splitList(selector) {
  const out = [];
  let depth = 0;
  let current = [];
  for (const ch of selector) {
    if (ch === "(" || ch === "[") depth += 1;
    else if (ch === ")" || ch === "]") depth -= 1;
    if (ch === "," && depth === 0) {
      out.push(collapse(current.join("")));
      current = [];
    } else current.push(ch);
  }
  out.push(collapse(current.join("")));
  return out.filter(Boolean);
}

const maxSpecificity = (values) => values.reduce((best, item) => (compareTuples(item, best) > 0 ? item : best), [0, 0, 0]);
const NAME_START = rx(String.raw`^[\w\\-]`);
const WORD_OR_HYPHEN = rx(String.raw`^[\w-]`);
const IDENT_START = rx(String.raw`^[A-Za-z_\\]`);

export function specificity(selector) {
  let a = 0;
  let b = 0;
  let c = 0;
  let i = 0;
  const n = selector.length;
  const elementPseudos = new Set(["before", "after", "first-line", "first-letter"]);
  while (i < n) {
    const ch = selector[i];
    if (ch === "#" || ch === ".") {
      if (ch === "#") a += 1;
      else b += 1;
      i += 1;
      while (i < n && NAME_START.test(selector[i])) i += 1;
    } else if (ch === "[") {
      b += 1;
      let depth = 0;
      while (i < n) {
        if (selector[i] === "[") depth += 1;
        else if (selector[i] === "]") {
          depth -= 1;
          if (depth === 0) {
            i += 1;
            break;
          }
        } else if (selector[i] === '"' || selector[i] === "'") i = skipString(selector, i) - 1;
        i += 1;
      }
    } else if (ch === ":") {
      if (selector.startsWith("::", i)) {
        c += 1;
        i += 2;
        while (i < n && WORD_OR_HYPHEN.test(selector[i])) i += 1;
        continue;
      }
      const found = rx(String.raw`^:([\w-]+)`).exec(selector.slice(i));
      const name = found ? found[1].toLowerCase() : "";
      i += 1 + name.length;
      let args = null;
      if (i < n && selector[i] === "(") {
        let depth = 0;
        let j = i;
        while (j < n) {
          if (selector[j] === "(") depth += 1;
          else if (selector[j] === ")") {
            depth -= 1;
            if (depth === 0) break;
          }
          j += 1;
        }
        args = selector.slice(i + 1, j);
        i = j + 1;
      }
      if (elementPseudos.has(name)) c += 1;
      else if (name === "where") {
        // zero specificity
      } else if (["is", "not", "has", "matches"].includes(name)) {
        const best = maxSpecificity(splitList(args ?? "").map(specificity));
        a += best[0]; b += best[1]; c += best[2];
      } else if (name.startsWith("nth-") && args && args.includes(" of ")) {
        b += 1;
        const best = maxSpecificity(splitList(args.split(" of ").slice(1).join(" of ")).map(specificity));
        a += best[0]; b += best[1]; c += best[2];
      } else b += 1;
    } else if (" >+~\t\n*|".includes(ch)) i += 1;
    else if (IDENT_START.test(ch)) {
      c += 1;
      while (i < n && NAME_START.test(selector[i])) i += 1;
    } else i += 1;
  }
  return [a, b, c];
}

// ---- the model ----------------------------------------------------------------------------------------------------------
/** A style rule (or a conditional group inside one) with its selectors fully resolved. */
class Rule {
  constructor(alts, context, layer, start, opaque) {
    Object.assign(this, { alts, context, layer, start, opaque });
    this.decls = []; // [property, value, start offset]
  }
}

function resolveSelectors(parentAlts, childSelector) {
  const specs = new Set(parentAlts.map((alt) => specificity(alt).join(",")));
  const out = [];
  for (const child of splitList(childSelector)) {
    for (const parent of parentAlts) {
      out.push(child.includes("&") ? collapse(child.split("&").join(parent)) : collapse(`${parent} ${child}`));
    }
  }
  return parentAlts.length > 1 && specs.size > 1 ? null : out;
}

function collect(text) {
  const rules = [];
  const walk = (node, span) => {
    const bodyOpen = indexAfter(text, "{", span[0]) + 1;
    for (const [prelude, body, s, e] of splitChildren(text.slice(bodyOpen, span[1] - 1), bodyOpen)) {
      if (body === null) {
        if (prelude) {
          const colon = prelude.indexOf(":");
          const property = colon < 0 ? prelude : prelude.slice(0, colon);
          const value = colon < 0 ? "" : prelude.slice(colon + 1);
          node.decls.push([strip(property), strip(value), s]);
        }
      } else if (prelude.startsWith("@")) {
        if (GROUPS.some((group) => prelude.startsWith(group))) {
          const group = new Rule(node.alts, [...node.context, collapse(prelude)], node.layer, s, node.opaque);
          rules.push(group);
          walk(group, [s, e]);
        }
      } else {
        const alts = node.opaque ? null : resolveSelectors(node.alts, prelude);
        const child = new Rule(alts ?? [], node.context, node.layer, s, alts === null);
        rules.push(child);
        walk(child, [s, e]);
      }
    }
  };
  const top = (children, layer, context) => {
    for (const [prelude, body, s, e] of children) {
      if (body === null) continue;
      if (prelude.startsWith("@layer")) {
        const inner = indexAfter(text, "{", s) + 1;
        const words = prelude.split(SPACES).filter(Boolean);
        const name = words.length > 1 ? strip(prelude.replace(new RegExp(`^${SPACE_CLASS}*\\S+${SPACE_CLASS}+`, "u"), "")) : "";
        top(splitChildren(text.slice(inner, e - 1), inner), name || layer, context);
      } else if (["@media", "@supports", "@container"].some((group) => prelude.startsWith(group))) {
        const inner = indexAfter(text, "{", s) + 1;
        top(splitChildren(text.slice(inner, e - 1), inner), layer, [...context, collapse(prelude)]);
      } else if (!prelude.startsWith("@")) {
        const rule = new Rule(splitList(prelude), context, layer || "(unlayered)", s, false);
        rules.push(rule);
        walk(rule, [s, e]);
      }
    }
  };
  top(splitChildren(text), "", []);
  rules.sort((a, b) => a.start - b.start);
  return rules;
}

/** [[loser rule, [property, value, start], winner rule, [property, value, start]]] */
export function findDead(text) {
  const rules = collect(text);
  const index = new Map();
  const keyOf = (rule, alt) => JSON.stringify([rule.layer, rule.context, alt]);
  for (const rule of rules) {
    if (!rule.opaque && rule.alts.length > 0 && rule.decls.length > 0) {
      for (const alt of rule.alts) {
        const key = keyOf(rule, alt);
        if (!index.has(key)) index.set(key, []);
        index.get(key).push(rule);
      }
    }
  }
  const dead = [];
  for (const a of rules) {
    if (a.opaque || a.alts.length === 0 || a.decls.length === 0) continue;
    let candidates = null;
    for (const alt of a.alts) {
      const later = new Set((index.get(keyOf(a, alt)) ?? []).filter((b) => b.start > a.start));
      candidates = candidates === null ? later : new Set([...candidates].filter((b) => later.has(b)));
    }
    if (!candidates || candidates.size === 0) continue;
    for (const [property, value, start] of a.decls) {
      if (value.includes("!important")) continue;
      for (const b of [...candidates].sort((x, y) => x.start - y.start)) {
        const hit = b.decls.find(([p, v]) => covers(p, property) && !v.includes("!important") && !NEWER_THAN_BASELINE.some((token) => v.includes(token)));
        if (hit) {
          dead.push([a, [property, value, start], b, hit]);
          break;
        }
      }
    }
  }
  return dead;
}

const clip = (text) => [...text].slice(0, 60).join("");

function main(argv) {
  const args = argv.filter((argument) => !argument.startsWith("--"));
  const path = args.length > 0 ? resolve(args[0]) : resolve(dirname(fileURLToPath(import.meta.url)), "styles.css");
  const text = readText(path);
  const line = (offset) => text.slice(0, offset).split("\n").length;
  const name = basename(path);
  const dead = findDead(text);
  for (const [a, [property, , start], b, [winnerProperty, , winnerStart]] of dead) {
    console.log(
      `${name}:${line(start)}: \`${property}\` of \`${clip(a.alts.join(", "))}\` is always overridden by \`${winnerProperty}\` at line ${line(winnerStart)} ` +
        `(\`${clip(b.alts.join(", "))}\`)`,
    );
  }
  if (dead.length > 0) {
    console.log(`\n${dead.length} dead declaration(s). Delete them, or move what differs into a variant rule.`);
    return 1;
  }
  console.log(`${name}: no dead declarations`);
  return 0;
}

if (isMain(import.meta.url)) process.exit(main(process.argv.slice(2)));
