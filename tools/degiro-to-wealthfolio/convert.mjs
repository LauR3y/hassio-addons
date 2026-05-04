#!/usr/bin/env node
// Convert DeGiro Account.csv -> Wealthfolio import-wizard CSV.
//
// Multi-row aggregation by Order Id, locale keyword tables, and FLATEX
// cash-sweep filtering follow dickwolff/Export-To-Ghostfolio (MIT).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { parse } from 'csv-parse/sync';

export const LOCALES = {
  nl: {
    headerSignature: 'Datum',
    buyPrefix:    ['Koop'],
    sellPrefix:   ['Verkoop'],
    dividend:     ['Dividend'],
    dividendTax:  ['Dividendbelasting'],
    fee: [
      'Transactiekosten en/of kosten van derden',
      'Aansluitingskosten',
      'DEGIRO Aansluitingskosten',
    ],
    fx:           ['Valuta Creditering', 'Valuta Debitering'],
    deposit: [
      'iDEAL Deposit',
      'iDEAL storting',
      'flatex storting',
      // Cash sweep TO flatex savings — treated as deposit per user's mental
      // model (flatex is the canonical wealth account). Both legacy and SE
      // (post-2024) phrasings.
      'Overboeking naar uw geldrekening bij flatexDEGIRO Bank',
    ],
    withdrawal:   ['Processed Flatex Withdrawal', 'flatex terugstorting'],
    cashSweep:    ['Cash Sweep Transfer'],
  },
  en: {
    headerSignature: 'Date',
    buyPrefix:    ['Buy'],
    sellPrefix:   ['Sell'],
    dividend:     ['Dividend'],
    dividendTax:  ['Dividend Tax'],
    fee: [
      'Transaction and/or third party costs',
      'Connection fee',
      'DEGIRO Connection fee',
    ],
    fx:           ['FX Credit', 'FX Debit', 'Currency Credit', 'Currency Debit'],
    deposit:      ['Deposit'],
    withdrawal:   ['Withdrawal', 'Processed Flatex Withdrawal'],
    cashSweep:    ['Cash Sweep Transfer'],
  },
};

// "Koop 12,5 @ 79,35 EUR" / "Buy 1 @ 33.9 USD"
const TRADE_RE = /^(?<verb>\w+)\s+(?<qty>[\d.,]+)\s*@\s*(?<price>[\d.,]+)\s+(?<ccy>[A-Z]{3})/;

const WF_COLS = [
  'date', 'activityType', 'currency', 'symbol', 'isin',
  'quantity', 'unitPrice', 'amount', 'fee', 'comment',
];

// Account.csv layout (12 cols). DeGiro puts the column header above the
// CURRENCY cell and an empty header above the VALUE cell, so:
//   Mutatie  -> ccy at [7], value at [8]
//   Saldo    -> ccy at [9], value at [10]
const COL = {
  date: 0, time: 1, valueDate: 2, product: 3, isin: 4, desc: 5,
  fx: 6, mutCcy: 7, mutVal: 8, salCcy: 9, salVal: 10, orderId: 11,
};

export function parseDecimal(s) {
  if (s == null) return null;
  const str = String(s).trim();
  if (str === '') return null;
  // DeGiro mixes comma- and period-decimal even within a single CSV. The
  // LAST separator in the string is the decimal; any earlier . or , are
  // thousands separators.
  const lastDot = str.lastIndexOf('.');
  const lastComma = str.lastIndexOf(',');
  let cleaned;
  if (lastDot >= 0 && lastComma >= 0) {
    cleaned = lastComma > lastDot
      ? str.replace(/\./g, '').replace(',', '.')
      : str.replace(/,/g, '');
  } else if (lastComma >= 0) {
    cleaned = str.replace(',', '.');
  } else {
    cleaned = str;
  }
  const n = Number(cleaned);
  return Number.isFinite(n) ? n : null;
}

export function isoDate(s) {
  const [d, m, y] = s.split('-');
  return `${y}-${m}-${d}`;
}

export function detectLocale(headers) {
  const h0 = (headers[0] || '').replace(/^﻿/, '');
  for (const [code, table] of Object.entries(LOCALES)) {
    if (h0 === table.headerSignature) return code;
  }
  throw new Error(`Unknown DeGiro locale (header: ${JSON.stringify(h0)})`);
}

export function parseDegiro(csvText) {
  const rows = parse(csvText, {
    bom: true,
    columns: false,
    skip_empty_lines: true,
    relax_column_count: true,
    trim: false,
  });
  if (rows.length === 0) return [];
  const headers = rows[0];
  const table = LOCALES[detectLocale(headers)];

  const groups = new Map();
  const standalone = [];
  for (const r of rows.slice(1)) {
    if (r.every(c => c === '' || c == null)) continue;
    if ((r[COL.isin] || '') === 'NLFLATEXACNT') continue; // cash sweep filter
    const orderId = (r[COL.orderId] || '').trim();
    if (orderId) {
      if (!groups.has(orderId)) groups.set(orderId, []);
      groups.get(orderId).push(r);
    } else {
      standalone.push(r);
    }
  }

  const out = [];
  for (const group of groups.values()) {
    const wf = foldTradeGroup(group, table);
    if (wf) out.push(wf);
  }
  for (const r of standalone) {
    const wf = classifyStandalone(r, table);
    if (wf) out.push(wf);
  }
  out.sort((a, b) => a.date.localeCompare(b.date));
  return out;
}

function foldTradeGroup(group, table) {
  const verbs = [...table.buyPrefix, ...table.sellPrefix];
  const assetRow = group.find(r => {
    const desc = r[COL.desc] || '';
    return verbs.some(p => desc.startsWith(p));
  });
  if (!assetRow) return null;
  const m = (assetRow[COL.desc] || '').match(TRADE_RE);
  if (!m) return null;

  const isBuy = table.buyPrefix.includes(m.groups.verb);
  const qty = parseDecimal(m.groups.qty);
  const price = parseDecimal(m.groups.price);
  if (qty == null || price == null || qty === 0) return null;
  const ccy = m.groups.ccy;

  let feeTotal = 0;
  for (const r of group) {
    const desc = r[COL.desc] || '';
    if (table.fee.some(label => desc.includes(label))) {
      const v = parseDecimal(r[COL.mutVal]);
      if (v != null) feeTotal += Math.abs(v);
    }
  }

  return {
    date: isoDate(assetRow[COL.date]),
    activityType: isBuy ? 'BUY' : 'SELL',
    currency: ccy,
    symbol: '',
    isin: assetRow[COL.isin] || '',
    quantity: String(qty),
    unitPrice: String(price),
    amount: '',
    fee: feeTotal ? feeTotal.toFixed(2) : '',
    comment: assetRow[COL.desc] || '',
  };
}

// Pulls the trailing `<number> <CCY>` token from descriptions like
// "Overboeking naar uw geldrekening bij flatexDEGIRO Bank: 0,92 EUR".
// Used for rows where the Mutatie column is empty and the cash amount
// is encoded inside the description text.
export function extractEmbeddedAmount(desc) {
  const matches = [...desc.matchAll(/([\d.,]+)\s+([A-Z]{3})\b/g)];
  if (matches.length === 0) return null;
  const last = matches[matches.length - 1];
  const amount = parseDecimal(last[1]);
  if (amount == null) return null;
  return { amount: Math.abs(amount), ccy: last[2] };
}

function classifyStandalone(r, table) {
  const desc = r[COL.desc] || '';
  const isin = r[COL.isin] || '';
  const date = isoDate(r[COL.date]);
  const mutCcy = r[COL.mutCcy] || '';
  const mutAmt = parseDecimal(r[COL.mutVal]);

  const make = (type, amount, currency) => ({
    date, activityType: type, currency,
    symbol: '', isin, quantity: '', unitPrice: '',
    amount: String(amount), fee: '', comment: desc,
  });

  // Sign-aware classification de-duplicates DeGiro's paired rows (e.g. a
  // withdrawal ships as `flatex terugstorting` (negative, cash leaves) +
  // `Processed Flatex Withdrawal` (positive, ack from bank). Only the
  // actual cash-flow side is kept.
  if (mutAmt != null) {
    if (table.dividendTax.some(d => desc.includes(d))) return mutAmt < 0 ? make('TAX', Math.abs(mutAmt), mutCcy) : null;
    if (table.dividend.some(d => desc.includes(d)))    return mutAmt > 0 ? make('DIVIDEND', mutAmt, mutCcy) : null;
    if (table.deposit.some(d => desc.includes(d)))     return mutAmt > 0 ? make('DEPOSIT', mutAmt, mutCcy) : null;
    if (table.withdrawal.some(d => desc.includes(d))) return mutAmt < 0 ? make('WITHDRAWAL', Math.abs(mutAmt), mutCcy) : null;
    if (table.fee.some(d => desc.includes(d)))         return mutAmt < 0 ? make('FEE', Math.abs(mutAmt), mutCcy) : null;
    return null;
  }

  // No Mutatie value — fall back to amount embedded in the description.
  // Currently only used by the flatex `Overboeking naar` sweep rows.
  if (table.deposit.some(d => desc.includes(d))) {
    const e = extractEmbeddedAmount(desc);
    return e ? make('DEPOSIT', e.amount, e.ccy) : null;
  }
  return null;
}

// ----------------------------------------------------------------------------
// ISIN -> ticker resolution via OpenFIGI (free, no API key needed).
// Cached on disk so repeat runs don't re-query.
// ----------------------------------------------------------------------------

export function cachePath() {
  const base = process.env.XDG_CACHE_HOME || path.join(os.homedir(), '.cache');
  return path.join(base, 'degiro-to-wealthfolio', 'figi.json');
}

function loadCache() {
  try { return JSON.parse(fs.readFileSync(cachePath(), 'utf8')); }
  catch { return {}; }
}

function saveCache(cache) {
  const p = cachePath();
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, JSON.stringify(cache, null, 2));
}

async function defaultFetcher(isins) {
  const body = isins.map(isin => ({ idType: 'ID_ISIN', idValue: isin }));
  const res = await fetch('https://api.openfigi.com/v3/mapping', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    throw new Error(`OpenFIGI HTTP ${res.status}: ${await res.text()}`);
  }
  return res.json();
}

// Pick the best ticker from OpenFIGI's mapping array. OpenFIGI returns multiple
// listings for cross-listed securities. We want the bare home-exchange ticker
// (e.g. "VICI" on NYSE, not "1KN" on Frankfurt) because Wealthfolio's resolver
// then appends an exchange suffix based on the activity currency.
//
// OpenFIGI marks the composite/primary listing with figi === compositeFIGI;
// take that. Otherwise fall back to the first entry that has a ticker.
function bestTicker(mappings) {
  if (!Array.isArray(mappings) || mappings.length === 0) return '';
  const equity = mappings.filter(m => m.ticker && m.marketSector === 'Equity');
  const pool = equity.length > 0 ? equity : mappings.filter(m => m.ticker);
  const composite = pool.find(m => m.figi && m.figi === m.compositeFIGI);
  return (composite || pool[0])?.ticker || '';
}

export async function resolveSymbols(rows, opts = {}) {
  const log = opts.log || (() => {});
  const fetcher = opts.fetcher || defaultFetcher;
  const cache = opts.cache || loadCache();
  const persist = opts.persist !== false;

  const isins = [...new Set(rows.map(r => r.isin).filter(Boolean))];
  const missing = isins.filter(i => !(i in cache));

  if (missing.length > 0) {
    log(`Looking up ${missing.length} ISIN(s) via OpenFIGI...`);
    // OpenFIGI free tier: 10 mappings per request, 25 reqs/min.
    let anyResolved = false;
    for (let i = 0; i < missing.length; i += 10) {
      const batch = missing.slice(i, i + 10);
      try {
        const result = await fetcher(batch);
        for (let j = 0; j < batch.length; j++) {
          const ticker = bestTicker(result[j]?.data);
          // Cache the empty result too so subsequent runs don't re-query
          // ISINs that OpenFIGI genuinely doesn't know.
          cache[batch[j]] = { ticker };
          if (ticker) anyResolved = true;
        }
      } catch (e) {
        log(`OpenFIGI lookup failed for batch: ${e.message} — symbols left blank, retrying next run`);
        // Do NOT cache transient failures — let next run retry.
      }
    }
    if (persist && anyResolved) saveCache(cache);
  }

  for (const r of rows) {
    if (r.isin && !r.symbol && cache[r.isin]?.ticker) {
      r.symbol = cache[r.isin].ticker;
    }
  }
  return rows;
}

function toCsv(rows) {
  const escape = v => {
    const s = v == null ? '' : String(v);
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const header = WF_COLS.join(',');
  const body = rows.map(r => WF_COLS.map(c => escape(r[c])).join(','));
  return [header, ...body].join('\n') + '\n';
}

async function main() {
  const argv = process.argv.slice(2);
  if (argv.length === 0 || argv.includes('-h') || argv.includes('--help')) {
    console.error('Usage: node convert.mjs <Account.csv> [-o output.csv] [--no-figi]');
    process.exit(2);
  }
  const oIdx = argv.indexOf('-o');
  const output = oIdx >= 0 ? argv[oIdx + 1] : '-';
  const skipFigi = argv.includes('--no-figi');
  const inputArg = argv.find(a => !a.startsWith('-') && a !== output);
  const text = fs.readFileSync(inputArg, 'utf8');
  const rows = parseDegiro(text);
  if (!skipFigi) {
    await resolveSymbols(rows, { log: m => process.stderr.write(m + '\n') });
  }
  const csv = toCsv(rows);
  if (output === '-') process.stdout.write(csv);
  else fs.writeFileSync(output, csv);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch(e => { console.error(e); process.exit(1); });
}
