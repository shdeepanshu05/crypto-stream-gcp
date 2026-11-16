-- DQ: SUM(gold trade_count) = COUNT(silver trades) over the same window.
-- The window ends at the last bar Gold has built, so trades not yet merged are not flagged.
WITH bounds AS (
  SELECT
    TIMESTAMP_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), DAY), INTERVAL 3 DAY) AS w_start,
    TIMESTAMP_ADD(MAX(minute_start), INTERVAL 1 MINUTE)                     AS w_end
  FROM `crypto-de-dev-4821.gold.ohlcv_1m`
  WHERE minute_start >= TIMESTAMP_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), DAY), INTERVAL 3 DAY)
),
gold AS (
  SELECT SUM(trade_count) AS n
  FROM `crypto-de-dev-4821.gold.ohlcv_1m`, bounds
  WHERE minute_start >= w_start AND minute_start < w_end
),
silver AS (
  SELECT COUNT(*) AS n
  FROM `crypto-de-dev-4821.silver.trades`, bounds
  WHERE trade_ts >= w_start AND trade_ts < w_end
)
SELECT
  'gold_silver_trade_consistency' AS check_name,
  'gold'                          AS layer,
  'error'                         AS severity,
  ABS(IFNULL(gold.n, 0) - IFNULL(silver.n, 0)) AS failed_count,
  FORMAT('gold=%d silver=%d', IFNULL(gold.n, 0), IFNULL(silver.n, 0)) AS details
FROM gold, silver