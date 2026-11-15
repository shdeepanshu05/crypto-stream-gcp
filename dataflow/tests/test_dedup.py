"""Tests DedupTrades with TestStream: a fake stream where we control the watermark."""
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions, StandardOptions
from apache_beam.testing.test_stream import TestStream as BeamTestStream
from apache_beam.testing.util import assert_that, equal_to
from apache_beam.transforms.window import TimestampedValue

from crypto_silver.dedup import DedupTrades, dedup_key


def trade(trade_id: int) -> dict:
    return {"product_id": "BTC-USD", "trade_id": trade_id}


def run_dedup(stream: BeamTestStream, expected_ids: list) -> None:
    options = PipelineOptions([])
    options.view_as(StandardOptions).streaming = True
    with beam.Pipeline(options=options) as p:
        ids = (
            p
            | stream
            | beam.Map(dedup_key)
            | beam.ParDo(DedupTrades(horizon_seconds=600))
            | beam.Map(lambda row: row["trade_id"])
        )
        assert_that(ids, equal_to(expected_ids))


def test_redelivery_within_horizon_is_dropped():
    stream = (
        BeamTestStream()
        .add_elements([TimestampedValue(trade(1), 0), TimestampedValue(trade(2), 1)])
        .add_elements([TimestampedValue(trade(1), 30)])  # trade 1 redelivered 30 s later
        .advance_watermark_to_infinity()
    )
    run_dedup(stream, expected_ids=[1, 2])


def test_same_trade_after_horizon_passes_again():
    stream = (
        BeamTestStream()
        .add_elements([TimestampedValue(trade(1), 0)])
        .advance_watermark_to(700)                        # passes 0 + 600, so the alarm rings and state is cleared
        .add_elements([TimestampedValue(trade(1), 800)])  # same trade, after the horizon
        .advance_watermark_to_infinity()
    )
    run_dedup(stream, expected_ids=[1, 1])