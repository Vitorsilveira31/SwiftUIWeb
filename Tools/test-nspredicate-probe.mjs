#!/usr/bin/env bun
// The NSPredicate probe tooling (Tools/nspredicate-probe): the case list and the corpus it feeds to the predicate
// engine's test (`test-predicate-engine.mjs`). On a Mac with Xcode's command line tools the corpus is rebuilt from
// Apple's Foundation and must come out byte for byte the same as the checked-in file.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { main as buildCorpus } from "./nspredicate-probe/build-corpus.mjs";
import { buildCases, serialize } from "./nspredicate-probe/make-cases.mjs";
import { dumps, parseJson } from "./format-compat.mjs";
import { capture, finish, ROOT, test, withTemporary } from "./measurement-test-support.mjs";

const CORPUS = join(ROOT, "Tests/Fixtures/nspredicate_corpus.json");

await test("the case list is the checked-in one (8880 cases, same bytes)", () => {
  const corpus = buildCases();
  assert.equal(corpus.cases.length, 8880);
  const text = serialize(corpus);
  assert.equal(Buffer.byteLength(text), 1204138);
  assert.equal(createHash("sha256").update(text).digest("hex"), "e6932a674024da4fb27f01b9d3ad44306a4f83f47b8ede3e0906f85d9da7b600");
});

await test("the checked-in corpus records the generated cases and objects", () => {
  const generated = buildCases();
  const checkedIn = parseJson(readFileSync(CORPUS, "utf8"));
  // Foundation hands the arguments back with whole doubles as plain numbers (`0.0` -> `0`) and its dictionaries in
  // its own key order, so compare as numbers with sorted keys.
  const plain = (value) => dumps(JSON.parse(dumps(value ?? null)), { sortKeys: true });
  assert.equal(plain(checkedIn.objects), plain(generated.objects));
  assert.equal(checkedIn.cases.length, generated.cases.length);
  generated.cases.forEach((expected, index) => {
    const entry = checkedIn.cases[index];
    assert.equal(entry.f, expected.format, `case ${index}`);
    assert.equal(plain(entry.o), plain(expected.objects), `case ${index} objects`);
    assert.equal(plain(entry.a), plain(expected.args), `case ${index} args`);
    assert.equal(plain(entry.v), plain(expected.vars), `case ${index} vars`);
    assert.equal(entry.e === 1 || typeof entry.r === "string", true, `case ${index} outcome`);
  });
});

await test("rebuilding the corpus from Foundation reproduces the checked-in file", async () => {
  if (process.platform !== "darwin" || !Bun.which("clang")) {
    console.log("     (skipped: needs macOS and clang)");
    return;
  }
  await withTemporary((directory) => {
    const output = join(directory, "corpus.json");
    const printed = capture(() => buildCorpus(output)).out;
    assert.match(printed, /^8880 cases, \d+ evaluations -> /);
    assert.equal(readFileSync(output, "utf8"), readFileSync(CORPUS, "utf8"));
  });
});

finish();
