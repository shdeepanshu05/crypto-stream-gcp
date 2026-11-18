# ADR-0013: Keyless CI/CD with GitHub Actions and Workload Identity Federation

**Status:** Accepted · **Date:** 2026-11-18 · **Phase:** 15 (CI/CD)
**Relates to:** Section 10B (service accounts only, no keys), ADR-0003 (local impersonation), ADR-0009 (Workflows), ADR-0011 (monitoring)

## Context
Until Phase 15 every change was shipped by hand from the owner's laptop: `docker build`,
`docker push`, `gcloud run jobs update`, impersonating `sa-cicd-deployer`. That works, but:
- nothing checks a change before it reaches `main` (a missing `"` in `monitoring.tf` was
  found only at `terraform plan` time);
- the deploy depends on one laptop and on the owner's personal account being allowed to
  become the deployer.

Section 10B requires: *"Use Workload Identity Federation wherever possible… Do not store
long-lived service account JSON keys in GitHub Secrets."* The repository is **public**.

## Decision

### 1. Two workflows, two trust levels
| Workflow | Trigger | GCP access | Does |
|---|---|---|---|
| `ci.yml` | every pull request and push to `main` | **none** (`contents: read` only) | `terraform fmt -check`, `terraform init -backend=false` + `validate`, `ruff` (syntax errors and undefined names) |
| `deploy-dq-runner.yml` | push to `main` touching `docker/dq-runner/**`, `tools/run_dq.py`, `sql/dq/**`, or manual dispatch | `sa-cicd-deployer` via WIF | build the image, push it to Artifact Registry tagged with the 7-character commit SHA, `gcloud run jobs update dq-runner` |

CI needs no cloud credentials at all, so pull requests (including from forks) can never reach GCP.

### 2. WIF *through a service account*, not direct WIF
Google's auth action prefers *direct* WIF (IAM roles granted to the federated principal).
We use **WIF through `sa-cicd-deployer`** instead, because Section 10B requires every
application-to-GCP interaction to authenticate as a dedicated service account. Benefits:
the deploy shows up in audit logs as a named SA; its permissions are the same narrow set
reviewed in Phase 11 (`artifactregistry.writer` on the `crypto-stream` repo only,
`run.developer`, `actAs` on the job's runtime SA); no data access.

### 3. Three locks on the trust
1. **Provider issuer:** only tokens signed by `https://token.actions.githubusercontent.com`.
2. **Provider attribute condition:**
   `assertion.repository == 'shdeepanshu05/crypto-stream-gcp' && assertion.ref == 'refs/heads/main'`.
   Every other repository on GitHub, every other branch, and every pull request is rejected
   at the token exchange. (Google requires GitHub providers to have a condition. We use the
   exact repository, stricter than the common `repository_owner` check.)
3. **IAM binding:** `roles/iam.workloadIdentityUser` on `sa-cicd-deployer` **only**, for
   `principalSet://…/attribute.repository/shdeepanshu05/crypto-stream-gcp`. An accepted
   token still cannot become any other service account.

### 4. Manual deploy access removed
After the first CI deploy was proven in production, the binding
`admin_impersonates_deployer` (owner → `serviceAccountTokenCreator` on the deployer) was
destroyed. Verified: `gcloud auth print-access-token --impersonate-service-account=sa-cicd-deployer@…`
now returns `PERMISSION_DENIED`. **Only GitHub Actions, from `main`, can deploy.**

### 5. `terraform apply` stays manual
Infrastructure changes are still planned and applied from the laptop as `sa-tf-provisioner`
(impersonation, ADR-0003). Applying from CI would need near-admin rights for the CI identity,
an approval gate and state protections. And on a **public** repository the plan output would
be world-readable: the provider builds resource IDs that contain values Terraform otherwise
masks (e.g. the owner's email in an IAM member ID), so `sensitive = true` does not fully protect a plan log.

## Evidence (2026-11-18)
- `ci` runs #1 and #2: green (~21 s).
- `deploy-dq-runner` run #1 (manual dispatch on `main`): green in 39 s; "who am I" step printed
  `sa-cicd-deployer@crypto-de-dev-4821.iam.gserviceaccount.com`.
- Cloud Run job image changed `dq-runner:b93d62f` (built by hand) → `dq-runner:e0ce584` (built by CI).
- Next scheduled pipeline run used the CI image: `dq-runner-xpkpp` COMPLETE 1/1 (all 8 DQ checks
  passed), run by `sa-orchestrator`; workflow execution SUCCEEDED 18:05:01 → 18:07:04 UTC.
- No JSON key exists for any service account; none is stored in GitHub Secrets.

## Alternatives considered
- **Service account key in GitHub Secrets:** forbidden by 10B; long-lived, works from anywhere,
  rotation is manual, and exposure through logs or a compromised token is permanent until rotated.
- **Direct WIF:** Google's preferred mode and one less moving part, but grants roles to a federated
  principal instead of a named SA (see decision 2).
- **Cloud Build triggers:** runs inside GCP with no federation needed. Rejected: CI logic would live
  outside the repository's normal GitHub flow, and the project already standardised on GitHub.
- **`terraform plan` on pull requests** (a read-only `sa-ci-plan`): useful in teams; rejected here
  because of public logs (decision 5) and the broad read permissions it needs.

## Consequences
- Positive: every change is checked automatically; deploys are reproducible, tied to a commit SHA,
  and need no human credentials; the owner's account has one fewer standing privilege.
- Negative: a deploy now requires a push or merge to `main`; there is no local fallback without
  temporarily re-adding the impersonation binding (a deliberate, reviewable Terraform change).
- GitHub OIDC tokens are short-lived (minutes) and the impersonated access token about 1 hour;
  nothing long-lived exists to leak.

## Follow-ups
- Branch protection on `main`: require the `ci` checks before merging.
- Repository setting: require approval for workflow runs from outside contributors.
- Extend CD to the ingestion job (same pattern: path filter + `gcloud run jobs update`).
- Pin third-party actions to commit SHAs instead of major tags (supply-chain hardening).
