// The number formatting and text folding behind the `text` BrowserIO operation. Every case is one the operation was checked against Foundation with.
import { describe, expect, test } from 'bun:test';
import { foldText, formatNumber } from './BrowserIO/text-format.mjs';

const NBSP = ' ', NNBSP = ' ';
const run = (cases) => { for (const [text, options, expected] of cases) expect([text, options, formatNumber(text, options)]).toEqual([text, options, expected]); };

describe('number formatting', () => {
  test('Brazilian currency matches Foundation', () => {
    const brl = 'style=currency;currency=BRL;locale=pt_BR';
    run([
      ['1027.5', brl, `R$${NBSP}1.027,50`],
      ['1027', brl, `R$${NBSP}1.027,00`],
      ['-22', brl, `-R$${NBSP}22,00`],
      ['1027.5', `${brl};minFrac=0;maxFrac=2`, `R$${NBSP}1.027,5`],
      ['1027', `${brl};minFrac=0;maxFrac=2`, `R$${NBSP}1.027`],
      ['12', 'style=currency;currency=USD;locale=pt_BR;minFrac=0;maxFrac=0', `US$${NBSP}12`],
      ['1.5', 'style=currency;currency=XYZ;locale=pt_BR', `XYZ${NBSP}1,50`],
      ['1234.5', 'style=currency;currency=JPY;locale=pt_BR', `JP¥${NBSP}1.234`],
      ['1027.5', `${brl};sign=always`, `+R$${NBSP}1.027,50`],
      ['-22', `${brl};sign=never`, `R$${NBSP}22,00`],
      ['-22', 'style=currency;currency=EUR;locale=pt_BR;sign=accounting', `-€${NBSP}22,00`],
    ]);
  });

  test('English and European currencies match Foundation', () => {
    run([
      ['1027.5', 'style=currency;currency=USD;locale=en_US', '$1,027.50'],
      ['1027.5', 'style=currency;currency=BRL;locale=en_US', 'R$1,027.50'],
      ['-1.5', 'style=currency;currency=USD;locale=en_US', '-$1.50'],
      ['-22', 'style=currency;currency=USD;locale=en_US;sign=accounting', '($22.00)'],
      ['22', 'style=currency;currency=USD;locale=en_US;sign=accounting', '$22.00'],
      ['1.5', 'style=currency;currency=CHF;locale=en_US', `CHF${NBSP}1.50`],
      ['1234.5', 'style=currency;currency=KRW;locale=en_US', '₩1,234'],
      ['1234.5', 'style=currency;currency=USD;locale=en_GB', 'US$1,234.50'],
      ['1027.5', 'style=currency;currency=EUR;locale=de_DE', `1.027,50${NBSP}€`],
      ['1234.5', 'style=currency;currency=EUR;locale=fr_FR', `1${NNBSP}234,50${NBSP}€`],
      ['-22', 'style=currency;currency=EUR;locale=fr_FR;sign=accounting', `(22,00${NBSP}€)`],
      ['1234.5', 'style=currency;currency=EUR;locale=es_ES', `1234,50${NBSP}€`],
      ['12345.5', 'style=currency;currency=USD;locale=it_IT', `12.345,50${NBSP}USD`],
      ['1234.5', 'style=currency;currency=JPY;locale=ja_JP', '¥1,234'],
      ['nan', 'style=currency;currency=USD;locale=en_US', '$NaN'],
    ]);
  });

  test('decimal and percent follow the locale and the default precision', () => {
    run([
      ['28300', 'locale=pt_BR', '28.300'],
      ['28300.4', 'locale=pt_BR', '28.300,4'],
      ['1234567.891', 'locale=en_US', '1,234,567.891'],
      ['0.30000000000000004', 'locale=en_US', '0.3'],
      ['123456789.12345679', 'locale=en_US', '123,456,789.123457'],
      ['1e-07', 'locale=en_US', '0'],
      ['1e+21', 'locale=en_US', '1,000,000,000,000,000,000,000'],
      ['1234.5', 'locale=fr_FR', `1${NNBSP}234,5`],
      ['1234.5', 'locale=es_ES', '1234,5'],
      ['12345.5', 'locale=es_ES', '12.345,5'],
      ['12345.5', 'locale=pt_PT', `12${NBSP}345,5`],
      ['1000000.5', 'locale=en_US;grouping=never', '1000000.5'],
      ['-1234.5', 'locale=en_US', '-1,234.5'],
      ['-0.0', 'locale=en_US', '-0'],
      ['-0.001', 'locale=en_US;maxFrac=0', '-0'],
      ['inf', 'locale=en_US', '∞'],
      ['-inf', 'locale=en_US', '-∞'],
      ['nan', 'locale=en_US', 'NaN'],
      ['0.74', 'style=percent;locale=pt_BR', '74%'],
      ['0.7456', 'style=percent;locale=pt_BR', '74,56%'],
      ['0.7456', 'style=percent;locale=pt_BR;maxFrac=0', '75%'],
      ['0.736', 'style=percent;locale=pt_BR;minFrac=0;maxFrac=0', '74%'],
      ['-0.74', 'style=percent;locale=pt_BR', '-74%'],
      ['0.74', 'style=percent;locale=de_DE', `74${NBSP}%`],
      ['7', 'style=percent;locale=en_US;scale=0;maxFrac=0', '7%'],
      ['1e-07', 'style=percent;locale=en_US', '0.00001%'],
      ['0.123456789', 'style=percent;locale=en_US', '12.345679%'],
      ['inf', 'style=percent;locale=en_US', '∞%'],
    ]);
  });

  test('rounding is half-even on the shortest digits', () => {
    run([
      ['2.5', 'locale=en_US;maxFrac=0', '2'],
      ['3.5', 'locale=en_US;maxFrac=0', '4'],
      ['0.5', 'locale=en_US;maxFrac=0', '0'],
      ['1.005', 'locale=en_US;minFrac=2;maxFrac=2', '1.00'],
      ['1.015', 'locale=en_US;minFrac=2;maxFrac=2', '1.02'],
      ['0.745', 'style=percent;locale=en_US;maxFrac=0', '74%'],
      ['0.735', 'style=percent;locale=en_US;maxFrac=0', '74%'],
      ['9.999', 'locale=en_US;maxFrac=2', '10'],
      ['999.5', 'locale=en_US;maxFrac=0', '1,000'],
      ['0.0004', 'locale=en_US;maxFrac=3', '0'],
      ['0.0006', 'locale=en_US;maxFrac=3', '0.001'],
    ]);
  });

  test('precision controls integer, fraction and significant digits', () => {
    run([
      ['1.5', 'locale=en_US;minFrac=2;maxFrac=4', '1.50'],
      ['2', 'locale=pt_BR;minFrac=1;maxFrac=3', '2,0'],
      ['12', 'locale=en_US;minInt=4', '0,012'],
      ['5.25', 'locale=en_US;minInt=2;minFrac=1;maxFrac=1', '05.2'],
      ['123', 'locale=en_US;minInt=0;maxInt=2', '23'],
      ['1234.5678', 'locale=en_US;minSig=3;maxSig=3', '1,230'],
      ['1234', 'locale=en_US;minSig=2;maxSig=2', '1,200'],
      ['1.5', 'locale=en_US;minSig=2;maxSig=4', '1.5'],
      ['1.23456', 'locale=en_US;minSig=2;maxSig=4', '1.235'],
      ['0.00123456', 'locale=en_US;minSig=3;maxSig=3', '0.00123'],
    ]);
  });

  test('large integers keep every digit', () => {
    run([
      ['9007199254740993', 'locale=en_US;maxFrac=0', '9,007,199,254,740,993'],
      ['2147483647', 'locale=en_US;maxFrac=0', '2,147,483,647'],
      ['-28300', 'locale=pt_BR;maxFrac=0', '-28.300'],
      ['18446744073709551615', 'locale=en_US;maxFrac=0', '18,446,744,073,709,551,615'],
    ]);
    const huge = formatNumber('1e+300', 'locale=en_US');
    expect(huge.startsWith('1,000,000,000,000')).toBe(true);
    expect([...huge].length).toBe(401);
  });

  test('bad input is rejected', () => {
    for (const [text, options] of [['abc', ''], ['1.5', 'style=hex'], ['1.5', 'maxFrac=x'], ['', '']]) expect(formatNumber(text, options)).toBeNull();
  });

  test('remaining currency symbols follow the locale', () => {
    run([
      ['1.5', 'style=currency;currency=GBP;locale=en_GB', '£1.50'],
      ['1.5', 'style=currency;currency=GBP;locale=fr_FR', `1,50${NBSP}£GB`],
      ['1.5', 'style=currency;currency=GBP;locale=es_ES', `1,50${NBSP}GBP`],
      ['1.5', 'style=currency;currency=CAD;locale=en_US', 'CA$1.50'],
      ['1.5', 'style=currency;currency=AUD;locale=en_US', 'A$1.50'],
      ['1.5', 'style=currency;currency=MXN;locale=en_US', 'MX$1.50'],
      ['1.5', 'style=currency;currency=CNY;locale=en_US', 'CN¥1.50'],
      // A minimum alone widens the maximum to the currency's digits.
      ['1.5', 'style=currency;currency=USD;locale=en_US;minFrac=1', '$1.5'],
      ['1.567', 'style=currency;currency=USD;locale=en_US;minFrac=1', '$1.57'],
    ]);
  });

  test('signs, exponents and significant digit edges', () => {
    run([
      ['+1.5', 'locale=en_US', '1.5'],
      ['1e5', 'locale=en_US', '100,000'],
      ['1E-2', 'locale=en_US', '0.01'],
      // Far below the last kept place, the value rounds away entirely.
      ['1e-10', 'locale=en_US;maxFrac=3', '0'],
      ['0.5', 'locale=en_US;minInt=0;minFrac=1', '.5'],
      ['1234.5678', 'locale=en_US;maxSig=3', '1,230'],
      ['1.5', 'locale=en_US;maxSig=3', '1.5'],
      ['2', 'locale=en_US;sign=alwaysExceptZero', '+2'],
      ['0', 'locale=en_US;sign=alwaysExceptZero', '0'],
      ['-2', 'locale=en_US;sign=alwaysExceptZero', '-2'],
      ['2', 'locale=en_US;sign=auto;grouping=auto;style=decimal', '2'],
    ]);
  });

  test('malformed options and numbers are rejected', () => {
    for (const options of ['maxFrac=1234', 'maxFrac=', 'maxFrac=300', 'grouping=sometimes', 'sign=bogus', 'unknown=1', 'noequals', 'toString=1']) {
      expect([options, formatNumber('1.5', options)]).toEqual([options, null]);
    }
    for (const text of ['1e', '1e+', '1e1234567', '1.2.3', '-', '1x', '0x10', ' 1', '1 ']) expect([text, formatNumber(text, '')]).toEqual([text, null]);
  });

  test('the cache keeps answering after it is full', () => {
    for (let i = 0; i < 300; i++) expect(formatNumber('1234.5', `locale=en_US;minFrac=${i % 7};maxFrac=${(i % 7) + (i % 3)};minInt=${1 + (i % 250)}`)).not.toBeNull();
    expect(formatNumber('1234.5', 'locale=en_US')).toBe('1,234.5');
  });
});

describe('text folding', () => {
  test('strips Latin accents and lowercases', () => {
    expect(foldText('Maré de SANGUE', true, true)).toBe('mare de sangue');
    expect(foldText('Ação à vontade, ÉPICO', true, true)).toBe('acao a vontade, epico');
    expect(foldText('Čeština Ÿ', true, true)).toBe('cestina y');
  });

  test('every Latin-1 base letter folds in both cases', () => {
    expect(foldText('ÇÑÝ çñýÿ', true, false)).toBe('CNY cnyy');
    expect(foldText('ÀÈÌÒÙ àèìòù', true, false)).toBe('AEIOU aeiou');
    // `×` and `÷` sit between the letters and have no base.
    expect(foldText('× ÷', true, true)).toBe('× ÷');
  });

  test('options are independent', () => {
    expect(foldText('Maré', true, false)).toBe('Mare');
    expect(foldText('Maré', false, true)).toBe('maré');
    expect(foldText('Maré', false, false)).toBe('Maré');
  });

  test('decomposed marks fold like precomposed letters', () => {
    expect(foldText('Maré', true, false)).toBe('Mare');
    expect(foldText('é', false, false)).toBe('é');
  });

  test('letters without a base and other scripts pass through', () => {
    expect(foldText('Straße Ærø Þór 日本 🙂', true, true)).toBe('straße ærø þor 日本 🙂');
    expect(foldText('', true, true)).toBe('');
  });

  // Foundation (macOS 27) keeps stroked letters and every mark outside U+0300..U+036F, and folds a final sigma.
  test('behaves like Foundation outside the folding table', () => {
    expect(foldText('Łódź đ Ħ ı İ', true, true)).toBe('łodz đ ħ ı i');
    expect(foldText('ế ά Ά', true, false)).toBe('e α Α');
    expect(foldText('が 한국어 שָׁלוֹם', true, true)).toBe('が 한국어 שָׁלוֹם');
    expect(foldText('ΟΔΟΣ ΣΑΣ', false, true)).toBe('οδοσ σασ');
  });
});
