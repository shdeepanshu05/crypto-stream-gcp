"""Phase 7, Part 2: streaming Silver pipeline.

Pub/Sub (coinbase-trades-to-dataflow) -> validate -> dedup (state + event-time
timer) -> BigQuery silver.trades. Invalid messages -> silver.trades_quarantine.
Runs on Dataflow as sa-dataflow-worker (launched in Part 3).
"""
import argparse
import logging
from datetime import datetime, timezone

import apache_beam as beam
from apache_beam.io.gcp.bigquery_tools import RetryStrategy
from apache_beam.metrics import Metrics
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions

from crypto_silver.dedup import DedupTrades, dedup_key
from crypto_silver.parse import INVALID, ParseAndValidate


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def to_bq_row(row: dict) -> dict:
    """Silver row -> BigQuery row. Price/size stay strings so NUMERIC keeps exact decimals."""
    return {**row, "processed_ts": utc_now_iso()}


def to_quarantine_row(bad: dict) -> dict:
    return {"error": bad["error"], "raw": bad["raw"], "quarantined_ts": utc_now_iso()}


class LogFailedInserts(beam.DoFn):
    """Rows BigQuery permanently rejected: log them and count them, never drop silently."""

    def __init__(self, label: str):
        self.label = label
        self.failed = Metrics.counter("silver", "failed_inserts")

    def process(self, failure):
        self.failed.inc()
        logging.error("BigQuery insert failed (%s): %s", self.label, str(failure)[:2000])


def write_to_bigquery(pcoll, label: str, table: str):
    result = pcoll | f"Write{label}" >> beam.io.WriteToBigQuery(
        table=table,
        method=beam.io.WriteToBigQuery.Method.STREAMING_INSERTS,
        create_disposition=beam.io.BigQueryDisposition.CREATE_NEVER,  # Terraform owns the tables
        write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
        insert_retry_strategy=RetryStrategy.RETRY_ON_TRANSIENT_ERROR,
    )
    _ = result.failed_rows_with_errors | f"LogFailed{label}" >> beam.ParDo(LogFailedInserts(label))


def run(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--subscription", required=True,
                        help="projects/PROJECT/subscriptions/coinbase-trades-to-dataflow")
    parser.add_argument("--trades_table", required=True, help="PROJECT:silver.trades")
    parser.add_argument("--quarantine_table", required=True, help="PROJECT:silver.trades_quarantine")
    args, beam_args = parser.parse_known_args(argv)

    options = PipelineOptions(beam_args)
    options.view_as(StandardOptions).streaming = True
    pipeline = beam.Pipeline(options=options)

    results = (
        pipeline
        | "ReadPubSub" >> beam.io.ReadFromPubSub(subscription=args.subscription)
        | "ParseAndValidate" >> beam.ParDo(ParseAndValidate()).with_outputs(INVALID, main="valid")
    )

    silver = (
        results.valid
        | "KeyByTrade" >> beam.Map(dedup_key)
        | "DedupTrades" >> beam.ParDo(DedupTrades())
        | "ToBqRow" >> beam.Map(to_bq_row)
    )
    write_to_bigquery(silver, "Trades", args.trades_table)

    quarantine = results[INVALID] | "ToQuarantineRow" >> beam.Map(to_quarantine_row)
    write_to_bigquery(quarantine, "Quarantine", args.quarantine_table)

    result = pipeline.run()  # streaming: submit and return, don't block forever
    logging.info("Pipeline submitted. State: %s", result.state)


if __name__ == "__main__":
    logging.getLogger().setLevel(logging.INFO)
    run()