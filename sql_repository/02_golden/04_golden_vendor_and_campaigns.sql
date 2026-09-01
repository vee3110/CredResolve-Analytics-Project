-- 04_golden_vendor_and_campaigns.sql

-- vendor_telephony: 15 clean rows, no duplicates. But vendor_id is a CONTRACT/ACCOUNT
-- level id, not a brand-level id: 5 real telephony brands (Airtel, Twilio, Exotel,
-- Knowlarity, TataTele) are split across 15 vendor_ids. Any "which vendor performs
-- best" analysis needs a brand-level rollup or it will fragment a single vendor's
-- true performance across 2-5 separate rows.
CREATE OR REPLACE TABLE golden_vendor_telephony AS
SELECT
    vendor_id,
    vendor_name AS vendor_brand,
    vendor_account_id,
    timezone AS vendor_timezone,
    status AS vendor_status,
    schema_version
FROM raw_vendor_telephony;

-- campaigns: 120 campaign_ids but only 5 campaign_names, and each campaign_name spans
-- all 5 channels, up to 4 strategy_versions and all 5 target_definitions. campaign_name
-- alone is a "theme" label, not a stable campaign definition - grouping by name alone
-- would silently mix a WhatsApp NPA_RECOVERY campaign with a Field NPA_RECOVERY campaign.
-- We keep campaign_id as the grain and expose name/channel/strategy/target as separate
-- dimensions so downstream analysis can choose the right grouping deliberately.
CREATE OR REPLACE TABLE golden_campaigns AS
SELECT
    campaign_id,
    campaign_name,
    channel AS campaign_channel,
    strategy_version,
    target_definition,
    start_at AS campaign_start_at,
    end_at AS campaign_end_at
FROM raw_campaigns;

SELECT
    (SELECT COUNT(*) FROM raw_vendor_telephony) AS raw_vendor_rows,
    (SELECT COUNT(DISTINCT vendor_name) FROM raw_vendor_telephony) AS distinct_brands,
    (SELECT COUNT(*) FROM raw_campaigns) AS raw_campaign_rows,
    (SELECT COUNT(DISTINCT campaign_name) FROM raw_campaigns) AS distinct_campaign_names;
