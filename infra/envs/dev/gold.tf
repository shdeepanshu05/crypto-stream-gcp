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
# Phase 9: CoinGecko vs Coinbase price at the same minute (cross-source check).
resource "google_bigquery_table" "gold_price_divergence" {
  dataset_id          = google_bigquery_dataset.layer["gold"].dataset_id
  table_id            = "price_divergence"
  deletion_protection = false # a view holds no data

  view {
    query          = file("${path.module}/../../../sql/gold/views/price_divergence.sql")
    use_legacy_sql = false
  }

  depends_on = [
    google_bigquery_table.gold_ohlcv_1m,
    google_bigquery_table.silver_asset_snapshots,
  ]
}

# Phase 13: detected anomalies. One row per (rule, entity, event_ts); insert-only.
resource "google_bigquery_table" "gold_anomalies" {
  dataset_id          = google_bigquery_dataset.layer["gold"].dataset_id
  table_id            = "anomalies"
  deletion_protection = false

  time_partitioning {
    type  = "DAY"
    field = "event_ts"
  }
  clustering = ["rule", "entity"]

  schema = jsonencode([
    { name = "anomaly_id", type = "STRING", mode = "REQUIRED", description = "MD5 of rule|entity|event_ts (deterministic, makes reruns idempotent)" },
    { name = "rule", type = "STRING", mode = "REQUIRED", description = "price_jump | volume_surge | divergence_break" },
    { name = "entity", type = "STRING", mode = "REQUIRED", description = "coin_id or product_id" },
    { name = "event_ts", type = "TIMESTAMP", mode = "REQUIRED", description = "when the anomalous data point happened" },
    { name = "severity", type = "STRING", mode = "REQUIRED", description = "MEDIUM | HIGH" },
    { name = "observed", type = "FLOAT64", mode = "NULLABLE", description = "the value that was flagged" },
    { name = "baseline", type = "FLOAT64", mode = "NULLABLE", description = "what normal looked like (mean, or the allowed threshold)" },
    { name = "spread", type = "FLOAT64", mode = "NULLABLE", description = "typical variation (std dev) of the baseline" },
    { name = "zscore", type = "FLOAT64", mode = "NULLABLE", description = "standard deviations from the baseline" },
    { name = "details", type = "STRING", mode = "NULLABLE", description = "human-readable explanation" },
    { name = "detected_at", type = "TIMESTAMP", mode = "REQUIRED", description = "when the pipeline detected it" },
  ])

  depends_on = [google_bigquery_table.gold_ohlcv_1m]
}

# Phase 14: serving views for the Looker Studio dashboard (the report reads ONLY these + anomalies).
resource "google_bigquery_table" "gold_dash_asset_prices" {
  dataset_id          = google_bigquery_dataset.layer["gold"].dataset_id
  table_id            = "dash_asset_prices"
  deletion_protection = false # a view holds no data

  view {
    query          = file("${path.module}/../../../sql/gold/views/dash_asset_prices.sql")
    use_legacy_sql = false
  }

  depends_on = [
    google_bigquery_table.silver_asset_snapshots,
    google_bigquery_table.silver_fx_rates,
  ]
}

resource "google_bigquery_table" "gold_dash_pipeline_status" {
  dataset_id          = google_bigquery_dataset.layer["gold"].dataset_id
  table_id            = "dash_pipeline_status"
  deletion_protection = false # a view holds no data

  view {
    query          = file("${path.module}/../../../sql/gold/views/dash_pipeline_status.sql")
    use_legacy_sql = false
  }

  depends_on = [
    google_bigquery_table.gold_anomalies,
    google_bigquery_table.dq_results,
  ]
}