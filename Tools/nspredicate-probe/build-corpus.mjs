#!/usr/bin/env bun
// Rebuilds Tests/Fixtures/nspredicate_corpus.json from make-cases.mjs and Apple's Foundation.
//
//     bun build-corpus.mjs
//
// Compiles probe.m, runs the cases through it (bisecting around any case that crashes the process) and writes the
// compact corpus Tools/test-predicate-engine.mjs replays. Needs a Mac with Xcode's command line tools.
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { dumps, parseJson } from "../format-compat.mjs";
import { buildCases } from "./make-cases.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = resolve(HERE, "../../Tests/Fixtures/nspredicate_corpus.json");

/** Run the probe over `cases`, splitting the batch in two whenever the probe process dies or hangs. */
export function probe(binary, objects, cases, run = runBatch) {
  const answer = (batch) => {
    if (!batch.length) return [];
    const answered = run(binary, objects, batch);
    if (answered !== null) return answered;
    if (batch.length === 1) throw new Error(`Foundation crashed on ${dumps(batch[0], { ensureAscii: false })}`);
    const middle = Math.floor(batch.length / 2);
    return [...answer(batch.slice(0, middle)), ...answer(batch.slice(middle))];
  };
  return answer(cases);
}

function runBatch(binary, objects, batch) {
  const directory = mkdtempSync(join(tmpdir(), "nspredicate-probe-"));
  try {
    const source = join(directory, "in.json");
    const result = join(directory, "out.json");
    writeFileSync(source, dumps({ objects, cases: batch }));
    const finished = spawnSync(binary, [source, result], { timeout: 60000, stdio: "ignore" });
    if (finished.status === 0 && !finished.error) return parseJson(readFileSync(result, "utf8")).cases;
    return null;
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

/** The compact corpus entry for one case Foundation answered. */
export function compactCase(item) {
  const apple = item.apple;
  const entry = { f: item.format, o: item.objects };
  if ("args" in item) entry.a = item.args;
  if ("vars" in item) entry.v = item.vars;
  if (apple.parse !== "ok") entry.e = 1;
  else {
    entry.p = apple.format;
    if ("substituted" in apple) entry.s = apple.substituted;
    entry.r = apple.results.map((r) => (r === true ? "T" : r === false ? "F" : "X")).join("");
  }
  return entry;
}

export function main(output = OUT) {
  const directory = mkdtempSync(join(tmpdir(), "nspredicate-corpus-"));
  let data;
  let answered;
  try {
    const binary = join(directory, "probe");
    const compiled = spawnSync("clang", ["-fobjc-arc", "-framework", "Foundation", join(HERE, "probe.m"), "-o", binary], { stdio: "inherit" });
    if (compiled.status !== 0) throw new Error(`Command 'clang' returned non-zero exit status ${compiled.status ?? compiled.error?.message}.`);
    data = buildCases();
    answered = probe(binary, data.objects, data.cases);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
  const compact = answered.map(compactCase);
  writeFileSync(output, dumps({ objects: data.objects, cases: compact }, { ensureAscii: false, separators: [",", ":"] }));
  console.log(compact.length, "cases,", compact.reduce((sum, item) => sum + item.o.length, 0), "evaluations ->", relative(HERE, output));
}

if (import.meta.main) {
  try {
    main();
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}
