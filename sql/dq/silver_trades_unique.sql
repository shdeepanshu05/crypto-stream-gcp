-- DQ: no duplicate (product_id, trade_id) in silver.trades over the last 3 days.
WITH dupes AS (
  SELECT product_id, trade_id
  FROM `crypto-de-dev-4821.silver.trades`
  WHERE trade_ts >= TIMESTAMP_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), DAY), INTERVAL 3 DAY)
  GROUP BY product_id, trade_id
  HAVING COUNT(*) > 1
)
SELECT
  'silver_trades_unique' AS check_name,
  'silver'               AS layer,
  'error'                AS severity,
  COUNT(*)               AS failed_count,
  FORMAT('%d duplicated trades', COUNT(*)) AS details
FROM dupes