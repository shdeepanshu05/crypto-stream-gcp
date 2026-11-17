# Phase 12: alerting. Email to the project owner (address comes from tfvars, never committed).
resource "google_monitoring_notification_channel" "owner_email" {
  display_name = "Project owner email"
  type         = "email"
  labels = {
    email_address = var.admin_email
  }
}

resource "google_monitoring_alert_policy" "elt_pipeline_failed" {
  display_name = "elt-pipeline execution failed"
  combiner     = "OR"
  severity     = "CRITICAL" # the whole pipeline stopped

  conditions {
    display_name = "finished_execution_count with status FAILED > 0"
    condition_threshold {
      filter          = "resource.type = \"workflows.googleapis.com/Workflow\" AND metric.type = \"workflows.googleapis.com/finished_execution_count\" AND metric.labels.status = \"FAILED\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  notification_channels = [google_monitoring_notification_channel.owner_email.id]

  documentation {
    mime_type = "text/markdown"
    content   = "elt-pipeline failed. Run `gcloud workflows executions list elt-pipeline --location=us-central1` and describe the FAILED execution; its `error:` names the failing step. DQ failures: check ops.dq_results."
  }
}

# Alert 2: any Cloud Run job (publishers, dq-runner) logged an ERROR.
resource "google_monitoring_alert_policy" "cloud_run_job_errors" {
  display_name = "Cloud Run job logged an ERROR"
  combiner     = "OR"
  severity     = "ERROR" # one job failed; the email says which


  conditions {
    display_name = "severity >= ERROR in a Cloud Run job"
    condition_matched_log {
      filter = "resource.type=\"cloud_run_job\" AND severity>=ERROR"
      label_extractors = {
        job_name = "EXTRACT(resource.labels.job_name)"
      }
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "300s" # at most one email per 5 minutes per incident
    }
    auto_close = "1800s"
  }

  notification_channels = [google_monitoring_notification_channel.owner_email.id]

  documentation {
    mime_type = "text/markdown"
    content   = "A Cloud Run job logged an ERROR. The job_name label says which. For dq-runner, the log line's jsonPayload.check_name and details say which check failed."
  }
}
