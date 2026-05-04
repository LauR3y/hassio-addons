import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  parseDegiro,
  parseDecimal,
  isoDate,
  detectLocale,
  resolveSymbols,
  extractEmbeddedAmount,
  LOCALES,
} from './convert.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const fixturePath = path.join(here, 'fixtures', 'degiro-sample.csv');
const rows = parseDegiro(fs.readFileSync(fixturePath, 'utf8'));

test('parseDecimal handles comma and period decimals', () => {
  assert.equal(parseDecimal('-33,90'), -33.9);
  assert.equal(parseDecimal('-97.93'), -97.93);
  assert.equal(parseDecimal('1.234,56'), 1234.56);
  assert.equal(parseDecimal('1,234.56'), 1234.56);
  assert.equal(parseDecimal('0'), 0);
  assert.equal(parseDecimal(''), null);
  assert.equal(parseDecimal(null), null);
});

test('isoDate flips DD-MM-YYYY to ISO', () => {
  assert.equal(isoDate('15-12-2022'), '2022-12-15');
});

test('detectLocale', () => {
  assert.equal(detectLocale(['Datum', 'Tijd']), 'nl');
  assert.equal(detectLocale(['Date', 'Time']), 'en');
  assert.throws(() => detectLocale(['Foo']), /Unknown DeGiro locale/);
});

test('aggregates BUY trade from 4-row VICI group', () => {
  const buys = rows.filter(r => r.activityType === 'BUY');
  assert.ok(buys.length >= 1);
  const vici = buys.find(r => r.isin === 'US9256521090');
  assert.ok(vici, 'expected VICI buy');
  assert.equal(vici.quantity, '1');
  assert.equal(vici.unitPrice, '33.9');
  assert.equal(vici.fee, '1.00');
  assert.equal(vici.currency, 'USD');
  assert.equal(vici.date, '2022-12-15');
});

test('aggregates SELL trade from BANK NOVA SCOTIA group', () => {
  const sells = rows.filter(r => r.activityType === 'SELL');
  assert.ok(sells.length >= 1);
  const bns = sells.find(r => r.isin === 'CA0641491075');
  assert.ok(bns, 'expected BNS sell');
  assert.equal(bns.quantity, '1');
  assert.equal(bns.unitPrice, '63.97');
  assert.equal(bns.fee, '0.50');
  assert.equal(bns.currency, 'USD');
});

test('splits DIVIDEND from dividend TAX', () => {
  const divs = rows.filter(r => r.activityType === 'DIVIDEND');
  const taxes = rows.filter(r => r.activityType === 'TAX');
  assert.ok(divs.length >= 3, `expected several DIVIDEND rows, got ${divs.length}`);
  assert.ok(taxes.length >= 3, `expected several TAX rows, got ${taxes.length}`);
  const cocaTax = taxes.find(r => r.isin === 'US1912161007');
  assert.ok(cocaTax);
  assert.equal(cocaTax.amount, '0.07');
});

test('classifies DEPOSIT and WITHDRAWAL exactly once per paired event', () => {
  const dep = rows.filter(r => r.activityType === 'DEPOSIT');
  assert.ok(dep.length >= 1, 'expected at least one DEPOSIT');
  assert.equal(dep[0].currency, 'EUR');
  // The fixture has exactly one withdrawal event — both the
  // `Processed Flatex Withdrawal` and `flatex terugstorting` rows describe
  // it. Sign-aware classification keeps only the negative leg.
  const wdr = rows.filter(r => r.activityType === 'WITHDRAWAL');
  assert.equal(wdr.length, 1, `expected exactly 1 WITHDRAWAL, got ${wdr.length}`);
  assert.equal(wdr[0].amount, '15.1');
});

test('captures connection / Aansluitingskosten as FEE', () => {
  const fees = rows.filter(r => r.activityType === 'FEE');
  assert.ok(fees.length >= 1);
  for (const f of fees) {
    assert.match(f.comment, /Aansluiting|Connection/);
  }
});

test('filters FLATEX cash-sweep rows (ISIN NLFLATEXACNT and "Cash Sweep Transfer")', () => {
  for (const r of rows) {
    assert.notEqual(r.isin, 'NLFLATEXACNT');
    assert.doesNotMatch(r.comment, /Cash Sweep Transfer/);
  }
});

test('skips PRODUCTWIJZIGING corporate-action rows', () => {
  for (const r of rows) {
    assert.doesNotMatch(r.comment, /PRODUCTWIJZIGING/);
  }
});

test('emits ISO dates and sorted ascending', () => {
  for (const r of rows) {
    assert.match(r.date, /^\d{4}-\d{2}-\d{2}$/);
  }
  const dates = rows.map(r => r.date);
  for (let i = 1; i < dates.length; i++) {
    assert.ok(dates[i - 1] <= dates[i], `not sorted at index ${i}`);
  }
});

test('resolveSymbols populates symbol from a mocked OpenFIGI cache', async () => {
  const sample = parseDegiro(fs.readFileSync(fixturePath, 'utf8'));
  const cache = {
    US9256521090: { ticker: 'VICI' },
    IE00B3RBWM25: { ticker: 'VWRA' },
    US1912161007: { ticker: 'KO' },
  };
  await resolveSymbols(sample, {
    cache,
    persist: false,
    fetcher: async () => { throw new Error('should not be called'); },
  });
  const vici = sample.find(r => r.isin === 'US9256521090');
  assert.equal(vici.symbol, 'VICI');
  const vwrl = sample.find(r => r.isin === 'IE00B3RBWM25');
  assert.equal(vwrl.symbol, 'VWRA');
});

test('resolveSymbols batches missing ISINs via the fetcher and caches results', async () => {
  const sample = parseDegiro(fs.readFileSync(fixturePath, 'utf8'));
  const seen = [];
  const fetcher = async (isins) => {
    seen.push(isins);
    return isins.map(isin => ({
      data: [{
        ticker: isin.slice(-4),  // synthetic ticker so we can detect mapping
        marketSector: 'Equity',
        securityType2: 'Common Stock',
      }],
    }));
  };
  const cache = {};
  await resolveSymbols(sample, { cache, persist: false, fetcher });
  // OpenFIGI free-tier batch size is 10. The fixture has 16 unique ISINs,
  // so we expect ceil(16/10) = 2 batched calls.
  assert.ok(seen.length >= 1, 'expected at least one batched call');
  for (const batch of seen) assert.ok(batch.length <= 10, 'batches must be <= 10');
  const callsAfterFirstPass = seen.length;
  // Second pass: fetcher must NOT be called again — everything is cached.
  await resolveSymbols(sample, { cache, persist: false, fetcher });
  assert.equal(seen.length, callsAfterFirstPass, 'second pass should hit cache only');
  for (const r of sample) {
    if (r.isin) assert.ok(r.symbol, `expected symbol for ${r.isin}`);
  }
});

test('resolveSymbols leaves symbol blank when fetcher fails', async () => {
  const sample = parseDegiro(fs.readFileSync(fixturePath, 'utf8'));
  const fetcher = async () => { throw new Error('network down'); };
  const cache = {};
  const messages = [];
  await resolveSymbols(sample, {
    cache, persist: false, fetcher, log: m => messages.push(m),
  });
  assert.ok(messages.some(m => /OpenFIGI lookup failed/.test(m)));
  for (const r of sample) {
    assert.equal(r.symbol, '');
  }
});

test('extractEmbeddedAmount picks the trailing amount + currency', () => {
  assert.deepEqual(
    extractEmbeddedAmount('Overboeking naar uw geldrekening bij flatexDEGIRO Bank: 0,92 EUR'),
    { amount: 0.92, ccy: 'EUR' },
  );
  assert.deepEqual(
    extractEmbeddedAmount('Overboeking naar uw geldrekening bij flatexDEGIRO Bank 26,45 EUR'),
    { amount: 26.45, ccy: 'EUR' },
  );
  assert.equal(extractEmbeddedAmount('Dividend'), null);
});

test('flatex Overboeking naar → DEPOSIT (amount from description)', () => {
  const naar = rows.filter(r =>
    r.activityType === 'DEPOSIT' && /Overboeking naar/.test(r.comment));
  // Fixture has 2 `Overboeking naar` rows: 0,92 EUR and 0,4 EUR.
  assert.equal(naar.length, 2);
  const cents = naar.find(r => r.amount === '0.92');
  assert.ok(cents);
  assert.equal(cents.currency, 'EUR');
});

test('Overboeking VAN is intentionally NOT classified', () => {
  for (const r of rows) {
    assert.doesNotMatch(r.comment, /Overboeking van uw geldrekening/);
  }
});

test('flatex Overboeking with .SE suffix is recognized as DEPOSIT', () => {
  const text = [
    'Datum,Tijd,Valutadatum,Product,ISIN,Omschrijving,FX,Mutatie,,Saldo,,Order Id',
    '01-01-2025,12:00,01-01-2025,,,"Overboeking naar uw geldrekening bij flatexDEGIRO Bank SE: 5,00 EUR",,,,EUR,"100,00",',
  ].join('\n');
  const result = parseDegiro(text);
  assert.equal(result.length, 1);
  assert.equal(result[0].activityType, 'DEPOSIT');
  assert.equal(result[0].amount, '5');
  assert.equal(result[0].currency, 'EUR');
});

test('iDEAL storting (Dutch label) → DEPOSIT', () => {
  const text = [
    'Datum,Tijd,Valutadatum,Product,ISIN,Omschrijving,FX,Mutatie,,Saldo,,Order Id',
    '01-01-2025,12:00,01-01-2025,,,iDEAL storting,,EUR,"100,00",EUR,"100,00",',
  ].join('\n');
  const result = parseDegiro(text);
  assert.equal(result.length, 1);
  assert.equal(result[0].activityType, 'DEPOSIT');
  assert.equal(result[0].amount, '100');
});

test('LOCALES table is well-formed', () => {
  for (const [code, t] of Object.entries(LOCALES)) {
    assert.ok(t.headerSignature, `${code} missing headerSignature`);
    for (const k of ['buyPrefix', 'sellPrefix', 'dividend', 'dividendTax',
                     'fee', 'fx', 'deposit', 'withdrawal', 'cashSweep']) {
      assert.ok(Array.isArray(t[k]), `${code}.${k} not an array`);
    }
  }
});
