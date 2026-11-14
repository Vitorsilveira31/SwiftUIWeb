#!/usr/bin/env bun
// Runs independent test scripts at the same time and prints each one's output in one piece, in the order given, once it
// has finished: a list of `bun` scripts that used to run one after another in a make recipe.
//
//   bun Tools/run-scripts.mjs Tools/test-a.mjs "Tools/test-b.mjs --flag" "test ./Tools/test-c.mjs" ...
//
// Each argument is the argument list of one `bun` call, split on spaces. RUN_SCRIPTS_JOBS caps how many run together
// (default: the number of cores, at most 8); RUN_SCRIPTS_JOBS=1 runs them in order. The exit status is 1 when any
// script failed; every script runs to its end.
import { spawn } from "node:child_process";
import { availableParallelism } from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

export async function runScripts(commands, { jobs = Number(process.env.RUN_SCRIPTS_JOBS || Math.min(8, availableParallelism())), bun = process.execPath } = {}) {
  const results = new Array(commands.length);
  let next = 0;
  const run = (index) =>
    new Promise((done) => {
      const started = Date.now();
      const child = spawn(bun, commands[index].split(/\s+/).filter(Boolean), { cwd: ROOT, stdio: ["ignore", "pipe", "pipe"] });
      const chunks = [];
      child.stdout.on("data", (chunk) => chunks.push(chunk));
      child.stderr.on("data", (chunk) => chunks.push(chunk));
      child.on("close", (code, signal) => {
        results[index] = { command: commands[index], ok: code === 0, code: code ?? signal, output: Buffer.concat(chunks).toString("utf8"), seconds: (Date.now() - started) / 1000 };
        done();
      });
    });
  const worker = async () => {
    for (let index = next++; index < commands.length; index = next++) await run(index);
  };
  await Promise.all(Array.from({ length: Math.max(1, Math.min(jobs, commands.length)) }, worker));
  return results;
}

if (import.meta.main) {
  const commands = process.argv.slice(2);
  const started = Date.now();
  const results = await runScripts(commands);
  for (const result of results) {
    process.stdout.write(`$ bun ${result.command}  (${result.seconds.toFixed(1)}s)\n${result.output}`);
    if (!result.ok) process.stdout.write(`FAILED (${result.code}): bun ${result.command}\n`);
  }
  const failed = results.filter((result) => !result.ok);
  console.log(`${results.length - failed.length} of ${results.length} scripts passed in ${((Date.now() - started) / 1000).toFixed(1)}s`);
  process.exit(failed.length ? 1 : 0);
}
