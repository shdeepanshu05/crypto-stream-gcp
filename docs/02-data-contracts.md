# 02 — Data contracts

Version: v1 · Last updated: 2026-11-13

Every message published to Pub/Sub has two parts:
- **Envelope**: fields WE add (same for every source)
- **Payload**: fields from the API

## Common envelope (all messages)

| Field | Type | Meaning |
|---|---|---|
| `schema_version` | STRING | Contract version, e.g. `"v1"`. Lets readers handle future changes safely |
| `source` | STRING | `coinbase`, `coingecko` or `frankfurter` |
| `ingest_ts` | TIMESTAMP | When OUR program received the message (UTC) |
| `payload` | JSON | The original API message, unchanged |

## 1. trade_event (Coinbase `matches` channel)

One message = one completed trade.

| Field | Type | Source field | Notes |
|---|---|---|---|
| `product_id` | STRING | `product_id` | Trading pair, e.g. `BTC-USD` |
| `trade_id` | INT64 | `trade_id` | Unique per product |
| `sequence` | INT64 | `sequence` | Message counter; a jump means messages were missed |
| `trade_ts` | TIMESTAMP | `time` | **Event time**: when the trade happened (UTC) |
| `price` | NUMERIC | `price` | Arrives as text, converted to exact decimal |
| `size` | NUMERIC | `size` | Quantity traded |
| `side` | STRING | `side` | Side of the **maker** order: `buy` or `sell` |

**Natural key:** `product_id` + `trade_id` (used to remove duplicates).

## 2. quote_event (Coinbase `ticker` channel)

One message = latest price plus the best buy and sell offers.

| Field | Type | Source field | Notes |
|---|---|---|---|
| `product_id` | STRING | `product_id` | |
| `sequence` | INT64 | `sequence` | |
| `quote_ts` | TIMESTAMP | `time` | Event time |
| `last_price` | NUMERIC | `price` | Price of the latest trade |
| `last_size` | NUMERIC | `last_size` | Size of the latest trade |
| `best_bid` | NUMERIC | `best_bid` | Highest price a buyer offers |
| `best_bid_size` | NUMERIC | `best_bid_size` | |
| `best_ask` | NUMERIC | `best_ask` | Lowest price a seller asks |
| `best_ask_size` | NUMERIC | `best_ask_size` | |

**Natural key:** `product_id` + `sequence`.

## 3. asset_snapshot (CoinGecko `/coins/markets`) *(confirm in Phase 2)*

One message = one coin's data at one poll.

| Field | Type | Notes |
|---|---|---|
| `coin_id` | STRING | e.g. `bitcoin` |
| `symbol` | STRING | e.g. `btc` |
| `name` | STRING | |
| `price_usd` | NUMERIC | Used for the cross-source check |
| `market_cap_usd` | NUMERIC | |
| `market_cap_rank` | INT64 | Changes over time, tracked by SCD2 in `dim_asset` |
| `total_volume_usd` | NUMERIC | |
| `source_updated_ts` | TIMESTAMP | When CoinGecko last updated this coin |

**Natural key:** `coin_id` + `source_updated_ts`.

## 4. fx_rate (Frankfurter `/v2/rates`) *(confirm in Phase 2)*

| Field | Type | Notes |
|---|---|---|
| `rate_date` | DATE | The day the rate applies to |
| `base_currency` | STRING | `USD` |
| `quote_currency` | STRING | `INR` |
| `rate` | NUMERIC | 1 USD = `rate` INR |

**Natural key:** `rate_date` + `base_currency` + `quote_currency`.

## Rules for changing a contract

- Adding a new optional field → allowed, keep the same major version.
- Renaming, removing or changing the type of a field → **breaking change**: new version (`v2`) and all readers updated first.