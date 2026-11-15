"""The rows we build must match the BigQuery schemas defined in silver.tf."""
from pipeline_streaming import to_bq_row, to_quarantine_row

SILVER_TRADES_COLUMNS = {
    "product_id", "trade_id", "price", "size", "side", "trade_ts",
    "ingest_ts", "processed_ts", "maker_order_id", "taker_order_id", "sequence",
}
QUARANTINE_COLUMNS = {"error", "raw", "quarantined_ts"}


def sample_silver_row() -> dict:
    return {
        "product_id": "BTC-USD", "trade_id": 1127332258, "price": "64275.01",
        "size": "0.00000413", "side": "buy", "trade_ts": "2026-11-15T06:02:49.290892+00:00",
        "ingest_ts": "2026-11-15T06:02:49.312090+00:00", "maker_order_id": "m",
        "taker_order_id": "t", "sequence": 139458236777,
    }


def test_bq_row_matches_silver_schema_and_keeps_exact_decimals():
    out = to_bq_row(sample_silver_row())
    assert set(out) == SILVER_TRADES_COLUMNS
    assert out["price"] == "64275.01"
    assert out["size"] == "0.00000413"
    assert out["processed_ts"].endswith("+00:00")


def test_quarantine_row_matches_schema():
    out = to_quarantine_row({"error": "not_json", "raw": "iam-test"})
    assert set(out) == QUARANTINE_COLUMNS
    assert out["error"] == "not_json"