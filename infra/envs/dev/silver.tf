# Phase 7: Silver tables written by the streaming pipeline.

resource "google_bigquery_table" "silver_trades" {
  dataset_id = google_bigquery_dataset.layer["silver"].dataset_id
  table_id   = "trades"

  time_partitioning {
    type  = "DAY"
    field = "trade_ts" # partition by EVENT time
  }
  require_partition_filter = true
  clustering               = ["product_id"]

  schema = jsonencode([
    { name = "product_id", type = "STRING", mode = "REQUIRED" },
    { name = "trade_id", type = "INT64", mode = "REQUIRED" },
    { name = "price", type = "NUMERIC", mode = "REQUIRED" },
    { name = "size", type = "NUMERIC", mode = "REQUIRED" },
    { name = "side", type = "STRING", mode = "REQUIRED" },
    { name = "trade_ts", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "ingest_ts", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "processed_ts", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "maker_order_id", type = "STRING", mode = "NULLABLE" },
    { name = "taker_order_id", type = "STRING", mode = "NULLABLE" },
    { name = "sequence", type = "INT64", mode = "NULLABLE" },
  ])
}

resource "google_bigquery_table" "silver_trades_quarantine" {
  dataset_id = google_bigquery_dataset.layer["silver"].dataset_id
  table_id   = "trades_quarantine"

  time_partitioning {
    type  = "DAY"
    field = "quarantined_ts"
  }
  require_partition_filter = true

  schema = jsonencode([
    { name = "error", type = "STRING", mode = "REQUIRED" },
    { name = "raw", type = "STRING", mode = "NULLABLE" },
    { name = "quarantined_ts", type = "TIMESTAMP", mode = "REQUIRED" },
  ])
}