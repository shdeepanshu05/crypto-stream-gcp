"""Phase 8 Part 3: batch backfill of Silver trades from the raw GCS archive.

Archive JSONL -> the same validation as streaming (crypto_silver.parse)
-> silver.trades_backfill (staging, replaced every run via WRITE_TRUNCATE).
A MERGE (sql/silver/merge_trades_backfill.sql) then inserts only missing trades.
"""
import argparse
import logging
from datetime import datetime, timezone

import apache_beam as beam
from apache_beam.metrics.metric import MetricsFilter
from apache_beam.options.pipeline_options import PipelineOptions

from crypto_silver.parse import INVALID, ParseAndValidate


def add_processed_ts(row: dict) -> dict:
    return {**row, "processed_ts": datetime.now(timezone.utc).isoformat()}


def run(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="gs://.../coinbase-trades/DATE/*.jsonl")
    parser.add_argument("--staging_table", required=True, help="PROJECT:silver.trades_backfill")
    args, beam_args = parser.parse_known_args(argv)

    pipeline = beam.Pipeline(options=PipelineOptions(beam_args))

    results = (
        pipeline
        | "ReadArchive" >> beam.io.ReadFromText(args.input, validate = False)
        | "ParseAndValidate" >> beam.ParDo(ParseAndValidate()).with_outputs(INVALID, main="valid")
    )

    _ = (
        results.valid
        | "AddProcessedTs" >> beam.Map(add_processed_ts)
        | "WriteStaging" >> beam.io.WriteToBigQuery(
            table=args.staging_table,
            method=beam.io.WriteToBigQuery.Method.FILE_LOADS,           # batch load jobs: free
            create_disposition=beam.io.BigQueryDisposition.CREATE_NEVER,  # Terraform owns the table
            write_disposition=beam.io.BigQueryDisposition.WRITE_TRUNCATE, # replace staging each run
        )
    )
    # Invalid rows are only counted here (invalid_rows metric). Streaming already
    # quarantines them live; re-writing them on every backfill would duplicate quarantine.

    result = pipeline.run()
    result.wait_until_finish()  # batch: block until done

    for counter in result.metrics().query(MetricsFilter().with_namespace("silver"))["counters"]:
        print(f"{counter.key.metric.name}: {counter.committed}")


if __name__ == "__main__":
    logging.getLogger().setLevel(logging.INFO)
    run()