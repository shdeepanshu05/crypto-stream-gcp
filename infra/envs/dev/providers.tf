provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    project    = "crypto-stream"
    env        = "dev"
    managed_by = "terraform"
  }
}