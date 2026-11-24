#!/usr/bin/env bun
// Copies the browser files of a consumer's local packages into its Embedded bundle.
//
// usage: package-web-resources.mjs CONSUMER BUNDLE
//
// A library package can keep browser-only files in its own `Web/Resources/` (the page service or the component its web
// target drives, a JavaScript SDK it vendors), so an application that depends on it ships them without copies of its own.
// For each local package the consumer depends on (`.package(path: "...")`, followed transitively, SwiftUIWeb itself
// excepted) that has a `Web/Resources/` directory:
//
// * every file in it is copied to the same relative place in BUNDLE, links followed (a link must stay inside the
//   package, as for the application's own resources); names that start with "." are skipped;
// * its `head.html` is not copied but appended, after a comment that names the package, to BUNDLE/.package-head.html,
//   which the launcher puts before the application's own head.html, so the application's fragment comes last.
//
// A file two packages both ship, or one that would replace a file already in BUNDLE (the framework's), stops the build.
// The application's resources are copied after this, so an application file of the same name replaces a package's.
// Prints one line per package copied.
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { isFramework, pathDependencies } from "./local-package-dependencies.mjs";

export const HEAD_FILE = ".package-head.html";

class ToolExit extends Error {}

/** The consumer's local package dependencies, breadth first, each once, by real path. */
export function localPackages(consumer) {
  const root = realpathSync(consumer);
  const seen = new Set([root]);
  const queue = [root];
  const packages = [];
  while (queue.length) {
    const current = queue.shift();
    for (const relativePath of pathDependencies(current)) {
      if (isFramework(relativePath)) continue;
      let source;
      try { source = realpathSync(join(current, relativePath)); } catch { continue; }
      if (seen.has(source) || !existsSync(join(source, "Package.swift"))) continue;
      seen.add(source);
      packages.push(source);
      queue.push(source);
    }
  }
  return packages;
}

/** The files under `directory` (links followed), as paths relative to it; every one must resolve inside `boundary`. */
function filesIn(directory, boundary) {
  const out = [];
  const visit = (absolute, relativePath, depth) => {
    if (depth > 64) throw new ToolExit(`error: ${absolute} is nested too deeply (a link loop?)`);
    let target;
    try { target = realpathSync(absolute); } catch { throw new ToolExit(`error: ${absolute} points to a missing file`); }
    if (target !== boundary && !target.startsWith(boundary + sep)) {
      throw new ToolExit(`error: ${absolute} points outside the package (${target}); resources may only link inside ${boundary}`);
    }
    if (statSync(absolute).isDirectory()) {
      for (const name of readdirSync(absolute).sort()) {
        if (!name.startsWith(".")) visit(join(absolute, name), relativePath ? join(relativePath, name) : name, depth + 1);
      }
    } else {
      out.push(relativePath);
    }
  };
  visit(directory, "", 0);
  return out;
}

export function copyPackageResources(consumer, bundle, log = () => {}) {
  const shippedBy = new Map();
  const headPath = join(bundle, HEAD_FILE);
  let heads = "";
  for (const source of localPackages(consumer)) {
    const resources = join(source, "Web", "Resources");
    if (!existsSync(resources) || !statSync(resources).isDirectory()) continue;
    const name = basename(source);
    const files = filesIn(resources, source);
    for (const file of files) {
      if (file === "head.html") continue;
      const owner = shippedBy.get(file);
      if (owner) throw new ToolExit(`error: ${file} is in the browser resources of both ${owner} and ${name}; rename one`);
      const destination = join(bundle, file);
      if (existsSync(destination)) throw new ToolExit(`error: ${file} from ${name}'s browser resources would replace the bundle's own ${file}`);
      shippedBy.set(file, name);
    }
    for (const file of files) {
      if (file === "head.html") {
        heads += `<!-- ${name} (its Web/Resources/head.html) -->\n${readFileSync(join(resources, file), "utf8").replace(/\s*$/, "\n")}`;
        continue;
      }
      const destination = join(bundle, file);
      mkdirSync(dirname(destination), { recursive: true });
      copyFileSync(join(resources, file), destination);
    }
    log(`copied the browser resources of ${name} (${files.length} files)`);
  }
  if (heads) writeFileSync(headPath, heads);
  return { heads, files: [...shippedBy.keys()] };
}

export function main(argv = process.argv.slice(2)) {
  if (argv.length !== 2) {
    console.error("usage: package-web-resources.mjs CONSUMER BUNDLE");
    return 2;
  }
  try {
    copyPackageResources(resolve(argv[0]), resolve(argv[1]), (line) => console.log(line));
    return 0;
  } catch (error) {
    if (error instanceof ToolExit) { console.error(error.message); return 1; }
    throw error;
  }
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) process.exit(main());
