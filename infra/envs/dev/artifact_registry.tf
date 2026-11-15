resource "google_artifact_registry_repository" "containers" {
  location      = var.region
  repository_id = "crypto-stream"
  format        = "DOCKER"
  description   = "Container images for crypto-stream-gcp"

  # Cost control: keep the 5 newest images, delete anything older than 30 days
  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 5
    }
  }

  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      older_than = "2592000s" # 30 days
    }
  }

  depends_on = [google_project_service.enabled]
}