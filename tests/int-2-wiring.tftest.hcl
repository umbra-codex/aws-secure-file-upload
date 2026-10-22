# INT step 2: no module output is still a placeholder. Nothing to build here:
# it turns green when every portion has replaced its placeholders.

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

  # Later milestones add roles, functions, and log groups whose ARNs other
  # resources validate. The mock would invent random strings, so give every
  # resource of these types a well-formed ARN. (mock_resource needs no target,
  # so this is safe before those resources exist.)
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

  # C adds a rule, a queue, and a topic whose ARNs and URLs other resources
  # validate. Give every resource of these types a well-formed value.
  mock_resource "aws_cloudwatch_event_rule" {
    defaults = {
      arn = "arn:aws:events:us-east-1:210987654321:rule/mock-rule"
    }
  }

  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:us-east-1:210987654321:mock-queue"
      url = "https://sqs.us-east-1.amazonaws.com/210987654321/mock-queue"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:210987654321:mock-topic"
    }
  }
}

run "no_placeholder_left" {
  variables {
    project_name = "demo"
    owner        = "tester"
    alert_email  = "alerts@example.com"
  }

  assert {
    condition = length([
      for name, value in {
        "storage.incoming_bucket_name"          = module.storage.incoming_bucket_name,
        "storage.incoming_bucket_arn"           = module.storage.incoming_bucket_arn,
        "storage.approved_bucket_name"          = module.storage.approved_bucket_name,
        "storage.approved_bucket_arn"           = module.storage.approved_bucket_arn,
        "storage.quarantine_bucket_name"        = module.storage.quarantine_bucket_name,
        "storage.quarantine_bucket_arn"         = module.storage.quarantine_bucket_arn,
        "storage.table_name"                    = module.storage.table_name,
        "storage.table_arn"                     = module.storage.table_arn,
        "upload_api.api_url"                    = module.upload_api.api_url,
        "upload_api.api_id"                     = module.upload_api.api_id,
        "upload_api.api_execution_arn"          = module.upload_api.api_execution_arn,
        "upload_api.upload_role_arn"            = module.upload_api.upload_role_arn,
        "upload_api.upload_function_name"       = module.upload_api.upload_function_name,
        "upload_api.dashboard_name"             = module.upload_api.dashboard_name,
        "upload_api.alarm_names"                = module.upload_api.alarm_names,
        "scanning.guardduty_role_arn"           = module.scanning.guardduty_role_arn,
        "scanning.guardduty_plan_id"            = module.scanning.guardduty_plan_id,
        "scanning.scan_rule_arn"                = module.scanning.scan_rule_arn,
        "scanning.dlq_arn"                      = module.scanning.dlq_arn,
        "scanning.dlq_name"                     = module.scanning.dlq_name,
        "scanning.alerts_topic_arn"             = module.scanning.alerts_topic_arn,
        "scanning.alert_rule_name"              = module.scanning.alert_rule_name,
        "scanning.alarm_names"                  = module.scanning.alarm_names,
        "processing.router_lambda_arn"          = module.processing.router_lambda_arn,
        "processing.router_function_name"       = module.processing.router_function_name,
        "processing.router_role_arn"            = module.processing.router_role_arn,
        "processing.router_failures_queue_name" = module.processing.router_failures_queue_name,
        "processing.router_failures_queue_url"  = module.processing.router_failures_queue_url,
        "status.status_role_arn"                = module.status.status_role_arn,
        "status.status_function_name"           = module.status.status_function_name,
        "status.status_route_key"               = module.status.status_route_key
      } : name if strcontains(jsonencode(value), "placeholder")
    ]) == 0
    error_message = "These module outputs still hold a placeholder, so the milestone that owns them is not finished: ${jsonencode([
      for name, value in {
        "storage.incoming_bucket_name"          = module.storage.incoming_bucket_name,
        "storage.incoming_bucket_arn"           = module.storage.incoming_bucket_arn,
        "storage.approved_bucket_name"          = module.storage.approved_bucket_name,
        "storage.approved_bucket_arn"           = module.storage.approved_bucket_arn,
        "storage.quarantine_bucket_name"        = module.storage.quarantine_bucket_name,
        "storage.quarantine_bucket_arn"         = module.storage.quarantine_bucket_arn,
        "storage.table_name"                    = module.storage.table_name,
        "storage.table_arn"                     = module.storage.table_arn,
        "upload_api.api_url"                    = module.upload_api.api_url,
        "upload_api.api_id"                     = module.upload_api.api_id,
        "upload_api.api_execution_arn"          = module.upload_api.api_execution_arn,
        "upload_api.upload_role_arn"            = module.upload_api.upload_role_arn,
        "upload_api.upload_function_name"       = module.upload_api.upload_function_name,
        "upload_api.dashboard_name"             = module.upload_api.dashboard_name,
        "upload_api.alarm_names"                = module.upload_api.alarm_names,
        "scanning.guardduty_role_arn"           = module.scanning.guardduty_role_arn,
        "scanning.guardduty_plan_id"            = module.scanning.guardduty_plan_id,
        "scanning.scan_rule_arn"                = module.scanning.scan_rule_arn,
        "scanning.dlq_arn"                      = module.scanning.dlq_arn,
        "scanning.dlq_name"                     = module.scanning.dlq_name,
        "scanning.alerts_topic_arn"             = module.scanning.alerts_topic_arn,
        "scanning.alert_rule_name"              = module.scanning.alert_rule_name,
        "scanning.alarm_names"                  = module.scanning.alarm_names,
        "processing.router_lambda_arn"          = module.processing.router_lambda_arn,
        "processing.router_function_name"       = module.processing.router_function_name,
        "processing.router_role_arn"            = module.processing.router_role_arn,
        "processing.router_failures_queue_name" = module.processing.router_failures_queue_name,
        "processing.router_failures_queue_url"  = module.processing.router_failures_queue_url,
        "status.status_role_arn"                = module.status.status_role_arn,
        "status.status_function_name"           = module.status.status_function_name,
        "status.status_route_key"               = module.status.status_route_key
      } : name if strcontains(jsonencode(value), "placeholder")
    ])}"
  }
}
