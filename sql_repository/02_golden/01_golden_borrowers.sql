-- 01_golden_borrowers.sql
--
-- Finding: borrowers.csv has 30,600 rows but only 11,015 distinct borrower_id.
-- 600 rows are exact full-row duplicates (straightforward ingestion retries - drop them).
-- The remaining repeats are NOT legitimate profile updates: name/phone/email/city/state
-- vary incoherently for the same borrower_id (e.g. the same borrower_id shows up as
-- "Sneha Das" in Delhi and "Amit Kumar" in Mumbai on different rows), and the entire
-- borrower base only draws from 10 distinct names and 10 distinct cities. This is
-- consistent with the demographic fields being re-randomized on every duplicate/late
-- write rather than reflecting a real person's data changing over time.
--
-- Decision: borrower_id is the only trustworthy key. For descriptive attributes we take
-- the most recently updated row per borrower_id (best-effort "current" snapshot), but we
-- explicitly flag city/state/name/phone/email as LOW-TRUST attributes - they should not be
-- used as a reliable basis for hard conclusions (e.g. "Delhi borrowers recovered better"),
-- only as a rough segmentation lens, and any geography finding must be sanity-checked.

CREATE OR REPLACE TABLE stg_borrowers_nodupe AS
SELECT DISTINCT * FROM raw_borrowers;

CREATE OR REPLACE TABLE golden_borrowers AS
SELECT
    borrower_id,
    name,
    phone,
    email,
    city,
    state,
    created_at AS borrower_created_at,
    updated_at AS borrower_updated_at,
    TRUE AS demographic_fields_low_trust   -- see note above
FROM (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY borrower_id
               ORDER BY updated_at DESC, created_at DESC
           ) AS rn
    FROM stg_borrowers_nodupe
    WHERE borrower_id IS NOT NULL
)
WHERE rn = 1;

-- Impact check
SELECT
    (SELECT COUNT(*) FROM raw_borrowers) AS raw_rows,
    (SELECT COUNT(*) FROM stg_borrowers_nodupe) AS after_exact_dedupe,
    (SELECT COUNT(*) FROM golden_borrowers) AS golden_rows;
