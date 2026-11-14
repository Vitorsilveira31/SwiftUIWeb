// !/usr/bin/env bun
// Writes cases.json, the NSPredicate corpus the Objective-C probe (probe.m) evaluates against Foundation.
//
//     bun make-cases.mjs cases.json
//     clang -fobjc-arc -framework Foundation probe.m -o /tmp/nspredicate-probe
//     /tmp/nspredicate-probe cases.json ../../Tests/Fixtures/nspredicate_corpus.json
//
// Tools/test-predicate-engine.mjs replays the corpus (cases plus what Foundation answered) through the JavaScript
// parser and evaluator, and fails on any difference in `predicateFormat`, parse failures or results.
//
// Numbers that Foundation must see as doubles are `Float`s (`2.5`, `4.0`, `1e15`), so `cases.json` and the corpus
// keep the `.0` of a whole double; integers stay plain numbers and the 64-bit extremes are BigInts.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { dumps, Float } from "../format-compat.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const I = (n) => ({ "$i": n });
const F = (n) => ({ "$f": new Float(n) });
const Fi = (n) => ({ "$f": n });
const fl = (n) => new Float(n);
const B = (v) => ({ "$b": v });
const D = (s) => ({ "$d": s });
const NULL = { "$null": 1 };
const NIL = { "$nil": 1 };
const SET = (...items) => ({ "$set": items });

export function buildCases() {
const OBJECTS = {
    "alice": {
        "name": "Alice", "age": 30, "score": F(2.5), "active": B(true), "email": "alice@example.com",
        "tags": ["swift", "web"], "city": "São Paulo", "joined": D(1_600_000_000), "nick": NULL,
        "address": {"city": "Lisbon", "zip": "1000"},
        "friends": [{"name": "Bob", "age": 25}, {"name": "Carol", "age": 35}],
        "nums": [1, 2, 3, 4], "cafe": "café", "ids": SET(1, 2, 3), "ratio": F(0.1),
    },
    "bob": {
        "name": "bob", "age": 25, "score": F(4.0), "active": B(false), "email": "BOB@EXAMPLE.COM",
        "tags": [], "city": "sao paulo", "joined": D(1_700_000_000), "address": {"city": "Porto"},
        "friends": [], "nums": [], "cafe": "cafe", "ids": SET(), "ratio": F(0.2),
    },
    "carol": {
        "name": "Carol", "age": 35, "score": I(3), "active": B(true), "tags": ["swift"], "nick": "CC",
        "friends": [{"name": "Alice", "age": 30}], "nums": [5], "zip": "90210", "cafe": "CAFÉ",
    },
    "text": "Hello, World",
    "empty": "",
    "number": 42,
    "decimal": F(2.5),
    "numbers": [3, 1, 2],
    "words": ["apple", "Banana", "cherry"],
    "nothing": NIL,
};
const EVERYONE = ["alice", "bob", "carol", "nothing"]
const PEOPLE = ["alice", "bob", "carol"]
const STRINGS = ["text", "empty", "nothing"]

const CASES = [];


const case_ = (fmt, objects = PEOPLE, args = null, variables = null) => {
  const entry = { format: fmt, objects };
  if (args !== null) entry.args = args;
  if (variables !== null) entry.vars = variables;
  CASES.push(entry);
};

// Comparison operators and numeric coercion.
for (const fmt of [
    "name == 'Alice'", 'name = "Alice"', "name != 'Alice'", "name <> 'Alice'", "age > 25", "age >= 30",
    "age => 30", "age < 30", "age <= 30", "age =< 30", "age == 30.0", "score == 2.5", "score > 2",
    "score == 3", "score == 3.0", "age == '30'", "active == YES", "active == true", "active == 1",
    "active == NO", "active != 0", "age == nil", "nick == nil", "nick != nil", "missing == nil",
    "missing != 5", "missing < 5", "missing <= nil", "name == name", "age == age", "ratio == 0.1",
    "ratio < 0.15", "age == 0x1E", "age == 3e1", "age == 30e0", "-age == -30", "age == - -30",
    "name == nick", "zip == '90210'", "nick == 'CC'", "name < 'B'", "name > 'B'", "name < 'alice'",
    "name == missing", "age BETWEEN {25, 30}", "age BETWEEN {30, 25}", "age BETWEEN {26, 34}",
    "age BETWEEN {1.5, 30.5}", "name BETWEEN {'A', 'B'}", "age BETWEEN {20}", "score BETWEEN {2, 3}",
    "joined BETWEEN {1550000000, 1650000000}", "age IN {25, 35}", "age IN {30.0}", "name IN {'Alice', 'bob'}",
    "name IN {}", "name IN {'alice'}", "age IN {'30'}", "name IN[c] {'ALICE'}", "tags == {'swift', 'web'}",
    "tags == {'web', 'swift'}", "nums == {1, 2, 3, 4}", "tags == nil", "tags != {}",
]) {
  case_(fmt, EVERYONE);
}

// String operators and their options.
for (const fmt of [
    "name BEGINSWITH 'Al'", "name beginswith 'al'", "name BEGINSWITH[c] 'al'", "name ENDSWITH 'e'",
    "name ENDSWITH[c] 'E'", "name CONTAINS 'li'", "name CONTAINS[c] 'LI'", "name CONTAINS ''",
    "name BEGINSWITH ''", "name ENDSWITH ''", "name ==[c] 'ALICE'", "name !=[c] 'ALICE'",
    "name <[c] 'bob'", "name >[c] 'BOB'", "name ==[cd] 'ALICE'", "name ==[d] 'Alice'",
    "cafe == 'cafe'", "cafe ==[d] 'cafe'", "cafe ==[c] 'CAFÉ'", "cafe ==[cd] 'CAFE'", "cafe ==[cd] 'cafe'",
    "cafe CONTAINS[d] 'afe'", "cafe BEGINSWITH[cd] 'CAF'", "cafe ENDSWITH[d] 'e'", "cafe LIKE[d] 'caf?'",
    "cafe MATCHES[d] 'cafe'", "cafe < 'cafz'", "cafe >[d] 'cafd'", "city CONTAINS[d] 'sao'",
    "city ==[cd] 'sao paulo'", "city BEGINSWITH 'S'", "city BEGINSWITH[cd] 's'", "email ENDSWITH[c] '.COM'",
    "email CONTAINS '@'", "email LIKE '*@example.com'", "email LIKE[c] '*@EXAMPLE.COM'",
    "email MATCHES '[a-z]+@[a-z]+\\\\.com'", "email MATCHES[c] '[a-z]+@[a-z]+\\\\.com'",
    "name ==[l] 'Alice'", "name ==[n] 'Alice'", "name ==[x] 'ALICE'", "name == [c] 'ALICE'",
    "name ==[C] 'ALICE'", "name ==[dc] 'ALICE'", "name ==[cc] 'ALICE'", "age CONTAINS 3", "age BEGINSWITH '3'",
    "name CONTAINS 5", "name == 5",
]) {
  case_(fmt, EVERYONE);
}

// LIKE and MATCHES edge cases.
for (const fmt of [
    "SELF LIKE 'Hello*'", "SELF LIKE '*World'", "SELF LIKE 'H?llo, World'", "SELF LIKE 'H??llo*'",
    "SELF LIKE '*'", "SELF LIKE ''", "SELF LIKE '*o*o*'", "SELF LIKE 'hello*'", "SELF LIKE[c] 'hello*'",
    "SELF LIKE '*,*'", "SELF LIKE 'Hello, World?'", "SELF LIKE '?*'", "SELF LIKE '**'", "SELF LIKE 'H[a-z]llo*'",
    "SELF LIKE 'Hello.*'", "SELF LIKE '\\*'", "SELF LIKE 'Hello\\?'", "SELF LIKE 'Hello, W?rld'",
    "SELF MATCHES 'Hello, World'", "SELF MATCHES 'Hello'", "SELF MATCHES 'Hello.*'", "SELF MATCHES '.*World'",
    "SELF MATCHES '(?i)hello, world'", "SELF MATCHES[c] 'HELLO, WORLD'", "SELF MATCHES '[A-Z][a-z]+, [A-Z][a-z]+'",
    "SELF MATCHES '\\\\w+, \\\\w+'", "SELF MATCHES '^Hello.*$'", "SELF MATCHES 'Hello|Bye'",
    "SELF MATCHES '(Hello|Bye), World'", "SELF MATCHES '.{12}'", "SELF MATCHES '.{3,11}'", "SELF MATCHES '[^a-z]+'",
    "SELF MATCHES '['", "SELF MATCHES '('", "SELF MATCHES '*'", "SELF MATCHES ''", "SELF MATCHES '\\\\d+'",
    "SELF MATCHES 'Hello,\\\\sWorld'", "SELF MATCHES '(?=Hello).*'", "SELF MATCHES 'Hello(?!!).*'",
    "SELF MATCHES '\\\\bHello\\\\b.*'", "SELF MATCHES 'H.llo, W.rld'", "SELF MATCHES 'h.*'",
]) {
  case_(fmt, STRINGS);
}
case_("SELF MATCHES '\\\\d{2}'", ["number", "text", "nothing"]);
case_("SELF == 42", ["number", "decimal", "text", "nothing"]);
case_("SELF > 40", ["number", "decimal", "nothing"]);
case_("SELF IN {42, 43}", ["number", "decimal", "nothing"]);
case_("SELF == 2.5", ["number", "decimal"]);
case_("SELF BETWEEN {1, 10}", ["number", "decimal"]);

// Collections: IN, CONTAINS, ANY / ALL / NONE.
for (const fmt of [
    "'swift' IN tags", "'go' IN tags", "tags CONTAINS 'web'", "tags CONTAINS 'WEB'", "tags CONTAINS[c] 'WEB'",
    "ANY tags == 'swift'", "ANY tags BEGINSWITH 'we'", "ANY tags LIKE 's*'", "ALL tags BEGINSWITH 's'",
    "ALL tags == 'swift'", "NONE tags == 'swift'", "NONE tags == 'go'", "SOME tags == 'web'", "ANY tags == nil",
    "ANY nums > 3", "ALL nums > 0", "ALL nums > 1", "NONE nums > 4", "ANY nums == 2.0", "nums CONTAINS 3",
    "3 IN nums", "5 IN nums", "nums == {1, 2, 3, 4}", "ANY nums IN {4, 5}", "ANY ids == 2", "ids CONTAINS 3",
    "NOT ANY nums > 3", "NOT (ANY nums > 3)", "ANY nums > 3 AND ANY nums < 2", "ALL tags != 'go'",
    "ANY friends.name == 'Bob'", "ALL friends.age > 20", "friends.name CONTAINS 'Carol'", "'Bob' IN friends.name",
    "ANY friends.age BETWEEN {30, 40}", "friends.@count == 2", "friends.@count > 0", "nums.@count == 4",
    "tags.@count == 0", "friends.@sum.age == 60", "friends.@avg.age == 30", "friends.@avg.age > 29.5",
    "friends.@min.age == 25", "friends.@max.age == 35", "friends.@max.name == 'Carol'", "friends.@min.name == 'Bob'",
    "friends.@sum.age > 100", "missing.@count == 0", "address.@count == 2", "address.city == 'Lisbon'",
    "address.city BEGINSWITH 'Li'", "address.zip == nil", "address.country == nil", "address.city.length == 6",
    "name.length == 5", "name.uppercaseString == 'ALICE'", "name.lowercaseString == 'alice'",
    "nick.length == 2", "SELF.name == 'Alice'", "SELF.age > 26", "SELF.address.city == 'Porto'",
    "friends.@unionOfObjects.name == {'Bob', 'Carol'}",
]) {
  case_(fmt, EVERYONE);
}
case_("ANY SELF > 2", ["numbers", "nothing"]);
case_("ALL SELF > 0", ["numbers", "nothing"]);
case_("SELF CONTAINS 2", ["numbers", "words", "nothing"]);
case_("SELF CONTAINS 'apple'", ["words", "numbers"]);
case_("ANY SELF BEGINSWITH 'B'", ["words", "numbers"]);
case_("ANY SELF BEGINSWITH[c] 'b'", ["words"]);
case_("'cherry' IN SELF", ["words", "numbers"]);
case_("SELF.@count == 3", ["numbers", "words"]);
case_("SELF.@max.self == 3", ["numbers"]);

// Compound predicates, precedence and canonical printing.
for (const fmt of [
    "name == 'Alice' AND age == 30", "name == 'Alice' && age == 30", "name == 'Alice' and age == 30",
    "name == 'Alice' OR age == 25", "name == 'Alice' || age == 25", "name == 'Alice' or age == 25",
    "NOT name == 'Alice'", "NOT (name == 'Alice')", "!(name == 'Alice')", "not name == 'Alice'", "! name == 'Alice'",
    "NOT NOT name == 'Alice'", "NOT (NOT name == 'Alice')", "NOT (name == 'Alice' AND age == 30)",
    "NOT (name == 'Alice' OR age == 25)", "NOT (name == 'Alice') AND age > 20", "(NOT name == 'Alice') AND age > 20",
    "name == 'Alice' AND age == 30 OR age == 25", "age == 25 OR name == 'Alice' AND age == 30",
    "(name == 'Alice' OR age == 25) AND age < 31", "(name == 'Alice' AND age == 30) OR (age == 25 AND name == 'bob')",
    "(name == 'Alice' AND age == 30) AND active == YES", "name == 'Alice' AND (age == 30 AND active == YES)",
    "name == 'Alice' OR (age == 25 OR age == 35)", "((name == 'Alice'))", "(((name == 'Alice') AND (age == 30)))",
    "TRUEPREDICATE", "FALSEPREDICATE", "truepredicate", "TRUEPREDICATE AND name == 'Alice'",
    "FALSEPREDICATE OR name == 'Alice'", "NOT TRUEPREDICATE", "NOT FALSEPREDICATE", "name == 'Alice' AND FALSEPREDICATE",
    "TRUEPREDICATE OR garbage == 1", "FALSEPREDICATE AND missing > 3", "name == 'zzz' AND age.foo == 1",
    "age == 30 AND ANY tags == 'swift'", "NOT ANY tags == 'swift' AND age > 20", "ANY tags == 'swift' OR NONE tags == 'x'",
    "age > 20 AND age < 40 AND name != 'bob'", "age < 20 OR age > 40 OR name == 'Carol'",
    "  name   ==   'Alice'  ", "name=='Alice'", "age>=30", "age<>30", "(age>25)AND(age<40)",
]) {
  case_(fmt, EVERYONE);
}

// Arithmetic.
for (const fmt of [
    "age + 1 == 31", "age - 1 == 29", "age * 2 == 60", "age / 2 == 15", "age / 4 == 7", "age / 4.0 == 7.5",
    "age ** 2 == 900", "age + 1 * 2 == 32", "(age + 1) * 2 == 62", "age - 1 - 1 == 28", "score * 2 == 5",
    "score + 1 == 3.5", "score + age == 32.5", "age + score > 32", "age + 0.5 == 30.5", "-age < 0", "age + nick == 30",
    "name + 1 == 1", "age + missing == 30", "(age * 2) BETWEEN {50, 70}", "age / 0 == 0", "10 / 4 == 2",
    "10 / 4.0 == 2.5", "2 ** 10 == 1024", "1 + 2 * 3 == 7", "(1 + 2) * 3 == 9",
]) {
  case_(fmt, EVERYONE);
}

// Literals and string escapes.
for (const fmt of [
    "name == 'Al\\u0069ce'", "name == 'Al\\x69ce'", "name == 'Al\\151ce'", "name == 'Al\\ice'", "name == \"Alice\"",
    "name == 'it\\'s'", "name == \"say \\\"hi\\\"\"", "name == 'a\\\\b'", "name == 'tab\\there'", "name == 'new\\nline'",
    "name == 'é'", "name == '🙂'", "name == ''", "age == 30.", "age == +30", "age == .5", "age == 1e2", "age == 1E+2",
    "age == 1.5e-3", "age == 007", "age == 100000", "age == -0", "age == 3.0e1", "name == NIL", "name == Nil",
    "name == null", "name == NULL", "active == TRUE", "active == yes", "active == False", "{1, 2} == {1, 2}",
    "{1, 2} == {2, 1}", "{} == {}", "1 == 1", "'a' == 'a'", "1 < 2 AND 3 > 2", "nil == nil", "'a' < 'b'",
    "{1, 2} = {1, 2, 3}", "ANY {1, 2} > 1", "ALL {1, 2} > 1", "age IN {30, 'x', 2.5}", "SELF == nil", "SELF != nil",
    "self == nil", "SELF.SELF == nil",
]) {
  case_(fmt, EVERYONE);
}

// Arithmetic over every kind of operand.
const ARITHMETIC = {
    "i3": 3, "i0": 0, "ineg": -2, "d25": F(2.5), "d0": F(0.0), "big": I(9223372036854775807n), "bigd": F(1e300),
    "b": B(true), "s": "abc", "s5": "5", "date": D(1_000_000), "null": NULL, "arr": [1, 2],
}
OBJECTS.arithmetic = ARITHMETIC;
for (const operator of ["+", "-", "*", "/", "**"]) {
  for (const left of [...Object.keys(ARITHMETIC), "missing"]) {
    for (const right of [...Object.keys(ARITHMETIC), "missing"]) {
      case_(`(${left} ${operator} ${right}) > 0`, ["arithmetic"]);
    }
  }
}

// Tokens, keywords, literals, whitespace and the odd spellings of the format language (parse_formats.txt, one
// format per line; `%` conversions are tried with several argument lists).
OBJECTS.spelling = {"name": "x", "order": 1, "android": 2, "note": 3, "in_stock": B(true), "a1": 4, "under_score": 5,
                       "ID": 8, "id": 9, "x": {"y": 1}};
const ARGUMENT_LISTS = [["v"], [I(1)], [F(2.5)], ["v", "w"], [I(1), I(2)], ["a.b", "c"], []];
for (const line of readFileSync(join(HERE, "parse_formats.txt"), "utf8").split("\n")) {
  if (!line.trim()) continue;
  if (line.includes("%")) {
    for (const args of ARGUMENT_LISTS) case_(line, ["spelling"], args);
  } else case_(line, ["spelling"]);
}
case_("order == 1\n AND name == 'x'", ["spelling"]);
case_("order == 1\tAND\tname == 'x'", ["spelling"]);
case_("name\n==\n'x'", ["spelling"]);

// Key paths and operators over every kind of top-level object (self_formats.txt).
const SELF_KINDS = {"dicts":[{"n":1,"s":"a","t":[1,2]},{"n":2,"s":"B","t":[3]},{"n":3}],
"nums":[3,1,2],"dbls":[{"$f":fl(1.5)},{"$f":fl(2.5)}],"strs":["b","A","c"],"empty":[],"nested":[[1,2],[3,4]],"deep":[{"a":{"b":[{"c":1},{"c":2}]}},{"a":{"b":[{"c":3}]}}],
"set":{"$set":[1,2,3]},"dsets":{"$set":[{"n":1},{"n":2}]},"date":{"$d":1000000},"dates":[{"$d":0},{"$d":10}],"str":"Hello","num":42,"dbl":{"$f":fl(4.5)},"null":{"$null":1},"nilobj":{"$nil":1},"dict":{"n":1,"d":{"x":[1,2]}},
"mixed":[1,"a",{"$null":1}],"nulls":[{"$null":1},{"$null":1}]};
for (const [name, value] of Object.entries(SELF_KINDS)) OBJECTS[`kind_${name}`] = value;
const KIND_NAMES = Object.keys(SELF_KINDS).map((name) => `kind_${name}`);
for (const line of readFileSync(join(HERE, "self_formats.txt"), "utf8").split("\n")) {
  if (line.trim()) case_(line, KIND_NAMES);
}
case_("SELF == %@", KIND_NAMES, [D(1_000_000)]);
case_("SELF > %@", KIND_NAMES, [D(5)]);

// Every kind of constant as a format argument and as a substitution variable: how it prints and how it compares.
const CONSTANTS = [ "str", "", "it's", 'q"x', "back\\slash", "new\nline", "tab\t", "ünï", "日本", "🙂",
 {"$i":0},{"$i":-1},{"$i":9223372036854775807n},{"$i":-9223372036854775808n},{"$f":fl(0.0)},{"$f":fl(1.0)},{"$f":fl(0.5)},{"$f":fl(1e15)},{"$f":fl(1e16)},{"$f":fl(1e-5)},{"$f":fl(1e-4)},{"$f":fl(123456789.123456789)},{"$f":fl(1.7976931348623157e308)},{"$f":fl(5e-324)},{"$f":fl(3.141592653589793)},{"$f":fl(0.1)},{"$f":fl(0.30000000000000004)},{"$f":fl(100.0)},{"$f":fl(2.5e10)},
 {"$b":true},{"$b":false},{"$d":0},{"$d":-1},{"$d":1600000000.5},{"$d":-9999999999},{"$d":253402300800},
 {"$null":1},{"$nil":1},
 [],[1],[1,2],["a"],["a","b"],[[1],[2]],[{"$null":1}],[{"$d":0}],[{"$f":fl(1.5)}],[{"$b":true}],[1,"a",{"$f":fl(2.5)}],
 {"$set":[]},{"$set":[1]},{"$set":["a"]},
 {},{"k":1},{"k":"v"},{"k":[1,2]},{"a":{"b":1}}]
OBJECTS.constants = {"x": 5};
for (const constant of CONSTANTS) {
  for (const fmt of ["x == %@", "x IN %@", "x CONTAINS %@", "%@ == x", "x BETWEEN %@", "ANY x == %@", "x LIKE %@", "x < %@"]) {
    case_(fmt, ["constants"], [constant]);
  }
  case_("x == %@ AND y == %@", ["constants"], [constant, constant]);
  for (const fmt of ["x == $V", "x IN $V", "x CONTAINS $V", "x BETWEEN $V", "ANY x == $V", "$V.@count == 1", "$V.length == 3",
    "NOT (x == $V)", "x == $V + 1", "x IN {$V, 1}"]) {
    case_(fmt, ["constants"], null, {"V": constant});
  }
}

// Parse failures (Foundation raises).
for (const fmt of [
    "", "  ", "name", "name ==", "== 1", "name == 'Alice' AND", "name == 'Alice'  name == 'b'", "(name == 'Alice'",
    "name == 'Alice')", "name === 'x'", "name = = 'x'", "age > 1 AND AND age < 5", "name ==[] 'a'", "name == 'unterminated",
    "{1,2}", "age == {1", "age BETWEEN", "age == 1;", "name == `a`", "age == 5.", "age ==", "name LIKE", "NOT",
    "TRUEPREDICATE garbage", "ANY", "age IN", "%", "name == %@", "name == %z", "$ == 1", "name == 1 2",
    "name.@sum.age ==", "FUNCTION(name, 'x') == 1", "SUBQUERY(friends, $f, $f.age > 1).@count == 1",
    "name[0] == 'A'",
]) {
  case_(fmt, PEOPLE);
}

// Format arguments.
case_("name == %@", PEOPLE, ["Alice"]);
case_("name == %@", PEOPLE, ["it's"]);
case_("name == %@", PEOPLE, ['say "hi"']);
case_("name == %@", PEOPLE, ["back\\slash"]);
case_("name == '%@'", PEOPLE, ["Alice"]);
case_("name == %@ AND age == %d", PEOPLE, ["Alice", I(30)]);
case_("age == %d", PEOPLE, [I(30)]);
case_("age == %i", PEOPLE, [I(30)]);
case_("age == %ld", PEOPLE, [I(30)]);
case_("age == %lu", PEOPLE, [I(30)]);
case_("age == %lld", PEOPLE, [I(30)]);
case_("age > %d", PEOPLE, [I(26)]);
case_("score == %f", PEOPLE, [F(2.5)]);
case_("score == %f", PEOPLE, [Fi(3)]);
case_("score > %lf", PEOPLE, [F(2.75)]);
case_("ratio == %g", PEOPLE, [F(0.1)]);
case_("age == %@", PEOPLE, [I(30)]);
case_("score == %@", PEOPLE, [F(2.5)]);
case_("age == %@", PEOPLE, [B(true)]);
case_("%K == %@", PEOPLE, ["name", "Alice"]);
case_("%K == 30", PEOPLE, ["age"]);
case_("%K.length == 5", PEOPLE, ["name"]);
case_("%K CONTAINS %@", PEOPLE, ["email", "@"]);
case_("address.%K == %@", PEOPLE, ["city", "Lisbon"]);
case_("%K == %K", PEOPLE, ["name", "name"]);
case_("name IN %@", PEOPLE, [["Alice", "Carol"]]);
case_("age IN %@", PEOPLE, [[I(25), I(35)]]);
case_("name IN %@", PEOPLE, [[]]);
case_("age BETWEEN %@", PEOPLE, [[I(26), I(34)]]);
case_("name LIKE %@", PEOPLE, ["A*"]);
case_("name MATCHES %@", PEOPLE, ["[A-Z][a-z]+"]);
case_("name CONTAINS[cd] %@", PEOPLE, ["LIC"]);
case_("name BEGINSWITH %@", PEOPLE, ["Al"]);
case_("tags == %@", PEOPLE, [["swift", "web"]]);
case_("joined > %@", PEOPLE, [D(1_650_000_000)]);
case_("joined == %@", PEOPLE, [D(1_600_000_000)]);
case_("joined BETWEEN %@", PEOPLE, [[D(1_550_000_000), D(1_650_000_000)]]);
case_("joined < %@", PEOPLE, [D(0)]);
case_("name == %@", PEOPLE, [NULL]);
case_("name == %@", PEOPLE, [NIL]);
case_("nick == %@", PEOPLE, [NULL]);
case_("name == %@", PEOPLE, ["a", "b"]);
case_("age == %@ + 1", PEOPLE, [I(29)]);
case_("age == %@", PEOPLE, [F(1e-7)]);
case_("age == %@", PEOPLE, [F(1e20)]);
case_("age == %@", PEOPLE, [F(123456789.123456789)]);
case_("age == %@", PEOPLE, [I(-5)]);
case_("name == %@ OR name == %@", PEOPLE, ["Alice", "bob"]);
case_("ANY tags == %@", PEOPLE, ["swift"]);
case_("%K == %d AND %K == %@", PEOPLE, ["age", I(30), "name", "Alice"]);
case_("age == %d", PEOPLE, []);
case_("%K == 1", PEOPLE, [I(5)]);

// Key-value coding on strings, numbers and dates; collection operators over doubles and unions.
OBJECTS.kvc = {
    "title": "alice smith", "count": 42, "ratio": F(2.75), "label": "007", "flag": "Yes", "when": D(1_600_000_000),
    "prices": [F(1.5), F(2.5), I(3)], "boxes": [{"items": [1, 2]}, {"items": [3]}], "names": ["Bob", "alice", "Carol"],
    "empty": [], "pairs": [[1, 2], [3]],
}
for (const fmt of [
    "title.capitalizedString == 'Alice Smith'", "title.uppercaseString == 'ALICE SMITH'", "title.length == 11",
    "label.intValue == 7", "label.doubleValue == 7", "label.integerValue == 7", "flag.boolValue == YES",
    "title.boolValue == NO", "title.description == 'alice smith'", "count.stringValue == '42'", "count.intValue == 42",
    "ratio.intValue == 2", "ratio.doubleValue == 2.75", "ratio.stringValue == '2.75'", "count.boolValue == YES",
    "ratio.description == '2.75'", "when.timeIntervalSince1970 == 1600000000", "when.timeIntervalSinceReferenceDate > 0",
    "when.year == 2020", "count.nonsense == 1", "title.nonsense == 1", "prices.@sum.self == 7",
    "prices.@sum == 7", "boxes.@sum.items.@count == 3", "boxes.@count == 2", "boxes.items.@count == 2",
    "boxes.@unionOfArrays.items == {1, 2, 3}",
    "pairs.@unionOfArrays.self == {1, 2, 3}", "empty.@count == 0", "empty.@sum.x == 0", "empty.@max.x == nil",
    "empty.@avg.x == 0", "names.@min.self == 'Bob'", "names.@max.length == 5", "boxes.@max.items == nil",
    "names.@unionOfObjects.length == {3, 5, 5}", "names.length == {3, 5, 5}", "names.uppercaseString == {'BOB', 'ALICE', 'CAROL'}",
    "names.@count.self == 3", "prices.@avg.self == 7", "names.@sum.length == 13", "names.@avg.length > 4",
    "names.@sum.length > 12.5 AND names.@sum.length < 13.5", "prices.@max.self == 3", "prices.@min.self == 1.5",
]) {
  case_(fmt, ["kvc", "nothing"]);
}

// Variables inside compound predicates, negations, aggregates and key paths.
case_("NOT (age > $MIN OR name == $NAME) AND $A.length > 2", PEOPLE, null, {"MIN": I(26), "NAME": "bob", "A": "abc"});
case_("ANY friends.age > $LIMIT OR (name == $NAME AND age IN {$X, $Y})", PEOPLE, null,
     {"LIMIT": I(30), "NAME": "Alice", "X": I(1), "Y": I(30)});
case_("age + $N * 2 > ($M - 1)", PEOPLE, null, {"N": I(3), "M": I(40)});
case_("$LIST.@count == 3 AND $LIST.@sum.self == 6", PEOPLE, null, {"LIST": [I(1), I(2), I(3)]});
case_("$MISSING.name == 1 OR TRUEPREDICATE", PEOPLE, null, {"OTHER": I(1)});

// Substitution variables.
case_("name == $NAME", PEOPLE, null, {"NAME": "Alice"});
case_("age > $MIN AND age < $MAX", PEOPLE, null, {"MIN": I(26), "MAX": I(40)});
case_("age IN $AGES", PEOPLE, null, {"AGES": [I(25), I(35)]});
case_("name LIKE $PATTERN", PEOPLE, null, {"PATTERN": "*o*"});
case_("name == $NAME", PEOPLE, null, {});
case_("name == $NAME AND age == $AGE", PEOPLE, null, {"NAME": "Alice"});
case_("age BETWEEN $RANGE", PEOPLE, null, {"RANGE": [I(26), I(34)]});
case_("age BETWEEN {$LOW, $HIGH}", PEOPLE, null, {"LOW": I(26), "HIGH": I(34)});
case_("ANY tags == $TAG", PEOPLE, null, {"TAG": "web"});
case_("nick == $NICK", PEOPLE, null, {"NICK": NULL});
case_("$NAME.length == 5", PEOPLE, null, {"NAME": "Alice"});
case_("age == $N + 1", PEOPLE, null, {"N": I(29)});
case_("SELF.name == $NAME", PEOPLE, null, {"NAME": "bob"});
case_("joined > $WHEN", PEOPLE, null, {"WHEN": D(1_650_000_000)});
case_("name == $NAME", PEOPLE, null, {"NAME": "Alice", "UNUSED": I(1)});
case_("$A == $B", PEOPLE, null, {"A": I(1), "B": F(1.0)});
case_("name == $x_1", PEOPLE, null, {"x_1": "Alice"});
case_("name == $NAME", PEOPLE);


// Every operator against every kind of value, directly and under the ANY / ALL / NONE quantifiers.
const MATRIX = {
    "int": 5, "dbl": F(2.5), "bool": B(true), "str": "abc", "date": D(1_000_000), "null": NULL,
    "arr": [1, 2], "set": SET(1, 2), "dict": {"k": 1}, "es": "", "ea": [], "str2": "ABC",
    "arrs": ["abc", "x"], "arrn": [NULL, NULL], "arrm": ["abc", NULL], "acc": "Café", "plain": "cafe",
}
OBJECTS.matrix = MATRIX;
const MATRIX_KEYS = ["int", "dbl", "str", "date", "null", "arr", "set", "dict", "es", "ea", "arrs", "arrm", "acc", "missing"];
for (const prefix of ["", "ANY ", "ALL "]) {
  for (const operator of ["==", "<", "CONTAINS", "IN", "BEGINSWITH", "LIKE", "MATCHES", "BETWEEN"]) {
    if (prefix && ["BEGINSWITH", "MATCHES", "BETWEEN"].includes(operator)) continue;
    for (const left of MATRIX_KEYS) {
      for (const right of MATRIX_KEYS) case_(`${prefix}${left} ${operator} ${right}`, ["matrix", "nothing"]);
    }
  }
}
for (const operator of ["==[c]", "<[c]", "CONTAINS[c]", "IN[c]", "LIKE[cd]", "==[d]", "BEGINSWITH[cd]"]) {
  for (const left of MATRIX_KEYS) {
    for (const right of ["str", "str2", "acc", "plain", "arrs", "null", "int"]) case_(`${left} ${operator} ${right}`, ["matrix", "nothing"]);
  }
}

// Patterns against subjects: LIKE wildcards and escapes, MATCHES (ICU regular expressions), with options.
const SUBJECTS = ["", "a", "abc", "ABC", "café", "CAFÉ", "cafe\u0301", "naïve", "Straße", "a.c", "a*c", "a\\c",
            "line1\nline2", "日本語", "Hello, World", "foo123"]
SUBJECTS.forEach((text, index) => {
  OBJECTS[`subject${index}`] = text;
});
const SUBJECT_NAMES = SUBJECTS.map((_, index) => `subject${index}`);
const LIKE_PATTERNS = ["", "a", "abc", "ABC", "a*", "*c", "*", "**", "a?c", "a??", "???", "?", "a*c", "*b*", "a.c",
                 "a\\*c", "a\\?c", "\\*", "\\\\", "a\\\\c", "[abc]", "a[b]c", "caf?", "caf*", "CAF*", "*é", "?é",
                 "*É", "naïve", "naive", "na?ve", "Stra?e", "Stra*", "日*", "?本*", "*語", "🙂", "🙂*", "hello*",
                 "Hello, *", "*World", "H*o*d", "a\\.c", "\\", "a\\"]
for (const option of ["", "[c]", "[d]", "[cd]"]) {
  for (const pattern of LIKE_PATTERNS) case_(`SELF LIKE${option} %@`, SUBJECT_NAMES, [pattern]);
}
const REGEX_PATTERNS = [
    "", "a", "abc", "ABC", "a.*", ".*c", ".", "..", "...", ".+", "a.c", "a\\.c", "[abc]+", "[a-c]{3}", "[^a-c]+",
    "a|ab", "(a|ab)(c|bcd)?", "(a*)*", "a?", "a+", "a*", "a{2}", "a{1,2}", "a{2,}", "a*?", "a+?", "a*+", "(?>a)",
    "\\w+", "\\W+", "\\s+", "\\S+", "\\d+", "\\D+", "\\bhello\\b.*", "\\Babc", "^abc$", "^abc", "abc$",
    "\\Aabc\\z", "(?i)abc", "(?i)ABC", "(?-i)abc", "(?s)a.c", "(?m)^abc$", "(?x) a b c", "(?i)[a-c]+",
    "(abc)", "(?:abc)", "(?<n>a)\\k<n>", "(a)\\1", "(.)\\1", "a(?=b)b.*", "a(?!b).*", "(?<=a)b", "(?<!a)b",
    "\\p{L}+", "\\P{L}+", "\\p{Lu}+", "\\p{Ll}+", "\\p{N}+", "\\p{Lu}\\p{Ll}+", "[\\p{L}\\d]+", "\\X+",
    "caf.", "caf\\u00e9", "caf[eé]", "\\x61bc", "\\x{61}bc", "\\u0061bc", "\\141bc", "\\Qa.c\\E", "\\Qa.c",
    "\\q", "\\y", "\\t", "\\n", "line1.line2", "line1\\nline2", "line1$\\nline2", "line1\\n^line2", "日.*",
    "日本\\p{L}", "[日-本]+", "\\h", "\\v", "Hello,\\sWorld", "[A-Z][a-z]+, [A-Z][a-z]+", "foo\\d{3}",
    "[", "(", ")", "a)", "*a", "a**", "a{", "a{1", "a{,2}", "a{2,1}", "[b-a]", "\\", "\\k", "\\p", "\\p{Foo}",
    "\\x", "\\u12", "\\1", "(a)\\2", "(?z)", "(?<n>a)(?<n>b)", "a{1,2}{3}", "(?=a)*", "\\b*", "[]", "[^]",
    "(?", "(?i", "[a-\\d]", "x*+", "^*", "$+",
]
for (const option of ["", "[c]", "[d]", "[cd]"]) {
  for (const pattern of REGEX_PATTERNS) case_(`SELF MATCHES${option} %@`, SUBJECT_NAMES, [pattern]);
}
for (const operator of ["==", "!=", "<", "<=", ">", ">=", "CONTAINS", "BEGINSWITH", "ENDSWITH", "IN"]) {
  for (const option of ["", "[c]", "[d]", "[cd]"]) {
    for (const text of ["", "a", "abc", "ABC", "cafe", "café", "CAFÉ", "cafe\u0301", "Straße", "STRASSE", "ñ", "Ñ", "z", "日本"]) case_(`SELF ${operator}${option} %@`, SUBJECT_NAMES, [text]);
  }
}

return { objects: OBJECTS, cases: CASES };
}

/** The text `json.dump(..., indent=1, ensure_ascii=False)` wrote: no trailing newline. */
export const serialize = (corpus) => dumps(corpus, { indent: 1, ensureAscii: false });

if (import.meta.main) {
  const output = process.argv[2];
  if (!output) {
    console.error("usage: make-cases.mjs cases.json");
    process.exit(2);
  }
  const corpus = buildCases();
  writeFileSync(output, serialize(corpus));
  console.log(corpus.cases.length, "cases");
}
