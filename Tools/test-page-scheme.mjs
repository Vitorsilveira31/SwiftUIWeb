#!/usr/bin/env bun
// The page's own color scheme comes from the first `data-color-scheme` that is not scoped to a subtree, else from the root's
// first child unless that one is scoped too (`.environment(\.colorScheme, ...)` writes `data-color-scheme-scope`): a scoped
// first child must not become the document's scheme and change the unmodified siblings beside it.
import assert from "node:assert/strict";
import { pageSchemeHost } from "./embedded-dom.js";

const element = (scoped) => ({ hasAttribute: (name) => name === "data-color-scheme-scope" && scoped });
const root = (unscoped, first) => ({ querySelector: () => unscoped, firstElementChild: first });

const preferred = element(false);
assert.equal(pageSchemeHost(root(preferred, element(true))), preferred, "an unscoped scheme in the subtree is the page's");
const plain = element(false);
assert.equal(pageSchemeHost(root(null, plain)), plain, "else the root's first child");
assert.equal(pageSchemeHost(root(null, element(true))), null, "a scoped first child is not the page's scheme: the page follows the system");
assert.equal(pageSchemeHost(root(null, null)), null, "an empty root has none");
console.log("page scheme test: OK");
