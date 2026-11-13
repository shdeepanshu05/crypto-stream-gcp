# 03 — Identity and access

Rule: every workload runs as its own service account. No JSON keys exist.
My personal account is used only for the initial setup (Phase 3).

| Service account | Job | Doors it opens (roles, where) | In my words |
|---|---|---|---|
| sa-tf-provisioner | Runs Terraform | Creates and manages infrastructure and IAM | The builder. It constructs the building: rooms (topics, tables, buckets) and keycards for everyone else. Most powerful card, so only I and the CI deployer may use it. |
| sa-cicd-deployer | GitHub Actions deploys code | Deploys Cloud Run, Workflows, launches Dataflow; acts as runtime SAs | The installer. It puts new machines (code) into rooms and assigns which keycard each machine uses, but it cannot open the data rooms itself. |
| sa-ingest-run | Reads APIs, publishes messages | Pub/Sub publisher (3 topics); reads CoinGecko secret | The postman. It collects data from Coinbase, CoinGecko and Frankfurter and drops it into the Pub/Sub mailboxes. It cannot open BigQuery at all. |
| sa-pubsub-bq-writer | Pub/Sub writes raw data to Bronze | BigQuery data editor (Bronze tables only) | The filing clerk. It takes letters from the mailbox and files them, unopened, into the Bronze cabinet, and no other cabinet. |
| sa-dataflow-worker | Stream processing | Dataflow worker; Pub/Sub subscriber (its subscriptions); BigQuery editor (Silver + anomaly table); temp bucket | The live inspector. It reads messages as they arrive, removes duplicates, builds candles, raises alarms, and writes results into Silver and the alert table. |
| sa-orchestrator | Runs SQL Silver → Gold | BigQuery job user; read Bronze; edit Silver + Gold | The accountant. On a schedule it reads the cabinets, cleans and summarises the data, and writes the final reports into Gold. |
| sa-scheduler | Starts jobs on a timer | Can only trigger Workflows and the poller jobs | The alarm clock. It only rings to start other workers at the right time; it cannot open any data room itself. |

## Two important differences

- **Deployer vs runtime:** the identity that *deploys* a service is different from the identity the service *runs as*.
- **actAs vs impersonation:** actAs (Service Account User) = attach a service account to a resource. Impersonation (Token Creator) = become that service account and call APIs as it.   