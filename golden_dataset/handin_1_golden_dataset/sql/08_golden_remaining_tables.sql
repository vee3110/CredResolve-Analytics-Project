-- 08_golden_remaining_tables.sql

-- whatsapp_events / sms_events: simple exact-duplicate ingestion retries (600 pairs / 0
-- pairs respectively at full-row level for whatsapp; sms had none). Drop exact dupes only.
CREATE OR REPLACE TABLE golden_whatsapp_events AS
SELECT DISTINCT
    whatsapp_event_id, account_id, borrower_id, event_at, message_id,
    event_type, template_code, provider_id
FROM raw_whatsapp_events;

CREATE OR REPLACE TABLE golden_sms_events AS
SELECT DISTINCT
    sms_event_id, account_id, borrower_id, event_at, message_id,
    event_type, template_code, provider_id
FROM raw_sms_events;

-- field_visits: unique PK, no dupes. ~1% missing scheduled_at (visit happened without a
-- prior schedule, e.g. an ad-hoc/walk-in visit) - kept as NULL, not imputed, since a
-- fabricated schedule time would misrepresent an unscheduled visit as planned.
CREATE OR REPLACE TABLE golden_field_visits AS
SELECT
    visit_id, account_id, borrower_id, agent_id, visit_type, outcome,
    latitude, longitude, scheduled_at, event_at,
    (scheduled_at IS NULL) AS was_unscheduled_visit
FROM raw_field_visits;

-- promises_to_pay: unique PK, no dupes.
CREATE OR REPLACE TABLE golden_promises_to_pay AS
SELECT
    ptp_id, account_id, borrower_id, agent_id, promised_amount, promised_date,
    status AS ptp_status, source AS ptp_source, event_at
FROM raw_promises_to_pay;

-- complaints: unique PK, no dupes.
CREATE OR REPLACE TABLE golden_complaints AS
SELECT
    complaint_id, account_id, borrower_id, complaint_type, severity,
    status AS complaint_status, source, event_at, resolution_at
FROM raw_complaints;

-- account_status_history: history_id is a genuine unique key, but the borrower_id column
-- is 100% inconsistent with accounts.csv (verified on every row) - it is discarded and
-- re-derived via a join to golden_accounts. recorded_at is essentially random noise
-- within +/-24h of event_at (50% of rows even show recorded_at BEFORE event_at, which is
-- operationally impossible) - it is kept for reference but flagged as not usable for
-- lineage/lag analysis. event_at is the only trustworthy timestamp in this table.
CREATE OR REPLACE TABLE golden_account_status_history AS
SELECT
    h.history_id,
    h.account_id,
    a.borrower_id,                    -- re-derived from accounts.csv, not from raw history
    h.status,
    h.changed_by,
    h.source,
    h.event_at,
    h.recorded_at,
    TRUE AS recorded_at_low_trust
FROM raw_account_status_history h
LEFT JOIN golden_accounts a ON h.account_id = a.account_id;

-- agent_sessions: unique PK, no dupes. Has its own timezone column - normalize like calls.
CREATE OR REPLACE TABLE golden_agent_sessions AS
SELECT
    session_id, agent_id, channel, device_id,
    timezone AS session_timezone,
    login_at AS login_at_local,
    logout_at AS logout_at_local,
    CASE timezone WHEN 'UTC' THEN login_at
                  WHEN 'Asia/Kolkata' THEN login_at - (INTERVAL '5 hour' + INTERVAL '30 minute')
                  ELSE login_at END AS login_at_utc,
    CASE timezone WHEN 'UTC' THEN logout_at
                  WHEN 'Asia/Kolkata' THEN logout_at - (INTERVAL '5 hour' + INTERVAL '30 minute')
                  ELSE logout_at END AS logout_at_utc,
    DATE_DIFF('second', login_at, logout_at) / 3600.0 AS session_hours
FROM raw_agent_sessions;

-- daily_targeting: unique PK, no dupes.
CREATE OR REPLACE TABLE golden_daily_targeting AS
SELECT
    target_id, account_id, campaign_id, target_date, priority,
    recommended_channel, status AS targeting_status
FROM raw_daily_targeting;

SELECT 'whatsapp' AS tbl, COUNT(*) FROM golden_whatsapp_events
UNION ALL SELECT 'sms', COUNT(*) FROM golden_sms_events
UNION ALL SELECT 'field_visits', COUNT(*) FROM golden_field_visits
UNION ALL SELECT 'ptp', COUNT(*) FROM golden_promises_to_pay
UNION ALL SELECT 'complaints', COUNT(*) FROM golden_complaints
UNION ALL SELECT 'status_history', COUNT(*) FROM golden_account_status_history
UNION ALL SELECT 'agent_sessions', COUNT(*) FROM golden_agent_sessions
UNION ALL SELECT 'daily_targeting', COUNT(*) FROM golden_daily_targeting;
