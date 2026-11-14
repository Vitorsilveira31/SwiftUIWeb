#!/usr/bin/env bun
// Live literals in a real browser (Tests/Apps/MotionApp built with SWIFTUIWEB_LIVE_LITERALS=1): the replacements the
// development loop computes for a save that only changes literal values (`swiftuiweb-lowering --literal-diff`) are given
// to the running page, which renders again with the new values and keeps its state. On the main thread and in the worker.
// The bundle: the first argument, or LIVE_LITERALS_BUNDLE (built by `make live-literals-browser-test`).
// Engine: SWIFTUIWEB_BROWSER_ENGINE (chromium by default).
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { engineName, freePort, launch, runSuite, serveBundle, ROOT } from "./browser-test-support.mjs";

const BUNDLE = resolve(process.argv[2] ?? process.env.LIVE_LITERALS_BUNDLE ?? join(ROOT, ".build/live-literals/embedded/MotionApp"));
const SOURCE = "Tests/Apps/MotionApp/MotionRootView.swift";

/** The lines the watcher would send for `edit` applied to the fixture's source, or null when the edit needs a build. */
function replacements(edit) {
  const directory = mkdtempSync(join(tmpdir(), "live-literals-"));
  try {
    const original = readFileSync(join(ROOT, SOURCE), "utf8");
    const edited = edit(original);
    assert.notEqual(edited, original, "the edit changed the source");
    writeFileSync(join(directory, "old.swift"), original);
    writeFileSync(join(directory, "new.swift"), edited);
    const result = Bun.spawnSync(["/bin/bash", join(ROOT, "Tools/swiftuiweb-lowering.sh"), "--literal-diff", join(directory, "old.swift"), join(directory, "new.swift"), SOURCE], { stdout: "pipe", stderr: "pipe" });
    if (result.exitCode === 3) return null;
    assert.equal(result.exitCode, 0, result.stderr.toString());
    return result.stdout.toString().trim();
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

await runSuite(async () => {
  // What the lowerer decides, before any page: literal values are replaceable, anything else needs a build.
  const renamed = replacements((text) => text.replace('Button("Add")', 'Button("Add a row")').replace('Text("Box")', 'Text("Crate")'));
  assert.ok(renamed, "a save that only changes strings is replaceable");
  assert.equal(renamed.split("\n").length, 2);
  assert.match(renamed, /^\d+\ts\tAdd a row$/m);
  assert.equal(replacements((text) => text.replace('Button("Add")', 'Button("Add").bold()')), null, "a new modifier needs a build");
  assert.equal(replacements((text) => text.replace('Button("Add")', 'Button("Add \\(next)")')), null, "an interpolation is not a literal value");

  const server = await serveBundle({ bundle: BUNDLE, port: await freePort() });
  const browser = await launch();
  try {
    for (const query of ["?render-in-worker=0", ""]) {
      const where = query ? "main thread" : "worker";
      const page = await (await browser.newContext({ viewport: { width: 800, height: 900 } })).newPage();
      const problems = [];
      page.on("pageerror", (error) => problems.push(String(error)));
      page.on("console", (message) => { if (message.type() === "error") problems.push(message.text()); });
      await page.goto(`${server.base}/${query}`);
      await page.waitForSelector('[data-testid="row-1"]');
      const rows = () => page.evaluate(() => document.querySelectorAll('[data-testid^="row-"]').length);
      const label = (id) => page.evaluate((id) => document.querySelector(`[data-testid="${id}"]`)?.textContent ?? null, id);

      // State the replacement must keep: two more rows than the page starts with.
      const initial = await rows();
      await page.click('[data-testid="add"]');
      await page.click('[data-testid="add"]');
      await page.waitForFunction((count) => document.querySelectorAll('[data-testid^="row-"]').length === count, initial + 2);
      assert.equal(await label("add"), "Add", where);

      const taken = await page.evaluate((text) => window.__swiftuiwebLiveLiterals(text), renamed);
      assert.ok(taken > 0, `${where}: the page took the replacements (${taken})`);
      await page.waitForFunction(() => document.querySelector('[data-testid="add"]')?.textContent === "Add a row");
      assert.equal(await rows(), initial + 2, `${where}: the rows added before the replacement are still there`);
      assert.equal(await label("remove"), "Remove", `${where}: a literal that was not replaced keeps its value`);

      // The page still works after it, and a second replacement of the same literal wins over the first.
      await page.click('[data-testid="add"]');
      await page.waitForFunction((count) => document.querySelectorAll('[data-testid^="row-"]').length === count, initial + 3);
      const again = replacements((text) => text.replace('Button("Add")', 'Button("More")'));
      await page.evaluate((text) => window.__swiftuiwebLiveLiterals(text), again);
      await page.waitForFunction(() => document.querySelector('[data-testid="add"]')?.textContent === "More");
      assert.equal(await rows(), initial + 3, where);
      assert.deepEqual(problems, [], where);
      await page.close();
    }
  } finally {
    await browser.close();
    await server.stop();
  }
  console.log(`PASS ${engineName()}: literal values are replaced in the running page, on the main thread and in the worker, and its state is kept`);
});
