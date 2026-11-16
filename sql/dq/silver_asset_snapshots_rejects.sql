-- DQ (completeness): Bronze CoinGecko rows that merge_asset_snapshots.sql would silently drop.
-- Mirrors the MERGE's envelope filter and NOT NULL filter EXACTLY. Keep both files in sync.
WITH bronze AS (
  SELECT
    JSON_VALUE(data, '$.schema_version')                              AS schema_version,
    JSON_VALUE(data, '$.source')                                      AS source,
    JSON_VALUE(data, '$.payload.id')                                  AS coin_id,
    SAFE.TIMESTAMP(JSON_VALUE(data, '$.payload.last_updated'))        AS snapshot_ts,
    SAFE_CAST(JSON_VALUE(data, '$.payload.current_price') AS NUMERIC) AS price_usd
  FROM `crypto-de-dev-4821.bronze.coingecko_markets`
  WHERE publish_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
),
classified AS (
  SELECT
    CASE
      WHEN IFNULL(schema_version, '') != 'v1'
        OR IFNULL(source, '') != 'coingecko' THEN 'envelope_mismatch'
      WHEN coin_id IS NULL                   THEN 'null_coin_id'
      WHEN snapshot_ts IS NULL               THEN 'bad_last_updated'
      WHEN price_usd IS NULL                 THEN 'bad_current_price'
    END AS reason
  FROM bronze
)
SELECT
  'silver_asset_snapshots_rejects' AS check_name,
  'silver'                         AS layer,
  'error'                          AS severity,
  COUNTIF(reason IS NOT NULL)      AS failed_count,
  FORMAT('%d bronze rows in 24h; rejected: envelope=%d null_coin_id=%d bad_last_updated=%d bad_current_price=%d',
         COUNT(*),
         COUNTIF(reason = 'envelope_mismatch'),
         COUNTIF(reason = 'null_coin_id'),
         COUNTIF(reason = 'bad_last_updated'),
         COUNTIF(reason = 'bad_current_price')) AS details
FROM classified