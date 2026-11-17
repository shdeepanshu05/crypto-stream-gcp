-- Dashboard: one row of pipeline health for the status tiles.
WITH last_dq AS (
  SELECT ARRAY_AGG(run_id ORDER BY run_ts DESC LIMIT 1)[SAFE_OFFSET(0)] AS run_id
  FROM `crypto-de-dev-4821.ops.dq_results`
  WHERE run_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 DAY)
),
last_dq_counts AS (
  SELECT COUNTIF(r.passed) AS passed, COUNT(*) AS total, MAX(r.run_ts) AS run_ts
  FROM `crypto-de-dev-4821.ops.dq_results` AS r
  JOIN last_dq USING (run_id)
  WHERE r.run_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 DAY)
)
SELECT
  (SELECT MAX(snapshot_ts) FROM `crypto-de-dev-4821.silver.asset_snapshots`
    WHERE snapshot_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 DAY))      AS latest_snapshot_ts,
  (SELECT MAX(rate_date) FROM `crypto-de-dev-4821.silver.fx_rates`)               AS latest_fx_date,
  (SELECT MAX(minute_start) FROM `crypto-de-dev-4821.gold.ohlcv_1m`
    WHERE minute_start >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY))    AS latest_candle_ts,
  c.run_ts                                                                        AS last_dq_run_ts,
  c.passed                                                                        AS last_dq_passed,
  c.total                                                                         AS last_dq_total,
  (SELECT COUNT(*) FROM `crypto-de-dev-4821.gold.anomalies`
    WHERE event_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR))       AS anomalies_24h
FROM last_dq_counts AS c