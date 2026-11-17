# Phase 12 Part 2: DQ failures as a metric, plus a pipeline-health dashboard (all as code).
# The dashboard JSON is written the way the Monitoring API stores it (targetAxis set, zero
# positions omitted); otherwise every plan shows a false "1 to change".

# Turns dq-runner FAIL log lines into a number per check (counting starts when this is created).
resource "google_logging_metric" "dq_check_failures" {
  name        = "dq_check_failures"
  description = "dq-runner blocking check failures, labelled by check_name"
  filter      = "resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"dq-runner\" AND severity>=ERROR AND jsonPayload.check_name:*"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    labels {
      key        = "check_name"
      value_type = "STRING"
    }
  }

  label_extractors = {
    check_name = "EXTRACT(jsonPayload.check_name)"
  }
}

locals {
  wf_filter = "resource.type = \"workflows.googleapis.com/Workflow\" AND resource.label.workflow_id = \"elt-pipeline\""
}

resource "google_monitoring_dashboard" "pipeline_health" {
  dashboard_json = jsonencode({
    displayName = "Pipeline health"
    mosaicLayout = {
      columns = 48
      tiles = [
        {
          width  = 24
          height = 16
          widget = {
            title = "elt-pipeline runs by status (per 30 min)"
            xyChart = {
              dataSets = [{
                plotType   = "STACKED_BAR"
                targetAxis = "Y1"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "${local.wf_filter} AND metric.type = \"workflows.googleapis.com/finished_execution_count\""
                    aggregation = {
                      alignmentPeriod    = "1800s"
                      perSeriesAligner   = "ALIGN_SUM"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["metric.label.status"]
                    }
                  }
                }
              }]
            }
          }
        },
        {
          xPos   = 24
          width  = 24
          height = 16
          widget = {
            title = "elt-pipeline run duration (p50, p95)"
            xyChart = {
              dataSets = [
                {
                  plotType       = "LINE"
                  targetAxis     = "Y1"
                  legendTemplate = "p50"
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "${local.wf_filter} AND metric.type = \"workflows.googleapis.com/execution_times\""
                      aggregation = {
                        alignmentPeriod  = "1800s"
                        perSeriesAligner = "ALIGN_PERCENTILE_50"
                      }
                    }
                  }
                },
                {
                  plotType       = "LINE"
                  targetAxis     = "Y1"
                  legendTemplate = "p95"
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "${local.wf_filter} AND metric.type = \"workflows.googleapis.com/execution_times\""
                      aggregation = {
                        alignmentPeriod  = "1800s"
                        perSeriesAligner = "ALIGN_PERCENTILE_95"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          yPos   = 16
          width  = 24
          height = 16
          widget = {
            title = "DQ check failures by check (per 30 min)"
            xyChart = {
              dataSets = [{
                plotType   = "STACKED_BAR"
                targetAxis = "Y1"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type = \"logging.googleapis.com/user/${google_logging_metric.dq_check_failures.name}\""
                    aggregation = {
                      alignmentPeriod    = "1800s"
                      perSeriesAligner   = "ALIGN_SUM"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["metric.label.check_name"]
                    }
                  }
                }
              }]
            }
          }
        },
        {
          xPos   = 24
          yPos   = 16
          width  = 24
          height = 16
          widget = {
            title = "Recent ERROR logs from Cloud Run jobs"
            logsPanel = {
              filter = "resource.type=\"cloud_run_job\" AND severity>=ERROR"
            }
          }
        }
      ]
    }
  })
}
