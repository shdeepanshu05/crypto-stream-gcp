# Phase 11: orchestration. Scheduler -> Workflow (sa-orchestrator) -> 3 MERGEs -> dq-runner.
locals {
  wf_project          = google_bigquery_dataset.layer["gold"].project
  wf_region           = "us-central1"
  wf_orchestrator_sa  = "sa-orchestrator@${google_bigquery_dataset.layer["gold"].project}.iam.gserviceaccount.com"
  wf_scheduler_member = "serviceAccount:sa-scheduler@${google_bigquery_dataset.layer["gold"].project}.iam.gserviceaccount.com"
}

# --- What the workflow identity (sa-orchestrator) needs ---

# Execute ONLY the dq-runner job (resource-level, not project-wide).
resource "google_cloud_run_v2_job_iam_member" "orchestrator_runs_dq" {
  project  = local.wf_project
  location = local.wf_region
  name     = "dq-runner"
  role     = "roles/run.invoker"
  member   = local.dq_orchestrator_member
}

# Read-only: lets the connector poll the execution's long-running operation.
resource "google_project_iam_member" "orchestrator_run_viewer" {
  project = local.wf_project
  role    = "roles/run.viewer"
  member  = local.dq_orchestrator_member
}

# Workflows writes step/error logs as the workflow identity.
resource "google_project_iam_member" "orchestrator_log_writer" {
  project = local.wf_project
  role    = "roles/logging.logWriter"
  member  = local.dq_orchestrator_member
}

resource "google_workflows_workflow" "elt_pipeline" {
  name            = "elt-pipeline"
  region          = local.wf_region
  description     = "Silver/Gold MERGEs then data-quality checks (Phase 11)."
  service_account = local.wf_orchestrator_sa
  call_log_level  = "LOG_ERRORS_ONLY"

   source_contents = templatefile("${path.module}/workflows/elt_pipeline.yaml.tftpl", {
    sql_asset_snapshots = jsonencode(replace(file("${path.module}/../../../sql/silver/merge_asset_snapshots.sql"), "\r\n", "\n"))
    sql_fx_rates        = jsonencode(replace(file("${path.module}/../../../sql/silver/merge_fx_rates.sql"), "\r\n", "\n"))
    sql_ohlcv_1m        = jsonencode(replace(file("${path.module}/../../../sql/gold/merge_ohlcv_1m.sql"), "\r\n", "\n"))
  })
  depends_on = [
    google_cloud_run_v2_job_iam_member.orchestrator_runs_dq,
    google_project_iam_member.orchestrator_run_viewer,
    google_project_iam_member.orchestrator_log_writer,
  ]
}

# --- Trigger: Scheduler (sa-scheduler) starts an execution ---

# Workflows IAM is project-level only (no per-workflow binding), so this is the narrowest option.
resource "google_project_iam_member" "scheduler_invokes_workflows" {
  project = local.wf_project
  role    = "roles/workflows.invoker"
  member  = local.wf_scheduler_member
}

resource "google_cloud_scheduler_job" "elt_pipeline_trigger" {
  name             = "elt-pipeline-trigger"
  region           = local.wf_region
  schedule         = "5,35 * * * *" # 5 min after the CoinGecko snapshot at :00/:30
  time_zone        = "Etc/UTC"
  attempt_deadline = "180s"

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/${google_workflows_workflow.elt_pipeline.id}/executions"
    body        = base64encode(jsonencode({ argument = "{}" }))
    headers     = { "Content-Type" = "application/json" }

    oauth_token {
      service_account_email = "sa-scheduler@${local.wf_project}.iam.gserviceaccount.com"
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [google_project_iam_member.scheduler_invokes_workflows]
}