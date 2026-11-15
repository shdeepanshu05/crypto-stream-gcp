# Phase 8: run the REST publisher Cloud Run jobs on a schedule.
# The Cloud Run jobs themselves are deployed by sa-cicd-deployer (gcloud, later CI),
# like the worker pool. Terraform owns only the triggers and who may fire them.

locals {
  scheduler_member = "serviceAccount:${google_service_account.workload["sa-scheduler"].email}"

  scheduled_jobs = {
    coingecko-snapshot = {
      schedule    = "*/10 * * * *" # every 10 minutes, ~4,320 calls/month (Demo cap 10k)
      description = "CoinGecko BTC/ETH market snapshot"
    }
    fx-rates = {
      schedule    = "30 16 * * 1-5" # weekdays 16:30 UTC, after the ECB's daily publication
      description = "Frankfurter ECB USD/INR rates"
    }
  }
}

# sa-scheduler may START these two jobs, and nothing else.
resource "google_cloud_run_v2_job_iam_member" "scheduler_runs_job" {
  for_each = local.scheduled_jobs

  name     = each.key
  location = var.region
  role     = "roles/run.invoker"
  member   = local.scheduler_member
}

resource "google_cloud_scheduler_job" "run_job" {
  for_each = local.scheduled_jobs

  name             = "${each.key}-trigger"
  description      = each.value.description
  region           = var.region
  schedule         = each.value.schedule
  time_zone        = "Etc/UTC"
  attempt_deadline = "180s"

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${each.key}:run"

    oauth_token {
      service_account_email = google_service_account.workload["sa-scheduler"].email
    }
  }

  depends_on = [
    google_project_service.enabled,
    google_cloud_run_v2_job_iam_member.scheduler_runs_job,
  ]
}