# ADR-0002: Orchestrate with Workflows + Cloud Scheduler, not Cloud Composer
Status: Accepted
Context: We need to run a few scheduled steps (pollers, SQL transformations). Remaining credit is ₹9,410 until 21 Jan 2027.
Decision: Use Cloud Scheduler to trigger Workflows and Cloud Run jobs.
Alternatives considered: Cloud Composer (managed Airflow). Rejected: roughly $300+/month even when idle, more than our whole remaining credit.
Consequences: Near-zero orchestration cost. If the project grows to dozens of dependent pipelines, revisit Composer.