
# ---------- Raw archive bucket ----------
resource "google_storage_bucket" "raw_archive" {
  name     = "${var.project_id}-raw-archive"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # NFR-10: archive keeps 30 days, then files are deleted automatically
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

# The archive writer can create files and read bucket metadata, on this bucket only
resource "google_storage_bucket_iam_member" "gcs_writer_creates" {
  bucket = google_storage_bucket.raw_archive.name
  role   = "roles/storage.objectCreator"
  member = local.sa["sa-pubsub-gcs-writer"]
}

resource "google_storage_bucket_iam_member" "gcs_writer_reads_bucket" {
  bucket = google_storage_bucket.raw_archive.name
  role   = "roles/storage.legacyBucketReader"
  member = local.sa["sa-pubsub-gcs-writer"]
}

# The Pub/Sub service agent may impersonate the archive writer
resource "google_service_account_iam_member" "pubsub_agent_impersonates_gcs_writer" {
  service_account_id = google_service_account.workload["sa-pubsub-gcs-writer"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.pubsub_agent
}

# ---------- One archive subscription per topic ----------
resource "google_pubsub_subscription" "archive" {
  for_each = local.topics

  name  = "${each.value}-to-archive"
  topic = google_pubsub_topic.main[each.value].id

  # Must be at least max_duration below
  ack_deadline_seconds = 600

  cloud_storage_config {
    bucket                   = google_storage_bucket.raw_archive.name
    filename_prefix          = "${each.value}/"
    filename_datetime_format = "YYYY-MM-DD/hh_mm_ssZ"
    filename_suffix          = ".jsonl"
    max_duration             = "300s"
    service_account_email    = google_service_account.workload["sa-pubsub-gcs-writer"].email
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter[each.value].id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  message_retention_duration = "86400s"

  expiration_policy {
    ttl = ""
  }

  depends_on = [
    google_service_account_iam_member.pubsub_agent_impersonates_gcs_writer,
    google_storage_bucket_iam_member.gcs_writer_creates,
    google_storage_bucket_iam_member.gcs_writer_reads_bucket,
  ]
}

# The service agent must acknowledge dead-lettered messages on these subscriptions
resource "google_pubsub_subscription_iam_member" "agent_subscribes_archive" {
  for_each = google_pubsub_subscription.archive

  subscription = each.value.name
  role         = "roles/pubsub.subscriber"
  member       = local.pubsub_agent
}