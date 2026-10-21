# C3 step 1: modules/scanning/alert_rule.tf, the alert rule.
# Brief: docs/milestones/C3.md

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

run "alert_rule" {
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
    condition     = aws_cloudwatch_event_rule.alerts.name == "demo-alerts"
    error_message = "aws_cloudwatch_event_rule.alerts must be named <project_name>-alerts (got ${aws_cloudwatch_event_rule.alerts.name})."
  }

  assert {
    condition     = coalesce(aws_cloudwatch_event_rule.alerts.event_bus_name, "default") == "default"
    error_message = "aws_cloudwatch_event_rule.alerts must not set event_bus_name: GuardDuty publishes to the default bus, and a rule on another bus never sees its events (got ${coalesce(aws_cloudwatch_event_rule.alerts.event_bus_name, "default")})."
  }

  assert {
    condition     = length(trimspace(try(aws_cloudwatch_event_rule.alerts.description, ""))) > 0
    error_message = "aws_cloudwatch_event_rule.alerts needs a description: a short sentence saying what the rule catches."
  }

  assert {
    condition = (
      can(jsondecode(aws_cloudwatch_event_rule.alerts.event_pattern)) &&
      toset(keys(jsondecode(aws_cloudwatch_event_rule.alerts.event_pattern))) == toset(["source", "detail-type", "detail"]) &&
      jsondecode(aws_cloudwatch_event_rule.alerts.event_pattern)["source"] == ["aws.guardduty"] &&
      toset(jsondecode(aws_cloudwatch_event_rule.alerts.event_pattern)["detail-type"]) == toset(["GuardDuty Malware Protection Object Scan Result", "GuardDuty Malware Protection Resource Status Error"])
    )
    error_message = "The event_pattern needs exactly three keys: source = [\"aws.guardduty\"]; detail-type listing both \"GuardDuty Malware Protection Object Scan Result\" and \"GuardDuty Malware Protection Resource Status Error\"; and detail (got ${try(aws_cloudwatch_event_rule.alerts.event_pattern, "nothing")})."
  }

  assert {
    condition = (
      can(jsondecode(aws_cloudwatch_event_rule.alerts.event_pattern)["detail"]) &&
      toset(keys(jsondecode(aws_cloudwatch_event_rule.alerts.event_pattern)["detail"])) == toset(["$or"]) &&
      length(jsondecode(aws_cloudwatch_event_rule.alerts.event_pattern)["detail"]["$or"]) == 2
    )
    error_message = "The pattern's detail must hold only a \"$or\" key, a list of exactly two conditions (got ${try(jsonencode(jsondecode(aws_cloudwatch_event_rule.alerts.event_pattern)["detail"]), "nothing")})."
  }

  assert {
    condition = (
      can(jsondecode(aws_cloudwatch_event_rule.alerts.event_pattern)["detail"]["$or"]) &&
      length([for o in jsondecode(aws_cloudwatch_event_rule.alerts.event_pattern)["detail"]["$or"] : o if try(o.scanResultDetails.scanResultStatus == ["THREATS_FOUND"] && length(keys(o)) == 1 && length(keys(o.scanResultDetails)) == 1, false)]) == 1
    )
    error_message = "One \"$or\" condition must be exactly scanResultDetails > scanResultStatus = [\"THREATS_FOUND\"] (no other statuses, no other keys)."
  }

  assert {
    condition = (
      can(jsondecode(aws_cloudwatch_event_rule.alerts.event_pattern)["detail"]["$or"]) &&
      length([for o in jsondecode(aws_cloudwatch_event_rule.alerts.event_pattern)["detail"]["$or"] : o if try(o.resourceStatus == ["ERROR"] && length(keys(o)) == 1, false)]) == 1
    )
    error_message = "The other \"$or\" condition must be exactly resourceStatus = [\"ERROR\"] (no other keys)."
  }

  assert {
    condition     = lookup(aws_cloudwatch_event_rule.alerts.tags, "Name", "") == "demo-alerts" && lookup(aws_cloudwatch_event_rule.alerts.tags, "Role", "") == "alerts" && lookup(aws_cloudwatch_event_rule.alerts.tags, "ManagedBy", "") == "terraform"
    error_message = "aws_cloudwatch_event_rule.alerts needs tags Name = \"demo-alerts\", Role = \"alerts\", ManagedBy = \"terraform\" (got ${jsonencode(aws_cloudwatch_event_rule.alerts.tags)})."
  }
}
