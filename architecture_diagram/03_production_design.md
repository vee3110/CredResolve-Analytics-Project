# Part 5 — Production Analytics Design

Companion document to `architecture_diagram.svg`. This is written for the engineering
team that would actually build this, not as a restatement of the diagram — it covers
the things a diagram can't: exact contracts, failure handling, and what "done" means
for each stage.

## Pipeline stages

**RAW.** Append-only landing of every source table, exactly as received, hourly.
Schema-on-read — we do not reject a row at this stage for looking wrong, we just
record it arrived. This is deliberate: Part 1 of this project depended on being able
to see the raw mess (30,000 noisy agent rows, borrower demographic noise, etc.) — if
staging silently "fixed" things on the way in, that evidence disappears and the next
data-quality investigation starts blind.

**STAGING.** Type casts and column renames only — no business logic. 1:1 grain with
raw. This is the layer that would break loudly (schema check gate) if a source system
changes a column name or type without warning.

**CLEAN.** Deduplication and entity resolution, exactly as implemented in this
project's `02_golden` SQL scripts: exact-duplicate removal, ID-collision handling via
surrogate keys, timezone normalization where a timezone field exists. This is where
the "raw → rejected/corrected → golden" funnel counts (Golden Dataset doc) get
generated and logged — every run should emit its own funnel counts as a monitoring
signal (see Monitoring below), not just at build time.

**GOLDEN.** Source-of-truth joins and attribution decisions: `accounts.csv` as the
only source of `account_id → borrower_id` truth, `SUCCESS`-only payment attribution,
disposition-code normalization, agent identity resolution via mode. One row per real
business entity or event. This is the layer every other team's dashboards and ad-hoc
queries should be built on — nobody outside the data team should query RAW or STAGING
directly.

**FEATURE.** Rollups and rolling windows built on GOLDEN: account-level 30/60/90-day
contact counts, agent-level rolling answer rates, campaign-level touch counts. This
layer exists so METRICS queries don't each independently recompute the same window
logic — a change to "what counts as a rolling 30-day window" happens in one place.

**METRICS.** The redefined recovery metrics from the SQL Repository (contact rate,
RPC, PTP rate, PTP-kept rate, recovery rate, recovery per account, recovery per
agent-hour, channel conversion), computed daily, **versioned, never overwritten in
place**. If a metric definition changes (e.g. RPC gets a better proxy than the one
built here), that's a new version (`metric_rpc_rate_v2`), and `v1` stays queryable —
otherwise a historical dashboard silently changes meaning underneath a chart nobody
touched, which is exactly the kind of silent redefinition this whole project exists to
catch.

**DASHBOARD.** Executive + operational views, refreshed on a schedule, reading from a
cached replica — never live queries against GOLDEN/METRICS tables directly, so a slow
ad-hoc query doesn't degrade the CEO's dashboard load time.

## Data contracts

Every edge between stages is a contract, checked automatically before data is allowed
to flow to the next stage. Minimum contract fields:

- **Primary key** (and whether it's natural or surrogate)
- **Grain** (what one row represents)
- **Required (non-nullable) fields**
- **Freshness SLA** (max allowed staleness)
- **Breaking-change rule**: a column rename, type change, or grain change requires a
  new contract version; the old version is kept live for 90 days so downstream
  consumers have a migration window instead of breaking on deploy day.

Example (also shown on the diagram):

| Field | Value |
|---|---|
| Table | `golden_payments` |
| Primary key | `payment_sk` (surrogate: `payment_id` + `dup_seq`, because `payment_id` alone collided in the source data — see Data Quality Report item A) |
| Grain | One row per payment event, post-deduplication |
| Required fields | `account_id`, `amount`, `payment_status`, `event_at` |
| Freshness SLA | Refreshed within 2 hours of RAW landing |

## Incremental processing

RAW → GOLDEN runs hourly, incrementally, keyed on `event_at` (or `updated_at` where
`event_at` doesn't exist) — only rows newer than the last successful watermark are
reprocessed, not a full rebuild every run. GOLDEN → DASHBOARD runs daily, because
executive metrics don't need hourly freshness and a daily cadence keeps compute cost
down.

**Late-arriving data:** a 3-day reprocessing window on `event_at` — any row that lands
within 3 days of its own event timestamp gets picked up automatically by the next
incremental run touching that date range. Processing is idempotent (upsert keyed on
natural key + surrogate), so re-running a date range is always safe. A row arriving
**after** the 3-day window is quarantined (logged, not silently dropped) and swept up
in a weekly reconciliation job rather than blocking the daily pipeline.

**Backfills:** a backfill is just a replay of STAGING → GOLDEN for a specified date
range, using the same idempotent upsert logic as normal incremental runs — there is no
separate "backfill code path" to maintain and accidentally let drift from the main
pipeline.

## Data-quality checks (automated, not just this project's one-time investigation)

Every stage transition runs:
- Row-count delta vs. a 7-day rolling median (catches a source feed going silent or
  suddenly duplicating)
- Primary-key uniqueness and null-rate thresholds, per the table's contract
- Referential integrity (does every `account_id` in a child table exist in
  `golden_accounts`?) — this specific check would have caught the
  `account_status_history.borrower_id` mismatch found in this project on day one
  instead of during a one-off audit
- Business-rule checks (e.g. `amount >= 0`, `payment_status` in the known enum)

A failed check blocks that table's downstream propagation and pages the on-call data
engineer — it does not silently let bad data flow through with a warning nobody reads.

## Monitoring & anomaly detection

- Daily metric values compared against a 28-day rolling z-score; a jump outside
  ~2.5 standard deviations gets flagged for review before it reaches a dashboard.
- **Cherry-pick guard**, specific to this project's central finding: an automated check
  on any headline month-on-month or period-on-period number, flagging if a single
  day/week/month is doing all the work of an otherwise-flat trend (exactly the pattern
  behind the "11% improvement" claim this whole project investigated). This is the one
  monitoring rule I'd consider closest to mandatory given what we found — it exists
  specifically so a misleading single-month comparison can't reach a leadership
  dashboard again without a flag on it.
- Pipeline SLA breaches (a stage running later than its contract's freshness SLA)
  page on-call within 15 minutes.

## Lineage & catalog

Every GOLDEN/FEATURE/METRICS column is tagged with its source lineage (which raw
columns and which transformation logic produced it) — generated from the dbt
`schema.yml` / model config rather than maintained by hand in a separate document,
so it can't silently go stale. Each table has an owner and a freshness SLA recorded in
the catalog, and metric definitions are versioned as described above rather than
overwritten.

## What this design specifically protects against

Every design choice above maps to a real problem found in this project, not a generic
best practice:

| Design choice | Problem it prevents (found in this project) |
|---|---|
| RAW layer never modifies incoming data | Losing visibility into the messiness itself (agent identity noise, borrower demographic noise) |
| Surrogate keys, not trust in source PKs | `payment_id` and `call_id` collisions (Data Quality Report item A) |
| `accounts.csv` as sole source of borrower truth | `account_status_history.borrower_id` was 100% wrong |
| Versioned metric definitions | A metric silently changing meaning underneath a historical chart |
| Referential-integrity checks at every stage | The borrower_id mismatch could have been caught same-day instead of during a one-off audit |
| Cherry-pick guard on headline numbers | The exact failure mode behind the reported "11% improvement" |
