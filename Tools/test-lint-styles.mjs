#!/usr/bin/env bun
// Tests for Tools/lint-styles.mjs, and the lint itself on Tools/styles.css.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { readText, runCases } from "./audit-support.mjs";
import { findDead } from "./lint-styles.mjs";

const TOOLS = dirname(fileURLToPath(import.meta.url));

/** ['<loser selector> <property>'] for every dead declaration of a small stylesheet. */
const dead = (css) => findDead(css).map(([rule, declaration]) => `${rule.alts.join(", ")} ${declaration[0]}`);

await runCases({
  "same selector later wins"() {
    assert.deepEqual(dead("@layer c { .a { color: red; margin: 0; } .a { color: blue; } }"), [".a color"]);
  },
  "different property is live"() {
    assert.deepEqual(dead("@layer c { .a { color: red; } .a { background: blue; } }"), []);
  },
  "a later rule with more selectors shadows"() {
    assert.deepEqual(dead("@layer c { .a { color: red; } .b, .a { color: blue; } }"), [".a color"]);
  },
  "a later rule covering only some selectors does not"() {
    assert.deepEqual(dead("@layer c { .a, .b { color: red; } .a { color: blue; } }"), []);
  },
  "an earlier winner does not shadow"() {
    assert.deepEqual(dead("@layer c { .a { color: blue; } .a { margin: 0; } }"), []);
  },
  "important is never reported"() {
    assert.deepEqual(dead("@layer c { .a { color: red !important; } .a { color: blue; } }"), []);
  },
  "a shorthand covers its longhands but not unrelated ones"() {
    assert.deepEqual(dead("@layer c { .a { border-color: red; border-radius: 4px; } .a { border: 1px solid blue; } }"), [".a border-color"]);
  },
  "outline does not reset outline-offset"() {
    assert.deepEqual(dead("@layer c { .a { outline-offset: 2px; } .a { outline: 1px solid; } }"), []);
  },
  "vendor alias is not the same property"() {
    assert.deepEqual(dead("@layer c { .a { -webkit-backdrop-filter: blur(4px); } .a { backdrop-filter: blur(4px); } }"), []);
  },
  "a different media context is not compared"() {
    assert.deepEqual(dead("@layer c { .a { color: red; } @media (min-width: 10px) { .a { color: blue; } } }"), []);
  },
  "a different layer is not compared"() {
    assert.deepEqual(dead("@layer one { .a { color: red; } } @layer two { .a { color: blue; } }"), []);
  },
  "the same layer in two blocks is one cascade"() {
    assert.deepEqual(dead("@layer c { .a { color: red; } } @layer c { .a { color: blue; } }"), [".a color"]);
  },
  "nested rule against a flat rule"() {
    assert.deepEqual(dead("@layer c { .a { &:hover { color: red; } } .a:hover { color: blue; } }"), [".a:hover color"]);
  },
  "nested rule with a stronger flat rule elsewhere stays"() {
    assert.deepEqual(dead("@layer c { .a { &:hover { color: red; } } .a:hover:not(:disabled) { color: blue; } }"), []);
  },
  "nested rule under parents of different specificity is left alone"() {
    assert.deepEqual(dead("@layer c { .a, .b.c { &:hover { color: red; } } .a:hover { color: blue; } }"), []);
  },
  "a winner using a newer function shadows nothing"() {
    assert.deepEqual(dead("@layer c { .a { color: red; } .a { color: light-dark(red, blue); } }"), []);
  },
  "the stylesheet has no dead declarations"() {
    const found = findDead(readText(join(TOOLS, "styles.css"))).map(([rule, declaration]) => `${rule.alts[0]} ${declaration[0]}`);
    assert.deepEqual(found, [], "Tools/styles.css has declarations that a later rule always overrides; run `bun Tools/lint-styles.mjs`");
  },
  "the command line reports a dead declaration with its line and exits 1"() {
    const work = mkdtempSync(join(tmpdir(), "lint-styles-"));
    try {
      const file = join(work, "broken.css");
      writeFileSync(file, "@layer c {\n  .a { color: red; }\n  .a { color: blue; }\n}\n");
      const run = spawnSync("bun", [join(TOOLS, "lint-styles.mjs"), file], { encoding: "utf8" });
      assert.equal(run.status, 1);
      assert.equal(
        run.stdout,
        "broken.css:2: `color` of `.a` is always overridden by `color` at line 3 (`.a`)\n\n1 dead declaration(s). Delete them, or move what differs into a variant rule.\n",
      );
      writeFileSync(file, "@layer c {\n  .a { color: red; }\n  .a { margin: 0; }\n}\n");
      const clean = spawnSync("bun", [join(TOOLS, "lint-styles.mjs"), file], { encoding: "utf8" });
      assert.equal(clean.status, 0);
      assert.equal(clean.stdout, "broken.css: no dead declarations\n");
    } finally {
      rmSync(work, { recursive: true, force: true });
    }
  },
}, "test-lint-styles");
