// Run with: bun test ./Tools/test-audit-showcase-catalog.mjs
import { expect, test } from "bun:test";
import { audit, publicViews, recipeCovers } from "./audit-showcase-catalog.mjs";

const symbols = [
  { signature: "public struct Slider<Label: View>: View" },
  { signature: "public nonisolated struct Menu<Label: View, Content: View>: View" },
  { signature: "public struct Text" },
  { signature: "public struct Fancy: ViewModifier" },
  { signature: "public struct Stack<Content: View>: View, Equatable where Content: Hashable" },
  { signature: "public final class Model: Observable" },
];
const recipe = (covers) => ({ "Recipes/XCatalogRecipe.swift": `covers: [${covers.map((name) => `"${name}"`).join(", ")}],` });

test("only declarations that say View are views", () => {
  expect([...publicViews(symbols)].sort()).toEqual(["Menu", "Slider", "Stack"]);
});

test("covers are read from the recipe sources", () => {
  expect([...recipeCovers(recipe(["Slider", "Menu"])).keys()]).toEqual(["Slider", "Menu"]);
});

test("a view with no entry, exemption or pending note fails", () => {
  const { failures } = audit({ symbols, recipeSources: recipe(["Slider"]), manifest: { also: ["Text"], exempt: { Menu: "x" } } });
  expect(failures.some((failure) => failure.startsWith("Stack is a public View with no catalog entry"))).toBe(true);
  expect(failures.some((failure) => failure.startsWith("Text is"))).toBe(true);
});

test("everything covered, exempt or pending passes", () => {
  const { failures, counts } = audit({
    symbols,
    recipeSources: recipe(["Slider", "Text"]),
    manifest: { also: ["Text"], exempt: { Menu: "a menu is a button" }, pending: { Stack: "next" } },
  });
  expect(failures).toEqual([]);
  expect(counts).toEqual({ views: 4, covered: 2, exempt: 1, pending: 1 });
});

test("a covered type must leave the pending list", () => {
  const { failures } = audit({ symbols, recipeSources: recipe(["Slider", "Menu", "Stack"]), manifest: { pending: { Stack: "next" } } });
  expect(failures).toEqual(["catalog-coverage.json: Stack is covered by Recipes/XCatalogRecipe.swift, remove it from pending"]);
});

test("a name that is not a public type is rejected", () => {
  const { failures } = audit({ symbols, recipeSources: recipe(["Slider", "Menu", "Stack", "Nope"]), manifest: {} });
  expect(failures).toEqual(["Recipes/XCatalogRecipe.swift: covers Nope, which is not a public type"]);
});

test("an exemption needs a reason and must name a public view", () => {
  const { failures } = audit({ symbols, recipeSources: recipe(["Slider", "Menu"]), manifest: { exempt: { Stack: "", Ghost: "why" } } });
  expect(failures).toContain("catalog-coverage.json: exempt lists Stack without a reason");
  expect(failures).toContain("catalog-coverage.json: exempt lists Ghost, which is not a public View");
});
