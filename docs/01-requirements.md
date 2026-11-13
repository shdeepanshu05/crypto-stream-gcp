# 01 — Requirements

**Project:** Real-Time Crypto Market Analytics & Anomaly Detection Platform on GCP
**Owner:** <your name>
**Version:** 0.1 (Phase 1 draft)
**Last updated:** 2026-11-13

## 1. Purpose

Build a streaming data platform on Google Cloud that ingests live crypto market
data from public APIs, stores it in a Bronze/Silver/Gold BigQuery warehouse, and
flags abnormal market activity within seconds. All data comes from real external
sources; nothing is simulated.

## 2. Users

| User | Need |
|---|---|
| Market surveillance analyst | Alerts on price shocks, volume spikes and trade bursts within seconds |
| Trading analyst | Clean, deduplicated trades and 1-minute OHLC candles per trading pair |
| Finance user (India) | Traded value in both USD and INR |
| Platform owner | Reliable, observable, secure pipeline within a fixed monthly budget |

## 3. Business questions

| ID | Question | Answered by (Gold) |
|---|---|---|
| BQ-01 | What were 1-minute OHLC and volume for each pair over the last 24 hours? | `fact_candles_1m` |
| BQ-02 | Which minutes had abnormal price moves, volume spikes or trade bursts, and how severe? | `fact_anomalies` |
| BQ-03 | What is the hourly realised volatility per pair? | `fact_candles_1m` |
| BQ-04 | How does the Coinbase price compare with CoinGecko, and when did they diverge? | `fact_anomalies`, `dim_asset` |
| BQ-05 | What was traded value in USD and INR per day? | `fact_trades` |

## 4. Scope

- Trading pairs: BTC-USD, ETH-USD (SOL-USD optional, decided in Phase 2)
- Sources: Coinbase Exchange WebSocket (`matches`, `ticker`, `heartbeat`),
  CoinGecko Demo API (`/coins/markets`), Frankfurter (`/v2/rates`)
- Environment: one dev project, region `us-central1`

## 5. Functional requirements

| ID | Requirement |
|---|---|
| FR-01 | The system shall ingest every trade for the in-scope pairs from the Coinbase `matches` channel. |
| FR-02 | The system shall ingest best bid/ask updates from the Coinbase `ticker` channel. |
| FR-03 | The system shall poll CoinGecko for asset metadata and price every 10 minutes. |
| FR-04 | The system shall load the USD→INR reference rate once per day. |
| FR-05 | The system shall store every received message unchanged in Bronze with its ingest timestamp and source. |
| FR-06 | The system shall archive every raw message to Cloud Storage so any day can be replayed. |
| FR-07 | The system shall validate records and send invalid ones to a quarantine table with the failed rule name. |
| FR-08 | The system shall deduplicate trades on `product_id` + `trade_id`. |
| FR-09 | The system shall detect and log gaps in `trade_id` per product (missed trades). |
| FR-10 | The system shall build 1-minute OHLC candles per pair using event time. |
| FR-11 | The system shall evaluate the five anomaly rules and write alerts to `gold.fact_anomalies`. |
| FR-12 | The system shall keep the history of asset metadata changes (SCD Type 2 in `dim_asset`). |
| FR-13 | The system shall expose Gold tables to a Looker Studio dashboard. |
| FR-14 | When an external API returns HTTP 429 or a 5xx error, the system shall wait and retry with exponential backoff (maximum 3 retries), log the failure, and skip that poll without crashing. |

## 6. Non-functional requirements

| ID | Category | Requirement | How we measure it |
|---|---|---|---|
| NFR-01 | Latency | Trade → Bronze: p95 ≤ 60 s | `publish_time` vs `trade_ts` in Bronze |
| NFR-02 | Latency | Trade → Silver: p95 ≤ 30 s while Dataflow runs | `trade_ts` vs Silver write time |
| NFR-03 | Latency | Anomaly alert written ≤ 90 s after the trade that caused it | `window_end` vs alert write time |
| NFR-04 | Freshness | Gold facts refreshed every 30 minutes | Workflows run history |
| NFR-05 | Freshness | CoinGecko data never older than 20 minutes; FX never older than 4 days (no ECB rates on weekends/holidays) | Max timestamp per table |
| NFR-06 | Correctness | Zero duplicate trades in Silver and Gold | `COUNT(*)` vs `COUNT(DISTINCT product_id, trade_id)` |
| NFR-07 | Completeness | Sequence-gap rate < 0.1% of messages per session (to confirm after Phase 2 measurement) | Gap log in Silver |
| NFR-08 | Data types | All prices and sizes stored as `NUMERIC` | Table schemas |
| NFR-09 | Recovery | Any archived day can be replayed into Bronze within 1 hour | Phase 17 replay drill |
| NFR-10 | Retention (dev) | Bronze: 30 days; GCS archive: 30 days; Silver/Gold: 90 days | Partition expiration, bucket lifecycle rule |
| NFR-11 | Availability | Pipeline runs during study sessions only; the WebSocket consumer reconnects within 30 s after a disconnect | Consumer logs |
| NFR-12 | Cost | Total spend ≤ ₹2,000/month; remaining credit (₹9,410) must last until 21 Jan 2027 | Billing budget alerts at 50/90/100% |
| NFR-13 | Query cost | Any dashboard query scans ≤ 1 GB | `INFORMATION_SCHEMA.JOBS` |
| NFR-14 | Security | No service-account keys exist; every workload runs as a dedicated least-privilege service account | IAM review, key-creation audit |
| NFR-15 | Security | Third-party API keys live only in Secret Manager | Code review, secret scan in CI |

## 7. Out of scope

- Placing trades or any trading execution
- Order-book depth (`level2`, `full` channels, which need authentication)
- Machine-learning anomaly detection (rule-based only in this project)
- Production-grade 24/7 availability or multi-region setup
- Exchanges other than Coinbase as primary sources
- Real-time alert notifications (email, Slack, SMS); alerts are only written to `gold.fact_anomalies` and shown on the dashboard

## 8. Assumptions and open questions

- Assumption: Coinbase public channels stay unauthenticated and free.
- Open: message volume per pair, measured in Phase 2, decides the number of pairs (FR-01).
- Open: WebSocket consumer hosting (Cloud Run vs e2-micro VM), decided in Phase 5.
- Open: local access approach, Option A or B, decided in ADR-0003.

## 9. Design notes

NFR-02 (trade → Silver) is the most expensive requirement to tighten 10×. Going from 30 s to 3 s forces Dataflow to run 24/7 on more capacity, costing hundreds of dollars a month, while a faster Gold refresh only means more frequent scheduled queries.

