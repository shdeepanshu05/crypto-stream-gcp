-- DQ (completeness): every valid Bronze snapshot that the last MERGE should have covered must be in Silver.
-- Bounded by Silver's high-water mark, so "MERGE hasn't run yet" is NOT flagged here (freshness covers that).
WITH silver_mark AS (
  SELECT MAX(publish_time) AS loaded_up_to
  FROM `crypto-de-dev-4821.silver.asset_snapshots`
  WHERE snapshot_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 DAY)
),
bronze_valid AS (
  SELECT DISTINCT coin_id, snapshot_ts
  FROM (
    SELECT
      JSON_VALUE(data, '$.payload.id')                                  AS coin_id,
      SAFE.TIMESTAMP(JSON_VALUE(data, '$.payload.last_updated'))        AS snapshot_ts,
      SAFE_CAST(JSON_VALUE(data, '$.payload.current_price') AS NUMERIC) AS price_usd
    FROM `crypto-de-dev-4821.bronze.coingecko_markets`, silver_mark
    WHERE publish_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
      AND publish_time <= silver_mark.loaded_up_to
      AND JSON_VALUE(data, '$.schema_version') = 'v1'
      AND JSON_VALUE(data, '$.source') = 'coingecko'
  )
  WHERE coin_id IS NOT NULL AND snapshot_ts IS NOT NULL AND price_usd IS NOT NULL
),
silver AS (
  SELECT coin_id, snapshot_ts
  FROM `crypto-de-dev-4821.silver.asset_snapshots`
  WHERE snapshot_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 DAY)
),
missing AS (
  SELECT b.coin_id, b.snapshot_ts
  FROM bronze_valid AS b
  LEFT JOIN silver AS s USING (coin_id, snapshot_ts)
  WHERE s.coin_id IS NULL
)
SELECT
  'silver_asset_snapshots_reconciliation' AS check_name,
  'silver'                                AS layer,
  'error'                                 AS severity,
  (SELECT COUNT(*) FROM missing)          AS failed_count,
  FORMAT('valid bronze snapshots up to %t: %d; missing from silver: %d',
         (SELECT loaded_up_to FROM silver_mark),
         (SELECT COUNT(*) FROM bronze_valid),
         (SELECT COUNT(*) FROM missing)) AS details