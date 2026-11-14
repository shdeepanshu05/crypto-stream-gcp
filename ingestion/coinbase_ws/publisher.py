import asyncio
import json
import logging
import os
import threading
import time
from datetime import datetime , timezone

from google.cloud import pubsub_v1
from websockets.asyncio.client import connect
from concurrent import futures

##---- Environment Variables ------ ##
PROJECT_ID = os.environ["GCP_PROJECT_ID"]
TOPIC_ID = os.environ.get("TRADES_TOPIC", "coinbase-trades")
PRODUCTS = os.environ.get("PRODUCTS", "BTC-USD,ETH-USD").split(",")
RUN_SECONDS = int(os.environ.get("RUN_SECONDS", "60"))

WS_URL = "wss://ws-feed.exchange.coinbase.com"
SCHEMA_VERSION = "v1"

# Wait up to 1 s or 500 messages per request, so each request carries many
# messages and the 1 KB per-request minimum is not wasted (ADR-0004).
BATCH_SETTINGS = pubsub_v1.types.BatchSettings(
    max_messages=500,
    max_bytes=1_000_000,
    max_latency=1.0,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("coinbase-publisher")

# Publish results arrive on background threads, so protect the counters with a lock.

stats = {"published": 0, "failed": 0}
pending = set()
stats_lock = threading.Lock()


def on_publish_done(future) -> None:
    """Called by the Pub/Sub client when a message is confirmed or fails."""
    try:
        future.result()  # raises if the publish failed
        with stats_lock:
            stats["published"] += 1
    except Exception as exc:
        with stats_lock:
            stats["failed"] += 1
        log.error("Publish failed: %s", exc)
    finally:
        with stats_lock:
            pending.discard(future)


def build_envelope(msg: dict) -> bytes:
    """Wrap the original Coinbase message in our contract envelope."""
    envelope = {
        "schema_version": SCHEMA_VERSION,
        "source": "coinbase",
        "ingest_ts": datetime.now(timezone.utc).isoformat(),
        "payload": msg,
    }
    return json.dumps(envelope, separators=(",", ":")).encode("utf-8")

async def main() -> None:
    publisher = pubsub_v1.PublisherClient(batch_settings=BATCH_SETTINGS)
    topic_path = publisher.topic_path(PROJECT_ID, TOPIC_ID)
    received = 0
    start = time.monotonic()

    async with connect(WS_URL) as ws:
        await ws.send(json.dumps({
            "type": "subscribe",
            "product_ids": PRODUCTS,
            "channels": ["matches"],
        }))
        log.info("Subscribed to matches for %s; publishing to %s", PRODUCTS, topic_path)

        async for raw in ws:
            msg = json.loads(raw)

            if msg.get("type") != "match":
                log.info("Skipping message of type %s", msg.get("type"))
                continue

            future = publisher.publish(
                topic_path,
                build_envelope(msg),
                product_id=msg["product_id"],  # attribute: useful for filtering later
            )
            with stats_lock:
                pending.add(future)
            future.add_done_callback(on_publish_done)
            received += 1
            

            if RUN_SECONDS and time.monotonic() - start >= RUN_SECONDS:
                break

    publisher.stop()  # sends any messages still waiting in a batch

    # wait (upto 30 s) until Pub/Sub has confirmed every message we sent
    with stats_lock:
        still_pending = list(pending)
    futures.wait(still_pending, timeout = 30)
    
    log.info("Done: received=%d published=%d failed=%d",
             received, stats["published"], stats["failed"])


if __name__ == "__main__":
    asyncio.run(main())