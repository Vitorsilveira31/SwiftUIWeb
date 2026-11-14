#!/usr/bin/env bun
// Prints a markdown table of Embedded boundary hits (`hasFeature(Embedded)`) and unavailable/unsupported/no-op
// mentions per framework area. Counts are lexical, over the files listed per area; missing files are skipped.
import { existsSync, writeSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { BOUNDARY, readTextIgnoringErrors, realpath } from "./text-semantics.mjs";

const ROOT = join(dirname(realpath(fileURLToPath(import.meta.url))), "..");

const AREAS = [
  ["Slider / continuous interaction", ["Sources/SwiftUIWebBrowser/BrowserApp.swift", "Sources/SwiftUIWebCore/Views.swift"]],
  ["DisclosureGroup", ["Sources/SwiftUIWebCore/Views.swift", "Sources/SwiftUIWebBrowser/BrowserApp.swift"]],
  ["Navigation / Tabs", ["Sources/SwiftUIWebCore/Navigation.swift", "Sources/SwiftUIWebBrowser/BrowserHistoryAdapter.swift"]],
  ["Animations", ["Sources/SwiftUIWebFeatures/AdvancedAnimations.swift", "Sources/SwiftUIWebBrowser/BrowserAdvancedAnimations.swift"]],
  ["Gestures", ["Sources/SwiftUIWebCore/Gestures.swift", "Sources/SwiftUIWebBrowser/BrowserApp.swift"]],
  ["Lazy lists", ["Sources/SwiftUIWebFiber/LazyLayout.swift"]],
  ["Internationalization", ["Sources/SwiftUIWebInternationalization/DateFormatting.swift"]],
  ["History / URL navigation", ["Sources/SwiftUIWebBrowser/BrowserHistoryAdapter.swift"]],
  ["WebMount", ["Sources/SwiftUIWebBrowser/WebMount.swift"]],
  ["Networking / fetch", ["Sources/SwiftUIWebNetworking/Networking.swift", "Sources/SwiftUIWebBrowser/BrowserApp.swift"]],
  ["Storage", ["Sources/SwiftUIWebBrowser/WebStorage.swift", "Sources/SwiftUIWebFeatures/Storage.swift"]],
  ["Codable / Transferable", ["Sources/SwiftUIWebTransferable/Transferable.swift"]],
  ["AVFoundation / media", ["Sources/SwiftUIWebAVFoundation/MediaBackend.swift", "Tools/avfoundation.js"]],
  ["Browser feature loader", ["Sources/SwiftUIWebBrowser/BrowserFeatureLoader.swift", "Tools/feature-loader.js"]],
  ["Browser scheduler / timeline", ["Sources/SwiftUIWebBrowser/BrowserTimeline.swift"]],
  ["SF Symbols / Lucide", ["Sources/SwiftUIWebBrowser/LucideIcons.swift"]],
  ["BrowserIO runtime dependency", ["Package.swift", "Sources/SwiftUIWebBrowser/BrowserApp.swift"]],
];

const BOUNDARY_HITS = /hasFeature\(Embedded\)|!hasFeature\(Embedded\)/g;
const BAD_HITS = new RegExp(`${BOUNDARY}unavailable${BOUNDARY}|${BOUNDARY}unsupported${BOUNDARY}|${BOUNDARY}no-op${BOUNDARY}`, "giu");

export function areaCounts(root, paths) {
  let boundary = 0;
  let bad = 0;
  for (const rel of paths) {
    const file = join(root, rel);
    if (!existsSync(file)) continue;
    const text = readTextIgnoringErrors(file);
    boundary += [...text.matchAll(BOUNDARY_HITS)].length;
    bad += [...text.matchAll(BAD_HITS)].length;
  }
  return { boundary, bad };
}

export function markdownTable(root = ROOT) {
  const lines = ["| Area | Embedded boundary hits | unavailable/unsupported hits |", "|---|---:|---:|"];
  for (const [area, paths] of AREAS) {
    const { boundary, bad } = areaCounts(root, paths);
    lines.push(`| ${area} | ${boundary} | ${bad} |`);
  }
  return lines;
}

if (process.argv[1] && realpath(process.argv[1]) === realpath(fileURLToPath(import.meta.url))) {
  for (const line of markdownTable()) writeSync(1, line + "\n");
}
