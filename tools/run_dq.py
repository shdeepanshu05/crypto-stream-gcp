"""Run every sql/dq/*.sql check, store results in ops.dq_results, exit 1 if an 'error' check fails.

Contract: each check returns exactly ONE row with
check_name, layer, severity ('error'|'warn'), failed_count (0 = pass), details.
Identity: whatever ADC is (should be sa-orchestrator, via impersonation, no key file).
"""
import argparse
import pathlib
import sys
import uuid
from datetime import datetime, timezone

import google.auth
from google.cloud import bigquery

PROJECT = "crypto-de-dev-4821"
LOCATION = "us-central1"
RESULTS_TABLE = f"{PROJECT}.ops.dq_results"
REQUIRED = {"check_name", "layer", "severity", "failed_count", "details"}


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

    creds, _ = google.auth.default()
    print("running as:", getattr(creds, "service_account_email", "unknown (not a service account!)"))
    client = bigquery.Client(project=PROJECT, credentials=creds, location=LOCATION)

    files = sorted(pathlib.Path(args.checks_dir).glob("*.sql"))
    if not files:
        print(f"no checks found in {args.checks_dir}")
        return 1

    run_id = str(uuid.uuid4())
    run_ts = datetime.now(timezone.utc).isoformat()
    results = []
    for path in files:
        r = run_check(client, path)
        passed = r["failed_count"] == 0
        status = "PASS" if passed else ("WARN" if r["severity"] == "warn" else "FAIL")
        print(f"{status:4}  {r['check_name']:<35} failed={r['failed_count']}  {r['details']}")
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
        print(f"stored {len(results)} results in {RESULTS_TABLE} (run_id={run_id})")

    errors = [r for r in results if not r["passed"] and r["severity"] == "error"]
    print(f"summary: {len(results)} checks, {len(errors)} blocking failures")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())