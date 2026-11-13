import asyncio
import json
import pathlib
from datetime import datetime, timezone

from websockets.asyncio.client import connect

WS_URL = "wss://ws-feed.exchange.coinbase.com"
PRODUCTS = ["BTC-USD"]
MAX_MESSAGES = 20
SAMPLE_FILE = pathlib.Path("samples/coinbase/matches_sample.jsonl")

SUBSCRIBE_MSG = {
    "type" : "subscribe",
    "product_ids" : PRODUCTS,
    "channels" : ["matches"]
}

async def main() -> None:
    SAMPLE_FILE.parent.mkdir(parents=True, exist_ok = True)

    async with connect(WS_URL) as ws:
        await ws.send(json.dumps(SUBSCRIBE_MSG))
        print(f"Subscribed to 'matches' for {PRODUCTS}\n")

        count = 0
        with SAMPLE_FILE.open("w", encoding= "utf-8") as f:
            async for raw in ws:
                received_at = datetime.now(timezone.utc).isoformat()
                f.write(raw + "\n")
                msg = json.loads(raw)

                if msg.get("type") in ("match", "last_match"):
                    print(
                        f"{msg['product_id']} | trade{msg['trade_id']} | "
                        f"{msg['side']:4} | price {msg['price']} | size {msg['size']} | "
                        f"trade time {msg ['time']} | received {received_at}"
                    )
                else:
                    print(f"[{msg.get('type')}] {msg}")

                count += 1
                if count >= MAX_MESSAGES:
                    break
    
    print(f"\nSaved {count} raw messages to {SAMPLE_FILE}")

if __name__ == "__main__":
    asyncio.run(main())