-- gold.ohlcv_1m in INR, using an AS-OF join: each minute uses the latest USD/INR rate
-- published on or before its date (the ECB publishes no rates at weekends or on holidays).
WITH fx AS (
  -- Turn daily rates into validity ranges: [valid_from, valid_to).
  SELECT
    rate_date                                   AS valid_from,
    LEAD(rate_date) OVER (ORDER BY rate_date)   AS valid_to,   -- next published date; NULL = still current
    rate
  FROM `crypto-de-dev-4821.silver.fx_rates`
  WHERE base_currency = 'USD' AND quote_currency = 'INR'
)
SELECT
  o.product_id,
  o.minute_start,
  o.open, o.high, o.low, o.close, o.vwap,
  o.volume, o.quote_volume_usd, o.trade_count,
  fx.rate                                              AS usd_inr_rate,
  fx.valid_from                                        AS fx_rate_date,
  DATE_DIFF(DATE(o.minute_start), fx.valid_from, DAY)  AS fx_age_days,  -- 0 = same-day rate
  ROUND(o.open  * fx.rate, 2)                          AS open_inr,
  ROUND(o.high  * fx.rate, 2)                          AS high_inr,
  ROUND(o.low   * fx.rate, 2)                          AS low_inr,
  ROUND(o.close * fx.rate, 2)                          AS close_inr,
  ROUND(o.vwap  * fx.rate, 2)                          AS vwap_inr,
  ROUND(o.quote_volume_usd * fx.rate, 2)               AS quote_volume_inr
FROM `crypto-de-dev-4821.gold.ohlcv_1m` AS o
JOIN fx
  ON  DATE(o.minute_start) >= fx.valid_from
  AND (fx.valid_to IS NULL OR DATE(o.minute_start) < fx.valid_to)
-- Gold keeps 90 days; this bound also satisfies ohlcv_1m's require_partition_filter.
WHERE o.minute_start >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)