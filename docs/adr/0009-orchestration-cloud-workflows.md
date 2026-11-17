# ADR-0009: Orchestrate the batch ELT with Cloud Workflows; DQ as a Cloud Run job

**Status:** Accepted · **Date:** 2026-11-17

## Context
After Phase 10, Silver/Gold MERGEs and the DQ checks were run by hand. Freshness DQ caught
Silver 191 minutes stale because nobody ran the MERGE. We need an unattended, ordered chain
that stops on failure, at near-zero cost.

## Decision
- **Cloud Scheduler** (`elt-pipeline-trigger`, `5,35 * * * *` UTC, runs as `sa-scheduler`)
  starts the **Cloud Workflows** workflow `elt-pipeline` (runs as `sa-orchestrator`).
- Steps, in order: MERGE `silver.asset_snapshots` → MERGE `silver.fx_rates` →
  MERGE `gold.ohlcv_1m` → Cloud Run job `dq-runner` → MERGE `gold.anomalies` (ADR-0010).
- MERGEs use the BigQuery `jobs.insert` connector, which blocks until the job succeeds or fails;
  a failure raises and **stops the chain** at that step.
- `dq-runner` is a container (`docker/dq-runner/`) running `tools/run_dq.py` with the attached
  identity `sa-orchestrator` (no key). Exit 1 = blocking DQ failure → workflow fails.
- SQL is **injected from `sql/` at deploy time** via Terraform `templatefile()`, so the repo's
  `.sql` files are the single source of truth.
- Schedule at :05/:35 so each run follows a fresh CoinGecko snapshot.

## Alternatives considered
| Option | Why not |
|---|---|
| Cloud Composer (Airflow) | Always-on environment (hundreds of $/month) for a 5-step chain |
| Cron on a VM | A server to patch; no retries, step history or IAM-native identity |
| Scheduled queries in BigQuery | No ordering across steps, no DQ gate, no stop-on-failure |
| SQL copied into the YAML | Two copies drift apart |

## Consequences
- (+) Per-step billing; effectively free at 48 runs/day. Every run is visible with its step
  history; failures name the step.
- (+) Least privilege: `sa-orchestrator` has `run.invoker` on **dq-runner only**,
  `run.viewer` (to poll the execution), `logging.logWriter`; `sa-deployer` may actAs
  `sa-orchestrator` only to attach it to the job.
- (−) Changing a `.sql` file requires `terraform apply` to redeploy the workflow.
- (−) DQ checks are baked into the `dq-runner` image: adding a check means rebuild + redeploy.
- (−) `roles/workflows.invoker` for `sa-scheduler` is project-level (no per-workflow IAM).

## Lessons recorded
1. **CRLF broke the first run**: Windows line endings made `\r` reach BigQuery as literal text
   ("Expected keyword USING but got \\"). Fix: `replace(file(...), "\r\n", "\n")` before
   `jsonencode`. Injected text must be OS-independent.
2. **Terraform templates interpolate inside comments**: `${...}` in a YAML comment broke the
   render. Use `$${...}` for Workflows expressions and keep `${` out of comments.
3. **Declare variables before a `try` block** if later steps read them (`dq_execution: {}` in `init`).
4. **Cloud Run credentials report "default" until refreshed**: `run_dq.py` calls
   `creds.refresh()` (with an explicit cloud-platform scope) before checking its identity.
5. **Stop-on-failure was proven by a real failure**: the CRLF run failed at
   `merge_asset_snapshots` in 0.6 s, wrote nothing, and the next run recovered all rows.
6. **When reviewing a plan, check what disappears, not only what is added**: a template
   accidentally truncated to its last steps was caught only because Workflows rejected it.