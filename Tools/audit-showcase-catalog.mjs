#!/usr/bin/env bun
// The component catalog of the project site (Examples/ShowcaseSite) against the public API: every public SwiftUIWeb
// `View` has a catalog entry that shows it, or is listed in Examples/ShowcaseSite/catalog-coverage.json with a reason.
//
//   - a recipe's `covers: [...]` names the public types it shows (Features/Components/Recipes/*CatalogRecipe.swift);
//   - `exempt` lists types that are not components to configure (type erasure, builder plumbing), `pending` the ones
//     that still need an entry; both carry the reason, and a type that has been covered must leave both lists;
//   - `also` lists views whose public declaration does not say `: View` (Text, Image, ...), so they are checked too.
//
// A public type that conforms to View in its declaration and is in none of these fails the audit, so a new component
// cannot ship without an entry or a reason.
// usage: audit-showcase-catalog.mjs   (run by `make tools-test`; tests: bun test ./Tools/test-audit-showcase-catalog.mjs)
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(fileURLToPath(new URL(".", import.meta.url)), "..");
const SITE = join(ROOT, "Examples", "ShowcaseSite");

/** Public types whose declaration says they are Views. */
export function publicViews(symbols) {
  const names = new Set();
  for (const symbol of symbols) {
    const match = /^public\s+(?:[@\w]+\s+)*?(?:struct|class)\s+(\w+)(?:<[^>]*>)?\s*:\s*([^{]*?)(?:\s+where\s.*)?$/.exec(symbol.signature);
    if (!match) continue;
    if (/(^|[\s,])View(\s|,|$)/.test(match[2])) names.add(match[1]);
  }
  return names;
}

export function publicTypes(symbols) {
  const names = new Set();
  for (const symbol of symbols) {
    const match = /^public\s+(?:[@\w]+\s+)*?(?:struct|class|enum)\s+(\w+)/.exec(symbol.signature);
    if (match) names.add(match[1]);
  }
  return names;
}

/** The type names each recipe file lists in `covers: [...]`. */
export function recipeCovers(recipeSources) {
  const covered = new Map();
  for (const [file, text] of Object.entries(recipeSources)) {
    const match = /covers:\s*\[([^\]]*)\]/.exec(text);
    if (!match) continue;
    for (const name of match[1].split(",").map((part) => part.trim().replace(/^"|"$/g, "")).filter(Boolean)) covered.set(name, file);
  }
  return covered;
}

export function audit({ symbols, recipeSources, manifest }) {
  const failures = [];
  const views = publicViews(symbols);
  const types = publicTypes(symbols);
  const covered = recipeCovers(recipeSources);
  const exempt = manifest.exempt ?? {};
  const pending = manifest.pending ?? {};
  const also = manifest.also ?? [];
  const checked = new Set([...views, ...also]);

  for (const name of also) if (!types.has(name)) failures.push(`catalog-coverage.json: "also" lists ${name}, which is not a public type`);
  for (const [name, file] of covered) if (!types.has(name)) failures.push(`${file}: covers ${name}, which is not a public type`);
  for (const [list, entries] of [["exempt", exempt], ["pending", pending]]) {
    for (const [name, reason] of Object.entries(entries)) {
      if (!checked.has(name)) failures.push(`catalog-coverage.json: ${list} lists ${name}, which is not a public View`);
      if (covered.has(name)) failures.push(`catalog-coverage.json: ${name} is covered by ${covered.get(name)}, remove it from ${list}`);
      if (!reason || String(reason).trim() === "") failures.push(`catalog-coverage.json: ${list} lists ${name} without a reason`);
    }
  }
  for (const name of [...checked].sort()) {
    if (!covered.has(name) && !(name in exempt) && !(name in pending)) {
      failures.push(`${name} is a public View with no catalog entry: add a recipe that covers it, or list it in catalog-coverage.json`);
    }
  }
  return { failures, counts: { views: checked.size, covered: [...checked].filter((name) => covered.has(name)).length, exempt: Object.keys(exempt).length, pending: Object.keys(pending).length } };
}

function main() {
  const api = JSON.parse(readFileSync(join(ROOT, "Documentation", "API", "public-api.json"), "utf8"));
  const manifest = JSON.parse(readFileSync(join(SITE, "catalog-coverage.json"), "utf8"));
  const directory = join(SITE, "Features", "Components", "Recipes");
  const recipeSources = {};
  if (existsSync(directory)) {
    for (const name of readdirSync(directory)) {
      if (name.endsWith("CatalogRecipe.swift")) recipeSources[`Features/Components/Recipes/${name}`] = readFileSync(join(directory, name), "utf8");
    }
  }
  const { failures, counts } = audit({ symbols: api.symbols, recipeSources, manifest });
  if (failures.length > 0) {
    console.error("Showcase catalog audit: FAIL");
    for (const failure of failures) console.error(`- ${failure}`);
    process.exit(1);
  }
  console.log(`Showcase catalog audit: PASS (${counts.covered} of ${counts.views} public views have an entry, ${counts.exempt} exempt, ${counts.pending} pending)`);
}

if (import.meta.main) main();
