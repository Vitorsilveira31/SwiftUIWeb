// A tap on a view with onTapGesture must reach the runtime on Safari for iOS. WebKit only synthesizes a click for an
// element it considers clickable, and the runtime delegates click handlers (data-embedded-events) instead of attaching
// them to the element, so styles.css marks those elements with cursor: pointer where there is no hover (touch screens).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const css = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "styles.css"), "utf8").replace(/\s+/g, " ");
const events = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "embedded-dom.js"), "utf8");

assert.match(events, /const EVENTS = 'data-embedded-events';/, "the runtime still marks delegated handlers with data-embedded-events");
assert.match(css, /@media \(hover: none\) \{ \[data-embedded-events\*="click"\] \{ cursor: pointer; \} \}/,
  "elements with a delegated click handler are marked clickable on touch screens");
// Mouse users keep the arrow over a plain tappable view: the rule must not apply where hover exists.
assert.ok(!/\[data-embedded-events\*="click"\] \{ cursor: pointer; \}/.test(css.replace(/@media \(hover: none\) \{[^}]*\{[^}]*\} \}/, "")),
  "the cursor rule exists only inside @media (hover: none)");
console.log("tap target css: ok");
