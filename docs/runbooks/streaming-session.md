# Runbook: streaming session (publisher + Dataflow Silver)

All commands run as service accounts via impersonation. Never leave anything running.
SA shorthand: DEPLOYER = sa-cicd-deployer@crypto-de-dev-4821.iam.gserviceaccount.com

## 0. Start-of-session mark (UTC, keep it for validation queries)
```powershell
(Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
```

## 1. Launch Dataflow (ADC = deployer, run from dataflow/)
Use a NEW job name each session (silver-trades-stream-3, -4, ...) so each session is easy to find in the job history.
```powershell
gcloud auth application-default login --impersonate-service-account sa-cicd-deployer@crypto-de-dev-4821.iam.gserviceaccount.com
cd dataflow
python pipeline_streaming.py --runner=DataflowRunner --project=crypto-de-dev-4821 --region=us-central1 --job_name=silver-trades-stream-N --service_account_email=sa-dataflow-worker@crypto-de-dev-4821.iam.gserviceaccount.com --temp_location=gs://crypto-de-dev-4821-dataflow/temp --staging_location=gs://crypto-de-dev-4821-dataflow/staging --setup_file=./setup.py --enable_streaming_engine --machine_type=n1-standard-2 --num_workers=1 --autoscaling_algorithm=NONE --disk_size_gb=30 --subscription=projects/crypto-de-dev-4821/subscriptions/coinbase-trades-to-dataflow --trades_table=crypto-de-dev-4821:silver.trades --quarantine_table=crypto-de-dev-4821:silver.trades_quarantine
cd ..
```
Wait until `jobs list` shows Running:
```powershell
gcloud dataflow jobs list --region=us-central1 --status=active --impersonate-service-account=sa-cicd-deployer@crypto-de-dev-4821.iam.gserviceaccount.com
```

## 2. Publisher on (1-2 minutes AFTER the job shows Running)
Running means the job exists, not that the workers are ready. Starting the publisher too
early causes a start-up backlog (session 2: ~1,000-message spike, ~1.2 min oldest age).
```powershell
gcloud run worker-pools update coinbase-publisher --region=us-central1 --instances=1 --impersonate-service-account=sa-cicd-deployer@crypto-de-dev-4821.iam.gserviceaccount.com
```

## 3. Shutdown (in this order)
1. Publisher off:
```powershell
gcloud run worker-pools update coinbase-publisher --region=us-central1 --instances=0 --impersonate-service-account=sa-cicd-deployer@crypto-de-dev-4821.iam.gserviceaccount.com
```
2. **Wait until the backlog is 0.** Console → Pub/Sub → Subscriptions →
   `coinbase-trades-to-dataflow` → Metrics:
   - **"Oldest unacked message age" = 0** (the strongest signal: nothing is waiting)
   - "Unacked messages" = 0 (confirms it)
   The charts lag 1-3 minutes, so give them time after stopping the publisher.
   Do NOT drain after a fixed wait: draining stops reading, and anything still
   unacked is left behind (Phase 7: 863 trades missed this way).
   Session 2 followed this rule: bronze = silver = 37,547, zero loss.
3. Drain:
```powershell
gcloud dataflow jobs drain JOB_ID --region=us-central1 --impersonate-service-account=sa-cicd-deployer@crypto-de-dev-4821.iam.gserviceaccount.com
```
4. Confirm: the job is `Drained`, and the worker pool shows `Instances: 0`.
   If still Draining after 15 min, run `gcloud dataflow jobs cancel JOB_ID ...`.

## 4. After the session (ADC = orchestrator)
```powershell
gcloud auth application-default login --impersonate-service-account sa-orchestrator@crypto-de-dev-4821.iam.gserviceaccount.com
python tools\run_sql.py sql\silver\merge_asset_snapshots.sql
python tools\run_sql.py sql\gold\merge_ohlcv_1m.sql
```
The first line of each must say `running as: sa-orchestrator@...`.

Validate (BigQuery console): Silver count = Bronze unique trades for the session window.
```sql
-- Silver
SELECT COUNT(*) FROM `crypto-de-dev-4821.silver.trades`
WHERE trade_ts BETWEEN TIMESTAMP('START') AND TIMESTAMP('END');

-- Bronze (deduplicated by the same key as Dataflow)
SELECT COUNT(DISTINCT CONCAT(JSON_VALUE(data,'$.payload.product_id'), ':', JSON_VALUE(data,'$.payload.trade_id')))
FROM `crypto-de-dev-4821.bronze.coinbase_trades`
WHERE publish_time BETWEEN TIMESTAMP_SUB(TIMESTAMP('START'), INTERVAL 5 MINUTE) AND TIMESTAMP_ADD(TIMESTAMP('END'), INTERVAL 15 MINUTE)
  AND SAFE.TIMESTAMP(JSON_VALUE(data,'$.payload.time')) BETWEEN TIMESTAMP('START') AND TIMESTAMP('END');
```
Leave ADC on the orchestrator (least privilege). Switch to the provisioner only right before Terraform.

## 5. Cost guardrails
Running ~$0.10-0.25 per 30 min session. Forgotten 24/7: ~$100+/month. Set a phone timer.