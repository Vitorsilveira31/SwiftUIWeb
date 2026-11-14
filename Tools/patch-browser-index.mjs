#!/usr/bin/env bun
// Edits the generated browser index.html for the Embedded launcher (replaces two inline snippets in
// run-browser-embedded.sh). Text is read and written as UTF-8 with universal newlines.
//
// usage: patch-browser-index.mjs embedded-bootstrap <index.html>
//        Embedded owns bootstrap directly: the import of init becomes the instantiate entry point.
//        patch-browser-index.mjs showcase-host <index.html>
//        Adds the showcase stylesheet and host preload before </head> and mounts the documentation host as a plugin.
//        Fails (and leaves the file unchanged) when the bootstrap line it expects is not there.
import { writeSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { ToolExit, readText, realpath, writeText } from "./text-semantics.mjs";

const BOOTSTRAP_IMPORT = 'const { init } = await import(new URL("./index.js", document.baseURI).href);';
const EMBEDDED_IMPORT = 'const { instantiate: init } = await import(new URL("./index.js", document.baseURI).href);';
const SHOWCASE_HEAD = '  <link rel="stylesheet" href="./showcase.css">\n  <link rel="modulepreload" href="./showcase-host.js">\n</head>';
const SHOWCASE_INIT = "await init(undefined, { performanceDiagnostics })";
const SHOWCASE_INIT_PLUGIN =
  'await init(undefined, { performanceDiagnostics, plugins: [(await import("./showcase-host.js")).mountShowcaseHost] })';

// Replaces every occurrence.
export function embeddedBootstrap(text) {
  return text.replaceAll(BOOTSTRAP_IMPORT, EMBEDDED_IMPORT);
}

export function showcaseHost(text) {
  let patched = text.replaceAll("</head>", SHOWCASE_HEAD);
  // The bootstrap imports the documentation host inside its try block, so a failed download is reported like any other
  // start-up failure.
  if (!patched.includes(SHOWCASE_INIT)) {
    throw new ToolExit("Showcase bootstrap changed: cannot mount the documentation host");
  }
  patched = patched.replaceAll(SHOWCASE_INIT, SHOWCASE_INIT_PLUGIN);
  return patched;
}

export function main(argv = process.argv.slice(2)) {
  const [command, file] = argv;
  const patches = { "embedded-bootstrap": embeddedBootstrap, "showcase-host": showcaseHost };
  if (!Object.hasOwn(patches, command) || argv.length !== 2) {
    writeSync(2, "usage: patch-browser-index.mjs (embedded-bootstrap | showcase-host) <index.html>\n");
    return 2;
  }
  try {
    const text = readText(file);
    // The check throws before anything is written, so the file is left as it was when the bootstrap check fails.
    writeText(file, patches[command](text));
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
