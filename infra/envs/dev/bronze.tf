# One raw table per topic. Bronze stores every message exactly as received.
resource "google_bigquery_table" "bronze_raw" {
  for_each = local.topics

  dataset_id = google_bigquery_dataset.layer["bronze"].dataset_id
  table_id   = replace(each.value, "-", "_") # coinbase-trades -> coinbase_trades

  time_partitioning {
    type  = "DAY"
    field = "publish_time"
  }

  # Every query must filter on publish_time, so nobody scans all history by accident (NFR-13)
  require_partition_filter = true

  schema = jsonencode([
    { name = "subscription_name", type = "STRING", mode = "NULLABLE" },
    { name = "message_id", type = "STRING", mode = "NULLABLE" },
    { name = "publish_time", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "data", type = "STRING", mode = "NULLABLE", description = "Raw message body (our envelope JSON)" },
    { name = "attributes", type = "JSON", mode = "NULLABLE" },
  ])
}