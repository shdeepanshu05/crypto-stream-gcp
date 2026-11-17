"""Run every sql/dq/*.sql check, store results in ops.dq_results, exit 1 if an 'error' check fails.

Contract: each check returns exactly ONE row with
check_name, layer, severity ('error'|'warn'), failed_count (0 = pass), details.
Identity: must be sa-orchestrator (impersonation locally, attached identity in Cloud Run; no key file).
Logging: one JSON line per event on stdout; Cloud Run maps "severity" to the log entry's severity,
so FAIL lines are ERROR and can trigger alerts.
Exit codes: 0 = all blocking checks pass, 1 = a blocking check failed, 2 = wrong identity.
"""
import argparse
import json
import pathlib
import sys
import uuid
from datetime import datetime, timezone

import google.auth
import google.auth.transport.requests
from google.cloud import bigquery

PROJECT = "crypto-de-dev-4821"
LOCATION = "us-central1"
RESULTS_TABLE = f"{PROJECT}.ops.dq_results"
EXPECTED_SA = "sa-orchestrator@crypto-de-dev-4821.iam.gserviceaccount.com"
REQUIRED = {"check_name", "layer", "severity", "failed_count", "details"}


def log(severity: str, message: str, **fields) -> None:
    """Write one structured log line. 'severity' and 'message' are special fields for Cloud Logging."""
    print(json.dumps({"severity": severity, "message": message, **fields}, default=str), flush=True)


def run_check(client: bigquery.Client, path: pathlib.Path) -> dict:
    """Run one check file and return a result dict. Never raises: a broken check is a failed check."""
    sql = path.read_text(encoding="utf-8")
    if not sql.strip():
        return {"check_name": path.stem, "layer": None, "severity": "error",
                "failed_count": None, "details": "check file is empty"}
    try:
        rows = list(client.query(sql).result())
    except Exception as exc:  # a check that cannot run must not pass silently
        return {"check_name": path.stem, "layer": None, "severity": "error",
                "failed_count": None, "details": f"query failed: {str(exc)[:1000]}"}
    if len(rows) != 1:
        return {"check_name": path.stem, "layer": None, "severity": "error",
                "failed_count": None, "details": f"contract violation: returned {len(rows)} rows, expected 1"}
    row = dict(rows[0].items())
    missing = REQUIRED - row.keys()
    if missing:
        return {"check_name": path.stem, "layer": None, "severity": "error",
                "failed_count": None, "details": f"contract violation: missing columns {sorted(missing)}"}
    return {k: row[k] for k in REQUIRED}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checks-dir", default="sql/dq")
    parser.add_argument("--no-store", action="store_true", help="print results only, do not write to BigQuery")
    args = parser.parse_args()

    creds, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    creds.refresh(google.auth.transport.requests.Request())  # Cloud Run creds report "default" until refreshed
    identity = getattr(creds, "service_account_email", None)
    log("INFO", "dq run starting", identity=identity)
    if identity != EXPECTED_SA:
        log("ERROR", f"refusing to run: expected {EXPECTED_SA}", identity=identity,
            fix=f"gcloud auth application-default login --impersonate-service-account={EXPECTED_SA}")
        return 2

    client = bigquery.Client(project=PROJECT, credentials=creds, location=LOCATION)

    files = sorted(pathlib.Path(args.checks_dir).glob("*.sql"))
    if not files:
        log("ERROR", f"no checks found in {args.checks_dir}")
        return 1

    run_id = str(uuid.uuid4())
    run_ts = datetime.now(timezone.utc).isoformat()
    results = []
    for path in files:
        r = run_check(client, path)
        passed = r["failed_count"] == 0
        status = "PASS" if passed else ("WARN" if r["severity"] == "warn" else "FAIL")
        severity = "INFO" if passed else ("WARNING" if r["severity"] == "warn" else "ERROR")
        log(severity, f"{status} {r['check_name']}", check_name=r["check_name"], layer=r["layer"],
            failed_count=r["failed_count"], details=r["details"], run_id=run_id)
        results.append({**r, "run_id": run_id, "run_ts": run_ts, "passed": passed})

    if not args.no_store:
        schema = client.get_table(RESULTS_TABLE).schema
        job = client.load_table_from_json(
            results, RESULTS_TABLE,
            job_config=bigquery.LoadJobConfig(
                schema=schema,
                write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
                create_disposition=bigquery.CreateDisposition.CREATE_NEVER,
            ),
        )
        job.result()
        log("INFO", f"stored {len(results)} results", table=RESULTS_TABLE, run_id=run_id)

    errors = [r for r in results if not r["passed"] and r["severity"] == "error"]
    log("ERROR" if errors else "INFO",
        f"summary: {len(results)} checks, {len(errors)} blocking failures",
        run_id=run_id, checks=len(results), blocking_failures=len(errors))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())