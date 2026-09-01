# SQL Repository — Collections Analytics

Reproducible SQL for the whole analytical layer: raw → golden → metrics, plus the
ad-hoc forensic queries behind the Data Quality Report.

## How to run

```
pip install duckdb --break-system-packages
python3 run_all.py
```

This creates `collections.duckdb` from scratch and runs every script in order. Each
script prints a small validation query at the end so you can see row counts / sanity
checks as it goes. Needs `raw/*.csv` present alongside this folder (the 17 source
CSVs from the assignment dataset).

## Structure

```
01_staging/    load every raw CSV into DuckDB, zero transformation - "don't trust
               anything yet" layer
02_golden/     dedup, entity resolution, timezone normalization, attribution
               decisions - one file per table group, each with the reasoning for
               that table's specific issue written as SQL comments
03_metrics/    the redefined recovery metrics (contact rate, RPC, PTP rate,
               PTP-kept rate, recovery rate, recovery per account, recovery per
               agent-hour, channel conversion) as DuckDB views
04_analysis/   the forensic queries behind the Data Quality Report (duplicate
               payments, attribution coverage, timezone split, vendor code checks,
               agent identity noise, portfolio mix, denominator checks)
```

## Why the metric definitions differ from what's likely being reported today

Every metric in `03_metrics` was built by first trying the "obvious" definition and
checking whether it produced something incoherent, then fixing it — not just picked
off a textbook. Two examples worth knowing before reading the notebook:

- **RPC (Right Party Contact)**: first attempt defined RPC as "any disposition exists
  for this account this month." That produced an RPC rate *higher than the contact
  rate itself* — logically impossible, and a clear sign the assumption was wrong.
  Root cause: dispositions are logged at roughly equal volume across every
  `call_status` value (ANSWERED, NO_ANSWER, BUSY, FAILED, VOICEMAIL all show ~7,000
  linked dispositions), so "a disposition exists" doesn't mean a real conversation
  happened. Fixed definition requires the *specific* call to be `ANSWERED` AND its
  own disposition to not be `WRONG_NUMBER`/`NO_CONTACT`. See the comment block at the
  top of `03_metrics/01_contact_and_rpc_rate.sql`.
- **PTP-kept rate**: the source data has a `ptp_status` field (KEPT/BROKEN/OPEN/
  CANCELLED) that looks like it should just be aggregated directly. We checked it
  against actual payment evidence first: only 3.1% of PTPs marked "KEPT" have a
  matching real payment near the promised date, and 2.2% of PTPs marked "BROKEN" do
  too — the self-reported label is statistically almost uncorrelated with what
  actually happened to the money. `03_metrics/02_ptp_rate_and_kept_rate.sql`
  computes both the self-reported number and an evidence-based one (matched against
  `golden_payments`) side by side, so the gap is visible rather than hidden.

**Cost per ₹ recovered is deliberately NOT implemented as a SQL metric.** The source
data has no cost table — no agent wage/cost-per-hour, no per-minute telephony cost, no
per-message WhatsApp/SMS cost. Faking a cost-per-rupee number here would bury invented
assumptions inside what looks like a data-derived fact. It's handled explicitly, with
stated assumptions, in the Executive Memo / Part 4 investment recommendation instead.

## Known limitations carried into every metric here

- `call_attempts`, `call_dispositions`, `payments`, and most event tables don't carry
  their own timezone field and are assumed UTC (see Data Quality Report, item C).
- Campaign/channel attribution only covers ~9% of successful payments (Data Quality
  Report, item B) — `metric_channel_conversion_monthly` is conversion *among traceable
  touches*, not a share of total recovery.
- Agent-level and vendor-level rollups inherit the identity noise documented in
  `02_golden/03_golden_agents.sql` — directional, not precise.

Full narrative reasoning, the statistical investigation, and the counterfactual
methodology are in the Analysis Notebook (next deliverable), which builds on these
views rather than duplicating the SQL.
