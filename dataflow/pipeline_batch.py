"""Phase 7, Part 1: batch Beam pipeline over archived raw messages.

Reads raw Coinbase envelopes (JSON Lines) from the archive, validates them,
sends bad lines to quarantine, removes duplicate trades, and writes Silver
rows as JSON Lines. Validation logic lives in crypto_silver.parse, so the
streaming pipeline can reuse exactly the same rules.
"""
import argparse
import json
import logging

import apache_beam as beam
from apache_beam.metrics import Metrics
from apache_beam.metrics.metric import MetricsFilter
from apache_beam.options.pipeline_options import PipelineOptions

from crypto_silver.parse import INVALID, ParseAndValidate


class KeepOnePerTrade(beam.DoFn):
    """Batch dedup: after GroupByKey, keep one row per (product_id, trade_id)."""

    def __init__(self):
        self.duplicates = Metrics.counter("silver", "duplicates_removed")

    def process(self, element):
        _key, rows = element
        rows = list(rows)
        if len(rows) > 1:
            self.duplicates.inc(len(rows) - 1)
        yield rows[0]


def run(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="File pattern of raw JSONL files")
    parser.add_argument("--output", required=True, help="Output prefix, e.g. dataflow/out/")
    args, beam_args = parser.parse_known_args(argv)

    pipeline = beam.Pipeline(options=PipelineOptions(beam_args))

    results = (
        pipeline
        | "ReadRaw" >> beam.io.ReadFromText(args.input)
        | "ParseAndValidate" >> beam.ParDo(ParseAndValidate()).with_outputs(INVALID, main="valid")
    )

    (
        results.valid
        | "KeyByTrade" >> beam.Map(lambda r: ((r["product_id"], r["trade_id"]), r))
        | "GroupByTrade" >> beam.GroupByKey()
        | "KeepOnePerTrade" >> beam.ParDo(KeepOnePerTrade())
        | "SilverToJson" >> beam.Map(json.dumps)
        | "WriteSilver" >> beam.io.WriteToText(args.output + "silver/trades", file_name_suffix=".jsonl")
    )

    (
        results[INVALID]
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