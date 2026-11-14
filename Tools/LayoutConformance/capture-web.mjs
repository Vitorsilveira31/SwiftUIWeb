#!/usr/bin/env bun
// Captures the SwiftUIWeb side of the layout conformance fixtures: node geometry relative to each fixture host.
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { launch, ROOT, runSuite } from "../browser-test-support.mjs";

await runSuite(async () => {
  const { values: a } = parseArgs({
    options: {
      url: { type: "string", default: "http://127.0.0.1:8099/" },
      output: { type: "string" },
    },
  });
  if (!a.output) throw new Error("the following arguments are required: --output");
  const manifest = JSON.parse(readFileSync(join(ROOT, "Tools/LayoutConformance/fixtures.json"), "utf8"));
  const sortKeys = (value) => {
    if (Array.isArray(value)) return value.map(sortKeys);
    if (value !== null && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map((key) => [key, sortKeys(value[key])]));
    return value;
  };
  const dump = (value) => JSON.stringify(sortKeys(value), null, 2) + "\n";
  const browser = await launch();
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
    await page.goto(a.url, { waitUntil: "networkidle" });
    await page.evaluate("document.fonts && document.fonts.ready");
    await page.waitForTimeout(100);
    const nodes = {};
    for (const fixture of manifest.fixtures) {
      const hostId = fixture.id + ".host";
      const host = await page.locator(`[data-testid="${hostId}"]`).boundingBox();
      if (!host) throw new Error(`missing host ${hostId}`);
      for (const nodeId of fixture.nodes) {
        const box = await page.locator(`[data-testid="${nodeId}"]`).boundingBox();
        if (!box) throw new Error(`missing node ${nodeId}`);
        nodes[nodeId] = { x: box.x - host.x, y: box.y - host.y, width: box.width, height: box.height };
      }
    }
    writeFileSync(a.output, dump({ platform: "SwiftUIWeb", nodes }));
  } finally {
    await browser.close();
  }
  console.log(`SwiftUIWeb geometry: ${a.output}`);
});
