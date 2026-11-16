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
# Phase 9: CoinGecko snapshots, parsed from Bronze JSON by SQL (ELT).
resource "google_bigquery_table" "silver_asset_snapshots" {
  dataset_id = google_bigquery_dataset.layer["silver"].dataset_id
  table_id   = "asset_snapshots"

  time_partitioning {
    type  = "DAY"
    field = "snapshot_ts" # CoinGecko last_updated = event time
  }
  require_partition_filter = true
  clustering               = ["coin_id"]

  schema = jsonencode([
    { name = "coin_id", type = "STRING", mode = "REQUIRED" },
    { name = "symbol", type = "STRING", mode = "NULLABLE" },
    { name = "name", type = "STRING", mode = "NULLABLE" },
    { name = "snapshot_ts", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "price_usd", type = "NUMERIC", mode = "REQUIRED" },
    { name = "market_cap_usd", type = "NUMERIC", mode = "NULLABLE" },
    { name = "market_cap_rank", type = "INT64", mode = "NULLABLE" },
    { name = "volume_24h_usd", type = "NUMERIC", mode = "NULLABLE" },
    { name = "high_24h_usd", type = "NUMERIC", mode = "NULLABLE" },
    { name = "low_24h_usd", type = "NUMERIC", mode = "NULLABLE" },
    { name = "price_change_pct_24h", type = "NUMERIC", mode = "NULLABLE" },
    { name = "circulating_supply", type = "NUMERIC", mode = "NULLABLE" },
    { name = "total_supply", type = "NUMERIC", mode = "NULLABLE" },
    { name = "max_supply", type = "NUMERIC", mode = "NULLABLE" },
    { name = "ingest_ts", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "publish_time", type = "TIMESTAMP", mode = "REQUIRED" },
  ])
}
# Phase 9: daily ECB reference rates. Tiny table (~260 rows/year): no partitioning needed.
resource "google_bigquery_table" "silver_fx_rates" {
  dataset_id = google_bigquery_dataset.layer["silver"].dataset_id
  table_id   = "fx_rates"
  clustering = ["base_currency", "quote_currency"]

  schema = jsonencode([
    { name = "rate_date", type = "DATE", mode = "REQUIRED" },
    { name = "base_currency", type = "STRING", mode = "REQUIRED" },
    { name = "quote_currency", type = "STRING", mode = "REQUIRED" },
    { name = "rate", type = "NUMERIC", mode = "REQUIRED" },
    { name = "provider", type = "STRING", mode = "REQUIRED" },
    { name = "ingest_ts", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "publish_time", type = "TIMESTAMP", mode = "REQUIRED" },
  ])
}