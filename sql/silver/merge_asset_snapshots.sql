-- Bronze coingecko_markets (raw JSON) -> silver.asset_snapshots.
-- Insert-only: a snapshot at a point in time never changes. Idempotent.
MERGE `crypto-de-dev-4821.silver.asset_snapshots` AS t
USING (
  SELECT *
  FROM (
    SELECT
      JSON_VALUE(data, '$.payload.id')                                      AS coin_id,
      JSON_VALUE(data, '$.payload.symbol')                                  AS symbol,
      JSON_VALUE(data, '$.payload.name')                                    AS name,
      SAFE.TIMESTAMP(JSON_VALUE(data, '$.payload.last_updated'))            AS snapshot_ts,
      SAFE_CAST(JSON_VALUE(data, '$.payload.current_price') AS NUMERIC)     AS price_usd,
      SAFE_CAST(JSON_VALUE(data, '$.payload.market_cap') AS NUMERIC)        AS market_cap_usd,
      SAFE_CAST(JSON_VALUE(data, '$.payload.market_cap_rank') AS INT64)     AS market_cap_rank,
      SAFE_CAST(JSON_VALUE(data, '$.payload.total_volume') AS NUMERIC)      AS volume_24h_usd,
      SAFE_CAST(JSON_VALUE(data, '$.payload.high_24h') AS NUMERIC)          AS high_24h_usd,
      SAFE_CAST(JSON_VALUE(data, '$.payload.low_24h') AS NUMERIC)           AS low_24h_usd,
      SAFE_CAST(JSON_VALUE(data, '$.payload.price_change_percentage_24h') AS NUMERIC) AS price_change_pct_24h,
      SAFE_CAST(JSON_VALUE(data, '$.payload.circulating_supply') AS NUMERIC) AS circulating_supply,
      SAFE_CAST(JSON_VALUE(data, '$.payload.total_supply') AS NUMERIC)      AS total_supply,
      SAFE_CAST(JSON_VALUE(data, '$.payload.max_supply') AS NUMERIC)        AS max_supply,
      SAFE.TIMESTAMP(JSON_VALUE(data, '$.ingest_ts'))                       AS ingest_ts,
      publish_time
    FROM `crypto-de-dev-4821.bronze.coingecko_markets`
    -- Incremental window: only recent Bronze partitions (also satisfies require_partition_filter).
    WHERE publish_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 DAY)
      AND JSON_VALUE(data, '$.schema_version') = 'v1'
      AND JSON_VALUE(data, '$.source') = 'coingecko'
  )
  WHERE coin_id IS NOT NULL AND snapshot_ts IS NOT NULL AND price_usd IS NOT NULL
  -- Bronze is at-least-once: keep the first delivery of each snapshot.
  QUALIFY ROW_NUMBER() OVER (PARTITION BY coin_id, snapshot_ts ORDER BY publish_time) = 1
) AS s
ON  t.coin_id = s.coin_id
AND t.snapshot_ts = s.snapshot_ts
AND t.snapshot_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 4 DAY)  -- target partition filter
WHEN NOT MATCHED THEN
  INSERT ROW