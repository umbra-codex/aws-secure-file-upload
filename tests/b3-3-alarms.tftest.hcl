# B3 step 3: modules/upload_api/alarms.tf, Lambda error alarms.
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
}

run "error_alarms" {
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

  assert {
    condition = (
      length(trimspace(try(aws_cloudwatch_metric_alarm.upload_url_errors.alarm_description, ""))) > 0 &&
      aws_cloudwatch_metric_alarm.upload_url_errors.alarm_name == "demo-upload-url-errors" &&
      aws_cloudwatch_metric_alarm.upload_url_errors.namespace == "AWS/Lambda" &&
      aws_cloudwatch_metric_alarm.upload_url_errors.metric_name == "Errors" &&
      aws_cloudwatch_metric_alarm.upload_url_errors.dimensions == tomap({ FunctionName = "demo-upload-url" }) &&
      aws_cloudwatch_metric_alarm.upload_url_errors.statistic == "Sum" &&
      aws_cloudwatch_metric_alarm.upload_url_errors.period == 60 &&
      aws_cloudwatch_metric_alarm.upload_url_errors.evaluation_periods == 1 &&
      aws_cloudwatch_metric_alarm.upload_url_errors.threshold == 1 &&
      aws_cloudwatch_metric_alarm.upload_url_errors.comparison_operator == "GreaterThanOrEqualToThreshold" &&
      aws_cloudwatch_metric_alarm.upload_url_errors.treat_missing_data == "notBreaching"
    )
    error_message = "aws_cloudwatch_metric_alarm.upload_url_errors must be named demo-upload-url-errors and watch AWS/Lambda Errors for FunctionName demo-upload-url: Sum over 60 seconds, 1 evaluation period, GreaterThanOrEqualToThreshold 1, treat_missing_data notBreaching, and an alarm_description (got ${jsonencode(aws_cloudwatch_metric_alarm.upload_url_errors.dimensions)})."
  }

  assert {
    condition     = lookup(aws_cloudwatch_metric_alarm.upload_url_errors.tags, "Name", "") == "demo-upload-url-errors" && lookup(aws_cloudwatch_metric_alarm.upload_url_errors.tags, "Role", "") == "observability" && lookup(aws_cloudwatch_metric_alarm.upload_url_errors.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_cloudwatch_metric_alarm.upload_url_errors needs tags Name = \"demo-upload-url-errors\", Role = \"observability\", ManagedBy = \"terraform\" (got ${jsonencode(aws_cloudwatch_metric_alarm.upload_url_errors.tags)})."
  }

  assert {
    condition = (
      length(trimspace(try(aws_cloudwatch_metric_alarm.router_errors.alarm_description, ""))) > 0 &&
      aws_cloudwatch_metric_alarm.router_errors.alarm_name == "demo-router-errors" &&
      aws_cloudwatch_metric_alarm.router_errors.namespace == "AWS/Lambda" &&
      aws_cloudwatch_metric_alarm.router_errors.metric_name == "Errors" &&
      aws_cloudwatch_metric_alarm.router_errors.dimensions == tomap({ FunctionName = "demo-router" }) &&
      aws_cloudwatch_metric_alarm.router_errors.statistic == "Sum" &&
      aws_cloudwatch_metric_alarm.router_errors.period == 60 &&
      aws_cloudwatch_metric_alarm.router_errors.evaluation_periods == 1 &&
      aws_cloudwatch_metric_alarm.router_errors.threshold == 1 &&
      aws_cloudwatch_metric_alarm.router_errors.comparison_operator == "GreaterThanOrEqualToThreshold" &&
      aws_cloudwatch_metric_alarm.router_errors.treat_missing_data == "notBreaching"
    )
    error_message = "aws_cloudwatch_metric_alarm.router_errors must be named demo-router-errors and watch AWS/Lambda Errors for FunctionName demo-router: Sum over 60 seconds, 1 evaluation period, GreaterThanOrEqualToThreshold 1, treat_missing_data notBreaching, and an alarm_description (got ${jsonencode(aws_cloudwatch_metric_alarm.router_errors.dimensions)})."
  }

  assert {
    condition     = lookup(aws_cloudwatch_metric_alarm.router_errors.tags, "Name", "") == "demo-router-errors" && lookup(aws_cloudwatch_metric_alarm.router_errors.tags, "Role", "") == "observability" && lookup(aws_cloudwatch_metric_alarm.router_errors.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_cloudwatch_metric_alarm.router_errors needs tags Name = \"demo-router-errors\", Role = \"observability\", ManagedBy = \"terraform\" (got ${jsonencode(aws_cloudwatch_metric_alarm.router_errors.tags)})."
  }
}
