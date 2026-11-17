-- Dashboard: continuous BTC/ETH prices from CoinGecko snapshots, in USD and INR.
-- INR uses the as-of FX rate valid on the snapshot's date (same pattern as ohlcv_1m_inr).
WITH fx AS (
  SELECT
    rate_date                                    AS valid_from,
    LEAD(rate_date) OVER (ORDER BY rate_date)    AS valid_to,
    rate
  FROM `crypto-de-dev-4821.silver.fx_rates`
  WHERE base_currency = 'USD' AND quote_currency = 'INR'
)
SELECT
  s.coin_id,
  UPPER(s.symbol)                               AS symbol,
  s.snapshot_ts,
  s.price_usd,
  ROUND(s.price_usd * fx.rate, 2)               AS price_inr,
  fx.rate                                       AS usd_inr_rate,
  s.market_cap_usd,
  s.volume_24h_usd,
  s.price_change_pct_24h
FROM `crypto-de-dev-4821.silver.asset_snapshots` AS s
LEFT JOIN fx
  ON  DATE(s.snapshot_ts) >= fx.valid_from
  AND (fx.valid_to IS NULL OR DATE(s.snapshot_ts) < fx.valid_to)
WHERE s.snapshot_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)