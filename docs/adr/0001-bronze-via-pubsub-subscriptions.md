# ADR-0001: Write Bronze with Pub/Sub subscriptions, not Dataflow
Status: Accepted
Context: Bronze must store every raw message unchanged. Dataflow workers cost money for every hour they run.
Decision: Use a Pub/Sub BigQuery subscription for Bronze and a Cloud Storage subscription for the raw archive.
Alternatives considered: Dataflow writing Bronze. Rejected: it adds worker cost for a job with no transformation.
Consequences: Bronze costs nothing to run and keeps working even when Dataflow is stopped. Dataflow is used only for Silver and anomalies.