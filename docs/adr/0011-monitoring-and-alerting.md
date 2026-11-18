# ADR-0011: Monitoring and alerting for the batch ELT pipeline

**Status:** Accepted · **Date:** 2026-11-18 · **Phase:** 12 (Observability)
**Relates to:** ADR-0008 (SQL ELT), ADR-0009 (Workflows orchestration), ADR-0010 (anomaly rules)

## Context
The `elt-pipeline` workflow runs every 30 minutes (Cloud Scheduler, `5,35 * * * *`):
MERGEs → `dq-runner` (Cloud Run job) → `merge_anomalies`. Nobody watches it.
A pipeline nobody watches fails in one of three ways, and each one needs its own signal:

| Failure mode | Example | What a naive setup sees |
|---|---|---|
| **Loud failure** | A MERGE errors, or DQ fails and the workflow stops | One FAILED execution, noticed only if someone looks |
| **Failure with detail hidden in logs** | `dq-runner` exits 1 because 2 of 8 checks failed | "Job failed": *which* check, and why, is only in the logs |
| **Silent absence** | Scheduler paused, trigger deleted, IAM broken before the workflow starts | **Nothing at all.** No run means no failure to alert on |

The third mode is the dangerous one: every failure-based alert stays quiet while the
data quietly goes stale.

## Decision
Three alert policies, one log-based metric and one dashboard, all in Terraform
(`infra/envs/dev/monitoring.tf`, `dashboard.tf`), applied by `sa-tf-provisioner`.
Notifications go to one email channel. The address is a `sensitive` Terraform variable, so
it never appears in plan output.

| # | Policy | Signal | Severity | Catches |
|---|---|---|---|---|
| 1 | `elt_pipeline_failed` | Metric `workflowexecutions … finished_execution_count`, `status = FAILED` | CRITICAL | Loud failure |
| 2 | `cloud_run_job_errors` | Log-based: `resource.type = cloud_run_job`, `severity >= ERROR`; `job_name` extracted as a label; notification rate limit 5 min | ERROR | The *reason*: which DQ check failed, with its message |
| 3 | `elt_pipeline_absent` | Metric absence: no SUCCEEDED execution for **90 min** (`condition_absent`, 5400s); auto-close 30 min | CRITICAL | Silent absence |

Supporting pieces:
- **Log-based metric `dq_check_failures`:** counts DQ check results logged at ERROR, so DQ
  health can be charted over time, not just alerted on.
- **Dashboard `pipeline_health`** (as code): executions by status, DQ failures, job errors.
  The JSON is normalised to the API's stored form (e.g. `targetAxis = "Y1"`, zero positions
  omitted) so `terraform plan` shows no perpetual diff.
- Every policy has a **documentation block** with the first commands to run, so the alert
  email is also the start of the runbook.

### Why this works: the runner logs structured JSON
`dq-runner` writes one JSON log line per check, with a `severity` field
(PASS → INFO, WARN → WARNING, FAIL → ERROR). Cloud Logging reads `severity` directly, so
alert 2 and the `dq_check_failures` metric need no parsing. Exit codes separate causes:
**1 = data failed checks**, **2 = wrong identity or credential problem**.

### Why 90 minutes for absence
The schedule is every 30 minutes. 90 minutes = **three missed runs**, which tolerates one slow or
skipped run without paging, but still flags a real outage within about 1.5 hours.

## IAM (least privilege)
Granted to `sa-tf-provisioner` only, recorded in `infra/bootstrap/README.md` section 13:

| Role | Needed for |
|---|---|
| `roles/monitoring.alertPolicyEditor` | Create and update alert policies |
| `roles/monitoring.notificationChannelEditor` | Create the email channel |
| `roles/logging.configWriter` | Log-based alert and log-based metric (narrowest role verified with `gcloud iam roles describe`) |
| `roles/monitoring.dashboardEditor` | The `pipeline_health` dashboard |

No broad roles (`monitoring.editor`, `editor`) are used.

## Incident: false absence alerts (fixed 2026-11-18)
**Symptom:** absence alerts at 22:45 and 23:45 on 17 Nov while the pipeline was succeeding every 30 min.
**Cause:** Cloud Monitoring evaluates absence **per time series**. The execution metric has a
`revision_id` label, and each `terraform apply` that changes the workflow creates a new revision. The old
revision's series went silent, so "absent" fired on it.
**Fix:** aggregate before applying absence logic:
`cross_series_reducer = "REDUCE_SUM"`, `group_by_fields = ["resource.label.workflow_id"]`.
One series per workflow, whatever the revision.
**Lesson:** absence conditions must aggregate away any label that changes on deploy
(revision IDs, pod names, container IDs).

## Alternatives considered
- **One alert per DQ check:** precise, but 8 policies to maintain and noisy. One log-based alert
  with the check name in the log line gives the same detail.
- **Error handling inside the workflow that sends email:** couples alerting to the code it
  monitors. If the workflow never starts, it can't report that. Absence must be observed from outside.
- **Slack / PagerDuty channels:** better for teams. Email is enough for a single-owner portfolio
  project, and new channels can be added without changing the policies.
- **Uptime checks:** for HTTP endpoints. This pipeline has none.

## Consequences and known gaps
- Positive: every failure mode in the context table produces an email with the cause and the first commands to run.
- **No concurrency lock:** a manual run overlapping a scheduled one is not prevented. Both succeeded so far.
- **Streaming and batch overlap:** if the stream is running while `merge_ohlcv_1m` runs, a partial
  last minute can fail the Gold-to-Silver consistency check, which triggers alerts 1 and 2. Workaround: pause the
  trigger during long streaming sessions. Planned fix: a watermark (only process minutes older
  than now − 2 min, in both the MERGE and the DQ check).
- Anomalies (ADR-0010) are shown on the dashboard but **not** alerted on. Market anomalies are
  information, not pipeline faults.
