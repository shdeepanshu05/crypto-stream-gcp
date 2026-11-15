"""Streaming-safe deduplication: per-key state plus an event-time timer.

Input elements are (key, row), where key = "product_id:trade_id".
The first row for a key is emitted. Repeats arriving within the horizon are
dropped. When the watermark passes (first-seen time + horizon), the timer fires
and the key's state is cleared, so memory doesn't grow forever.
"""
from typing import Any, Dict, Tuple

import apache_beam as beam
from apache_beam.coders import BooleanCoder
from apache_beam.metrics import Metrics
from apache_beam.transforms.timeutil import TimeDomain
from apache_beam.transforms.userstate import ReadModifyWriteStateSpec, TimerSpec, on_timer
from apache_beam.utils.timestamp import Duration

DEDUP_HORIZON_SECONDS = 600  # 10 minutes


def dedup_key(row: dict) -> Tuple[str, Dict[str, Any]]:
    """Turn a Silver row into (key, row) for DedupTrades."""
    return (f"{row['product_id']}:{row['trade_id']}", row)


class DedupTrades(beam.DoFn):
    SEEN = ReadModifyWriteStateSpec("seen", BooleanCoder())   # the notepad
    EXPIRY = TimerSpec("expiry", TimeDomain.WATERMARK)        # the alarm (event time)

    def __init__(self, horizon_seconds: int = DEDUP_HORIZON_SECONDS):
        self.horizon = Duration(seconds=horizon_seconds)
        self.duplicates = Metrics.counter("silver", "duplicates_removed")

    def process(
        self,
        element,
        timestamp=beam.DoFn.TimestampParam,
        seen=beam.DoFn.StateParam(SEEN),
        expiry=beam.DoFn.TimerParam(EXPIRY),
    ):
        _key, row = element
        if seen.read():
            self.duplicates.inc()
            return
        seen.write(True)
        expiry.set(timestamp + self.horizon)
        yield row

    @on_timer(EXPIRY)
    def forget(self, seen=beam.DoFn.StateParam(SEEN)):
        seen.clear()