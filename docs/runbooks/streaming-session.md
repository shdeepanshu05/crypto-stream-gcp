# Runbook: streaming session (publisher + Dataflow Silver)

All commands run as service accounts via impersonation. Never leave anything running.
SA shorthand: DEPLOYER = sa-cicd-deployer@crypto-de-dev-4821.iam.gserviceaccount.com

## 0. Start-of-session mark (UTC, keep it for validation queries)
```powershell
(Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
```

## 1. Launch Dataflow (ADC = deployer, run from dataflow/)
```powershell
gcloud auth application-default login --impersonate-service-account sa-cicd-deployer@crypto-de-dev-4821.iam.gserviceaccount.com
cd dataflow
python pipeline_streaming.py --runner=DataflowRunner --project=crypto-de-dev-4821 --region=us-central1 --job_name=silver-trades-stream --service_account_email=sa-dataflow-worker@crypto-de-dev-4821.iam.gserviceaccount.com --temp_location=gs://crypto-de-dev-4821-dataflow/temp --staging_location=gs://crypto-de-dev-4821-dataflow/staging --setup_file=./setup.py --enable_streaming_engine --machine_type=n1-standard-2 --num_workers=1 --autoscaling_algorithm=NONE --disk_size_gb=30 --subscription=projects/crypto-de-dev-4821/subscriptions/coinbase-trades-to-dataflow --trades_table=crypto-de-dev-4821:silver.trades --quarantine_table=crypto-de-dev-4821:silver.trades_quarantine
cd ..
```
Wait until `jobs list` shows Running:
```powershell
gcloud dataflow jobs list --region=us-central1 --status=active --impersonate-service-account=sa-cicd-deployer@crypto-de-dev-4821.iam.gserviceaccount.com
```

## 2. Publisher on
```powershell
gcloud run worker-pools update coinbase-publisher --region=us-central1 --instances=1 --impersonate-service-account=sa-cicd-deployer@crypto-de-dev-4821.iam.gserviceaccount.com
```

## 3. Shutdown (in this order)
1. Publisher off:
```powershell
gcloud run worker-pools update coinbase-publisher --region=us-central1 --instances=0 --impersonate-service-account=sa-cicd-deployer@crypto-de-dev-4821.iam.gserviceaccount.com
```
2. **Wait until the backlog is 0.** Console → Pub/Sub → Subscriptions →
   `coinbase-trades-to-dataflow` → Unacked message count = 0.
   Do NOT drain after a fixed wait: draining stops reading, and anything still
   unacked is left behind (Phase 7: 863 trades missed this way).
3. Drain:
```powershell
gcloud dataflow jobs drain JOB_ID --region=us-central1 --impersonate-service-account=sa-cicd-deployer@crypto-de-dev-4821.iam.gserviceaccount.com
```
4. Confirm: the job is `Drained`, and the worker pool shows `Instances: 0`.
   If still Draining after 15 min, run `gcloud dataflow jobs cancel JOB_ID ...`.
5. Switch ADC back to the provisioner.

## 4. Cost guardrails
Running ~$0.10-0.25 per 30 min session. Forgotten 24/7: ~$100+/month. Set a phone timer.