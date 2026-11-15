# Phase 7: resources for the streaming Silver pipeline (Dataflow).

locals {
  dataflow_worker_member = "serviceAccount:sa-dataflow-worker@${var.project_id}.iam.gserviceaccount.com"
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