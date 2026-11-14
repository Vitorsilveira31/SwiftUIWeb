#!/usr/bin/env bun
// Computes the staging layout the Embedded launcher uses (replaces two inline snippets in run-browser-embedded.sh).
//
// usage: staging-layout.mjs relative-framework <framework-root> <consumer-root>
//        prints os.path.relpath(realpath(framework-root), realpath(consumer-root)).
//
//        staging-layout.mjs layout <staging-root> <relative-path>
//        prints two lines: the consumer's workspace and the framework's place in the topology. A relative path that goes
//        up levels gets one `levelN` directory per level, and a path ending in `..` gets a `swiftuiweb` directory first,
//        so the framework lands in a directory named swiftuiweb. An absolute path is an error.
import { writeSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { ToolExit, abspath, join, realpath, relpath, isAbs } from "./text-semantics.mjs";

// PurePosixPath(relative).parts for a relative path: empty and "." components are dropped.
const parts = (relative) => relative.split("/").filter((part) => part !== "" && part !== ".");

export function relativeFramework(frameworkRoot, consumerRoot) {
  return relpath(realpath(frameworkRoot), realpath(consumerRoot));
}

export function layout(staging, relative) {
  if (isAbs(relative)) {
    throw new ToolExit(
      "absolute path dependencies cannot be staged; use a relative path to the SwiftUIWeb checkout or set SWIFTUIWEB_LOWER_IN_PLACE=1",
    );
  }
  const components = parts(relative);
  const up = components.filter((part) => part === "..").length;
  const last = components.length ? components[components.length - 1] : "";
  const prefix =
    last === ".."
      ? ["swiftuiweb", ...Array.from({ length: Math.max(up - 1, 0) }, (_, index) => `level${index}`)]
      : Array.from({ length: up }, (_, index) => `level${index}`);
  const workspace = join(staging, ...prefix, "consumer");
  const framework = abspath(join(workspace, relative));
  return [workspace, framework];
}

export function main(argv = process.argv.slice(2)) {
  const [command, ...operands] = argv;
  try {
    if (command === "relative-framework") {
      if (operands.length !== 2) throw new Error(`not enough values to unpack (expected 2, got ${operands.length})`);
      writeSync(1, relativeFramework(operands[0], operands[1]) + "\n");
      return 0;
    }
    if (command === "layout") {
      if (operands.length !== 2) throw new Error(`not enough values to unpack (expected 2, got ${operands.length})`);
      for (const line of layout(operands[0], operands[1])) writeSync(1, line + "\n");
      return 0;
    }
    writeSync(2, "usage: staging-layout.mjs (relative-framework <framework-root> <consumer-root> | layout <staging-root> <relative-path>)\n");
    return 2;
  } catch (error) {
    if (error instanceof ToolExit) {
      writeSync(2, error.message + "\n");
      return error.code;
    }
    writeSync(2, `Traceback (most recent call last):\n${error.name}: ${error.message}\n`);
    return 1;
  }
}

if (process.argv[1] && realpath(process.argv[1]) === realpath(fileURLToPath(import.meta.url))) {
  process.exitCode = main();
}
