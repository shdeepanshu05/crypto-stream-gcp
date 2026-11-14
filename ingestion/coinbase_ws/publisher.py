"""Coinbase WebSocket -> Pub/Sub publisher (Phase 5, Part 2: reliability).

Adds automatic reconnect with backoff, stale-connection detection, trade_id gap
detection, structured JSON logs and graceful shutdown.
"""

import asyncio
import json
import logging
import os
import random
import signal
import sys
import threading
import time
from concurrent import futures
from datetime import datetime, timezone

from google.cloud import pubsub_v1
from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed

# ---------- Configuration (environment variables) ----------
PROJECT_ID = os.environ["GCP_PROJECT_ID"]
TOPIC_ID = os.environ.get("TRADES_TOPIC", "coinbase-trades")
PRODUCTS = os.environ.get("PRODUCTS", "BTC-USD,ETH-USD").split(",")
RUN_SECONDS = int(os.environ.get("RUN_SECONDS", "0"))  # 0 = run until stopped

WS_URL = "wss://ws-feed.exchange.coinbase.com"
SCHEMA_VERSION = "v1"
STALE_SECONDS = 30          # no message at all for this long -> reconnect
MAX_BACKOFF_SECONDS = 30    # NFR-11: back within 30 s
STATS_EVERY_SECONDS = 60
SHUTDOWN_WAIT_SECONDS = 8   # Cloud Run gives ~10 s after SIGTERM

BATCH_SETTINGS = pubsub_v1.types.BatchSettings(
    max_messages=500, max_bytes=1_000_000, max_latency=1.0,  # ADR-0004
)


# ---------- Structured logging: one JSON object per line ----------
class JsonFormatter(logging.Formatter):
    """Cloud Logging reads 'severity' and 'message'; other keys become searchable fields."""

    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }
        entry.update(getattr(record, "fields", {}))
        return json.dumps(entry)


_handler = logging.StreamHandler(sys.stdout)
_handler.setFormatter(JsonFormatter())
log = logging.getLogger("coinbase-publisher")
log.setLevel(logging.INFO)
log.addHandler(_handler)


def log_event(level: int, message: str, **fields) -> None:
    log.log(level, message, extra={"fields": fields})


# ---------- Shared state (callbacks run on background threads) ----------
class Stats:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.received = 0
        self.published = 0
        self.failed = 0
        self.missing_trades = 0
        self.reconnects = 0
        self.pending: set = set()

    def snapshot(self) -> dict:
        with self.lock:
            return {
                "received": self.received,
                "published": self.published,
                "failed": self.failed,
                "pending": len(self.pending),
                "missing_trades": self.missing_trades,
                "reconnects": self.reconnects,
            }


stats = Stats()
last_trade_id: dict = {}   # product_id -> highest trade_id seen (kept across reconnects)
backoff = {"seconds": 1}


def on_publish_done(future) -> None:
    try:
        future.result()
        with stats.lock:
            stats.published += 1
    except Exception as exc:
        with stats.lock:
            stats.failed += 1
        log_event(logging.ERROR, "publish failed", error=str(exc))
    finally:
        with stats.lock:
            stats.pending.discard(future)


def check_trade_gap(product_id: str, trade_id: int) -> None:
    """FR-09: trade_ids are consecutive per product, so a jump means missed trades."""
    last = last_trade_id.get(product_id)
    if last is not None:
        if trade_id > last + 1:
            missing = trade_id - last - 1
            with stats.lock:
                stats.missing_trades += missing
            log_event(logging.WARNING, "trade_id gap detected", product_id=product_id,
                      last_trade_id=last, trade_id=trade_id, missing=missing)
        elif trade_id <= last:
            log_event(logging.WARNING, "duplicate or out-of-order trade",
                      product_id=product_id, last_trade_id=last, trade_id=trade_id)
            return  # never move the marker backwards
    last_trade_id[product_id] = trade_id


def build_envelope(msg: dict) -> bytes:
    envelope = {
        "schema_version": SCHEMA_VERSION,
        "source": "coinbase",
        "ingest_ts": datetime.now(timezone.utc).isoformat(),
        "payload": msg,
    }
    return json.dumps(envelope, separators=(",", ":")).encode("utf-8")


# ---------- One WebSocket session ----------
async def stream_once(publisher, topic_path: str, stop_event: asyncio.Event) -> None:
    async with connect(WS_URL) as ws:
        await ws.send(json.dumps({
            "type": "subscribe",
            "product_ids": PRODUCTS,
            "channels": ["matches", "heartbeat"],
        }))
        log_event(logging.INFO, "connected", products=PRODUCTS, topic=topic_path)
        backoff["seconds"] = 1          # healthy connection: reset the backoff
        next_stats = time.monotonic() + STATS_EVERY_SECONDS

        while not stop_event.is_set():
            # Heartbeats arrive every second, so silence means a dead connection.
            raw = await asyncio.wait_for(ws.recv(), timeout=STALE_SECONDS)
            msg = json.loads(raw)
            msg_type = msg.get("type")

            if msg_type == "match":
                check_trade_gap(msg["product_id"], int(msg["trade_id"]))
                future = publisher.publish(topic_path, build_envelope(msg),
                                           product_id=msg["product_id"])
                with stats.lock:
                    stats.received += 1
                    stats.pending.add(future)
                future.add_done_callback(on_publish_done)
            elif msg_type == "error":
                raise RuntimeError(f"Coinbase error: {msg}")
            # 'subscriptions', 'heartbeat' and 'last_match' are not published

            if time.monotonic() >= next_stats:
                log_event(logging.INFO, "stats", **stats.snapshot())
                next_stats = time.monotonic() + STATS_EVERY_SECONDS


# ---------- Main loop: reconnect until told to stop ----------
async def run() -> None:
    stop_event = asyncio.Event()
    loop = asyncio.get_running_loop()

    # Cloud Run sends SIGTERM before stopping a container. (Not supported on
    # Windows; there Ctrl+C cancels the program and the 'finally' below still runs.)
    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            loop.add_signal_handler(sig, stop_event.set)
        except NotImplementedError:
            pass

    if RUN_SECONDS:
        loop.call_later(RUN_SECONDS, stop_event.set)

    publisher = pubsub_v1.PublisherClient(batch_settings=BATCH_SETTINGS)
    topic_path = publisher.topic_path(PROJECT_ID, TOPIC_ID)

    try:
        while not stop_event.is_set():
            try:
                await stream_once(publisher, topic_path, stop_event)
            except (ConnectionClosed, asyncio.TimeoutError, OSError, RuntimeError) as exc:
                if stop_event.is_set():
                    break
                with stats.lock:
                    stats.reconnects += 1
                wait = backoff["seconds"] + random.uniform(0, 1)   # jitter
                log_event(logging.WARNING, "connection lost, reconnecting",
                          error=repr(exc), wait_seconds=round(wait, 1))
                try:
                    await asyncio.wait_for(stop_event.wait(), timeout=wait)
                except asyncio.TimeoutError:
                    pass
                backoff["seconds"] = min(backoff["seconds"] * 2, MAX_BACKOFF_SECONDS)
    finally:
        shutdown(publisher)


def shutdown(publisher) -> None:
    """Flush the last batch and wait for Pub/Sub to confirm everything."""
    publisher.stop()
    with stats.lock:
        still_pending = list(stats.pending)
    futures.wait(still_pending, timeout=SHUTDOWN_WAIT_SECONDS)
    log_event(logging.INFO, "shutdown complete", **stats.snapshot())


if __name__ == "__main__":
    asyncio.run(run())