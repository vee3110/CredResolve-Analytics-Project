# Part 1 — Golden Dataset: Build Documentation

**Scope:** turning 17 raw tables into a trustworthy analytical layer.
**Tooling:** DuckDB (SQL scripts in `/sql`, run in order by `run_pipeline.py`). Every
decision below is implemented as SQL, not eyeballed in a notebook, so it's reproducible.

---

## 1. How I approached this

Before writing any cleaning logic, I profiled every table: row counts, exact-duplicate
counts, primary-key uniqueness, null rates, and date ranges (`profile_raw.py` +
`profile_summary.csv`). That surfaced most of the real issues before I touched any
"cleaning" — a few of them changed my plan for the golden layer entirely (agents and
account_status_history especially). I'd rather over-invest in profiling up front than
clean confidently in the wrong direction.

## 2. Raw → Golden funnel (see `docs/raw_to_golden_funnel.csv`)

| table | raw rows | removed/collapsed | golden rows |
|---|---:|---:|---:|
| borrowers | 30,600 | 19,585 | 11,015 |
| accounts | 30,000 | 0 | 30,000 |
| agents | 30,000 | 29,000 | 1,000 |
| vendor_telephony | 15 | 0 | 15 |
| campaigns | 120 | 0 | 120 |
| calls | 91,350 | 1,271 | 90,079 |
| call_attempts | 120,000 | 0 | 120,000 |
| call_dispositions | 35,000 | 0 | 35,000 |
| whatsapp_events | 60,600 | 600 | 60,000 |
| sms_events | 45,000 | 0 | 45,000 |
| field_visits | 25,000 | 0 | 25,000 |
| promises_to_pay | 18,000 | 0 | 18,000 |
| payments | 25,500 | 486 | 25,014 |
| complaints | 8,000 | 0 | 8,000 |
| account_status_history | 60,000 | 0 | 60,000 |
| agent_sessions | 15,000 | 0 | 15,000 |
| daily_targeting | 45,000 | 0 | 45,000 |

Two tables lost the overwhelming majority of their raw row count on the way to golden
— **not** because the data was thrown away, but because the raw grain was wrong
(see §3 and §4). Everything else in the dataset was close to clean at the row level;
the real problems in this dataset live in *identity* and *definitions*, not row counts.

## 3. Source-of-truth & entity-resolution decisions

**Borrowers (`borrowers.csv`).** 30,600 rows resolve to only 11,015 distinct
`borrower_id`. 600 rows are plain exact-duplicate ingestion retries. The rest is more
interesting: for the same `borrower_id`, name/phone/email/city/state change
incoherently between rows (one borrower_id showed up as "Sneha Das" in Delhi on one
row and "Amit Kumar" in Mumbai on another). Across all 11,015 borrowers there are only
**10 distinct names and 10 distinct cities in the entire file** — that's not real
people's data changing over time, that's a demographic field being re-randomized on
every duplicate write. `borrower_id` is treated as the only trustworthy key; for
descriptive fields I take the most-recently-updated row per borrower as a best-effort
"current" snapshot, but I've flagged every borrower row `demographic_fields_low_trust
= TRUE`. **Any geography or name-based cut later in this project should be read as
directional, not authoritative** — this is exactly the kind of thing Part 2 (Geography)
asks us to be suspicious of.

**Accounts (`accounts.csv`).** This one is genuinely clean — real unique key, no
duplicate rows. 455 accounts (1.5%) have a null `borrower_id`; I kept these accounts
(they still have real calls/payments against them) but flagged them as
`is_orphan_account` so borrower-level rollups can exclude them deliberately instead of
silently losing them. `accounts.csv` is designated the **single source of truth for
account→borrower mapping** for the whole project (see account_status_history below for
why this matters).

**Agents (`agents.csv`) — the biggest identity problem in the dataset.** 30,000 rows
but only 1,000 distinct `agent_id`. That's not a slowly-changing-dimension history —
there's no snapshot date, and `employee_code`, `team`, `vendor_id`, `status`, and
`joined_at` all vary almost randomly across the ~30 rows per agent (one agent_id
carried 15+ different employee codes and touched 13 of 15 vendors). `agent_name` is
drawn from a pool of only 10 names, so it can't be used to cross-check identity either.
**Decision:** `agent_id` is the only real identity. For every other attribute I take
the statistical mode across that agent's rows (best guess of the "true" value);
`joined_at` takes the minimum (earliest plausible join date). I kept
`n_distinct_employee_codes` on the golden table specifically so anyone doing
agent-tenure or vendor-attribution analysis downstream can see how much noise sits
behind a given agent's resolved profile and discount accordingly — this directly
affects the "Agent" and "Agent tenure" driver investigation Part 2 asks for.

**Vendor telephony (`vendor_telephony.csv`).** Clean, 15 rows, no duplicates — but
`vendor_id` is a contract/account-level id, not a brand-level one: the 15 vendor_ids
map to only **5 real telephony brands** (Airtel, Twilio, Exotel, Knowlarity,
TataTele), each split across 2-5 vendor_ids. I added a `vendor_brand` column so
"which telephony vendor performs best" doesn't get fragmented across a brand's own
multiple contracts.

**Campaigns (`campaigns.csv`).** Clean, 120 rows, no duplicates — but `campaign_name`
is a coarse theme label, not a stable campaign definition: there are only 5 distinct
names, and each one spans all 5 channels, up to 4 strategy versions, and all 5 target
definitions. Grouping by `campaign_name` alone would silently blend, for example, a
WhatsApp NPA_RECOVERY campaign with a Field-visit NPA_RECOVERY campaign that has a
completely different targeting rule. I kept `campaign_id` as the grain and expose
name/channel/strategy_version/target_definition as separate columns so any rollup
has to choose its grouping deliberately.

## 4. Deduplication logic

Two distinct kinds of "duplicate" showed up repeatedly, and they need different fixes:

1. **Exact ingestion retries** — same row, byte-for-byte, more than once. Found in
   `borrowers` (600), `calls` (2,542 rows / 1,271 pairs), `whatsapp_events` (600), and
   `payments` (972 rows / 486 pairs). Fix: `SELECT DISTINCT`, keep one copy. Simple and
   safe because there's no ambiguity about what happened.

2. **ID collisions** — the *same ID* attached to two rows that are otherwise
   different (different timestamp, or different account/amount/status entirely). Found
   in `calls` (79 colliding `call_id`s) and `payments` (14 colliding `payment_id`s).
   These are **not** duplicates to drop — they're two different real events that
   happen to share an identifier, most likely because the ID generator has a narrow
   ID space relative to row count. I don't guess which one is "the real" event; I keep
   both and give them a surrogate key (`call_sk` / `payment_sk`), flagged with
   `is_colliding_call_id` / `is_colliding_payment_id` so a downstream analyst can see
   exactly how many rows this affected (79 and 14 respectively — small, but real).

I also checked `payment_reference` (the external transaction reference) as a possible
dedup key and rejected it: only 20,821 distinct values across 25,118 non-null rows.
That ~4,300-collision rate is almost exactly what you'd expect from randomly assigning
25,000 rows into a ~70,000-value ID space (birthday-paradox expectation ≈4,460) — so
this reads as a fragile, small ID space, not evidence of real duplicate payments. I'm
flagging this as **Correlation / Hypothesis, not Fact**, and did not use
`payment_reference` for any dedup or attribution logic.

## 5. Missing-data treatment

- `accounts.borrower_id`: 455 nulls (1.5%) → kept, flagged `is_orphan_account`, not
  imputed. Fabricating a borrower link would create false certainty where none exists.
- `field_visits.scheduled_at`: 250 nulls (~1%) → kept as NULL, flagged
  `was_unscheduled_visit`. This plausibly represents genuine walk-in/ad-hoc visits
  rather than missing data, so imputing a schedule time would misrepresent the record.
- `payments.payment_reference`, `calls.agent_id`, `call_attempts.vendor_id`: low
  single-digit % nulls, left as-is — no business decision depends on filling them.

No numeric field (amounts, DPD, durations) was imputed anywhere in the pipeline.
Where a value is missing, it stays missing; I did not want a synthetic fill value
quietly propagating into a recovery or ROI number three steps downstream.

## 6. Timestamp treatment

`accounts`, `calls`, and `agent_sessions` each carry their own `timezone` column,
roughly evenly split across UTC / Asia/Kolkata / Asia/Dubai. Event timestamps are
stored **in that local timezone**, not normalized — so any hour-of-day or
day-of-week analysis on the raw `event_at` would misclassify roughly two-thirds of
events. I computed explicit `event_at_utc` columns for these three tables.

**Limitation, stated plainly:** `call_attempts`, `call_dispositions`,
`whatsapp_events`, `sms_events`, `field_visits`, `promises_to_pay`, `payments`,
`complaints`, and `account_status_history` do **not** carry their own timezone field,
and don't share a join key back to `vendor_telephony` for all of them either
(`payments`/`whatsapp`/`sms` use a `provider_id` from a different namespace than
telephony's `vendor_id`). Rather than guess a timezone conversion for these, I left
`event_at` as-is and am treating it as an **assumption of UTC**, not a verified fact.
This is called out again in the Data Quality Report as an open limitation — any
calling-time analysis on `call_attempts`/`call_dispositions` should be treated as
approximate.

`account_status_history.recorded_at` deserves a specific note: I checked
`recorded_at - event_at` across all 60,000 rows and found it's essentially random
noise within ±24 hours of `event_at`, with **50.3% of rows showing `recorded_at`
before `event_at` even happened** — which is operationally impossible for a real
system-recording timestamp. I'm treating `recorded_at` as unreliable and unusable for
lineage/lag analysis; `event_at` is the only trustworthy timestamp in that table.

## 7. Payment attribution

This is the decision that most directly affects whether the reported 11% improvement
holds up, so I want to be explicit about it here (full quantification comes in the
Data Quality Report and Part 3 write-up).

`payments.payment_status` has four values: SUCCESS, FAILED, PENDING, REVERSED. Summed
across all statuses, raw payment amount over the period is **₹191.7 Cr**. Restricted
to `SUCCESS` only, it's **₹131.6 Cr** — a 31% gap. If "recovery" is being reported as
the sum of all payment rows regardless of status, that alone is a materially different
number from actual cash collected.

I checked whether `REVERSED` rows are traceable clawbacks of a specific prior
`SUCCESS` payment (same account + same amount, reversed row dated later) — in every
case checked, they are not; `REVERSED` behaves as an independent event with no
identifiable parent transaction. I also checked whether the SUCCESS/FAILED/
PENDING/REVERSED **mix shifts month to month** — it doesn't; SUCCESS sits in a flat
67-72% band from January through August. That's a useful negative result: a shifting
payment-status mix is **not**, on its own, the explanation for a reported
month-on-month improvement. (Full trend analysis, including whether the 11% figure
itself holds up, is Part 3 — this is flagged here because it's fundamentally a
payment-attribution decision made in the golden layer.)

**Golden-layer rule:** `is_recovered_cash = (payment_status = 'SUCCESS')`. All rows
are kept in `golden_payments` (for funnel/cost-per-contact analysis), but any
recovery or recovery-rate metric built on top of this table defaults to
SUCCESS-only unless explicitly stated otherwise.

## 8. Historical changes / overwrite handling

`account_status_history` is the one table explicitly built to log every status change
for an account over time — but its `borrower_id` column is **100% inconsistent** with
`accounts.csv` (checked on all 60,000 rows: every single one mismatches). I discarded
that column entirely and re-derived `borrower_id` via a join to `golden_accounts` on
`account_id`, which is the actually-reliable key. Status values themselves are
non-monotonic for a given account (PAID → CLOSED → WRITEOFF → CLOSED → PAID →
DELINQUENT in one real example) — this looks like injected noise rather than a
realistic account lifecycle, so I did **not** attempt to infer a "true" status
timeline from this table; it's kept as a raw event log with the caveat that
"current status" derived from it should be treated as approximate, and
`accounts.status` (the account table's own snapshot field) is the preferred source
for current-state questions.

## 9. Exclusion rules (summary)

| Rule | Rows affected | Rationale |
|---|---:|---|
| Drop exact full-row duplicates | ~3,443 rows across borrowers/calls/whatsapp/payments | Ingestion retries, zero information loss |
| Keep colliding IDs, add surrogate key | 79 (calls) + 14 (payments) | Different real events; can't tell which is "correct" so keep both |
| Discard `account_status_history.borrower_id` | 60,000 rows (column-level) | 100% inconsistent with source-of-truth accounts table |
| Exclude non-SUCCESS payments from "recovered cash" by default | ~10,486 of 25,014 payment rows | FAILED/PENDING/REVERSED are not collected cash |
| Flag (not drop) orphan accounts | 455 | No borrower link, but real operational data |
| Flag (not drop) low-trust borrower demographics | 11,015 (all borrower rows) | Fields shown to be randomized noise, not real profile data |

Nothing was dropped purely because it looked messy. Every exclusion above is
row-count-quantified and reversible — the raw tables are untouched and every golden
table can be rebuilt from `/sql` end to end.

## 10. Key assumptions (stated explicitly, for anyone auditing this)

1. Where an agent/borrower attribute is noisy across duplicate rows, the *mode* (or
   most recent update) is a reasonable best-effort resolution — not a claim of ground
   truth.
2. Tables without their own timezone field are assumed UTC.
3. `payment_reference` collisions are assumed to be a narrow-ID-space artifact, not
   evidence of duplicate real-world transactions (classified as Hypothesis, not Fact).
4. `REVERSED` payments are treated as independent events, not linked reversals of a
   specific prior payment, because no reliable linking key was found.
5. `accounts.csv` and `accounts.status` are the source of truth for
   account→borrower mapping and current account state, overriding any conflicting
   value found in event-level tables.

## Files delivered for this part

- `sql/00_load_raw.sql` through `sql/08_golden_remaining_tables.sql` — full,
  reproducible transformation logic (also doubles as the start of the SQL Repository
  deliverable)
- `run_pipeline.py` — runs all SQL in order, prints impact checks, exports every
  golden table to CSV
- `golden/*.csv` — the 17 golden tables
- `docs/raw_to_golden_funnel.csv` — the row-count funnel in machine-readable form
- `profile_raw.py` / `profile_summary.csv` — the raw-table profiling that this
  document's findings are based on
