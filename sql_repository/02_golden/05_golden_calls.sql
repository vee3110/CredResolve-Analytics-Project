-- 05_golden_calls.sql
--
-- Findings on calls.csv:
--  1. 91,350 raw rows but only 90,000 distinct call_id. Of the ~2,700 rows sharing a
--     call_id with another row, 2,542 are exact full-row duplicates (plain ingestion
--     retries - safe to drop) and 158 rows are a genuine ID COLLISION: the same call_id
--     is reused for two rows that differ (e.g. CALL0000226 appears on Jan 9 and again on
--     Jan 12 with an identical everything-else - the same voicemail call logged 3 days
--     apart under one ID). We cannot tell which one is "the real one," so instead of
--     guessing we keep both and give them a surrogate key, flagging them for visibility.
--  2. event_at is stored in the LOCAL timezone named in the timezone column (roughly an
--     even 3-way split of UTC / Asia/Kolkata / Asia/Dubai). If hour-of-day or day-of-week
--     analysis is run on the raw event_at without normalizing, ~2/3 of calls get bucketed
--     into the wrong hour/day. We compute event_at_utc explicitly.

CREATE OR REPLACE TABLE stg_calls_nodupe AS
SELECT DISTINCT * FROM raw_calls;

CREATE OR REPLACE TABLE golden_calls AS
SELECT
    call_id,
    call_id || '-' || CAST(dup_seq AS VARCHAR) AS call_sk,
    (dup_seq > 1) AS is_colliding_call_id,
    account_id,
    borrower_id,
    agent_id,
    campaign_id,
    direction,
    vendor_id,
    call_status,
    duration_sec,
    timezone AS event_timezone,
    event_at AS event_at_local,
    CASE timezone
        WHEN 'UTC'          THEN event_at
        WHEN 'Asia/Kolkata'  THEN event_at - (INTERVAL '5 hour' + INTERVAL '30 minute')
        WHEN 'Asia/Dubai'    THEN event_at - INTERVAL '4' HOUR
        ELSE event_at
    END AS event_at_utc
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY call_id ORDER BY event_at) AS dup_seq
    FROM stg_calls_nodupe
);

SELECT
    (SELECT COUNT(*) FROM raw_calls) AS raw_rows,
    (SELECT COUNT(*) FROM stg_calls_nodupe) AS after_exact_dedupe,
    (SELECT COUNT(*) FROM golden_calls) AS golden_rows,
    (SELECT COUNT(*) FROM golden_calls WHERE is_colliding_call_id) AS colliding_id_rows_kept;
