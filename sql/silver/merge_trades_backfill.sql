-- Insert archived trades missing from silver.trades. Idempotent: safe to run repeatedly.
MERGE `crypto-de-dev-4821.silver.trades` AS t
USING (
  SELECT *
  FROM `crypto-de-dev-4821.silver.trades_backfill`
  WHERE TRUE
  -- The archive is at-least-once: keep one row per trade.
  QUALIFY ROW_NUMBER() OVER (PARTITION BY product_id, trade_id ORDER BY ingest_ts) = 1
) AS s
ON  t.product_id = s.product_id
AND t.trade_id   = s.trade_id
-- silver.trades requires a partition filter; constant lower bound for this backfill window.
AND t.trade_ts  >= TIMESTAMP('2026-11-14')
WHEN NOT MATCHED THEN
  INSERT ROW