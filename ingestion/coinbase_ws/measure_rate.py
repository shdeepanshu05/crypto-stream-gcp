"""Phase 2: measure trade rate and message size per product for a fixed time."""

import asyncio
import json
import time
from collections import Counter

from websockets.asyncio.client import connect

WS_URL = "wss://ws-feed.exchange.coinbase.com"
PRODUCTS = ["BTC-USD", "ETH-USD"]
DURATION_SECONDS = 120

SESSION_HOURS = 2          # one study session
SESSIONS_PER_MONTH = 20


async def main() -> None:
    counts = Counter()        # number of trades per product
    total_bytes = Counter()   # total message size per product

    async with connect(WS_URL) as ws:
        await ws.send(json.dumps({
            "type": "subscribe",
            "product_ids": PRODUCTS,
            "channels": ["matches"],
        }))
        print(f"Measuring {PRODUCTS} for {DURATION_SECONDS} s...")

        start = time.monotonic()
        while (elapsed := time.monotonic() - start) < DURATION_SECONDS:
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=DURATION_SECONDS - elapsed)
            except asyncio.TimeoutError:
                break
            msg = json.loads(raw)
            if msg.get("type") == "match":
                counts[msg["product_id"]] += 1
                total_bytes[msg["product_id"]] += len(raw.encode("utf-8"))

    print(f"\n{'product':8} {'trades':>7} {'per sec':>8} {'avg bytes':>10} "
          f"{'GB/session':>11} {'GB/month(sessions)':>19} {'GB/month(24x7)':>15}")
    for product in PRODUCTS:
        n = counts[product]
        if n == 0:
            print(f"{product:8} no trades received")
            continue
        per_sec = n / DURATION_SECONDS
        avg_bytes = total_bytes[product] / n
        bytes_per_sec = per_sec * avg_bytes
        gb_session = bytes_per_sec * SESSION_HOURS * 3600 / 1e9
        gb_month_sessions = gb_session * SESSIONS_PER_MONTH
        gb_month_24x7 = bytes_per_sec * 30 * 24 * 3600 / 1e9
        print(f"{product:8} {n:7} {per_sec:8.2f} {avg_bytes:10.0f} "
              f"{gb_session:11.3f} {gb_month_sessions:19.2f} {gb_month_24x7:15.2f}")


if __name__ == "__main__":
    asyncio.run(main())