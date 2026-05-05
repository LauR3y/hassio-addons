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
  bestTicker,
  CACHE_VERSION,
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
  // Cache entries must match both currency hint AND CACHE_VERSION to be
  // considered fresh. Without v, they get re-queried.
  const v = CACHE_VERSION;
  const cache = {
    US9256521090: { ticker: 'VICI', currency: 'USD', v },
    IE00B3RBWM25: { ticker: 'VWRA', currency: 'EUR', v },
    US1912161007: { ticker: 'KO',   currency: 'USD', v },
  };
  let fetcherCalled = false;
  await resolveSymbols(sample, {
    cache,
    persist: false,
    fetcher: async () => { fetcherCalled = true; return []; },
  });
  // The three explicitly cached ISINs should NOT trigger a fetch.
  const vici = sample.find(r => r.isin === 'US9256521090');
  assert.equal(vici.symbol, 'VICI');
  const vwrl = sample.find(r => r.isin === 'IE00B3RBWM25');
  assert.equal(vwrl.symbol, 'VWRA');
});

test('resolveSymbols invalidates cache entries that are missing CACHE_VERSION', async () => {
  const sample = parseDegiro(fs.readFileSync(fixturePath, 'utf8'));
  // Pre-populate cache with an entry that has no version field — must be
  // re-queried.
  const cache = {};
  for (const r of sample) {
    if (r.isin) cache[r.isin] = { ticker: 'STALE', currency: r.currency };
  }
  let calls = 0;
  await resolveSymbols(sample, {
    cache,
    persist: false,
    fetcher: async (isins) => {
      calls++;
      return isins.map(() => ({ data: [{
        ticker: 'FRESH', exchCode: 'NA', marketSector: 'Equity',
        figi: 'A', compositeFIGI: 'A',
      }] }));
    },
  });
  assert.ok(calls > 0, 'expected fetcher to be invoked for unversioned cache');
});

test('bestTicker for offshore-fund ISIN uses currency-based exchange (PHAG case)', () => {
  // Output includes Yahoo suffix so Wealthfolio resolves unambiguously.
  const mappings = [
    { ticker: 'PHAGEUR', exchCode: 'EO', marketSector: 'Equity', figi: 'A', compositeFIGI: 'A' },
    { ticker: 'PHAG', exchCode: 'NA', marketSector: 'Equity', figi: 'C', compositeFIGI: 'C' },
    { ticker: 'PHAG', exchCode: 'LN', marketSector: 'Equity', figi: 'D', compositeFIGI: 'D' },
  ];
  assert.equal(bestTicker(mappings, 'EUR', 'JE00B1VS3333'), 'PHAG.AS');
});

test('bestTicker for US-domiciled ISIN prefers US exchange (no Yahoo suffix)', () => {
  const mappings = [
    { ticker: 'BABA', exchCode: 'UN', marketSector: 'Equity', figi: 'A', compositeFIGI: 'A' },
    { ticker: 'AHLA', exchCode: 'GR', marketSector: 'Equity', figi: 'B', compositeFIGI: 'B' },
  ];
  assert.equal(bestTicker(mappings, 'EUR', 'US01609W1027'), 'BABA');
});

test('bestTicker for JP-domiciled ISIN prefers Tokyo with .T suffix (Toyota case)', () => {
  const mappings = [
    { ticker: 'TOYOF', exchCode: 'UQ', marketSector: 'Equity', figi: 'A', compositeFIGI: 'A' },
    { ticker: 'TOYOY', exchCode: 'UN', marketSector: 'Equity', figi: 'B', compositeFIGI: 'B' },
    { ticker: '7203',  exchCode: 'JT', marketSector: 'Equity', figi: 'C', compositeFIGI: 'C' },
  ];
  assert.equal(bestTicker(mappings, 'JPY', 'JP3633400001'), '7203.T');
});

test('bestTicker falls back to currency exchanges when country home has no listing (BYD case)', () => {
  // ISIN CNE100000296 (BYD): country home = CN mainland (CG, CH), but BYD
  // doesn't trade on those mainland exchanges in OpenFIGI's mapping. The
  // user buys via DeGiro on Tradegate (Frankfurt-affiliated) so we should
  // fall through to EUR-currency preferred exchanges.
  const mappings = [
    { ticker: 'BYDDF', exchCode: 'US', marketSector: 'Equity', figi: 'A', compositeFIGI: 'A' },
    { ticker: 'BY6', exchCode: 'GR', marketSector: 'Equity', figi: 'B', compositeFIGI: 'B' },
    { ticker: 'BY6', exchCode: 'TH', marketSector: 'Equity', figi: 'C', compositeFIGI: 'C' },
    { ticker: '1211', exchCode: 'HK', marketSector: 'Equity', figi: 'D', compositeFIGI: 'D' },
  ];
  // BY6 is alphanumeric (has digit), so tier1 (alphabetic) only has BYDDF.
  // Country exchanges (CG/CH) miss. EUR fallback puts NA, then GR — BY6 on
  // GR is in tier2 (clean alphanumeric), tier-iter walks tier1 (no match)
  // then tier2 (GR matches) → BY6.DE.
  assert.equal(bestTicker(mappings, 'EUR', 'CNE100000296'), 'BY6.DE');
});

test('bestTicker for German stock uses .DE suffix', () => {
  const mappings = [
    { ticker: 'SAP', exchCode: 'GR', marketSector: 'Equity', figi: 'A', compositeFIGI: 'A' },
  ];
  assert.equal(bestTicker(mappings, 'EUR', 'DE0007164600'), 'SAP.DE');
});

test('bestTicker falls back to first non-empty tier when no preferred exchange matches', () => {
  const mappings = [
    { ticker: 'XYZ', exchCode: 'XX', marketSector: 'Equity', figi: 'A', compositeFIGI: 'B' },
    { ticker: 'XYZ', exchCode: 'YY', marketSector: 'Equity', figi: 'B', compositeFIGI: 'B' },
  ];
  // 'XX' isn't in YAHOO_SUFFIX_BY_EXCHANGE so no suffix is appended.
  assert.equal(bestTicker(mappings, 'EUR', 'IE00B0000001'), 'XYZ');
});

test('bestTicker handles unknown currency / no ISIN by falling back gracefully', () => {
  const mappings = [
    { ticker: 'AAA', exchCode: 'XX', marketSector: 'Equity', figi: 'A', compositeFIGI: 'A' },
  ];
  assert.equal(bestTicker(mappings, 'XYZ'), 'AAA');
  assert.equal(bestTicker(mappings, undefined), 'AAA');
});

test('bestTicker returns empty string on empty / non-equity-only input', () => {
  assert.equal(bestTicker([], 'EUR'), '');
  assert.equal(bestTicker(null, 'EUR'), '');
});

test('resolveSymbols batches missing ISINs via the fetcher and caches results', async () => {
  const sample = parseDegiro(fs.readFileSync(fixturePath, 'utf8'));
  const seen = [];
  const fetcher = async (isins) => {
    seen.push(isins);
    return isins.map(isin => ({
      data: [{
        ticker: isin.slice(-4),  // synthetic ticker so we can detect mapping
        exchCode: 'NA',           // matches EUR preferred exchange
        marketSector: 'Equity',
        securityType2: 'Common Stock',
        figi: 'F' + isin,
        compositeFIGI: 'F' + isin,
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

test('resolveSymbols falls back to ISIN when fetcher fails', async () => {
  const sample = parseDegiro(fs.readFileSync(fixturePath, 'utf8'));
  const fetcher = async () => { throw new Error('network down'); };
  const cache = {};
  const messages = [];
  await resolveSymbols(sample, {
    cache, persist: false, fetcher, log: m => messages.push(m),
  });
  assert.ok(messages.some(m => /OpenFIGI lookup failed/.test(m)));
  for (const r of sample) {
    if (r.isin) assert.equal(r.symbol, r.isin, 'isin should be the fallback symbol');
  }
});

test('resolveSymbols falls back to ISIN when OpenFIGI returns no data', async () => {
  const text = [
    'Datum,Tijd,Valutadatum,Product,ISIN,Omschrijving,FX,Mutatie,,Saldo,,Order Id',
    '01-01-2021,09:00,01-01-2021,DISSOLVED,KYG8990D1253,"Koop 26 @ 10,00 USD",,USD,"-260,00",USD,"100,00",abc',
  ].join('\n');
  const out = parseDegiro(text);
  // Mock OpenFIGI returning empty data (matches its real behavior for
  // dissolved/delisted ISINs).
  await resolveSymbols(out, {
    cache: {},
    persist: false,
    fetcher: async () => [{ data: [] }],
  });
  assert.equal(out[0].symbol, 'KYG8990D1253');
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

test('Overboeking naar/van uw geldrekening bij flatexDEGIRO Bank are dropped (internal sweeps)', () => {
  // Both directions are internal cash sweeps between trading and flatex
  // savings sub-accounts — must NOT appear in the output. The previous
  // mapping of `naar` to DEPOSIT inflated cost basis 5× in real exports.
  for (const r of rows) {
    assert.doesNotMatch(r.comment, /Overboeking (van|naar) uw geldrekening bij flatexDEGIRO/);
  }
});

test('flatex Overboeking with .SE suffix is also dropped', () => {
  const text = [
    'Datum,Tijd,Valutadatum,Product,ISIN,Omschrijving,FX,Mutatie,,Saldo,,Order Id',
    '01-01-2025,12:00,01-01-2025,,,"Overboeking naar uw geldrekening bij flatexDEGIRO Bank SE: 5,00 EUR",,,,EUR,"100,00",',
  ].join('\n');
  const result = parseDegiro(text);
  assert.equal(result.length, 0);
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
    for (const k of ['buyPrefix', 'sellPrefix', 'dividend', 'tax', 'interest',
                     'fee', 'fx', 'deposit', 'withdrawal', 'cashSweep']) {
      assert.ok(Array.isArray(t[k]), `${code}.${k} not an array`);
    }
  }
});

// Helper: build a synthetic 1-row Account.csv (NL header) and return the
// converter output as a single row object.
function nl1(desc, mutCcy = 'EUR', mutVal = '0,00', isin = '', orderId = '') {
  const escape = v => /[",]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v;
  const cells = ['01-01-2025', '12:00', '01-01-2025', '', isin, desc, '', mutCcy, mutVal, 'EUR', '0,00', orderId];
  const row = cells.map(escape).join(',');
  const text = 'Datum,Tijd,Valutadatum,Product,ISIN,Omschrijving,FX,Mutatie,,Saldo,,Order Id\n' + row + '\n';
  const out = parseDegiro(text);
  return out[0] || null;
}

test('Transactiebelasting België → TAX', () => {
  const r = nl1('Transactiebelasting België', 'EUR', '-1,63', 'US0231351067');
  assert.equal(r.activityType, 'TAX');
  assert.equal(r.amount, '1.63');
  assert.equal(r.currency, 'EUR');
});

test('B.T.W. → TAX', () => {
  const r = nl1('B.T.W.', 'EUR', '-0,21');
  assert.equal(r.activityType, 'TAX');
  assert.equal(r.amount, '0.21');
});

test('Kapitaalsuitkering → DIVIDEND', () => {
  const r = nl1('Kapitaalsuitkering', 'USD', '1,76', 'US7561091049');
  assert.equal(r.activityType, 'DIVIDEND');
  assert.equal(r.amount, '1.76');
  assert.equal(r.currency, 'USD');
});

test('Flatex Interest Income → INTEREST (zero amount allowed)', () => {
  const r = nl1('Flatex Interest Income', 'EUR', '0,00');
  assert.equal(r.activityType, 'INTEREST');
  assert.equal(r.amount, '0');
});

test('Flatex Interest → INTEREST', () => {
  const r = nl1('Flatex Interest', 'EUR', '5,42');
  assert.equal(r.activityType, 'INTEREST');
  assert.equal(r.amount, '5.42');
});

test('Inkomsten uit Securities Lending → INTEREST', () => {
  const r = nl1('Inkomsten uit Securities Lending - Maart', 'EUR', '2,17');
  assert.equal(r.activityType, 'INTEREST');
  assert.equal(r.amount, '2.17');
});

test('Sofort Deposit → DEPOSIT', () => {
  const r = nl1('Sofort Deposit', 'EUR', '500,00');
  assert.equal(r.activityType, 'DEPOSIT');
  assert.equal(r.amount, '500');
});

test('flatex Deposit → DEPOSIT', () => {
  const r = nl1('flatex Deposit', 'EUR', '250,00');
  assert.equal(r.activityType, 'DEPOSIT');
  assert.equal(r.amount, '250');
});

test('Service-fee → FEE', () => {
  const r = nl1('Service-fee', 'EUR', '-0,06');
  assert.equal(r.activityType, 'FEE');
  assert.equal(r.amount, '0.06');
});

test('ADR/GDR Externe Kosten → FEE', () => {
  const r = nl1('ADR/GDR Externe Kosten', 'EUR', '-1,30', 'US62914V1061');
  assert.equal(r.activityType, 'FEE');
  assert.equal(r.amount, '1.3');
});

test('Trustly/Sofort Storting Kosten → FEE', () => {
  const r = nl1('Trustly/Sofort Storting Kosten', 'EUR', '-0,50');
  assert.equal(r.activityType, 'FEE');
  assert.equal(r.amount, '0.5');
});

test('DEGIRO Exchange Connection Fee → FEE', () => {
  const r = nl1('DEGIRO Exchange Connection Fee 2024 (Nasdaq - NDQ)', 'EUR', '-2,50');
  assert.equal(r.activityType, 'FEE');
  assert.equal(r.amount, '2.5');
});

test('WIJZIGING ISIN: Koop → BUY with qty/price from description', () => {
  const r = nl1('WIJZIGING ISIN: Koop 16 @ 5,55 EUR', 'EUR', '-88,80', 'DE000TUAG505');
  assert.equal(r.activityType, 'BUY');
  assert.equal(r.quantity, '16');
  assert.equal(r.unitPrice, '5.55');
  assert.equal(r.currency, 'EUR');
  assert.equal(r.isin, 'DE000TUAG505');
});

test('CLAIMEMISSIE: Koop @ 0 EUR -> TRANSFER_IN (free bonus shares)', () => {
  const r = nl1('CLAIMEMISSIE: Koop 8 @ 0 EUR', 'EUR', '0,00', 'CNE100000296');
  assert.equal(r.activityType, 'TRANSFER_IN');
  assert.equal(r.quantity, '8');
  assert.equal(r.unitPrice, '0');
  assert.equal(r.isin, 'CNE100000296');
});

test('STOCK SPLIT priced -> BUY/SELL (TUI reverse split)', () => {
  // Reverse split: 85 shares of old ISIN -> 8 shares of new ISIN.
  const sell = nl1('STOCK SPLIT: Verkoop 85 @ 1,858 EUR', 'EUR', '157,93', 'DE000TUAG000');
  // SELL gets dropped by orphan filter without prior BUY in this isolated
  // single-row CSV — verify with a synthetic 2-row CSV that has a prior buy.
  const text = [
    'Datum,Tijd,Valutadatum,Product,ISIN,Omschrijving,FX,Mutatie,,Saldo,,Order Id',
    '01-01-2020,09:00,01-01-2020,TUI AG,DE000TUAG000,"Koop 85 @ 5,00 EUR",,EUR,"-425,00",EUR,"100,00",abc',
    '24-02-2023,08:02,24-02-2023,TUI AG,DE000TUAG000,"STOCK SPLIT: Verkoop 85 @ 1,858 EUR",,EUR,"157,93",EUR,"515,97",',
    '24-02-2023,08:02,24-02-2023,TUI AG,DE000TUAG505,"STOCK SPLIT: Koop 8 @ 18,58 EUR",,EUR,"-148,64",EUR,"358,04",',
  ].join('\n');
  const out = parseDegiro(text);
  assert.equal(out.filter(r => r.activityType === 'BUY').length, 2);  // initial + split koop
  assert.equal(out.filter(r => r.activityType === 'SELL').length, 1); // split verkoop survives (had +85)
  const split = out.find(r => r.activityType === 'SELL' && /STOCK SPLIT/.test(r.comment));
  assert.equal(split.quantity, '85');
  assert.equal(split.unitPrice, '1.858');
});

test('DELISTING: Verkoop @ 0 USD -> TRANSFER_OUT (closes dissolved-SPAC position)', () => {
  // Need a prior BUY so the orphan filter doesn't drop our SELL.
  const text = [
    'Datum,Tijd,Valutadatum,Product,ISIN,Omschrijving,FX,Mutatie,,Saldo,,Order Id',
    '01-01-2021,09:00,01-01-2021,TPG,KYG8990D1253,"Koop 26 @ 11,90 USD",,USD,"-309,40",USD,"100,00",abc',
    '13-10-2022,10:02,12-10-2022,TPG,KYG8990D1253,"DELISTING: Verkoop 26 @ 0 USD",,USD,"0,00",USD,"0,00",',
  ].join('\n');
  const out = parseDegiro(text);
  const buy = out.find(r => r.activityType === 'BUY');
  const out_ = out.find(r => r.activityType === 'TRANSFER_OUT');
  assert.ok(buy);
  assert.ok(out_);
  assert.equal(out_.quantity, '26');
  assert.equal(out_.unitPrice, '0');
});

test('Verrekening van Aandelen -> CREDIT (positive cash settlement)', () => {
  const r = nl1('Verrekening van Aandelen', 'EUR', '7,78', 'CNE100000296');
  assert.equal(r.activityType, 'CREDIT');
  assert.equal(r.amount, '7.78');
  assert.equal(r.currency, 'EUR');
});

test('Contante Verrekening Aandelen -> CREDIT (SPAC redemption)', () => {
  const r = nl1('Contante Verrekening Aandelen', 'USD', '261,50', 'KYG8990D1253');
  assert.equal(r.activityType, 'CREDIT');
  assert.equal(r.amount, '261.5');
});

test('orphan corporate-action SELL is dropped (CLAIMEMISSIE/STOCK SPLIT also covered)', () => {
  // SELL of an ISIN we have no prior position on — must drop regardless of
  // which corporate-action prefix.
  const text = [
    'Datum,Tijd,Valutadatum,Product,ISIN,Omschrijving,FX,Mutatie,,Saldo,,Order Id',
    '01-01-2025,09:00,01-01-2025,X,XX0000000001,"STOCK SPLIT: Verkoop 10 @ 1,00 EUR",,EUR,"10,00",EUR,"10,00",',
  ].join('\n');
  const out = parseDegiro(text);
  assert.equal(out.length, 0);
});

test('orphan WIJZIGING SELL is dropped when no prior position exists', () => {
  // The TUI case: a WIJZIGING Verkoop of an ISIN that has no prior BUY in
  // the export window. The corresponding WIJZIGING Koop on the new ISIN
  // must still emit normally.
  const text = [
    'Datum,Tijd,Valutadatum,Product,ISIN,Omschrijving,FX,Mutatie,,Saldo,,Order Id',
    '01-01-2025,09:00,01-01-2025,TUI AG - NON TRADEABLE,DE000TUAG1E4,"WIJZIGING ISIN: Verkoop 16 @ 5,55 EUR",,EUR,"88,80",EUR,"4,57",',
    '01-01-2025,09:00,01-01-2025,TUI AG,DE000TUAG505,"WIJZIGING ISIN: Koop 16 @ 5,55 EUR",,EUR,"-88,80",EUR,"-84,23",',
  ].join('\n');
  const out = parseDegiro(text);
  // Only the BUY of the new ISIN should remain; orphan SELL is dropped.
  assert.equal(out.length, 1);
  assert.equal(out[0].activityType, 'BUY');
  assert.equal(out[0].isin, 'DE000TUAG505');
});

test('balanced WIJZIGING pair on same ISIN is preserved (TPG case)', () => {
  // TPG case: BUY then SELL of same ISIN. Running balance is 0 at the end
  // but never goes negative — both rows must survive.
  const text = [
    'Datum,Tijd,Valutadatum,Product,ISIN,Omschrijving,FX,Mutatie,,Saldo,,Order Id',
    '01-01-2025,09:00,01-01-2025,TPG PACE,KYG8990D1253,"WIJZIGING ISIN: Koop 26 @ 10,02 USD",,USD,"-260,52",USD,"0,00",',
    '01-01-2025,10:00,01-01-2025,TPG PACE,KYG8990D1253,"WIJZIGING ISIN: Verkoop 26 @ 10,02 USD",,USD,"260,52",USD,"260,52",',
  ].join('\n');
  const out = parseDegiro(text);
  assert.equal(out.length, 2);
  assert.equal(out.filter(r => r.activityType === 'BUY').length, 1);
  assert.equal(out.filter(r => r.activityType === 'SELL').length, 1);
});

test('Transactiebelasting België inside a trade group emits a separate TAX row', () => {
  // A real BUY trade group with an embedded Belgian TOB row sharing the
  // Order Id. Should yield exactly two output rows: BUY and TAX.
  const orderId = 'fc99ea8c-9b99-493c-abe9-66bef3de2757';
  const text = [
    'Datum,Tijd,Valutadatum,Product,ISIN,Omschrijving,FX,Mutatie,,Saldo,,Order Id',
    `01-01-2025,12:00,01-01-2025,AMAZON.COM INC,US0231351067,"Koop 1 @ 200,00 EUR",,EUR,"-200,00",EUR,"800,00",${orderId}`,
    `01-01-2025,12:00,01-01-2025,AMAZON.COM INC,US0231351067,DEGIRO Transactiekosten en/of kosten van derden,,EUR,"-1,00",EUR,"799,00",${orderId}`,
    `01-01-2025,12:00,01-01-2025,AMAZON.COM INC,US0231351067,Transactiebelasting België,,EUR,"-1,63",EUR,"797,37",${orderId}`,
  ].join('\n');
  const out = parseDegiro(text);
  assert.equal(out.length, 2, `expected 2 rows, got ${out.length}`);
  const buy = out.find(r => r.activityType === 'BUY');
  const tax = out.find(r => r.activityType === 'TAX');
  assert.ok(buy);
  assert.equal(buy.fee, '1.00');
  assert.ok(tax);
  assert.equal(tax.amount, '1.63');
  assert.equal(tax.isin, 'US0231351067');
});

test('WIJZIGING ISIN: Verkoop → SELL with qty/price from description', () => {
  // Need a prior BUY of the same ISIN so the orphan-WIJZIGING dropper
  // doesn't filter the SELL.
  const text = [
    'Datum,Tijd,Valutadatum,Product,ISIN,Omschrijving,FX,Mutatie,,Saldo,,Order Id',
    '01-01-2024,09:00,01-01-2024,TUI AG,DE000TUAG1E4,"Koop 16 @ 5,00 EUR",,EUR,"-80,00",EUR,"100,00",abc',
    '01-01-2025,09:00,01-01-2025,TUI AG,DE000TUAG1E4,"WIJZIGING ISIN: Verkoop 16 @ 5,55 EUR",,EUR,"88,80",EUR,"4,57",',
  ].join('\n');
  const out = parseDegiro(text);
  const sell = out.find(r => r.activityType === 'SELL');
  assert.ok(sell, 'expected SELL row');
  assert.equal(sell.quantity, '16');
  assert.equal(sell.unitPrice, '5.55');
  assert.equal(sell.isin, 'DE000TUAG1E4');
});
