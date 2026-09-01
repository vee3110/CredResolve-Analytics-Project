-- Contact rate & Right-Party-Contact (RPC) rate, monthly, account-level.
--
-- Why account-level, not call-level: the business's naive "contact rate" is very
-- likely answered-calls / total-calls, which inflates whenever a predictive dialer
-- makes repeat attempts on the same easy-to-reach account. Defining it per account
-- (was this account reached at all this month, yes/no) is a fairer denominator.
--
-- RPC definition - iterated once already. First attempt joined "any disposition
-- exists for this account this month" as a proxy for real contact; that produced RPC
-- rates over 100% of contact rate, which is a logical impossibility, so it was wrong.
-- Root cause: dispositions are logged at roughly EQUAL volume across every call_status
-- (ANSWERED, NO_ANSWER, BUSY, FAILED, VOICEMAIL all show ~7,000 linked dispositions) -
-- i.e. a disposition code gets attached regardless of whether the call actually
-- connected. So "a disposition exists" is not a valid signal of real contact on its
-- own. Fixed definition: RPC requires BOTH call_status = 'ANSWERED' on the specific
-- call AND its disposition code is not WRONG_NUMBER / NO_CONTACT (those two codes
-- explicitly mean "answered but not the right person / no real conversation").

CREATE OR REPLACE VIEW metric_contact_rpc_monthly AS
WITH targeted AS (
    SELECT DISTINCT account_id, strftime(target_date, '%Y-%m') AS month
    FROM golden_daily_targeting
),
answered AS (
    SELECT DISTINCT account_id, strftime(event_at_utc, '%Y-%m') AS month
    FROM golden_calls WHERE call_status = 'ANSWERED'
),
call_level_rpc AS (
    SELECT c.call_sk, c.account_id, c.event_at_utc
    FROM golden_calls c
    JOIN golden_call_dispositions d ON d.call_id = c.call_id
    WHERE c.call_status = 'ANSWERED'
      AND d.disposition_code_raw NOT IN ('WRONG_NUMBER', 'NO_CONTACT')
),
rpc AS (
    SELECT DISTINCT account_id, strftime(event_at_utc, '%Y-%m') AS month
    FROM call_level_rpc
)
SELECT
    t.month,
    COUNT(DISTINCT t.account_id) AS accounts_targeted,
    COUNT(DISTINCT a.account_id) AS accounts_answered,
    COUNT(DISTINCT r.account_id) AS accounts_rpc,
    ROUND(100.0 * COUNT(DISTINCT a.account_id) / NULLIF(COUNT(DISTINCT t.account_id),0), 2) AS contact_rate_pct,
    ROUND(100.0 * COUNT(DISTINCT r.account_id) / NULLIF(COUNT(DISTINCT a.account_id),0), 2) AS rpc_rate_pct_of_answered
FROM targeted t
LEFT JOIN answered a ON t.account_id = a.account_id AND t.month = a.month
LEFT JOIN rpc r ON t.account_id = r.account_id AND t.month = r.month
GROUP BY t.month
ORDER BY t.month;
