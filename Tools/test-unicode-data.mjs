// The Unicode character data the browser build answers for the Swift standard library (Tools/BrowserIO/unicode-data.mjs,
// Sources/CSwiftUIWebBrowserIO/UnicodeData.c), against values from the Unicode Character Database. The derivation was
// checked against every scalar of UCD 18.0 with Node's ICU; these cases cover each rule and its exceptions.
import assert from "node:assert/strict";
import { test } from "bun:test";
import {
  caseMapping, composition, createUnicodeImports, decomposition, graphemeBreakProperty, isExtendedPictographic,
  isInCBConsonant, normalizationData,
} from "./BrowserIO/unicode-data.mjs";

const norm = (ccc, quickCheck, decomposes) => (ccc << 3) | (quickCheck << 1) | (decomposes ? 1 : 0);
const YES = 0, NO = 1, MAYBE = 2;

test("normalization data: combining class, NFC_QC and NFD_QC", () => {
  assert.equal(normalizationData(0x00E9), norm(0, YES, true));
  assert.equal(normalizationData(0x4E00), norm(0, YES, false));
  assert.equal(normalizationData(0xAC00), norm(0, YES, true));
  assert.equal(normalizationData(0x0301), norm(230, MAYBE, false));
  assert.equal(normalizationData(0x0327), norm(202, MAYBE, false));
  assert.equal(normalizationData(0x0345), norm(240, MAYBE, false));
  assert.equal(normalizationData(0x05B0), norm(10, MAYBE, false));
  assert.equal(normalizationData(0x0E48), norm(107, MAYBE, false));
  assert.equal(normalizationData(0x093C), norm(7, MAYBE, false));
  assert.equal(normalizationData(0x0340), norm(230, NO, true));
  assert.equal(normalizationData(0x0344), norm(230, NO, true));
  assert.equal(normalizationData(0x0F73), norm(0, NO, true));
  assert.equal(normalizationData(0x212B), norm(0, NO, true));
  // Composing scalars with class 0: a Hangul vowel and a Bengali vowel sign.
  assert.equal(normalizationData(0x1161), norm(0, MAYBE, false));
  assert.equal(normalizationData(0x09BE), norm(0, MAYBE, false));
});

test("decomposition and composition", () => {
  assert.equal(decomposition(0x1E69), "s\u{323}\u{307}");
  assert.equal(decomposition(0x212B), "A\u{30A}");
  assert.equal(decomposition(0x1F82), "\u{3B1}\u{313}\u{300}\u{345}");
  assert.equal(decomposition(0x00C0 + 0x4000), null);
  assert.equal(composition(0x41, 0x30A), 0xC5);
  assert.equal(composition(0x1EA1, 0x302), 0x1EAD);
  assert.equal(composition(0x1100, 0x1161), 0xAC00);
  assert.equal(composition(0x09C7, 0x09BE), 0x09CB);
  assert.equal(composition(0x61, 0x62), 0xFFFFFFFF);
  // An excluded composite is never formed.
  assert.equal(composition(0x915, 0x93C), 0xFFFFFFFF);
});

test("grapheme break properties", () => {
  const CONTROL = 0, EXTEND = 1, PREPEND = 2, SPACING_MARK = 3, ANY = 4;
  assert.equal(graphemeBreakProperty(0x7F), CONTROL);
  assert.equal(graphemeBreakProperty(0x2028), CONTROL);
  assert.equal(graphemeBreakProperty(0xFEFF), CONTROL);
  assert.equal(graphemeBreakProperty(0x0301), EXTEND);
  assert.equal(graphemeBreakProperty(0x200C), EXTEND);
  assert.equal(graphemeBreakProperty(0x1F3FB), EXTEND);
  assert.equal(graphemeBreakProperty(0xE0020), EXTEND);
  assert.equal(graphemeBreakProperty(0x0600), PREPEND);
  assert.equal(graphemeBreakProperty(0x093E), SPACING_MARK);
  assert.equal(graphemeBreakProperty(0x0E33), SPACING_MARK);
  assert.equal(graphemeBreakProperty(0x4E00), ANY);
  assert.equal(graphemeBreakProperty(0x00E9), ANY);
  assert.equal(isInCBConsonant(0x0915), true);
  assert.equal(isInCBConsonant(0x094D), false);
  assert.equal(isInCBConsonant(0x0061), false);
  assert.equal(isExtendedPictographic(0x1F600), true);
  assert.equal(isExtendedPictographic(0x00A9), true);
  assert.equal(isExtendedPictographic(0x0041), false);
});

test("case mappings, including the special and titlecase ones", () => {
  assert.equal(caseMapping(0xDF, 0), "SS");
  assert.equal(caseMapping(0x130, 1), "i\u{307}");
  assert.equal(caseMapping(0x3A3, 1), "\u{3C3}");
  assert.equal(caseMapping(0x1F80, 0), "\u{1F08}\u{399}");
  assert.equal(caseMapping(0x10D0, 0), "\u{1C90}");
  assert.equal(caseMapping(0x61, 2), "A");
  assert.equal(caseMapping(0xDF, 2), "Ss");
  assert.equal(caseMapping(0xFB01, 2), "Fi");
  assert.equal(caseMapping(0x587, 2), "\u{535}\u{582}");
  assert.equal(caseMapping(0x149, 2), "\u{2BC}N");
  assert.equal(caseMapping(0x1C6, 2), "\u{1C5}");
  assert.equal(caseMapping(0x1C5, 2), "\u{1C5}");
  assert.equal(caseMapping(0x10D0, 2), "\u{10D0}");
  assert.equal(caseMapping(0x1F80, 2), "\u{1F88}");
  assert.equal(caseMapping(0x1FB3, 2), "\u{1FBC}");
  assert.equal(caseMapping(0x1FB2, 2), "\u{1FBA}\u{345}");
  assert.equal(caseMapping(0x1FB7, 2), "\u{391}\u{342}\u{345}");
});

test("the browser_io imports write UTF-8 into the instance's memory", () => {
  const memory = new Uint8Array(64);
  const imports = createUnicodeImports(() => memory);
  assert.equal(imports.unicode_case_delta(0x41, 1), 32);
  assert.equal(imports.unicode_case_delta(0xDF, 0), 0);
  assert.equal(imports.unicode_case_special(0xDF, 0, 8, 16), 2);
  assert.equal(new TextDecoder().decode(memory.subarray(8, 10)), "SS");
  assert.equal(imports.unicode_case_special(0x41, 0, 8, 16), 0);
  assert.equal(imports.unicode_decomposition(0x1E69, 16, 16), 5);
  assert.equal(new TextDecoder().decode(memory.subarray(16, 21)), "s\u{323}\u{307}");
  assert.equal(imports.unicode_decomposition(0x41, 16, 16), 0);
  // A buffer too small for the bytes yields no answer rather than a cut sequence.
  assert.equal(imports.unicode_decomposition(0x1E69, 16, 3), 0);
  assert.equal(imports.unicode_composition(0x41, 0x30A), 0xC5);
  assert.equal(imports.unicode_norm_data(0x301), norm(230, MAYBE, false));
  assert.equal(imports.unicode_grapheme_break(0x301), 1);
  assert.equal(imports.unicode_incb_consonant(0x915), 1);
  assert.equal(imports.unicode_extended_pictographic(0x1F600), 1);
});
