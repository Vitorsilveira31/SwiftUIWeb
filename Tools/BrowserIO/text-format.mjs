// Number formatting and text folding for the `text` BrowserIO operation: Foundation's number `FormatStyle`s and
// `String.folding(options:locale:)` for Embedded builds, on top of the browser's `Intl` and `String.normalize`.
// Both are pure functions of their arguments; nothing here touches the BrowserIO ABI.

// The text Swift prints for a number (`28300.4`, `1e+21`, `-0.0`, `inf`, `nan`). Intl reads a decimal string
// exactly, so no digit is lost to a double.
const DECIMAL = /^([+-]?(?:\d+\.?\d*|\.\d+))(?:e([+-]?\d{1,6}))?$/i;
const SPECIAL = /^([+-]?)(inf|infinity|nan)$/i;
const SIGN = { auto: 'auto', always: 'always', alwaysExceptZero: 'exceptZero', never: 'never', accounting: 'auto', accountingAlways: 'always', accountingExceptZero: 'exceptZero' };
const STYLES = new Set(['decimal', 'percent', 'currency']);
const formatters = new Map();

/** `text` in the locale and style of `options` (`name=value;...`), or null when either is malformed. */
export function formatNumber(text, options) {
  let formatter = formatters.get(options);
  if (formatter === undefined) {
    try { formatter = numberFormatter(options); } catch { formatter = null; }
    if (formatters.size >= 256) formatters.clear();
    formatters.set(options, formatter);
  }
  return formatter && formatter(text);
}

function numberFormatter(text) {
  const o = { style: 'decimal', scale: 2, grouping: 'auto', sign: 'auto', currency: '', locale: '', minInt: 1 };
  const numbers = new Set(['minFrac', 'maxFrac', 'minInt', 'maxInt', 'minSig', 'maxSig', 'scale']);
  const names = new Set(['style', 'currency', 'locale', 'grouping', 'sign']);
  for (const pair of text.split(';')) {
    if (!pair) continue;
    const at = pair.indexOf('=');
    const name = pair.slice(0, at), value = pair.slice(at + 1);
    if (at < 0 || !names.has(name) && !numbers.has(name)) throw new Error('Invalid number format option');
    o[name] = numbers.has(name) ? parseCount(value) : value;
    // A currency is an ISO 4217 code; anything else is refused rather than handed to Intl.
    if (name === "currency" && !/^[A-Z]{3}$/.test(value)) throw new Error("Invalid number format option");
  }
  const currency = o.style === 'currency';
  if (!STYLES.has(o.style) || !(o.grouping === 'auto' || o.grouping === 'never') || !Object.hasOwn(SIGN, o.sign)) throw new Error('Invalid number format option');
  const intl = { style: o.style, roundingMode: 'halfEven', signDisplay: SIGN[o.sign] };
  if (o.grouping === 'never') intl.useGrouping = false;
  if (currency) { intl.currency = o.currency; if (o.sign.startsWith('accounting')) intl.currencySign = 'accounting'; }
  if (o.minInt > 0) intl.minimumIntegerDigits = Math.min(o.minInt, 21);
  if (o.minSig != null || o.maxSig != null) {
    // Significant digits take over from fraction digits, as they do in Foundation.
    if (o.minSig != null) intl.minimumSignificantDigits = Math.max(1, Math.min(o.minSig, 21));
    if (o.maxSig != null) intl.maximumSignificantDigits = Math.max(1, Math.min(o.maxSig, 21));
  } else {
    // Without a precision a number shows up to six fraction digits; a currency its own (Intl's default).
    let min = o.minFrac, max = o.maxFrac;
    if (min == null && max != null) min = 0;
    if (max == null && !currency) max = Math.max(min ?? 0, 6);
    if (min == null && !currency) min = 0;
    if (min != null) intl.minimumFractionDigits = Math.min(min, 100);
    if (max != null) intl.maximumFractionDigits = Math.min(Math.max(max, min ?? 0), 100);
  }
  const tag = o.locale.replace(/_/g, '-').split('@')[0] || undefined;
  let format;
  try { format = new Intl.NumberFormat(tag, intl); } catch (error) { if (!tag) throw error; format = new Intl.NumberFormat('en', intl); }
  // A percentage that is already one (an integer) is not multiplied by 100 again: the value moves two places down.
  const shift = o.style === 'percent' ? o.scale - 2 : 0;
  // Intl has no maximum integer digits, and no minimum of zero (`.5`): both rewrite the integer part.
  const zero = o.maxInt != null || o.minInt === 0 ? new Intl.NumberFormat(tag, { useGrouping: false }).format(0) : null;
  return (value) => {
    const special = SPECIAL.exec(value);
    const decimal = special ? null : DECIMAL.exec(value);
    if (!special && !decimal) return null;
    const input = special ? (special[2].toLowerCase() === 'nan' ? NaN : special[1] === '-' ? -Infinity : Infinity)
      : shift ? `${decimal[1]}e${Number(decimal[2] ?? 0) + shift}` : value;
    const text = zero ? trimInteger(format.formatToParts(input), o.maxInt, o.minInt === 0, zero) : format.format(input);
    // CLDR writes the yen in Japanese as the fullwidth sign (U+FFE5); Foundation, on Apple's CLDR, writes U+00A5 in
    // every locale. Engines that bundle their own ICU (Chrome, bun on Linux) would otherwise differ from Foundation.
    return currency ? text.replace(/\uFFE5/g, '\u00A5') : text;
  };
}

function parseCount(value) {
  const count = /^\d{1,3}$/.test(value) ? Number(value) : 256;
  if (count > 255) throw new Error('Invalid number format option');
  return count;
}

// Keeps the last `maxInteger` digits of the integer part (123 -> 23) and, for a minimum of zero, drops a zero one.
function trimInteger(parts, maxInteger, dropZero, zero) {
  const digits = parts.filter((part) => part.type === 'integer').flatMap((part) => Array.from(part.value));
  let skip = Math.max(0, digits.length - (maxInteger ?? digits.length));
  const clear = dropZero && digits.every((digit) => digit === zero);
  let out = '', started = false;
  for (const { type, value } of parts) {
    if (type === 'integer') {
      for (const digit of Array.from(value)) { if (skip > 0) skip--; else { started = true; if (!clear) out += digit; } }
    } else if (type === 'group') { if (started && !clear) out += value; } else out += value;
  }
  return out;
}

/** Foundation's `folding(options:)`: accents (the combining marks) and/or case dropped. */
export function foldText(text, diacritics, foldsCase) {
  if (diacritics) text = text.normalize('NFD').replace(/[̀-ͯ]/g, '').normalize('NFC');
  // A final sigma folds to the same letter as any other.
  if (foldsCase) text = text.toLowerCase().replace(/ς/g, 'σ');
  return text;
}
