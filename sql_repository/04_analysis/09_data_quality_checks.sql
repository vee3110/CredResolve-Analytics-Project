 09_data_quality_checks.sql
Investigation queries used to support docs/02_data_quality_report.md (Part 2, items A:G).
These queries are for data quality checks and are not part of the golden layer build.

 A. Duplicate payments: already handled in the golden layer (07_golden_payments.sql).
    Estimate the potential impact of duplicate payments:
SELECT
    486 * (SELECT AVG(amount) FROM golden_payments) AS approx_double_counted_amount;

B. Attribution errors: check campaign touch coverage for successful payments
WITH pay AS (
    SELECT payment_sk, account_id, event_at
    FROM golden_payments
    WHERE is_recovered_cash
),
touches AS (
    SELECT
        p.payment_sk,
        COUNT(DISTINCT c.campaign_id) AS n_campaigns_touched
    FROM pay p
    JOIN golden_calls c
      ON c.account_id = p.account_id
     AND c.event_at_utc BETWEEN p.event_at - INTERVAL '7 day' AND p.event_at
     AND c.campaign_id IS NOT NULL
    GROUP BY p.payment_sk
)
SELECT
    (SELECT COUNT(*) FROM pay) AS total_success_payments,
    (SELECT COUNT(*) FROM touches) AS payments_with_any_campaign_touch,
    (SELECT COUNT(*) FROM touches WHERE n_campaigns_touched > 1) AS payments_with_ambiguous_attribution;

C. Timezone issues: share of calls recorded in each timezone
SELECT
    event_timezone,
    COUNT(*),
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM golden_calls
GROUP BY 1;

D. Vendor and disposition mapping: compare call status across schema versions
    The distribution should stay fairly consistent unless there was an actual change.
SELECT
    v.schema_version,
    c.call_status,
    COUNT(*) AS n
FROM golden_calls c
JOIN golden_vendor_telephony v
  ON c.vendor_id = v.vendor_id
GROUP BY 1, 2
ORDER BY 1, 2;

E. Agent identity: quantify duplicate and inconsistent agent records
SELECT
    (SELECT COUNT(*) FROM raw_agents) AS raw_rows,
    (SELECT COUNT(DISTINCT agent_id) FROM raw_agents) AS real_agents,
    (SELECT ROUND(AVG(n_distinct_employee_codes), 1) FROM golden_agents) AS avg_employee_codes_per_agent;

F. Portfolio mix: risk segment share among accounts contacted each month
SELECT
    strftime(c.event_at_utc, '%Y-%m') AS month,
    a.risk_segment,
    COUNT(DISTINCT c.account_id) AS n
FROM golden_calls c
JOIN golden_accounts a
  ON c.account_id = a.account_id
GROUP BY 1, 2
ORDER BY 1, 2;

G. Denominator checks: compare targeted accounts with converted accounts each month
WITH targeted AS (
    SELECT DISTINCT
        account_id,
        strftime(target_date, '%Y-%m') AS month
    FROM golden_daily_targeting
),
converted AS (
    SELECT DISTINCT
        account_id,
        strftime(event_at, '%Y-%m') AS month
    FROM golden_payments
    WHERE is_recovered_cash
)
SELECT
    t.month,
    COUNT(DISTINCT t.account_id) AS targeted_accounts,
    COUNT(DISTINCT c.account_id) AS converted_accounts,
    ROUND(
        100.0 * COUNT(DISTINCT c.account_id) / COUNT(DISTINCT t.account_id),
        2
    ) AS conversion_pct
FROM targeted t
LEFT JOIN converted c
  ON t.account_id = c.account_id
 AND t.month = c.month
GROUP BY 1
ORDER BY 1;