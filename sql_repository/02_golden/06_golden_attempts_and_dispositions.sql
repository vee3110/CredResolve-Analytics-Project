-- 06_golden_attempts_and_dispositions.sql
--
-- call_attempts (120,000 rows) and call_dispositions (35,000 rows) both have a genuinely
-- unique primary key already - no dedup needed. Two notes carried forward:
--  1. Neither table carries its own timezone column (unlike calls/accounts/agent_sessions).
--     We do not fabricate a timezone conversion for these - event_at is left as-is and
--     assumed UTC unless proven otherwise. This is a documented ASSUMPTION, not a fact,
--     and is flagged as a limitation in the data quality report.
--  2. call_dispositions has a disposition_version column (legacy/v1/v2) that looks like it
--     should explain a code migration, but all three versions use the exact same 9 codes,
--     and the version mix is flat across every month - it is not actually a legacy-code
--     migration signal. The real duplicate-meaning issue is that 'PTP' and
--     'PROMISE_TO_PAY' are two different string codes for the same underlying event; we
--     checked the monthly split and it's a stable ~50/50 split with no time trend either
--     (so it doesn't explain the reported 11% swing), but any PTP-rate metric that filters
--     on only one of the two strings will silently undercount by roughly half. We
--     normalize both into a single disposition_group.

CREATE OR REPLACE TABLE golden_call_attempts AS
SELECT
    attempt_id,
    account_id,
    borrower_id,
    call_id,
    agent_id,
    attempt_no,
    vendor_id,
    attempt_status,
    event_at AS event_at_assumed_utc
FROM raw_call_attempts;

CREATE OR REPLACE TABLE golden_call_dispositions AS
SELECT
    disposition_id,
    account_id,
    borrower_id,
    call_id,
    agent_id,
    disposition_code AS disposition_code_raw,
    CASE
        WHEN disposition_code IN ('PTP', 'PROMISE_TO_PAY') THEN 'PTP'
        ELSE disposition_code
    END AS disposition_group,
    disposition_version,
    event_at AS event_at_assumed_utc
FROM raw_call_dispositions;

SELECT
    (SELECT COUNT(*) FROM raw_call_attempts) AS raw_attempts,
    (SELECT COUNT(*) FROM golden_call_attempts) AS golden_attempts,
    (SELECT COUNT(*) FROM raw_call_dispositions) AS raw_dispositions,
    (SELECT COUNT(*) FROM golden_call_dispositions) AS golden_dispositions;
