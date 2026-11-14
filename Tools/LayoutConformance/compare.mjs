#!/usr/bin/env bun
// Compares the node frames SwiftUI reports (Apple) with the ones the web build lays out, per fixture tolerance,
// and writes the report. Exits 1 when a node is missing or off by more than its tolerance.
import { readFileSync, writeFileSync } from "node:fs";
import { fixed, parseArguments } from "../format-compat.mjs";

const FRAME = ["x", "y", "width", "height"];

/** Compare two captures against a fixtures spec; returns the report lines and the failures. */
export function compare(apple, web, spec) {
  const rows = [];
  const failed = [];
  for (const fixture of spec.fixtures) {
    const tolerance = Number(fixture.tolerance ?? 1.0);
    for (const node of fixture.nodes) {
      const a = apple.nodes[node] ?? null;
      const w = web.nodes[node] ?? null;
      if (a === null || w === null) {
        failed.push(`${node}: missing ${a === null ? "Apple " : ""}${w === null ? "Web" : ""}`);
        continue;
      }
      const diffs = Object.fromEntries(FRAME.map((key) => [key, Math.abs(Number(a[key]) - Number(w[key]))]));
      const ok = Math.max(...Object.values(diffs)) <= tolerance;
      rows.push([fixture.id, node, tolerance, a, w, diffs, ok]);
      if (!ok) failed.push(`${node}: max delta ${fixed(Math.max(...Object.values(diffs)), 2)} > ${fixed(tolerance, 2)}`);
    }
  }
  const lines = [
    "# SwiftUI Geometry Conformance Report",
    "",
    `Apple: ${apple.os ?? "unknown"}`,
    "",
    "| Fixture | Node | Tol | Apple size | Web size | Δx | Δy | Δw | Δh | Status |",
    "|---|---|---:|---:|---:|---:|---:|---:|---:|---|",
  ];
  for (const [id, node, tolerance, a, w, d, ok] of rows) {
    lines.push(`| ${id} | \`${node}\` | ${fixed(tolerance, 1)} | ${fixed(a.width, 2)}×${fixed(a.height, 2)} | ${fixed(w.width, 2)}×${fixed(w.height, 2)} | ${fixed(d.x, 2)} | ${fixed(d.y, 2)} | ${fixed(d.width, 2)} | ${fixed(d.height, 2)} | ${ok ? "PASS" : "FAIL"} |`);
  }
  const passed = rows.filter((row) => row[row.length - 1]).length;
  lines.push("", `Result: **${failed.length ? "FAIL" : "PASS"}** (${passed}/${rows.length} measured nodes within tolerance)`);
  if (failed.length) lines.push("", "## Failures", ...failed.map((item) => `- ${item}`));
  return { lines, failed };
}

export function main(argv) {
  const args = parseArguments({
    prog: "compare.mjs",
    options: ["apple", "web", "fixtures", "report"].map((name) => ({ names: [`--${name}`], dest: name, type: "string", required: true })),
  }, argv);
  const read = (path) => JSON.parse(readFileSync(path, "utf8"));
  const { lines, failed } = compare(read(args.apple), read(args.web), read(args.fixtures));
  writeFileSync(args.report, `${lines.join("\n")}\n`);
  console.log(lines.join("\n"));
  return failed.length ? 1 : 0;
}

if (import.meta.main) process.exit(main(process.argv.slice(2)));
