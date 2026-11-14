#!/usr/bin/env bun
// Lists the lines of Sources/ that mark a wasm32 or Embedded boundary as unavailable, unsupported or a no-op.
import { join } from "node:path";
import { filesWithSuffix, fromRoot, jsonDumps, stripWhitespace, readTextLossy, ROOT, splitlines } from "./audit-support.mjs";

const BOUNDARY = /arch\(wasm32\).*?!hasFeature\(Embedded\)|hasFeature\(Embedded\).*?(?:unavailable|unsupported|no-op)/i;
const rows = [];
for (const path of filesWithSuffix(join(ROOT, "Sources"), ".swift")) {
  splitlines(readTextLossy(path)).forEach((line, index) => {
    if (BOUNDARY.test(line)) rows.push({ file: fromRoot(path), line: index + 1, text: stripWhitespace(line) });
  });
}
console.log(jsonDumps({ status: "AUDIT", embedded_boundary_hits: rows.length, items: rows }));
