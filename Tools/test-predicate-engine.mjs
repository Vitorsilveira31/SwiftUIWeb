#!/usr/bin/env bun
// The NSPredicate engine that answers BrowserIO's `predicate` operation (Tools/BrowserIO/predicate-engine.mjs). The
// specification is what Apple's Foundation answered: `Tests/Fixtures/nspredicate_corpus.json` records
// 8880 formats with their `predicateFormat`, substitutions and `evaluate(with:)` results (Tools/nspredicate-probe builds
// it on a Mac). The rest pins individual rules, the regular expression dialect and the wire format Swift writes.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Bag, Obj, Predicate, Raise, Time, createPredicates, decode, decodeList } from "./BrowserIO/predicate-engine.mjs";
import { finish, ROOT, test } from "./measurement-test-support.mjs";

const CORPUS = join(ROOT, "Tests/Fixtures/nspredicate_corpus.json");

/** Cases whose answers cannot be matched, and why. A case is listed by a piece of its format; the test fails if a listed
 * piece no longer matches a differing case, so the list cannot go stale. */
const KNOWN_DIVERGENCES = [
  ["FUNCTION(", "function expressions are not parsed"],
  ["function(", "function expressions are not parsed"],
  ["max(x)", "function expressions are not parsed"],
  ["sum:", "function expressions are not parsed"],
  ["uppercase:", "function expressions are not parsed"],
  ["CAST(", "CAST is not parsed"],
  ["SUBQUERY(", "SUBQUERY is not parsed"],
  ["[0]", "index expressions are not parsed"],
  ["x[", "index expressions are not parsed"],
  ["x.$y", "variables inside a key path are not parsed"],
  ["order | 1", "bitwise operators are not parsed"],
  ["order ^ 1", "bitwise operators are not parsed"],
  ["order & 1", "bitwise operators are not parsed"],
  ["1..2", "Foundation reads `1.0.2` as a key path"],
  ["0b101", "Foundation reads `0b101` as `0` followed by a key"],
  ["-x.y", "Foundation raises for the negation of a key path's number"],
  ["@count.nil", "Foundation raises when a key follows @count"],
];

const show = (value) => JSON.stringify(value, (_key, item) => (typeof item === "bigint" ? Number(item) : item));
const dict = (entries) => new Map(Object.entries(entries));
/** The evaluation of `format` on `object`, or "raise" where Foundation raises; `undefined` when it does not parse. */
function run(format, object, { args, variables } = {}) {
  try {
    let predicate = Predicate.parse(format, args);
    if (variables) predicate = predicate.substitute(new Map(Object.entries(variables)));
    return predicate.evaluate(object);
  } catch (error) {
    if (error instanceof Raise) return "raise";
    throw error;
  }
}
const parses = (format, args) => { try { Predicate.parse(format, args); return true; } catch (error) { if (error instanceof Raise) return false; throw error; } };
const format = (text, args) => Predicate.parse(text, args).format;

// MARK: The corpus

/** The probe's JSON as values: whole numbers are integers, others doubles; `$i $f $b $d $null $nil $set` wrap the rest. */
function typed(json, nilIsNull) {
  if (json === null) return undefined;
  if (Array.isArray(json)) return json.map((item) => typed(item, true));
  if (typeof json === "object") {
    const keys = Object.keys(json);
    if (keys.length === 1) {
      const [key] = keys, value = json[key];
      if (key === "$i") return BigInt(value);
      if (key === "$f") return Number(value);
      if (key === "$b") return Boolean(value);
      if (key === "$d") return new Time(Number(value));
      if (key === "$null") return null;
      if (key === "$nil") return nilIsNull ? null : undefined;
      if (key === "$set") return Bag.from(value.map((item) => typed(item, true)));
    }
    return new Map(keys.map((key) => [key, typed(json[key], true)]));
  }
  return json;
}

/** Numbers keep their spelling: `2.5` and `1.0` are doubles, `3` an integer (JSON.parse alone cannot tell, and loses
 * the low bits of a 64-bit one). */
const number = (_key, value, { source } = {}) => (typeof value !== "number" ? value : /^-?\d+$/.test(source) && BigInt.asIntN(64, BigInt(source)) === BigInt(source) ? { $int: source } : Number(source));
const ints = (json) => {
  if (Array.isArray(json)) return json.map(ints);
  if (json && typeof json === "object") {
    if (Object.keys(json).length === 1 && "$int" in json) return BigInt(json.$int);
    return Object.fromEntries(Object.entries(json).map(([key, item]) => [key, ints(item)]));
  }
  return json;
};

/** What differs for one case, one line each. */
function check(c, objects) {
  const label = c.a ? `${c.f} ${show(c.a)}` : c.f;
  const appleParsed = c.e == null;
  let predicate;
  try { predicate = Predicate.parse(c.f, (c.a ?? []).map((item) => typed(item, true))); }
  catch (error) { if (!(error instanceof Raise)) throw error; return appleParsed ? [`${label}: Apple parses it, we reject it`] : []; }
  if (!appleParsed) return [`${label}: Apple rejects it, we parse ${JSON.stringify(predicate.format)}`];
  const differences = [];
  if (predicate.format !== (c.p ?? "")) differences.push(`${label}: predicateFormat ${JSON.stringify(predicate.format)}, Apple ${JSON.stringify(c.p)}`);
  let evaluated = predicate;
  if (c.v) {
    evaluated = predicate.substitute(new Map(Object.entries(c.v).map(([name, value]) => [name, typed(value, true)])));
    if (evaluated.format !== (c.s ?? "")) differences.push(`${label}: substituted ${JSON.stringify(evaluated.format)}, Apple ${JSON.stringify(c.s)}`);
  }
  (c.o ?? []).forEach((name, at) => {
    let ours;
    try { ours = evaluated.evaluate(objects.get(name)) ? "T" : "F"; } catch (error) { if (!(error instanceof Raise)) throw error; ours = "X"; }
    if (ours !== (c.r ?? "")[at]) differences.push(`${label} on ${name}: ${ours}, Apple ${(c.r ?? "")[at]}`);
  });
  return differences;
}

await test("matches what Foundation answered (8880 formats)", () => {
  const corpus = ints(JSON.parse(readFileSync(CORPUS, "utf8"), number));
  const objects = new Map(Object.entries(corpus.objects).map(([name, value]) => [name, typed(value, false)]));
  const failures = [];
  const matched = KNOWN_DIVERGENCES.map(() => false);
  let evaluations = 0;
  for (const c of corpus.cases) {
    evaluations += c.o?.length ?? 0;
    const differences = check(c, objects);
    const known = KNOWN_DIVERGENCES.findIndex(([piece]) => c.f.includes(piece));
    if (known >= 0) matched[known] ||= differences.length > 0;
    else failures.push(...differences);
  }
  const stale = KNOWN_DIVERGENCES.filter((_, at) => !matched[at]).map(([piece]) => piece);
  assert.deepEqual(stale, [], `known divergences that now match: ${stale}`);
  assert.equal(failures.length, 0, `${failures.length} differences in ${corpus.cases.length} cases (${evaluations} evaluations):\n${failures.slice(0, 40).join("\n")}`);
});

// MARK: Rules, one by one

await test("the canonical format follows Foundation", () => {
  for (const [text, canonical] of [
    ["name = 'a' && age <> 3", 'name == "a" AND age != 3'],
    ["a == 1 OR b == 2 AND c == 3", "a == 1 OR (b == 2 AND c == 3)"],
    ["NOT (a == 1 AND b == 2)", "NOT (a == 1 AND b == 2)"],
    ["a == 1 AND NOT b == 2", "a == 1 AND (NOT b == 2)"],
    ["NOT NOT a == 1", "a == 1"],
    ["NONE tags == 'x'", 'NOT ANY tags == "x"'],
    ["SOME tags == 'x'", 'ANY tags == "x"'],
    ["SELF.name LIKE[CD] 'a*'", 'name LIKE[cd] "a*"'],
    ["x == YES AND y == nil", "x == 1 AND y == nil"],
    ["x == 0x10 AND y == 1e2 AND z == .5", "x == 16 AND y == 100 AND z == 0.5"],
    ["i + 1 * 2 > -3", "i + (1 * 2) > -3"],
    ["-i < 1", "0 - i < 1"],
    ["x BETWEEN {1, 2}", "x BETWEEN {1, 2}"],
    ["x IN {'a', 'b'}", 'x IN {"a", "b"}'],
    ["name == 'it\\'s \"q\" \\\\'", 'name == "it\'s \\"q\\" \\\\"'],
    ["name == 'caf\\u00e9\\x21'", 'name == "café!"'],
    ["TRUEPREDICATE", "TRUEPREDICATE"],
    ["a.b.@sum.c == $X.d", "a.b.@sum.c == $X.d"],
  ]) assert.equal(format(text), canonical, text);
});

await test("format arguments substitute in order", () => {
  const args = ["Alice", 30n, 2.5, "address.city"];
  assert.equal(format("name == %@ AND age > %d AND score < %f AND %K == 'x'", args), 'name == "Alice" AND age > 30 AND score < 2.5 AND address.city == "x"');
  // `%` inside a literal is text, an extra argument is ignored, a missing one is an error.
  assert.equal(format("name == '%@'", args), 'name == "%@"');
  assert.equal(parses("a == %@ AND b == %@", args.slice(0, 1)), false);
  assert.equal(parses("%K == 1", [1n]), false);
  assert.equal(parses("a == %q", args), false);
});

await test("malformed formats are rejected", () => {
  for (const text of ["", "name", "name ==", "== 1", "a == 1 AND", "(a == 1", "a == 1)", "a === 1", "a ==[] 1", "a == 'x", "{1,2}", "a == 5.", "a == +5",
    "a == 1;", "a[0] == 1", "FUNCTION(a, 'b') == 1", "SUBQUERY(a, $x, $x > 1).@count == 1", "TRUEPREDICATE junk", "a == 1 b == 2", "a == 5e", "a == 5e+", "x == 0x"]) {
    assert.equal(parses(text), false, JSON.stringify(text));
  }
});

await test("nil handling and numeric coercion", () => {
  const object = dict({ age: 30n, score: 2.5, nick: null, name: "Alice" });
  for (const [text, expected] of [
    ["age == 30.0", true], ["score > 2 AND score < age", true], ["nick == nil AND missing == nil", true],
    ["missing != 5 AND NOT missing == 5", true], ["missing < 5 OR missing > 5", false], ["missing <= nil", true],
    ["name CONTAINS missing", false], ["age < 'x'", "raise"], ["age == 'x'", false], ["age CONTAINS 3", "raise"],
  ]) assert.equal(run(text, object), expected, text);
  // A nil object reads every key as nil.
  assert.equal(run("name == nil", undefined), true);
  assert.equal(run("ANY tags == 'x'", undefined), false);
  assert.equal(run("ALL tags == 'x'", undefined), true);
});

await test("string options fold case and diacritics", () => {
  const object = dict({ city: "São Paulo", decomposed: "cafe\u0301" });
  for (const [text, expected] of [
    ["city == 'sao paulo'", false], ["city ==[c] 'são paulo'", true], ["city ==[d] 'Sao Paulo'", true], ["city ==[cd] 'SAO PAULO'", true],
    ["city CONTAINS[cd] 'ao pa'", true], ["city BEGINSWITH[d] 'Sa'", true], ["city ENDSWITH 'Paulo'", true],
    // A letter and its accent are one character: `e` is not inside `é`.
    ["decomposed CONTAINS 'e'", false], ["decomposed LIKE 'caf?'", true], ["decomposed == 'café'", false], ["decomposed ==[cd] 'CAFÉ'", true],
  ]) assert.equal(run(text, object), expected, text);
  assert.equal(run("SELF < 'cafz'", "café"), true);
});

await test("LIKE and MATCHES: wildcards, escapes and empty strings", () => {
  for (const [text, expected] of [
    ["SELF LIKE 'Hello*'", true], ["SELF LIKE '*World'", true], ["SELF LIKE 'H?llo, W?rld'", true], ["SELF LIKE '*o*o*'", true], ["SELF LIKE 'hello*'", false],
    ["SELF LIKE[c] 'hello*'", true], ["SELF LIKE ''", false], ["SELF LIKE '[A-Z]*'", false], ["SELF MATCHES 'Hello, World'", true], ["SELF MATCHES 'Hello'", false],
    ["SELF MATCHES '(?i)hello.*'", true], ["SELF MATCHES[c] 'HELLO.*'", true], ["SELF MATCHES '\\\\w+, \\\\w+'", true], ["SELF MATCHES '['", "raise"],
  ]) assert.equal(run(text, "Hello, World"), expected, text);
  assert.equal(run("SELF LIKE '*'", ""), true);
  // The format parser unescapes a doubled backslash first, so LIKE sees `a\*c`: a literal star.
  assert.equal(run("SELF LIKE 'a\\\\*c'", "a*c"), true);
  assert.equal(run("SELF LIKE 'a\\\\*c'", "abc"), false);
  assert.equal(run("SELF LIKE 'a\\*c'", "abc"), true);
  assert.equal(run("SELF LIKE 'abc\\\\'", "abc"), "raise"); // a pattern that ends in a lone backslash is invalid
});

await test("quantifiers, collections and key paths", () => {
  const object = dict({
    tags: ["swift", "web"],
    friends: [dict({ name: "Bob", age: 25n }), dict({ name: "Carol", age: 35n })],
    address: dict({ city: "Lisbon" }),
  });
  for (const [text, expected] of [
    ["ANY tags == 'web'", true], ["ALL tags BEGINSWITH 's'", false], ["NONE tags == 'go'", true], ["tags.@count == 2", true], ["friends.@sum.age == 60", true],
    ["friends.@avg.age == 30", true], ["friends.@min.age == 25 AND friends.@max.age == 35", true], ["friends.@max.name == 'Carol'", true],
    ["ANY friends.name == 'Bob'", true], ["friends.name CONTAINS 'Carol'", true], ["address.city.length == 6", true], ["address.@count == 1", true],
    ["'swift' IN tags", true], ["tags CONTAINS[c] 'WEB'", false], ["tags == {'swift', 'web'}", true], ["friends.@sum == 1", "raise"],
  ]) assert.equal(run(text, object), expected, text);
  const keys = Predicate.parse("ANY friends.name == 'Bob' AND address.city == 'x' AND tags.@count > 0").keys();
  assert.deepEqual(keys, { names: ["friends", "name", "address", "city", "tags"], depth: 2 });
});

await test("arithmetic follows integer and floating point rules", () => {
  const object = dict({ age: 30n, score: 2.5 });
  for (const [text, expected] of [
    ["age + 1 == 31", true], ["age / 4 == 7", true], ["age / 4.0 == 7.5", true], ["age / 0 == 0", true], ["age ** 2 == 900", true], ["score * 2 == 5", true],
    ["(age + 1) * 2 == 62", true], ["-age < 0", true], ["2 ** -1 == 0.5", true], ["age + missing == 1", "raise"],
    ["9223372036854775807 + 1 < 0", true], ["1 ** 99999 == 1", true],
  ]) assert.equal(run(text, object), expected, text);
});

await test("substitution binds variables and leaves the rest", () => {
  const predicate = Predicate.parse("age > $MIN AND name == $NAME AND $LIST.@count == 2");
  const bindings = new Map([["MIN", 18n], ["NAME", null]]);
  const partly = predicate.substitute(bindings);
  assert.equal(partly.format, "age > 18 AND name == nil AND $LIST.@count == 2");
  const object = dict({ age: 30n });
  assert.throws(() => partly.evaluate(object), Raise); // an unbound variable raises when it is reached
  bindings.set("LIST", [1n, 2n]);
  assert.equal(predicate.substitute(bindings).evaluate(object), true);
  assert.equal(Predicate.parse("'abcd'.length == $N").substitute(new Map([["N", 4n]])).evaluate(undefined), true);
});

await test("class instances compare by identity", () => {
  const first = new Obj(1n, new Map()), second = new Obj(2n, new Map());
  const predicate = Predicate.parse("SELF == %@", [first]);
  assert.equal(predicate.evaluate(first), true);
  assert.equal(predicate.evaluate(second), false);
});

await test("evaluation short-circuits like Foundation", () => {
  const object = dict({ age: 3n });
  assert.equal(run("FALSEPREDICATE AND age < 'x'", object), false);
  assert.equal(run("TRUEPREDICATE OR age < 'x'", object), true);
  assert.equal(run("TRUEPREDICATE AND age < 'x'", object), "raise");
});

await test("constant predicates and dates", () => {
  assert.equal(format("FALSEPREDICATE"), "FALSEPREDICATE");
  const object = dict({ when: new Time(1_600_000_000) });
  const later = Predicate.parse("when < %@", [new Time(1_700_000_000)]);
  assert.equal(later.evaluate(object), true);
  assert.equal(later.format, 'when < CAST(721692800.000000, "NSDate")');
  const between = Predicate.parse("when BETWEEN %@", [[new Time(0), new Time(2_000_000_000)]]);
  assert.equal(between.evaluate(object), true);
  assert.equal(between.format, "when BETWEEN {1970-01-01 00:00:00 +0000, 2033-05-18 03:33:20 +0000}");
  for (const [seconds, expected] of [[-0.5, "1969-12-31 23:59:59 +0000"], [0, "1970-01-01 00:00:00 +0000"], [1_600_000_000.75, "2020-09-13 12:26:40 +0000"]]) {
    assert.equal(run(`SELF.description == '${expected}'`, new Time(seconds)), true, expected);
  }
});

await test("collection operators follow Foundation", () => {
  const friend = (name, age) => dict({ name, age });
  const object = dict({
    friends: [friend("Bob", 25n), friend("Carol", 35n), friend("Bob", 25n)],
    scores: [1.5, 2.5], mixed: [2n, 0.5], big: [2n ** 63n - 1n, 1n], ints: [3n, 3n, 4n],
  });
  for (const [text, expected] of [
    ["friends.@sum.age == 85", true], ["friends.@max.age == 35", true], ["ANY friends.@distinctUnionOfObjects.name == 'Bob'", true],
    ["friends.@distinctUnionOfObjects.name == {'Bob', 'Carol'}", true], ["scores.@sum.doubleValue == 4.0", true], ["scores.@avg.doubleValue == 2.0", true],
    ["mixed.@sum.doubleValue == 2.5", true], ["mixed.@avg.doubleValue == 1.25", true],
    ["big.@sum.doubleValue > 0", true], // the integer sum overflows, so the sum is a double
    ["ints.@sum.intValue == 10", true], ["missing.@count == nil", true], ["missing.@sum == nil", true],
    ["friends.@sum == 1", "raise"], ["friends.@foo.age == 1", "raise"], ["friends.@unionOfArrays.name.@count == 2", "raise"],
  ]) assert.equal(run(text, object), expected, text);
});

await test("string literals and numbers follow Foundation", () => {
  for (const [text, subject] of [["SELF == 'a\\rb'", "a\rb"], ["SELF == '\\x41\\u0042'", "AB"], ["SELF == '\\a\\b\\f\\v'", "\x07\x08\x0c\x0b"], ["SELF == '\\101'", "A"],
    ["SELF ==[c] 'ς'", "Σ"], ["SELF == -2.5", -2.5], ["SELF == 99999999999999999999", 1e20], ["(SELF).name == 'Alice'", dict({ name: "Alice" })]]) {
    assert.equal(run(text, subject), true, text);
  }
  assert.equal(run("SELF == -2.5", 2.5), false);
  assert.equal(format("SELF == 1e20"), "SELF == 1e+20");
  assert.equal(format("a == 5e+3"), "a == 5000");
  assert.equal(format("(SELF).name == 'Alice'"), 'name == "Alice"');
});

await test("key names cover aggregates, arithmetic, negation and constants", () => {
  assert.deepEqual(Predicate.parse("name IN {age, nick.first} AND score + bonus > 1").keys(), { names: ["name", "age", "nick", "first", "score", "bonus"], depth: 2 });
  assert.deepEqual(Predicate.parse("NOT (flag == 1)").keys(), { names: ["flag"], depth: 1 });
  assert.deepEqual(Predicate.parse("TRUEPREDICATE").keys(), { names: [], depth: 0 });
  assert.deepEqual(Predicate.parse("'abcd'.length == 4").keys(), { names: [], depth: 0 });
});

await test("LIKE's question mark is one composed character", () => {
  for (const [subject, expected] of [["x\u0301", true], ["x\u0301\u0302", false], ["xy", true], ["x", false]]) assert.equal(run("SELF LIKE 'x?'", subject), expected, JSON.stringify(subject));
  assert.equal(run("SELF LIKE 'x?'", "xq\u0301"), false);
  assert.equal(run("SELF LIKE 'x*'", "xq\u0301"), true);
  assert.equal(run("SELF LIKE %@", "aX\u{1F600}zz", { args: ["a?\u{1F600}*"] }), true); // characters beyond the BMP are one character
});

await test("key path keywords are read as their numbers", () => {
  assert.equal(parses("SELF.NO == 7"), true);
  assert.equal(parses("SELF.YES == 8"), true);
});

await test("doubles print like %.16g", () => {
  for (const [number, text] of [[2.5, "2.5"], [100, "100"], [0.1, "0.1"], [1e20, "1e+20"], [1e-7, "1e-07"], [0.0015, "0.0015"], [123456789.12345679, "123456789.1234568"],
    [-0.5, "-0.5"], [1e16, "1e+16"], [1e15, "1000000000000000"], [9.223372036854776e18, "9.223372036854776e+18"], [NaN, "nan"], [Infinity, "inf"], [-Infinity, "-inf"]]) {
    assert.equal(format("x == %@", [number]), `x == ${text}`);
  }
});

// MARK: ICU regular expressions

/** Answers Foundation gave for `SELF MATCHES` (ICU with dot-all and multiline on): the match result, or null where Foundation raised. */
const FOUNDATION_MATCHES = [
  ["\\e", "\u{1b}", true],
  ["\\a", "\u{7}", true],
  ["\\f", "\u{c}", true],
  ["\\t", "\u{9}", true],
  ["\\n", "\u{a}", true],
  ["\\r", "\u{d}", true],
  ["\\x41", "A", true],
  ["\\x{41}", "A", true],
  ["\\x{1F600}", "\u{1f600}", true],
  ["\\u00e9", "\u{e9}", true],
  ["\\U0001F600", "\u{1f600}", true],
  ["\\0", "\u{0}", null],
  ["\\012", "\u{a}", true],
  ["\\0101", "A", true],
  ["\\0101", "A1", false],
  ["\\101", "A", null],
  ["\\1011", "A1", null],
  ["\\cA", "\u{1}", true],
  ["\\c", "c", true],
  ["\\cz", "\u{1a}", true],
  ["\\H", " ", false],
  ["\\H", "\u{a}", true],
  ["\\V", "\u{a}", false],
  ["\\V", " ", true],
  ["\\h", "\u{9}", true],
  ["\\v", "\u{b}", true],
  ["a\\Z", "a\u{a}", false],
  ["a\\Z", "a", true],
  ["a\\z", "a\u{a}", false],
  ["\\Aa", "a", true],
  ["a\\Z\\z", "a", true],
  ["\\p{L}", "\u{e9}", true],
  ["\\P{L}", "1", true],
  ["\\p{Lu}", "A", true],
  ["\\p{Ll}", "A", false],
  ["\\p{N}", "5", true],
  ["\\p{P}", "!", true],
  ["\\p{S}", "+", true],
  ["\\p{Z}", " ", true],
  ["\\p{Cc}", "\u{a}", true],
  ["\\pL", "x", null],
  ["\\p{M}", "\u{301}", true],
  ["\\p{Mn}", "\u{301}", true],
  ["\\p{Alnum}", "x", true],
  ["\\p{Alphabetic}", "x", true],
  ["\\p{Foo}", "x", null],
  ["\\p{", "x", null],
  ["\\p", "x", null],
  ["\\p{Lu}\\P{Lu}", "Ab", true],
  ["\\p{Zs}", " ", true],
  ["[\\d\\s]", " ", true],
  ["[\\d\\s]", "5", true],
  ["[\\D]", "1", false],
  ["[\\W]", "!", true],
  ["[\\S]", " ", false],
  ["[\\h]", "\u{9}", true],
  ["[\\V]", "\u{a}", false],
  ["[\\v]", "\u{a}", true],
  ["[\\p{Lu}]", "A", true],
  ["[\\P{L}]", "1", true],
  ["[^a-c]", "d", true],
  ["[^a-c]", "b", false],
  ["[a-]", "-", true],
  ["[\\]]", "]", true],
  ["[\\x41-\\x43]", "B", true],
  ["[\\u0041-C]", "C", true],
  ["[z-a]", "b", null],
  ["[a", "a", null],
  ["[]", "]", null],
  ["[]a]", "]", true],
  ["[^]a]", "b", true],
  ["[\\w]", "_", true],
  ["[\\e]", "\u{1b}", true],
  ["[\\n]", "\u{a}", true],
  ["[\\D\\s]", "x", true],
  ["[\\d-z]", "-", true],
  ["[a-\\d]", "-", null],
  ["[\\p{L}\\d]", "7", true],
  ["[\\W\\S]", "a", true],
  ["[\\p{Lu}-z]", "a", false],
  ["[\\q]", "q", true],
  ["[\\u0041]", "A", true],
  ["[\\x{42}]", "B", true],
  ["[\\cA]", "\u{1}", true],
  ["[\\H\\V]", "x", true],
  ["[\\0101]", "A", true],
  ["[a\\]b]", "]", true],
  ["[\\\\]", "\\", true],
  ["(?#note)a", "a", true],
  ["(?x) a b # c\u{a}", "ab", true],
  ["(?x)a #c\u{a}b", "ab", true],
  ["(?x)a\\ b", "a b", true],
  ["(?i:ab)c", "ABc", true],
  ["(?i:ab)c", "ABC", false],
  ["(?i)a(?-i:b)", "Ab", true],
  ["(?i)a(?-i:b)", "AB", false],
  ["(?s:.)", "\u{a}", true],
  ["(?s).", "\u{a}", true],
  [".", "\u{a}", true],
  ["(?m)^b$", "a\u{a}b\u{a}c", false],
  ["^b$", "a\u{a}b", false],
  ["(?m)a$", "a\u{a}b", false],
  ["(?i-)a", "A", true],
  ["(?i-m)a", "A", true],
  ["(?q)a", "a", null],
  ["(?i", "a", null],
  ["(?", "a", null],
  ["(?Q)", "x", null],
  ["(?i)(?x)a b", "AB", true],
  ["(?<n>a)", "a", true],
  ["(?<n>a)(?<n>b)", "ab", null],
  ["(?<1x>a)", "a", null],
  ["(?<a-b>c)", "c", null],
  ["(?<n>a)\\1", "aa", true],
  ["(?<=a)b", "ab", false],
  ["(?<!a)b", "cb", false],
  ["a(?=b)b", "ab", true],
  ["a(?!b)", "ac", false],
  ["(?<=a|bc)d", "bcd", false],
  ["(?<x", "a", null],
  ["(?<=a", "a", null],
  ["(?<=a)*a", "a", null],
  ["(?<a", "a", null],
  ["(?>a+)", "aa", true],
  ["(?>a+)a", "aa", false],
  ["(?>a", "a", null],
  ["(a)\\1", "aa", true],
  ["(a)\\1", "ab", false],
  ["(?i)(a)\\1", "aA", true],
  ["(a)\\2", "a", null],
  ["\\1", "a", null],
  ["(a)\\", "a", null],
  ["(a)(b)\\2\\1", "abba", true],
  ["a{2}", "aa", true],
  ["a{2,}", "aaa", true],
  ["a{1,2}", "aaa", false],
  ["a{0,}", "", true],
  ["a{,3}", "a", null],
  ["a{3,2}", "aaa", null],
  ["a{x}", "a", null],
  ["a{2", "aa", null],
  ["a{2,3", "aa", null],
  ["a{2,", "aa", null],
  ["a*?", "", true],
  ["a+?", "aa", true],
  ["a??", "a", true],
  ["a*+", "aaa", true],
  ["a++a", "aa", false],
  ["a**", "a", null],
  ["a+?+", "a", null],
  ["a{2}+", "aa", true],
  ["a{2}?", "aa", true],
  ["*a", "a", null],
  ["{", "{", null],
  ["a{1}{2}", "a", null],
  ["(?=a)*a", "a", null],
  ["\\b*", "", null],
  ["a{99999999999}", "a", null],
  ["a{1,99999999999}", "a", null],
  ["a{1,2}?", "a", true],
  [")", "a", null],
  ["(", "a", null],
  ["a)", "a", null],
  ["a|b|", "", true],
  ["|", "", true],
  ["(a|b)+", "abba", true],
  ["", "a", false],
  ["a$", "a\u{a}", false],
  ["\\Ba", "ba", false],
  ["a\\b", "a", true],
  ["\\bA", "A", true],
  ["\\bA", "xA", false],
  ["\\b", "", false],
  ["\\B", "", true],
  ["\\", "x", null],
  ["\\q", "q", true],
  ["\\k", "k", null],
  ["\\x{110000}", "x", null],
  ["\\xZZ", "x", null],
  ["\\u12", "x", null],
  ["\\U00110000", "x", null],
  ["\\x{}", "x", null],
  ["\\x", "x", null],
  ["(?i)[a-c]+", "ABC", true],
  ["(?i)\u{e9}", "\u{c9}", true],
  ["(?i)\u{df}", "\u{1e9e}", true],
  ["(?i)\\x41", "a", true],
  ["(?i)[\\x41]", "a", true],
  ["(?i)\\u0061", "A", true],
  ["(?i)[^a]", "A", false],
  ["(?i)(?:\u{e9})+", "\u{c9}", true],
  ["(?i)\\h", " ", true],
  [".*", "abc", true],
  [".*x", "abcx", true],
  ["(a*)*b", "aaab", true],
  ["(a|ab)(c|bcd)(d*)", "abcd", true],
  ["(?:a", "a", null],
  ["(?=a", "a", null],
  ["(?<n>a", "a", null],
  ["(?#abc", "a", null],
  ["(?i:a", "a", null],
  ["x\\u{00e9}", "x", null],
  ["\\\u{e9}", "\u{e9}", true],
  ["[\\\u{e9}]", "\u{e9}", true],
  ["\\ ", " ", true],
  ["\\-", "-", true],
  ["(aa)\\1", "aaa", false],
  ["(a)?b\\1", "b", false],
  ["(a)?b\\1", "bb", false],
  ["(a)?\\1", "", false],
  ["(a)|b\\1", "b", false],
  ["\\p{P}", "\u{2010}", true],
  ["\\p{S}", "\u{a9}", true],
  ["(?i)\u{130}", "\u{130}", true],
];
// What JavaScript's RegExp cannot answer as ICU does (see the report of the pull request that added this engine).
const REGEX_DIVERGENCES = new Set(["(a)?b\\1|b", "(a)?b\\1|bb", "(a)?\\1|", "(a)|b\\1|b"]);

await test("MATCHES answers as Foundation's ICU did", () => {
  const mismatches = [];
  for (const [pattern, subject, expected] of FOUNDATION_MATCHES) {
    if (REGEX_DIVERGENCES.has(`${pattern}|${subject}`)) continue;
    const actual = run("SELF MATCHES %@", subject, { args: [pattern] });
    if ((actual === "raise" ? null : actual) !== expected) mismatches.push([pattern, subject, actual, expected]);
  }
  assert.deepEqual(mismatches, []);
});

await test("MATCHES: classes, quantifiers, flags, anchors and lookaround", () => {
  const whole = (pattern, subject) => run("SELF MATCHES %@", subject, { args: [pattern] });
  for (const [pattern, subject, expected] of [
    ["abc", "abc", true], ["ab", "abc", false], ["a.*", "abc", true], ["[a-c]{3}", "abc", true], ["a|b", "b", true], ["a|b", "ab", false],
    ["\\w+@\\w+\\.com", "me@site.com", true], ["(ab)+", "abab", true], ["a{2,3}", "aaa", true], ["a{2,3}", "aaaa", false], ["a*?b", "aab", true],
    ["[^0-9]+", "abc", true], ["[^0-9]+", "a1c", false], ["(?i)ABC", "abc", true], ["^abc$", "abc", true], ["\\bfoo\\b", "foo", true], ["(?=a)abc", "abc", true],
    ["(?!a)abc", "abc", false], ["(a)\\1", "aa", true], ["\\d{3}-\\d{4}", "555-1234", true], ["\\x41\\u0042", "AB", true],
    ["caf\u00e9\\b", "caf\u00e9", true], ["\\b\u00e9", "\u00e9", true], ["a++b", "aab", true], ["(?:ab|a)*+c", "abac", true],
  ]) assert.equal(whole(pattern, subject), expected, `${pattern} on ${JSON.stringify(subject)}`);
  for (const pattern of ["[", "(", "a)", "*a", "a**", "a{", "[b-a]", "[a&&b]", "\\", "\\k", "(?<1a>x)", "(?z)", "(?<n>a)(?<n>b)", "a{1,2}{3}", "\\p{Foo}", "(?=a)*"]) {
    assert.equal(whole(pattern, "a"), "raise", pattern);
  }
});

// MARK: The wire format Swift writes (Sources/WebFoundation/PredicateEngine.swift, `_PredicateWire`)

const u32 = (n) => [n & 255, (n >> 8) & 255, (n >> 16) & 255, n >>> 24];
const word64 = (n) => Array.from({ length: 8 }, (_, k) => Number((BigInt.asUintN(64, BigInt(n)) >> BigInt(8 * k)) & 255n));
const wireText = (text) => [...u32(Buffer.byteLength(text)), ...Buffer.from(text)];
const wireString = (text) => [4, ...wireText(text)];
const wireInt = (n) => [2, ...word64(n)];
const wireDouble = (x) => [3, ...new Uint8Array(new Float64Array([x]).buffer)];
const wireItems = (tag, items) => [tag, ...u32(items.length), ...items.flat()];
const wireDict = (entries) => [8, ...u32(entries.length), ...entries.flatMap(([key, value]) => [...wireText(key), ...value])];
const bytes = (list) => Uint8Array.from(list);

/** A value as a string, with the type told apart: integers plain, doubles with a `d`, sets and objects marked. */
function describe(value) {
  if (value === undefined) return "nil";
  if (value === null) return "null";
  if (typeof value === "number") return `${value}d`;
  if (typeof value === "bigint" || typeof value === "boolean") return String(value);
  if (typeof value === "string") return JSON.stringify(value);
  if (value instanceof Time) return `@${value.s}`;
  if (value instanceof Bag) return `set[${value.map(describe).join(" ")}]`;
  if (Array.isArray(value)) return `[${value.map(describe).join(" ")}]`;
  if (value instanceof Obj) return `object#${value.id}{${[...value.props].map(([key, item]) => `${key}=${describe(item)}`).join(" ")}}`;
  return `{${[...value].map(([key, item]) => `${key}=${describe(item)}`).join(" ")}}`;
}

await test("wire values decode every tag, or fail cleanly", () => {
  const cases = [
    [[0], "nil"], [[1], "null"], [[10, 1], "true"], [[10, 0], "false"], [wireInt(-7), "-7"], [wireDouble(2.5), "2.5d"], [[5, ...wireDouble(1.5).slice(1)], "@1.5"],
    [wireItems(6, [wireInt(1), wireInt(2)]), "[1 2]"], [wireItems(7, [wireInt(1), wireInt(1)]), "set[1 1]"],
    [wireDict([["a", wireInt(1)]]), "{a=1}"], [[9, ...word64(42), ...u32(1), ...wireText("k"), ...wireString("v")], 'object#42{k="v"}'],
    [wireString("é"), '"é"'], [wireInt(Number.MIN_SAFE_INTEGER), String(Number.MIN_SAFE_INTEGER)],
  ];
  for (const [wire, expected] of cases) assert.equal(describe(decode(bytes(wire))), expected);
  const two = [...wireString("a"), ...wireString("b")];
  assert.throws(() => decode(bytes(two)), Raise);
  assert.equal(decodeList(bytes(two)).length, 2);
  for (const bad of [[4, 5, 0, 0, 0, 97], [4, 1, 0, 0, 0, 0xff], [0xee], [], [3, 0, 0], [8, 1, 0, 0, 0, 2, 0, 0, 0, 0xff, 0]]) assert.throws(() => decode(bytes(bad)), Raise, JSON.stringify(bad));
  // A buffer nested deeper than the limit is refused rather than recursed into.
  assert.throws(() => decode(bytes([...Array(100).fill([6, 1, 0, 0, 0]).flat(), 0])), Raise);
});

await test("the bytes Swift's tests record decode to the values they stand for", () => {
  // From `collectionEncodingsAreByteIdenticalToTheRecordedWire` in Tests/SwiftUIWebTests/WebFoundationPredicateTests.swift.
  for (const [wire, expected] of [
    [[6, 0, 0, 0, 0], "[]"],
    [[6, 2, 0, 0, 0, 4, 1, 0, 0, 0, 97, 4, 1, 0, 0, 0, 98], '["a" "b"]'],
    [[6, 2, 0, 0, 0, 2, 1, 0, 0, 0, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0], "[1 2]"],
    [[6, 2, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 248, 63, 3, 0, 0, 0, 0, 0, 0, 208, 191], "[1.5d -0.25d]"],
    [[6, 2, 0, 0, 0, 10, 1, 10, 0], "[true false]"],
    [[6, 1, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 89, 64], "[@100]"],
    [[6, 1, 0, 0, 0, 8, 1, 0, 0, 0, 1, 0, 0, 0, 107, 2, 1, 0, 0, 0, 0, 0, 0, 0], "[{k=1}]"],
    [[7, 2, 0, 0, 0, 4, 1, 0, 0, 0, 120, 4, 1, 0, 0, 0, 121], 'set["x" "y"]'],
    [[8, 1, 0, 0, 0, 1, 0, 0, 0, 97, 3, 0, 0, 0, 0, 0, 0, 248, 63], "{a=1.5d}"],
    [[8, 2, 0, 0, 0, 1, 0, 0, 0, 97, 10, 1, 1, 0, 0, 0, 98, 10, 0], "{a=true b=false}"],
    [[6, 2, 0, 0, 0, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0], "[1 nil]"],
    [[6, 2, 0, 0, 0, 6, 2, 0, 0, 0, 2, 1, 0, 0, 0, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0, 6, 1, 0, 0, 0, 4, 1, 0, 0, 0, 120], '[[1 2] ["x"]]'],
    [[8, 1, 0, 0, 0, 1, 0, 0, 0, 107, 8, 1, 0, 0, 0, 1, 0, 0, 0, 97, 4, 1, 0, 0, 0, 120], '{k={a="x"}}'],
  ]) assert.equal(describe(decode(bytes(wire))), expected);
});

await test("a class instance written by Swift is read by the keys the predicate asks for", () => {
  // From `classInstancesAreWrittenWithTheKeysThePredicateReads`: identity 7, keys `name` and `age`.
  const person = bytes([9, ...word64(7), ...u32(2), ...wireText("name"), ...wireString("Alice"), ...wireText("age"), ...wireInt(30)]);
  const alice = decode(person);
  assert.equal(describe(alice), 'object#7{name="Alice" age=30}');
  assert.equal(run("name == 'Alice' AND age > 18", alice), true);
  assert.equal(run("SELF == %@", alice, { args: [alice] }), true);
  assert.equal(run("SELF == %@", new Obj(8n, new Map()), { args: [alice] }), false);
});

await test("the host answers by id from wire bytes: describe, evaluate, variables, failures", () => {
  const predicates = createPredicates();
  const args = bytes([...wireString("Alice"), ...wireInt(18)]);
  const object = bytes(wireDict([["age", wireInt(30)], ["name", wireString("Alice")]]));
  const none = bytes([]);
  const describeAs = (id, text, arguments_, bindings) => predicates.describe(id, text, arguments_, bindings);
  assert.deepEqual(describeAs(1, "name == %@ AND age > %d AND friends.name == 'x'", args, none), { format: 'name == "Alice" AND age > 18 AND friends.name == "x"', names: ["name", "age", "friends"], depth: 2 });
  assert.equal(predicates.evaluate(1, "name == %@ AND age > %d AND friends.name == 'x'", args, none, object), 0);
  assert.equal(predicates.evaluate(2, "name == %@ AND age > %d", args, none, object), 1);
  // Variables arrive as dictionaries, applied one after another; names bound earlier stay bound.
  const first = bytes(wireDict([["MIN", wireInt(40)]])), second = bytes([...first, ...wireDict([["MIN", wireInt(1)], ["NAME", wireString("Alice")]])]);
  assert.equal(describeAs(3, "age > $MIN AND name == $NAME", none, first).format, "age > 40 AND name == $NAME");
  assert.equal(describeAs(4, "age > $MIN AND name == $NAME", none, second).format, 'age > 40 AND name == "Alice"');
  assert.equal(predicates.evaluate(4, "age > $MIN AND name == $NAME", none, second, object), 0);
  assert.equal(predicates.evaluate(5, "age > $MIN", none, none, object), 2); // an unbound variable raises
  assert.equal(predicates.evaluate(6, "age < 'x'", none, none, object), 2);
  assert.equal(predicates.evaluate(7, "age >", none, none, object), 3); // the format does not parse
  assert.equal(describeAs(8, "age >", none, none), null);
  assert.equal(predicates.evaluate(9, "age > 1", none, none, bytes([0xee])), 2); // the object is not a wire value
  // Parsed once per id: later requests under the same id use what the first one made.
  assert.equal(predicates.evaluate(2, "FALSEPREDICATE", none, none, object), 1);
  // A new host knows nothing, and a bounded number of parsed predicates are kept.
  for (let id = 100; id < 400; id++) predicates.evaluate(id, "age > 1", none, none, object);
  assert.equal(predicates.evaluate(2, "FALSEPREDICATE", none, none, object), 0);
});

await test("a MATCHES pattern that backtracks exponentially raises on a long subject instead of freezing the page", () => {
  const started = performance.now();
  assert.equal(run("SELF MATCHES %@", "a".repeat(40) + "!", { args: ["(a+)+"] }), "raise");
  // Short subjects still answer as Foundation does, and patterns without nested quantifiers are not limited.
  assert.equal(run("SELF MATCHES %@", "aaa", { args: ["(a+)+"] }), true);
  assert.equal(run("SELF MATCHES %@", "a".repeat(5000), { args: ["a+"] }), true);
  // A repeated group that ends in a fixed element splits a text one way only: it is matched at any length.
  const csv = Array.from({ length: 200 }, (_, n) => String(n)).join(",");
  assert.equal(run("SELF MATCHES %@", csv, { args: ["^(\\d+,)*\\d+$"] }), true);
  assert.equal(run("SELF MATCHES %@", csv + ",", { args: ["^(\\d+,)*\\d+$"] }), false);
  // Ending in a quantified element is still refused on a long subject, in any alternative.
  assert.equal(run("SELF MATCHES %@", "ab ".repeat(20) + "!", { args: ["(\\w+\\s?)+"] }), "raise");
  assert.equal(run("SELF MATCHES %@", "a".repeat(40) + "!", { args: ["(x|a+)+"] }), "raise");
  // A fixed end that a variable element can also take splits exponentially too: refused.
  assert.equal(run("SELF MATCHES %@", "a".repeat(30) + "c", { args: ["^(a*a)*b$"] }), "raise");
  assert.equal(run("SELF MATCHES %@", "aab".repeat(15) + "!", { args: ["(\\w+b)*"] }), "raise");
  // Delimited repetitions of other shapes are matched at any length.
  assert.equal(run("SELF MATCHES %@", "ab;cd;ef;".repeat(20), { args: ["([a-z]+;)*"] }), true);
  assert.ok(performance.now() - started < 2000);
});

finish();
