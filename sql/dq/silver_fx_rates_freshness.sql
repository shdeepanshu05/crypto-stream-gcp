-- DQ: the latest USD/INR rate is at most 4 days old (covers weekend + one holiday).
WITH latest AS (
  SELECT MAX(rate_date) AS max_date
  FROM `crypto-de-dev-4821.silver.fx_rates`
  WHERE base_currency = 'USD' AND quote_currency = 'INR'
)
SELECT
  'silver_fx_rates_freshness' AS check_name,
  'silver'                    AS layer,
  'warn'                      AS severity,
  IF(max_date IS NULL OR DATE_DIFF(CURRENT_DATE(), max_date, DAY) > 4, 1, 0) AS failed_count,
  FORMAT('latest rate_date = %t (%d days old)', max_date, DATE_DIFF(CURRENT_DATE(), max_date, DAY)) AS details
FROM latest