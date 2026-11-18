-- Gold anomalies: three explainable statistical rules. Insert-only and idempotent
-- (deterministic anomaly_id). Thresholds calibrated 2026-11-17 on ~2 days of data;
-- volume_surge recalibrated 2026-11-18 on a 10-hour session (see ADR-0010).
MERGE `crypto-de-dev-4821.gold.anomalies` AS tgt
USING (
  WITH
  -- Rule 1: CoinGecko 10-min return vs the trailing 24h (excluding the current point).
  snap AS (
    SELECT coin_id, snapshot_ts,
           TIMESTAMP_DIFF(snapshot_ts, LAG(snapshot_ts) OVER w, MINUTE) AS gap_min,
           CAST(SAFE_DIVIDE(price_usd - LAG(price_usd) OVER w, LAG(price_usd) OVER w) * 100 AS FLOAT64) AS ret_pct
    FROM `crypto-de-dev-4821.silver.asset_snapshots`
    WHERE snapshot_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 4 DAY)
    WINDOW w AS (PARTITION BY coin_id ORDER BY snapshot_ts)
  ),
  snap_scored AS (
    SELECT *,
           AVG(ret_pct) OVER trail AS mu,
           STDDEV_SAMP(ret_pct) OVER trail AS sd,
           COUNT(ret_pct) OVER trail AS n
    FROM snap
    WINDOW trail AS (PARTITION BY coin_id ORDER BY UNIX_SECONDS(snapshot_ts)
                     RANGE BETWEEN 86400 PRECEDING AND 1 PRECEDING)
  ),
  price_jump AS (
    SELECT 'price_jump' AS rule, coin_id AS entity, snapshot_ts AS event_ts,
           IF(ABS(SAFE_DIVIDE(ret_pct - mu, sd)) > 6, 'HIGH', 'MEDIUM') AS severity,
           ret_pct AS observed, mu AS baseline, sd AS spread,
           SAFE_DIVIDE(ret_pct - mu, sd) AS zscore,
           FORMAT('%+.3f%% in %d min; typical move %.3f%% (trailing 24h, n=%d)', ret_pct, gap_min, sd, n) AS details
    FROM snap_scored
    WHERE n >= 36
      AND gap_min BETWEEN 1 AND 15          -- guard against missed-snapshot artifacts
      AND ABS(SAFE_DIVIDE(ret_pct - mu, sd)) > 4
  ),

  -- Rule 2: Coinbase 1-min log(volume) vs the trailing 60 min.            -- CHANGED (was 15 min)
  -- A 15-min baseline underestimated normal variability and inflated z (24 flags in 10 h);
  -- 60 min with >= 40 bars gave 9 flags and removes the session warm-up artifact.
  bars AS (
    SELECT product_id, minute_start,
           CAST(volume AS FLOAT64) AS vol,
           LN(CAST(volume AS FLOAT64)) AS lv
    FROM `crypto-de-dev-4821.gold.ohlcv_1m`
    WHERE minute_start >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 4 DAY)
      AND volume > 0
  ),
  bars_scored AS (
    SELECT *,
           AVG(lv) OVER trail AS mu,
           STDDEV_SAMP(lv) OVER trail AS sd,
           COUNT(*) OVER trail AS n
    FROM bars
    WINDOW trail AS (PARTITION BY product_id ORDER BY UNIX_SECONDS(minute_start)
                     RANGE BETWEEN 3600 PRECEDING AND 1 PRECEDING)          -- CHANGED (was 900)
  ),
  volume_surge AS (
    SELECT 'volume_surge' AS rule, product_id AS entity, minute_start AS event_ts,
           IF(SAFE_DIVIDE(lv - mu, sd) > 4, 'HIGH', 'MEDIUM') AS severity,   -- CHANGED (was > 5)
           vol AS observed, EXP(mu) AS baseline, sd AS spread,
           SAFE_DIVIDE(lv - mu, sd) AS zscore,
           FORMAT('volume %.4f = %.1fx typical %.4f (geometric mean, trailing 60 min, n=%d)',
                  vol, SAFE_DIVIDE(vol, EXP(mu)), EXP(mu), n) AS details    -- CHANGED (shows the multiple)
    FROM bars_scored
    WHERE n >= 40                                                           -- CHANGED (was 10)
      AND SAFE_DIVIDE(lv - mu, sd) > 3
  ),

  -- Rule 3: CoinGecko vs Coinbase disagree by more than CoinGecko's lag can explain.
  -- Allowed gap = 0.5% + how far Coinbase moved in the previous 5 minutes.
  div AS (
    SELECT d.product_id, d.snapshot_ts,
           CAST(d.abs_divergence_pct AS FLOAT64) AS abs_div,
           CAST(ABS(SAFE_DIVIDE(d.coinbase_close - p.close, p.close)) * 100 AS FLOAT64) AS move5_pct
    FROM `crypto-de-dev-4821.gold.price_divergence` AS d
    JOIN `crypto-de-dev-4821.gold.ohlcv_1m` AS p
      ON  p.product_id = d.product_id
      AND p.minute_start = TIMESTAMP_SUB(d.coinbase_minute, INTERVAL 5 MINUTE)
    WHERE d.snapshot_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 4 DAY)
      AND p.minute_start >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 4 DAY)
  ),
  divergence_break AS (
    SELECT 'divergence_break' AS rule, product_id AS entity, snapshot_ts AS event_ts,
           IF(abs_div > 2 * (0.5 + move5_pct), 'HIGH', 'MEDIUM') AS severity,
           abs_div AS observed, 0.5 + move5_pct AS baseline,
           CAST(NULL AS FLOAT64) AS spread, CAST(NULL AS FLOAT64) AS zscore,
           FORMAT('divergence %.3f%% > allowed %.3f%% (0.5%% + 5-min move %.3f%%)',
                  abs_div, 0.5 + move5_pct, move5_pct) AS details
    FROM div
    WHERE abs_div > 0.5 + move5_pct
  ),

  all_rules AS (
    SELECT * FROM price_jump
    UNION ALL SELECT * FROM volume_surge
    UNION ALL SELECT * FROM divergence_break
  )
  SELECT TO_HEX(MD5(FORMAT('%s|%s|%t', rule, entity, event_ts))) AS anomaly_id,
         *,
         CURRENT_TIMESTAMP() AS detected_at
  FROM all_rules
  WHERE event_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 DAY)
) AS src
ON  tgt.anomaly_id = src.anomaly_id
AND tgt.event_ts >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 4 DAY)
WHEN NOT MATCHED THEN
  INSERT (anomaly_id, rule, entity, event_ts, severity, observed, baseline, spread, zscore, details, detected_at)
  VALUES (src.anomaly_id, src.rule, src.entity, src.event_ts, src.severity, src.observed,
          src.baseline, src.spread, src.zscore, src.details, src.detected_at)