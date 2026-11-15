"""Frankfurter (ECB provider) rates -> one Pub/Sub message per call. See ADR-0005."""
from common import build_envelope, get_with_backoff, log_event, publish

FRANKFURTER_URL = "https://api.frankfurter.dev/v2/providers/ecb/rates"
FRANKFURTER_PARAMS = {"base": "USD", "quotes": "INR"}


def run(project_id: str, topic_id: str) -> None:
    rates = get_with_backoff(FRANKFURTER_URL, FRANKFURTER_PARAMS)
    message_ids = publish(project_id, topic_id, [build_envelope("frankfurter", rates)])
    log_event("published", source="frankfurter", topic=topic_id, messages=len(message_ids))