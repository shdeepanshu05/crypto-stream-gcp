# ADR-0012: Dashboard in Data Studio reads BigQuery with owner's credentials

- **Status:** Accepted
- **Date:** 2026-11-18
- **Phase:** 14 (Serving / Dashboard)
- **Relates to:** Section 10B (service-account-only authentication), ADR-0003 (local impersonation)

## Context

Phase 14 adds a dashboard on top of the Gold layer: pipeline health tiles,
BTC/ETH price, USD→INR rate and the anomalies table. The tool chosen is
Data Studio (formerly Looker Studio): free, native BigQuery connector,
no infrastructure to run.

Section 10B requires every application-to-GCP interaction to authenticate
as a dedicated service account. Data Studio supports three credential modes
for a BigQuery data source:

| Mode | Who BigQuery sees | Usable here? |
|---|---|---|
| Owner's credentials | The report owner (personal Google account) | Yes |
| Viewer's credentials | Each viewer, who needs their own BigQuery access | Yes, but every viewer needs IAM on the project |
| Service account credentials | A GCP service account, via the Data Studio service agent | **No.** It requires the report owner to belong to a Google Workspace or Cloud Identity organisation. The project owner has a personal Gmail account only. |

So the 10B-compliant mode is not available on this account type.

## Decision

The four data sources (`gold.dash_pipeline_status`, `gold.dash_asset_prices`,
`gold.anomalies`, `gold.ohlcv_1m_inr`) use **owner's credentials**.

This is an **approved, documented exception** to Section 10B, limited to the
dashboard's read path. Everything else is unchanged: ingestion, Dataflow,
Workflows, the DQ runner and Terraform still run as their dedicated service
accounts.

### Mitigations

1. **Read-only, narrow surface.** The report reads only Gold views and the
   anomalies table, never Bronze/Silver or anything writable. The views
   limit history (for example 90 days in `dash_asset_prices`) to bound the bytes scanned.
2. **Report stays private.** It is not shared publicly or "anyone with the link".
   With owner's credentials, any viewer would query BigQuery *as the owner*.
3. **No keys anywhere.** No service account key is created or uploaded, so
   nothing long-lived can leak.
4. **Cost control.** Data freshness is set per data source (15 minutes or more)
   so chart refreshes reuse the cache instead of re-querying BigQuery.
5. **Visible in the audit trail.** BigQuery job history attributes dashboard
   queries to the owner, which separates them clearly from pipeline jobs
   (service accounts).

## Alternatives considered

- **Service account credentials:** the preferred option, but blocked by the
  account type (see Context).
- **Viewer's credentials:** works, but every viewer would need
  `bigquery.dataViewer` and `bigquery.jobUser` on the project. Not suitable
  for a portfolio demo, and it widens IAM for people instead of narrowing it.
- **Custom dashboard on Cloud Run** (e.g. Streamlit) running as a dedicated
  service account: fully 10B-compliant, but adds an application to build,
  deploy, secure and pay for. Out of proportion for this phase. It is the
  right move if the dashboard ever becomes public.
- **Looker (paid):** supports service accounts, but the licence cost conflicts
  with the low-budget constraint.

## Consequences

- Positive: a working dashboard at zero extra cost and with no new infrastructure.
- Negative: one deliberate gap in the "service accounts only" rule, which
  depends on the report staying private.
- Dashboard queries appear under the owner's identity, not a workload identity.

## Revisit when

- The project moves to a Google Workspace or Cloud Identity organisation:
  switch all four data sources to service account credentials, using a new
  read-only `sa-dashboard` (with `bigquery.dataViewer` on `gold` and
  `bigquery.jobUser` on the project).
- The dashboard needs to be shared beyond the owner: replace it with a
  Cloud Run app that runs as a service account, or move to the option above first.
