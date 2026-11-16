-- silver.trades -> gold.ohlcv_1m (one-minute candles).
-- UPSERT: a bar changes when late or backfilled trades arrive. Idempotent.
-- Window starts at MIDNIGHT 3 days ago so every minute in it is complete (never a partial bar).
MERGE `crypto-de-dev-4821.gold.ohlcv_1m` AS t
USING (
  SELECT
    product_id,
    TIMESTAMP_TRUNC(trade_ts, MINUTE)                                           AS minute_start,
    ARRAY_AGG(price ORDER BY trade_ts, trade_id LIMIT 1)[OFFSET(0)]             AS open,
    MAX(price)                                                                  AS high,
    MIN(price)                                                                  AS low,
    ARRAY_AGG(price ORDER BY trade_ts DESC, trade_id DESC LIMIT 1)[OFFSET(0)]   AS close,
    SUM(size)                                                                   AS volume,
    SUM(price * size)                                                           AS quote_volume_usd,
    SAFE_DIVIDE(SUM(price * size), SUM(size))                                   AS vwap,
    COUNT(*)                                                                    AS trade_count,
    SUM(IF(side = 'sell', size, 0))   AS taker_buy_volume,   -- maker sold => taker bought (up-tick)
    SUM(IF(side = 'buy',  size, 0))   AS taker_sell_volume,  -- maker bought => taker sold (down-tick)
    MIN(trade_id)                                                               AS first_trade_id,
    MAX(trade_id)                                                               AS last_trade_id,
    CURRENT_TIMESTAMP()                                                         AS updated_at
  FROM `crypto-de-dev-4821.silver.trades`
  WHERE trade_ts >= TIMESTAMP_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), DAY), INTERVAL 3 DAY)
  GROUP BY product_id, minute_start
) AS s
ON  t.product_id   = s.product_id
AND t.minute_start = s.minute_start
AND t.minute_start >= TIMESTAMP_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), DAY), INTERVAL 3 DAY)
WHEN MATCHED AND (t.trade_count    != s.trade_count
              OR t.first_trade_id != s.first_trade_id
              OR t.last_trade_id  != s.last_trade_id) THEN
  UPDATE SET
    open = s.open, high = s.high, low = s.low, close = s.close,
    volume = s.volume, quote_volume_usd = s.quote_volume_usd, vwap = s.vwap,
    trade_count = s.trade_count,
    taker_buy_volume = s.taker_buy_volume, taker_sell_volume = s.taker_sell_volume,
    first_trade_id = s.first_trade_id, last_trade_id = s.last_trade_id,
    updated_at = s.updated_at
WHEN NOT MATCHED THEN
  INSERT ROW