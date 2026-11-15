# Phase 7: resources for the streaming Silver pipeline (Dataflow).

locals {
  dataflow_worker_member = "serviceAccount:${google_service_account.workload["sa-dataflow-worker"].email}"
  deployer_member        = "serviceAccount:${google_service_account.workload["sa-cicd-deployer"].email}"
}

# Dataflow's own copy of every trade message. Bronze and archive have theirs.
resource "google_pubsub_subscription" "dataflow_trades" {
  name  = "coinbase-trades-to-dataflow"
  topic = google_pubsub_topic.main["coinbase-trades"].id

  ack_deadline_seconds       = 60
  message_retention_duration = "86400s" # 1 day of backlog while the job is stopped

  expiration_policy {
    ttl = "" # never auto-delete when idle
  }
}

# Least privilege: read THIS subscription only, not the whole project.
resource "google_pubsub_subscription_iam_member" "dataflow_subscriber" {
  subscription = google_pubsub_subscription.dataflow_trades.name
  role         = "roles/pubsub.subscriber"
  member       = local.dataflow_worker_member
}

resource "google_pubsub_subscription_iam_member" "dataflow_viewer" {
  subscription = google_pubsub_subscription.dataflow_trades.name
  role         = "roles/pubsub.viewer"
  member       = local.dataflow_worker_member
}

# ---------------------------------------------------------------------------
# Part 3a: what's needed to LAUNCH and RUN the job on Dataflow
# ---------------------------------------------------------------------------

# Staging (uploaded code) and temp files for Dataflow. Short-lived, private.
resource "google_storage_bucket" "dataflow" {
  name                        = "${var.project_id}-dataflow"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true # only temp files; lets Phase 17 teardown remove it

  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }
}

# WORKER: read/write its own temp and staging files, in this bucket only.
resource "google_storage_bucket_iam_member" "dataflow_worker_temp" {
  bucket = google_storage_bucket.dataflow.name
  role   = "roles/storage.objectAdmin"
  member = local.dataflow_worker_member
}

# LAUNCHER: upload the pipeline package, in this bucket only.
resource "google_storage_bucket_iam_member" "deployer_stages_code" {
  bucket = google_storage_bucket.dataflow.name
  role   = "roles/storage.objectAdmin"
  member = local.deployer_member
}

# LAUNCHER: create, inspect, drain and cancel Dataflow jobs.
resource "google_project_iam_member" "deployer_dataflow_developer" {
  project = var.project_id
  role    = "roles/dataflow.developer"
  member  = local.deployer_member
}

# LAUNCHER: read machine types and other Compute settings at launch.
resource "google_project_iam_member" "deployer_compute_viewer" {
  project = var.project_id
  role    = "roles/compute.viewer"
  member  = local.deployer_member
}

# LAUNCHER may run jobs AS the worker SA, and as no other SA.
resource "google_service_account_iam_member" "deployer_acts_as_dataflow_worker" {
  service_account_id = google_service_account.workload["sa-dataflow-worker"].name
  role               = "roles/iam.serviceAccountUser"
  member             = local.deployer_member
}