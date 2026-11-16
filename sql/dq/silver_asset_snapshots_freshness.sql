-- DQ: silver.asset_snapshots must have a snapshot no older than 30 minutes.
WITH latest AS (
  SELECT MAX(snapshot_ts) AS max_ts
  FROM `crypto-de-dev-4821.silver.asset_snapshots`
  WHERE snapshot_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 DAY)
)
SELECT
  'silver_asset_snapshots_freshness' AS check_name,
  'silver'                           AS layer,
  'error'                            AS severity,
  IF(max_ts IS NULL
     OR TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), max_ts, MINUTE) > 30, 1, 0) AS failed_count,
  FORMAT('latest snapshot_ts = %t (%d min old)',
         max_ts, TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), max_ts, MINUTE)) AS details
FROM latest