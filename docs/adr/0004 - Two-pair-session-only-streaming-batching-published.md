# ADR-0004: Two pairs, session-only streaming, batched publishing
Status: Accepted
Context: Phase 2 measured ~38 trades/s (BTC-USD) and ~32 trades/s (ETH-USD), ~285 bytes each.
Session plan = ~2.9 GB/month; 24x7 = ~51.5 GB/month. Pub/Sub bills a 1 KB minimum per request,
and BigQuery/Cloud Storage subscriptions have no free tier ($50/TiB).
Decision: Stream BTC-USD and ETH-USD only, during study sessions. Batch Pub/Sub publishes.
Use ticker_batch (5 s) instead of ticker for quotes.
Alternatives considered: Adding SOL-USD (more volume, little learning value); 24x7 streaming
(Pub/Sub cheap, but Dataflow ~$200+/month); unbatched publishing (~10 GB/month just to publish).
Consequences: Estimated Pub/Sub cost ≈ $0.30/month. Quotes have 5-second granularity.