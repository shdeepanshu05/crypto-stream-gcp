"""Phase 7, Part 1: batch Beam pipeline over archived raw messages.

Reads envelope JSON lines, validates each one, removes duplicate trades,
and writes clean Silver rows and quarantined rows to files.
Runs locally with the DirectRunner: no GCP resources, no cost.
"""

from apache_beam.metrics.metric import MetricsFilter
import argparse
import json
import logging
from datetime import datetime
from decimal import Decimal, InvalidOperation

import apache_beam as beam
from apache_beam.metrics import Metrics
from apache_beam.options.pipeline_options import PipelineOptions

INVALID = "invalid"
ALLOWED_PRODUCTS = {"BTC-USD", "ETH-USD"}
REQUIRED_FIELDS = ("trade_id", "product_id", "price", "size", "side", "time")


def to_silver_row(line: str) -> dict:
    """Validate one raw line against the trade_event contract. Raise ValueError(reason) if invalid."""
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

    p = envelope.get("payload") or {}
    if p.get("type") != "match":
        raise ValueError("not_a_trade")
    missing = [f for f in REQUIRED_FIELDS if f not in p]
    if missing:
        raise ValueError("missing_fields:" + ",".join(missing))
    if p["product_id"] not in ALLOWED_PRODUCTS:
        raise ValueError("unknown_product")
    try:
        price, size = Decimal(p["price"]), Decimal(p["size"])
    except InvalidOperation:
        raise ValueError("bad_number")
    if price <= 0 or size <= 0:
        raise ValueError("non_positive_price_or_size")
    if p["side"] not in ("buy", "sell"):
        raise ValueError("bad_side")
    try:
        trade_ts = datetime.fromisoformat(p["time"].replace("Z", "+00:00"))
    except ValueError:
        raise ValueError("bad_timestamp")

    return {
        "product_id": p["product_id"],
        "trade_id": int(p["trade_id"]),
        "price": str(price),          # exact decimal kept as text -> NUMERIC later
        "size": str(size),
        "side": p["side"],
        "trade_ts": trade_ts.isoformat(),   # EVENT time
        "ingest_ts": envelope.get("ingest_ts"),
        "maker_order_id": p.get("maker_order_id"),
        "taker_order_id": p.get("taker_order_id"),
        "sequence": p.get("sequence"),
    }


class ParseAndValidate(beam.DoFn):
    """Valid rows go to the main output; invalid ones to the 'invalid' output with a reason."""

    def __init__(self):
        self.valid = Metrics.counter("silver", "valid_rows")
        self.invalid = Metrics.counter("silver", "invalid_rows")

    def process(self, line):
        try:
            row = to_silver_row(line)
        except ValueError as exc:
            self.invalid.inc()
            yield beam.pvalue.TaggedOutput(INVALID, {"error": str(exc), "raw": line[:2000]})
            return
        self.valid.inc()
        yield row


class KeepOnePerTrade(beam.DoFn):
    """Input: ((product_id, trade_id), [rows]). Output: one row; count the extras."""

    def __init__(self):
        self.duplicates = Metrics.counter("silver", "duplicates_removed")

    def process(self, keyed):
        _, rows = keyed
        rows = list(rows)
        if len(rows) > 1:
            self.duplicates.inc(len(rows) - 1)
        yield rows[0]


def run(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="File pattern, e.g. dataflow/testdata/*.jsonl")
    parser.add_argument("--output", required=True, help="Output folder, e.g. dataflow/out/")
    args, beam_args = parser.parse_known_args(argv)

    pipeline = beam.Pipeline(options=PipelineOptions(beam_args))

    parsed = (
        pipeline
        | "ReadRawLines" >> beam.io.ReadFromText(args.input)
        | "ParseAndValidate" >> beam.ParDo(ParseAndValidate()).with_outputs(INVALID, main="valid")
    )

    (
        parsed.valid
        | "KeyByTrade" >> beam.Map(lambda r: ((r["product_id"], r["trade_id"]), r))
        | "GroupDuplicates" >> beam.GroupByKey()
        | "KeepOne" >> beam.ParDo(KeepOnePerTrade())
        | "SilverToJson" >> beam.Map(json.dumps)
        | "WriteSilver" >> beam.io.WriteToText(args.output + "silver/trades", file_name_suffix=".jsonl")
    )

    (
        parsed[INVALID]
        | "QuarantineToJson" >> beam.Map(json.dumps)
        | "WriteQuarantine" >> beam.io.WriteToText(args.output + "quarantine/rows", file_name_suffix=".jsonl")
    )

    result = pipeline.run()
    result.wait_until_finish()

    our_counters = result.metrics().query(MetricsFilter().with_namespace("silver"))["counters"]
    for counter in our_counters:
        print(f"{counter.key.metric.name}: {counter.committed}")
        


if __name__ == "__main__":
    logging.getLogger().setLevel(logging.WARNING)
    run()