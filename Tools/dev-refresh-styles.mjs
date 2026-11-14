#!/usr/bin/env bun
// Refreshes the stylesheets of a development bundle without a Swift build: the fast path of Tools/dev-watch.mjs for a
// save that changed only .css files.
//
//   bun Tools/dev-refresh-styles.mjs --bundle <dir> --package-root <dir> --product <name> --framework-root <dir> --files <a.css,b.css>
//
// It writes what Tools/run-browser-embedded.sh writes for these sources, in the launcher's order, and nothing else:
//   - the framework's Tools/styles.css: the bundle's styles.css (Tools/build-styles.mjs);
//   - a .css file in an external package's resources directory (SWIFTUIWEB_RESOURCES, else Web/Resources, else
//     Resources): copied to the same relative path in the bundle, as the launcher's `cp -RL` does;
//   - the framework's Tools/showcase.css when the product is ShowcaseApp: the bundle's showcase.css.
// styles.css is rebuilt whatever changed, because Tools/scope-resize-transitions.mjs appends its rule to it and must see
// the bundle's stylesheets as a whole. That script then runs on the bundle, as the launcher runs it.
//
// The configuration is read from CONFIGURATION, as the launcher reads it (default release).
//
// Exit status:
//   0  the stylesheets of the bundle are refreshed (one summary line on stdout);
//   3  nothing was written: a changed file is not one of those sources, the bundle is missing, or the build is a release
//      (the launcher prunes release stylesheets against the build's manifest, which a refresh does not have);
//      the caller runs the normal build;
//   2  a usage error;
//   1  any other failure; the caller runs the normal build, which rewrites every file this could have touched.
import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync, statSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { parseArgs } from "node:util";

/** The exit status of "not a stylesheet-only save". */
export const NOT_REFRESHABLE = 3;

/** A reason the refresh does not apply. Thrown before anything is written. */
class NotRefreshable extends Error {}

const isDirectory = (path) => {
  try { return statSync(path).isDirectory(); } catch { return false; }
};
const isFile = (path) => {
  try { return statSync(path).isFile(); } catch { return false; }
};

/** The resources directory the launcher copies into an external package's bundle, or null. */
function resourcesDirectory(packageRoot, frameworkRoot, env) {
  if (env.SWIFTUIWEB_RESOURCES) {
    const dir = resolve(frameworkRoot, env.SWIFTUIWEB_RESOURCES);
    return isDirectory(dir) ? dir : null;
  }
  for (const candidate of [join(packageRoot, "Web/Resources"), join(packageRoot, "Resources")]) {
    if (isDirectory(candidate)) return candidate;
  }
  return null;
}

/**
 * Refreshes the stylesheets of `bundle` for the changed `files` (absolute, or relative to packageRoot). Returns the
 * bundle files it wrote. Throws NotRefreshable, before writing anything, when a file is not a stylesheet source.
 */
export function refreshStylesheets({ bundle, packageRoot, product, frameworkRoot, files, configuration, env = process.env }) {
  if (configuration === "release") throw new NotRefreshable("a release build prunes its stylesheets against the build manifest");
  if (!isDirectory(bundle) || !isFile(join(bundle, "styles.css"))) throw new NotRefreshable(`no built bundle in ${bundle}`);
  if (files.length === 0) throw new NotRefreshable("no changed files");

  const showcase = product === "ShowcaseApp";
  const frameworkStyles = join(frameworkRoot, "Tools/styles.css");
  const showcaseStyles = join(frameworkRoot, "Tools/showcase.css");
  // The launcher copies the resources only for an external package (PACKAGE_ROOT differs from the framework root).
  const external = resolve(packageRoot) !== resolve(frameworkRoot);
  const resources = external ? resourcesDirectory(packageRoot, frameworkRoot, env) : null;

  // Classify every file before writing: one unknown file sends the whole save to the build.
  const copies = [];
  let showcaseChanged = false;
  for (const file of files) {
    const path = resolve(packageRoot, file);
    if (!path.endsWith(".css")) throw new NotRefreshable(`${file} is not a stylesheet`);
    if (path === frameworkStyles) {
      if (!isFile(path)) throw new NotRefreshable(`${file} was removed`);
      continue;
    }
    if (showcase && path === showcaseStyles) {
      if (!isFile(path)) throw new NotRefreshable(`${file} was removed`);
      showcaseChanged = true;
      continue;
    }
    const rel = resources ? relative(resources, path) : "";
    const inResources = rel !== "" && !isAbsolute(rel) && rel.split(sep)[0] !== "..";
    if (!inResources) throw new NotRefreshable(`${file} is not a stylesheet source`);
    // The launcher writes these itself, after the resources, so a copy would not be what the bundle ends up with.
    if (rel === "styles.css" || (showcase && rel === "showcase.css")) throw new NotRefreshable(`${rel} is written by the launcher`);
    if (!isFile(path)) throw new NotRefreshable(`${file} was removed`);
    // A stylesheet the bundle does not have yet may need a link the launcher adds (app.css in index.html).
    if (!isFile(join(bundle, rel))) throw new NotRefreshable(`${rel} is new in the bundle`);
    copies.push({ from: path, rel });
  }

  const run = (script, args) => {
    try {
      execFileSync(process.execPath, [script, ...args], { cwd: frameworkRoot, env, stdio: ["ignore", "pipe", "pipe"] });
    } catch (error) {
      throw new Error(`${relative(frameworkRoot, script)} failed: ${String(error.stderr ?? error.message).trim()}`);
    }
  };

  run(join(frameworkRoot, "Tools/build-styles.mjs"), [join(bundle, "styles.css")]);
  const written = ["styles.css"];
  for (const { from, rel } of copies) {
    const to = join(bundle, rel);
    mkdirSync(dirname(to), { recursive: true });
    copyFileSync(from, to);
    written.push(rel);
  }
  if (showcaseChanged) {
    copyFileSync(showcaseStyles, join(bundle, "showcase.css"));
    written.push("showcase.css");
  }
  run(join(frameworkRoot, "Tools/scope-resize-transitions.mjs"), [bundle]);
  return written;
}

function main(argv) {
  let values;
  try {
    ({ values } = parseArgs({
      args: argv,
      strict: true,
      options: {
        bundle: { type: "string" }, "package-root": { type: "string" }, product: { type: "string" },
        "framework-root": { type: "string" }, files: { type: "string" },
      },
    }));
  } catch (error) {
    console.error(`dev-refresh-styles: ${error.message}`);
    return 2;
  }
  const missing = ["bundle", "package-root", "product", "framework-root", "files"].filter((name) => values[name] === undefined);
  if (missing.length) {
    console.error(`dev-refresh-styles: pass ${missing.map((name) => `--${name}`).join(", ")}`);
    return 2;
  }
  const bundle = resolve(values.bundle);
  try {
    const written = refreshStylesheets({
      bundle,
      packageRoot: resolve(values["package-root"]),
      product: values.product,
      frameworkRoot: resolve(values["framework-root"]),
      files: values.files.split(",").filter(Boolean),
      configuration: process.env.CONFIGURATION ?? "release",
    });
    console.log(`refreshed the stylesheets of ${bundle}: ${written.join(", ")}`);
    return 0;
  } catch (error) {
    if (error instanceof NotRefreshable) {
      console.error(`dev-refresh-styles: not a stylesheet-only save: ${error.message}`);
      return NOT_REFRESHABLE;
    }
    console.error(`dev-refresh-styles: ${error.message}`);
    return 1;
  }
}

if (import.meta.main) process.exitCode = main(process.argv.slice(2));
