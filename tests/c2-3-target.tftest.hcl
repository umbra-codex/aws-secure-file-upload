# C2 step 3: modules/scanning/target.tf, the rule's target and the Lambda permission.
# Brief: docs/milestones/C2.md

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "210987654321"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
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

run "router_target" {
  module {
    source = "./modules/scanning"
  }

  variables {
    project_name         = "demo"
    incoming_bucket_name = "demo-incoming-210987654321"
    incoming_bucket_arn  = "arn:aws:s3:::demo-incoming-210987654321"
    router_lambda_arn    = "arn:aws:lambda:us-east-1:210987654321:function:demo-router"
    alert_email          = "alerts@example.com"
  }

  # The mock gives every resource of a type the same values. Pin distinct ones
  # so a reference to the wrong resource or attribute fails.
  override_resource {
    target = aws_sqs_queue.dlq
    values = {
      id  = "https://sqs.us-east-1.amazonaws.com/210987654321/demo-scan-dlq"
      arn = "arn:aws:sqs:us-east-1:210987654321:demo-scan-dlq"
      url = "https://sqs.us-east-1.amazonaws.com/210987654321/demo-scan-dlq"
    }
  }

  override_resource {
    target = aws_cloudwatch_event_rule.scan_result
    values = {
      arn = "arn:aws:events:us-east-1:210987654321:rule/demo-scan-result"
    }
  }

  assert {
    condition     = aws_cloudwatch_event_target.router.rule == "demo-scan-result" && aws_cloudwatch_event_target.router.arn == "arn:aws:lambda:us-east-1:210987654321:function:demo-router"
    error_message = "aws_cloudwatch_event_target.router must set rule to the scan-result rule's name and arn to the router_lambda_arn variable (got ${aws_cloudwatch_event_target.router.rule}, ${aws_cloudwatch_event_target.router.arn})."
  }

  assert {
    condition = (
      length(aws_cloudwatch_event_target.router.retry_policy) == 1 &&
      aws_cloudwatch_event_target.router.retry_policy[0].maximum_retry_attempts == 2 &&
      aws_cloudwatch_event_target.router.retry_policy[0].maximum_event_age_in_seconds == 300
    )
    error_message = "aws_cloudwatch_event_target.router needs one retry_policy block with maximum_retry_attempts = 2 and maximum_event_age_in_seconds = 300 (got ${jsonencode(aws_cloudwatch_event_target.router.retry_policy)})."
  }

  assert {
    condition = (
      length(aws_cloudwatch_event_target.router.dead_letter_config) == 1 &&
      aws_cloudwatch_event_target.router.dead_letter_config[0].arn == "arn:aws:sqs:us-east-1:210987654321:demo-scan-dlq"
    )
    error_message = "aws_cloudwatch_event_target.router needs one dead_letter_config block whose arn is the DLQ's arn (got ${jsonencode(aws_cloudwatch_event_target.router.dead_letter_config)})."
  }

  assert {
    condition = (
      aws_lambda_permission.scan_rule.statement_id == "AllowScanRule" &&
      aws_lambda_permission.scan_rule.action == "lambda:InvokeFunction" &&
      aws_lambda_permission.scan_rule.function_name == "arn:aws:lambda:us-east-1:210987654321:function:demo-router" &&
      aws_lambda_permission.scan_rule.principal == "events.amazonaws.com" &&
      aws_lambda_permission.scan_rule.source_arn == "arn:aws:events:us-east-1:210987654321:rule/demo-scan-result"
    )
    error_message = "aws_lambda_permission.scan_rule needs statement_id = \"AllowScanRule\", action = \"lambda:InvokeFunction\", function_name = the router_lambda_arn variable, principal = \"events.amazonaws.com\", and source_arn = the scan-result rule's arn (not the function's)."
  }
}
