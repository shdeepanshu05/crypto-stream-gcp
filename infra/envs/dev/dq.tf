# Phase 10: data-quality results. One row per check per run.
locals {
  dq_orchestrator_member = "serviceAccount:sa-orchestrator@${google_bigquery_dataset.layer["gold"].project}.iam.gserviceaccount.com"
}

resource "google_bigquery_dataset" "ops" {
  dataset_id                 = "ops"
  location                   = google_bigquery_dataset.layer["gold"].location
  description                = "Operational data: data-quality results (Phase 10)."
  delete_contents_on_destroy = true
}

resource "google_bigquery_table" "dq_results" {
  dataset_id          = google_bigquery_dataset.ops.dataset_id
  table_id            = "dq_results"
  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "run_ts"
  }
  clustering = ["check_name"]

  schema = jsonencode([
    { name = "run_id", type = "STRING", mode = "REQUIRED" },
    { name = "run_ts", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "check_name", type = "STRING", mode = "REQUIRED" },
    { name = "layer", type = "STRING", mode = "NULLABLE" },
    { name = "severity", type = "STRING", mode = "REQUIRED" },
    { name = "failed_count", type = "INT64", mode = "NULLABLE" },
    { name = "passed", type = "BOOL", mode = "REQUIRED" },
    { name = "details", type = "STRING", mode = "NULLABLE" },
  ])
}

# Resource-level: the orchestrator can write ONLY to the ops dataset (not project-wide).
resource "google_bigquery_dataset_iam_member" "orchestrator_writes_ops" {
  dataset_id = google_bigquery_dataset.ops.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = local.dq_orchestrator_member
}

# Phase 11: the deployer may attach sa-orchestrator to the dq-runner Cloud Run job (and nothing else).
resource "google_service_account_iam_member" "deployer_acts_as_orchestrator" {
  service_account_id = "projects/${google_bigquery_dataset.layer["gold"].project}/serviceAccounts/sa-orchestrator@${google_bigquery_dataset.layer["gold"].project}.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:sa-cicd-deployer@${google_bigquery_dataset.layer["gold"].project}.iam.gserviceaccount.com"
}