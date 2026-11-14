#!/usr/bin/env bun
// Serves a directory over HTTP on 127.0.0.1 until interrupted. Usage: bun Tools/serve-static.mjs <directory> [port]
// (the port defaults to 8080; 0 picks a free one).
import { serveStatic } from "./browser-test-support.mjs";

const [directory, portText = "8080"] = process.argv.slice(2);
if (!directory || !/^\d+$/.test(portText)) {
  console.error("usage: bun Tools/serve-static.mjs <directory> [port]");
  process.exit(2);
}
const server = serveStatic(directory, { port: Number(portText) });
console.log(`Serving ${directory} at ${server.base}/ (Ctrl-C to stop)`);
