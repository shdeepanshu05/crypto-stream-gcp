# Bootstrap (manual, run once by the human admin)

These are the only infrastructure steps done by hand. Everything else is Terraform (Phase 4+).
Run as: my personal account (project Owner). Shell: PowerShell.

## 1. Variables
```powershell
$PROJECT_ID = "crypto-de-dev-4821"
$REGION     = "us-central1"
$BUCKET     = "$PROJECT_ID-tfstate"
$TF_SA      = "sa-tf-provisioner@$PROJECT_ID.iam.gserviceaccount.com"
$ME         = gcloud config get-value account
```

## 2. gcloud configuration and project
```powershell
gcloud config configurations create crypto-dev
gcloud auth login
gcloud projects create $PROJECT_ID --name="Crypto DE Platform Dev"
gcloud config set project $PROJECT_ID
gcloud billing projects link $PROJECT_ID --billing-account=<BILLING_ACCOUNT_ID>
```
Budget (console): `crypto-dev-monthly`, ₹2,000/month, project-scoped, all credits excluded,
alerts at 50/90/100%.

## 3. Bootstrap APIs
```powershell
gcloud services enable iam.googleapis.com iamcredentials.googleapis.com cloudresourcemanager.googleapis.com serviceusage.googleapis.com storage.googleapis.com --project=$PROJECT_ID
```

## 4. Terraform state bucket (uniform access, no public access, versioned)
```powershell
gcloud storage buckets create "gs://$BUCKET" --project=$PROJECT_ID --location=$REGION --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update "gs://$BUCKET" --versioning
```

## 5. Terraform service account and its Phase 4 roles
```powershell
gcloud iam service-accounts create sa-tf-provisioner --display-name="Terraform provisioner" --project=$PROJECT_ID
$roles = @("roles/serviceusage.serviceUsageAdmin","roles/iam.serviceAccountAdmin","roles/resourcemanager.projectIamAdmin","roles/storage.admin","roles/pubsub.admin","roles/bigquery.admin","roles/secretmanager.admin")
foreach ($r in $roles) { gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$TF_SA" --role=$r --condition=None --quiet }
```

## 6. Allow me to impersonate it (Token Creator on the SA only)
```powershell
gcloud iam service-accounts add-iam-policy-binding $TF_SA --member="user:$ME" --role="roles/iam.serviceAccountTokenCreator" --project=$PROJECT_ID
```

## 7. Verify and set up local ADC via impersonation (ADR-0003)
```powershell
gcloud storage ls "gs://$BUCKET" --impersonate-service-account=$TF_SA
gcloud auth application-default login --impersonate-service-account $TF_SA
```
Expected ADC type: `impersonated_service_account`.

## 8. you (gcloud CLI login, project Owner), changing the provisioner’s permissions
```powershell
gcloud projects add-iam-policy-binding crypto-de-dev-4821 --member="serviceAccount:sa-tf-provisioner@crypto-de-dev-4821.iam.gserviceaccount.com" --role="roles/artifactregistry.admin" --condition=None --quiet
```

## 9. Phase 6 addition
```powershell
gcloud iam service-accounts add-iam-policy-binding sa-pubsub-bq-writer@crypto-de-dev-4821.iam.gserviceaccount.com --member="serviceAccount:sa-tf-provisioner@crypto-de-dev-4821.iam.gserviceaccount.com" --role="roles/iam.serviceAccountUser" --project=crypto-de-dev-4821
gcloud iam service-accounts add-iam-policy-binding sa-pubsub-gcs-writer@crypto-de-dev-4821.iam.gserviceaccount.com --member="serviceAccount:sa-tf-provisioner@crypto-de-dev-4821.iam.gserviceaccount.com" --role="roles/iam.serviceAccountUser" --project=crypto-de-dev-4821
```

## Security notes
- No service-account keys exist. Never create one.
- sa-tf-provisioner holds project-level admin roles (it must create resources), so only
  the admin (and later CI) may impersonate it.

