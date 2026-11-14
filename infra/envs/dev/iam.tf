# ---------- Workload service accounts ----------
locals {
  workload_sas = {
    "sa-cicd-deployer"    = "Deploys code from GitHub Actions"
    "sa-ingest-run"       = "Publishes API data to Pub/Sub"
    "sa-pubsub-bq-writer" = "Writes Pub/Sub messages into Bronze"
    "sa-dataflow-worker"  = "Runs Dataflow streaming workers"
    "sa-orchestrator"     = "Runs Workflows and SQL transformations"
    "sa-scheduler"        = "Triggers scheduled jobs"
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