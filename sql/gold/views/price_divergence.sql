-- CoinGecko (aggregated across exchanges) vs Coinbase (one exchange), matched by minute.
-- A large gap means a data problem (stale feed, wrong mapping) or a real market dislocation.
WITH coingecko AS (
  SELECT
    CASE coin_id WHEN 'bitcoin' THEN 'BTC-USD' WHEN 'ethereum' THEN 'ETH-USD' END AS product_id,
    snapshot_ts,
    price_usd AS coingecko_price
  FROM `crypto-de-dev-4821.silver.asset_snapshots`
  WHERE snapshot_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
    AND coin_id IN ('bitcoin', 'ethereum')
)
SELECT
  cg.product_id,
  cg.snapshot_ts,
  cg.coingecko_price,
  o.minute_start                                            AS coinbase_minute,
  o.vwap                                                    AS coinbase_vwap,
  o.close                                                   AS coinbase_close,
  o.trade_count                                             AS coinbase_trades,
  ROUND((cg.coingecko_price - o.vwap) / o.vwap * 100, 4)    AS divergence_pct,
  ROUND(ABS(cg.coingecko_price - o.vwap) / o.vwap * 100, 4) AS abs_divergence_pct
FROM coingecko AS cg
JOIN `crypto-de-dev-4821.gold.ohlcv_1m` AS o
  ON  o.product_id   = cg.product_id
  AND o.minute_start = TIMESTAMP_TRUNC(cg.snapshot_ts, MINUTE)
WHERE o.minute_start >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)