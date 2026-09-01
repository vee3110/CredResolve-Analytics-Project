# Data Quality Report — Collections Analytics

This report answers the seven forensic questions the brief asks us to investigate
(Part 2, items A-G). For each one I state: what I checked, what I found, how I'm
classifying the finding (**Fact / Strong Evidence / Correlation / Hypothesis**, per the
brief's own framework), and what the business impact is if the issue isn't corrected.

Not every hypothesis panned out — I've kept the "checked, ruled out" findings in here
too, because knowing what *isn't* driving the numbers is as useful as knowing what is,
and it's evidence I did the check rather than only reporting the interesting parts.

---

## A. Duplicate payments — CONFIRMED, but small in isolation

**Method:** compared full-row duplicates on `payment_id`, then separately checked
whether the same `payment_id` was ever reused across two genuinely different
transactions (different account/amount/status).

**Finding:**
- 486 pairs (972 rows) are exact, byte-for-byte duplicate payment records — classic
  double-ingestion. **Fact.**
- 14 pairs (28 rows) are worse: the same `payment_id` is attached to two *different*
  real transactions (different account, different amount). This isn't a duplicate to
  drop — it's an ID collision that could cause one of the two real payments to be
  silently overwritten if a system does a naive upsert by `payment_id`. **Fact.**

**Business impact:** on its own, dropping the 486 duplicate pairs removes ~₹3.7 Cr of
double-counted "recovery" (486 duplicate rows × avg ₹75,600/row ≈ ₹3.67 Cr) — real,
but not close to explaining an 11-percentage-point swing. The 14 collision rows are a
smaller number but a more serious *system* risk: a naive dedup-by-ID process could
have quietly discarded a real payment.

**Treatment:** exact duplicates dropped (keep 1 of each pair). Colliding IDs kept, both
sides, tagged with a surrogate key (`payment_sk`) so no real money is deleted.

---

## B. Attribution errors — CONFIRMED, and this one is bigger than it looks

**Method:** for every SUCCESS payment, I looked for calls to the same account in the 7
days before the payment and counted how many *distinct campaigns* touched that account
in that window. I also compared "credit the last campaign touched" vs. "credit the
first campaign touched" to see how often the answer would change depending on
attribution rule.

**Findings:**
- Of 17,545 SUCCESS payments, only **1,585 (9%)** have *any* campaign-linked call in
  the 7 days before payment. **The other 91% of successful payments have no traceable
  campaign touch at all in that window.** That means any campaign-level "recovery" or
  "channel ROI" number the business reports is necessarily built on well under 1 in 10
  actual recovered payments — the rest of recovery (WhatsApp/SMS/field-visit-driven, or
  simply un-attributable) doesn't show up anywhere in a campaign rollup. **Fact.**
- Of the 1,585 payments that *do* have a traceable campaign touch, 70 (4.4%) were
  touched by more than one distinct campaign in the window, and the last-touch vs.
  first-touch attribution rule disagreed on the credited campaign in exactly those 70
  cases. **Fact**, but small in absolute count.

**Business impact:** this is the more consequential attribution problem of the two —
not the ambiguity, but the *coverage gap*. If leadership is deciding "invest ₹10 Cr
in the campaign/channel that looks best," and that ranking is built on <10% of actual
recovered payments, the ranking itself is unreliable regardless of which attribution
rule is used on the touched subset. This directly affects Part 3 (channel conversion)
and Part 4 (the investment decision) — I'm treating any campaign-level recovery number
as **indicative, not authoritative**, for the rest of this project.

**Treatment:** no campaign-attribution column was added to `golden_payments` — I
deliberately did not force a last-touch (or any other) attribution model into the
golden layer, because doing so would hide the 91% coverage gap behind a single number
that looks precise. Channel/campaign-level recovery conclusions elsewhere in this
project are explicitly caveated with this coverage limitation.

---

## C. Timezone problems — CONFIRMED

**Method:** checked whether `event_at` in `calls`/`accounts`/`agent_sessions` is
already UTC-normalized or expressed in the table's own `timezone` column.

**Finding:** timestamps are stored in local time as named by the `timezone` column,
split roughly evenly across UTC / Asia/Kolkata (+5:30) / Asia/Dubai (+4:00) — about
two-thirds of calls are in a non-UTC timezone. Any hour-of-day or day-of-week
"best time to call" analysis run directly on raw `event_at` would misclassify roughly
two-thirds of calls into the wrong hour or, near midnight boundaries, the wrong day
entirely. **Fact** (directly measured from the `timezone` column and offsets).

**Business impact:** this directly affects the "Calling time" driver investigation
Part 2 of the assignment specifically calls out, and any "call between 6-8pm for best
answer rate" recommendation built on unconverted local timestamps would be wrong for
most of the book.

**Treatment:** `event_at_utc` computed explicitly for `calls`, `accounts`, and
`agent_sessions` (the three tables that carry their own timezone field).
**Limitation:** `call_attempts`, `call_dispositions`, `payments`, `whatsapp_events`,
`sms_events`, `field_visits`, `promises_to_pay`, `complaints`, and
`account_status_history` do not carry a timezone field and have no reliable join back
to one (their `vendor_id`/`provider_id` values don't consistently map to
`vendor_telephony`). These are left as assumed-UTC — an explicit **assumption**, not a
verified fact, and flagged as an open gap rather than silently resolved.

---

## D. Vendor / disposition-code mapping changes — CHECKED, NOT CONFIRMED

**Method:** checked whether `call_status` mix differs by vendor `schema_version`
(v1/v2/v3) or drifts over calendar time; checked whether `disposition_version`
(legacy/v1/v2) corresponds to different disposition code sets or a code migration
over time.

**Finding:** **No material effect found on either count.**
- `call_status` mix (ANSWERED/BUSY/FAILED/NO_ANSWER/VOICEMAIL) is flat at ~20% each
  across all three schema versions and flat across every month Jan-Aug.
- All three `disposition_version` values use the exact same 9 disposition codes — this
  column does not represent an actual code migration.
- However: `PTP` and `PROMISE_TO_PAY` genuinely are two different string codes for the
  same underlying event, coexisting throughout the whole period at a stable ~50/50
  split with no time trend. This isn't a migration (nothing changed over time to
  explain a reported improvement) but it **is** a live measurement risk: a PTP-rate
  query that filters on only one of the two strings undercounts true PTP rate by
  roughly half, every single month, uniformly — this wouldn't create a fake trend, but
  it would make any absolute PTP-rate number wrong.

**Classification:** the "vendor code migration" hypothesis is **ruled out**
(Strong Evidence against it, based on flat distributions across version and time). The
PTP/PROMISE_TO_PAY synonym issue is **Fact**.

**Treatment:** `disposition_group` column normalizes `PTP` and `PROMISE_TO_PAY` into a
single value in `golden_call_dispositions`. No time-based correction was needed since
there's no drift to correct for.

---

## E. Agent identity problems — CONFIRMED, this is the single biggest issue in the dataset

**Method:** compared `agent_id` cardinality against row count in `agents.csv`; checked
whether `employee_code`/`team`/`vendor_id`/`status`/`joined_at` are stable for a given
`agent_id`.

**Finding:** 30,000 rows resolve to only 1,000 distinct `agent_id` values — roughly 30
rows per real agent, with **no snapshot date** to say which row is current. Sampled
manually: one agent_id showed 15+ different `employee_code` values, touched 13 of 15
vendors, and had a `joined_at` spread of ~650 days across its own rows. `agent_name`
is drawn from a pool of only 10 names shared across all 1,000 agents, so name can't be
used to sanity-check identity either. **Fact.**

**Business impact:** this is exactly the failure mode the brief warns about under
"Agent" and "Agent tenure" as investigation dimensions. Any query that joins
`employee_code` to another table to trace a specific person's performance, tenure, or
vendor assignment will get an essentially random result. Team-level and
vendor-level agent rollups (e.g. "Team T1 recovers more than Team T3") are only as
reliable as the mode-resolution applied in the golden layer — directionally useful,
not precise.

**Treatment:** `agent_id` is the only identity trusted. Team/vendor/status/name
resolved via statistical mode per agent; `joined_at` via minimum. `n_raw_rows` and
`n_distinct_employee_codes` kept on `golden_agents` so downstream analysis can see
(and discount for) how much noise sits behind any given agent's resolved profile.

---

## F. Portfolio mix changes — CHECKED, NOT CONFIRMED

**Method:** checked risk_segment / loan_type / DPD-bucket mix two ways: (1) of accounts
*opened* each month (acquisition mix, Jan 2024 - Nov 2025), and (2) of accounts
*actually contacted* each collection month (Jan-Aug 2026, the period the 11% claim
covers) — the second is the one that actually matters for the reported metric.

**Finding:** **Flat on both counts.** Risk segment share of accounts opened per month
holds within a 23-27% band for all four segments across the full 23-month acquisition
window — no trend. Risk segment and DPD-bucket share of accounts actually *contacted*
during Jan-Aug 2026 is similarly flat (e.g. DPD_1_30 share sits at 34-38% every single
month). There is no evidence the business started working a materially easier or
harder portfolio partway through the year. **Strong Evidence against** a portfolio-mix
explanation for the reported 11% change.

**Business impact:** this rules out one of the more common false explanations for a
misleading recovery trend (Simpson's-paradox-via-portfolio-mix). It means if the 11%
figure is wrong, portfolio mix isn't why — the explanation has to be somewhere else
(payment-status definition, attribution, targeting/channel shift, etc.).

**Treatment:** no correction needed; documented as a checked-and-ruled-out hypothesis
so it isn't re-litigated in Part 3.

---

## G. Denominator manipulation — CHECKED, NOT CONFIRMED (at the population level)

**Method:** checked whether the size of the targeted account population
(`daily_targeting`) shrinks over time in a way that could inflate a rate metric by
quietly dropping hard/unsuccessful accounts from the denominator; checked
converted-accounts-per-month against targeted-accounts-per-month.

**Finding:** distinct accounts targeted per month is flat, ranging 5,160-5,800 every
full month (Jan-Jul 2026; August is a partial month by data-cutoff, excluded from this
comparison). Converted-account counts per month (462, 349, 474, 432, 452, 432, 482)
imply a targeted→converted rate drifting from roughly **6.8% in February to 8.5% in
July** — a real movement, but the *denominator itself* (population size) is not
shrinking or being curated to produce this. **Strong Evidence against** denominator
manipulation as the mechanism; the movement in the rate looks like a genuine change in
either targeting quality or conversion behavior, not an artifact of who's included in
the count.

**Business impact:** this is actually a constructive finding — it means the ~6.8%→8.5%
movement in targeted-to-converted rate is a legitimate area to dig into further in
Part 3 (is it a real operational improvement, a targeting-strategy change, or a cohort
effect?), not an artifact to dismiss.

**Treatment:** no correction applied; flagged as a genuine signal worth carrying into
the statistical investigation (Part 3) and counterfactual (Part 4), rather than
something to explain away here.

---

## Summary table

| # | Issue | Status | Classification | Business impact |
|---|---|---|---|---|
| A | Duplicate payments | Confirmed | Fact | ~₹3.7 Cr double-counted; 14-row ID-collision risk |
| B | Attribution errors | Confirmed (bigger than expected) | Fact | 91% of successful payments have no traceable campaign touch — campaign-level ROI numbers are built on <10% of recovery |
| C | Timezone problems | Confirmed | Fact | ~2/3 of calls misclassified by hour/day if unconverted |
| D | Vendor/disposition code changes | Ruled out (migration); PTP/PROMISE_TO_PAY synonym confirmed | Strong Evidence (D) / Fact (synonym) | PTP-rate understated ~2x if only one code string is filtered |
| E | Agent identity problems | Confirmed — largest issue found | Fact | Agent/team/vendor rollups are directional only, not precise |
| F | Portfolio mix changes | Ruled out | Strong Evidence | Not the explanation for the reported 11% |
| G | Denominator manipulation | Ruled out | Strong Evidence | Targeted→converted rate movement (6.8%→8.5%) looks real, not an artifact |

**Read together, the two findings that matter most for the 11% question (Part 3) are
the payment-status definition gap (₹191.7 Cr all-status vs. ₹131.6 Cr SUCCESS-only,
documented in the Golden Dataset write-up) and the attribution coverage gap (B above).
Portfolio mix and denominator manipulation are checked and cleared — they are not
where the story is.**
