#!/usr/bin/env bun
// Static check that the Embedded browser networking integration matches the Networking facade.
import assert from "node:assert/strict";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { readText, rx } from "../audit-support.mjs";

const root = process.env.SWIFTUIWEB_AUDIT_ROOT
  ? resolve(process.env.SWIFTUIWEB_AUDIT_ROOT)
  : resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const networking = readText(join(root, "Sources/SwiftUIWebNetworking/Networking.swift"));
const browser = readText(join(root, "Sources/SwiftUIWebBrowser/BrowserApp.swift"));

const match = rx(String.raw`(?:public|package) enum NetworkConnectivity[^\{]*\{(.*?)\n\}`, "s").exec(networking);
assert(match, "NetworkConnectivity enum not found");
const cases = new Set([...match[1].matchAll(rx(String.raw`\bcase\s+([A-Za-z_][A-Za-z0-9_]*)`, "g"))].map((found) => found[1]));
for (const name of ["unknown", "online", "offline"]) assert(cases.has(name), `NetworkConnectivity missing ${name}`);
assert(!browser.includes("online ? .satisfied : .unsatisfied"));
assert(!browser.includes("box.response ="));
console.log("PASS: Embedded Browser networking integration matches the Networking facade");
assert(!browser.includes("return { operation.cancel() }"), "non-Sendable BrowserIOOperation captured by @Sendable cancellation token");
assert(browser.includes("let box = _EmbeddedBrowserIOOperationBox()"));
console.log("PASS: Embedded Browser cancellation tokens do not directly capture BrowserIOOperation");
