# Runbook: backfill Silver trades from the raw archive

Use when Silver has gaps (e.g. an early drain, a pipeline outage). Idempotent: safe to re-run.

## 1. Load the day's archive into staging (as sa-cicd-deployer -> worker sa-dataflow-worker)
```powershell
gcloud auth application-default login --impersonate-service-account sa-cicd-deployer@crypto-de-dev-4821.iam.gserviceaccount.com
cd dataflow
python pipeline_backfill.py --runner=DataflowRunner --project=crypto-de-dev-4821 --region=us-central1 --job_name=silver-backfill-YYYYMMDD --service_account_email=sa-dataflow-worker@crypto-de-dev-4821.iam.gserviceaccount.com --temp_location=gs://crypto-de-dev-4821-dataflow/temp --staging_location=gs://crypto-de-dev-4821-dataflow/staging --setup_file=./setup.py --machine_type=n1-standard-1 --num_workers=1 --max_num_workers=1 --input=gs://crypto-de-dev-4821-raw-archive/coinbase-trades/YYYY-MM-DD/*.jsonl --staging_table=crypto-de-dev-4821:silver.trades_backfill
cd ..
```
Batch job: stops by itself. ~5 min (mostly worker start-up), a few cents.

## 2. Predict the inserts (BigQuery console)
Anti-join DISTINCT (product_id, trade_id) in trades_backfill vs silver.trades. Write the number down.

## 3. MERGE (as sa-orchestrator)
Update the TIMESTAMP lower bound in sql/silver/merge_trades_backfill.sql if needed, then:
```powershell
gcloud auth application-default login --impersonate-service-account sa-orchestrator@crypto-de-dev-4821.iam.gserviceaccount.com
python tools\run_sql.py sql\silver\merge_trades_backfill.sql
```
rows_affected must equal the prediction. Run again: must be 0.

## 4. Validate
Silver unique trades for the day = staging unique trades.

## First use (Phase 8)
2026-11-15: predicted 26,848, inserted 26,848, re-run 0. Silver = archive = 79,196 trades.