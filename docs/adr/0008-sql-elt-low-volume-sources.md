# ADR-0008: SQL ELT for low-volume sources; views for derived Gold data

**Status:** Accepted
**Date:** 2026-11-17

## Context
CoinGecko (~12 messages/hour per coin) and Frankfurter FX (1 message per business day) land in Bronze
via Pub/Sub BigQuery subscriptions. Coinbase trades (~20–37/s) use Dataflow (ADR-0007).

## Decision
1. **Silver for low-volume sources = SQL MERGE in BigQuery**, run as `sa-orchestrator`.
   - `asset_snapshots`: insert-only (snapshots are immutable events).
   - `fx_rates`: upsert (ECB can correct a published rate).
2. **Gold candles = an upsert MERGE** over a midnight-aligned 3-day window (late trades can change a bar).
3. **Derived Gold = views**, not tables: `ohlcv_1m_inr` (an as-of FX join through validity ranges built with `LEAD()`)
   and `price_divergence`.

## Alternatives considered
- **Dataflow for every source:** rejected. A streaming worker running all the time (~$) for 1 message every 10 minutes is wasteful.
- **Materialized tables for the INR and divergence data:** rejected for now. Views are always current, have no refresh job,
  and the data volume is small. Revisit if dashboard query costs grow.

## Consequences
- (+) Almost zero cost; the SQL can be reviewed in Git; reruns are safe (MERGEs are idempotent; second runs gave 0 rows).
- (−) The MERGEs need orchestration (until Phase 11 they are run by hand).
- (−) Views recompute on every query.

## Known gaps (to be addressed)
1. **Silent NULL drops:** `SAFE_CAST` plus `IS NOT NULL` filters drop bad rows without an error → Phase 10 DQ checks.
2. **Partial bars** at session edges (the first and last minute of a session are incomplete).
3. **CoinGecko lag bias:** `last_updated` lags the market, so divergence follows the market's direction
   (session 2: always positive while prices fell, 0.02–0.22%). Anomaly thresholds must allow for this.
4. **Hard-coded coin mapping** (`CASE coin_id`) in `price_divergence` → should become a mapping table.
5. **p50 latency of 81 s** on the first streaming run (tuning in the monitoring phase).