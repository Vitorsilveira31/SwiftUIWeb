/**
 * Tests for Tools/compile-strings.mjs.
 *
 * Run: bun test ./Tools/test-compile-strings.mjs
 */
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { collect, main, render, swiftLiteral } from "./compile-strings.mjs";

function withTempDir(fn) {
  const dir = mkdtempSync(join(tmpdir(), "compile-strings-test-"));
  try {
    return fn(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function tablesOf(object) {
  return new Map(Object.entries(object).map(([language, entries]) => [language, new Map(Object.entries(entries))]));
}

function utf8Compare(a, b) {
  return Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
}

test("catalog text and plurals", () => {
  withTempDir((root) => {
    writeFileSync(
      join(root, "Localizable.xcstrings"),
      JSON.stringify({
        sourceLanguage: "pt-BR",
        version: "1.0",
        strings: {
          "Criar obra": {
            localizations: {
              "pt-BR": { stringUnit: { state: "translated", value: "Criar obra" } },
              en: { stringUnit: { state: "translated", value: "Create work" } },
            },
          },
          "%lld obras": {
            localizations: {
              "pt-BR": {
                variations: {
                  plural: {
                    one: { stringUnit: { value: "%lld obra" } },
                    other: { stringUnit: { value: "%lld obras" } },
                  },
                },
              },
            },
          },
          Skipped: { localizations: { "pt-BR": { substitutions: {}, stringUnit: { value: "x" } } } },
        },
      }),
    );
    const [development, tables] = collect([root]);
    assert.equal(development, "pt-BR");
    assert.deepEqual(tables.get("en"), new Map([["Criar obra", "Create work"]]));
    assert.deepEqual(
      tables.get("pt-BR").get("%lld obras"),
      new Map([
        ["one", "%lld obra"],
        ["other", "%lld obras"],
      ]),
    );
    assert.equal(tables.get("pt-BR").has("Skipped"), false);
    const swift = render(development, tables);
    assert.ok(swift.includes('LocalizationTable.developmentLanguage = "pt-BR"'));
    assert.ok(swift.includes('LocalizationTable.register(language: "en", sorted: entriesEn)'));
    assert.ok(swift.includes("import SwiftUIWeb\n"));
    assert.ok(render(development, tables, "SwiftUI").includes("import SwiftUI\n"));
    assert.ok(swift.includes("Criar obra\\u{3}Create work"));
    // Plural forms ride in the value slot: marker, then `category END text` per form.
    assert.ok(swift.includes("%lld obras\\u{3}\\u{1}one\\u{2}%lld obra\\u{1}other\\u{2}%lld obras"));
    assert.ok(swift.includes(": StaticString = \"\"\""));
    assert.ok(swift.startsWith("// Generated") && swift.includes("#if WEB"));
  });
});

test("development values equal to their key are not registered", () => {
  const swift = render(
    "pt-BR",
    tablesOf({
      "pt-BR": { "Criar obra": "Criar obra", "%@ · %@": "%1$@ · %2$@", Olá: "Oi" },
      en: { "Criar obra": "Create work" },
    }),
  );
  assert.ok(!swift.includes("Criar obra\\u{3}Criar obra"));
  assert.ok(!swift.includes("%@ · %@\\u{3}"));
  assert.ok(swift.includes("Olá\\u{3}Oi"));
  assert.ok(swift.includes("Criar obra\\u{3}Create work"));
});

test("entries are sorted by UTF-8 bytes for binary search", () => {
  const swift = render("pt-BR", tablesOf({ en: { b: "1", a: "2", é: "3", z: "4", Z: "5" } }));
  const order = swift
    .split("\n")
    .filter((line) => line.includes("\\u{3}"))
    .map((line) => line.trim().split("\\u{3}")[0]);
  assert.deepEqual(order, ["b", "a", "é", "z", "Z"].sort(utf8Compare));
});

test("records keep one per line and reject control separators", () => {
  const swift = render("pt-BR", tablesOf({ en: { a: "1", b: "2" } }));
  assert.ok(swift.includes("a\\u{3}1\\u{4}\\\n"));
  assert.ok(swift.includes("    b\\u{3}2\n"));
  for (const separator of ["\x01", "\x02", "\x03", "\x04"]) {
    assert.throws(() => render("pt-BR", tablesOf({ en: { a: "x" + separator + "y" } })));
    assert.throws(() => render("pt-BR", tablesOf({ en: { ["a" + separator]: "y" } })));
    assert.throws(() => render("pt-BR", tablesOf({ en: { a: { one: "x" + separator } } })));
  }
});

test("strings files: comments and escapes", () => {
  withTempDir((root) => {
    const lproj = join(root, "pt-BR.lproj");
    mkdirSync(lproj);
    writeFileSync(
      join(lproj, "Localizable.strings"),
      '/* c */\n// line\n"Dizer \\"oi\\"" = "Linha 1\\nLinha 2 \\\\ \\U00E9";\n"k" = "v";\n',
      "utf8",
    );
    const [, tables] = collect([root]);
    assert.deepEqual(
      tables.get("pt-BR"),
      new Map([
        ['Dizer "oi"', "Linha 1\nLinha 2 \\ é"],
        ["k", "v"],
      ]),
    );
    assert.ok(render("pt-BR", tables).includes('Dizer \\"oi\\"\\u{3}Linha 1\\nLinha 2 \\\\ é'));
  });
});

test("build directories are skipped", () => {
  withTempDir((root) => {
    const hidden = join(root, ".build");
    mkdirSync(hidden);
    writeFileSync(
      join(hidden, "Localizable.xcstrings"),
      JSON.stringify({ sourceLanguage: "en", strings: { a: { localizations: { en: { stringUnit: { value: "b" } } } } } }),
    );
    assert.deepEqual(collect([root])[1], new Map());
  });
});

test("sourceLanguage must be a language tag string", () => {
  withTempDir((root) => {
    const catalog = (sourceLanguage) =>
      JSON.stringify({ sourceLanguage, strings: { a: { localizations: { en: { stringUnit: { value: "b" } } } } } });
    for (const language of ["en", "pt-BR", "zh-Hans", "sr-Latn-BA", "es_419"]) {
      writeFileSync(join(root, "Localizable.xcstrings"), catalog(language));
      assert.equal(collect([root])[0], language);
    }
    const hostile = [
      ['en"\n  Foo.bar()\n//'],
      ["en", "x"],
      { en: "x" },
      "",
      "pt BR",
      5,
      true,
      null,
    ];
    for (const language of hostile) {
      writeFileSync(join(root, "Localizable.xcstrings"), catalog(language));
      assert.throws(() => collect([root]), /sourceLanguage/, JSON.stringify(language));
    }
  });
});

test("swiftLiteral and render refuse non-string text", () => {
  for (const value of [['a"b'], { 'a"b': "c" }, 1, null, undefined, true]) {
    assert.throws(() => swiftLiteral(value), TypeError, JSON.stringify(value));
  }
  assert.throws(() => render(['en"\n  Foo.bar()\n//'], new Map()), TypeError);
  assert.equal(swiftLiteral('a"b\n'), '"a\\"b\\n"');
});

test("a hostile sourceLanguage writes no Swift file", () => {
  withTempDir((root) => {
    writeFileSync(
      join(root, "Localizable.xcstrings"),
      JSON.stringify({
        sourceLanguage: ['en"\n  Foo.bar()\n//'],
        strings: { a: { localizations: { en: { stringUnit: { value: "b" } } } } },
      }),
    );
    const output = join(root, "out", "LocalizedStrings.generated.swift");
    assert.throws(() => main([root, "-o", output]), /sourceLanguage/);
    assert.equal(existsSync(output), false);
  });
});
