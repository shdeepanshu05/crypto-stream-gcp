# ADR-0010: Explainable statistical rules for anomaly detection

**Status:** Accepted · **Date:** 2026-11-17

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
| volume_surge | Coinbase 1-min log(volume) | trailing 15 min, ≥10 bars | z > 3 MEDIUM, > 5 HIGH |
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

## Trade-offs and follow-ups
- Volume rule: a 30-min/20-bar baseline scored only 5 of 44 bars; 15 min/10 bars scores 16 of 44
  per product. Max z = 2.15, so no surges were flagged. Needs sessions of 60+ minutes for
  meaningful coverage; re-calibrate then.
- Divergence threshold is reasoned, not calibrated (only 6 data points so far).
- Anomalies are stored but not yet notified; surfaced in the dashboard (Phase 14).
- Future: BigQuery ML forecasting-based detection once weeks of history exist.