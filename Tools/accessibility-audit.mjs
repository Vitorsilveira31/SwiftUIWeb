#!/usr/bin/env bun
// Static contract audit for the unified accessibility backend.
import assert from "node:assert/strict";
import { join } from "node:path";
import { readText, ROOT } from "./audit-support.mjs";

// The capability matrix this audit also read was removed with the other obsolete documents in ff0c73f; the backend's
// source contract remains.
const source = readText(join(ROOT, "Sources", "SwiftUIWebCore", "Accessibility.swift"));
assert(source.includes("enum _AccessibilityBackend"), "enum _AccessibilityBackend");
assert(source.includes("data-a11y-backend"), "data-a11y-backend");
assert(source.includes("hasNativeRole"), "hasNativeRole");
console.log("PASS accessibility backend source contract");
