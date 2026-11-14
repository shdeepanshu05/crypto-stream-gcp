import json
import pathlib
import time

import requests

COINGECKO_URL = "https://api.coingecko.com/api/v3/coins/markets"
COINGECKO_PARAMS = {"vs_currency": "usd", "ids":"bitcoin,ethereum"}

FRANKFURTER_URL = "https://api.frankfurter.dev/v2/providers/ecb/rates"
FRANKFURTER_PARAMS = {"base": "USD", "quotes": "INR"}

TIMEOUT_SECONDS = 10
MAX_RETRIES = 3

def get_with_backoff(url: str, params: dict) -> object:
    for attempt in range(1 , MAX_RETRIES+1):
        response = requests.get(url, params=params, timeout = TIMEOUT_SECONDS)

        if response.status_code == 429 or response.status_code >= 500:
            wait_seconds = 2 ** attempt
            print(f"HTTP {response.status_code}; retry {attempt}/{MAX_RETRIES} in {wait_seconds}s")
            time.sleep(wait_seconds)
            continue

        response.raise_for_status()     # any other error (e.g 404) stops here
        return response.json()

    raise RuntimeError(f"Giving up on {url} after {MAX_RETRIES} retries")

def save(data: object, path: str) -> None:
    file = pathlib.Path(path)
    file.parent.mkdir(parents=True, exist_ok = True)
    file.write_text(json.dumps(data, indent=2), encoding= "utf-8")
    print(f"saved raw response to {file}")

def main() -> None:
    print("CoinGecko /coins/markets...")
    coins = get_with_backoff(COINGECKO_URL, COINGECKO_PARAMS)
    save(coins, "samples/coingecko/markets_sample.json")
    for coin in coins:
        print(f"  {coin.get('id')}: price={coin.get('current_price')} "
              f"rank={coin.get('market_cap_rank')} updated={coin.get('last_updated')}")

    print("\nFrankfurter /v2/rates ...")          # ✅ runs once, after the loop
    fx = get_with_backoff(FRANKFURTER_URL, FRANKFURTER_PARAMS)
    save(fx, "samples/frankfurter/rates_sample.json")
    print(f"  raw response: {fx}")

if __name__ == "__main__":
    main()