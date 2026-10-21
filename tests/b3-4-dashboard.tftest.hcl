# B3 step 4: modules/upload_api/dashboard.tf, the pipeline dashboard.
# Brief: docs/milestones/B3.md

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "210987654321"
    }
  }

  # A3 adds bucket policies built from this data source. The mock would fake
  # its JSON with random text, which the bucket policy rejects.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # Resources other resources validate as ARNs or URLs. The mock would invent
  # random strings, so give every resource of these types a well-formed value.
  # (mock_resource needs no target, so this is safe before they exist.)
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::210987654321:role/mock-role"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn        = "arn:aws:lambda:us-east-1:210987654321:function:mock-function"
      invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:210987654321:function:mock-function/invocations"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:210987654321:log-group:mock"
    }
  }

  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      arn           = "arn:aws:apigateway:us-east-1::/apis/mock-api"
      execution_arn = "arn:aws:execute-api:us-east-1:210987654321:mock-api"
      api_endpoint  = "https://mock-api.execute-api.us-east-1.amazonaws.com"
    }
  }

  mock_resource "aws_apigatewayv2_stage" {
    defaults = {
      arn           = "arn:aws:apigateway:us-east-1::/apis/mock-api/stages/$default"
      execution_arn = "arn:aws:execute-api:us-east-1:210987654321:mock-api/$default"
      invoke_url    = "https://mock-api.execute-api.us-east-1.amazonaws.com/"
    }
  }

  # The dashboard's widgets need the region as a plain string.
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
}

run "dashboard" {
  module {
    source = "./modules/upload_api"
  }

  variables {
    project_name               = "demo"
    incoming_bucket_name       = "demo-incoming-210987654321"
    incoming_bucket_arn        = "arn:aws:s3:::demo-incoming-210987654321"
    table_name                 = "demo-uploads"
    table_arn                  = "arn:aws:dynamodb:us-east-1:210987654321:table/demo-uploads"
    allowed_types              = ["image/png", "application/pdf"]
    max_size_mb                = 25
    router_function_name       = "demo-router"
    dlq_name                   = "demo-scan-dlq"
    router_failures_queue_name = "demo-router-failures"
    cors_allowed_origins       = ["http://localhost:3000", "https://app.example.com"]
  }

  # The mock gives every resource of a type the same values. Pin distinct ones
  # so a reference to the wrong resource or attribute fails.
  override_resource {
    target = aws_apigatewayv2_api.this
    values = {
      id            = "demo-api-id"
      arn           = "arn:aws:apigateway:us-east-1::/apis/demo-api-id"
      execution_arn = "arn:aws:execute-api:us-east-1:210987654321:demo-api-id"
    }
  }

  assert {
    condition     = aws_cloudwatch_dashboard.pipeline.dashboard_name == "demo-pipeline"
    error_message = "aws_cloudwatch_dashboard.pipeline must be named <project_name>-pipeline (got ${aws_cloudwatch_dashboard.pipeline.dashboard_name})."
  }

  assert {
    condition     = can(jsondecode(aws_cloudwatch_dashboard.pipeline.dashboard_body).widgets) && length(jsondecode(aws_cloudwatch_dashboard.pipeline.dashboard_body).widgets) == 5
    error_message = "dashboard_body must be built with jsonencode and hold a widgets list of exactly five widgets."
  }

  assert {
    condition = can(jsondecode(aws_cloudwatch_dashboard.pipeline.dashboard_body).widgets) && alltrue([
      for w in jsondecode(aws_cloudwatch_dashboard.pipeline.dashboard_body).widgets :
      w.type == "metric" && try(w.properties.region, "") == "us-east-1" && length(try(w.properties.title, "")) > 0
    ])
    error_message = "Every widget must be type \"metric\" with a title and properties.region = the region from data.aws_region.current."
  }

  assert {
    condition = can(jsondecode(aws_cloudwatch_dashboard.pipeline.dashboard_body).widgets) && alltrue([
      for w in jsondecode(aws_cloudwatch_dashboard.pipeline.dashboard_body).widgets :
      try(w.width, 0) == 12 && try(w.height, 0) == 6 && try(
        {
          "GuardDuty scan results" = [0, 0, "Sum", 300]
          "Lambda errors"          = [12, 0, "Sum", 60]
          "Lambda duration"        = [0, 6, "Average", 60]
          "Failure queue depth"    = [12, 6, "Maximum", 60]
          "API errors"             = [0, 12, "Sum", 60]
        }[w.properties.title] == [w.x, w.y, w.properties.stat, w.properties.period],
        false
      )
    ])
    error_message = "Each widget needs width 12, height 6, and the title, x, y, stat, and period from the brief's table (titles must match exactly)."
  }

  assert {
    condition = alltrue([
      for s in [
        "AWS/GuardDuty/MalwareProtection", "CompletedScanCount", "InfectedScanCount", "SkippedScanCount", "FailedScanCount",
        "\"Errors\"", "\"Duration\"", "\"demo-upload-url\"", "\"demo-router\"",
        "ApproximateNumberOfMessagesVisible", "\"demo-scan-dlq\"", "\"demo-router-failures\"",
        "\"4xx\"", "\"5xx\"", "\"demo-api-id\"",
      ] : strcontains(aws_cloudwatch_dashboard.pipeline.dashboard_body, s)
    ])
    error_message = "The dashboard is missing a metric. It needs GuardDuty's four scan counts, Errors and Duration for Lambda 1 (its function_name) and the router (router_function_name), ApproximateNumberOfMessagesVisible for dlq_name and router_failures_queue_name, and 4xx and 5xx for the API's id."
  }
}
