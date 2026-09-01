-- Channel conversion: of accounts touched by a given channel in a month, what share
-- had a SUCCESS payment within 14 days of that touch.
--
-- Caveat carried from the Data Quality Report (finding B): only ~9% of successful
-- payments have ANY traceable campaign/channel touch in the preceding window at all.
-- So channel_conversion as computed here should be read as "conversion rate among
-- traceable touches", not "share of all recovery driven by this channel" - the two
-- are very different numbers and conflating them is exactly the attribution-error
-- trap this project is meant to catch.

CREATE OR REPLACE VIEW metric_channel_conversion_monthly AS
WITH touches AS (
    SELECT account_id, campaign_id, event_at_utc AS touch_at, strftime(event_at_utc,'%Y-%m') AS month
    FROM golden_calls
    WHERE campaign_id IS NOT NULL
),
touches_with_channel AS (
    SELECT t.account_id, t.touch_at, t.month, c.campaign_channel
    FROM touches t JOIN golden_campaigns c ON t.campaign_id = c.campaign_id
),
converted AS (
    SELECT twc.account_id, twc.month, twc.campaign_channel,
           EXISTS (
               SELECT 1 FROM golden_payments p
               WHERE p.account_id = twc.account_id
                 AND p.is_recovered_cash
                 AND p.event_at BETWEEN twc.touch_at AND twc.touch_at + INTERVAL '14 day'
           ) AS converted
    FROM touches_with_channel twc
)
SELECT
    month,
    campaign_channel,
    COUNT(DISTINCT account_id) AS accounts_touched,
    SUM(CASE WHEN converted THEN 1 ELSE 0 END) AS accounts_converted,
    ROUND(100.0 * SUM(CASE WHEN converted THEN 1 ELSE 0 END) / COUNT(*), 2) AS conversion_rate_pct
FROM converted
GROUP BY month, campaign_channel
ORDER BY month, campaign_channel;
