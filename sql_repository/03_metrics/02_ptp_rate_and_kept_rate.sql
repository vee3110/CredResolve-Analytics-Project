-- PTP rate & PTP-kept rate, monthly.
--
-- PTP rate = of accounts that were an RPC (right party contact) this month, how many
-- resulted in a promise-to-pay disposition.
--
-- PTP-KEPT RATE - this is a redefinition, not the source field, and here's why:
-- promises_to_pay.ptp_status (KEPT/BROKEN/OPEN/CANCELLED) is self-reported, almost
-- certainly by the agent or a batch process. We tested it against actual payment
-- evidence: of PTPs marked 'KEPT', only 3.1% have a matching SUCCESS payment within
-- -3/+7 days of the promised date. Of PTPs marked 'BROKEN', 2.2% have one too - i.e.
-- the self-reported label is statistically almost UNCORRELATED with what actually
-- happened to the money. We do not trust ptp_status for a kept-rate metric.
--
-- Instead: PTP-kept (evidence-based) = a promise where a SUCCESS payment for that
-- account actually landed within a -3/+7 day window of the promised_date. This ties
-- the metric to real cash movement instead of a self-reported status flag.

CREATE OR REPLACE VIEW metric_ptp_rate_monthly AS
WITH rpc AS (
    -- Uses the same corrected RPC definition as 01_contact_and_rpc_rate.sql:
    -- call was ANSWERED AND its own disposition is not WRONG_NUMBER/NO_CONTACT.
    SELECT DISTINCT c.account_id, strftime(c.event_at_utc, '%Y-%m') AS month
    FROM golden_calls c
    JOIN golden_call_dispositions d ON d.call_id = c.call_id
    WHERE c.call_status = 'ANSWERED'
      AND d.disposition_code_raw NOT IN ('WRONG_NUMBER', 'NO_CONTACT')
),
ptp_made AS (
    SELECT DISTINCT d.account_id, strftime(d.event_at_assumed_utc, '%Y-%m') AS month
    FROM golden_call_dispositions d
    WHERE d.disposition_group = 'PTP'
)
SELECT
    r.month,
    COUNT(DISTINCT r.account_id) AS accounts_rpc,
    COUNT(DISTINCT p.account_id) AS accounts_ptp,
    ROUND(100.0 * COUNT(DISTINCT p.account_id) / NULLIF(COUNT(DISTINCT r.account_id),0), 2) AS ptp_rate_pct
FROM rpc r
LEFT JOIN ptp_made p ON r.account_id = p.account_id AND r.month = p.month
GROUP BY r.month
ORDER BY r.month;

CREATE OR REPLACE VIEW metric_ptp_kept_rate_monthly AS
WITH ptp_evidence AS (
    SELECT
        ptp_id,
        account_id,
        promised_amount,
        promised_date,
        ptp_status AS self_reported_status,
        strftime(promised_date, '%Y-%m') AS month,
        EXISTS (
            SELECT 1 FROM golden_payments pay
            WHERE pay.account_id = promises_to_pay.account_id
              AND pay.is_recovered_cash
              AND pay.event_at BETWEEN promises_to_pay.promised_date - INTERVAL '3 day'
                                    AND promises_to_pay.promised_date + INTERVAL '7 day'
        ) AS kept_evidence_based
    FROM golden_promises_to_pay AS promises_to_pay
    WHERE ptp_status IN ('KEPT','BROKEN')   -- exclude OPEN (not yet due) and CANCELLED (withdrawn)
)
SELECT
    month,
    COUNT(*) AS ptps_resolved,
    SUM(CASE WHEN self_reported_status = 'KEPT' THEN 1 ELSE 0 END) AS self_reported_kept,
    SUM(CASE WHEN kept_evidence_based THEN 1 ELSE 0 END) AS evidence_based_kept,
    ROUND(100.0 * SUM(CASE WHEN self_reported_status='KEPT' THEN 1 ELSE 0 END) / COUNT(*), 2) AS self_reported_kept_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN kept_evidence_based THEN 1 ELSE 0 END) / COUNT(*), 2) AS evidence_based_kept_rate_pct
FROM ptp_evidence
GROUP BY month
ORDER BY month;
