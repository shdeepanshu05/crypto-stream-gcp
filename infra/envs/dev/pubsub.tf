resource "google_pubsub_topic" "coinbase_trades" {
  name = "coinbase-trades"

  depends_on = [google_project_service.enabled]
}
resource "google_pubsub_topic" "coinbase_quotes" {
  name = "coinbase-quotes"

  depends_on = [google_project_service.enabled]
}
