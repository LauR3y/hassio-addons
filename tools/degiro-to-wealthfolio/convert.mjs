#!/usr/bin/env node
// Convert DeGiro Account.csv -> Wealthfolio import-wizard CSV.
//
// Multi-row aggregation by Order Id, locale keyword tables, and FLATEX
// cash-sweep filtering follow dickwolff/Export-To-Ghostfolio (MIT).

import fs from 'node:fs';
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
    deposit:      ['iDEAL Deposit', 'flatex storting'],
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

function classifyStandalone(r, table) {
  const desc = r[COL.desc] || '';
  const isin = r[COL.isin] || '';
  const ccy = r[COL.mutCcy] || '';
  const amt = parseDecimal(r[COL.mutVal]);
  if (amt == null) return null;
  const date = isoDate(r[COL.date]);
  const base = (type, amount) => ({
    date, activityType: type, currency: ccy,
    symbol: '', isin, quantity: '', unitPrice: '',
    amount: String(amount), fee: '', comment: desc,
  });

  // Sign-aware classification de-duplicates DeGiro's paired rows (e.g. a
  // withdrawal ships as `flatex terugstorting` (negative, cash leaves) +
  // `Processed Flatex Withdrawal` (positive, ack from bank). Only the
  // actual cash-flow side is kept.
  if (table.dividendTax.some(d => desc.includes(d))) return amt < 0 ? base('TAX', Math.abs(amt)) : null;
  if (table.dividend.some(d => desc.includes(d)))    return amt > 0 ? base('DIVIDEND', amt) : null;
  if (table.deposit.some(d => desc.includes(d)))     return amt > 0 ? base('DEPOSIT', amt) : null;
  if (table.withdrawal.some(d => desc.includes(d))) return amt < 0 ? base('WITHDRAWAL', Math.abs(amt)) : null;
  if (table.fee.some(d => desc.includes(d)))         return amt < 0 ? base('FEE', Math.abs(amt)) : null;
  return null;
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

function main() {
  const argv = process.argv.slice(2);
  if (argv.length === 0 || argv.includes('-h') || argv.includes('--help')) {
    console.error('Usage: node convert.mjs <Account.csv> [-o output.csv]');
    process.exit(2);
  }
  const oIdx = argv.indexOf('-o');
  const output = oIdx >= 0 ? argv[oIdx + 1] : '-';
  const inputArg = argv.find(a => a !== '-o' && a !== output);
  const text = fs.readFileSync(inputArg, 'utf8');
  const rows = parseDegiro(text);
  const csv = toCsv(rows);
  if (output === '-') process.stdout.write(csv);
  else fs.writeFileSync(output, csv);
}

if (import.meta.url === `file://${process.argv[1]}`) main();
