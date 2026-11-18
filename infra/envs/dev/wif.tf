# ---------- Workload Identity Federation: GitHub Actions -> GCP, no keys ----------
locals {
  github_repository = "shdeepanshu05/crypto-stream-gcp"
}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  description               = "Keyless auth for GitHub Actions (ADR-0013)"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  # Which GitHub token claims Google keeps, and under what names
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Front-desk rule: only THIS repo, only the main branch. Everything else is rejected.
  attribute_condition = "assertion.repository == '${local.github_repository}' && assertion.ref == 'refs/heads/main'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# GitHub runs from this repo may impersonate sa-cicd-deployer, and nothing else
resource "google_service_account_iam_member" "github_impersonates_deployer" {
  service_account_id = google_service_account.workload["sa-cicd-deployer"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${local.github_repository}"
}

# GitHub needs this full name in the workflow file
output "github_wif_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
}