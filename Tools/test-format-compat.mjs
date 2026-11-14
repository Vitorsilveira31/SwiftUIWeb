#!/usr/bin/env bun
// Tools/format-compat.mjs keeps the byte-level behaviour the measurement tools depend on: float repr, `round`, the
// two-decimal format, the JSON layout, and argparse exit codes. The expected values below are literals.
import assert from "node:assert/strict";
import { compareParts, dumps, Float, fixed, floatRepr, parseJson, displayText, roundTo } from "./format-compat.mjs";
import { finish, test } from "./measurement-test-support.mjs";

await test("float repr has the shortest round-trip digits", () => {
  const cases = [
    [0.0, "0.0"], [-0.0, "-0.0"], [1.0, "1.0"], [0.5, "0.5"], [100.0, "100.0"], [1e15, "1000000000000000.0"], [1e16, "1e+16"], [1e17, "1e+17"],
    [123456789.123456789, "123456789.12345679"], [1e-4, "0.0001"], [1e-5, "1e-05"], [0.00012345, "0.00012345"], [5e-324, "5e-324"],
    [1.7976931348623157e308, "1.7976931348623157e+308"], [0.1, "0.1"], [0.30000000000000004, "0.30000000000000004"], [2.5e10, "25000000000.0"],
    [1e300, "1e+300"], [-1.5, "-1.5"], [12.125, "12.125"], [Math.PI, "3.141592653589793"], [1234567890123456.0, "1234567890123456.0"],
    [12345678901234567.0, "1.2345678901234568e+16"], [Infinity, "inf"], [-Infinity, "-inf"],
  ];
  for (const [value, text] of cases) assert.equal(floatRepr(value), text, String(value));
  assert.equal(String(new Float(4)), "4.0");
  assert.equal(displayText(null), "None");
  assert.equal(displayText(true), "True");
  assert.equal(displayText(3), "3");
  assert.equal(displayText(new Float(3)), "3.0");
});

await test("fixed breaks exact ties to the even digit, like f-strings", () => {
  const cases = [
    [12.125, 2, "12.12"], [12.135, 2, "12.13"], [0.0625, 3, "0.062"], [0.0625, 2, "0.06"], [2.5, 0, "2"], [1.005, 2, "1.00"], [0.375, 2, "0.38"],
    [-0.125, 2, "-0.12"], [-2.675, 2, "-2.67"], [100.0, 2, "100.00"], [75.0, 1, "75.0"], [0.04999, 1, "0.0"], [1234.5678, 3, "1234.568"],
    [0.5, 0, "0"], [1.5, 0, "2"], [0.0005, 3, "0.001"], [98.765, 2, "98.77"],
  ];
  for (const [value, digits, text] of cases) assert.equal(fixed(value, digits), text, `${value}:.${digits}f`);
  assert.equal(String(roundTo(12.125, 2)), "12.12");
  assert.equal(String(roundTo(75, 2)), "75.0");
});

const sample = () => ({ b: [1, new Float(2), { z: null, a: true }], a: "é\u0000\n\"\\😀/\x7f", c: {}, d: [], e: new Float(1e16), f: 12345678901234567890n });

await test("dumps lays out JSON like json.dumps", () => {
  assert.equal(dumps(sample()), '{"b": [1, 2.0, {"z": null, "a": true}], "a": "\\u00e9\\u0000\\n\\"\\\\\\ud83d\\ude00/\\u007f", "c": {}, "d": [], "e": 1e+16, "f": 12345678901234567890}');
  assert.equal(
    dumps(sample(), { indent: 2 }),
    '{\n  "b": [\n    1,\n    2.0,\n    {\n      "z": null,\n      "a": true\n    }\n  ],\n  "a": "\\u00e9\\u0000\\n\\"\\\\\\ud83d\\ude00/\\u007f",\n  "c": {},\n  "d": [],\n  "e": 1e+16,\n  "f": 12345678901234567890\n}',
  );
  assert.equal(
    dumps(sample(), { indent: 1, sortKeys: true, ensureAscii: false }),
    '{\n "a": "é\\u0000\\n\\"\\\\😀/\x7f",\n "b": [\n  1,\n  2.0,\n  {\n   "a": true,\n   "z": null\n  }\n ],\n "c": {},\n "d": [],\n "e": 1e+16,\n "f": 12345678901234567890\n}',
  );
  assert.equal(
    dumps(sample(), { separators: [",", ":"], ensureAscii: false }),
    '{"b":[1,2.0,{"z":null,"a":true}],"a":"é\\u0000\\n\\"\\\\😀/\x7f","c":{},"d":[],"e":1e+16,"f":12345678901234567890}',
  );
});

await test("parseJson keeps floats, big integers and the order of integer-like keys", () => {
  const text = '{"10": 1.0, "2": 2, "name": [1e3, -0.5, 12345678901234567890], "x": {"3": null, "1": true}}';
  const value = parseJson(text);
  assert.ok(value["10"] instanceof Float);
  assert.equal(dumps(value), '{"10": 1.0, "2": 2, "name": [1000.0, -0.5, 12345678901234567890], "x": {"3": null, "1": true}}');
  assert.throws(() => parseJson("{"), SyntaxError);
  assert.throws(() => parseJson("[1,]"), SyntaxError);
  assert.throws(() => parseJson("1 2"), SyntaxError);
});

await test("path parts sort like pathlib, not like strings", () => {
  const names = ["a-c", "a/b", "a", "a/b/c", "B", "a.js"];
  // Paths sort by their parts: "a/b" comes first; a plain string sort would put "a-c" and "a.js" before "a/b".
  assert.deepEqual([...names].sort(compareParts), ["B", "a", "a/b", "a/b/c", "a-c", "a.js"]);
  assert.deepEqual([...names].sort(), ["B", "a", "a-c", "a.js", "a/b", "a/b/c"]);
});

await test("a __proto__ key is an ordinary own property", () => {
  const value = parseJson('{"__proto__": {"x": 1}}');
  assert.equal(Object.getPrototypeOf(value), Object.prototype);
  assert.deepEqual(Object.keys(value), ["__proto__"]);
});

finish();
