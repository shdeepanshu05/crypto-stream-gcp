# The secret "box" only. The VALUE is added by hand later, never through Terraform.
resource "google_secret_manager_secret" "coingecko_api_key" {
  secret_id = "coingecko-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.enabled]
}

resource "google_secret_manager_secret_iam_member" "ingest_reads_coingecko" {
  project   = google_secret_manager_secret.coingecko_api_key.project
  secret_id = google_secret_manager_secret.coingecko_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa["sa-ingest-run"]
}