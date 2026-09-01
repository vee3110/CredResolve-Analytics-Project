-- 00_load_raw.sql
-- Loads every source CSV into DuckDB with zero transformation.
-- This is the "Raw" layer - nothing here is trusted yet.

CREATE OR REPLACE TABLE raw_borrowers AS SELECT * FROM read_csv_auto('raw/borrowers.csv');
CREATE OR REPLACE TABLE raw_accounts AS SELECT * FROM read_csv_auto('raw/accounts.csv');
CREATE OR REPLACE TABLE raw_agents AS SELECT * FROM read_csv_auto('raw/agents.csv');
CREATE OR REPLACE TABLE raw_agent_sessions AS SELECT * FROM read_csv_auto('raw/agent_sessions.csv');
CREATE OR REPLACE TABLE raw_campaigns AS SELECT * FROM read_csv_auto('raw/campaigns.csv');
CREATE OR REPLACE TABLE raw_daily_targeting AS SELECT * FROM read_csv_auto('raw/daily_targeting.csv');
CREATE OR REPLACE TABLE raw_calls AS SELECT * FROM read_csv_auto('raw/calls.csv');
CREATE OR REPLACE TABLE raw_call_attempts AS SELECT * FROM read_csv_auto('raw/call_attempts.csv');
CREATE OR REPLACE TABLE raw_call_dispositions AS SELECT * FROM read_csv_auto('raw/call_dispositions.csv');
CREATE OR REPLACE TABLE raw_whatsapp_events AS SELECT * FROM read_csv_auto('raw/whatsapp_events.csv');
CREATE OR REPLACE TABLE raw_sms_events AS SELECT * FROM read_csv_auto('raw/sms_events.csv');
CREATE OR REPLACE TABLE raw_field_visits AS SELECT * FROM read_csv_auto('raw/field_visits.csv');
CREATE OR REPLACE TABLE raw_promises_to_pay AS SELECT * FROM read_csv_auto('raw/promises_to_pay.csv');
CREATE OR REPLACE TABLE raw_payments AS SELECT * FROM read_csv_auto('raw/payments.csv');
CREATE OR REPLACE TABLE raw_vendor_telephony AS SELECT * FROM read_csv_auto('raw/vendor_telephony.csv');
CREATE OR REPLACE TABLE raw_complaints AS SELECT * FROM read_csv_auto('raw/complaints.csv');
CREATE OR REPLACE TABLE raw_account_status_history AS SELECT * FROM read_csv_auto('raw/account_status_history.csv');
