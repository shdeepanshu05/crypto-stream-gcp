# ADR-0003: Local access by service account impersonation (Option A)
Status: Accepted
Context: No service-account JSON keys may exist. Local testing and Terraform still need to call GCP.
Decision: I sign in to gcloud with my own account only to request short-lived tokens for a service account (impersonation). All API calls run as that service account.
Alternatives considered: Option B (CI-only, no local GCP access). Rejected for now: too slow for learning. JSON keys: rejected for security.
Consequences: I need the Service Account Token Creator role on each service account I impersonate. Audit logs show the service account doing the work.