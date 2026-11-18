# ADR-0010: Explainable statistical rules for anomaly detection

**Status:** Accepted · **Date:** 2026-11-17 · **Amended:** 2026-11-18 (volume_surge recalibration)

## Context
The platform's purpose includes anomaly detection on crypto market data. History is short
(about 2 days of CoinGecko snapshots, two ~25-minute Coinbase streaming sessions).

## Decision
Three SQL rules in `sql/gold/merge_anomalies.sql` write to `gold.anomalies`
(insert-only; `anomaly_id` = MD5 of `rule|entity|event_ts`, so reruns never duplicate).
The step runs in `elt-pipeline` **after DQ passes**: never interpret data that failed quality checks.

| Rule | Data | Baseline | Threshold |
|---|---|---|---|
| price_jump | CoinGecko 10-min return | trailing 24h, ≥36 points, gap 1–15 min | \|z\| > 4 MEDIUM, > 6 HIGH |
| volume_surge | Coinbase 1-min log(volume) | trailing **60 min**, **≥40 bars** *(was 15 min / ≥10)* | z > 3 MEDIUM, **> 4 HIGH** *(was > 5)* |
| divergence_break | CoinGecko vs Coinbase VWAP | allowed = 0.5% + Coinbase 5-min move | > allowed MEDIUM, > 2× HIGH |

Design rules:
- Baselines **exclude the current point** (`… AND 1 PRECEDING`), so a spike cannot hide itself.
- Windows are **time-based** (`RANGE` over seconds), so gaps between sessions are handled correctly.
- Volume uses **log(volume)** because raw volume is heavily skewed.
- The divergence allowance **grows with market movement**, encoding the CoinGecko lag bias
  found in Phase 9 (divergence tracks market direction).

## Why rules, not ML (yet)
Explainable ("+1.451% in 9 min; typical move 0.184%"), works with days of history, about 24 KB
scanned per run, and fits the existing pipeline as one MERGE.

## Calibration evidence (2026-11-17)
- Returns have **fat tails**: 2–3 points per coin with |z| > 4 in 243 scored points, where a
  normal distribution predicts about 0. |z| > 4 ≈ 1 event per coin per day.
- All 5 flags were **real**: gaps 9–10 min, and BTC and ETH moved together during a volatility
  burst on 16 Nov, 14:20–15:10 UTC (+1.45% / +1.80% at 14:40, then −0.90% / −1.84% at 15:09).
- The trailing standard deviation **rose after the jump** (volatility clustering), so the
  reversal needed a larger move to be flagged: the baseline adapts on its own.
- First run inserted 5 rows; rerun inserted 0 (idempotent).

## Amendment 2026-11-18: volume_surge recalibration

**Trigger.** The first long streaming session (overnight 17–18 Nov, about 10 hours, about 1.2 million trades,
1,208 one-minute candles) gave the volume rule enough data to score. With the original
15-minute / 10-bar baseline it produced **24 flags**, most of them during quiet overnight hours.

**Diagnosis.** A 15-minute baseline is too short. When the market is quiet, the trailing
standard deviation of log(volume) collapses, so an ordinary burst of a few larger trades scores
z > 3. The rule was measuring "louder than the last quarter-hour", not "unusual".

**Change.**
- Baseline window 15 → **60 minutes** (`RANGE BETWEEN 3600 PRECEDING AND 1 PRECEDING`).
- Minimum history 10 → **40 bars**, so the first ~40 minutes of a session are never scored
  against a thin baseline.
- HIGH threshold 5 → **4**: with a stabler baseline, z > 4 is already rare, and 5 would almost
  never fire.
- `details` now states the baseline explicitly: "… = Nx typical … (geometric mean, trailing 60 min, n=…)".

**Result.** On the same overnight data: **24 → 9 flags**. Each remaining flag is a 10–30× jump over the
hourly typical volume, which a reviewer would agree is unusual.

**How it was applied** (commit `8eb450e`):
1. `sql/maintenance/2026-11-18_recalibrate_volume_surge.sql` deleted the 24 flags produced by the
   old rule (`rule = 'volume_surge' AND event_ts >= '2026-11-14'`): 24 rows.
2. The updated `merge_anomalies.sql` was re-run: 9 rows inserted.
3. Both ran as `sa-orchestrator` via impersonation. The scheduled workflow uses the new SQL from
   then on (Terraform `templatefile`, applied the same day).

Deleting rows breaks "insert-only" deliberately and once: flags produced by a rule that was
wrong are not history worth keeping. The maintenance script is committed, so the deletion is
auditable and repeatable.

## Live evidence (after deployment)
- **17 Nov 15:49:58 UTC:** joint drop flagged by price_jump: ETH z −7.87 (HIGH), BTC z −5.9
  (MEDIUM, just under the HIGH cut-off of 6). Detected about 9 minutes after the move, which is the
  CoinGecko snapshot cadence plus the 30-minute workflow schedule.
- **18 Nov 14:39:52 UTC:** ETH −1.26% (z −4.29) and BTC −0.91% (z −4.23), both MEDIUM. Detected
  by the scheduled pipeline with no manual action, and visible on the dashboard
  (anomalies in the last 24 h: 11 → 13).
- The same z-score gives different severities to BTC and ETH for the same market event,
  because each coin is measured against its **own** recent volatility.

## Trade-offs and follow-ups
- ~~Volume rule needs sessions of 60+ minutes; re-calibrate then.~~ Done (amendment above).
- Divergence threshold is reasoned, not calibrated (only 6 data points so far).
- Anomalies are stored, surfaced in the dashboard (Phase 14, ADR-0012), but not yet notified.
- **`entity` is not conformed:** price_jump uses CoinGecko IDs (`bitcoin`), volume_surge uses
  Coinbase products (`BTC-USD`). Filtering by coin misses half the rows. Fix with a `dim_assets`
  mapping table (known gap #4) and a shared `asset` key in `gold.anomalies`.
- Future: BigQuery ML forecasting-based detection once weeks of history exist.
