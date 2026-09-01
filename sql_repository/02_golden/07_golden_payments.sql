-- 07_golden_payments.sql
--
-- This is the most important table in the whole assignment - it decides whether the
-- reported 11% recovery improvement is real.
--
-- Findings:
--  1. 25,500 raw rows, 25,000 distinct payment_id. 486 pairs (972 rows) are exact
--     full-row duplicates - plain retry/ingestion duplicates, safe to drop.
--     14 pairs (28 rows) are a genuine payment_id COLLISION: the same payment_id is
--     attached to two rows with different account_id/amount/status. These are two
--     different real payments that happened to get the same ID. We keep both and give
--     them a surrogate key rather than deleting real money.
--  2. payment_reference (the external transaction id) is NOT a reliable key either:
--     20,821 distinct values across 25,118 non-null rows, i.e. ~4,300 references are
--     reused. The reference pool only spans ~70,000 possible values across ~25,000
--     rows, which is almost exactly the collision count you'd expect from pure random
--     assignment (~4,460 expected via the birthday paradox). Classification: this
--     looks like a fragile identifier, not evidence of a real duplicate-payment
--     process - CORRELATION at best, not FACT. We do not use payment_reference for
--     dedup or attribution.
--  3. payment_status has four values: SUCCESS / FAILED / PENDING / REVERSED. FAILED and
--     PENDING amounts are large (FAILED ~15% of rows, PENDING ~10%) - if the business's
--     reported recovery number sums ALL payment rows regardless of status, that alone
--     would overstate cash actually collected by roughly 30%+. We checked whether
--     REVERSED rows are linked to a specific prior SUCCESS row (same account + amount) -
--     they are not, in any of the rows checked - so REVERSED behaves as an independent
--     event, not a traceable clawback of a specific transaction.
--  4. We checked the SUCCESS/FAILED/PENDING/REVERSED mix month by month: it is flat
--     (SUCCESS sits between 67-72% every month, Jan through Aug). So a shifting status
--     mix is NOT, on its own, the explanation for a reported MoM improvement - this is
--     an important ruled-out hypothesis, documented in the Data Quality Report.
--
-- Decision: "recovered amount" in the golden layer = SUM(amount) WHERE payment_status =
-- 'SUCCESS' only. FAILED/PENDING/REVERSED are kept in the table (for funnel and cost
-- analysis) but excluded from any recovery/recovery-rate metric by default.

CREATE OR REPLACE TABLE stg_payments_nodupe AS
SELECT DISTINCT * FROM raw_payments;

CREATE OR REPLACE TABLE golden_payments AS
SELECT
    payment_id,
    payment_id || '-' || CAST(dup_seq AS VARCHAR) AS payment_sk,
    (dup_seq > 1) AS is_colliding_payment_id,
    account_id,
    borrower_id,
    payment_reference,
    amount,
    payment_status,
    (payment_status = 'SUCCESS') AS is_recovered_cash,
    payment_method,
    provider_id,
    event_at
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY payment_id ORDER BY event_at) AS dup_seq
    FROM stg_payments_nodupe
);

SELECT
    (SELECT COUNT(*) FROM raw_payments) AS raw_rows,
    (SELECT COUNT(*) FROM stg_payments_nodupe) AS after_exact_dedupe,
    (SELECT COUNT(*) FROM golden_payments) AS golden_rows,
    (SELECT COUNT(*) FROM golden_payments WHERE is_colliding_payment_id) AS colliding_id_rows_kept,
    (SELECT ROUND(SUM(amount),0) FROM raw_payments) AS raw_total_amount_all_status,
    (SELECT ROUND(SUM(amount),0) FROM golden_payments WHERE is_recovered_cash) AS golden_recovered_cash_only;
