"""Shared validation: turns one raw Coinbase envelope into a typed Silver row.

Used by both the batch pipeline (lines from archive files) and the streaming
pipeline (messages from Pub/Sub). Keeping it in one module means both
pipelines validate trades identically.
"""
import json
from datetime import datetime
from decimal import Decimal, InvalidOperation

import apache_beam as beam
from apache_beam.metrics import Metrics

INVALID = "invalid"
ALLOWED_PRODUCTS = {"BTC-USD", "ETH-USD"}
REQUIRED_FIELDS = ("trade_id", "product_id", "price", "size", "side", "time")


def to_silver_row(line) -> dict:
    """Validate one raw message and return a Silver row.

    Raises ValueError with a short reason code if the message is invalid.
    """
    if isinstance(line, bytes):
        line = line.decode("utf-8", errors="replace")

    try:
        envelope = json.loads(line)
    except json.JSONDecodeError:
        raise ValueError("not_json")

    if not isinstance(envelope, dict):
        raise ValueError("not_an_object")
    if envelope.get("schema_version") != "v1":
        raise ValueError("unknown_schema_version")
    if envelope.get("source") != "coinbase":
        raise ValueError("unexpected_source")

    payload = envelope.get("payload")
    if not isinstance(payload, dict) or payload.get("type") != "match":
        raise ValueError("not_a_trade")

    missing = [f for f in REQUIRED_FIELDS if payload.get(f) in (None, "")]
    if missing:
        raise ValueError("missing_fields:" + ",".join(missing))

    if payload["product_id"] not in ALLOWED_PRODUCTS:
        raise ValueError("unknown_product")

    try:
        trade_id = int(payload["trade_id"])
        price = Decimal(str(payload["price"]))
        size = Decimal(str(payload["size"]))
    except (InvalidOperation, ValueError, TypeError):
        raise ValueError("bad_number")

    if price <= 0 or size <= 0:
        raise ValueError("non_positive_price_or_size")

    if payload["side"] not in ("buy", "sell"):
        raise ValueError("bad_side")

    try:
        trade_ts = datetime.fromisoformat(payload["time"].replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        raise ValueError("bad_timestamp")

    return {
        "product_id": payload["product_id"],
        "trade_id": trade_id,
        "price": str(price),
        "size": str(size),
        "side": payload["side"],
        "trade_ts": trade_ts.isoformat(),  # EVENT time: when the trade happened
        "ingest_ts": envelope.get("ingest_ts"),
        "maker_order_id": payload.get("maker_order_id"),
        "taker_order_id": payload.get("taker_order_id"),
        "sequence": payload.get("sequence"),
    }


class ParseAndValidate(beam.DoFn):
    """Valid rows go to the main output; invalid ones go to the INVALID tag."""

    def __init__(self):
        self.valid = Metrics.counter("silver", "valid_rows")
        self.invalid = Metrics.counter("silver", "invalid_rows")

    def process(self, line):
        try:
            row = to_silver_row(line)
        except ValueError as exc:
            self.invalid.inc()
            raw = line.decode("utf-8", errors="replace") if isinstance(line, bytes) else line
            yield beam.pvalue.TaggedOutput(INVALID, {"error": str(exc), "raw": raw[:2000]})
            return
        self.valid.inc()
        yield row