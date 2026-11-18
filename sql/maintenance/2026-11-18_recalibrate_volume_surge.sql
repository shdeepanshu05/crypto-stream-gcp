-- One-off (2026-11-18): volume_surge recalibrated from a 15-min to a 60-min baseline (ADR-0010).
-- Remove flags produced by the old rule; the next merge_anomalies run recomputes them.
DELETE FROM `crypto-de-dev-4821.gold.anomalies`
WHERE rule = 'volume_surge'
  AND event_ts >= TIMESTAMP('2026-11-14')