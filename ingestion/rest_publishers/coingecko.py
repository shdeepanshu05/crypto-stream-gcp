"""CoinGecko /coins/markets snapshot -> one Pub/Sub message per coin."""
from google.cloud import secretmanager

from common import build_envelope, get_with_backoff, log_event, publish

COINGECKO_URL = "https://api.coingecko.com/api/v3/coins/markets"
COINGECKO_PARAMS = {"vs_currency": "usd", "ids": "bitcoin,ethereum"}
SECRET_ID = "coingecko-api-key"


def read_secret(project_id: str, secret_id: str) -> str:
    """Read the latest secret version AS the current identity (sa-ingest-run)."""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/latest"
    return client.access_secret_version(name=name).payload.data.decode("utf-8").strip()


def run(project_id: str, topic_id: str) -> None:
    api_key = read_secret(project_id, SECRET_ID)
    coins = get_with_backoff(COINGECKO_URL, COINGECKO_PARAMS, headers={"x-cg-demo-api-key": api_key})

    if not isinstance(coins, list) or not coins:
        raise RuntimeError(f"Unexpected CoinGecko response type: {type(coins).__name__}")

    envelopes = [build_envelope("coingecko", coin) for coin in coins]
    message_ids = publish(project_id, topic_id, envelopes)
    log_event(
        "published",
        source="coingecko",
        topic=topic_id,
        messages=len(message_ids),
        coins=[c.get("id") for c in coins],
        last_updated=[c.get("last_updated") for c in coins],
    )