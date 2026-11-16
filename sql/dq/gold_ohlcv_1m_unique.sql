-- DQ: no duplicate (product_id, minute_start) bars in the last 3 days.
WITH dupes AS (
  SELECT product_id, minute_start, COUNT(*) AS n
  FROM `crypto-de-dev-4821.gold.ohlcv_1m`
  WHERE minute_start >= TIMESTAMP_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), DAY), INTERVAL 3 DAY)
  GROUP BY product_id, minute_start
  HAVING COUNT(*) > 1
)
SELECT
  'gold_ohlcv_1m_unique' AS check_name,
  'gold'                 AS layer,
  'error'                AS severity,
  COUNT(*)               AS failed_count,
  FORMAT('%d duplicate groups; worst = %d copies', COUNT(*), IFNULL(MAX(n), 0)) AS details
FROM dupes