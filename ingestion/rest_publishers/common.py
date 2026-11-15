"""Shared helpers for the REST publishers: HTTP with backoff, envelope, Pub/Sub, logging."""
import json
import logging
import random
import sys
import time
from datetime import datetime , timezone

import requests
from google.cloud import pubsub_v1

TIMEOUT_SECONDS = 10
MAX_RETRIES = 4
SCHEMA_VERSION = "v1"

class JsonFormatter(logging.Formatter):
    "One JSON object per line, so Cloud Logging parses severity and fields."

    def format(self, record):
        entry = {"severity": record.levelname, "message": record.getMessage(), "logger": record.name}
        entry.update(getattr(record, "fields", {}))
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry)

def setup_logging() -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)

def log_event(message: str, **fields) -> None:
    logging.getLogger("rest_publisher").info(message, extra={"fields": fields})

def get_with_backoff(url: str, params: dict, headers: dict | None = None) -> object:
    """GET with retries on 429, 5xx, timeouts and connection errors. Never logs headers (they hold the key)."""
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            response = requests.get(url, params=params, headers=headers, timeout=TIMEOUT_SECONDS)
        except (requests.ConnectionError, requests.Timeout) as exc:
            reason = type(exc).__name__
        else:
            if response.status_code == 429 or response.status_code >= 500:
                reason = f"HTTP {response.status_code}"
            else:
                response.raise_for_status()  # other 4xx (401 bad key, 404) fail immediately
                return response.json()

        if attempt == MAX_RETRIES:
            break
        wait = min(2 ** attempt, 30) + random.uniform(0, 1)  # backoff + jitter, capped
        log_event("retrying", url=url, reason=reason, attempt=attempt, wait_seconds=round(wait, 1))
        time.sleep(wait)

    raise RuntimeError(f"Giving up on {url} after {MAX_RETRIES} attempts")


def build_envelope(source: str, payload: object) -> dict:
    return {
        "schema_version": SCHEMA_VERSION,
        "source": source,
        "ingest_ts": datetime.now(timezone.utc).isoformat(),
        "payload": payload,
    }


def publish(project_id: str, topic_id: str, envelopes: list) -> list:
    """Publish all envelopes and WAIT for every confirmation. Returns the message IDs."""
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, topic_id)
    futures = [
        publisher.publish(topic_path, json.dumps(e, separators=(",", ":")).encode("utf-8"))
        for e in envelopes
    ]
    return [f.result(timeout=60) for f in futures]