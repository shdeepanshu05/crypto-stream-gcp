locals {
  topics = toset([
    "coinbase-trades",
    "coinbase-quotes",
    "coingecko-markets",
    "fx-rates",
  ])
}

resource "google_pubsub_topic" "main" {
  for_each = local.topics

  name = each.value

  depends_on = [google_project_service.enabled]
}

resource "google_pubsub_topic" "dead_letter" {
  for_each = local.topics

  name = "${each.value}-dlq"

  depends_on = [google_project_service.enabled]
}

moved {
  from = google_pubsub_topic.coinbase_trades
  to   = google_pubsub_topic.main["coinbase-trades"]
}

moved {
  from = google_pubsub_topic.coinbase_quotes
  to   = google_pubsub_topic.main["coinbase-quotes"]
}