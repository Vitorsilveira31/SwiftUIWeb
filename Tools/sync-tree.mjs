#!/usr/bin/env bun
// Makes <to> an exact copy of <from> while rewriting only the files whose bytes differ.
//
//   bun Tools/sync-tree.mjs <from> <to>        prints "changed N, removed M, unchanged K"
//
// The Embedded build lowers the sources into a fresh folder on every run. SwiftPM and the Swift driver decide what to
// recompile from file modification times, so a fresh copy makes every run a full build. The development loop lowers
// into the fresh folder as before and syncs it into a folder that lives between runs: a file that did not change keeps
// its modification time, and only the modules that did change are compiled again.
import { copyFileSync, lstatSync, mkdirSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

// Folders the build writes into its own tree (the lowerer's state under `.build`): never copied, never deleted.
const LEFT_ALONE = new Set([".build"]);

export function syncTree(from, to, onChange = () => {}) {
  const counts = { changed: 0, removed: 0, unchanged: 0 };
  const walk = (source, destination) => {
    mkdirSync(destination, { recursive: true });
    // Symbolic links are left out, never followed: a link can point outside the tree, or into a cycle. A destination entry
    // of the same name is then removed like any entry the source does not have.
    const names = new Set(
      readdirSync(source).filter((name) => !LEFT_ALONE.has(name) && !lstatSync(join(source, name)).isSymbolicLink()),
    );
    for (const name of readdirSync(destination)) {
      if (!names.has(name) && !LEFT_ALONE.has(name)) {
        rmSync(join(destination, name), { recursive: true, force: true });
        counts.removed++;
        onChange("removed", join(destination, name));
      }
    }
    for (const name of names) {
      const src = join(source, name);
      const dst = join(destination, name);
      const info = lstatSync(src);
      if (info.isDirectory()) {
        // A link at the destination is removed, not written through (`rmSync` removes the link itself).
        const current = lstatSync(dst, { throwIfNoEntry: false });
        if (current && !current.isDirectory()) rmSync(dst, { recursive: true, force: true });
        walk(src, dst);
        continue;
      }
      const current = lstatSync(dst, { throwIfNoEntry: false });
      if (current?.isSymbolicLink()) {
        rmSync(dst, { force: true });
      } else if (current?.isDirectory()) {
        rmSync(dst, { recursive: true, force: true });
      } else if (current && current.size === info.size && readFileSync(src).equals(readFileSync(dst))) {
        counts.unchanged++;
        continue;
      }
      mkdirSync(dirname(dst), { recursive: true });
      copyFileSync(src, dst);
      counts.changed++;
      onChange("changed", dst);
    }
  };
  walk(resolve(from), resolve(to));
  return counts;
}

if (import.meta.main) {
  const [from, to, flag] = process.argv.slice(2);
  if (!from || !to) {
    console.error("usage: bun Tools/sync-tree.mjs <from> <to> [--list]");
    process.exit(64);
  }
  // --list names each file that was rewritten or removed, on stderr (to find files that change without an edit).
  const { changed, removed, unchanged } = syncTree(from, to, flag === "--list" ? (kind, path) => console.error(`  ${kind}: ${path}`) : undefined);
  console.log(`changed ${changed}, removed ${removed}, unchanged ${unchanged}`);
}
