# ---------- Workload service accounts ----------
locals {
  workload_sas = {
    "sa-cicd-deployer"     = "Deploys code from GitHub Actions"
    "sa-ingest-run"        = "Publishes API data to Pub/Sub"
    "sa-pubsub-bq-writer"  = "Writes Pub/Sub messages into Bronze"
    "sa-dataflow-worker"   = "Runs Dataflow streaming workers"
    "sa-orchestrator"      = "Runs Workflows and SQL transformations"
    "sa-scheduler"         = "Triggers scheduled jobs"
    "sa-pubsub-gcs-writer" = "Writes Pub/Sub messages into the raw archive bucket"
  }

  sa = { for name, sa in google_service_account.workload : name => "serviceAccount:${sa.email}" }
}

resource "google_service_account" "workload" {
  for_each = local.workload_sas

  account_id   = each.key
  display_name = each.key
  description  = each.value
}

# ---------- sa-ingest-run: publish to each main topic (topic-level) ----------
resource "google_pubsub_topic_iam_member" "ingest_publisher" {
  for_each = google_pubsub_topic.main

  topic  = each.value.name
  role   = "roles/pubsub.publisher"
  member = local.sa["sa-ingest-run"]
}

# ---------- sa-pubsub-bq-writer: write raw data into bronze only (dataset-level) ----------
resource "google_bigquery_dataset_iam_member" "bq_writer_bronze" {
  dataset_id = google_bigquery_dataset.layer["bronze"].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = local.sa["sa-pubsub-bq-writer"]
}

# ---------- sa-dataflow-worker ----------
resource "google_project_iam_member" "dataflow_worker" {
  project = var.project_id
  role    = "roles/dataflow.worker"
  member  = local.sa["sa-dataflow-worker"]
}

resource "google_bigquery_dataset_iam_member" "dataflow_writes" {
  for_each = toset(["silver", "gold"])

  dataset_id = google_bigquery_dataset.layer[each.value].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = local.sa["sa-dataflow-worker"]
}

# ---------- sa-orchestrator ----------
resource "google_project_iam_member" "orchestrator_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = local.sa["sa-orchestrator"]
}

resource "google_bigquery_dataset_iam_member" "orchestrator_reads_bronze" {
  dataset_id = google_bigquery_dataset.layer["bronze"].dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = local.sa["sa-orchestrator"]
}

resource "google_bigquery_dataset_iam_member" "orchestrator_writes" {
  for_each = toset(["silver", "gold"])

  dataset_id = google_bigquery_dataset.layer[each.value].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = local.sa["sa-orchestrator"]
}
# Local testing: the admin may impersonate sa-ingest-run (Token Creator on this SA only)
resource "google_service_account_iam_member" "admin_impersonates_ingest" {
  service_account_id = google_service_account.workload["sa-ingest-run"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${var.admin_email}"
}
# ---------- sa-cicd-deployer: deploy code, never touch data ----------
resource "google_artifact_registry_repository_iam_member" "deployer_pushes_images" {
  location   = google_artifact_registry_repository.containers.location
  repository = google_artifact_registry_repository.containers.name
  role       = "roles/artifactregistry.writer"
  member     = local.sa["sa-cicd-deployer"]
}

resource "google_project_iam_member" "deployer_run_developer" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = local.sa["sa-cicd-deployer"]
}

# The deployer may attach sa-ingest-run to Cloud Run (actAs), but cannot become it
resource "google_service_account_iam_member" "deployer_acts_as_ingest" {
  service_account_id = google_service_account.workload["sa-ingest-run"].name
  role               = "roles/iam.serviceAccountUser"
  member             = local.sa["sa-cicd-deployer"]
}

# Local deploys until Phase 15 (then GitHub Actions takes over and this is removed)
resource "google_service_account_iam_member" "admin_impersonates_deployer" {
  service_account_id = google_service_account.workload["sa-cicd-deployer"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${var.admin_email}"
}