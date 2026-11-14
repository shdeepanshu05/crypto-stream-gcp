# ADR-0006: Run the Coinbase publisher on a Cloud Run worker pool
Status: Accepted
Context: The publisher holds one WebSocket open indefinitely and serves no HTTP traffic.
Decision: Deploy it as a Cloud Run worker pool with manual scaling: 1 instance during
study sessions, 0 otherwise. Runtime identity: sa-ingest-run.
Alternatives considered: Cloud Run service (built for HTTP; would need a fake server),
Cloud Run job (for finite tasks), e2-micro VM (free but requires OS/Docker operations).
Consequences: No servers to manage. ~$2.75/month in sessions (upper bound at
instance-based service rates); ~$49/month if left at 1 instance, so scaling to 0
after each session is mandatory.