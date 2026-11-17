#!/usr/bin/env bun
// Source wiring regressions. These do not replace Swift compilation.
import assert from "node:assert/strict";
import { join } from "node:path";
import { readText, ROOT, runCases } from "./audit-support.mjs";

const read = (path) => readText(join(ROOT, path));
const includes = (text, needle) => assert(text.includes(needle), `expected ${JSON.stringify(needle)} in the source`);
const excludes = (text, needle) => assert(!text.includes(needle), `unexpected ${JSON.stringify(needle)} in the source`);
const indexOf = (text, needle) => {
  const index = text.indexOf(needle);
  assert(index >= 0, `substring not found: ${needle}`);
  return index;
};

await runCases({
  "plain stylesheet and no styling dependency"() {
    const manifest = JSON.parse(read("package.json"));
    const names = [...Object.keys(manifest.dependencies ?? {}), ...Object.keys(manifest.devDependencies)].map((name) => name.toLowerCase());
    assert(!names.some((name) => name.includes("tailwind") || name.includes("starting")));
    const css = read("Tools/styles.css");
    for (const marker of ['@import "tailwindcss"', "@apply", "@theme", "@source", "@custom-variant", "--tw-"]) excludes(css, marker);
  },
  "all viewport scroll and history exports are defined"() {
    const lower = read("Tools/SwiftUIWebLowering/Sources/LoweringCore/BrowserExportsTemplate.swift") + read("Tools/SwiftUIWebLowering/Sources/LoweringCore/LinkerExports.swift");
    for (const name of [
      "viewport", "scroll_ack", "scroll_prepare", "history_ack", "history_restore", "history_location",
      "secure_value", "secure_value_reset", "secure_value_byte",
    ]) includes(lower, `embedded_browser_${name}`);
  },
  "modifier boundary does not duplicate events"() {
    const source = read("Sources/SwiftUIWebCore/SemanticLayout.swift");
    for (const reset of ["node.events = .init()", "node.taskRegistrations = []", "node.lazyCollection = nil", "node._canvasCommands = []"]) includes(source, reset);
    includes(read("Sources/SwiftUIWebFeatures/MissingFeatures.swift"), '_semanticWrap(node, kind: "inset")');
  },
  "builtin erased layout uses semantic contract"() {
    // The erased layout type stays in Core; the layout container that consumes the contract is in SwiftUIWebFeatures.
    includes(read("Sources/SwiftUIWebFeatures/Layout.swift"), "if let semantic = layout._swiftUIWebSemanticLayout");
    includes(read("Sources/SwiftUIWebCore/Layout.swift"), "_swiftUIWebSemanticLayout = layout._swiftUIWebSemanticLayout");
  },
  "no showcase page names in generic runtime"() {
    const source = read("Tools/embedded-dom.js");
    for (const token of ["showcase-route", "showcaseSection", "/collections", "/advanced", "/themes"]) excludes(source, token);
  },
  "document theme cannot change demo scroll geometry"() {
    const css = read("Tools/showcase.css");
    for (const token of ["!important", ".scroll-view", ".chart-svg", "height:100vh"]) excludes(css, token);
    assert(/max-width:\s*999px/u.test(css));
  },
  "laziness has stable container identity"() {
    const source = read("Sources/SwiftUIWebBrowser/BrowserApp.swift");
    includes(source, "data-keep-lazy-index");
    includes(source, "data-embedded-scroll-sequence");
  },
  "runtime instantiates the layout host"() {
    const source = read("Tools/embedded-dom.js");
    includes(source, "new SemanticLayoutHost(root,{");
    includes(source, "layout.update()");
    includes(source, "new NativeDragDropCoordinator(root,dispatchNamed)");
  },
  "mount marker is the documented attribute"() {
    const source = read("Tools/embedded-dom.js");
    // dataset.embeddedMounted is the attribute data-embedded-mounted that the browser suites wait for.
    includes(source, "mounted.embeddedMounted = 'true'");
    excludes(source, "swiftuiwebEmbeddedMounted");
  },
  "dialog has stable host and not button descendant"() {
    const source = read("Sources/SwiftUIWebCore/Modifiers.swift");
    const hostCalls = source.split("preparePresentationHost(node)").length - 1 + (source.split("preparePresentationHost(node, context: context)").length - 1);
    assert(hostCalls >= 9, `expected at least 9 host calls, found ${hostCalls}`);
    includes(source, 'node.attributes["data-presentation-host"]');
  },
  "new drawer is not native semantic requirement"() {
    includes(read("Tests/Apps/ShowcaseApp/main.swift"), "private struct DocsChrome");
    excludes(read("Sources/SwiftUIWebCore/Views.swift"), "DocsChrome");
  },
}, "test-semantic-integration");
