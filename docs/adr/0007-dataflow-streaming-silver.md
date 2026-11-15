# ADR-0007: Streaming Silver on Dataflow

## Status
Accepted (Phase 7)

## Context
Silver needs validated, deduplicated, typed trades within seconds of arrival,
reusing the same validation as the batch pipeline.

## Decisions
1. **Apache Beam on Dataflow**, reading a dedicated pull subscription
   (`coinbase-trades-to-dataflow`), since a shared subscription would split messages.
2. **Stateful dedup** keyed on product_id:trade_id with an event-time timer
   (10 min horizon). State is lost on a new job; the Gold MERGE (Phase 9) is the backstop.
3. **Legacy streaming inserts** instead of the Storage Write API: no Java toolchain
   on developer machines; cost ~$0.50/month at our volume; at-least-once is
   acceptable because of points 2 and the Gold MERGE.
   Exit plan: Flex Template launched from CI (Phase 15), then switch to STORAGE_WRITE_API.
4. **Least privilege, found by testing:**
   - Worker: pubsub.subscriber + pubsub.viewer on ONE subscription (not pubsub.editor
     as Google's docs suggest); dataEditor on silver; objectAdmin + legacyBucketReader
     on the Dataflow bucket only.
   - Launcher (sa-cicd-deployer): dataflow.developer, compute.viewer, serviceAccountUser
     on sa-dataflow-worker only, objectAdmin + legacyBucketReader on the bucket only.
   - legacyBucketReader was added after a real 403 (storage.buckets.get) at launch.
5. **Cost controls:** 1 x n1-standard-2, autoscaling NONE, Streaming Engine,
   30 GB disk, session-only runs, always drained.

## Consequences
- First run: 52,348 rows, 0 duplicates, 0 quarantined; 863 trades (1.6%) left
  in the subscription by draining too early. Runbook now drains only at zero backlog.
- p50 latency 81 s on the first run (startup backlog); to be tuned in Phase 14.