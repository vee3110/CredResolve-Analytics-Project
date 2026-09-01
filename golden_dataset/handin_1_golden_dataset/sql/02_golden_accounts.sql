-- 02_golden_accounts.sql
--
-- accounts.csv is one of the cleanest tables: account_id is a genuine unique key,
-- no full-row duplicates. Two issues worth carrying forward:
--   1. 455 accounts (~1.5%) have a NULL borrower_id - orphan accounts. We keep them
--      (they still have real payments/calls against them) but flag them so borrower-level
--      rollups can exclude them explicitly rather than silently dropping rows.
--   2. accounts.csv is the SOURCE OF TRUTH for account -> borrower mapping. This matters
--      because account_status_history.csv also carries a borrower_id column that is
--      100% inconsistent with accounts.csv (verified - every single row mismatches).
--      We never use borrower_id from account_status_history, calls, payments etc. as
--      ground truth; we always re-derive it from golden_accounts by joining on account_id.

CREATE OR REPLACE TABLE golden_accounts AS
SELECT
    account_id,
    borrower_id,
    (borrower_id IS NULL) AS is_orphan_account,
    loan_type,
    principal_amount,
    outstanding_amount,
    dpd,
    CASE
        WHEN dpd = 0 THEN 'CURRENT'
        WHEN dpd BETWEEN 1 AND 30 THEN 'DPD_1_30'
        WHEN dpd BETWEEN 31 AND 60 THEN 'DPD_31_60'
        WHEN dpd BETWEEN 61 AND 90 THEN 'DPD_61_90'
        ELSE 'DPD_90_PLUS'
    END AS dpd_bucket,
    risk_segment,
    status AS account_status_snapshot,
    opened_at,
    timezone AS account_timezone,
    schema_version
FROM raw_accounts;

SELECT
    (SELECT COUNT(*) FROM raw_accounts) AS raw_rows,
    (SELECT COUNT(*) FROM golden_accounts) AS golden_rows,
    (SELECT COUNT(*) FROM golden_accounts WHERE is_orphan_account) AS orphan_accounts;
