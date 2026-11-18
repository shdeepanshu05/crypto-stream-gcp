locals {
  services = [
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "secretmanager.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "dataflow.googleapis.com",
    "compute.googleapis.com", # Dataflow workers are Compute Engine VMs
    "cloudscheduler.googleapis.com",
    "workflows.googleapis.com",
    "workflowexecutions.googleapis.com",
    "monitoring.googleapis.com",
    "sts.googleapis.com",
    "iamcredentials.googleapis.com",
  ]
}

resource "google_project_service" "enabled" {
  for_each = toset(local.services)

  service            = each.value
  disable_on_destroy = false
}