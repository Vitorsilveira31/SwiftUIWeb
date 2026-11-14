#!/usr/bin/env bun
/* Static architecture guardrails for the SwiftUIWeb layered renderer. */
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const failures = [];
const checks = [];

function read(relative) {
  const file = path.join(ROOT, relative);
  return fs.existsSync(file) ? fs.readFileSync(file, "utf8") : null;
}
function check(name, condition, detail) {
  checks.push({ name, passed: Boolean(condition), detail });
  if (!condition) failures.push(`${name}: ${detail}`);
}

const packageSwift = read("Package.swift") || "";
const browserAppSource = read("Sources/SwiftUIWebBrowser/BrowserApp.swift") || "";
const fiberSource = read("Sources/SwiftUIWebFiber/Fiber.swift") || "";
const layoutPhaseSource = read("Sources/SwiftUIWebBrowser/BrowserLayoutPhases.swift") || "";
const coreSources = ["Sources/SwiftUIWebCore", "Sources/SwiftUIWebFeatures", "Sources/SwiftUIWebFiber", "Sources/SwiftUIWebHTML"]
  .flatMap(relative => {
    const directory = path.join(ROOT, relative);
    if (!fs.existsSync(directory)) return [];
    return fs.readdirSync(directory).filter(file => file.endsWith(".swift")).map(file => path.join(relative, file));
  });
const coreInteropImports = coreSources.filter(file => /(?:^|\n)\s*import\s+(?:JavaScriptKit|JavaScriptEventLoop)\b|\bJSObject\b/.test(read(file) || ""));

check("core-target-boundary", /\.target\(name: "SwiftUIWebCore", dependencies: \["SwiftUIWebTransferable"\]/.test(packageSwift), "SwiftUIWebCore may depend only on the neutral transferable target");
check("features-target-boundary", /\.target\(name: "SwiftUIWebFeatures", dependencies: \["SwiftUIWebCore", "SwiftUIWebTransferable"\]/.test(packageSwift), "SwiftUIWebFeatures depends only on Core and the neutral transferable target");
check("fiber-target-boundary", /\.target\(name: "SwiftUIWebFiber", dependencies: \["SwiftUIWebCore"\]/.test(packageSwift), "SwiftUIWebFiber depends on Core, never browser/JavaScript targets");
check("backend-neutral-core-sources", coreInteropImports.length === 0, `Core/Fiber/HTML sources import browser concepts: ${coreInteropImports.join(", ") || "none"}`);
check("packed-mutation-buffer", Boolean(read("Sources/SwiftUIWebFiber/PackedMutationBuffer.swift")), "the compact packed mutation buffer must remain present");
check("embedded-browser-publisher", /_embeddedBrowserPublish/.test(browserAppSource) && /StaticHTMLFiberRenderer/.test(browserAppSource), "Embedded BrowserIO publishes retained Fiber snapshots through one browser publisher");
check("session-no-body-replacement", !/body\.innerHTML\s*=/.test(browserAppSource), "BrowserSession must not replace document.body after state updates");
check("event-token-table", /_embeddedBrowserEventTokens/.test(browserAppSource) && /embeddedBrowserDispatch/.test(browserAppSource), "BrowserIO dispatch uses stable semantic event tokens");
check("mount-registry", /(?:class|struct) WebMountRegistry/.test(read("Sources/SwiftUIWebBrowser/WebMount.swift") || ""), "WebMountRegistry ownership/lifecycle foundation must remain present");
check("generation-checks", /generation|Generation/.test(fiberSource) && /structuralID\.generation|StructuralNodeID/.test(browserAppSource), "structural and browser callbacks retain generation validation");
check("single-browser-scheduler", /_BrowserLayoutPhaseCoordinator/.test(layoutPhaseSource) && /scheduleDeferredInvalidation/.test(fiberSource), "Fiber coalescing and browser layout phases provide one scheduling authority");
check("release-reachability-tool", Boolean(read("Tools/release-reachability.js")) && Boolean(read("Tools/prune-release-assets.js")), "release asset reachability/pruning tools must remain available");

const result = { version: 1, status: failures.length ? "fail" : "pass", checks, failures };
console.log(JSON.stringify(result, null, 2));
if (failures.length) process.exitCode = 1;
