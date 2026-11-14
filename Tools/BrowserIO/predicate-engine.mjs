// NSPredicate's format language for Embedded builds, which have no Foundation: the parser, `predicateFormat`,
// variable substitution and the evaluator. Swift flattens the object under test into bytes (`_PredicateWire` in
// Sources/WebFoundation/PredicateEngine.swift: no reflection in Embedded Swift) and `browser-io.mjs` answers the
// `predicate` operation with `createPredicates()`. The grammar is the one of Apple's Predicate Programming Guide;
// function expressions (`FUNCTION(..)`, `sum:`), `SUBQUERY` and index expressions (`a[0]`) are not parsed.
//
// Values: nil is `undefined`, NSNull `null`, an integer a `bigint` (64-bit, wrapping), a double a `number`, a boolean a
// `boolean`, a string a `string`, a date a `Time`, an array an `Array`, a set a `Bag`, a dictionary a `Map` and a class
// instance an `Obj`. Where Foundation raises an exception this module throws `Raise`.

const decoder = new TextDecoder('utf-8', { fatal: true });

/** What Foundation raises as an `NSException`: a format that does not parse, or a predicate that cannot be evaluated. */
export class Raise extends Error {}
const raise = () => { throw new Raise('NSPredicate'); };

/** A date: seconds since 1970-01-01T00:00:00Z. */
export class Time { constructor(seconds) { this.s = seconds; } }
/** A set; its elements are compared by value. */
export class Bag extends Array {}
/** A class instance: equal only to itself (by identity), readable through its properties. */
export class Obj { constructor(id, props) { this.id = id; this.props = props; } }

// MARK: Wire format (tag byte, then 0 nil, 1 NSNull, 2 i64, 3 f64, 4 string, 5 date, 6 array, 7 set, 8 dictionary,
// 9 class instance (u64 identity, then a dictionary), 10 boolean; counts and lengths are u32, all little endian)

/** A reader of wire values over `bytes`: `value()` reads one, `done()` says whether the buffer is used up. */
function wire(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let at = 0;
  const take = (n) => { if (n > bytes.length - at) raise(); at += n; return at - n; };
  const count = () => view.getUint32(take(4), true);
  const text = () => {
    const n = count(), start = take(n);
    try { return decoder.decode(bytes.subarray(start, start + n)); } catch { return raise(); }
  };
  const value = (depth = 0) => {
    if (depth > 64) raise();
    const tag = bytes[take(1)];
    switch (tag) {
      case 0: return undefined;
      case 1: return null;
      case 2: return view.getBigInt64(take(8), true);
      case 3: return view.getFloat64(take(8), true);
      case 4: return text();
      case 5: return new Time(view.getFloat64(take(8), true));
      case 6: case 7: {
        const items = tag === 6 ? [] : new Bag();
        for (let n = count(); n > 0; n--) items.push(value(depth + 1));
        return items;
      }
      case 8: case 9: {
        const id = tag === 9 ? view.getBigUint64(take(8), true) : 0n, props = new Map();
        for (let n = count(); n > 0; n--) { const key = text(); props.set(key, value(depth + 1)); }
        return tag === 8 ? props : new Obj(id, props);
      }
      case 10: return bytes[take(1)] !== 0;
      default: return raise();
    }
  };
  return { value, done: () => at === bytes.length };
}

/** The values of an argument list, one after another until the bytes end. */
export function decodeList(bytes) {
  const reader = wire(bytes), values = [];
  while (!reader.done()) values.push(reader.value());
  return values;
}

/** One value that fills `bytes` exactly. */
export function decode(bytes) {
  const reader = wire(bytes), value = reader.value();
  return reader.done() ? value : raise();
}

// MARK: Printing (`predicateFormat`)

const EPOCH_OFFSET = 978_307_200; // seconds from 1970 to the reference date, 2001-01-01

/** C's `%.16g`, which is how `-[NSNumber description]` prints a double. */
function printDouble(x) {
  if (!Number.isFinite(x)) return Number.isNaN(x) ? 'nan' : x < 0 ? '-inf' : 'inf';
  if (x === 0) return Object.is(x, -0) ? '-0' : '0';
  const [mantissa, power] = x.toExponential(15).split('e'), exponent = Number(power);
  const digits = mantissa.replace(/[-.]/g, '').replace(/0+$/, '') || '0';
  let text;
  if (exponent < -4 || exponent >= 16) {
    text = `${digits[0]}${digits.length > 1 ? `.${digits.slice(1)}` : ''}e${exponent < 0 ? '-' : '+'}${String(Math.abs(exponent)).padStart(2, '0')}`;
  } else if (exponent < 0) {
    text = `0.${'0'.repeat(-exponent - 1)}${digits}`;
  } else {
    text = digits.length <= exponent + 1 ? digits.padEnd(exponent + 1, '0') : `${digits.slice(0, exponent + 1)}.${digits.slice(exponent + 1)}`;
  }
  return mantissa[0] === '-' ? `-${text}` : text;
}

/** `NSDate.description`: `1970-01-01 00:00:00 +0000`. */
// A date past JavaScript's range (\u00b18.64e12 s) has no ISO form, and toISOString would throw: it prints as its number.
const printDate = (seconds) => {
  const date = new Date(Math.floor(seconds) * 1000);
  return Number.isNaN(date.getTime()) ? `${seconds}` : `${date.toISOString().slice(0, 19).replace('T', ' ')} +0000`;
};

const quote = (text) => `"${text.replace(/[\\"]/g, '\\$&')}"`;
const printElement = (v) => (v instanceof Time ? printDate(v.s) : printValue(v));

/** How a constant prints in a predicate. */
function printValue(v) {
  if (v === undefined) return 'nil';
  if (v === null) return '<null>';
  if (typeof v === 'bigint') return String(v);
  if (typeof v === 'boolean') return v ? '1' : '0';
  if (typeof v === 'number') return printDouble(v);
  if (typeof v === 'string') return quote(v);
  if (v instanceof Time) return `CAST(${(v.s - EPOCH_OFFSET).toFixed(6)}, "NSDate")`;
  if (Array.isArray(v)) return `{${v.map(printElement).join(', ')}}`;
  const entries = [...(v instanceof Obj ? v.props : v)].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  return `{${entries.map(([key, item]) => `${quote(key)} = ${printElement(item)}`).join(', ')}}`;
}

const printExpr = (e) => {
  switch (e.t) {
    case 'const': return printValue(e.v);
    case 'self': return 'SELF';
    case 'var': return `$${e.name}`;
    case 'path': return e.c.join('.');
    case 'apply': return `${printExpr(e.base)}.${e.c.join('.')}`;
    case 'agg': return `{${e.items.map(printExpr).join(', ')}}`;
    default: { const side = (x) => (x.t === 'bin' ? `(${printExpr(x)})` : printExpr(x)); return `${side(e.l)} ${e.op} ${side(e.r)}`; }
  }
};

const CASE = 1, DIACRITIC = 2, NORMALIZED = 4, LOCALE = 8;

function printPred(p) {
  switch (p.t) {
    case 'bool': return p.v ? 'TRUEPREDICATE' : 'FALSEPREDICATE';
    case 'not': return p.p.items ? `NOT (${printPred(p.p)})` : `NOT ${printPred(p.p)}`;
    case 'and': case 'or': {
      const other = p.t === 'and' ? 'or' : 'and';
      return p.items.map((item) => (item.t === 'not' || item.t === other ? `(${printPred(item)})` : printPred(item))).join(p.t === 'and' ? ' AND ' : ' OR ');
    }
    default: {
      const letters = [[CASE, 'c'], [DIACRITIC, 'd'], [LOCALE, 'l'], [NORMALIZED, 'n']].filter(([bit]) => p.o & bit).map(([, letter]) => letter).join('');
      return `${p.q === 'any' ? 'ANY ' : p.q === 'all' ? 'ALL ' : ''}${printExpr(p.l)} ${p.op}${letters && `[${letters}]`} ${printExpr(p.r)}`;
    }
  }
}

// MARK: Parsing

const SYMBOLS = ['==', '!=', '<>', '<=', '=<', '>=', '=>', '&&', '||', '**', '=', '<', '>', '!', '(', ')', '{', '}', ',', '.', '[', ']', '+', '-', '*', '/'];
const SYMBOL_OPERATORS = { '==': '==', '=': '==', '!=': '!=', '<>': '!=', '<': '<', '<=': '<=', '=<': '<=', '>': '>', '>=': '>=', '=>': '>=' };
const WORD_OPERATORS = new Set(['BEGINSWITH', 'ENDSWITH', 'CONTAINS', 'LIKE', 'MATCHES', 'IN', 'BETWEEN']);
const RESERVED = new Set(['AND', 'OR', 'NOT', 'IN', 'BETWEEN', 'BEGINSWITH', 'ENDSWITH', 'CONTAINS', 'LIKE', 'MATCHES', 'ANY', 'ALL', 'NONE', 'SOME', 'TRUEPREDICATE', 'FALSEPREDICATE']);
const WHITESPACE = /[\t-\r \u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]/;
const NUMBER = /0[xX]([0-9a-fA-F]*)|\d*(\.\d+)?([eE][+-]?\d+)?/y;
const WORD = /(?:@[A-Za-z]|[A-Za-z_])[A-Za-z0-9_]*/y;
const VARIABLE = /\$([A-Za-z_][A-Za-z0-9_]*)/y;
const CONVERSION = /%(?:(%)| ?[hlqL]*([@dDiuUxXoOfFgGeEaAcCsSpK]))/y;
const ESCAPES = { n: '\n', t: '\t', r: '\r', b: '\b', f: '\f', a: '\x07', v: '\x0b' };
const fitsInt64 = (n) => BigInt.asIntN(64, n) === n;

/** The tokens of `format`, with each `%` conversion replaced by its argument. */
function tokenize(format, args) {
  const tokens = [];
  let i = 0, used = 0, m;
  const argument = () => (used < args.length ? args[used++] : raise());
  const sticky = (re) => { re.lastIndex = i; m = re.exec(format); if (m) i = re.lastIndex; return m; };
  /** `count` hex digits as a character, consumed even when they spell no character; nothing is consumed when fewer follow. */
  const hex = (count, fallback) => {
    const digits = format.slice(i, i + count);
    if (digits.length < count || !/^[0-9a-fA-F]+$/.test(digits)) return fallback;
    i += count;
    const code = parseInt(digits, 16);
    return code >= 0xd800 && code <= 0xdfff ? fallback : String.fromCodePoint(code);
  };
  const literal = () => {
    const delimiter = format[i++];
    let text = '';
    for (;;) {
      const c = format[i++];
      if (c === undefined) raise();
      if (c === delimiter) return text;
      if (c !== '\\') { text += c; continue; }
      const e = format[i++];
      if (e === undefined) raise();
      if (e === 'x') text += hex(2, 'x');
      else if (e === 'u') text += hex(4, 'u');
      else if (e >= '0' && e <= '7') {
        // An octal escape is one byte; a larger value is dropped.
        let value = Number(e);
        for (let k = 0; k < 2 && format[i] >= '0' && format[i] <= '7'; k++) value = value * 8 + Number(format[i++]);
        if (value <= 0xff) text += String.fromCharCode(value);
      } else text += ESCAPES[e] ?? e;
    }
  };
  const number = () => {
    sticky(NUMBER);
    if (m[1] !== undefined) { const n = BigInt(`0x${m[1] || raise()}`); return fitsInt64(n) ? n : raise(); }
    if (!m[2] && !m[3]) { const n = BigInt(m[0]); if (fitsInt64(n)) return n; } // too big for 64 bits: a double
    return Number(m[0]);
  };
  while (i < format.length) {
    const c = format[i];
    if (WHITESPACE.test(c)) i++;
    else if (c === '"' || c === "'") tokens.push({ k: 't', v: literal() });
    else if (/\d/.test(c) || (c === '.' && /\d/.test(format[i + 1] ?? ''))) tokens.push({ k: 'n', v: number() });
    else if (c === '$') tokens.push({ k: 'v', v: (sticky(VARIABLE) ?? raise())[1] });
    else if (c === '%') {
      if (!sticky(CONVERSION)) raise();
      if (m[1]) tokens.push({ k: 'a', v: args.length ? '%' : raise() });
      else if (m[2] === 'K') { const path = argument(); tokens.push({ k: 'K', v: typeof path === 'string' ? path : raise() }); }
      else tokens.push({ k: 'a', v: argument() });
    } else if (/[@A-Za-z_]/.test(c) && sticky(WORD)) tokens.push({ k: 'w', v: m[0] });
    else {
      const symbol = SYMBOLS.find((s) => format.startsWith(s, i)) ?? raise();
      i += symbol.length;
      tokens.push({ k: 's', v: symbol });
    }
  }
  return tokens;
}

const join = (t, a, b) => ({ t, items: [...(a.t === t ? a.items : [a]), ...(b.t === t ? b.items : [b])] });
/** `NOT p`; a double negation cancels like in Foundation's parser. */
const negate = (p) => (p.t === 'not' ? p.p : { t: 'not', p });
const constant = (v) => ({ t: 'const', v });
/** A component spelled `self` in any case is `SELF`. */
const spellSelf = (c) => c.map((k) => (k.toUpperCase() === 'SELF' ? 'SELF' : k));
/** A key path expression: `SELF` alone is the object, and a leading `SELF` before another component is dropped. */
function path(components) {
  const c = spellSelf(components);
  if (c.length === 1 && c[0] === 'SELF') return { t: 'self' };
  return { t: 'path', c: c.length > 1 && c[0] === 'SELF' && c[1] !== 'SELF' ? c.slice(1) : c };
}

/** Parses `format`, replacing its `%` conversions with `args`. Throws `Raise` when Foundation would. */
export function parse(format, args = []) {
  const T = tokenize(format, args);
  let p = 0;
  const sym = (s) => T[p]?.k === 's' && T[p].v === s;
  const kw = (k) => T[p]?.k === 'w' && T[p].v.toUpperCase() === k;
  const eatSym = (s) => sym(s) && (p++, true);
  const eatKw = (k) => kw(k) && (p++, true);
  const expectSym = (s) => eatSym(s) || raise();

  const predicate = () => {
    let left = conjunction();
    while (eatKw('OR') || eatSym('||')) left = join('or', left, conjunction());
    return left;
  };
  const conjunction = () => {
    let left = negation();
    while (eatKw('AND') || eatSym('&&')) left = join('and', left, negation());
    return left;
  };
  const negation = () => (eatKw('NOT') || eatSym('!') ? negate(negation()) : primaryPredicate());
  const primaryPredicate = () => {
    if (eatKw('TRUEPREDICATE')) return { t: 'bool', v: true };
    if (eatKw('FALSEPREDICATE')) return { t: 'bool', v: false };
    if (sym('(')) {
      // A parenthesis opens a group of predicates, or an expression (`(a + 1) * 2 > 3`).
      const saved = p++;
      try { const inner = predicate(); if (eatSym(')')) return inner; } catch (error) { if (!(error instanceof Raise)) throw error; }
      p = saved;
    }
    const q = eatKw('ANY') || eatKw('SOME') ? 'any' : eatKw('ALL') ? 'all' : eatKw('NONE') ? 'none' : 'direct';
    const left = expression(), op = operator(), o = options();
    if (op === 'BETWEEN' && o) raise();
    const compared = { t: 'cmp', q: q === 'none' ? 'any' : q, l: left, op, o, r: expression() };
    return q === 'none' ? negate(compared) : compared;
  };
  const operator = () => {
    const t = T[p++], op = t?.k === 's' ? SYMBOL_OPERATORS[t.v] : t?.k === 'w' && WORD_OPERATORS.has(t.v.toUpperCase()) ? t.v.toUpperCase() : undefined;
    return op ?? raise();
  };
  /** `[cd]` after an operator; unknown letters are ignored, an empty list is an error. */
  const options = () => {
    if (!eatSym('[')) return 0;
    const letters = T[p++];
    if (letters?.k !== 'w') raise();
    expectSym(']');
    return [...letters.v.toLowerCase()].reduce((bits, letter) => bits | ({ c: CASE, d: DIACRITIC, n: NORMALIZED, l: LOCALE }[letter] ?? 0), 0);
  };

  const chain = (next, ops) => {
    let e = next();
    for (let op; (op = ops.find(eatSym)); ) e = { t: 'bin', op, l: e, r: next() };
    return e;
  };
  const expression = () => chain(term, ['+', '-']);
  const term = () => chain(power, ['*', '/']);
  const power = () => chain(unary, ['**']);
  const unary = () => {
    if (!eatSym('-')) return atom();
    const e = unary();
    if (e.t === 'const' && typeof e.v === 'bigint') return constant(BigInt.asIntN(64, -e.v));
    if (e.t === 'const' && typeof e.v === 'number') return constant(-e.v);
    return { t: 'bin', op: '-', l: constant(0n), r: e };
  };
  /** The `.name` components that follow a key path or a variable. Operator words are not allowed there, and the literal
   * spellings print as Foundation prints them (`x.null` is `x.nil`, `x.YES` is `x.1`). */
  const components = (list) => {
    while (eatSym('.')) {
      const t = T[p++];
      if (t?.k === 'w') {
        const word = t.v.toUpperCase();
        if (RESERVED.has(word)) raise();
        list.push(word === 'NIL' || word === 'NULL' ? 'nil' : word === 'TRUE' || word === 'YES' ? '1' : word === 'FALSE' || word === 'NO' ? '0' : t.v);
      } else if (t?.k === 'K') list.push(...t.v.split('.'));
      else raise();
    }
    if (sym('[') || sym('(')) raise();
    return list;
  };
  /** An operand, with the key path that may follow a parenthesis, aggregate or literal (`(a).b`, `'x'.length`). */
  const atom = () => {
    let e = primary();
    while (sym('.') && T[p + 1]?.k === 'w') {
      const more = components([]);
      if (e.t === 'path' || e.t === 'apply') e = e.t === 'path' ? { t: 'path', c: [...e.c, ...more] } : { ...e, c: [...e.c, ...more] };
      else e = e.t === 'self' ? path(['SELF', ...more]) : { t: 'apply', base: e, c: more };
    }
    return e;
  };
  const primary = () => {
    const t = T[p++];
    switch (t?.k) {
      case 'n': case 'a': return constant(t.v);
      case 't': return constant(t.v);
      case 'v': {
        const rest = spellSelf(components([]));
        return rest.length ? { t: 'apply', base: { t: 'var', name: t.v }, c: rest } : { t: 'var', name: t.v };
      }
      case 'K': return path(components(t.v.split('.')));
      case 's':
        if (t.v === '(') { const inner = expression(); expectSym(')'); return inner; }
        if (t.v === '{') {
          const items = [];
          if (!eatSym('}')) do items.push(expression()); while (!eatSym('}') && expectSym(','));
          return { t: 'agg', items };
        }
        return raise();
      case 'w': return word(t.v);
      default: return raise();
    }
  };
  const word = (text) => {
    const upper = text.toUpperCase();
    if (upper === 'NIL' || upper === 'NULL') return constant(undefined);
    if (upper === 'TRUE' || upper === 'YES') return constant(true);
    if (upper === 'FALSE' || upper === 'NO') return constant(false);
    if (RESERVED.has(upper) || upper === 'SUBQUERY' || upper === 'FUNCTION') raise();
    return path(components([upper === 'SELF' ? 'SELF' : text]));
  };

  const root = predicate();
  return p === T.length ? root : raise();
}

// MARK: Substitution and key names

/** `$NAME` replaced by its binding (a `Map`); unbound names stay, and an NSNull binding is nil. */
function bind(node, b) {
  const lookup = (name) => (b.has(name) ? constant(b.get(name) ?? undefined) : null);
  switch (node.t) {
    case 'var': return lookup(node.name) ?? node;
    case 'apply': {
      const base = node.base.t === 'var' ? lookup(node.base.name) : bind(node.base, b);
      return base ? { ...node, base } : node;
    }
    case 'agg': return { ...node, items: node.items.map((item) => bind(item, b)) };
    case 'bin': return { ...node, l: bind(node.l, b), r: bind(node.r, b) };
    case 'not': return { ...node, p: bind(node.p, b) };
    case 'and': case 'or': return { ...node, items: node.items.map((item) => bind(item, b)) };
    case 'cmp': return { ...node, l: bind(node.l, b), r: bind(node.r, b) };
    default: return node;
  }
}

/** The key names a class instance must be asked for, and the longest key path (in keys, operators excluded). */
function keysOf(root) {
  const names = [];
  let depth = 0;
  const visit = (n) => {
    switch (n.t) {
      case 'path': {
        const keys = n.c.filter((k) => !k.startsWith('@'));
        for (const key of keys) if (!names.includes(key)) names.push(key);
        depth = Math.max(depth, keys.length);
        break;
      }
      case 'agg': case 'and': case 'or': n.items.forEach(visit); break;
      case 'bin': case 'cmp': visit(n.l); visit(n.r); break;
      case 'apply': visit(n.base); break;
      case 'not': visit(n.p); break;
    }
  };
  visit(root);
  return { names, depth };
}

// MARK: Numbers

const isInt = (v) => typeof v === 'bigint' || typeof v === 'boolean'; // booleans are numbers to comparisons
const isNum = (v) => isInt(v) || typeof v === 'number';
const num = (v) => (isNum(v) ? Number(v) : undefined);
const wrap = (n) => BigInt.asIntN(64, n);
/** A double truncated to an integer, saturating like a C cast. */
const toInt = (x) => (Number.isNaN(x) ? 0n : x >= 2 ** 63 ? 2n ** 63n - 1n : x <= -(2 ** 63) ? -(2n ** 63n) : BigInt(Math.trunc(x)));
const parseDouble = (text) => {
  const s = text.trim();
  if (/^[+-]?(inf(inity)?|nan)$/i.test(s)) return /nan/i.test(s) ? NaN : s[0] === '-' ? -Infinity : Infinity;
  return /^[+-]?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?$/i.test(s) ? Number(s) : 0;
};
const parseInteger = (text) => { const s = text.trim(); return /^[+-]?\d+$/.test(s) && fitsInt64(BigInt(s)) ? BigInt(s) : 0n; };
/** C's `pow`, which differs from `Math.pow` where the base is 1 or -1. */
const pow = (base, exponent) => (base === 1 || (base === -1 && !Number.isFinite(exponent) && !Number.isNaN(exponent)) ? 1 : Math.pow(base, exponent));

function arithmetic(op, a, b) {
  if (op === '**') {
    const base = num(a) ?? raise();
    return pow(base, b === undefined || b === null ? 0 : typeof b === 'string' ? parseDouble(b) : num(b) ?? raise());
  }
  // Dates move by a number of seconds, and two dates subtract to the seconds between them.
  if (a instanceof Time && isNum(b) && (op === '+' || op === '-')) return new Time(op === '+' ? a.s + Number(b) : a.s - Number(b));
  if (op === '+' && isNum(a) && b instanceof Time) return new Time(b.s + Number(a));
  if (op === '-' && a instanceof Time && b instanceof Time) return a.s - b.s;
  if (typeof a === 'boolean' || typeof b === 'boolean') raise();
  if (typeof a === 'bigint' && typeof b === 'bigint') {
    // Foundation computes with machine integers: overflow wraps, division by zero is zero.
    if (op === '/') return b === 0n ? 0n : wrap(a / b);
    return wrap(op === '+' ? a + b : op === '-' ? a - b : a * b);
  }
  const x = num(a) ?? raise(), y = num(b) ?? raise();
  return op === '+' ? x + y : op === '-' ? x - y : op === '*' ? x * y : x / y;
}

// MARK: Key-value coding

const UNREADABLE = new Set(['SELF', '0', '1']); // as keys, `SELF` and the numbers `true` and `false` spell raise

/** `valueForKeyPath:` over a flattened object. */
function walk(value, c) {
  if (!c.length || value === undefined) return value;
  const [first, ...rest] = c;
  // An NSNull ends the path with nil, unless the path asks for `SELF`.
  if (value === null) return c.some((k) => UNREADABLE.has(k)) ? raise() : undefined;
  if (first.startsWith('@')) {
    if (rest.some((k) => UNREADABLE.has(k))) raise();
    return collectionOperator(value, first.slice(1), rest);
  }
  if (UNREADABLE.has(first)) raise();
  return walk(valueForKey(value, first), rest);
}

const capitalized = (text) => {
  let atStart = true, out = '';
  for (const ch of text) {
    out += atStart ? ch.toUpperCase() : ch.toLowerCase();
    atStart = !/[\p{Alphabetic}\p{N}]/u.test(ch);
  }
  return out;
};

function stringProperty(text, key) {
  switch (key) {
    case 'length': return BigInt(text.length);
    case 'uppercaseString': return text.toUpperCase();
    case 'lowercaseString': return text.toLowerCase();
    case 'capitalizedString': return capitalized(text);
    case 'description': return text;
    case 'doubleValue': case 'floatValue': return parseDouble(text);
    case 'intValue': case 'integerValue': return parseInteger(text);
    case 'boolValue': return /^[YyTt1-9]/.test(text.trimStart()) ? 1n : 0n;
    default: return raise();
  }
}

function numberProperty(v, key) {
  const double = Number(v);
  switch (key) {
    case 'intValue': case 'integerValue': case 'longValue': case 'longLongValue': return typeof v === 'number' ? toInt(v) : BigInt(v);
    case 'doubleValue': case 'floatValue': return double;
    case 'boolValue': return BigInt(double !== 0);
    case 'stringValue': case 'description': return printValue(v);
    default: return raise();
  }
}

function valueForKey(value, key) {
  if (value === undefined || value === null) return undefined; // messaging nil answers nil
  if (value instanceof Map) return value.get(key);
  if (value instanceof Obj) return value.props.get(key);
  if (Array.isArray(value)) {
    const out = value instanceof Bag ? new Bag() : [];
    for (const item of value) {
      const found = valueForKey(item, key);
      // An array keeps a placeholder for a missing value; a set cannot hold one.
      if (found !== undefined) out.push(found);
      else if (!(value instanceof Bag)) out.push(null);
    }
    return out;
  }
  if (typeof value === 'string') return stringProperty(value, key);
  if (isNum(value)) return numberProperty(value, key);
  if (value instanceof Time) {
    return key === 'timeIntervalSince1970' ? value.s : key === 'timeIntervalSinceReferenceDate' ? value.s - EPOCH_OFFSET : key === 'description' ? printDate(value.s) : raise();
  }
  return raise();
}

/** `@count`, `@sum`, `@avg`, `@min`, `@max` and the union operators. */
function collectionOperator(value, operator, rest) {
  if (operator === 'count') {
    return Array.isArray(value) ? BigInt(value.length) : value instanceof Map ? BigInt(value.size) : value instanceof Obj ? BigInt(value.props.size) : raise();
  }
  if (!Array.isArray(value) || !rest.length) raise();
  // Asking an NSNull element for a key raises.
  const collected = value.map((element) => (element === null ? raise() : walk(element, rest)));
  switch (operator) {
    case 'sum': case 'avg': {
      let exact = true, whole = 0n, total = 0;
      for (const item of collected) {
        if (typeof item === 'bigint') {
          if (fitsInt64(whole + item)) whole += item; else exact = false;
          total += Number(item);
        } else if (typeof item === 'number') { exact = false; total += item; }
        else if (item !== undefined && item !== null) raise();
      }
      if (operator === 'sum') return exact ? whole : total;
      return collected.length ? total / collected.length : undefined;
    }
    case 'min': case 'max': {
      let best;
      for (const item of collected) {
        if (item === undefined || item === null) continue;
        if (best === undefined || (operator === 'min' ? order(item, best, 0) < 0 : order(item, best, 0) > 0)) best = item;
      }
      return best;
    }
    case 'unionOfObjects': case 'distinctUnionOfObjects': return unique(collected, operator.startsWith('distinct'));
    case 'unionOfArrays': case 'distinctUnionOfArrays': case 'distinctUnionOfSets':
      return unique(collected.flatMap((item) => (Array.isArray(item) ? [...item] : raise())), operator.startsWith('distinct'));
    default: return raise();
  }
}

// A coarse key that equal values always share (equal(a, b) implies identityKey(a) === identityKey(b)): `unique` compares
// an item only with the earlier items that share its key, which gives the same result as comparing with all of them.
function identityKey(v) {
  if (isNum(v)) return 'N' + String(Number(v));
  if (typeof v === 'string') return 'S' + v;
  if (v instanceof Time) return 'T' + String(v.s);
  if (v instanceof Obj) return 'O' + String(v.id);
  if (v instanceof Bag) return 'B' + v.length;
  if (Array.isArray(v)) return 'A' + v.length;
  if (v instanceof Map) return 'M' + v.size;
  return 'X' + typeof v;
}
// The items indexed by identity key, so whether a value is equal to one of them compares it with its bucket only. `itemFirst`
// keeps the argument order of the scan it replaces (Bag equality is not symmetric).
function membership(items, itemFirst) {
  const buckets = new Map();
  for (const item of items) {
    const key = identityKey(item), bucket = buckets.get(key);
    if (bucket) bucket.push(item); else buckets.set(key, [item]);
  }
  return value => (buckets.get(identityKey(value)) ?? []).some((item) => (itemFirst ? equal(item, value) : equal(value, item)));
}
const unique = (items, distinct) => {
  if (!distinct) return items;
  const buckets = new Map(), out = [];
  for (const item of items) {
    const key = identityKey(item);
    const earlier = buckets.get(key);
    if (earlier) { if (!earlier.some((seen) => equal(seen, item))) out.push(item); earlier.push(item); }
    else { buckets.set(key, [item]); out.push(item); }
  }
  return out;
};

// MARK: Strings

const MARK = /[\u0300-\u036F\u1AB0-\u1AFF\u1DC0-\u1DFF\u20D0-\u20FF\uFE20-\uFE2F]/;
const MARKS = new RegExp(MARK.source, 'g');

/** `text` with the `[c]` and `[d]` options applied, as the string operators compare it. */
const fold = (text, o) => {
  if (o & CASE) text = text.toLowerCase().replace(/[\u00DF\u1E9E\u03C2]/g, (c) => (c === '\u03C2' ? '\u03C3' : 'ss'));
  return o & DIACRITIC ? text.normalize('NFD').replace(MARKS, '') : text;
};
/** `text` as substring searches see it: folded, then canonically decomposed. */
const canonical = (text, o) => fold(text, o).normalize('NFD');

/** Whether `part` occurs in `text` (both decomposed): at the start (`anchor` 1), at the end (2) or anywhere (0), never
 * with a combining mark of the same letter following it (`é` does not contain `e`). */
function search(text, part, anchor) {
  for (let at = text.indexOf(part); at >= 0; at = text.indexOf(part, at + 1)) {
    const end = at + part.length;
    if (!(end < text.length && MARK.test(text[end])) && (anchor === 0 || (anchor === 1 ? at === 0 : end === text.length))) return true;
  }
  return false;
}

/** `LIKE`: `*` matches any run of characters, `?` one character, a backslash makes the next one literal. */
function like(text, pattern) {
  const glob = [], chars = [...pattern];
  for (let k = 0; k < chars.length; k++) {
    if (chars[k] === '\\') glob.push({ c: chars[++k] ?? raise() });
    else glob.push(chars[k] === '*' ? { run: true } : chars[k] === '?' ? { one: true } : { c: chars[k] });
  }
  let t = 0, g = 0, star = -1, resume = 0;
  while (t < text.length) {
    const token = glob[g];
    if (token?.run) { star = g++; resume = t; }
    else if (token?.one || (token && token.c === text[t])) { g++; t++; }
    else if (star >= 0) { g = star + 1; t = ++resume; }
    else return false;
  }
  return glob.slice(g).every((token) => token.run);
}

// MARK: Regular expressions
// `MATCHES` hands its pattern to ICU, whole-string, with dot matching line terminators and `^`/`$` matching at every line
// boundary. `icu` rewrites a pattern into the JavaScript `v`-mode source that means the same, where the dialects differ.

const WORD_CHARS = '[\\p{Alphabetic}\\p{M}\\p{Nd}\\p{Pc}\\u200c\\u200d]';
const SPACE_CHARS = '\\t\\n\\f\\r\\p{Z}';
const VERTICAL = '\\n\\x0b\\f\\r\\x85\\u2028\\u2029';
const SHORTHANDS = {
  d: '\\p{Nd}', D: '\\P{Nd}', w: WORD_CHARS, W: `[^${WORD_CHARS.slice(1)}`, s: `[${SPACE_CHARS}]`, S: `[^${SPACE_CHARS}]`,
  h: '[\\t\\p{Zs}]', H: '[^\\t\\p{Zs}]', v: `[${VERTICAL}]`, V: `[^${VERTICAL}]`,
};
// Word boundaries, which ICU cannot repeat, spelled with the same word characters as `\w`.
const ASSERTIONS = {
  b: `(?:(?<=${WORD_CHARS})(?!${WORD_CHARS})|(?<!${WORD_CHARS})(?=${WORD_CHARS}))`,
  B: `(?:(?<=${WORD_CHARS})(?=${WORD_CHARS})|(?<!${WORD_CHARS})(?!${WORD_CHARS}))`,
};
// Zero-width anchors that ICU lets a quantifier repeat, and `\X`, a character with its combining marks.
const ANCHORS = {
  A: '(?<![^])', G: '(?<![^])', z: '(?![^])', Z: `(?=(?:\\r\\n|[${VERTICAL}])?(?![^]))`, X: '(?:\\r\\n|[^]\\p{M}*)',
};
const FLAGS = /([a-zA-Z]*)(?:-([a-zA-Z]*))?[:)]/y;
const QUANTIFIER = /([*+?]|\{(\d+)(,(\d*))?\})([?+])?/y;

function icu(source) {
  // `quantifiers` counts the quantifiers read so far, and `nested` records a quantified group that holds a quantifier
  // and may split one text in exponentially many ways (`(a+)+`, `(a*a)*`), which JavaScript's engine tries one by one.
  // A body is known to split one way only when it ends in a literal character that none of its variable elements can
  // match (`(\d+,)*`: `\d+` never takes the ","), so each repetition ends at the next such character.
  // `lastBodyAmbiguous` is whether the group body just read is not known to split one way, in any alternative.
  let i = 0, groups = 0, helpers = 0, lastCode = -1, boundary = false, quantifiers = 0, lastBodyAmbiguous = false;
  /** Whether one alternative of a group body may split a text in more than one way (see `nested`). */
  const ambiguous = (elements) => {
    const variable = elements.filter((element) => element.variable);
    if (variable.length === 0) return false;
    const last = elements[elements.length - 1];
    if (last.variable || last.literal === null) return true;
    for (const element of variable) {
      try { if (new RegExp(`^(?:${element.atom})$`, 'v').test(last.literal)) return true; } catch { return true; }
    }
    return false;
  };
  icu.nested = false;
  const names = new Map();
  const fail = () => { throw new Raise('regex'); };
  const char = () => { const c = String.fromCodePoint(source.codePointAt(i) ?? fail()); i += c.length; return c; };
  const read = (re) => { re.lastIndex = i; const m = re.exec(source) ?? fail(); i = re.lastIndex; return m; };
  /** One character as a source that is safe inside and outside a class. */
  const chr = (code) => {
    if (code > 0x10ffff) fail();
    lastCode = code;
    const c = String.fromCodePoint(code);
    return /[\p{L}\p{N} ]/u.test(c) ? c : `\\u{${code.toString(16)}}`;
  };
  /** A source that is a set of characters or an assertion, not one character. */
  const set = (text) => { lastCode = -1; return text; };
  const hex = (re) => chr(parseInt(read(re)[1], 16));

  function escape(inClass) {
    const c = char();
    if (Object.hasOwn(SHORTHANDS, c)) return set(SHORTHANDS[c]);
    switch (c) {
      case 'e': return chr(0x1b);
      case 'a': return chr(7);
      case 't': return chr(9);
      case 'n': return chr(10);
      case 'r': return chr(13);
      case 'f': return chr(12);
      case 'x': return hex(source[i] === '{' ? /\{([0-9a-fA-F]{1,6})\}/y : /([0-9a-fA-F]{2})/y);
      case 'u': return hex(/([0-9a-fA-F]{4})/y);
      case 'U': return hex(/([0-9a-fA-F]{8})/y);
      case '0': { // up to three octal digits, at most \0377
        let digits = read(/([0-7]{1,3})/y)[1];
        if (parseInt(digits, 8) > 255) { digits = digits.slice(0, 2); i--; }
        return chr(parseInt(digits, 8));
      }
      case 'c': { // a control character; a lone `\c` is the letter
        const next = source.codePointAt(i);
        if (next === undefined) return chr(99);
        char();
        return chr(next & 31);
      }
      case 'p': case 'P': {
        // ICU spells property names in any case (`\p{l}`), JavaScript only in one: `Lu`, `Alphabetic`.
        const name = read(/\{([\w=]+)\}/y)[1].toLowerCase();
        if (name === 'alnum') return set(`[${c === 'P' ? '^' : ''}\\p{Alphabetic}\\p{Nd}]`);
        return set(`\\${c}{${name[0].toUpperCase()}${name.slice(1)}}`);
      }
      default:
    }
    if (!inClass) {
      if (Object.hasOwn(ASSERTIONS, c)) { boundary = true; return set(ASSERTIONS[c]); }
      if (Object.hasOwn(ANCHORS, c)) return set(`(?:${ANCHORS[c]})`);
      if (c === 'Q') { // a quoted run, up to \E
        const end = source.indexOf('\\E', i), text = source.slice(i, end < 0 ? source.length : end);
        i = end < 0 ? source.length : end + 2;
        return set(`(?:${[...text].map((ch) => chr(ch.codePointAt(0))).join('')})`);
      }
      if (c === 'k') return set(`\\k<g${names.get(read(/<([A-Za-z][A-Za-z0-9]*)>/y)[1]) ?? fail()}>`);
      if (c >= '1' && c <= '9') { // the longest number that names a group opened so far
        let n = Number(c);
        while (/\d/.test(source[i] ?? '') && n * 10 + Number(source[i]) <= groups) n = n * 10 + Number(source[i++]);
        return n <= groups ? set(`\\k<g${n}>`) : fail();
      }
    }
    return chr(c.codePointAt(0));
  }

  function charClass() { // after `[`
    const negated = source[i] === '^' && ++i > 0;
    let body = '', first = true;
    const item = () => {
      const c = char();
      return c === '[' ? set(charClass()) : c === '\\' ? escape(true) : chr(c.codePointAt(0));
    };
    while (source[i] !== ']' || first) { // a `]` first is a literal
      first = false;
      if (source.startsWith('&&', i)) fail();
      const a = item(), low = lastCode;
      if (low >= 0 && source[i] === '-' && source[i + 1] !== ']' && i + 1 < source.length) {
        i++;
        const b = item();
        if (lastCode < low) fail();
        body += `${a}-${b}`;
      } else body += a;
    }
    i++;
    return `[${negated ? '^' : ''}${body}]`;
  }

  /** A group's body up to its `)`, or the whole pattern when `top`; `x` is the free-spacing flag. */
  function sequence(x, top) {
    let out = '', elements = [], anyAmbiguous = false;
    const wrappers = []; // `(?i)` applies to the rest of the group, so it opens a JavaScript modifier group
    const closing = () => ')'.repeat(wrappers.length);
    const body = (flag) => { const text = sequence(flag, false); i++; return text; };
    for (;;) {
      if (x) { // free spacing: skip white space and # comments
        const skipped = /(?:\s+|#[^\n]*\n?)+/y;
        skipped.lastIndex = i;
        if (skipped.test(source)) i = skipped.lastIndex;
      }
      if (i >= source.length) return top ? out + closing() : fail();
      if (source[i] === ')') { if (top) fail(); lastBodyAmbiguous = anyAmbiguous || ambiguous(elements); return out + closing(); }
      if (source[i] === '|') { i++; anyAmbiguous = anyAmbiguous || ambiguous(elements); elements = []; out += `${closing()}|${wrappers.join('')}`; continue; }
      const quantifiersBefore = quantifiers;
      const c = char();
      let text, repeatable = true, literal = null;
      if (c === '.') text = c;
      else if (c === '^' || c === '$') text = `(?:${c})`; // JavaScript cannot repeat an anchor, ICU can
      else if (c === '[') text = charClass();
      else if (c === '\\') { text = escape(false); repeatable = !boundary; boundary = false; }
      else if (c === '*' || c === '+' || c === '?' || c === '{') fail();
      else if (c !== '(') { text = chr(c.codePointAt(0)); literal = c; }
      else if (source[i] !== '?') { const n = ++groups; text = `(?<g${n}>${body(x)})`; }
      else {
        i++;
        const kind = source[i];
        if (kind === '=' || kind === '!') { i++; text = `(?${kind}${body(x)})`; repeatable = false; }
        else if (kind === '>') { i++; const name = `_a${++helpers}`; text = `(?=(?<${name}>${body(x)}))\\k<${name}>`; }
        else if (kind === '#') { const end = source.indexOf(')', i); if (end < 0) fail(); i = end + 1; continue; }
        else if (kind === '<' && (source[i + 1] === '=' || source[i + 1] === '!')) { text = `(?<${source[i + 1]}${(i += 2, body(x))})`; repeatable = false; }
        else if (kind === '<') {
          i++;
          const name = read(/([A-Za-z][A-Za-z0-9]*)>/y)[1], n = ++groups;
          if (names.has(name)) fail();
          names.set(name, n);
          text = `(?<g${n}>${body(x)})`;
        } else { // flags: (?i) for the rest of the group, (?i:...) for a part of it
          const [whole, on, off = ''] = read(FLAGS);
          if (/[^imsx]/.test(on + off)) fail();
          const onJS = on.replace(/x/g, ''), offJS = off.replace(/x/g, ''), modifier = `(?${onJS}${offJS && `-${offJS}`}:`;
          const spaced = on.includes('x') || (x && !off.includes('x'));
          if (whole.endsWith(')')) { // standalone
            x = spaced;
            if (onJS || offJS) { wrappers.push(modifier); out += modifier; }
            continue;
          }
          text = `${onJS || offJS ? modifier : '(?:'}${body(spaced)})`;
        }
      }
      QUANTIFIER.lastIndex = i;
      const m = QUANTIFIER.exec(source);
      const atom = text, holdsQuantifier = quantifiers > quantifiersBefore;
      if (m) {
        if (!repeatable) fail();
        if (c === '(' && holdsQuantifier && lastBodyAmbiguous) icu.nested = true;
        quantifiers++;
        if (m[2] !== undefined) { // {n}, {n,} or {n,m}
          const min = Number(m[2]), max = m[3] ? (m[4] ? Number(m[4]) : Infinity) : min;
          if (min > 2 ** 31 - 1 || (max !== Infinity && max > 2 ** 31 - 1) || max < min) fail();
        }
        i = QUANTIFIER.lastIndex;
        if (/[*+?]/.test(source[i] ?? '')) fail(); // two quantifiers in a row
        text += m[1] + (m[5] === '?' ? '?' : '');
        // A possessive quantifier is an atomic group, which JavaScript spells as a lookahead and a backreference to it.
        if (m[5] === '+') text = `(?=(?<_a${++helpers}>${text}))\\k<_a${helpers}>`;
      }
      // An element is variable when it repeats, or holds a repetition (a group with a quantifier inside).
      elements.push({ atom, variable: !!m || holdsQuantifier, literal: m ? null : literal });
      out += text;
    }
  }
  return sequence(false, true);
}

const regexes = new Map();
/** A pattern with a quantified group whose body ends in a quantified element (`(a+)+`) takes time exponential in the
 * subject's length in JavaScript's engine: past this length it raises instead of freezing the page. Foundation's ICU
 * would run it. A group that ends in a fixed element, as in `^(\d+,)*\d+$`, is matched at any length. */
const NESTED_QUANTIFIER_SUBJECT_LIMIT = 20;
/** Whether `pattern` matches all of `text`; raises for a pattern ICU would not compile. */
function matchesWhole(pattern, text) {
  let entry = regexes.get(pattern);
  if (entry === undefined) {
    try { entry = { re: new RegExp(`(?:${icu(pattern)})(?![^])`, 'vsmy'), nested: icu.nested }; } catch { entry = null; }
    if (regexes.size > 256) regexes.clear();
    regexes.set(pattern, entry);
  }
  if (!entry) raise();
  if (entry.nested && text.length > NESTED_QUANTIFIER_SUBJECT_LIMIT) raise();
  const re = entry.re;
  re.lastIndex = 0;
  return re.test(text);
}

// MARK: Comparison

/** `isEqual:` between two values; numbers compare by value whatever their type. */
function equal(a, b) {
  if (a === undefined || a === null || b === undefined || b === null) return a === b;
  if (isNum(a) && isNum(b)) return isInt(a) && isInt(b) ? BigInt(a) === BigInt(b) : Number(a) === Number(b);
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length || a instanceof Bag !== b instanceof Bag) return false;
    if (!(a instanceof Bag)) return a.every((x, at) => equal(x, b[at]));
    const has = membership(b, false);
    return a.every((x) => has(x));
  }
  if (a instanceof Map && b instanceof Map) return a.size === b.size && [...a].every(([key, x]) => b.has(key) && equal(x, b.get(key)));
  if (a instanceof Obj && b instanceof Obj) return a.id === b.id;
  return a instanceof Time && b instanceof Time ? a.s === b.s : a === b;
}

const equalWith = (a, b, o) => (typeof a === 'string' && typeof b === 'string' && o & (CASE | DIACRITIC) ? fold(a, o) === fold(b, o) : equal(a, b));

/** `compare:` of two comparable values (numbers, strings, dates): -1, 0 or 1. */
function order(a, b, o) {
  let x, y;
  if (isInt(a) && isInt(b)) { x = BigInt(a); y = BigInt(b); }
  else if (isNum(a) && isNum(b)) { x = Number(a); y = Number(b); }
  else if (typeof a === 'string' && typeof b === 'string') {
    // The text `compare:` orders by: the case-folded text with `[c]` or `[d]`, else the canonical decomposition.
    x = o & (CASE | DIACRITIC) ? fold(a, o) : a.normalize('NFD');
    y = o & (CASE | DIACRITIC) ? fold(b, o) : b.normalize('NFD');
  } else if (a instanceof Time && b instanceof Time) { x = a.s; y = b.s; }
  else raise();
  return x < y ? -1 : x > y ? 1 : x === y ? 0 : raise(); // NaN orders against nothing
}

const isNaNValue = (v) => typeof v === 'number' && Number.isNaN(v);

/** `lhs CONTAINS rhs`, and `rhs IN lhs` with the operands swapped. */
function contains(l, r, o) {
  if (l === undefined || r === undefined || l === null) return false;
  if (typeof l === 'string') {
    if (typeof r !== 'string') raise();
    return l !== '' && r !== '' && search(canonical(l, o), canonical(r, o), 0);
  }
  if (Array.isArray(l)) return l.some((item) => equal(item, r));
  if (l instanceof Map || l instanceof Obj) return [...(l instanceof Obj ? l.props : l).values()].some((item) => equal(item, r));
  return raise();
}

function compare(op, l, r, o) {
  switch (op) {
    case '==': return equalWith(l, r, o);
    case '!=': return !equalWith(l, r, o);
    case '<': case '<=': case '>': case '>=': {
      if (l === undefined || r === undefined) return l === r && (op === '<=' || op === '>=');
      if (isNaNValue(l) || isNaNValue(r)) return false;
      const c = order(l, r, o);
      return op === '<' ? c < 0 : op === '<=' ? c <= 0 : op === '>' ? c > 0 : c >= 0;
    }
    case 'CONTAINS': return contains(l, r, o);
    case 'IN': return contains(r, l, o);
    default:
  }
  if (l === undefined || r === undefined) return false;
  if (op === 'BETWEEN') {
    if (!Array.isArray(r) || r instanceof Bag || r.length !== 2) raise();
    const [low, high] = order(r[0], r[1], o) > 0 ? [r[1], r[0]] : r;
    return order(l, low, o) >= 0 && order(l, high, o) <= 0;
  }
  if ((op === 'LIKE' || op === 'MATCHES') && r === '') return false;
  if (typeof l !== 'string' || typeof r !== 'string') raise();
  if (op === 'LIKE' || op === 'MATCHES') {
    // Foundation folds the pattern's text along with the subject (so `\S` becomes `\s` under `[c]`).
    const text = fold(l, o).normalize('NFC'), pattern = fold(r, o).normalize('NFC');
    return op === 'LIKE' ? like([...text], pattern) : matchesWhole(pattern, text);
  }
  return l !== '' && r !== '' && search(canonical(l, o), canonical(r, o), op === 'BEGINSWITH' ? 1 : 2);
}

// MARK: Evaluation

const normalize = (v) => (v === null ? undefined : v);

function evalExpr(e, object) {
  switch (e.t) {
    case 'const': return normalize(e.v);
    case 'self': return normalize(object);
    case 'path': return normalize(walk(object, e.c));
    case 'apply': return normalize(walk(evalExpr(e.base, object), e.c));
    case 'agg': return e.items.map((item) => evalExpr(item, object));
    case 'bin': return arithmetic(e.op, evalExpr(e.l, object), evalExpr(e.r, object));
    default: return raise(); // an unbound variable
  }
}

function evalPred(p, object) {
  switch (p.t) {
    case 'bool': return p.v;
    case 'not': return !evalPred(p.p, object);
    case 'and': return p.items.every((item) => evalPred(item, object));
    case 'or': return p.items.some((item) => evalPred(item, object));
    default: {
      const l = evalExpr(p.l, object), r = evalExpr(p.r, object);
      if (p.q === 'direct') return compare(p.op, l, r, p.o);
      const all = p.q === 'all';
      if (l === undefined) return all;
      if (!Array.isArray(l)) raise();
      // `ANY x IN collection` tests each element against the collection: its items are indexed once, not scanned for each
      // element (`contains` treats an undefined element as absent, as here).
      const within = p.op === 'IN' && Array.isArray(r) && l.length > 1 ? membership(r, true) : null;
      // `ANY` is true at the first element that satisfies it, `ALL` false at the first that does not.
      return l.some((element) => (within ? element !== undefined && within(element) : compare(p.op, element, r, p.o)) !== all) !== all;
    }
  }
}

/** A parsed predicate. */
export class Predicate {
  constructor(root) { this.root = root; }
  /** Parses `format`, substituting `args` for its `%` conversions; throws `Raise` for a format Foundation rejects. */
  static parse(format, args = []) { return new Predicate(parse(format, args)); }
  /** `predicateFormat`. */
  get format() { return printPred(this.root); }
  /** The key names a class instance must be asked for, and how deep key paths go. */
  keys() { return keysOf(this.root); }
  /** `withSubstitutionVariables(_:)`: `bindings` is a `Map` of values by variable name. */
  substitute(bindings) { return new Predicate(bind(this.root, bindings)); }
  /** Evaluates the predicate with `object` as `SELF`; throws `Raise` where Foundation would raise. */
  evaluate(object) { return evalPred(this.root, object); }
}

/** The predicates one host knows. Swift sends a predicate's format, arguments and variables with every request under an
 * id of its own (a host that takes over from another has none of the earlier state); the parsed form is kept for the
 * newest 128 ids, so evaluating a list element by element parses once. */
export function createPredicates() {
  const cache = new Map();
  const compile = (id, format, args, bindings) => {
    let predicate = cache.get(id);
    if (predicate) return predicate;
    predicate = Predicate.parse(format, decodeList(args));
    const reader = wire(bindings);
    while (!reader.done()) {
      const variables = reader.value();
      if (!(variables instanceof Map)) raise();
      predicate = predicate.substitute(variables);
    }
    cache.set(id, predicate);
    if (cache.size > 128) cache.delete(cache.keys().next().value);
    return predicate;
  };
  const attempt = (work, failure) => { try { return work(); } catch (error) { if (error instanceof Raise) return failure; throw error; } };
  return {
    /** `{ format, names, depth }`, or null when Foundation would not parse the format. */
    describe: (id, format, args, bindings) => attempt(() => {
      const predicate = compile(id, format, args, bindings);
      return { format: predicate.format, ...predicate.keys() };
    }, null),
    /** 1 or 0 for the verdict on `object` (wire bytes), 2 when Foundation would raise, 3 when the format does not parse. */
    evaluate(id, format, args, bindings, object) {
      const predicate = attempt(() => compile(id, format, args, bindings), null);
      return predicate ? attempt(() => Number(predicate.evaluate(decode(object))), 2) : 3;
    },
  };
}
