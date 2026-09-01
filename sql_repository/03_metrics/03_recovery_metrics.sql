-- Recovery rate, recovery per account, recovery per agent-hour - monthly.
--
-- RECOVERY RATE - redefined. If the business's reported number sums payment amount
-- across ALL payment_status values, it is materially inflated (see Golden Dataset
-- doc: raw all-status total is Rs 191.7 Cr vs SUCCESS-only Rs 131.6 Cr, a 31% gap).
-- Our recovery rate = SUM(SUCCESS amount in month) / SUM(outstanding_amount of
-- accounts targeted that month) - a stock-based, cash-only definition.

CREATE OR REPLACE VIEW metric_recovery_monthly AS
WITH targeted AS (
    SELECT DISTINCT account_id, strftime(target_date, '%Y-%m') AS month
    FROM golden_daily_targeting
),
targeted_outstanding AS (
    SELECT t.month, SUM(a.outstanding_amount) AS total_outstanding, COUNT(DISTINCT t.account_id) AS n_accounts
    FROM targeted t JOIN golden_accounts a ON t.account_id = a.account_id
    GROUP BY t.month
),
recovered AS (
    SELECT strftime(event_at, '%Y-%m') AS month, SUM(amount) AS recovered_amount
    FROM golden_payments WHERE is_recovered_cash
    GROUP BY 1
)
SELECT
    o.month,
    o.n_accounts,
    o.total_outstanding,
    COALESCE(r.recovered_amount, 0) AS recovered_amount,
    ROUND(100.0 * COALESCE(r.recovered_amount,0) / NULLIF(o.total_outstanding,0), 3) AS recovery_rate_pct,
    ROUND(COALESCE(r.recovered_amount,0) / NULLIF(o.n_accounts,0), 0) AS recovery_per_account
FROM targeted_outstanding o
LEFT JOIN recovered r ON o.month = r.month
ORDER BY o.month;

-- Recovery per agent-hour: SUM(recovered) / SUM(logged session hours) that month.
-- Caveat kept in the column name and in the notebook: this is an EFFICIENCY ratio,
-- not a causal claim - a payment in month M can be the result of contact made in
-- month M-1 (PTP lag), so don't read this as "agents directly generated X per hour".
CREATE OR REPLACE VIEW metric_recovery_per_agent_hour_monthly AS
WITH hours AS (
    SELECT strftime(login_at_utc, '%Y-%m') AS month, SUM(session_hours) AS agent_hours
    FROM golden_agent_sessions
    GROUP BY 1
),
recovered AS (
    SELECT strftime(event_at, '%Y-%m') AS month, SUM(amount) AS recovered_amount
    FROM golden_payments WHERE is_recovered_cash
    GROUP BY 1
)
SELECT
    h.month,
    ROUND(h.agent_hours, 0) AS agent_hours_logged,
    COALESCE(r.recovered_amount, 0) AS recovered_amount,
    ROUND(COALESCE(r.recovered_amount, 0) / NULLIF(h.agent_hours, 0), 0) AS recovery_per_agent_hour
FROM hours h
LEFT JOIN recovered r ON h.month = r.month
ORDER BY h.month;

-- NOTE ON "COST PER RUPEE RECOVERED": deliberately not implemented here. The dataset
-- does not include any cost table - no agent wage/cost-per-hour, no per-minute
-- telephony cost, no per-message WhatsApp/SMS cost. Computing a real cost-per-rupee
-- figure from this data would require inventing unit costs, which we do NOT want to
-- bury inside a SQL view as if it were a data-derived fact. This is handled explicitly,
-- with assumptions stated, in the Analysis Notebook / Part 4 recommendation instead.
