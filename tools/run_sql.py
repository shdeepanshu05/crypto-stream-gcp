"""Run a SQL file in BigQuery as the current ADC identity (e.g. impersonated sa-orchestrator)."""
import argparse
import pathlib
import google.auth
from google.cloud import bigquery


def main() -> None:
    credentials, _ = google.auth.default()
    identity = getattr(credentials, "service_account_email", "unknown (not a service account)")
    print(f"running as: {identity}")
    parser = argparse.ArgumentParser()
    parser.add_argument("sql_file")
    parser.add_argument("--project", default="crypto-de-dev-4821")
    parser.add_argument("--location", default="us-central1")
    args = parser.parse_args()

    client = bigquery.Client(project=args.project, location=args.location)
    job = client.query(pathlib.Path(args.sql_file).read_text(encoding="utf-8"))
    job.result()  # wait for completion; raises on SQL errors

    print(f"job_id: {job.job_id}")
    print(f"statement_type: {job.statement_type}")
    print(f"rows_affected: {job.num_dml_affected_rows}")
    print(f"bytes_processed: {job.total_bytes_processed}")


if __name__ == "__main__":
    main()