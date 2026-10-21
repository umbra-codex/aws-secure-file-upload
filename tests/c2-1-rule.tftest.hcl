# C2 step 1: modules/scanning/rule.tf, the scan-result rule.
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

run "scan_result_rule" {
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

  assert {
    condition     = aws_cloudwatch_event_rule.scan_result.name == "demo-scan-result"
    error_message = "aws_cloudwatch_event_rule.scan_result must be named <project_name>-scan-result (got ${aws_cloudwatch_event_rule.scan_result.name})."
  }

  assert {
    condition     = coalesce(aws_cloudwatch_event_rule.scan_result.event_bus_name, "default") == "default"
    error_message = "aws_cloudwatch_event_rule.scan_result must not set event_bus_name: GuardDuty publishes to the default bus, and a rule on another bus never sees its events (got ${coalesce(aws_cloudwatch_event_rule.scan_result.event_bus_name, "default")})."
  }

  assert {
    condition     = length(trimspace(try(aws_cloudwatch_event_rule.scan_result.description, ""))) > 0
    error_message = "aws_cloudwatch_event_rule.scan_result needs a description: a short sentence saying what the rule catches."
  }

  assert {
    condition = (
      can(jsondecode(aws_cloudwatch_event_rule.scan_result.event_pattern)) &&
      toset(keys(jsondecode(aws_cloudwatch_event_rule.scan_result.event_pattern))) == toset(["source", "detail-type"]) &&
      jsondecode(aws_cloudwatch_event_rule.scan_result.event_pattern)["source"] == ["aws.guardduty"] &&
      jsondecode(aws_cloudwatch_event_rule.scan_result.event_pattern)["detail-type"] == ["GuardDuty Malware Protection Object Scan Result"]
    )
    error_message = "The event_pattern must have exactly two keys: source = [\"aws.guardduty\"] and detail-type = [\"GuardDuty Malware Protection Object Scan Result\"], with no result filter (got ${try(aws_cloudwatch_event_rule.scan_result.event_pattern, "nothing")})."
  }

  assert {
    condition     = lookup(aws_cloudwatch_event_rule.scan_result.tags, "Name", "") == "demo-scan-result" && lookup(aws_cloudwatch_event_rule.scan_result.tags, "Role", "") == "scan-rule" && lookup(aws_cloudwatch_event_rule.scan_result.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_cloudwatch_event_rule.scan_result needs tags Name = \"demo-scan-result\", Role = \"scan-rule\", ManagedBy = \"terraform\" (got ${jsonencode(aws_cloudwatch_event_rule.scan_result.tags)})."
  }
}
