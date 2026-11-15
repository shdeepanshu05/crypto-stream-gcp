data "google_project" "this" {}

locals {
  pubsub_agent = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# The Pub/Sub service agent may impersonate sa-pubsub-bq-writer (and nothing else)
resource "google_service_account_iam_member" "pubsub_agent_impersonates_bq_writer" {
  service_account_id = google_service_account.workload["sa-pubsub-bq-writer"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.pubsub_agent
}

# ---------- Bronze: one BigQuery subscription per topic ----------
resource "google_pubsub_subscription" "bronze" {
  for_each = local.topics

  name  = "${each.value}-to-bronze"
  topic = google_pubsub_topic.main[each.value].id

  bigquery_config {
    table                 = "${var.project_id}.${google_bigquery_dataset.layer["bronze"].dataset_id}.${google_bigquery_table.bronze_raw[each.value].table_id}"
    write_metadata        = true
    service_account_email = google_service_account.workload["sa-pubsub-bq-writer"].email
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter[each.value].id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  message_retention_duration = "86400s" # keep an unwritten backlog for 1 day

  expiration_policy {
    ttl = "" # never delete this subscription for inactivity
  }

  depends_on = [google_service_account_iam_member.pubsub_agent_impersonates_bq_writer]
}

# ---------- Dead-letter wiring ----------
# The service agent moves failed messages INTO the DLQ topics...
resource "google_pubsub_topic_iam_member" "agent_publishes_to_dlq" {
  for_each = google_pubsub_topic.dead_letter

  topic  = each.value.name
  role   = "roles/pubsub.publisher"
  member = local.pubsub_agent
}

# ...and must be able to acknowledge them on the source subscription
resource "google_pubsub_subscription_iam_member" "agent_subscribes_bronze" {
  for_each = google_pubsub_subscription.bronze

  subscription = each.value.name
  role         = "roles/pubsub.subscriber"
  member       = local.pubsub_agent
}

# A DLQ topic needs its own subscription, or dead-lettered messages are dropped too
resource "google_pubsub_subscription" "dead_letter" {
  for_each = google_pubsub_topic.dead_letter

  name                       = "${each.value.name}-sub"
  topic                      = each.value.id
  message_retention_duration = "604800s" # 7 days to inspect failures

  expiration_policy {
    ttl = ""
  }
}