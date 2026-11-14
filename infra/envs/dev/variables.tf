variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Default region for resources"
  type        = string
  default     = "us-central1"
}

variable "admin_email" {
  description = "Human admin allowed to impersonate workload SAs for local testing"
  type        = string
}