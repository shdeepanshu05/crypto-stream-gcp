-- Bronze fx_rates (payload is a LIST) -> silver.fx_rates, one row per (date, base, quote).
-- Upsert: if the provider corrects a rate, update it.
MERGE `crypto-de-dev-4821.silver.fx_rates` AS t
USING (
  SELECT *
  FROM (
    SELECT
      SAFE.PARSE_DATE('%Y-%m-%d', JSON_VALUE(item, '$.date')) AS rate_date,
      JSON_VALUE(item, '$.base')                              AS base_currency,
      JSON_VALUE(item, '$.quote')                             AS quote_currency,
      SAFE_CAST(JSON_VALUE(item, '$.rate') AS NUMERIC)        AS rate,
      'ecb'                                                   AS provider,
      SAFE.TIMESTAMP(JSON_VALUE(data, '$.ingest_ts'))         AS ingest_ts,
      publish_time
    FROM `crypto-de-dev-4821.bronze.fx_rates`,
      UNNEST(JSON_QUERY_ARRAY(data, '$.payload')) AS item       -- one row per list element
    WHERE publish_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
      AND JSON_VALUE(data, '$.source') = 'frankfurter'
  )
  WHERE rate_date IS NOT NULL AND base_currency IS NOT NULL
    AND quote_currency IS NOT NULL AND rate IS NOT NULL
  -- The same date arrives repeatedly (e.g. weekend runs return Friday): keep the LATEST delivery.
  QUALIFY ROW_NUMBER() OVER (PARTITION BY rate_date, base_currency, quote_currency
                             ORDER BY publish_time DESC) = 1
) AS s
ON  t.rate_date = s.rate_date
AND t.base_currency = s.base_currency
AND t.quote_currency = s.quote_currency
WHEN MATCHED AND t.rate != s.rate THEN
  UPDATE SET rate = s.rate, ingest_ts = s.ingest_ts, publish_time = s.publish_time
WHEN NOT MATCHED THEN
  INSERT ROW