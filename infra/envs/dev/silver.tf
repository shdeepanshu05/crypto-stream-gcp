# Phase 7: Silver tables written by the streaming pipeline.
# Phase 8: + backfill staging table sharing the same schema.

locals {
  # One schema for the live table and its backfill staging copy, so they can never drift apart.
  silver_trades_schema = jsonencode([
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

resource "google_bigquery_table" "silver_trades" {
  dataset_id = google_bigquery_dataset.layer["silver"].dataset_id
  table_id   = "trades"

  time_partitioning {
    type  = "DAY"
    field = "trade_ts" # partition by EVENT time
  }
  require_partition_filter = true
  clustering               = ["product_id"]

  schema = local.silver_trades_schema
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

# Phase 8: staging table for backfills from the archive. Replaced on every run;
# a MERGE copies only missing trades into silver.trades.
resource "google_bigquery_table" "silver_trades_backfill" {
  dataset_id = google_bigquery_dataset.layer["silver"].dataset_id
  table_id   = "trades_backfill"
  schema     = local.silver_trades_schema
}