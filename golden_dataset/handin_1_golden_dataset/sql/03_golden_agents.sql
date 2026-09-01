-- 03_golden_agents.sql
--
-- Finding (the single biggest data-quality issue in this dataset): agents.csv has
-- 30,000 rows but only 1,000 distinct agent_id values, i.e. ~30 rows per real agent.
-- These are NOT clean slowly-changing-dimension history rows - there is no snapshot
-- date, and employee_code/team/vendor_id/status/joined_at all vary near-randomly across
-- the 30 rows for the same agent_id (checked manually: one agent_id shows 15+ different
-- employee_codes, joins spread across a ~650-day window, and vendor_id touching 13 of
-- 15 possible vendors). agent_name is drawn from a pool of just 10 names, so it cannot
-- be used to cross-check identity either.
--
-- This means employee_code CANNOT be used as a reliable secondary identifier, and
-- team / vendor / status CANNOT be trusted at the row level.
--
-- Decision: treat agent_id as the only real identity. For each agent_id, resolve:
--   - team, home_vendor_id, status, agent_name -> most frequent value (MODE) across
--     that agent's rows, as our best statistical guess of the "true" current value
--   - joined_at -> earliest value seen (an agent's true join date should be the minimum,
--     later values are noise)
--   - n_raw_rows / n_distinct_employee_codes are kept so anyone downstream can see how
--     much noise sat behind a given agent's resolved profile, and can down-weight
--     agent-level conclusions accordingly.
-- Any metric cut by "team" or "telephony vendor" via this table should be read as
-- directional, not exact, given the underlying noise.

CREATE OR REPLACE TABLE golden_agents AS
SELECT
    agent_id,
    MODE(agent_name)  AS agent_name,
    MODE(team)        AS team,
    MODE(vendor_id)   AS home_vendor_id,
    MODE(status)      AS status,
    MIN(joined_at)    AS joined_at,
    MAX(updated_at)   AS last_seen_at,
    COUNT(*)          AS n_raw_rows,
    COUNT(DISTINCT employee_code) AS n_distinct_employee_codes
FROM raw_agents
GROUP BY agent_id;

SELECT
    (SELECT COUNT(*) FROM raw_agents) AS raw_rows,
    (SELECT COUNT(DISTINCT agent_id) FROM raw_agents) AS distinct_agent_ids,
    (SELECT COUNT(*) FROM golden_agents) AS golden_rows,
    (SELECT ROUND(AVG(n_distinct_employee_codes),1) FROM golden_agents) AS avg_employee_codes_per_agent;
