locals {
  datasets = {
    bronze = { description = "Raw messages as received", partition_days = 14 }
    silver = { description = "Validated, deduplicated, typed data", partition_days = 90 }
    gold   = { description = "Facts, dimensions and anomalies", partition_days = 90 }
  }
}

resource "google_bigquery_dataset" "layer" {
  for_each = local.datasets

  dataset_id  = each.key
  location    = var.region
  description = each.value.description

  default_partition_expiration_ms = each.value.partition_days * 24 * 60 * 60 * 1000

  depends_on = [google_project_service.enabled]
}