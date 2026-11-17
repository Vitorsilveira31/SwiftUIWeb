#!/usr/bin/env bun
// A seeded fuzz of the page's binary publication reader and builder (Tools/binary-publication.js) in a real browser: each
// fixture Swift's encoder wrote (Tests/Fixtures/BinaryPublication) is mutated (words set to small, large and out-of-range
// values, bytes flipped, the string table cut, the stream truncated or extended), half the time with a header the page
// accepts, so the builder runs on it. Every damaged publication must be answered within a time budget (built, or refused
// with an error), and no script element may ever be built. The publications come from the application's own WebAssembly
// module, so this is robustness of the decoder against a bug in the encoder, not an outside attacker.
//
//   bun Tools/test-binary-publication-fuzz.mjs [count per fixture] [seed]
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { launch, runSuite, serveStatic } from "./browser-test-support.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const FIXTURES = join(ROOT, "Tests/Fixtures/BinaryPublication");
const COUNT = Number(process.argv[2] ?? 400);
const SEED = Number(process.argv[3] ?? 0x5eed);

await runSuite(async () => {
  const fixtures = readdirSync(FIXTURES).filter((file) => file.endsWith(".bin")).sort()
    .map((file) => ({ name: file.slice(0, -4), bytes: [...readFileSync(join(FIXTURES, file))] }));
  assert.ok(fixtures.length > 10, "the binary publication fixtures are missing");
  const server = serveStatic(join(ROOT, "Tools"));
  const browser = await launch();
  try {
  // Mulberry32: small, seeded, the same sequence on every run.
  let state = SEED >>> 0;
  const random = () => { state = (state + 0x6d2b79f5) >>> 0; let x = state; x = Math.imul(x ^ (x >>> 15), x | 1); x ^= x + Math.imul(x ^ (x >>> 7), x | 61); return ((x ^ (x >>> 14)) >>> 0) / 4294967296; };
  const pick = (n) => Math.floor(random() * n);
  const HEADER = 28;
  const mutate = (original) => {
    const bytes = Uint8Array.from(original);
    const view = new DataView(bytes.buffer);
    const words = Math.max(0, Math.floor((bytes.length - HEADER) / 4));
    for (let step = 1 + pick(4); step > 0; step--) {
      const kind = pick(7);
      if (kind <= 2 && words > 0) {
        // A word of the stream: an opcode, a count, a string index or a handle.
        const at = HEADER + 4 * pick(words);
        const values = [0, 1, 2, 3, 7, 0xff, 0xffff, 0x7fffffff, 0xffffffff, pick(64), pick(4096)];
        if (at + 4 <= bytes.length) view.setUint32(at, values[pick(values.length)], true);
      } else if (kind === 3 && bytes.length > 0) {
        bytes[pick(bytes.length)] ^= 1 << pick(8);
      } else if (kind === 4 && bytes.length >= HEADER) {
        // The header's word count, string count or string bytes.
        const field = [16, 20, 24][pick(3)];
        view.setUint32(field, [0, 1, view.getUint32(field, true) + 1, view.getUint32(field, true) - 1, 0x7fffffff][pick(5)] >>> 0, true);
      } else if (kind === 5) {
        return bytes.slice(0, pick(bytes.length + 1));
      } else {
        const longer = new Uint8Array(bytes.length + 4 * (1 + pick(16)));
        longer.set(bytes);
        for (let i = bytes.length; i < longer.length; i++) longer[i] = pick(256);
        return longer;
      }
    }
    return bytes;
  };
  // One page call per case, so a case that never returns is caught by its own deadline and reported with its bytes.
  const open = async () => {
    const page = await browser.newPage();
    await page.goto(`${server.base}/binary-publication.js`);
    await page.evaluate(async (base) => {
      const module = await import(`${base}/binary-publication.js`);
      window.__fuzz = (list) => {
        const { readPublication, Builder, Handles, scanRecords, rootHoverRules } = module;
        const inert = document.implementation.createHTMLDocument("");
        const kind = (error) => error instanceof Error ? error.constructor.name : `non-error ${String(error).slice(0, 80)}`;
        let publication;
        try { publication = readPublication(Uint8Array.from(list)); } catch (error) { return { built: false, error: kind(error) }; }
        // The same words read as an update's records and as a root's hover rules: refusing is fine, hanging is not.
        let records = null;
        try { scanRecords(publication); rootHoverRules(publication); } catch (error) { records = kind(error); }
        try {
          const built = new Builder(publication, inert, new Handles()).buildRoot();
          return { built: true, script: !!(built && built.querySelector && built.querySelector("script")), records };
        } catch (error) {
          return { built: false, error: kind(error), records };
        }
      };
    }, server.base);
    return page;
  };
  let page = await open();
  const outcomes = { built: 0, refused: 0 };
  const errors = {};
  const problems = [];
  for (const fixture of fixtures) {
    for (let round = 0; round < COUNT; round++) {
      const bytes = [...mutate(fixture.bytes)];
      let timer;
      const deadline = new Promise((resolve) => { timer = setTimeout(() => resolve(null), 5_000); });
      const answer = await Promise.race([page.evaluate((list) => window.__fuzz(list), bytes), deadline]);
      clearTimeout(timer);
      if (answer === null) {
        problems.push(`${fixture.name} #${round}: no answer in 5 s; bytes ${Buffer.from(bytes).toString("base64")}`);
        await page.close().catch(() => {});
        page = await open();
        continue;
      }
      if (answer.built) outcomes.built++; else { outcomes.refused++; errors[answer.error] = (errors[answer.error] ?? 0) + 1; }
      if (answer.script) problems.push(`${fixture.name} #${round}: a script was built`);
      if (answer.records?.startsWith("non-error")) problems.push(`${fixture.name} #${round}: the records threw a ${answer.records}`);
      if (answer.error?.startsWith("non-error")) problems.push(`${fixture.name} #${round}: threw a ${answer.error}`);
      if (problems.length >= 5) break;
    }
    if (problems.length >= 5) break;
  }
  assert.deepEqual(problems, [], `damaged publications misbehaved (seed ${SEED}):\n  ${problems.join("\n  ")}`);
  const total = outcomes.built + outcomes.refused;
  assert.equal(total, fixtures.length * COUNT);
  assert.ok(outcomes.built > 0 && outcomes.refused > 0, `the fuzz reaches both the builder and the checks: ${JSON.stringify({ outcomes, errors })}`);
  console.log(`PASS binary publication fuzz: ${total} damaged publications (seed ${SEED}), ${outcomes.built} built, ${outcomes.refused} refused ${JSON.stringify(errors)}, no script built`);
  } finally {
    await browser.close();
    server.stop?.();
  }
});
