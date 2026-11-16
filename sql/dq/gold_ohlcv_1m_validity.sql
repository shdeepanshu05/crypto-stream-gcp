-- DQ: every bar must satisfy low <= open/close/vwap <= high, volume > 0, trade_count > 0.
SELECT
  'gold_ohlcv_1m_validity' AS check_name,
  'gold'                   AS layer,
  'error'                  AS severity,
  COUNTIF(NOT IFNULL(
        low <= LEAST(open, close)
    AND high >= GREATEST(open, close)
    AND vwap BETWEEN low AND high
    AND volume > 0
    AND trade_count > 0, FALSE)) AS failed_count,
  FORMAT('%d bars checked', COUNT(*)) AS details
FROM `crypto-de-dev-4821.gold.ohlcv_1m`
WHERE minute_start >= TIMESTAMP_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), DAY), INTERVAL 3 DAY)