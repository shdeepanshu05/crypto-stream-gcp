# Phase 9: Gold tables, business-ready aggregates read by dashboards.

resource "google_bigquery_table" "gold_ohlcv_1m" {
  dataset_id = google_bigquery_dataset.layer["gold"].dataset_id
  table_id   = "ohlcv_1m"

  time_partitioning {
    type  = "DAY"
    field = "minute_start"
  }
  require_partition_filter = true
  clustering               = ["product_id"]

  schema = jsonencode([
    { name = "product_id", type = "STRING", mode = "REQUIRED" },
    { name = "minute_start", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "open", type = "NUMERIC", mode = "REQUIRED" },
    { name = "high", type = "NUMERIC", mode = "REQUIRED" },
    { name = "low", type = "NUMERIC", mode = "REQUIRED" },
    { name = "close", type = "NUMERIC", mode = "REQUIRED" },
    { name = "volume", type = "NUMERIC", mode = "REQUIRED" },
    { name = "quote_volume_usd", type = "NUMERIC", mode = "REQUIRED" },
    { name = "vwap", type = "NUMERIC", mode = "NULLABLE" },
    { name = "trade_count", type = "INT64", mode = "REQUIRED" },
    { name = "taker_buy_volume", type = "NUMERIC", mode = "REQUIRED" },
    { name = "taker_sell_volume", type = "NUMERIC", mode = "REQUIRED" },
    { name = "first_trade_id", type = "INT64", mode = "REQUIRED" },
    { name = "last_trade_id", type = "INT64", mode = "REQUIRED" },
    { name = "updated_at", type = "TIMESTAMP", mode = "REQUIRED" },
  ])
}
# Phase 9: candles in INR via an as-of FX join. A VIEW: stores nothing, always in sync.
# The SQL lives in sql/gold/views/ (one source of truth), and Terraform deploys it.
resource "google_bigquery_table" "gold_ohlcv_1m_inr" {
  dataset_id          = google_bigquery_dataset.layer["gold"].dataset_id
  table_id            = "ohlcv_1m_inr"
  deletion_protection = false # a view holds no data

  view {
    query          = file("${path.module}/../../../sql/gold/views/ohlcv_1m_inr.sql")
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.gold_ohlcv_1m]
}