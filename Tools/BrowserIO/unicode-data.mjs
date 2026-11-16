// The Unicode character data of the Swift standard library, answered from the browser's own (ICU) data.
//
// Embedded Swift reads a scalar's normalization data, grapheme break property, Extended_Pictographic flag and case
// mapping through C functions (`_swift_stdlib_getNormData` and its neighbours). The browser build defines them in
// Sources/CSwiftUIWebBrowserIO/UnicodeData.c as calls to the functions below instead of linking the standard library's
// tables. Each answer is derived from an API that implements the Unicode algorithm itself:
//
// - normalization: `String.prototype.normalize`. A canonical combining class is not exposed, so it is read from how
//   NFD reorders the scalar against marks of known classes (canonical ordering sorts adjacent marks by class);
// - grapheme breaking: `Intl.Segmenter`, by how the scalar joins its neighbours in a few probe strings;
// - Extended_Pictographic: the regular-expression property escape;
// - case mapping: `toUpperCase` / `toLowerCase`, which apply the full (SpecialCasing) mappings without context.
//
// Only scalars outside ASCII reach this file, and each answer is cached.

const nfd = (text) => text.normalize('NFD');
const nfc = (text) => text.normalize('NFC');
const scalars = (text) => Array.from(text, (character) => character.codePointAt(0));

// One mark of every canonical combining class above 0, by class.
const COMBINING_CLASSES = [
  [1, 0x0334], [6, 0x16FF0], [7, 0x093C], [8, 0x3099], [9, 0x094D], [10, 0x05B0], [11, 0x05B1], [12, 0x05B2],
  [13, 0x05B3], [14, 0x05B4], [15, 0x05B5], [16, 0x05B6], [17, 0x05B7], [18, 0x05B8], [19, 0x05B9], [20, 0x05BB],
  [21, 0x05BC], [22, 0x05BD], [23, 0x05BF], [24, 0x05C1], [25, 0x05C2], [26, 0xFB1E], [27, 0x064B], [28, 0x064C],
  [29, 0x064D], [30, 0x064E], [31, 0x064F], [32, 0x0650], [33, 0x0651], [34, 0x0652], [35, 0x0670], [36, 0x0711],
  [84, 0x0C55], [91, 0x0C56], [103, 0x0E38], [107, 0x0E48], [118, 0x0EB8], [122, 0x0EC8], [129, 0x0F71],
  [130, 0x0F72], [132, 0x0F74], [202, 0x0327], [214, 0x1DCE], [216, 0x031B], [218, 0x302A], [220, 0x0316],
  [222, 0x059A], [224, 0x302E], [226, 0x1D16D], [228, 0x05AE], [230, 0x0300], [232, 0x0315], [233, 0x035C],
  [234, 0x035D], [240, 0x0345],
].map(([value, mark]) => [value, String.fromCodePoint(mark)]);

/** Whether NFD moves `mark` after `character`: both are marks and `mark`'s class is the higher one. */
const reordered = (mark, character) => mark !== character && nfd(mark + character) === character + mark;

/** The canonical combining class of a scalar that does not decompose. */
function undecomposedClass(character) {
  const [, highest] = COMBINING_CLASSES[COMBINING_CLASSES.length - 1];
  const [, lowest] = COMBINING_CLASSES[0];
  if (!reordered(highest, character) && !reordered(character, lowest)) return 0;
  // The first class that NFD puts after the scalar is the one above its own.
  let low = 0, high = COMBINING_CLASSES.length;
  while (low < high) {
    const middle = (low + high) >> 1;
    if (reordered(COMBINING_CLASSES[middle][1], character)) high = middle; else low = middle + 1;
  }
  return COMBINING_CLASSES[Math.max(low - 1, 0)][0];
}

/** The class of a scalar that decomposes is its decomposition's first scalar's, except three Tibetan vowel signs. */
function combiningClass(scalar, character, decomposed) {
  if (decomposed === character) return undecomposedClass(character);
  if (scalar === 0x0F73 || scalar === 0x0F75 || scalar === 0x0F81) return 0;
  return undecomposedClass(String.fromCodePoint(decomposed.codePointAt(0)));
}

// A scalar that may combine with the one before it under NFC (NFC_QC=Maybe). The exact set is the second scalar of
// some primary composite, which no browser API lists; this is a superset of it: every mark, the Hangul vowels and
// trailing consonants, and the two Kirat Rai vowel signs that compose. Answering "maybe" for a scalar that never
// composes only sends a string through the normalizer instead of its NFC fast path, with the same result.
const MAYBE_COMPOSES = /[\p{M}\u1161-\u1175\u11A8-\u11C2\u{16D67}\u{16D68}]/u;

export function normalizationData(scalar) {
  const character = String.fromCodePoint(scalar);
  const decomposed = nfd(character);
  const ccc = combiningClass(scalar, character, decomposed);
  let quickCheck = 0;
  if (nfc(character) !== character) quickCheck = 1;
  else if (ccc !== 0 || MAYBE_COMPOSES.test(character)) quickCheck = 2;
  return (ccc << 3) | (quickCheck << 1) | (decomposed === character ? 0 : 1);
}

/** The full canonical decomposition, or null when the scalar does not decompose. */
export function decomposition(scalar) {
  const character = String.fromCodePoint(scalar);
  const decomposed = nfd(character);
  return decomposed === character ? null : decomposed;
}

/** The primary composite of `first` and `second`, or 0xFFFFFFFF. */
export function composition(first, second) {
  const composed = nfc(String.fromCodePoint(first, second));
  const value = composed.codePointAt(0);
  return composed.length === (value > 0xFFFF ? 2 : 1) ? value : 0xFFFFFFFF;
}

let segmenter = null;
const clusters = (text) => {
  segmenter ??= new Intl.Segmenter(undefined, { granularity: 'grapheme' });
  let count = 0;
  for (const _ of segmenter.segment(text)) count++;
  return count;
};
const EMOJI = '\u{1F600}';

// Without Intl.Segmenter (Firefox before 125), the properties come from their definitions in UAX #29, through the
// property escapes: Extend is Grapheme_Extend or Emoji_Modifier, SpacingMark is (nearly) a spacing combining mark,
// Prepend is (nearly) a prepended concatenation mark, and Control the other separators, controls and formats.
const EXTEND = /^[\p{Grapheme_Extend}\p{Emoji_Modifier}]$/u;
const PREPEND = /^[\u{600}-\u{605}\u{6DD}\u{70F}\u{890}\u{891}\u{8E2}\u{110BD}\u{110CD}]$/u;
const CONTROL = /^[\p{Cc}\p{Zl}\p{Zp}\p{Cf}]$/u;
const SPACING_MARK = /^[\p{Mc}\u{E33}\u{EB3}]$/u;
function definedGraphemeBreakProperty(character) {
  if (EXTEND.test(character)) return 1;
  if (PREPEND.test(character)) return 2;
  if (CONTROL.test(character)) return 0;
  return SPACING_MARK.test(character) ? 3 : 4;
}

/** 0 Control, 1 Extend, 2 Prepend, 3 SpacingMark, 4 any other (the library resolves Hangul, RI and ZWJ itself). */
export function graphemeBreakProperty(scalar) {
  const character = String.fromCodePoint(scalar);
  if (typeof Intl.Segmenter !== 'function') return definedGraphemeBreakProperty(character);
  // Control breaks on both sides, even before a combining mark (GB4, GB5).
  if (clusters('a' + character + '\u0308') === 3) return 0;
  // Prepend joins what follows (GB9b).
  if (clusters(character + 'a') === 1) return 2;
  // Extend and SpacingMark join what precedes (GB9, GB9a); only Extend continues an emoji ZWJ sequence (GB11).
  if (clusters('a' + character) === 1) return clusters(EMOJI + character + '\u200D' + EMOJI) === 1 ? 1 : 3;
  return 4;
}

/** InCB=Consonant: a scalar that starts a cluster, except after a consonant and a linker (GB9c). */
export function isInCBConsonant(scalar) {
  if (typeof Intl.Segmenter !== 'function') return false;
  const character = String.fromCodePoint(scalar);
  return clusters('\u0915\u094D' + character) === 1 && clusters('a' + character) === 2;
}

const PICTOGRAPHIC = /^\p{Extended_Pictographic}$/u;
export const isExtendedPictographic = (scalar) => PICTOGRAPHIC.test(String.fromCodePoint(scalar));

// The titlecase mappings that differ from the uppercase ones in a single scalar: the Latin digraphs, and Georgian
// Mkhedruli, whose uppercase is Mtavruli while its titlecase is itself.
const TITLE_DIGRAPHS = new Map([0x01C4, 0x01C7, 0x01CA, 0x01F1].flatMap((capital) => [0, 1, 2].map((offset) => [capital + offset, capital + 1])));
const isMkhedruli = (scalar) => (scalar >= 0x10D0 && scalar <= 0x10FA) || (scalar >= 0x10FD && scalar <= 0x10FF);

/** Unicode's full titlecase mapping, derived from the uppercase one (the browser has no titlecase API). */
function titlecase(scalar, character) {
  if (isMkhedruli(scalar)) return character;
  if (TITLE_DIGRAPHS.has(scalar)) return String.fromCodePoint(TITLE_DIGRAPHS.get(scalar));
  const upper = character.toUpperCase();
  const parts = scalars(upper);
  if (parts.length === 1) return upper;
  // A Greek letter with a ypogegrammeni keeps it as a prosgegrammeni in titlecase (ᾳ → ᾼ, not ΑΙ).
  if (nfd(character).includes('\u0345') && parts[parts.length - 1] === 0x0399) {
    const kept = String.fromCodePoint(...parts.slice(0, -1), 0x0345);
    const composed = nfc(kept);
    return scalars(composed).length === 1 ? composed : kept;
  }
  // Otherwise the first scalar stays uppercase and the rest lowers (ß → Ss, ﬁ → Fi), unless the first is uncased
  // (ŉ → ʼN).
  const first = String.fromCodePoint(parts[0]);
  if (first.toLowerCase() === first) return upper;
  return first + String.fromCodePoint(...parts.slice(1)).toLowerCase();
}

/** The `mapping` (0 upper, 1 lower, 2 title) of a scalar, as a string. */
export function caseMapping(scalar, mapping) {
  const character = String.fromCodePoint(scalar);
  if (mapping === 0) return character.toUpperCase();
  if (mapping === 1) return character.toLowerCase();
  return titlecase(scalar, character);
}

function cached(compute) {
  const values = new Map();
  return (key) => {
    let value = values.get(key);
    if (value === undefined) { value = compute(key); values.set(key, value); }
    return value;
  };
}

/** The `browser_io` imports UnicodeData.c calls. `bytes()` is the instance's memory as a Uint8Array. */
export function createUnicodeImports(bytes) {
  const encoder = new TextEncoder();
  const write = (text, pointer, capacity) => {
    const target = bytes().subarray(pointer >>> 0, (pointer >>> 0) + (capacity >>> 0));
    const { read, written } = encoder.encodeInto(text, target);
    return read === text.length ? written : 0;
  };
  const normData = cached(normalizationData);
  const decomposed = cached(decomposition);
  const grapheme = cached(graphemeBreakProperty);
  const consonant = cached(isInCBConsonant);
  const pictographic = cached(isExtendedPictographic);
  const mapped = cached((key) => caseMapping(Math.floor(key / 4), key % 4));
  return {
    unicode_norm_data: (scalar) => normData(scalar >>> 0),
    unicode_decomposition(scalar, pointer, capacity) {
      const text = decomposed(scalar >>> 0);
      return text === null ? 0 : write(text, pointer, capacity);
    },
    unicode_composition: (first, second) => composition(first >>> 0, second >>> 0),
    unicode_grapheme_break: (scalar) => grapheme(scalar >>> 0),
    unicode_incb_consonant: (scalar) => (consonant(scalar >>> 0) ? 1 : 0),
    unicode_extended_pictographic: (scalar) => (pictographic(scalar >>> 0) ? 1 : 0),
    unicode_case_delta(scalar, mapping) {
      scalar >>>= 0;
      const parts = scalars(mapped(scalar * 4 + (mapping & 3)));
      return parts.length === 1 ? parts[0] - scalar : 0;
    },
    unicode_case_special(scalar, mapping, pointer, capacity) {
      scalar >>>= 0;
      const text = mapped(scalar * 4 + (mapping & 3));
      return scalars(text).length > 1 ? write(text, pointer, capacity) : 0;
    },
  };
}
