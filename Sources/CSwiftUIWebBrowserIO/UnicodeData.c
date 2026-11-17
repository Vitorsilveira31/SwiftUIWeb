/* The Unicode character data the Swift standard library reads, answered by the browser.
 *
 * Embedded Swift keeps the data behind String's Unicode semantics in a separate archive, libswiftUnicodeDataTables,
 * whose members are C functions the standard library calls for a scalar outside ASCII: its normalization data
 * (comparing and hashing strings), its grapheme break property (iterating characters), whether it is an extended
 * pictographic, and its case mapping (`lowercased()`, `uppercased()`). Linking the archive puts about 70 KB of tables in
 * every app, while the browser already ships the same data: `String.prototype.normalize`, `Intl.Segmenter`,
 * `toLowerCase` and the Unicode property escapes of regular expressions (Tools/BrowserIO/unicode-data.mjs).
 *
 * The definitions are weak. The archive stays on the link line for the properties the browser does not expose
 * (general category, numeric values, names, ages, scripts): an app that reads one of those pulls the archive member
 * that holds it, and when that member also defines one of these functions, its definition and tables win. */
#include <stdint.h>
#if defined(__wasm__) && defined(SWIFTUIWEB_EMBEDDED_RUNTIME)
#define IMPORT(name) __attribute__((import_module("browser_io"), import_name(name)))
#define WEAK __attribute__((weak, visibility("hidden")))
IMPORT("unicode_norm_data") extern uint32_t host_unicode_norm_data(uint32_t scalar);
IMPORT("unicode_decomposition") extern uint32_t host_unicode_decomposition(uint32_t scalar, uint8_t *buffer, uint32_t capacity);
IMPORT("unicode_composition") extern uint32_t host_unicode_composition(uint32_t first, uint32_t second);
IMPORT("unicode_grapheme_break") extern uint32_t host_unicode_grapheme_break(uint32_t scalar);
IMPORT("unicode_incb_consonant") extern uint32_t host_unicode_incb_consonant(uint32_t scalar);
IMPORT("unicode_extended_pictographic") extern uint32_t host_unicode_extended_pictographic(uint32_t scalar);
IMPORT("unicode_case_delta") extern int32_t host_unicode_case_delta(uint32_t scalar, uint32_t mapping);
IMPORT("unicode_case_special") extern uint32_t host_unicode_case_special(uint32_t scalar, uint32_t mapping, uint8_t *buffer, uint32_t capacity);

/* Normalization. The 16-bit value packs the canonical combining class (bits 3-10), NFC_QC (bits 1-2: 0 yes, 1 no,
 * 2 maybe) and NFD_QC (bit 0: 1 when the scalar decomposes). */
WEAK uint16_t _swift_stdlib_getNormData(uint32_t scalar) { return (uint16_t)host_unicode_norm_data(scalar); }

/* A decomposition entry is an offset into `_swift_stdlib_nfd_decompositions` (top 14 bits, pointing at a length byte
 * followed by the UTF-8 of the full canonical decomposition) and the scalar it belongs to (low 18 bits). The standard
 * library reads the bytes right after asking, so one buffer at offset 0 serves every lookup; an entry of 0 names no
 * scalar the library asks about (those start at U+00C0), which it reads as "no decomposition". The longest canonical
 * decomposition is four scalars. */
static uint8_t decomposition[64];
WEAK const uint8_t *_swift_stdlib_nfd_decompositions = decomposition;
WEAK uint32_t _swift_stdlib_getDecompositionEntry(uint32_t scalar) {
    uint32_t length = host_unicode_decomposition(scalar, decomposition + 1, (uint32_t)sizeof decomposition - 1);
    if (length == 0 || length >= sizeof decomposition || scalar > 0x3FFFFu) return 0;
    decomposition[0] = (uint8_t)length;
    return scalar;
}
/* The primary composite of the two scalars, or UINT32_MAX when there is none. */
WEAK uint32_t _swift_stdlib_getComposition(uint32_t first, uint32_t second) { return host_unicode_composition(first, second); }

/* Grapheme breaking: 0 Control, 1 Extend, 2 Prepend, 3 SpacingMark, anything else Any. The library resolves ASCII,
 * Hangul, regional indicators and ZWJ before asking. */
WEAK uint8_t _swift_stdlib_getGraphemeBreakProperty(uint32_t scalar) { return (uint8_t)host_unicode_grapheme_break(scalar); }
WEAK _Bool _swift_stdlib_isInCB_Consonant(uint32_t scalar) { return host_unicode_incb_consonant(scalar) != 0; }
WEAK _Bool _swift_stdlib_isExtendedPictographic(uint32_t scalar) { return host_unicode_extended_pictographic(scalar) != 0; }

/* Case mapping (`mapping`: 0 uppercase, 1 lowercase, 2 titlecase). The library first asks for a mapping to more than
 * one scalar (UTF-8, with its length), then for the distance to a single mapped scalar. */
static uint8_t caseMapping[64];
WEAK int32_t _swift_stdlib_getMapping(uint32_t scalar, uint8_t mapping) { return host_unicode_case_delta(scalar, mapping); }
WEAK const uint8_t *_swift_stdlib_getSpecialMapping(uint32_t scalar, uint8_t mapping, intptr_t *length) {
    uint32_t count = host_unicode_case_special(scalar, mapping, caseMapping, (uint32_t)sizeof caseMapping);
    if (count == 0 || count > sizeof caseMapping) { *length = 0; return 0; }
    *length = (intptr_t)count;
    return caseMapping;
}
#endif
