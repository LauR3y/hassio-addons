# DeGiro → Wealthfolio CSV converter

Convert DeGiro `Account.csv` (full ledger) to a CSV that imports cleanly into
the Wealthfolio HA add-on.

## Usage

```bash
npm install
node convert.mjs /path/to/Account.csv -o wealthfolio.csv
```

In Wealthfolio: **Activities → Import → Upload `wealthfolio.csv`**. The
column headers match Wealthfolio's defaults, so the mapping step is a
no-op — confirm, review the resolved ISINs, save the import template for
re-use on next month's export.

## Tests

```bash
npm test
```

Asserts against `fixtures/degiro-sample.csv`.

## Supported locales

- Dutch (NL) — primary
- English (EN) — works
- German / French / Italian / Spanish / Portuguese / Czech — extend
  `LOCALES` in `convert.mjs` (header signature + keyword tables for
  `buyPrefix`, `sellPrefix`, `dividend`, `dividendTax`, `fee`, `fx`,
  `deposit`, `withdrawal`, `cashSweep`).

## What it does

- Detects locale from the first header column (`Datum` → NL, `Date` → EN).
- Groups rows by `Order Id`. A typical buy ships as 4 rows (asset trade,
  FX debit, FX credit, transaction fee) — folded into a single Wealthfolio
  BUY row with `fee` summed in.
- Standalone rows (no Order Id) are classified as DIVIDEND, TAX (dividend
  withholding), DEPOSIT, WITHDRAWAL, or FEE (connection/exchange fees).
- Filters out FLATEX cash-sweep rows (`ISIN = NLFLATEXACNT`).
- Skips `PRODUCTWIJZIGING` (product-change) rows — they're ISIN remaps with
  zero cash effect, not real trades.
- Drops FX legs (`Valuta Creditering` / `Valuta Debitering`) — Wealthfolio
  doesn't model FX conversions; only the asset-currency leg of the trade
  is kept.
- Tolerates DeGiro's mixed comma/period decimal style (`-33,90` and
  `-97.93` both appear in real exports).

## Limitations

- Only Account.csv is supported (the cash-and-trades ledger). Transactions.csv
  is incomplete (no dividends/fees/deposits) so it's not worth the second
  code path.
- DE/FR/IT/etc. locales: untested. The `LOCALES` table is the only place
  to add them.
- FX conversion legs are discarded. Fine for portfolio tracking, lossy for
  exact cash-balance reconciliation.

## Acknowledgments

Aggregation logic, locale keyword tables, and the public test fixture come
from [dickwolff/Export-To-Ghostfolio](https://github.com/dickwolff/Export-To-Ghostfolio)
(MIT). Code rewritten for Wealthfolio's column shape.
