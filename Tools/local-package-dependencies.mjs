#!/usr/bin/env bun
// Lists the local package dependencies of a consumer package that the Embedded launcher must stage.
//
// usage: local-package-dependencies.mjs CONSUMER WORKSPACE STAGING FRAMEWORK
//        local-package-dependencies.mjs --framework-path CONSUMER
//
// CONSUMER is the consumer's checkout, WORKSPACE its place in the staging topology, STAGING the topology's root and
// FRAMEWORK the SwiftUIWeb checkout (staged separately). For each `.package(path: "...")` that is a relative path to
// another package, prints "<source>\t<destination>": the checkout and the place in the topology that keeps the same
// relative path, so the manifest of the staged consumer finds it where it says. The libraries of those libraries are
// followed too: a library that depends on another local library (`../Shared`) gets it staged at its own relative place.
// Exits with an error when a destination would be outside the staging root (the path goes up more levels than the
// topology has).
//
// A path dependency whose last component is `swiftuiweb` is the framework, whatever checkout provides it (a worktree,
// a copy with another name): SwiftPM identifies a local package by that directory name, and the launcher stages the
// framework it builds with there. It is never staged as a library.
//
// With --framework-path, prints the consumer's relative path to SwiftUIWeb as its manifest declares it (empty when the
// manifest names none), which the launcher uses to place the staged framework.
import { writeSync } from "node:fs";
import { fileURLToPath } from "node:url";
import {
  ToolExit,
  abspath,
  basename,
  commonpath,
  isFile,
  join,
  normpath,
  reprString,
  readText,
  realpath,
  SPACE,
} from "./text-semantics.mjs";

const PATH_DEPENDENCY = new RegExp(
  String.raw`\.package\(${SPACE}*(?:name:${SPACE}*"[^"]*",${SPACE}*)?path:${SPACE}*"([^"]+)"`,
  "gu",
);

export function pathDependencies(packagePath) {
  const manifest = join(packagePath, "Package.swift");
  if (!isFile(manifest)) return [];
  const text = readText(manifest);
  return [...text.matchAll(PATH_DEPENDENCY)].map((match) => match[1]).filter((relative) => !relative.startsWith("/"));
}

export function isFramework(relative) {
  return basename(normpath(relative)).toLowerCase() === "swiftuiweb";
}

// Calls emit(line) for each line the tool prints, in order, and throws ToolExit for its error messages.
export function localPackageDependencies(args, emit) {
  if (args[0] === "--framework-path") {
    if (args.length < 2) throw new Error("list index out of range");
    emit(pathDependencies(args[1]).find(isFramework) ?? "");
    return;
  }
  if (args.length < 4) throw new Error("not enough values to unpack (expected 4, got " + args.length + ")");
  const [consumer, , , framework] = args.slice(0, 4).map(realpath);
  // Staging is a lexical topology (the consumer's own `..` chain is made of its level directories), so destinations
  // are computed without resolving symlinks.
  const workspace = normpath(abspath(args[1]));
  const staging = normpath(abspath(args[2]));
  const staged = new Map([
    [consumer, workspace],
    [framework, null],
  ]);
  const queue = [[consumer, workspace]];
  while (queue.length) {
    const [packagePath, packageWorkspace] = queue.shift();
    for (const relative of pathDependencies(packagePath)) {
      if (isFramework(relative)) continue;
      const source = realpath(join(packagePath, relative));
      if (staged.has(source) || !isFile(join(source, "Package.swift"))) continue;
      const destination = normpath(join(packageWorkspace, relative));
      if (commonpath([destination, staging]) !== staging || destination === workspace || destination === staging) {
        throw new ToolExit(
          `error: the local package dependency ${reprString(relative)} of ${packagePath}/Package.swift resolves outside the ` +
            `staging area (${staging}) and cannot be copied; keep local package dependencies at most as many ` +
            "levels up as the SwiftUIWeb dependency",
        );
      }
      if ([...staged.values()].includes(destination)) {
        throw new ToolExit(
          `error: the local package dependency ${reprString(relative)} of ${packagePath}/Package.swift would be staged at ` +
            `${destination}, where another package already is`,
        );
      }
      staged.set(source, destination);
      emit(`${source}\t${destination}`);
      queue.push([source, destination]);
    }
  }
}

export function main(argv = process.argv.slice(2)) {
  // Synchronous writes keep the lines printed before an error.
  try {
    localPackageDependencies(argv, (line) => writeSync(1, line + "\n"));
    return 0;
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
