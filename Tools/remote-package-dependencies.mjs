#!/usr/bin/env bun
// Lists the remote (URL) packages of a consumer that the Embedded launcher must stage and lower like local ones.
//
// usage: remote-package-dependencies.mjs DEPENDENCIES STAGING
//        remote-package-dependencies.mjs --declares-url MANIFEST...
//        remote-package-dependencies.mjs --rewrite LIST MANIFEST...
//
// DEPENDENCIES is the output of `swift package show-dependencies --format json` for the staged consumer, resolved with
// the browser build's environment (SWIFTUIWEB_EMBEDDED=1), and STAGING the staging topology's root. A package that
// depends on SwiftUIWeb is a browser package: its sources use the SwiftUI-shaped API and have to be lowered for Embedded
// Swift, so a URL dependency on it cannot be left to SwiftPM, which would build the unlowered sources. For each remote
// package of the graph that depends on SwiftUIWeb directly, prints "<url>\t<checkout>\t<destination>": the URL the
// manifests declare, SwiftPM's checkout of the resolved version, and the place in the staging topology where the
// launcher lowers it, `STAGING/remote/<repository name>`, so the package identity (the directory name) stays the one the
// URL gives. The launcher then rewrites every staged manifest's declaration of that URL to a path dependency on it
// (`--rewrite` below). Remote packages that do not depend on SwiftUIWeb stay URL dependencies.
// SwiftUIWeb itself is staged by the launcher and never listed.
//
// `--declares-url` exits 0 when one of the manifests declares a package by URL other than SwiftUIWeb (the launcher then
// resolves the graph), 1 otherwise. `--rewrite` takes the list this tool printed and rewrites, in each staged manifest,
// the declarations of those URLs to path dependencies on their staged copies, printing the manifests it changed.
import { existsSync, readFileSync, writeFileSync, writeSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { isFrameworkURL, normalizedURL, repositoryName, rewriteURLDependency, urlDependencies } from "./framework-url-dependency.mjs";

const isRemote = (node) => typeof node.url === "string" && !node.url.startsWith("/");
const isFramework = (node) => node.identity === "swiftuiweb" || (isRemote(node) && isFrameworkURL(node.url));

export function remotePackages(graph, staging) {
  const found = new Map();
  const destinations = new Map();
  const visit = (node) => {
    for (const dependency of node.dependencies ?? []) visit(dependency);
    if (!isRemote(node) || isFramework(node)) return;
    if (!(node.dependencies ?? []).some(isFramework)) return;
    const key = normalizedURL(node.url);
    if (found.has(key)) return;
    const destination = join(staging, "remote", repositoryName(node.url));
    const other = destinations.get(destination.toLowerCase());
    if (other !== undefined) {
      throw new Error(`the remote packages ${other} and ${node.url} would both be staged at ${destination}`);
    }
    destinations.set(destination.toLowerCase(), node.url);
    found.set(key, { url: node.url, checkout: node.path, destination });
  };
  visit(graph);
  return [...found.values()];
}

// Whether a manifest declares a package by URL other than SwiftUIWeb (in any configuration: the text is not evaluated).
export function declaresRemotePackage(text) {
  return urlDependencies(text, (url) => !isFrameworkURL(url)).length > 0;
}

const USAGE = [
  "usage: remote-package-dependencies.mjs DEPENDENCIES STAGING",
  "       remote-package-dependencies.mjs --declares-url MANIFEST...",
  "       remote-package-dependencies.mjs --rewrite LIST MANIFEST...",
].join("\n");

export function main(argv = process.argv.slice(2)) {
  if (argv[0] === "--declares-url" && argv.length > 1) {
    return argv.slice(1).some((manifest) => existsSync(manifest) && declaresRemotePackage(readFileSync(manifest, "utf8"))) ? 0 : 1;
  }
  if (argv[0] === "--rewrite" && argv.length > 2) {
    const entries = readFileSync(argv[1], "utf8").split("\n").filter(Boolean).map((line) => line.split("\t"));
    for (const manifest of argv.slice(2)) {
      if (!existsSync(manifest)) continue;
      const text = readFileSync(manifest, "utf8");
      const rewritten = entries.reduce(
        (current, [url, , destination]) => rewriteURLDependency(current, dirname(manifest), url, destination),
        text,
      );
      if (rewritten !== text) {
        writeFileSync(manifest, rewritten);
        writeSync(1, manifest + "\n");
      }
    }
    return 0;
  }
  if (argv.length !== 2 || argv[0].startsWith("--")) {
    writeSync(2, USAGE + "\n");
    return 2;
  }
  try {
    const graph = JSON.parse(readFileSync(argv[0], "utf8"));
    for (const { url, checkout, destination } of remotePackages(graph, argv[1])) {
      writeSync(1, `${url}\t${checkout}\t${destination}\n`);
    }
    return 0;
  } catch (error) {
    writeSync(2, `error: ${error.message}\n`);
    return 1;
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exitCode = main();
}
